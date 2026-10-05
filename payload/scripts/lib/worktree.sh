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

# The D1 predicate. Prints `pid=<pid> cwd=<cwd> script=<path>` for the first runner that
# satisfies it and returns 0; returns 1 when none does. A working directory that could not
# be read prints `unreadable`. The script is `_wt_runner_script`'s word, taken against the
# working directory when it is relative, with its directory made physical, so a symlinked
# spelling (`/tmp` for `/private/tmp`) still compares. A candidate whose script cannot be
# resolved to a file is not a runner: no opinion, as for an unreadable process.
_wt_busy_suite() {  # <main-root> [target-checkout] -> pid=... cwd=... script=...
  local root="${1:-}" co="${2:-}" pids cwds pid cmd cwd script dir
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
      printf 'pid=%s cwd=%s script=%s' "$pid" "${cwd:-unreadable}" "$script"
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
# Two refusals can only be known after the merge, `onto-moved` and `branch-moved`
# (review 7 F8, F9); each undoes the merge first, so it leaves the same state. The
# exception is a refusal that says `undo=failed` (review 11 S1): the undo declined, because
# a commit sits on the merge or a change in the checkout touches a file the merge brought,
# so the merge stands on <onto>, the tree is kept, and the line prints the one fix that
# removes nothing but the merge.
#
# THE LANDING RULE (wave-26 D7, as ruled in A-orch-26). A tree lands on its own
# green run. It must first contain what landed since it branched only where that
# landed work touches a file the tree also changed: `not-current` names those
# files (`_wt_not_current`). `stale-proof` unless, for every suite stamped at the
# tree's head in its stamp file (`<git-dir>/bionic-stamps`, written by the booking
# shim), the newest stamp of that suite is green on a clean tree (T61; see
# `_wt_stale_proof`). No stamp file at all means no suite-class command ever ran
# in the tree, and is not refused. The head of <onto> is read
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

# THE STALE-PROOF READ (wave-26 D7; T61, critic F1). Reads EVERY line of the tree's stamp file,
# `stamp/v1|head=<40-hex>|dirty=<count>|rc=<n>|at=<ISO-UTC>[|suites=<names>]|cmd=<...>`, appended
# by the booking shim to `<the tree's git dir>/bionic-stamps`, one line per suite-class command.
# Prints the reason and the fix and returns 0 when the tree's runs are not proof for <head>.
# Returns 1 when they are — and when there is no stamp file, which means no suite-class command
# ever ran in the tree. On 1 it prints, byte for byte from this one read, the stamp lines at <head>
# it judged (none without a file): the land keeps those, and not a second read of a file a suite
# may append to in between (wave-27 T44).
#
# THE RULE: for EVERY suite stamped at <head>, the NEWEST stamp of that suite is green proof (rc 0
# on a clean tree). The doctrine runs a brief's suites one call each, so one head collects one line
# per suite; before T61 only the last line was read, and suite a red then suite b green LANDED.
#   - `suites=` names the basenames a line ran, comma-joined (the wall's names, booked.sh). A line
#     naming two suites has one exit code, so it speaks for both: red, both are red; green, both
#     are green.
#   - A line with no `suites=` (an older shim's) or a `?` in it is a run the land cannot keep apart
#     from any suite. A red or dirty one at <head> refuses, and NO later run at <head> clears it:
#     the fix is a commit, then the suites again. A green one asks nothing.
#   - Lines on another head are history. A file with lines and none at <head> is `why=head`, naming
#     the newest line's head, the head looked for and the stamp file read (A-orch-55).
#   - The NEWEST line must be readable, as before: an empty file, or a last line that is no stamp,
#     is `why=unreadable`. An unreadable line before it is no run's record (the shim writes none)
#     and is skipped.
# Failures are named in the order the suites first appear at <head>, dirty before red.
#   - A DECLARED RED (wave-27 T31; D23): with a <declared suite>, a red (not dirty) newest stamp of
#     exactly that suite is not a failure; the proof then prints `landed-red=<suite>` as its first
#     line, ahead of the judged lines, and `land` holds the declaration's evidence to <head>. A
#     second red suite is refused as any red is.
#
# `cmd=` is the last field and free text, so each line's read STOPS there (review 2 F2): what
# follows is the command, whatever it contains, and a `|rc=0` in it never speaks for the run.
# Before `cmd=`, each of head, dirty and rc appears exactly once and suites at most once; a line
# giving one twice is no line the shim writes. ONE awk over the file, whatever its length.
_wt_stale_proof() {  # <worktree abs> <head> [<declared suite>] -> why=... | the judged lines
  local wt="${1:-}" head="${2:-}" okred="${3:-}" gd file verdict what n s judged lr nl='
'
  local again="re-run the tree's suites at its head, land again"
  gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)"
  [ -n "$gd" ] || { printf 'why=unreadable stamps=%s/<no git dir> — %s' "$wt" "$again"; return 0; }
  file="${gd}/bionic-stamps"
  [ -e "$file" ] || [ -L "$file" ] || return 1
  verdict="$(awk -v want="$head" -v okred="$okred" '
    { last_ok = 0 }
    substr($0, 1, 9) != "stamp/v1|" { next }
    {
      nf = split($0, f, "|"); h = d = r = s = ""; nh = nd = nr = ns = 0
      for (i = 2; i <= nf; i++) {
        if (substr(f[i], 1, 4) == "cmd=") break
        if (substr(f[i], 1, 5) == "head=")        { h = substr(f[i], 6); nh++ }
        else if (substr(f[i], 1, 6) == "dirty=")  { d = substr(f[i], 7); nd++ }
        else if (substr(f[i], 1, 3) == "rc=")     { r = substr(f[i], 4); nr++ }
        else if (substr(f[i], 1, 7) == "suites=") { s = substr(f[i], 8); ns++ }
      }
      if (nh != 1 || nd != 1 || nr != 1 || ns > 1) next
      if (h == "" || d == "" || r == "" || (h d r) ~ /[^0-9a-f]/) next
      last_ok = 1; last_head = h
      if (h != want) next
      at_head++
      judged = judged $0 "\n"
      proof = (d == "0" && r == "0")
      if (s == "") s = "?"
      m = split(s, names, ",")
      for (j = 1; j <= m; j++) {
        x = names[j]; if (x == "") x = "?"
        if (!(x in seen)) { seen[x] = 1; order[++no] = x }
        if (x == "?") { if (!proof && !(x in state)) state[x] = d " " r }
        else state[x] = d " " r
      }
    }
    END {
      if (NR == 0 || !last_ok) { print "unreadable"; exit }
      if (at_head == 0) { print "head " last_head; exit }
      for (k = 1; k <= no; k++) {
        x = order[k]
        if (!(x in state)) continue
        split(state[x], v, " ")
        if (v[1] != "0") { print "dirty " v[1] " " x; exit }
        if (v[2] != "0") { if (okred != "" && x == okred) { lr = x; continue } print "red " v[2] " " x; exit }
      }
      printf "proof%s\n%s", (lr != "" ? " " lr : ""), judged
    }' "$file" 2>/dev/null)"
  judged=""
  case "$verdict" in *"$nl"*) judged="${verdict#*"$nl"}"; verdict="${verdict%%"$nl"*}" ;; esac
  what="${verdict%% *}"; n="${verdict#* }"; s="${n#* }"; n="${n%% *}"
  local fix_dirty="commit or clean the tree, $again" fix_red="make the suites green, $again"
  if [ "$s" = "?" ]; then
    fix_dirty="this run names no suite, so no later run at this head clears it: commit, then re-run the tree's suites at the new head, land again"
    fix_red="$fix_dirty"
  fi
  case "$what" in
    proof)
      lr=""; case "$verdict" in "proof "?*) lr="${verdict#proof }" ;; esac
      [ -z "$lr" ] || printf 'landed-red=%s\n' "$lr"
      [ -z "$judged" ] || printf '%s\n' "$judged"; return 1 ;;
    head)  printf 'why=head stamp_head=%s head=%s stamps=%s — %s' "$n" "$head" "$file" "$again" ;;
    dirty) printf 'why=dirty dirty=%s suite=%s head=%s — %s' "$n" "$s" "$head" "$fix_dirty" ;;
    red)   printf 'why=red rc=%s suite=%s head=%s — %s' "$n" "$s" "$head" "$fix_red" ;;
    *)     printf 'why=unreadable stamps=%s — %s' "$file" "$again" ;;
  esac
  return 0
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

