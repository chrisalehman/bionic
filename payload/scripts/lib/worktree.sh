#!/bin/bash
# worktree.sh — the worktree LEASE (bionic 1.4.0, spec AC-11/AC-28; design
# ledger C1 "worktree lease", C2 ".bionic symlink retired").
#
# WHAT THIS FILE OWNS. A spawned worktree is a leased slot, bound to the ledger
# row that dispatched its writer. A row lands through the landing line
# (lib/line.sh: `ready` and the hand landing), which judges the tree with this
# file's checks (`_wt_land_checks`, `_wt_busy_suite`) and removes it after the
# publish (`_wt_hand_remove`, `worktree_remove_landed`). The Patrol tick is a READER here and never a caller of the
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

# shellcheck source=/dev/null
declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac
# roots.sh, THE SOFT SOURCE — the idiom this file already uses for git-argv.sh, taken at
# source time because two of this file's roots are wanted on every path through it. Every
# root resolver in the tree has one definition there (epic-22 wave-01, N1); this file is a
# caller of `worktree_root` (three copies before N1: here as `_wt_main_root`, lib/patrol.sh,
# spawn-worktree.sh). `claude_home` is only the probe for "already loaded": D1 read session
# files through it until wave-20 T8c, and reads processes now.
bionic_need roots.sh claude_home
bionic_need fields.sh line_field_v

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
  bionic_need git-argv.sh git_branch_protected || return 2
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
# A RUN THE GATE ADMITTED (wave-28 T12; D10). Every suite asks the machine's one gate before it
# runs (payload/scripts/booked.sh for a Bash call, tests/run.sh for each suite of a run), and the
# request records the tree it runs in (`tree=`, git's toplevel where it asked, or the shim's
# --stamp-dir). So the land refuses while a request that is ADMITTED, NOT ENDED and whose holder
# is ALIVE (lib/slots.sh's rule, `_slots_live`) names the project's main checkout or the land's
# TARGET checkout as its tree. A request in a writer's own tree does not refuse: counting a
# writer's suite in its own tree would refuse every land of a wave while any writer tests (the
# reason the walk below counts only the runner). The store is the gate's (`gate_dir` in
# lib/gate.sh, spelled here so this library does not load the gate's verbs); a store that is
# absent or cannot be read gives no opinion.
#
# AND, AS BEFORE THE GATE, A RUNNER PROCESS (wave-20 T8c; review R2-1, R2-8; critic C2-1): a run
# that never asked (a runner on a tree without the gate library, an older bionic) is still
# found by its process.
#
# A FACT ABOUT PROCESSES AND DIRECTORIES. The walk refuses while a `tests/run.sh` process has
# its SCRIPT PATH or its WORKING DIRECTORY inside the project root (every linked worktree under
# it included) or inside the land's target checkout. Nothing else is read.
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

# THE RUNNER'S OWN SCRIPT, from its command line as `ps` prints it, one word per argument.
# A process IS the runner only when it runs the script: argv[0] ends in `tests/run.sh`, or
# argv[0] is an interpreter and its first word past the options does. A `-c` (or `-s`)
# among those options means the words that follow are a command string or positional
# arguments, never a script, so a shell whose command text merely MENTIONS the runner — the
# harness wraps every Bash call in `zsh -c '…'`, wait loops and progress notes included — is
# not one (T31). Prints the script word and returns 0, or returns 1.
#
# The options are walked as bash reads them (review 7 F7): a `-` or `+` cluster is one word,
# and EACH `o` or `O` in it takes the next word as its argument, so `-euo pipefail` and
# `-oo pipefail errexit` skip theirs. A `c` or `s` anywhere in a cluster, `+c` included, makes
# it a command string or stdin. `-` and `--` end the options; of the long ones only
# `--rcfile` and `--init-file` take an argument. zsh reads these forms the same way.
_wt_runner_script() {  # <argv word>...
  local takes
  case "${1:-}" in *tests/run.sh) printf '%s' "$1"; return 0 ;; esac
  [ "$#" -gt 1 ] || return 1
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -|--) shift; break ;;
      --rcfile|--init-file) shift 2 || return 1 ;;
      --*) shift ;;
      [-+]*[cs]*) return 1 ;;
      [-+]*) takes="${1//[!oO]/}"; shift $((1 + ${#takes})) || return 1 ;;
      *) break ;;
    esac
  done
  case "${1:-}" in *tests/run.sh) printf '%s' "$1"; return 0 ;; esac
  return 1
}

# _wt_busy_request <main-root> [target-checkout] — the gate's half of D1. Prints
# `request=<id> key=<key> tree=<tree> holder=<pid>` for the first admitted, unended request with a
# live holder whose tree is the main checkout or the target checkout, in the store's listing
# order, and returns 0; returns 1 when none is.
_wt_busy_request() {
  local root="${1:-}" co="${2:-}" store f id l key tree holder adm ended
  [ -n "$root" ] || return 1
  bionic_need slots.sh _slots_live || return 1
  store="${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}"
  for f in "$store"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    key=''; tree=''; holder=''; adm=''; ended=''
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in
        key=*) key="${l#key=}" ;;
        tree=*) tree="${l#tree=}" ;;
        holder=*) holder="${l#holder=}" ;;
        admitted=*) adm="${l#admitted=}" ;;
        ended=*) ended="${l#ended=}" ;;
      esac
    done < "$f" 2>/dev/null
    [ -n "$adm" ] && [ -z "$ended" ] && [ -n "$tree" ] || continue
    [ "$tree" = "$root" ] || { [ -n "$co" ] && [ "$tree" = "$co" ]; } || continue
    case "$holder" in *:*) : ;; *) continue ;; esac
    _slots_live "${holder%%:*}" "${holder#*:}" || continue
    printf 'request=%s key=%s tree=%s holder=%s' "$id" "$key" "$tree" "${holder%%:*}"
    return 0
  done
  return 1
}

# The D1 predicate: the gate's requests first (_wt_busy_request, whose line it prints), then the
# runner walk. The walk prints `pid=<pid> cwd=<cwd> script=<path>` for the first runner that
# satisfies it and returns 0; returns 1 when none does. A working directory that could not
# be read prints `unreadable`. The script is `_wt_runner_script`'s word, taken against the
# working directory when it is relative, with its directory made physical, so a symlinked
# spelling (`/tmp` for `/private/tmp`) still compares. A candidate whose script cannot be
# resolved to a file is not a runner: no opinion, as for an unreadable process.
# A THIRD ARGUMENT (wave-28 T3, D6): directories, one per line, whose runners do not count though they
# lie inside the first two. The line asks about the checkout that holds the branch, and the row trees
# and landing trees nested in it are other checkouts: a runner whose working directory, or whose
# script when its directory is unreadable, lies in one of them is left out.
_wt_busy_suite() {  # <main-root> [target-checkout] [nested dirs left out] -> request=... | pid=... cwd=... script=...
  local root="${1:-}" co="${2:-}" out="${3:-}" pids cwds pid cmd cwd script dir x skip
  local -a words
  [ -n "$root" ] || return 1
  _wt_busy_request "$root" "$co" && return 0
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
    read -r -a words <<< "$cmd"
    script="$(_wt_runner_script "${words[@]}")" || continue
    case "$script" in
      /*) : ;;
      *) [ -n "$cwd" ] || continue; script="${cwd}/${script}" ;;
    esac
    dir="$(cd "${script%/*}" 2>/dev/null && pwd -P)" || continue
    script="${dir}/${script##*/}"
    [ -f "$script" ] || continue
    if _wt_cwd_in_project "$script" "$root" "$co" || _wt_cwd_in_project "$cwd" "$root" "$co"; then
      skip=0
      while IFS= read -r x; do
        [ -n "$x" ] || continue
        if [ -n "$cwd" ]; then _wt_cwd_in_project "$cwd" "$x" && skip=1
        else _wt_cwd_in_project "$script" "$x" && skip=1; fi
        [ "$skip" = 1 ] && break
      done <<NESTED
$out
NESTED
      [ "$skip" = 1 ] && continue
      printf 'pid=%s cwd=%s script=%s' "$pid" "${cwd:-unreadable}" "$script"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# The tree's checks a landing shares.
#
# A row lands through the landing line (lib/line.sh: `ready`, and the hand landing), which judges the
# tree here (`_wt_land_checks`) before anything is changed, so a refused landing leaves the repository
# as it found it. The target is named by the caller, read off the session's bound plan and never off
# the main checkout; the checkout holding it is found in `git worktree list --porcelain`
# (`worktree_checkout_of`).
#
# TWO BOUNDS ON THE POWER (security review F1). A landing moves a branch and
# removes a worktree; both of those are irreversible enough that
# WHICH branch and WHICH tree cannot be left to the caller's word for it.
#
#   PROTECTED BRANCH. The branch landed onto — <onto> — is never `main`/`master`.
#   hooks/protect-main.sh is the wall that keeps unreviewed work off those
#   branches, and it reads `git push` argv, which a local landing never is.
#   The list is `git_branch_protected`'s, not a second copy of it.
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

# Every checkout git lists for <root>, from `git worktree list --porcelain`: one
# `worktree <path>` stanza per checkout, its `branch refs/heads/<b>` line naming
# what it holds. Printed one per line as `<ref>` TAB `<path as git prints it>`,
# the ref `-` for a detached or bare stanza, and the MAIN checkout first, because
# git lists it first. rc 1 when git cannot be asked or lists nothing (a root that
# is no repository). The one reader of the porcelain: `worktree_checkout_of` and
# the workspace readers below both take it from here.
_wt_checkouts() {  # <root>
  local list line path="" ref="-" n=0
  list="$(git -C "${1:-}" worktree list --porcelain 2>/dev/null)" || return 1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        [ "$n" -gt 0 ] && printf '%s\t%s\n' "$ref" "$path"
        path="${line#worktree }"; ref="-"; n=$((n + 1)) ;;
      "branch "*) ref="${line#branch }" ;;
    esac
  done <<EOF
$list
EOF
  [ "$n" -gt 0 ] || return 1
  printf '%s\t%s\n' "$ref" "$path"
}