# THE UNDO OF A MERGE A LAND MUST NOT KEEP (review 7 F8, F9; review 11 B1). Only the land's own
# merge is undone (its second parent is the head the land merged), and <onto> moves back by
# compare-and-swap: `update-ref <ref> <first parent> <merge>` moves it only if it still holds the
# merge, in one locked step, so a commit made on top of the merge at any instant stays on the
# branch and the undo declines. The checkout then follows with a two-tree `read-tree -m -u`, which
# keeps every uncommitted change, a staged one staged, and refuses rather than overwrite a file
# the merge touched and someone changed since; on that refusal the swap is reversed, again only
# if nothing moved the branch meanwhile. Returns 1, the merge left standing, when any step declines.
# A COMMIT MADE DURING THE UNDO (review 15 F1). Between the swap and the checkout's `read-tree`
# the checkout still holds the merge's tree while its branch sits on the first parent, so a
# commit made there carries the task's changes onto <onto>, unjudged. The branch is read once
# more on the way out, after the checkout followed and after a reverse swap that failed; a head
# that is not where the undo left it is printed, with 3 (the checkout followed, so its index has
# the task's changes taken out again) or 4 (it did not). A commit made after the checkout
# followed, which changes no file the merge changed, carries nothing of the task: the undo stands.
# A BRANCH NO CHECKOUT HOLDS (review 16 S1). When the checkout left <onto> after the merge and no
# other checkout holds it, its tree is nobody's working files: the compare-and-swap alone is the
# undo. A branch some other checkout holds is never moved under it; the undo declines.
_wt_undo_merge() {  # <checkout> <onto> <merge sha> <first parent> <head merged> -> [arrived sha]
  local ref="refs/heads/${2:-}" at held nl='
'
  [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ -n "${4:-}" ] && [ -n "${5:-}" ] || return 1
  [ "$(git -C "$1" rev-parse --verify --quiet "${3}^2" 2>/dev/null)" = "$5" ] || return 1
  if [ "$(git -C "$1" symbolic-ref --quiet HEAD 2>/dev/null)" != "$ref" ]; then
    held="$(_wt_checkouts "$1")" || return 1
    case "${nl}${held}" in *"${nl}${ref}"$'\t'*) return 1 ;; esac
    git -C "$1" update-ref -m "land: undo ${3}" "$ref" "$4" "$3" >/dev/null 2>&1 || return 1
    return 0
  fi
  git -C "$1" update-ref -m "land: undo ${3}" "$ref" "$4" "$3" >/dev/null 2>&1 || return 1
  git -C "$1" update-index -q --refresh >/dev/null 2>&1
  if git -C "$1" read-tree -m -u "$3" "$4" >/dev/null 2>&1; then
    at="$(git -C "$1" rev-parse --verify --quiet "$ref" 2>/dev/null)"
    [ "$at" = "$4" ] && return 0
    [ -n "$at" ] && ! _wt_shares_a_file "$1" "$4" "$3" "$at" && return 0
    printf '%s' "${at:-<none>}"; return 3
  fi
  git -C "$1" update-ref -m "land: undo refused, ${3} restored" "$ref" "$3" "$4" >/dev/null 2>&1 && return 1
  at="$(git -C "$1" rev-parse --verify --quiet "$ref" 2>/dev/null)"
  case "$at" in "$3"|"$4") return 1 ;; esac
  printf '%s' "${at:-<none>}"; return 4
}

# Whether <b> and <c> each change, against <base>, a file in common. Unreadable reads as yes.
_wt_shares_a_file() {  # <checkout> <base> <b> <c>
  local nl='
' one two f
  one="$(git -C "$1" diff --no-renames --name-only "$2" "$3" 2>/dev/null)" \
    && two="$(git -C "$1" diff --no-renames --name-only "$2" "$4" 2>/dev/null)" || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "${nl}${two}${nl}" in *"${nl}${f}${nl}"*) return 0 ;; esac
  done <<EOF
$one
EOF
  return 1
}

# THE LAND'S OWN MERGE (review 11 S1; review 16 B1). Bounded by what the land itself saw, never a
# search of history for a likely merge: <ref> is what the checkout's HEAD named just before
# `git merge`, <pre> the commit it held then, and the caller looks only when `git merge` said it
# made a merge. The land's merge is the newest first-parent commit of <ref> past <pre> whose
# second parent is the head merged: a commit another writer made on top in the instant after
# leaves it found, and a merge of that head someone else made earlier is never past <pre>.
# Prints the merge and its first parent; empty when <ref> holds none.
_wt_own_merge() {  # <checkout> <ref> <pre> <head merged> -> "<sha> <first parent>"
  local c p1 p2 more
  while read -r c p1 p2 more; do
    [ "$p2" = "$4" ] && [ -z "$more" ] && { printf '%s %s' "$c" "$p1"; return 0; }
  done <<EOF
$(git -C "$1" rev-list --first-parent --parents "${3}..${2}" 2>/dev/null)
EOF
  return 1
}

# WHAT TO DO WHEN THE UNDO DECLINED (review 11 S1): a reset only while <onto> still sits on the
# land's merge, since then it removes that merge and nothing else; under a later commit, the revert
# that takes the merge's changes out and keeps that commit; never a reset past another writer's work.
# THE RESET ONLY WHERE IT MOVES <onto> (review 15 F2): typed in a checkout that is detached or on
# another branch, a reset moves that instead, so there the advice moves <onto> itself, by the same
# compare-and-swap the undo uses, and names the checkout's state.
_wt_undo_failed_fix() {  # <checkout> <onto> <merge sha or empty> <first parent>
  local at on
  at="$(git -C "$1" rev-parse --verify --quiet "refs/heads/${2}" 2>/dev/null)"
  if [ -n "$3" ] && [ "$at" = "$3" ]; then
    on="$(git -C "$1" symbolic-ref --quiet HEAD 2>/dev/null)"
    if [ "$on" = "refs/heads/${2}" ]; then
      printf 'the merge stands: reset %s to %s in %s by hand' "$2" "${4:-its first parent}" "$1"
    else
      if [ -n "$on" ]; then on="on ${on#refs/heads/}"; else on="detached"; fi
      printf 'the merge stands and %s is %s, not on %s, so move the branch itself: git -C %s update-ref refs/heads/%s %s %s' \
        "$1" "$on" "$2" "$1" "$2" "${4:-<first parent>}" "$3"
    fi
  elif [ -n "$3" ] && git -C "$1" merge-base --is-ancestor "$3" "refs/heads/${2}" 2>/dev/null; then
    printf 'the merge stands under a later commit: git -C %s revert -m 1 %s' "$1" "$3"
  else
    printf 'the merge is not on %s any more: nothing to undo' "$2"
  fi
}