# The checkout holding <branch>. The path is printed physically (`pwd -P`), the
# form every other path in this file is compared in.
#
#   0  one checkout holds it -> its path
#   1  no checkout holds it
#   2  more than one does (`worktree add --force` makes that possible) -> the
#      paths, space-separated: which of them to merge in is not a guess to make
#   3  the one stanza's directory cannot be entered (a prunable entry) -> its path
worktree_checkout_of() {  # <root> <branch>
  local want="refs/heads/${2:-}" ref path hits="" n=0 abs
  [ -n "${2:-}" ] || return 1
  while IFS=$'\t' read -r ref path; do
    [ "$ref" = "$want" ] || continue
    n=$((n + 1)); hits="${hits:+$hits }${path}"
  done <<EOF
$(_wt_checkouts "${1:-}")
EOF
  [ "$n" -eq 0 ] && return 1
  if [ "$n" -gt 1 ]; then printf '%s' "$hits"; return 2; fi
  abs="$(_wt_abs "$hits")" || { printf '%s' "$hits"; return 3; }
  printf '%s' "$abs"
}

# THE RECORD LINK NEVER LANDS (wave-27 T79, the walk's W2). `create` plants `<tree>/.bionic` as a
# link to the project's one `.bionic` directory. In a project whose ignore rules never named it, a
# writer's `git add -A` committed the link, and the land merged it: git replaced the main
# checkout's real `.bionic`, every file of which its own `.gitignore` (`*`) ignores, with a link to
# itself, and the plan, the roster, the record and the engagement marker were gone. `create` now
# excludes the link; this is the second layer, for a link committed anyway (`git add -f`, a tree
# made before the exclude, a project that cleared the line). A range that ADDS `.bionic` or a path
# under it is refused before anything merges. A target that already tracks content there (an older
# project's own, the `create` header's "unless the branch already tracks something at that path")
# keeps it: a range may change or delete a path the target tracks, since a tracked path is never one
# of bionic's ignored files. `:(literal)` keeps the pathspec to exactly that path and its children.
# PER PATH, AND THE KIND FIRST (wave-27 T84; review pass 68, A-orch-227). T79 exempted every range
# into a target that tracked something at `.bionic`, so a tree that removed the tracked content and
# committed the link landed with the same loss, and one that added a file under the tracked
# directory overwrote the project's untracked file at that path (git overwrites ignored files
# freely). Now `.bionic`'s own kind never changes, whatever the target tracks: a range whose head
# has a directory, link or file at `.bionic` where the target has another kind is refused first,
# naming `.bionic` and the first commit that changed the kind. Then an add under `.bionic/` is
# refused, naming the first added path and the commit that added it; a target with nothing at
# `.bionic` gets a directory only through such adds, so that one change of kind is theirs to name.
# A range that deletes every tracked path, leaving nothing at `.bionic`, lands.
# BY ITS BYTES, IN ANY CASE (wave-27 T86; review pass 71, A-orch-242). T84 read one spelling
# (`:(literal).bionic`, `ls-tree -- .bionic`) and filtered `--name-only` lines with a pattern: on a
# case-insensitive disk a link committed as `.BIONIC` landed and the project's `.bionic` became a
# link to itself, and a name git C-quotes (`"`, `\`, a control character) never matched, so its add
# overwrote the project's untracked file. Now every name comes from git's NUL-separated streams
# (`ls-tree -z`, `diff --name-only -z`), split on NUL, and a root entry IS `.bionic` when its name
# case-folds to `.bionic` (ASCII, as `[:upper:]` to `[:lower:]` in the C locale), on every disk:
# `.BIONIC`, `.Bionic` and `.bionic` are one path here, as they are to a case-insensitive disk. The
# kind test, the add test and the tracked-content exception all read the folded entry. A range that
# keeps the target's entry, its kind and spelling, and adds a directory under another spelling beside
# it changes no kind: the adds under it are named; a link or a file beside it is a change of kind,
# named in its spelling. The commit that made a change is found by asking git for each commit's
# tree, never by a pathspec.
_wt_bionic_named() {  # <root entry name> -> 0 when it case-folds to `.bionic`
  case "$1" in .[Bb][Ii][Oo][Nn][Ii][Cc]) return 0 ;; esac
  return 1
}
# <root> <rev> [spelling] -> "<kind> <spelling>" for the one root entry of <rev> folding to `.bionic`
# (dir | link | file | other), "other <first>" for two such entries, or "nothing"; with a
# spelling, for the entry spelled exactly so.
_wt_bionic_kind() {
  local rec name kind="" n=0
  while IFS= read -r -d '' rec; do
    name="${rec#*$'\t'}"
    if [ -n "${3:-}" ]; then [ "$name" = "$3" ] || continue; else _wt_bionic_named "$name" || continue; fi
    n=$((n + 1))
    if [ "$n" -gt 1 ]; then kind="other ${kind#* }"; continue; fi
    case "${rec%% *}" in 040000) kind=dir ;; 120000) kind=link ;; 100644|100755) kind=file ;; *) kind=other ;; esac
    kind="${kind} ${name}"
  done < <(git -C "$1" ls-tree -z "$2" 2>/dev/null)
  printf '%s' "${kind:-nothing}"
}
_wt_bionic_beside() {  # <root> <rev> <spelling> -> the first other root entry folding to `.bionic` that is no directory
  local rec name
  while IFS= read -r -d '' rec; do
    name="${rec#*$'\t'}"
    [ "$name" != "$3" ] && _wt_bionic_named "$name" && [ "${rec%% *}" != 040000 ] && { printf '%s' "$name"; return 0; }
  done < <(git -C "$1" ls-tree -z "$2" 2>/dev/null)
  return 1
}
# <kind> <kind> -> 0 when the second is another kind at `.bionic`, or a link or a file under another
# spelling: no path under a link or a file shows a renamed one to the add test.
_wt_bionic_differs() {
  [ "${1%% *}" != "${2%% *}" ] && return 0
  case "${2%% *}" in link|file) [ "$1" != "$2" ] ;; *) return 1 ;; esac
}
# <root> <onto head> <tree head> -> "<commit> <spelling>": the first commit that changed the kind,
# and the entry that changed it in the range's spelling | nothing
_wt_bionic_kind_changed() {
  local root="$1" was now at c
  was="$(_wt_bionic_kind "$root" "$2")"; now="$(_wt_bionic_kind "$root" "$3")"
  _wt_bionic_differs "$was" "$now" && [ "$now" != nothing ] && [ "${was%% *}:${now%% *}" != nothing:dir ] || return 1
  at="${now#* }"
  case "$was" in
    nothing|other*) : ;;
    *) if [ "$(_wt_bionic_kind "$root" "$3" "${was#* }")" = "$was" ]; then
         at="$(_wt_bionic_beside "$root" "$3" "${was#* }")" || return 1
       fi ;;
  esac
  for c in $(git -C "$root" rev-list --reverse "${2}..${3}" 2>/dev/null); do
    _wt_bionic_differs "$(_wt_bionic_kind "$root" "${c}^")" "$(_wt_bionic_kind "$root" "$c")" \
      && { printf '%s %s' "$c" "$at"; return 0; }
  done
  printf '%s %s' "$3" "$at"
}
# `--ignore-submodules=none` (wave-28 T39, D31; wave-27 critic P3-1): `diff.ignoreSubmodules=all`, set in
# any config the user holds, took a gitlink out of the answer, and a submodule link under `.bionic/`
# landed; the answer is git's own, whatever `diff.ignoreSubmodules` says.
_wt_bionic_adds() {  # <root> <onto head> <tree head> -> every path the range adds, NUL-separated, as git stores it
  git -C "$1" diff --ignore-submodules=none --no-renames --diff-filter=A --name-only -z "$2" "$3" 2>/dev/null
}
_wt_bionic_first_add() {  # <root> <onto head> <tree head> -> the first path added under a root entry folding to `.bionic`, then `/`
  local p
  while IFS= read -r -d '' p; do
    case "$p" in */*) _wt_bionic_named "${p%%/*}" && { printf '%s/' "$p"; return 0; } ;; esac
  done < <(_wt_bionic_adds "$1" "$2" "$3")
  return 1
}
# THE ENTRY, NOT THE OBJECT (wave-28 T3, ruling A-orch-14): a submodule link names a commit of another
# repository, absent here, so `cat-file -e <c>:<path>` was false for it; the guard then named the head
# as a path the target dropped and printed `merge <onto>`, which left the refusal standing.
_wt_bionic_added_by() {  # <root> <onto head> <tree head> <path> -> the first commit of the range that added it | nothing
  local root="$1" c
  for c in $(git -C "$root" rev-list --reverse "${2}..${3}" 2>/dev/null); do
    git -C "$root" rev-parse --verify -q "${c}:${4}" >/dev/null 2>&1 && ! git -C "$root" rev-parse --verify -q "${c}^:${4}" >/dev/null 2>&1 \
      && { printf '%s' "$c"; return 0; }
  done
  return 1
}
# <root> <onto head> <tree head> -> "<commit> <path>/": `.bionic`'s entry in the range's spelling for a
# change of kind, else the first added path. The `/` no name ends with keeps a name's own trailing
# newline through `$(...)`; the caller takes it off. An add no commit of the range made is a path the
# target dropped after the tree branched: its commit is `dropped:<tree head>` (A-orch-256).
_wt_bionic_committed() {
  local root="$1" onto_head="$2" head="$3" path commit
  commit="$(_wt_bionic_kind_changed "$root" "$onto_head" "$head")" && { printf '%s/' "$commit"; return 0; }
  path="$(_wt_bionic_first_add "$root" "$onto_head" "$head")" || return 1
  path="${path%/}"
  commit="$(_wt_bionic_added_by "$root" "$onto_head" "$head" "$path")" || commit="dropped:${head}"
  printf '%s %s/' "$commit" "$path"
}
# <name> -> the name as `git -c core.quotePath=true` prints it when it holds `"`, `\` or a control
# character (in double quotes, C escapes, every other byte outside printable ASCII in octal), so a
# refusal naming it stays one line; any other name as it is.
_wt_cquote() {
  local LC_ALL=C s="$1" out='"' c i v
  case "$s" in *[\"\\]*|*[[:cntrl:]]*) : ;; *) printf '%s' "$s"; return 0 ;; esac
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \"|\\) out="${out}\\${c}" ;;
      $'\a') out="${out}\\a" ;; $'\b') out="${out}\\b" ;; $'\t') out="${out}\\t" ;; $'\n') out="${out}\\n" ;;
      $'\v') out="${out}\\v" ;; $'\f') out="${out}\\f" ;; $'\r') out="${out}\\r" ;;
      *)
        printf -v v '%d' "'$c"; [ "$v" -ge 0 ] || v=$((v + 256))
        if [ "$v" -lt 32 ] || [ "$v" -ge 127 ]; then printf -v c '\\%03o' "$v"; fi
        out="${out}${c}" ;;
    esac
  done
  printf '%s"' "$out"
}
# <word> -> the word as a shell reads it back to the same bytes, on one line (wave-28 T39, D31; review
# pass 74's P2-1): as it is when every byte is a letter, a digit or one of `_./@+:-`; in single quotes
# otherwise; as `$'…'` with C escapes when it holds `'` or a control character, so a tab or a line
# break never splits the refusal's line.
_wt_shquote() {
  local LC_ALL=C s="$1" out="\$'" c i v
  case "$s" in
    '') printf "''"; return 0 ;;
    *[!A-Za-z0-9_./@+:-]*) : ;;
    *) printf '%s' "$s"; return 0 ;;
  esac
  case "$s" in *\'*|*[[:cntrl:]]*) : ;; *) printf "'%s'" "$s"; return 0 ;; esac
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \'|\\) out="${out}\\${c}" ;;
      $'\t') out="${out}\\t" ;; $'\n') out="${out}\\n" ;; $'\r') out="${out}\\r" ;;
      *)
        printf -v v '%d' "'$c"; [ "$v" -ge 0 ] || v=$((v + 256))
        if [ "$v" -lt 32 ] || [ "$v" -eq 127 ]; then printf -v c '\\%03o' "$v"; fi
        out="${out}${c}" ;;
    esac
  done
  printf "%s'" "$out"
}

# The refusal is land's own contract line, like every sibling (wave-27 T79, A-orch-205): one
# `REFUSED reason=bionic-committed` line on stdout naming the path (`.bionic` for a change of kind,
# else the first added path), the commit that made it (12 hex) and the remedy, which
# `spawn-worktree.sh land` and the standdown's report read as they read every other land refusal.
# The remedy ends "say ready again": the line proves the next head itself and reads no stamp
# (wave-28 T3, D31; it said "run the suites, land again" until 1.12.0). The remedy is per path (A-orch-231): a
# path added under a directory the target tracks is taken out of the index alone, since
# `rm -r --cached .bionic` would also un-track the project's own files there and the merge would
# then delete them from the main checkout; `.bionic` itself, or an add where the target tracks no
# directory, takes the whole path out. The added file is then untracked in the tree, which land
# counts as dirty, so the line says to move it out of the tree: nothing of the writer's is lost
# (A-orch-238).
# The path and the remedy are in the range's spelling (wave-27 T86): the whole entry out is the
# folded root entry the range added, as the range spelled it; a name git C-quotes is printed quoted.
# PASTED AS PRINTED (wave-28 T39, D31; review pass 74's P2-1): every path and name the fix prints is
# quoted for the shell (`_wt_shquote`), save the whole entry, which folds to `.bionic` and so is all
# safe bytes and printed bare; and the per-path pathspec of a name holding a glob character
# is `:(literal)`, so git un-tracks that path alone, never a tracked file the pattern also matches.
# EVERY PRINTED FIX LANDS WHEN FOLLOWED (A-orch-244; pass 71's P2-1): the whole entry, out of the
# index, stays in the tree; where no ignore rule covers it and it is not the record link land passes
# over (`_wt_piece_dirt`), the next land read it as dirty, so the fix also moves it out of the tree.
_wt_bionic_left_dirty() {  # <tree abs> <entry> -> 0 when the entry, untracked, would read as dirt to land
  git -C "$1" check-ignore -q --no-index -- "$2" 2>/dev/null && return 1
  [ "$2" = .bionic ] && [ -L "${1}/.bionic" ] && return 1
  return 0
}
# A PATH THE TARGET DROPPED (A-orch-256): taking it out of the tree's index too makes both sides
# delete it, which land refuses not-current; merging the target into the tree carries the target's
# own untracking, after which the range adds nothing there. That shape's fix is the merge.
_wt_refuse_bionic() {  # <tree abs> <branch> <onto> <commit | dropped:<head>> <path> <target's kind at .bionic>
  local entry="${5%%/*}" commit="${4#dropped:}" path fix spec="$5"
  path="$(_wt_cquote "$5")"; fix="rm -r --cached ${entry}"
  case "$5" in *[][*?\\]*) spec=":(literal)$5" ;; esac
  if [ "$commit" != "$4" ]; then fix="merge $(_wt_shquote "$3")"
  elif [ "$5" != "$entry" ] && [ "${6%% *}" = dir ]; then
    fix="rm --cached $(_wt_shquote "$spec"), move $(_wt_shquote "$5") out of the tree, commit"
  elif _wt_bionic_left_dirty "$1" "$entry"; then fix="${fix}, move ${entry} out of the tree, commit"
  else fix="${fix}, commit"; fi
  _wt_refuse "bionic-committed path=${path} commit=${commit:0:12} branch=${2} onto=${3} fix='git -C $(_wt_shquote "$1") ${fix}, say ready again' — a committed .bionic, merged, replaces the project's .bionic directory; nothing is merged, the tree is kept"
}

# THE TREE'S OWN CHECKS, which `ready` and the hand landing share, in this order: a linked tree inside the farm, a branch to land onto that exists and is not
# protected, a plan not past judgment, the tree on a branch, clean, and ahead. With <need checkout> 1 the
# branch must be held by one checkout (land merges there); with 0 a branch no checkout holds is the
# line's `update-ref` case. Sets _WT_ABS, _WT_ROOT, _WT_BRANCH and _WT_CO ("" when none holds it).
_wt_land_checks() {  # <tree> <onto> <plan or empty> <need checkout 1|0> -> 0, or 2 having refused
  local target="${1:-}" onto="${2:-}" plan="${3:-}" wt_abs root co rc judged_cur branch dirt ahead row
  _WT_ABS=""; _WT_ROOT=""; _WT_BRANCH=""; _WT_CO=""
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
    1) [ "${4:-1}" = 0 ] || { _wt_refuse "onto-not-checked-out branch=${onto} root=${root}"; return 2; }; co="" ;;
    2) _wt_refuse "onto-ambiguous branch=${onto} checkouts=${co// /,}"; return 2 ;;
    *) _wt_refuse "onto-checkout-unresolvable branch=${onto} checkout=${co}"; return 2 ;;
  esac
  _wt_branch_protected "$onto"
  case $? in
    0) _wt_refuse "protected-branch branch=${onto} checkout=${co:-<none>}"; return 2 ;;
    2) _wt_refuse "protected-branch-unknowable branch=${onto} checkout=${co:-<none>}"; return 2 ;;
  esac

  # THE RUN HAS BEEN JUDGED FOR INTEGRATION (wave-27 T31; review pass 25 F3). `current 8` admits
  # integration on the judge at the working head; a landing after it would move the working branch
  # past the head that was judged, and nothing would judge it again. So with a bound plan at
  # `current: 8` or later (its letter dropped) nothing lands: the step is set back first, which the
  # `current` verb allows (`current 7`, dry-committed at 7 like any move). One row is the exception: a
  # fix born of a finding of a review the judge reads failing, since its landing is what answers that
  # review (lib/line.sh `line_born_failing`, which `ready` and the hand landing load; a caller that has
  # not loaded it keeps the refusal).
  if [ -n "$plan" ]; then
    judged_cur="$(_wt_plan_current "$plan")" || {
      _wt_refuse "place-unreadable plan=${plan} — the run's step could not be read, so whether it was judged for integration is not known; land again once the run's facts read"; return 2; }
    case "${judged_cur%[ab]}" in
      8|9) row="$(_wt_proofs_row "$root" "$plan" "$wt_abs")" && [ "$(worktree_row_kind "$plan" "$row")" = integrate ] && {
           _wt_refuse "integrate-row row=${row} kind=integrate path=${wt_abs} — an integrate row lands as a record, never through ready: remove its tree (spawn-worktree.sh remove ${wt_abs}), and once its writer ends with its contract met the tick lands the row (session-poker.sh tick)"; return 2; }
           declare -F line_born_failing >/dev/null 2>&1 && line_born_failing "$plan" "$root" "$wt_abs" || {
           _wt_refuse "past-judgment why=current-${judged_cur} plan=${plan} — the run has been judged for integration at current: ${judged_cur}, and a landing would move the working branch past the head that was judged; set the step back (session-poker.sh current 7), land again"; return 2; } ;;
    esac
  fi

  branch="$(git -C "$wt_abs" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$branch" ] && [ "$branch" != "HEAD" ] || { _wt_refuse "worktree-head-unreadable path=${wt_abs}"; return 2; }

  # The record link is not work. In a project that ignores `.bionic` only in its
  # directory shape, or not at all, git reads the link as `?? .bionic`; that one
  # entry is passed here and the link itself is dropped just before the removal.
  dirt="$(_wt_piece_dirt "$wt_abs")"
  if [ -n "$dirt" ]; then
    _wt_refuse "dirty-tree path=${wt_abs} branch=${branch}"; return 2
  fi

  ahead="$(git -C "$root" rev-list --count "refs/heads/${onto}..${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) _wt_refuse "branch-unreadable branch=${branch}"; return 2 ;; esac
  if [ "$ahead" -eq 0 ]; then
    _wt_refuse "nothing-to-land branch=${branch} onto=${onto}"; return 2
  fi
  _WT_ABS="$wt_abs"; _WT_ROOT="$root"; _WT_BRANCH="$branch"; _WT_CO="$co"
  return 0
}

# WHAT A RANGE CHANGES OF THE CHECK'S FILES: the project's declared list, `release-check-files:` in its config, met
# with the paths <base>..<head> changes. The config is the main checkout's, so <repo dir> may be any checkout of the
# repository. The list is space-separated paths or globs relative to the repository root, read as git's glob
# pathspecs, so a `*` stays within one directory and `**` crosses them. The check's files are declared, never read off
# its command or its loads: a library the check comes to source is its file only once the project says so. It is
# information alone, said on a hand landing's line and on the release approval card; it gates nothing, for the check
# is run as the release base holds it, which no landing writes. Prints the changed files joined by commas and returns
# 0 when the range changes one; 1 otherwise, and when no list is declared.
_wt_check_judge() {  # <repo dir> <base> <head> -> <path>[,<path>]
  local decl w ch root
  local -a spec=() words=()
  root="$(worktree_root "$1")" || root="$1"
  decl="$(config_value "$root" release-check-files "" 2>/dev/null)"
  read -r -a words <<< "$decl"
  for w in "${words[@]+"${words[@]}"}"; do spec+=(":(top,glob)$w"); done
  [ "${#spec[@]}" -gt 0 ] || return 1
  ch="$(git -C "$1" diff --name-only "$2" "$3" -- "${spec[@]}" 2>/dev/null)" || return 1
  [ -n "$ch" ] || return 1
  printf '%s\n' "$ch" | LC_ALL=C sort | paste -sd, -
}

# THE LAST RELEASE: release_base <plan> <checkout> <head> sets RB_BASE, the 40-hex start of the release range, and
# RB_FROM saying where it came from (`tag <t> on <branch>` | `base-sha <s>`), and RB_IB and RB_BS for a refusal to
# name; 1 when there is none. The nearest tag reachable from the plan's `integration-branch:` that is a PROPER ancestor
# of <head> (the fewest commits from it to <head>): a tag on <head>, or on a commit not on its history, is no base, for
# the range it opens would hold nothing or the wrong thing. With none, the plan's `base-sha:`. It is the release range's
# start for the release-check verb, the hand landing's scan and the release card, and the judge every run of the
# declared check is run as (`worktree_check_run`), so all of them name one commit. Its readers, lib/plan.sh
# `plan_integration_branch` and lib/proof.sh `proof_plan_base`, are loaded on first use, so a caller that never asks
# for the judge keeps its own load order.
# THE PERSON'S WORD MOVES IT. The run's standing judge event (the reader's `judge`, written by `check-from` on words
# the person typed) names a commit; read first, it is RB_BASE when that commit is a proper ancestor of <head>, and
# RB_FROM then names it, the words and who typed them, RB_WORD the last two alone. The judge is still never a commit
# the landing it judges wrote: the word was given at a head that landing's candidate only descends from. RB_RELEASE is
# the release base the tags and base-sha give, whatever the judge is, for a reader that counts from the release.
release_base() {  # <plan> <checkout> <head>
  local plan="$1" co="$2" head="$3" t tc tn best="" jw
  RB_BASE=""; RB_FROM=""; RB_BS=""; RB_IB=""; RB_RELEASE=""; RB_WORD=""
  bionic_need run.sh _run_lines
  bionic_need plan.sh plan_integration_branch && bionic_need proof.sh proof_plan_base || return 1
  jw="$(bionic_need reader.sh reader_log_in && reader_main "$plan" judge 2>/dev/null)" || jw=""
  RB_IB="$(plan_integration_branch "$plan")"
  if [ -n "$RB_IB" ]; then
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      tc="$(git -C "$co" rev-parse --verify -q "refs/tags/$t^{commit}" 2>/dev/null)" || continue
      [ "$tc" != "$head" ] || continue
      git -C "$co" merge-base --is-ancestor "$tc" "$head" 2>/dev/null || continue
      tn="$(git -C "$co" rev-list --count "$tc..$head" 2>/dev/null)" || continue
      if [ -z "$best" ] || [ "$tn" -lt "$best" ]; then
        best="$tn"; RB_BASE="$tc"; RB_FROM="tag $t on $RB_IB"
      fi
    done <<RB_TAGS
$(git -C "$co" tag --merged "refs/heads/$RB_IB" 2>/dev/null)
RB_TAGS
  fi
  if [ -z "$RB_BASE" ]; then
    RB_BS="$(proof_plan_base "$plan" "$co")"
    [ -z "$RB_BS" ] || RB_BASE="$(git -C "$co" rev-parse --verify -q "$RB_BS^{commit}" 2>/dev/null)"
    RB_FROM="base-sha $RB_BS"
  fi
  RB_RELEASE="$RB_BASE"
  tc="$(printf '%s\n' "$jw" | sed -n 's/^head=//p')"
  case "$tc" in *[!0-9a-f]*) tc="" ;; esac
  if [ -n "$tc" ] && [ "$tc" != "$head" ] && git -C "$co" merge-base --is-ancestor "$tc" "$head" 2>/dev/null; then
    RB_WORD="$(printf '%s\n' "$jw" | sed -n 's/^by=//p')'s word \"$(printf '%s\n' "$jw" | sed -n 's/^said=//p')\""
    RB_BASE="$tc"; RB_FROM="the judge ${tc:0:12}, set by ${RB_WORD}"
  fi
  [ -n "$RB_BASE" ]
}

# THE ONE RUNNER OF THE DECLARED CHECK. The release-check verb, the door and the hand landing's scan all run the
# project's `release-check:` command here and nowhere else, so every run over a range is judged by one copy: the
# judge's, the release base, which no landing it judges can have written. A head judged by its own copy could
# rewrite its check to pass; a target's copy changes with every landing. The judge is <judge> when the caller names
# it, else `release_base` for <plan> and <head>, else the range's own <base> (a plan with no tag and no base-sha),
# and WT_CHECK_FROM says which. It is checked out in a landing tree the tool owns, the command's words split on
# blanks with globbing off, an absolute word under <root> read as the same path inside that tree, so a declaration
# that names the main checkout's file still runs the judge's. The tree holds no plan, so BIONIC_CHECK_PROJECT names
# <root>, where the check reads the plan, the record and the renderer's plan; BIONIC_CHECK_BASE and _HEAD are the
# range, BIONIC_CHECK_TREE <tree> (the tree itself when none is given), BIONIC_CHECK_BRANCH <branch> when given, and
# BIONIC_CHECK_RELEASE the release base `release_base` finds (RB_RELEASE) whatever the judge is, so a check that counts
# from the release counts from the tag, never from a judge the person moved past it.
# Sets WT_CHECK_CMD, WT_CHECK_OUT (stdout and stderr), WT_CHECK_RC, WT_CHECK_JUDGE, WT_CHECK_FROM, WT_CHECK_DIR (the
# tree it ran in) and WT_CHECK_LEFT (`_wt_check_left` over that tree and <tree>, when <tree> is given).
worktree_check_run() {  # <root> <plan> <judge> <base> <head> [<tree>] [<branch>] -> 0 ran · 1 none declared · 2 not run
  local root="$1" plan="$2" judge="$3" base="$4" head="$5" tree="${6:-}" branch="${7:-}" lt rp rel=""
  WT_CHECK_OUT=""; WT_CHECK_RC=0; WT_CHECK_JUDGE=""; WT_CHECK_FROM=""; WT_CHECK_DIR=""; WT_CHECK_LEFT=""
  WT_CHECK_CMD="$(config_value "$root" release-check "" 2>/dev/null)"
  [ -n "$WT_CHECK_CMD" ] || return 1
  if [ -n "$judge" ]; then
    WT_CHECK_FROM="named by the caller"
    ! release_base "$plan" "$root" "$head" || rel="$RB_RELEASE"
  elif release_base "$plan" "$root" "$head"; then
    judge="$RB_BASE"; WT_CHECK_FROM="$RB_FROM"; rel="$RB_RELEASE"
  else
    judge="$base"; WT_CHECK_FROM="the range's base: the plan names no tag and no base-sha"
  fi
  WT_CHECK_JUDGE="$(git -C "$root" rev-parse --verify -q "${judge}^{commit}" 2>/dev/null)" \
    || { WT_CHECK_OUT="the judge ${judge:-<none>} is no commit in ${root}"; return 2; }
  lt="$(landing_tree_take "$root")" || { WT_CHECK_OUT="no landing tree can be taken under ${root}"; return 2; }
  if ! landing_tree_point "$lt" "$WT_CHECK_JUDGE"; then
    landing_tree_free "$lt"
    WT_CHECK_OUT="the landing tree ${lt} cannot be checked out at the judge ${WT_CHECK_JUDGE}"; return 2
  fi
  WT_CHECK_DIR="$lt"; rp="$(_wt_abs "$root")"
  WT_CHECK_OUT="$(cd "$lt" 2>/dev/null || exit 1
    set -f; set --
    # shellcheck disable=SC2086  # the configured command is meant to split on blanks
    for w in $WT_CHECK_CMD; do
      # Each arm opens with `(`: bash 3.2 reads an unopened arm's `)` inside `$( )` as the substitution's end.
      case "$w" in
        ("${root%/}"/*) w="${lt}/${w#"${root%/}"/}" ;;
        ("${rp:-/nonexistent}"/*) w="${lt}/${w#"$rp"/}" ;;
      esac
      set -- "$@" "$w"
    done
    # The hold holds the reads of the one command that opened it (lib/proof.sh), never the project: the check runs the
    # code of the judge, and a hold handed to it would fold its facts with the reader of the head being judged.
    # No quote mark in a comment here: bash 3.2 reads one inside a command substitution as a quote opened.
    unset BIONIC_HELD
    export BIONIC_CHECK_PROJECT="$root" BIONIC_CHECK_BASE="$base" BIONIC_CHECK_HEAD="$head" BIONIC_CHECK_TREE="${tree:-$lt}"
    [ -z "$rel" ] || export BIONIC_CHECK_RELEASE="$rel"
    [ -z "$branch" ] || export BIONIC_CHECK_BRANCH="$branch"
    exec "$@" </dev/null 2>&1)"; WT_CHECK_RC=$?
  [ -z "$tree" ] || WT_CHECK_LEFT="$(_wt_check_left "$lt" "$WT_CHECK_JUDGE" "$tree")"
  landing_tree_free "$lt"
  return 0
}

# THE DOOR'S RUN OF THE DECLARED CHECK, for `line_publish`: the one runner over <base>..<head>,
# judged by the release base of <plan>; <writer tree> is the piece whose cleanliness the check must leave as it found
# it. A landing that changes the check's own files is judged like any other: the judge is a commit no landing writes,
# so a fix to the check lands, and what it changes is said on the plan line by the hand scan and on the release card.
# 0 when no check is declared or it passed and left nothing; 2 having refused, nothing merged.
_wt_release_check() {  # <root> <plan> <base> <head> <writer tree> <branch> <onto> [<row>] -> 0 | 2
  local root="$1" plan="$2" onto_head="$3" head="$4" wt_abs="$5" branch="$6" onto="$7" rc left said judged
  worktree_check_run "$root" "$plan" "" "$onto_head" "$head" "$wt_abs"; rc=$?
  case "$rc" in
    1) return 0 ;;
    2) _wt_refuse "check-unrun why=release-check branch=${branch} onto=${onto} base=${onto_head} head=${head} — the project's declared release-check (${WT_CHECK_CMD}) cannot be run as the release base holds it: ${WT_CHECK_OUT}; nothing is merged"; return 2 ;;
  esac
  left="$WT_CHECK_LEFT"; judged="judged-by=${WT_CHECK_JUDGE:0:12}"
  if [ "$WT_CHECK_RC" -ne 0 ]; then
    [ -z "$WT_CHECK_OUT" ] || printf '%s\n' "$WT_CHECK_OUT" >&2
    _wt_refuse "check-failed why=release-check rc=${WT_CHECK_RC} branch=${branch} base=${onto_head} head=${head}${left:+ ${left}} ${judged} — the project's declared release-check (${WT_CHECK_CMD}), run as the judge ${WT_CHECK_JUDGE:0:12} holds it (${WT_CHECK_FROM}), fails over this landing's range${left:+ and left changes, named before judged-by}; fix what it names on ${branch}${left:+, put back what it changed}, re-run its suites, land again"; return 2
  fi
  if [ -n "$left" ]; then
    # WHAT THE CHECK LEFT: the judge's tree off the judge or changed, or the piece's checkout changed. A check that
    # moves or dirties what it was handed would leave the merge standing on something it did not judge.
    said=""
    case " $left" in *" head_was="*) said="moved the judge's landing tree ${WT_CHECK_DIR} off the judge (git -C ${WT_CHECK_DIR} reflog -2)" ;; esac
    case " $left" in *" paths="*) said="${said:+${said}; }left tracked files changed in the judge's landing tree ${WT_CHECK_DIR}" ;; esac
    case " $left" in *" piece_paths="*) said="${said:+${said}; }changed the piece's checkout ${wt_abs} (git -C ${wt_abs} status)" ;; esac
    _wt_refuse "check-dirtied why=release-check checkout=${WT_CHECK_DIR} ${left} branch=${branch} ${judged} — the project's declared release-check (${WT_CHECK_CMD}) ${said}, and nothing is merged; put back what it changed, make the check change nothing, land again"; return 2
  fi
  return 0
}

# THE LANDING RECORD (wave-27 T44; D15; the Interfaces row "landing record").
# `<docs-root>/record/<the bound plan's name less .plan.md>/run.log`, the run's log, where each landing is a
# `published` event; lib/line.sh `line_lines` reads it. The path is derived from the project's docs root
# (lib/roots.sh `docs_root`), in the project's docs tree, never in the tree being removed. The slug is lib/proof.sh `proof_plan_slug`'s, the
# one reader (wave-37 T2; AC-9.2), loaded on first use as units.sh and slots.sh are here.
_wt_proofs_path() {  # <root> <plan> -> the record's path, the run's log
  local slug
  bionic_need proof.sh proof_plan_slug && bionic_need reader.sh reader_log_in && slug="$(proof_plan_slug "${2:-}")" || return 1
  printf '%s' "$(reader_log_in "$(docs_root "$1")/record/$slug")"
}

# The id of the first `## Tasks` row, in table order, whose `worktree` cell names <tree>; a
# relative cell is read from <root>. Nothing when none does, or when lib/units.sh, the table's
# one reader, cannot be loaded (it is loaded lazily, as run.sh is below).
# A Tasks `worktree` cell as the tree it names: a leading `./` and any trailing slashes are not part of the name,
# and a relative cell is joined to <root>. rc 1 for an empty cell (`-`, `—`).
_wt_cell_tree() {  # <root> <cell>
  local cell="${2:-}"
  while :; do
    case "$cell" in ./*) cell="${cell#./}" ;; */) cell="${cell%/}" ;; *) break ;; esac
  done
  case "$cell" in ''|-|—) return 1 ;; /*) printf '%s' "$cell" ;; *) printf '%s/%s' "${1%/}" "$cell" ;; esac
}
_wt_proofs_row() {  # <root> <plan> <tree abs> -> <row id> | nothing
  local rec cell id
  bionic_need units.sh units_rows || return 1
  while IFS= read -r rec; do
    cell="$(_wt_cell_tree "$1" "$(units_field "$rec" worktree)")" || continue
    if [ "$cell" = "$3" ]; then
      # An id holding white space would break the header's `key=value` grammar: no row (`—`).
      id="$(units_field "$rec" id)"
      case "$id" in *[[:space:]]*) return 1 ;; esac
      printf '%s\n' "$id"; return 0
    fi
  done <<EOF
$(units_rows "$2" 2>/dev/null)
EOF
  return 1
}

# THE RECORD PATH IS A REGULAR FILE OR ABSENT, AND IS PROVED WRITABLE (wave-27 T44, T50; review pass
# 27 N1, N2). A symlink (a link to `/dev/null` silently loses the record; a link to a file outside the
# docs tree appends there), a FIFO (opening one for append blocks the landing for good), a device or a
# directory at the path is refused before anything is opened. A record that is there must be one this
# process may write.
#
# THE PROOF CREATES NOTHING AT THE RECORD'S PATH (wave-27 T69; review pass 48). The directory is made
# if it is missing, and is proved writable by a file of the proof's own (`_wt_proofs_private`) made and
# removed again there. The record itself is tested and never opened, so a landing refused after the
# proof has nothing to clean up, and no path of `land` removes or truncates the record.
_wt_proofs_prove() {  # <record path> -> 0 writable, 1 not
  local mine
  [ ! -L "$1" ] || return 1
  if [ -e "$1" ]; then [ -f "$1" ] && [ -w "$1" ] || return 1; fi
  mkdir -p "${1%/*}" 2>/dev/null || return 1
  mine="$(_wt_proofs_private "$1")" || return 1
  rm -f "$mine"
}

# A private file beside the record, made by `mktemp` (exclusive, so never another's):
# `.<record's name>.<this process's pid>.<random>`. One a killed append left is never read again.
_wt_proofs_private() {  # <record path> -> the new file's path
  local me
  me="$(exec sh -c 'echo "$PPID"')"   # this process's own pid, which `$$` is not inside a subshell
  mktemp "${1%/*}/.${1##*/}.${me}.XXXXXX" 2>/dev/null
}

# THE APPEND IS ONE WRITE (wave-27 T69; review pass 48; A-orch-124, A-orch-132). The record had a
# lock, and four rows on it (T50, T58, T63) each closed one race and exposed the next: a lock made of a
# directory has states a killed process leaves behind, and every rule for clearing them is itself a
# race. The record needs none. The block (the header and the judged lines under it) is written whole
# to a private file, and `dd` with one block size copies it to the record in one read and ONE
# write(2), on a descriptor the shell opened for append. A local filesystem puts each such write at the
# end of the file whole, so two landings' blocks never interleave and neither is lost, with no
# cooperation between writers. A network filesystem gives no such guarantee, and is not supported.
#   - the record's type is tested before it is read and again immediately before the append: anything
#     but a regular file or absent is not opened (a FIFO swapped in would block the open for good);
#   - a block over one mebibyte, dd's one block, is not written;
#   - the append is good when dd says so: exit 0 and, under `LC_ALL=C`, exactly one record out and
#     the line `<the block's size> bytes …` (BSD's and GNU's dd both open it so). And the record
#     must be at least as long as before plus the block, true under any interleaving of appends.
#   - a record that does not end in a line break (a write a full disk cut short, never truncated
#     away) gets one in front of the block, so the block's header is a line of its own
#     (`_wt_proofs_cut`).
# Each failure is the `proofs=unwritten` case, and `_WT_PROOFS_SAW` says what was seen. A process
# killed mid-append leaves the record without its block or with it whole, and at most its private
# file beside it.
_WT_PROOFS_SAW=""