# WHAT TO SAY WHEN A COMMIT ARRIVED DURING THE UNDO (review 15 F1): the commit, that it may carry
# the task's changes unjudged, and the way to take them out: the checkout's own staged change when
# it followed the branch back, the reverse of the merge's changes otherwise.
_wt_undo_arrival_fix() {  # <checkout> <onto> <merge sha> <first parent> <arrived sha> <3|4>
  printf 'commit %s arrived on %s during the undo, made while %s held merge %s, so it may carry the task'"'"'s changes, unjudged; ' \
    "$5" "$2" "$1" "$3"
  if [ "$6" = 3 ]; then
    printf '%s has them taken out, staged: review git -C %s diff --cached and commit it, or re-judge %s at %s' "$1" "$1" "$2" "$5"
  else
    printf 'take them out (git -C %s diff %s %s is that change) or re-judge %s at %s' "$1" "$3" "$4" "$2" "$5"
  fi
}

worktree_land() {  # <worktree path> <onto> [<bound plan>] [<lands_red> <red_evidence>] -> LANDED | REFUSED
  local target="${1:-}" onto="${2:-}" wt_abs root branch co ahead busy merge_sha rc
  local dirt onto_head head why link_to overlap now parent tip moved fix undo_on arrived
  local pre pre_ref was said held now_ref check_cmd check_out nl='
'
  local plan="${3:-}" judged proofs proofs_row
  local lands_red="${4:-}" red_ev="${5:-}" landed_red="" ev_heads judged_cur landed_at red_said

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

  # THE RUN HAS BEEN JUDGED FOR INTEGRATION (wave-27 T31; review pass 25 F3). `current 8` admits
  # integration on the judge at the working head; a landing after it would move the working branch
  # past the head that was judged, and nothing would judge it again. So with a bound plan at
  # `current: 8` or later (its letter dropped) nothing lands: the step is set back first, which the
  # `current` verb allows (`current 7`, dry-committed at 7 like any move).
  if [ -n "$plan" ]; then
    judged_cur="$(_wt_plan_current "$plan")"
    case "${judged_cur%[ab]}" in
      8|9) _wt_refuse "past-judgment why=current-${judged_cur} plan=${plan} — the run has been judged for integration at current: ${judged_cur}, and a landing would move the working branch past the head that was judged; set the step back (session-poker.sh current 7), land again"; return 2 ;;
    esac
  fi

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

  why="$(_wt_stale_proof "$wt_abs" "$head" "${lands_red%% until *}")" && {
    _wt_refuse "stale-proof ${why}"; return 2
  }
  judged="$why"

  # A DECLARED RED (wave-27 T31; REQ-14, D23). The row's launch line carried `lands_red=<suite>
  # until <token>` and `red_evidence=<path>` (worktree_land_for_session reads them), and the proof
  # above accepted a red newest run of exactly that suite with every other suite green. It lands
  # only beside its evidence: the file exists and holds a line `head: <the tree's head>`, so the
  # red it explains is this head's. A relative path is read from the project root, a `record/…`
  # one from the docs root, as proof-add reads one.
  case "$judged" in
    landed-red=*)
      landed_red="${judged%%"$nl"*}"; landed_red="${landed_red#landed-red=}"
      case "$judged" in *"$nl"*) judged="${judged#*"$nl"}" ;; *) judged="" ;; esac
      case "$red_ev" in
        /*) : ;;
        record/*) red_ev="$(docs_root "$root")/${red_ev}" ;;
        *) red_ev="${root}/${red_ev#./}" ;;
      esac
      if [ ! -f "$red_ev" ]; then
        _wt_refuse "stale-proof why=red-evidence suite=${landed_red} head=${head} evidence=${red_ev} — the declared red of ${landed_red} lands only beside its evidence, and that file is missing; write it with a line head: ${head}, land again"; return 2
      fi
      ev_heads="$(awk '/^head:[ \t]*[0-9a-f]+[ \t]*$/ { sub(/^head:[ \t]*/, ""); sub(/[ \t]*$/, ""); print }' "$red_ev" 2>/dev/null)"
      if case "${nl}${ev_heads}${nl}" in *"${nl}${head}${nl}"*) false ;; *) true ;; esac; then
        _wt_refuse "stale-proof why=red-evidence suite=${landed_red} head=${head} evidence=${red_ev} found=$(printf '%s' "${ev_heads:-none}" | tr '\n' ',') — the declared red of ${landed_red} lands only beside evidence naming this head, and ${red_ev} names none that is; write head: ${head} in it, land again"; return 2
      fi ;;
  esac

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

  # THE PROJECT'S DECLARED CHECK (wave-27 T16; D12). When `.bionic/config.yaml` names
  # `release-check: <command>`, the command runs over this landing's range before anything is
  # touched: in the TARGET checkout as it stands before the merge, never the task's tree (review
  # pass 22 B1; A-orch-75), so a command naming its script relatively runs the target's copy and a
  # piece cannot rewrite the check that judges it; the task's commits are read from the shared
  # object store. BIONIC_CHECK_BASE is the working branch's head and BIONIC_CHECK_HEAD the task's
  # head, its words split on blanks with globbing off, as
  # `impact-command:` is run (proof.sh `_proof_map`). A non-zero exit refuses the landing and
  # shows the command's output on stderr. With no key nothing runs and nothing prints.
  check_cmd="$(config_value "$root" release-check "" 2>/dev/null)"
  if [ -n "$check_cmd" ]; then
    check_out="$(cd "$co" 2>/dev/null || exit 1
      set -f
      export BIONIC_CHECK_BASE="$onto_head" BIONIC_CHECK_HEAD="$head"
      # shellcheck disable=SC2086  # the configured command splits on blanks, as impact-command does
      exec $check_cmd </dev/null 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then
      [ -z "$check_out" ] || printf '%s\n' "$check_out" >&2
      _wt_refuse "check-failed why=release-check rc=${rc} branch=${branch} base=${onto_head} head=${head} — the project's declared release-check (${check_cmd}) fails over this landing's range; fix what it names on ${branch}, re-run its suites, land again"; return 2
    fi
  fi

  # THE LANDING RECORD IS PROVED WRITABLE BEFORE THE MERGE (wave-27 T44; D15). With a bound plan,
  # the run's `landing-proofs.log` is created or opened for append here, and a record that cannot
  # be is refused with nothing changed. The row is the plan's `## Tasks` row whose `worktree` cell
  # names this tree. Both are written once the merge is made (_wt_proofs_append, below).
  proofs="none"; proofs_row=""
  if [ -n "$plan" ]; then
    proofs="$(_wt_proofs_path "$root" "$plan")" && mkdir -p "${proofs%/*}" 2>/dev/null \
      && { : >> "$proofs"; } 2>/dev/null || {
      _wt_refuse "record-unwritable why=proofs-unwritable path=${proofs:-<none>} branch=${branch} — the landing record cannot be written, so nothing is merged; make it writable, land again"; return 2
    }
    proofs_row="$(_wt_proofs_row "$root" "$plan" "$wt_abs")"
  fi

  # THE HEAD IS READ AGAIN JUST BEFORE THE MERGE (review 2 F7). Another land onto
  # <onto> may have gone through since the read above; if the head moved, the
  # not-current decision is taken again against the head the merge will meet.
  # A move after this read is caught once the merge is made, below.
  now="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${onto}" 2>/dev/null)"
  if [ "$now" != "$onto_head" ]; then
    onto_head="$now"
    overlap="$(_wt_not_current "$root" "$onto_head" "$head")" && {
      _wt_refuse_not_current "$branch" "$onto" "$onto_head" "$overlap"; return 2
    }
  fi

  # WHAT THE CHECKOUT HOLDS AS `git merge` RUNS (review 16 B1, S1): the commit and the ref its HEAD
  # names, in one read just before the merge. The land's merge is looked for on that ref past that
  # commit (_wt_own_merge), and is undone there, whatever the checkout does after.
  pre="$(git -C "$co" rev-parse HEAD --symbolic-full-name HEAD 2>/dev/null)"
  pre_ref="${pre#*"$nl"}"; pre="${pre%%"$nl"*}"
  case "${pre}:${pre_ref}" in
    *[!0-9a-f]*:*|:*) was="" ;;
    *:HEAD) was="<detached>" ;;
    *:refs/heads/?*) was="${pre_ref#refs/heads/}" ;;
    *) was="" ;;
  esac
  [ -n "$was" ] || { _wt_refuse "onto-checkout-unreadable checkout=${co} branch=${onto}"; return 2; }

  # --no-ff ALWAYS: a fast-forward would erase the fact that this was a task,
  # and the merge commit is what the ledger row points at. The head merged is
  # the one judged above, not whatever the branch holds by now. `git merge` says
  # so when it had nothing to do (the C locale fixes the words): then it made no
  # commit, and none is looked for.
  if ! said="$(LC_ALL=C git -C "$co" merge --no-ff -m "merge ${branch} (land)" "$head" 2>/dev/null)"; then
    git -C "$co" merge --abort >/dev/null 2>&1
    _wt_refuse "merge-failed branch=${branch} onto=${onto} checkout=${co}"; return 2
  fi
  merge_sha=""
  case "$said" in "Already up"*) : ;; *) merge_sha="$(_wt_own_merge "$co" "$pre_ref" "$pre" "$head")" ;; esac
  parent="${merge_sha#* }"; merge_sha="${merge_sha%% *}"

  # NO MERGE THIS LAND CAN PROVE ITS OWN (review 16 B1). `git merge` had nothing to do, or merged
  # somewhere other than the ref the checkout named just before it. Either way a merge of <head>
  # that now stands anywhere is not provably this land's, so nothing is undone, and the line says
  # what the checkout held and what it holds now.
  if [ -z "$merge_sha" ]; then
    case "$said" in "Already up"*)
      if [ "$was" = "$onto" ]; then fix="land again"; else fix="check out ${onto} in ${co}, land again"; fi
      _wt_refuse "merge-unproven branch=${branch} onto=${onto} checkout=${co} was_on=${was} was_at=${pre} — ${co}'s HEAD already held ${head} when git merge ran, so it made no merge, and nothing is undone; ${fix}"; return 2 ;;
    esac
    if [ "$was" = "<detached>" ]; then held="${co}'s HEAD"; else held="$was"; fi
    now="$(git -C "$co" rev-parse HEAD --symbolic-full-name HEAD 2>/dev/null)"
    now_ref="${now#*"$nl"}"; now="${now%%"$nl"*}"
    case "${now}:${now_ref}" in
      *[!0-9a-f]*:*|:*) now="<unreadable>"; now_ref="<unreadable>" ;;
      *:refs/heads/?*) now_ref="${now_ref#refs/heads/}" ;;
      *) now_ref="<detached>" ;;
    esac
    if [ "$now_ref" = "$onto" ]; then fix="land again"; else fix="check out ${onto} in ${co}, land again"; fi
    _wt_refuse "merge-unproven branch=${branch} onto=${onto} checkout=${co} was_on=${was} was_at=${pre} now_on=${now_ref} now_at=${now} — ${held} holds no merge of ${head} made past ${pre}, where ${co} stood just before git merge, so no merge git made is provably this land's, and nothing is undone; if ${now} holds ${head}, that merge is unjudged: take it out by hand, then ${fix}"; return 2
  fi

  # A DETACHED CHECKOUT (review 16 S1): the merge is on a HEAD no branch holds, so there is no
  # branch to move back and nothing is undone; once the checkout is on <onto> the merge is no
  # branch's commit.
  if [ "$was" = "<detached>" ]; then
    _wt_refuse "onto-detached branch=${branch} onto=${onto} checkout=${co} merge=${merge_sha} — the merge is on ${co}'s detached HEAD and no branch holds it, so nothing is undone; check out ${onto} in ${co} (the merge then belongs to no branch), land again"; return 2
  fi

  # THE MERGE WENT WHERE THE CHECKOUT WAS (review 15 F3). `git merge` merges onto the checkout's
  # HEAD, so a checkout switched to another branch after the clean check takes the merge there,
  # and it is undone there.
  undo_on="$was"

  # THE MERGE IS CHECKED AGAINST WHAT WAS JUDGED (review 7 F8, F9). `git merge` reads the
  # head of <onto> for itself, after the read above, and merges onto whatever it finds: a land
  # onto the same branch that completed in between is merged onto unjudged, with rc 0. So the
  # merge commit's first parent must be the onto head that was judged. And the tree's branch
  # must still hold the head that was merged: a commit its writer added since would be left
  # unlanded on a branch whose tree is about to go. Either way this land's merge is undone,
  # which moves <onto> back to the head another writer gave it, and the tree is kept.
  tip="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${branch}" 2>/dev/null)"
  moved=""
  if [ "$undo_on" != "$onto" ]; then
    moved="onto-switched branch=${branch} onto=${onto} checkout=${co} merged_into=${undo_on}"
    fix="check out ${onto} in ${co}, land again"
  elif [ "$parent" != "$onto_head" ]; then
    moved="onto-moved branch=${branch} onto=${onto} judged=${onto_head} merged_onto=${parent:-<none>}"
    fix="land again to judge the head ${onto} holds now"
  elif [ "$tip" != "$head" ]; then
    moved="branch-moved branch=${branch} judged=${head} branch_head=${tip:-<none>}"
    fix="re-run the tree's suites at its head, land again"
  fi
  if [ -n "$moved" ]; then
    arrived="$(_wt_undo_merge "$co" "$undo_on" "$merge_sha" "$parent" "$head")"; rc=$?
    case $rc in
      0)
        if [ "$undo_on" != "$onto" ]; then
          _wt_refuse "${moved} merge=${merge_sha} — the merge is undone on ${undo_on} and the tree kept; ${fix}"; return 2
        fi
        _wt_refuse "${moved} — the merge is undone and the tree kept; ${fix}"; return 2 ;;
      3|4)
        _wt_refuse "${moved} merge=${merge_sha} undo=failed arrived=${arrived} — $(_wt_undo_arrival_fix "$co" "$undo_on" "$merge_sha" "$parent" "$arrived" "$rc"), then ${fix}"; return 2 ;;
    esac
    _wt_refuse "${moved} merge=${merge_sha:-<none>} undo=failed — $(_wt_undo_failed_fix "$co" "$undo_on" "$merge_sha" "$parent"), then ${fix}"; return 2
  fi

  # THE LANDING KEEPS THE PROOF IT READ (wave-27 T44; D15): the header and the stamp lines judged
  # at <head>, appended before the tree and its stamps go. The merge is not undone if the append
  # fails; the tree is kept instead, so its stamp file still holds the proof.
  # ONE INSTANT FOR THE LANDING (wave-27 T31; A-orch-85): the record's `at=` and, for a declared
  # red, the `landed-red-at=` the orchestrator copies onto the `landed red: … at <ISO-UTC>` line.
  landed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  red_said=""; [ -z "$landed_red" ] || red_said=" landed-red=${landed_red} landed-red-at=${landed_at}"
  if [ "$proofs" != none ] && ! _wt_proofs_append "$proofs" "$proofs_row" "$branch" "$head" "$merge_sha" "$judged" "$landed_at"; then
    _wt_say "LANDED branch=${branch} onto=${onto} checkout=${co} merge=${merge_sha} kept=${wt_abs}${red_said} proofs=unwritten — ${proofs} could not be appended after the merge, so the tree and its stamp file are kept; append the landing to it by hand, then remove the tree"
    return 0
  fi

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

  _wt_say "LANDED branch=${branch} onto=${onto} checkout=${co} merge=${merge_sha} removed=${wt_abs}${red_said} proofs=${proofs}"
  return 0
}

# THE LANDING RECORD (wave-27 T44; D15; the Interfaces row "landing record").
# `<docs-root>/record/<the bound plan's name less .plan.md>/landing-proofs.log`, appended, never
# rewritten: one header line per landing, `landed: row=<id|—> branch=<b> head=<40-hex>
# merge=<40-hex> at=<ISO-UTC>`, then the stamp lines `_wt_stale_proof` judged at <head>, as the
# stamp file holds them. A row's landing is the `merge=` of the last header carrying its `row=`
# (the tick reads it, T43). The path is derived as fill_ledger_path (lib/patrol.sh) derives its
# own, in the project's docs tree, never in the tree being removed.
_wt_proofs_path() {  # <root> <plan> -> the record's path
  local slug="${2##*/}"
  slug="${slug%.plan.md}"
  [ -n "$slug" ] || return 1
  printf '%s/record/%s/landing-proofs.log' "$(docs_root "$1")" "$slug"
}

# The id of the first `## Tasks` row, in table order, whose `worktree` cell names <tree>; a
# relative cell is read from <root>. Nothing when none does, or when lib/units.sh, the table's
# one reader, cannot be loaded (it is loaded lazily, as run.sh is below).
_wt_proofs_row() {  # <root> <plan> <tree abs> -> <row id> | nothing
  local rec cell lib
  if ! declare -F units_rows >/dev/null 2>&1; then
    lib="$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/units.sh"
    # shellcheck source=/dev/null
    [ -r "$lib" ] && . "$lib" 2>/dev/null
    declare -F units_rows >/dev/null 2>&1 || return 1
  fi
  while IFS= read -r rec; do
    cell="$(units_field "$rec" worktree)"; cell="${cell#./}"; cell="${cell%/}"
    case "$cell" in ''|-|—) continue ;; /*) : ;; *) cell="${1}/${cell}" ;; esac
    [ "$cell" = "$3" ] && { units_field "$rec" id; return 0; }
  done <<EOF
$(units_rows "$2" 2>/dev/null)
EOF
  return 1
}

# One write, its status returned: the header and the judged lines under it.
_wt_proofs_append() {  # <file> <row> <branch> <head> <merge> <judged lines> [<at>]
  local block
  block="landed: row=${2:-—} branch=${3} head=${4} merge=${5} at=${7:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  [ -z "${6:-}" ] || block="${block}
${6}"
  { printf '%s\n' "$block" >> "$1"; } 2>/dev/null
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
  local target="${1:-}" root="${2:-}" sid="${3:-}" lib onto plan decl
  [ -n "$sid" ] || { _wt_refuse "no-session path=${target:-<none>}"; return 2; }
  if ! declare -f session_working_branch >/dev/null 2>&1; then
    lib="$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/run.sh"
    # shellcheck source=/dev/null
    [ -r "$lib" ] && . "$lib" 2>/dev/null
    declare -f session_working_branch >/dev/null 2>&1 \
      || { _wt_refuse "run-library-unloadable path=${lib}"; return 2; }
  fi
  onto="$(session_working_branch "$root" "$sid")" || { _wt_refuse "${onto:-no-bound-plan}"; return 2; }
  # The plan that branch was read from: the marker's `plan=`, the one session_working_branch's
  # verdict answered with (wave-27 T44). The landing record is written under its name.
  plan="$(session_plan "$root" "$sid")" || plan=""
  # THE DECLARED DEBT THE ROW CARRIED FROM ITS LAUNCH (wave-27 T31; D23), or nothing.
  local lands_red="" red_ev=""
  if decl="$(_wt_declared_debt "$root" "$sid" "$target")"; then
    lands_red="${decl%%	*}"; red_ev="${decl#*	}"
  fi
  worktree_land "$target" "$onto" "$plan" "$lands_red" "$red_ev"
}

# _wt_plan_current <plan> -> the plan's raw `current:` value, read by lib/fill.sh's one reader of
# it (loaded lazily, as units.sh is for the landing record), its memo dropped first.
_wt_plan_current() {
  local lib
  if ! declare -F _fill_current_field >/dev/null 2>&1; then
    lib="$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/fill.sh"
    # shellcheck source=/dev/null
    [ -r "$lib" ] && . "$lib" 2>/dev/null
    declare -F _fill_current_field >/dev/null 2>&1 || return 1
  fi
  fill_current_forget
  _fill_current_field "$1"
}

# _wt_declared_debt <root> <sid> <tree> -> `<lands_red><TAB><red_evidence>` from the LAUNCH line of
# the agent the tree was made for, rc 1 with nothing when there is none (wave-27 T31; REQ-14, D23).
# The agent is the name the workspace record holds for the tree (`spawn-worktree.sh create --for`),
# and only when `workspace_for_name` answers that tree for it. Its launch line is the last
# `status=intended` row of that name on the session's roster that no poker verb wrote: a row
# carrying `amended=`, `extended=`, `held=` or `adopted_from=` is a copy, never a launch. The
# dispatch wall is the one writer of the two keys on a launch line, so a key that reached the
# roster on any later row, by amend or by hand, is never read.
_wt_declared_debt() {  # <root> <sid> <tree>
  local root="${1:-}" sid="${2:-}" tree file name row roster
  tree="$(_wt_abs "${3:-}")" || return 1
  file="$(_wt_workspaces_file "$root" "$sid")" || return 1
  [ -f "$file" ] && _wt_workspaces_unlinked "$root" "$file" || return 1
  name="$(awk -F'|' -v p="$tree" '
    $1 == "workspace/v1" { n = ""; q = ""
      for (i = 2; i <= NF; i++) { if ($i ~ /^name=/) n = substr($i, 6); else if ($i ~ /^path=/) q = substr($i, 6) }
      if (q == p && n != "") last = n }
    END { if (last != "") print last }' "$file" 2>/dev/null)"
  [ -n "$name" ] || return 1
  [ "$(workspace_for_name "$root" "$sid" "$name" 2>/dev/null)" = "$tree" ] || return 1
  roster="${root%/}/.bionic/tmp/roster-${sid}.state"
  [ -f "$roster" ] && [ ! -L "$roster" ] || return 1
  row="$(awk -v n="$name" '
    index($0, "roster-state/") != 1 { next }
    index($0, "|name=" n "|") && index($0, "|status=intended|") \
      && !index($0, "|amended=") && !index($0, "|extended=") && !index($0, "|held=") && !index($0, "|adopted_from=") { last = $0 }
    END { if (last != "") print last }' "$roster" 2>/dev/null)"
  [ -n "$row" ] || return 1
  [ -n "$(_wt_field "$row" lands_red)" ] || return 1
  printf '%s\t%s' "$(_wt_field "$row" lands_red)" "$(_wt_field "$row" red_evidence)"
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

# The tree and base recorded for <name>, `<tree><TAB><base>`, by the rule above (wave-26 T40).
# The launch recorder fills a plan row's worktree and base cells from this record, so it asks
# the same witness: the tree is the one `workspace_for_name` answers, and the base is the one on
# the last line naming that tree. 1 none, 2 refused.
workspace_record_for_name() {  # <root> <sid> <name> -> tree TAB base
  local tree f rc
  tree="$(workspace_for_name "${1:-}" "${2:-}" "${3:-}")" || { rc=$?; return "$rc"; }
  f="$(_wt_workspaces_file "$1" "$2")" || return 2
  WT_SID="$2" WT_NAME="$3" WT_TREE="$tree" awk -F'|' -v schema="$WORKSPACE_SCHEMA" '
    BEGIN { sid = ENVIRON["WT_SID"]; want = ENVIRON["WT_NAME"]; tree = ENVIRON["WT_TREE"]; b = "" }
    { sub(/\r$/, "") }
    $1 != schema { next }
    {
      s = ""; n = ""; p = ""; v = ""; hn = 0
      for (i = 2; i <= NF; i++) {
        if (index($i, "session=") == 1) s = substr($i, 9)
        else if (index($i, "name=") == 1) { n = substr($i, 6); hn = 1 }
        else if (index($i, "path=") == 1) p = substr($i, 6)
        else if (index($i, "base=") == 1) v = substr($i, 6)
      }
      if (s == sid && hn && n == want && p == tree) b = v
    }
    END { printf "%s\t%s\n", tree, b }' "$f" 2>/dev/null || return 2
}