# THE RECORD ENDS IN A CUT LINE, and stays so (wave-27 T69; A-orch-132). A reader can see another
# landing's append half done (measured here: 4 of 1,169 reads of the last byte during appends), so a
# last byte that is not a line break is looked at again a twentieth of a second later: only a record
# whose size has not moved and whose last byte is still not a line break is cut. A size that moved is
# another append, and is looked at again, five times at most.
_wt_proofs_cut() {  # <record path> -> 0 cut, 1 not
  local n=0 a b
  while [ "$n" -lt 5 ]; do
    [ -s "$1" ] && [ -n "$(tail -c 1 "$1" 2>/dev/null)" ] || return 1
    a="$(wc -c < "$1" 2>/dev/null)"; sleep 0.05; b="$(wc -c < "$1" 2>/dev/null)"
    [ "$a" = "$b" ] && [ -n "$(tail -c 1 "$1" 2>/dev/null)" ] && return 0
    n=$((n + 1))
  done
  return 1
}

# A LANDING'S FACT GOES TO THE RUN'S LOG: the log in the directory of <record or log path>, through the log's one appender
# (lib/log.sh `log_append`, whose write is `_wt_proofs_write`), and never to the landing record. RUN_LOG is set for
# this one call and never exported, since the poker's globals use the name for a suite's output log.
_wt_log_put() {  # <record or log path> <event type> <key=value>... -> 0 appended, 1 not (proofs=unwritten)
  local log
  _WT_PROOFS_SAW=""
  bionic_need reader.sh reader_log_in && log="$(reader_log_in "${1%/*}")" || { _WT_PROOFS_SAW="lib/reader.sh could not be loaded"; return 1; }
  shift
  bionic_need log.sh log_append || { _WT_PROOFS_SAW="lib/log.sh could not be loaded"; return 1; }
  RUN_LOG="$log" log_append "$@" && return 0
  _WT_PROOFS_SAW="${_WT_PROOFS_SAW:-the appender of the log refused the line}"
  return 1
}

# The one write itself, for a landing's block and for the debt's lines alike (wave-27 T67): <text>
# appended whole, as the rules above say, with `_WT_PROOFS_SAW` set on every failure.
_wt_proofs_write() {  # <file> <text> -> 0 appended, 1 not (the proofs=unwritten case)
  local block="$2" priv size before after said rc lead="" nl='
'
  _WT_PROOFS_SAW=""
  if [ -L "$1" ] || { [ -e "$1" ] && [ ! -f "$1" ]; }; then _WT_PROOFS_SAW="the record's path is not a regular file"; return 1; fi
  ! _wt_proofs_cut "$1" || lead="$nl"
  priv="$(_wt_proofs_private "$1")" || { _WT_PROOFS_SAW="no private file could be made beside the record"; return 1; }
  { printf '%s%s\n' "$lead" "$block" > "$priv"; } 2>/dev/null || { rm -f "$priv"; _WT_PROOFS_SAW="the private file could not be written"; return 1; }
  size="$(wc -c < "$priv" 2>/dev/null)"; size="${size//[!0-9]/}"
  before=0; [ ! -e "$1" ] || { before="$(wc -c < "$1" 2>/dev/null)"; before="${before//[!0-9]/}"; }
  if [ -z "$size" ] || [ -z "$before" ]; then rm -f "$priv"; _WT_PROOFS_SAW="the block or the record could not be measured"; return 1; fi
  if [ "$size" -gt 1048576 ]; then rm -f "$priv"; _WT_PROOFS_SAW="the block is ${size} bytes, over the one write of 1048576"; return 1; fi
  if [ -L "$1" ] || { [ -e "$1" ] && [ ! -f "$1" ]; }; then rm -f "$priv"; _WT_PROOFS_SAW="the record's path is not a regular file"; return 1; fi
  said="$(LC_ALL=C dd if="$priv" bs=1048576 2>&1 >> "$1")"; rc=$?
  after="$(wc -c < "$1" 2>/dev/null)"; after="${after//[!0-9]/}"
  rm -f "$priv"
  [ "$rc" -eq 0 ] || { _WT_PROOFS_SAW="dd exit ${rc}: ${said//${nl}/; }"; return 1; }
  case "$said" in
    *"${nl}0+1 records out${nl}${size} bytes"*|*"${nl}1+0 records out${nl}${size} bytes"*)
      [ "${after:-0}" -ge $((before + size)) ] && return 0
      _WT_PROOFS_SAW="the record is ${after:-0} bytes after the append, short of ${before} plus the block's ${size} bytes"; return 1 ;;
  esac
  _WT_PROOFS_SAW="dd: ${said//${nl}/; }"
  return 1
}

# THE DEBT'S ONE WRITER (wave-27 T67; review pass 46 B3; A-orch-120). A declared red is owed because
# `line_publish` (lib/line.sh) wrote it to the run's log, never because a line was
# copied into the plan: the judge (lib/proof.sh `proof_debts`) reads these events, and an older run's `debt:` and
# `void:` lines of its landing record, and nothing else.
#   run/v1|ev=admitted|id=<id>|row=<row|—>|branch=<b>|head=<40-hex>|suite=<suite>|token=<token>|at=<ISO-UTC>
#   run/v1|ev=void|id=<id>|branch=<b>|why=<merge-failed|merge-undone|publish-failed>|at=<ISO-UTC>
# The instant is the appender's, the moment the debt is written, before the merge (the line's fast-forward); a
# green run after it covers the debt. A line that cannot be written is the append answering `proofs=unwritten`. A
# void names the debt of a landing whose merge or fast-forward failed, or was undone.
_wt_debt_write() {  # <record or log> <id> <row> <branch> <head> <suite> <token> -> 0 written, 1 not
  _wt_log_put "$1" admitted "id=${2}" "row=${3:-—}" "branch=${4}" "head=${5}" "suite=${6}" "token=${7}"
}
_wt_debt_void() {  # <record or log> <id> <branch> <why> -> 0 written, 1 not
  _wt_log_put "$1" void "id=${2}" "branch=${3}" "why=${4}"
}
_wt_proofs_put() {  # <record> <line> -> 0 appended, 1 not (proofs=unwritten)
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  _wt_proofs_write "$1" "$2"
}

# A piece's checkout as `land`'s dirty-tree test reads it: every porcelain line, untracked files
# included, less the record link's `?? .bionic`, which is not work.
_wt_piece_dirt() {  # <tree abs> -> porcelain lines | nothing
  local d
  d="$(git -C "$1" status --porcelain 2>/dev/null)"
  [ -L "${1}/.bionic" ] && d="$(printf '%s\n' "$d" | grep -vxF '?? .bionic')"
  printf '%s' "$d"
}

# What the declared check left that it found otherwise (wave-27 T58; review pass 34 N5), as the
# refusal's fields: `head_was=<short> head_now=<short>` when the target's HEAD moved, `paths=<…>`
# for tracked files changed in the target, `piece_paths=<…>` for the piece's checkout made dirty.
# Nothing when it left all three as it found them.
_wt_check_left() {  # <target checkout> <its HEAD before the check> <tree abs> -> fields | nothing
  local now out="" d
  now="$(git -C "$1" rev-parse --verify --quiet HEAD 2>/dev/null)"
  if [ "$now" != "$2" ]; then
    out="head_was=$(git -C "$1" rev-parse --short "$2" 2>/dev/null || printf '%s' "${2:-<none>}")"
    out="${out} head_now=$(git -C "$1" rev-parse --short "$now" 2>/dev/null || printf '%s' "${now:-<none>}")"
  fi
  d="$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null)"
  [ -z "$d" ] || out="${out:+${out} }paths=$(_wt_dirty_paths "$d")"
  d="$(_wt_piece_dirt "$3")"
  [ -z "$d" ] || out="${out:+${out} }piece_paths=$(_wt_dirty_paths "$d")"
  printf '%s' "$out"
}

# The paths of a `git status --porcelain` listing, comma-joined, the first five and a count of the
# rest: what a refusal names.
_wt_dirty_paths() {  # <porcelain lines>
  printf '%s\n' "$1" | awk 'NF { n++; if (n <= 5) out = out (n > 1 ? "," : "") substr($0, 4) }
    END { printf "%s", out; if (n > 5) printf ",+%d more", n - 5 }'
}

# ---------------------------------------------------------------------------
# LANDING TREES (wave-28 T3; spec D1, S14, S15). The line builds and proves a candidate in a tree the
# tool owns: a detached checkout at `<root>/.bionic/tmp/landing/<n>`, outside `.worktrees/`, so the
# tree conventions, the dispatch wall and close-out never count one. A tree is held while
# `<tree>.held` names a live `<pid>:<start>` (the pid and start-time rule of lib/slots.sh); a hold
# whose holder is not alive is free, and is cleared only under the directory's reap lock, so two
# takers never both clear it. Taking a free tree is one exclusive create of its hold. Trees are
# reused between landings and re-pointed, never removed per landing; no agent writes in one.
_wt_landing_dir() { printf '%s/.bionic/tmp/landing' "${1%/}"; }   # <root>
_wt_hold_alive() {  # <hold file> -> 0 while its `<pid>:<start>` lives
  local h="" p now
  { read -r h < "$1"; } 2>/dev/null
  p="${h%%:*}"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  bionic_need slots.sh _slots_since || return 0
  _slots_alive "$p" || return 1
  now="$(_slots_since "$p")"
  [ -z "$now" ] || [ "${h#*:}" = "$now" ]
}
landing_tree_take() {  # <root> -> a free landing tree's path, now held by this shell's process
  local root="${1:-}" dir n=1 t me tries=0
  [ -d "$root" ] || return 1
  dir="$(_wt_landing_dir "$root")"
  mkdir -p "$dir" 2>/dev/null || return 1
  bionic_need slots.sh _slots_since || return 1
  me="$$:$(_slots_since "$$")"
  while :; do
    t="${dir}/${n}"
    if ( set -C; printf '%s\n' "$me" > "${t}.held" ) 2>/dev/null; then break; fi
    if ! _wt_hold_alive "${t}.held"; then
      if mkdir "${dir}/.reap" 2>/dev/null; then
        _wt_hold_alive "${t}.held" || rm -f "${t}.held"
        rmdir "${dir}/.reap" 2>/dev/null
        continue
      fi
      # A reaper killed inside its microseconds leaves `.reap`: cleared once it is a minute old.
      [ -z "$(find "${dir}/.reap" -maxdepth 0 -mmin +1 2>/dev/null)" ] || rmdir "${dir}/.reap" 2>/dev/null
      tries=$((tries + 1)); [ "$tries" -lt 200 ] || return 1
      sleep 0.05; continue
    fi
    n=$((n + 1))
  done
  if [ ! -e "${t}/.git" ]; then
    rm -rf "$t" 2>/dev/null; git -C "$root" worktree prune >/dev/null 2>&1
    git -C "$root" worktree add --quiet --detach "$t" >/dev/null 2>&1 || { rm -f "${t}.held"; return 1; }
  fi
  printf '%s' "$t"
}
landing_tree_point() {  # <tree> <commit> -> 0 once the tree is detached at <commit>, clean
  local t="${1:-}" c="${2:-}"
  [ -n "$t" ] && [ -n "$c" ] && [ -e "${t}/.git" ] || return 1
  git -C "$t" merge --abort >/dev/null 2>&1
  git -C "$t" reset -q --hard >/dev/null 2>&1
  git -C "$t" clean -qfd >/dev/null 2>&1
  git -C "$t" checkout -q --detach "$c" >/dev/null 2>&1
}
landing_tree_free() { rm -f "${1:-/nonexistent}.held"; }   # <tree> — the hold removed

# THE TREE'S REMOVAL, one act for its two callers: the record link dropped, `git worktree remove`
# (which refuses a tree with changes), prune; the link put back when the removal is refused. The
# branch is never touched. rc 1 when git refused.
_wt_tree_remove() {  # <tree abs> <root>
  local wt="$1" root="$2" link_to plan gd stamps=""
  link_to="$(readlink "${wt}/.bionic" 2>/dev/null)"
  plan="$(_wt_tree_record_plan "$wt")"
  # A door run's stamp lives in the tree's own git dir, which the remove deletes. Stamps are read by the commit they
  # name, never by the file they sit in (lib/proof.sh `_proof_records`), so the tree's are kept in the common git dir.
  gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)" && [ -f "$gd/bionic-stamps" ] && stamps="$(cat "$gd/bionic-stamps")"
  _wt_drop_legacy_link "$wt" || :
  if ! git -C "$root" worktree remove "$wt" >/dev/null 2>&1; then
    [ -n "$link_to" ] && [ ! -e "${wt}/.bionic" ] && ln -s "$link_to" "${wt}/.bionic" 2>/dev/null
    return 1
  fi
  [ -z "$stamps" ] || printf '%s\n' "$stamps" >> "$(git -C "$root" rev-parse --absolute-git-dir)/bionic-stamps" 2>/dev/null || :
  git -C "$root" worktree prune >/dev/null 2>&1
  # The row's tree event goes with the tree, best effort: the tree is already gone, and the landing it ended stands.
  [ -z "$plan" ] || worktree_tree_gone "$root" "" "$wt" "$plan" >/dev/null 2>&1 || :
}

# THE HAND LANDING'S LAST ACT (wave-28 T3, D9): as land ended its lease, the writer's tree goes once
# its row is published, and land's LANDED line says so. (A queue landing's tree goes at the stop:
# `worktree_remove_landed`, from `stop-orders.sh stopped`; wave-28 T6.)
_wt_hand_remove() {  # <tree abs> <root> <branch> <onto> <checkout> <published> <the run log it was written to>
  local wt="$1"
  _wt_tree_remove "$wt" "$2" || { _wt_refuse "worktree-remove-refused path=${wt} merged=${6}"; return 2; }
  _wt_say "LANDED branch=${3} onto=${4} checkout=${5} merge=${6} removed=${wt} proofs=${7}"
}

# THE TREE GOES AT THE STOP (wave-28 T6; D7, AC-3.2): `stop-orders.sh stopped <name>` removes the tree
# of a row whose roster line carries the landing's mark, once the row is closed. Only a linked tree of
# <root> (never the main checkout), only when its head is in the landed commit (a commit the writer
# made after its landing is never dropped from disk), and never the branch. Prints why when it keeps
# the tree. rc 0 removed · 1 no tree there · 2 kept.
worktree_remove_landed() {  # <root> <tree> <landed commit> -> 0 · 1 · 2
  local root="${1:-}" wt head c linked=""
  wt="$(_wt_abs "${2:-}" 2>/dev/null)" || return 1
  while IFS= read -r c; do
    [ "$(_wt_abs "$c" 2>/dev/null)" = "$wt" ] && linked=1
  done <<EOF
$(_wt_checkouts "$root" | tail -n +2 | cut -f2)
EOF
  [ -n "$linked" ] || { printf 'it is not a linked tree of %s' "$root"; return 2; }
  head="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)" || { printf 'its head cannot be read'; return 2; }
  git -C "$root" merge-base --is-ancestor "$head" "$3" 2>/dev/null \
    || { printf 'its head %.12s is not in the landed commit %.12s' "$head" "$3"; return 2; }
  _wt_tree_remove "$wt" "$root" || { printf 'git worktree remove refused it (changes in the tree?)'; return 2; }
}

# _wt_plan_current <plan> -> the run's step as the reader answers it, through lib/fill.sh (loaded lazily, as units.sh
# is for the landing record), its memo dropped first; 1 when the step cannot be read.
_wt_plan_current() {
  bionic_need fill.sh _fill_current_load || return 1
  fill_current_forget
  _fill_current_load "$1" || return 1
  printf '%s' "$_FILL_CURRENT_VALUE"
}

# THE LAUNCH LINE, by one key (`ready` reads `lands_on=` and the debt off it): the last `status=intended` roster row
# whose <key>= is <value> that no poker verb wrote. A row carrying `amended=`, `extended=`, `held=` or `adopted_from=` is a copy.
_wt_launch_row() {  # <roster> <key> <value> -> the line; 1 when none
  local roster="${1:-}" row
  [ -n "$3" ] && [ -f "$roster" ] && [ ! -L "$roster" ] || return 1
  row="$(awk -v k="|${2}=${3}|" '
    index($0, "roster-state/") != 1 { next }
    index($0 "|", k) && index($0, "|status=intended|") \
      && !index($0, "|amended=") && !index($0, "|extended=") && !index($0, "|held=") && !index($0, "|adopted_from=") { last = $0 }
    END { if (last != "") print last }' "$roster" 2>/dev/null)"
  [ -n "$row" ] || return 1
  printf '%s\n' "$row"
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

# A field is read by key through lib/fields.sh; lib/line.sh still calls `_wt_field`.
_wt_field() { line_field "$@"; }  # <line> <key>

# The discharge set: an ack, or a WAIVED, CLOSED or MET contract. hooks/stop-orders.sh and
# `stop_guard` (lib/stop.sh) discharge on an ack, a WAIVED contract or a MET one that declared
# a deliverable. `status=` is read as well
# as `state=` so a roster row that records its own closure is understood by the
# same predicate as a sweeper verdict line.
_wt_discharged() {  # <line>
  local v
  line_field_v v "$1" acked
  [ "$v" = "yes" ] && return 0
  line_field_v v "$1" state
  case "$v" in MET|CLOSED|WAIVED) return 0 ;; esac
  line_field_v v "$1" status
  case "$v" in MET|CLOSED|WAIVED) return 0 ;; esac
  return 1
}

_wt_row_discharged() {  # <file> <row name>
  local line name
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in '#'*) continue ;; esac
    line_field_v name "$line" name
    [ "$name" = "$2" ] || continue
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
# APPEND-ONLY, THE LAST LINE THAT COUNTS WINS. A second create for one name appends a second
# line; `workspace_for_name` returns the later tree, `workspaces_of_session` every tree in order.
#
# A PATH COUNTS ONLY WHERE GIT SAYS A TREE IS (wave-25 T18, critic C1, A-orch-36). The file sits
# in `.bionic/tmp`, and a script the permission hook never sees can append to it, so a line is
# a claim and git is the witness: the path counts only when `git worktree list` names it as a
# LINKED worktree of this repository, spelled exactly as git spells it, resolving physically to
# that same spelling, with the `.git` file a linked tree has. Never the main checkout or a
# directory above it. A line that does not count is skipped, so an earlier true line still
# answers: the rule only narrows. Decided by place, never by a prefix: `create` accepts any
# parent directory. A yes is exact (A-orch-29), so a `..`, a trailing slash or another letter
# case is refused even where it names the same tree. Git is asked once per answer, and not at
# all when no line could count; when it cannot be asked the answer is rc 2, never a path.
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
  local p
  bionic_need run.sh session_plan || return 1
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

# THE TREE MARKER (wave-34 T2; D11, REQ-1 AC-1.1). One line, the name of the writer a linked tree
# was created or re-dispatched for, at `<git-dir>/bionic-agent`: the tree's OWN git directory, so
# the main checkout, whose git directory is the common one, never carries one, and `git worktree
# remove` takes it with the tree. lib/gate.sh (THE PLACE) reads it as who asks when no name is
# carried. Written beside and renamed over, so a reader never meets half a name. Silent rc 0, or
# the reason on stdout and rc 1.
worktree_mark() {  # <tree> <name>
  local tree="${1:-}" name="${2:-}" gd
  _wt_workspace_value_bad "$name" && { printf 'invalid-name'; return 1; }
  gd="$(git_linked_dir "$tree")"
  case $? in 0) ;; 2) printf 'not-a-linked-worktree'; return 1 ;; *) printf 'not-a-tree'; return 1 ;; esac
  printf '%s\n' "$name" > "$gd/bionic-agent.$$" 2>/dev/null \
    && mv -f "$gd/bionic-agent.$$" "$gd/bionic-agent" 2>/dev/null \
    || { rm -f "$gd/bionic-agent.$$"; printf 'marker-unwritable'; return 1; }
}

# worktree_marker <tree> -> the name the tree's marker holds; rc 1 and nothing when it carries none (wave-35
# T7; D14). The dispatch wall asks it before `mark` rewrites the marker, so a tree whose recorded writer is
# still open on the roster is not handed to a second one (hooks/dispatch-preflight.sh, THE ROW'S LIVE WRITER).
worktree_marker() {  # <tree>
  local gd m=""
  gd="$(git -C "${1:-}" rev-parse --absolute-git-dir 2>/dev/null)" && [ -f "$gd/bionic-agent" ] || return 1
  IFS= read -r m < "$gd/bionic-agent" || [ -n "$m" ] || return 1
  [ -n "$m" ] && printf '%s' "$m"
}

# THE TREE'S OWN RECORD: identity from place. `spawn-worktree.sh create --for <name>` gives a linked tree one
# `tree/v1` line in its own git directory, `<git-dir>/bionic-tree`, beside the marker above:
#   tree/v1|path=<abs tree>|plan=<abs plan or none>|row=<id or ->|worker=<name>|spawned-by=<session>|at=<ISO-UTC>
# the plan the spawning session is bound to, the plan row whose agent cell holds the name when one does at spawn,
# the worker and the spawning session. It lives exactly as long as the tree (`git worktree remove` takes it, and no
# session's clear or state sweep can), so a landing needs no session that remembers the spawn: every reader
# of a tree asks it before any session's binding (lib/line.sh `line_tree_run`). The path is the key, read back and
# compared: a record that names another tree's path is no record of this one.
TREE_RECORD_SCHEMA="tree/v1"

_wt_tree_record_file() {  # <tree> -> <its own git-dir>/bionic-tree; rc 1 when <tree> is no linked tree
  local gd
  gd="$(git_linked_dir "${1:-}")" || return 1
  printf '%s/bionic-tree' "$gd"
}

# The plan's `## Tasks` row whose <column> cell is <value>, as units_rows prints it; rc 1 when none is.
_wt_row_where() {  # <plan> <column> <value>
  local rec
  [ -n "${3:-}" ] && [ -f "${1:-}" ] && bionic_need units.sh units_rows || return 1
  while IFS= read -r rec; do
    [ -n "$rec" ] && [ "$(units_field "$rec" "$2")" = "$3" ] || continue
    printf '%s\n' "$rec"; return 0
  done <<EOF
$(units_rows "$1" 2>/dev/null)
EOF
  return 1
}

# Write the record for <name>'s tree. Silent rc 0, or the reason on stdout and rc 1.
worktree_record_tree() {  # <root> <sid> <name> <abs tree>
  local root="${1:-}" sid="${2:-}" name="${3:-}" tree="${4:-}" f plan row="" rec v
  f="$(_wt_tree_record_file "$tree")" || { printf 'not-a-linked-worktree'; return 1; }
  plan="$(_wt_workspace_plan "$root" "$sid")" || { printf 'run-library-unloadable'; return 1; }
  [ "$plan" = none ] || ! bionic_need units.sh units_rows || { rec="$(_wt_row_where "$plan" agent "$name")" && row="$(units_field "$rec" id)"; }
  case "$row" in ''|*[[:space:]]*) row=- ;; esac
  for v in "$tree" "$plan" "$row" "$name" "$sid"; do
    _wt_workspace_value_bad "$v" && { printf 'tree-field-unrecordable'; return 1; }
  done
  printf '%s|path=%s|plan=%s|row=%s|worker=%s|spawned-by=%s|at=%s\n' "$TREE_RECORD_SCHEMA" \
    "$tree" "$plan" "$row" "$name" "$sid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$f.$$" 2>/dev/null \
    && mv -f "$f.$$" "$f" 2>/dev/null \
    || { rm -f "$f.$$"; printf 'tree-record-unwritable'; return 1; }
}

# A TREE MADE FOR A ROW IS ONE EVENT OF ITS RUN. The row is the one the name's brief was rendered from
# (`<record>/briefs/<name>.md`, whose mark names the row and the name), and the event is appended to that run's log
# through the one appender: the row, the tree's path from the root (as a Tasks cell spells it), its branch, its base
# and the name. A row's tree and base are read from it (lib/units.sh `_units_live`); no cell is written.
# THE ROW IS NEVER LOST IN SILENCE: a tree made for a row with no tree event would leave the commit gate and the
# landing unable to find the row of that writer's commits. So `create` asks first: a name the bound plan's rows
# claim by the dispatch rule (lib/fill.sh `fill_row_launched`) with no brief rendered for it is refused before
# anything is made; a name no row claims, or a session bound to no plan, is no row's and makes its tree with no event.
# worktree_tree_row <root> <sid> <name> -> the brief's row, rc 0; nothing and rc 1 for no row's;
#   the rows the name claims and rc 2 when it claims one and has no brief
worktree_tree_row() {
  local root="${1:-}" name="${3:-}" plan rec id hits=""
  plan="$(_wt_workspace_plan "$root" "${2:-}")" && [ "$plan" != none ] || return 1
  rec="$(_wt_proofs_path "$root" "$plan")" || return 1
  rec="${rec%/*}"
  if [ -f "$rec/briefs/$name.md" ]; then
    if bionic_need brief.sh brief_file_read; then
      brief_file_read "$root" "$rec/briefs/$name.md"
      if [ -n "$BRIEF_FILE_ROW" ] && [ "$BRIEF_FILE_NAME" = "$name" ]; then printf '%s' "$BRIEF_FILE_ROW"; return 0; fi
    fi
  fi
  bionic_need fill.sh fill_row_launched && bionic_need units.sh units_rows || return 1
  for id in $(units_rows "$plan" 2>/dev/null | cut -f1); do
    fill_row_launched "$id" "$name" && hits="${hits:+$hits,}$id"
  done
  [ -n "$hits" ] || return 1
  printf '%s' "$hits"; return 2
}
worktree_row_kind() {  # <plan> <row> -> the row's kind cell; nothing, rc 1, for a row the plan lacks
  local rec
  bionic_need units.sh units_rows && rec="$(_wt_row_where "${1:-}" id "${2:-}")" || return 1
  units_field "$rec" kind
}
# worktree_tree_event <root> <sid> <name> <abs tree | empty> <branch> <base sha> <row> [<plan>] -> the row's tree event
# appended to the log of <plan>, else of the session's bound run; rc 1 with nothing appended. An empty tree is the
# tree removed: the path and base empty, `why=removed`.
worktree_tree_event() {
  local root="${1:-}" tree="${4:-}" plan="${8:-}" rec
  [ -n "${7:-}" ] || return 1
  [ -n "$plan" ] || plan="$(_wt_workspace_plan "$root" "${2:-}")" || return 1
  [ "$plan" != none ] || return 1
  rec="$(_wt_proofs_path "$root" "$plan")" || return 1
  bionic_need log.sh log_append || return 1
  [ -n "$tree" ] || { RUN_LOG="$rec" log_append tree "row=$7" path= "branch=${5:-}" base= "by=${3:-}" why=removed; return; }
  RUN_LOG="$rec" log_append tree "row=$7" "path=$(_wt_tree_rel "$root" "$tree")" "branch=${5:-}" "base=${6:-}" "by=${3:-}"
}
_wt_tree_rel() {  # <root> <abs tree> -> the tree from the root, as a tree event names it
  local rp tree="${2:-}"
  rp="$(cd "${1:-}" 2>/dev/null && pwd -P)" || rp="${1:-}"
  case "$tree" in "$rp"/*) tree="${tree#"$rp"/}" ;; "$1"/*) tree="${tree#"$1"/}" ;; esac
  printf '%s' "$tree"
}
_wt_tree_record_plan() {  # <abs tree> -> the plan its own record names, read before the tree goes; nothing for none
  local l
  l="$(worktree_tree_record "${1:-}" 2>/dev/null)" || return 0
  l="$(line_field "$l" plan)"; [ "$l" = none ] || printf '%s' "$l"
}
# A TREE REMOVED IS NO ROW'S TREE: each row whose latest tree event names it gets the event again with an empty path,
# through the one writer above, in <plan> (the tree's own record's, read before the removal) or the session's bound
# run. rc 0 with nothing to write, 1 when a removal could not be written.
worktree_tree_gone() {  # <root> <sid> <abs tree> [<plan>]
  local root="${1:-}" plan="${4:-}" t rel row branch by rc=0
  [ -n "$plan" ] || plan="$(_wt_workspace_plan "$root" "${2:-}")" || return 1
  [ "$plan" != none ] || return 0
  bionic_need reader.sh reader_trees || return 1
  t="$(reader_trees "$plan")" || return 1
  rel="$(_wt_tree_rel "$root" "${3:-}")"
  while IFS=$'\t' read -r row branch by; do
    [ -n "$row" ] || continue
    worktree_tree_event "$root" "${2:-}" "$by" "" "$branch" "" "$row" "$plan" || rc=1
  done <<TREES
$(printf '%s\n' "$t" | awk -F'|' -v p="$rel" "$_READER_AWK"'{ q = line_kv("path"); sub(/\/$/, "", q) }
  q != "" && q == p { print line_kv("row") "\t" line_kv("branch") "\t" line_kv("by") }')
TREES
  return "$rc"
}

# worktree_tree_record <tree> -> the tree's record line; rc 1 when it carries none of its own.
worktree_tree_record() {  # <tree>
  local tree f line=""
  tree="$(_wt_abs "${1:-}")" || return 1
  f="$(_wt_tree_record_file "$tree")" && [ -f "$f" ] && [ ! -L "$f" ] || return 1
  IFS= read -r line < "$f" || [ -n "$line" ] || return 1
  line="${line%$'\r'}"
  case "$line" in "${TREE_RECORD_SCHEMA}|"*) : ;; *) return 1 ;; esac
  [ "$(line_field "$line" path)" = "$tree" ] || return 1
  printf '%s\n' "$line"
}

# A ROW'S TREE BY THE PLAN'S TABLE: the `worktree` cell of the `## Tasks` row whose agent cell is <name>, in the plan
# each <sid> in turn is bound to, the first that names one. It is printed whether or not a tree stands there, so the
# caller can say where it looked. rc 1 when no bound plan names a tree for the name. The session's workspace record
# answers a tree its own carrier made; this answers one a predecessor made, which the record of no live session holds.
worktree_for_agent() {  # <root> <name> <sid>...
  local root="${1:-}" name="${2:-}" s plan rec
  shift 2
  bionic_need units.sh units_rows || return 1
  for s in "$@"; do
    [ -n "$s" ] || continue
    plan="$(_wt_workspace_plan "$root" "$s")" && [ "$plan" != none ] || continue
    rec="$(_wt_row_where "$plan" agent "$name")" || continue
    _wt_cell_tree "$root" "$(units_field "$rec" worktree)" && return 0
  done
  return 1
}

# rc 0 when no component of the absolute <path> is a symbolic link, so the path is its own
# physical name. Read with `[ -L ]` per component rather than `_wt_abs`, which costs a subshell
# per candidate on the permission hook's path; the two agree here because a candidate has
# already matched git's spelling exactly, and git records a tree by its physical path (measured
# on git 2.50: a tree added through /tmp is listed under /private/tmp), with no `.` or `..`.
_wt_unlinked_path() {  # <absolute path>
  local rest="${1#/}" at=""
  while [ -n "$rest" ]; do
    at="${at}/${rest%%/*}"
    [ -L "$at" ] && return 1
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
  done
  return 0
}

# The candidates that count, by the rule above: every one in order (<all> 1) or the last
# (<all> 0). 0 printed, 1 none counts, 2 git cannot be asked.
_wt_listed_trees() {  # <root> <candidate paths, one per line> <all: 1 or 0>
  local listed main="" linked="" first=1 ref path p last="" nl=$'\n'
  listed="$(_wt_checkouts "$1")" || return 2
  while IFS=$'\t' read -r ref path; do
    if [ "$first" = 1 ]; then main="$path"; first=0; continue; fi
    linked="${linked}${path}${nl}"
  done <<< "$listed"
  while IFS= read -r p; do
    case "${nl}${linked}" in *"${nl}${p}${nl}"*) : ;; *) continue ;; esac
    case "${main}/" in "${p}"/*) continue ;; esac
    [ -d "$p" ] && [ -f "${p}/.git" ] || continue
    _wt_unlinked_path "$p" || continue
    if [ "$3" = 1 ]; then printf '%s\n' "$p"; fi
    last="$p"
  done <<< "$2"
  [ -n "$last" ] || return 1
  [ "$3" = 1 ] || printf '%s\n' "$last"
}

# Both readers in one walk, read by key. A line is a candidate when it is this schema, names
# THIS session (the file name alone is not trusted for that) and carries an absolute path; a
# CRLF ending is translated, never kept in the path. A candidate counts by `_wt_listed_trees`.
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
      if (all == "1" || (hn && n == want)) print p
    }' "$f" 2>/dev/null)" || return 2
  [ -n "$out" ] || return 1
  _wt_listed_trees "$1" "$out" "$4"
}

workspace_for_name() {  # <root> <sid> <name> -> the last tree recorded for <name>; 1 none, 2 refused
  [ -n "${3:-}" ] || return 1
  _wt_workspace_paths "${1:-}" "${2:-}" "$3" 0
}

workspaces_of_session() {  # <root> <sid> -> every tree recorded, one per line; 1 none, 2 refused
  _wt_workspace_paths "${1:-}" "${2:-}" "" 1
}

