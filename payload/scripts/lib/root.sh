# payload/scripts/lib/root.sh — ONE READER FOR "which project root is this cwd in".
#
# WHAT IT OWNS. Given a directory, name the one project root every bionic reader
# must agree on: the nearest ancestor holding a REAL `.bionic/` directory, after
# a linked worktree has been mapped onto its main repository, bounded below
# `$HOME`. Ownership table, spec §3: `lib/root.sh:project_root` is the SSoT for
# the project root; eleven hooks and scripts, doctor, the Patrol tick's
# candidate listing and the SessionStart block all render from it.
#
# WHY IT EXISTS (R2, handoff §2.2). Eight byte-identical `resolve_project_root`
# copies, each in a hook of its own, asked git FIRST
# and walked for a `.bionic` ancestor only when no repository existed at all. So a
# git repo nested inside a plain workspace that holds the `.bionic` tree always
# resolves to ITSELF: the probe writes an attestation the gate then cannot find,
# and a roster dies with the worktree that wrote it. This library inverts the
# order — the `.bionic` decides, and git is used for two narrow jobs only
# (mapping a worktree, and answering last when nothing else can).
#
# THE FOUR RULES, in the order they fire:
#
#   1. A LINKED WORKTREE IS ITS MAIN REPOSITORY. If `--git-dir` and
#      `--git-common-dir` differ, the cwd is inside a linked worktree and the
#      walk begins at the main repo's working root instead. AC-9: a worktree cwd
#      and the main checkout must reach one address space or the writer's roster
#      and the gate's roster are two different files. In an ordinary checkout
#      the two agree and the walk begins at the cwd itself — the git root is
#      NOT privileged as a floor (design-ledger S3 rejects "git-root-privileged"
#      by name), which is what lets rule 2 see a `.bionic` below it.
#
#   2. NEAREST REAL `.bionic` WINS, wherever the git root is. Walk up; the first
#      ancestor with a `.bionic` that is a directory and not a symlink is the
#      root. A phantom nested `.bionic` therefore wins over the repo root above
#      it — "Phantom nested .bionic = nearest wins, by rule" (design-ledger S3).
#      That is a deliberate accepted edge, not an oversight: the alternative
#      privileges the git root, which is the bug in the eight copies.
#
#   3. A SYMLINKED `.bionic` IS NEVER A ROOT (design-ledger C2). spawn-worktree.sh
#      used to plant `<wt>/.bionic -> <main>/.bionic`; the link carried nothing
#      but a second path to the same state, and rule 1 already maps the worktree.
#      A legacy link left on disk is stepped over — the walk CONTINUES past it
#      rather than stopping — and reported as `skipped-symlink` so doctor and the
#      SessionStart block can name it. Order matters: a symlink to a directory
#      satisfies `-d` too, so `-L` is tested first.
#
#   4. `$HOME` AND EVERYTHING ABOVE IT ARE NEVER CANDIDATES. A stray `~/.bionic`
#      would otherwise become the root of every repo on the machine, since every
#      such repo lives under it. Directories BELOW `$HOME` are ordinary
#      candidates — that is where real projects live. No hit anywhere: the git
#      toplevel of the start directory, else the cwd, and `active_run` is
#      necessarily false at either.
#
# TWO FUNCTIONS, ONE WALK, AND IT RUNS IN THE CALLER. `project_root_candidates` prints the whole walk;
# `project_root` prints the path on its last line. They are the same traversal
# by construction, so the answer and the explanation can never disagree — which
# is the property the tick's absent-roster refusal (2.4) and doctor's root row
# are reporting on.
#
#   project_root [cwd]             -> one absolute path on stdout, exit 0 always
#   project_root_candidates [cwd]  -> one line per considered path:
#                                     <path>TAB<tag>
#
# AND THREE VALUES IN THE CALLER'S SHELL, set by either entry point (epic-23
# wave-14 REQ-2, spec D5 "Hook context"). They are the return channel for a
# caller that wants a VALUE rather than a line, and the pattern is the one
# `_bionic_jq_fill`/`_BIONIC_JQ_*` already uses one library over:
#
#   _BIONIC_ROOT_REPORT   the report the call printed, newline-terminated
#   _BIONIC_ROOT_ANSWER   the terminal line's path — what `project_root` prints
#   BIONIC_WORKTREE       the LINKED WORKTREE's name when rule 1 mapped one away,
#                         empty otherwise; `bionic_context` carries it as its
#                         eighth value so the evidence gate can find the plan row
#                         that owns a worktree writer's commit
#
# They describe the LAST walk, so a caller that resolves two roots reads the
# second one's answer. `bionic_context` walks exactly once per hook event.
#
# THE TAG VOCABULARY IS CLOSED. Exactly six, and the last line of a report is
# always one of the three terminal tags:
#
#   candidate              considered, no usable `.bionic`, the walk continued
#   skipped-symlink        `.bionic` present but a symlink — rule 3
#   above-home             `$HOME` or an ancestor of it — rule 4, never inspected
#   chosen                 TERMINAL: this is the project root
#   git-toplevel-fallback  TERMINAL: no root; the git toplevel of the start
#   cwd-fallback           TERMINAL: no root and no repository; the cwd
#
# BASH 3.2. No associative arrays, no `mapfile`, no `${var^^}`. `realpath` is
# not used: it is absent or flagless on some of the platforms this ships to, and
# `(cd "$d" && pwd -P)` resolves a directory's symlinks portably in the shell —
# which is all this file ever needs, since every path it canonicalises is a
# directory. jq is not needed here; nothing on this path parses JSON.
#
# NO SIDE EFFECTS. Sourcing this file defines functions and does nothing else —
# no output, no global assignment, no `cd`. Every hook in the spine sources it
# before doing its own work, and a PreToolUse hook's stdout is protocol.
#
# Pinned by tests/root.test.sh (seven on-disk topologies, each rule-bearing one
# paired with a differential control).

# The loader, for `docs_path`'s load of roots.sh at call time. It defines functions and runs nothing.
declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac

# _bionic_root_abs <path> -> absolute, symlink-resolved path
#
# Falls back up the chain when the path does not exist yet: a hook is handed a
# cwd from a tool payload, and a deleted or not-yet-created directory must still
# resolve to the nearest real ancestor rather than aborting the caller.
#
# THE SUBSHELL IS SKIPPED WHEN THE PATH IS ALREADY ITS OWN PHYSICAL PATH (epic-23
# wave-14 REQ-4, research R3 §8 cut 5). This function is called four times per root
# walk and `( cd … && pwd -P )` forks a subshell every time — ~3 ms per hook event
# to re-derive a path that was already absolute, already free of `.`, `..` and `//`,
# and already free of symlinks, which is the ordinary case on every checkout.
#
# THE PRECHECK IS NOT "IS IT ABSOLUTE". `pwd -P` does three things: it resolves
# symlinks, it collapses `.`/`..`/`//`, and it makes the path absolute. Skipping it
# is only sound when ALL THREE are already true, so the precheck refuses a path
# carrying any of those components and tests EVERY prefix of the rest with `[ -L ]`
# — a builtin lstat, no fork. Symlink resolution is the point of this function and
# `skipped-symlink` is a named rule in this file`s own tag vocabulary; a precheck
# that tested only the leaf would hand back a path through a symlinked ANCESTOR and
# every `.bionic` decision below it would be made about the wrong directory.
#
# WHEN IN DOUBT IT FALLS THROUGH TO THE SUBSHELL, which is the old behaviour exactly.
# tests/root.test.sh's seven topologies — the symlinked-root one included — are the
# wall this fast path has to keep green.
_bionic_root_phys() {  # <absolute path> -> 0 when `pwd -P` could not change it
  local p="$1" rest comp acc
  case "$p" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    */|*/./*|*/../*|*/.|*/..|*//*) return 1 ;;
  esac
  acc=""
  rest="${p#/}"
  while [ -n "$rest" ]; do
    comp="${rest%%/*}"
    acc="$acc/$comp"
    [ -L "$acc" ] && return 1
    case "$rest" in
      */*) rest="${rest#*/}" ;;
      *)   rest="" ;;
    esac
  done
  return 0
}

_bionic_root_abs() {
  local p="$1"
  [ -n "$p" ] || p="$PWD"
  case "$p" in
    /*) ;;
    *) p="$PWD/$p" ;;
  esac
  while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -d "$p" ]; do
    p="$(dirname "$p")"
  done
  if _bionic_root_phys "$p"; then
    printf '%s\n' "$p"
    return 0
  fi
  ( cd "$p" 2>/dev/null && pwd -P ) || printf '%s\n' "$p"
}

# path_normal <absolute path> -> PATH_NORMAL: `.`, `..` and doubled slashes folded LEXICALLY
# (`<link>/..` is the link's parent: a wall asks which tree a path names), `/` when none is left.
# A `*` is a character, so globbing is off for the split; the caller's state is kept.
PATH_NORMAL=""
path_normal() {
  local part had_f=0
  case "$-" in *f*) had_f=1 ;; esac
  set -f
  PATH_NORMAL=""
  local IFS=/
  for part in $1; do
    case "$part" in
      ''|.) ;;
      ..)   PATH_NORMAL="${PATH_NORMAL%/*}" ;;
      *)    PATH_NORMAL="$PATH_NORMAL/$part" ;;
    esac
  done
  [ "$had_f" -eq 1 ] || set +f
  PATH_NORMAL="${PATH_NORMAL:-/}"
}

# _bionic_root_is_home_or_above <path> <home> -> 0 when <path> is <home> or an
# ancestor of it. Rule 4. The pattern half of the `case` is quoted, so a path
# carrying a glob character is compared literally.
_bionic_root_is_home_or_above() {
  [ -n "${2:-}" ] || return 1
  [ "$1" = "$2" ] && return 0
  case "$2/" in
    "$1/"*) return 0 ;;
  esac
  return 1
}

# _bionic_root_start <abs cwd> -> RETURNED BY VARIABLE, not on stdout:
#
#   _BIONIC_ROOT_START   the directory the walk begins at (rule 1)
#   BIONIC_WORKTREE      the linked worktree's NAME when rule 1 mapped one away,
#                        empty in every other topology — including a worktree of
#                        a BARE repo, which the exception below does not map
#
# WHY BY VARIABLE (epic-23 wave-14 REQ-2). A `$(…)` is a subprocess, and a value
# assigned inside one is gone when it closes. `bionic_context` is four command
# substitutions above this function, so a `BIONIC_WORKTREE` set here could never
# have reached the hook that has to read it. The walk sets its values in the
# caller's shell instead and prints what it always printed.
#
# `--path-format=absolute` needs git >= 2.31; the second arm resolves a relative
# answer against the cwd for anything older. A repository is a linked worktree
# exactly when its git dir and its common git dir differ. The two answers are
# split on the first newline, so a git directory whose own path CONTAINS a
# newline is read as a non-repository — the same degenerate path the rest of this
# library's `case` patterns already decline to model.
#
# BARE EXCEPTION (critic-findings.md wave-1.4.0 issue 2). `dirname(common)` is the
# main repo's working root only when the main repo HAS a working tree. When the
# common dir belongs to a BARE repository, it names a directory holding a `.git`-
# equivalent tree (e.g. `.../bare.git`) with no working tree at all — dirname of
# THAT is just the folder the bare repo happens to sit in, unrelated to any
# checkout. In that case the linked worktree IS the only working tree there is, so
# the walk starts at the cwd instead, exactly as it would with no mapping applied.
_bionic_root_start() {
  local cwd="$1" both common gitdir

  _BIONIC_ROOT_START="$cwd"
  BIONIC_WORKTREE=""

  # ONE ASK, TWO ANSWERS. `git rev-parse` prints one line per path option, in the
  # order the options were given, so the two questions rule 1 has always asked cost
  # one process instead of two. Measured at the parent (R3 §5): 11.7 ms + 10.8 ms,
  # 19% of the whole bash-walls run, on EVERY hook event of every session.
  # Fewer than two lines is no answer from `git_common_dir_and`, so a linked worktree is
  # never silently demoted to an ordinary checkout; the arm below asks again.
  git_common_dir_and "$cwd" --git-dir
  common="$BIONIC_GIT_COMMON"
  gitdir="$BIONIC_GIT_ALSO"

  if [ -z "$common" ] || [ -z "$gitdir" ]; then
    # OLDER GIT (< 2.31) HAS NO `--path-format`, so the whole call above failed and
    # this arm asks again without it; the answers may be relative to the cwd.
    both="$(git -C "$cwd" rev-parse --git-common-dir --git-dir 2>/dev/null)" || both=""
    common="${both%%$'\n'*}"
    gitdir="${both#*$'\n'}"
    [ "$common" = "$both" ] && { common=""; gitdir=""; }
    case "$common" in ""|/*) ;; *) common="$cwd/$common" ;; esac
    case "$gitdir" in ""|/*) ;; *) gitdir="$cwd/$gitdir" ;; esac
  fi

  [ -n "$common" ] && [ -n "$gitdir" ] || return 0
  common="$(_bionic_root_abs "$common")"
  gitdir="$(_bionic_root_abs "$gitdir")"
  [ "$common" != "$gitdir" ] || return 0
  [ "$(git -C "$common" rev-parse --is-bare-repository 2>/dev/null)" != "true" ] || return 0

  # THE NAME WAS ALWAYS IN HAND AND ALWAYS DISCARDED. `<main>/.git/worktrees/<name>`
  # is what `--git-dir` answers inside a linked worktree, so its last segment IS the
  # worktree's name — the name `git worktree list` prints and the name
  # `spawn-worktree.sh` created the tree under. The evidence gate needs it to find
  # the plan row that owns a worktree writer's commit without asking git again.
  BIONIC_WORKTREE="${gitdir##*/}"
  _BIONIC_ROOT_START="$(dirname "$common")"
  return 0
}

# _bionic_root_report [cwd] -> the walk, one `<path>TAB<tag>` line each, on
# stdout. The last line is always terminal (chosen | git-toplevel-fallback |
# cwd-fallback).
#
# AND, IN THE CALLER'S SHELL, the same three values every entry point below
# leaves behind (REQ-2): `_BIONIC_ROOT_REPORT` (what it printed),
# `_BIONIC_ROOT_ANSWER` (the terminal line's path) and `BIONIC_WORKTREE`. The
# report is BUILT rather than streamed for exactly that reason — a caller that
# wants a value instead of a line no longer has to open a subshell to get one,
# which is what `bionic_context` does now for the root AND the worktree.
_bionic_root_report() {
  local cwd start home p top out="" tab=$'\t' nl=$'\n'

  _BIONIC_ROOT_REPORT=""
  _BIONIC_ROOT_ANSWER=""

  cwd="$(_bionic_root_abs "${1:-$PWD}")"
  _bionic_root_start "$cwd"          # sets _BIONIC_ROOT_START and BIONIC_WORKTREE
  start="$_BIONIC_ROOT_START"
  home=""
  [ -n "${HOME:-}" ] && home="$(_bionic_root_abs "$HOME")"

  p="$start"
  while [ -n "$p" ] && [ "$p" != "/" ]; do
    if _bionic_root_is_home_or_above "$p" "$home"; then
      out="$out$p$tab""above-home$nl"
    elif [ -L "$p/.bionic" ]; then
      out="$out$p$tab""skipped-symlink$nl"
    elif [ -d "$p/.bionic" ]; then
      out="$out$p$tab""chosen$nl"
      _BIONIC_ROOT_REPORT="$out"
      _BIONIC_ROOT_ANSWER="$p"
      printf '%s' "$out"
      return 0
    else
      out="$out$p$tab""candidate$nl"
    fi
    p="$(dirname "$p")"
  done

  top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -n "$top" ]; then
    top="$(_bionic_root_abs "$top")"
    out="$out$top$tab""git-toplevel-fallback$nl"
    _BIONIC_ROOT_ANSWER="$top"
  else
    out="$out$cwd$tab""cwd-fallback$nl"
    _BIONIC_ROOT_ANSWER="$cwd"
  fi
  _BIONIC_ROOT_REPORT="$out"
  printf '%s' "$out"
  return 0
}

# project_root_candidates [cwd] -> every considered path with its tag.
# Serves the tick's absent-roster refusal (2.4), doctor's root row and the
# SessionStart report: a reader that disagrees with the answer can see exactly
# which ancestor was rejected and why.
project_root_candidates() {
  _bionic_root_report "${1:-$PWD}"
}

# project_root [cwd] -> the one project root, absolute, exit 0.
#
# Read off the report's terminal line rather than recomputed, so the two
# functions cannot drift apart. The walk records that line as it emits it, so the
# reading no longer costs an `awk` in a pipeline — and, because a pipeline stage
# is a subprocess, that is also what lets `BIONIC_WORKTREE` survive this call.
project_root() {
  _bionic_root_report "${1:-$PWD}" >/dev/null
  [ -n "$_BIONIC_ROOT_ANSWER" ] && printf '%s\n' "$_BIONIC_ROOT_ANSWER"
  return 0
}

# git_common_dir [dir] -> the repository's common git directory, absolute and symlink-resolved;
# rc 1 and nothing printed when <dir> is in no repository.
#
# THE ONE RESOLVER of that directory. The common directory is the one every linked worktree of a
# repository shares (`<main>/.git`), so a record kept there is seen alike from the main checkout
# and from every tree, and no wipe of a project's own state reaches it. A tree's OWN git
# directory (`<main>/.git/worktrees/<name>`) is the wrong answer for anything shared, and this
# never gives it.
#
# A <dir> that does not exist yet is asked from its nearest existing ancestor, as
# `_bionic_root_abs` resolves it, so a caller holding the path of a file already removed still
# finds the repository it lived in. `--path-format=absolute` needs git 2.31; an older git either
# refuses it or echoes it back as a line of its own, and either way the second ask, without it,
# answers relative to <dir>.
git_common_dir() {
  local d c
  d="$(_bionic_root_abs "${1:-$PWD}")"
  c="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || c=""
  case "$c" in *$'\n'*) c="" ;; esac
  if [ -z "$c" ]; then
    c="$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)" || return 1
    case "$c" in ''|*$'\n'*) return 1 ;; /*) ;; *) c="$d/$c" ;; esac
  fi
  _bionic_root_abs "$c"
}

# git_common_dir_and <dir> <path option> -> rc 0 with BIONIC_GIT_COMMON and BIONIC_GIT_ALSO set to git's answers
# to `--git-common-dir` and to <path option> (`--git-dir`, `--show-toplevel`), from ONE ask of git; rc 1 and both
# blank when git fails or answers fewer than two lines, or either answer is empty.
#
# For a caller that wants a second path beside the common directory: two questions in one `rev-parse` cost one
# process where `git_common_dir` and a second ask cost two, on paths every hook event walks. The answers are git's
# own `--path-format=absolute` lines, not resolved further, so a caller compares them with `-ef` or with each other;
# an older git without the option fails here and the caller declines, or asks again itself. Set by variable, so no
# subshell carries them away. One line back is not two answers: it would read as "git dir equals common dir".
git_common_dir_and() {
  local both
  BIONIC_GIT_COMMON=""; BIONIC_GIT_ALSO=""
  both="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir "$2" 2>/dev/null)" || return 1
  case "$both" in *$'\n'*) ;; *) return 1 ;; esac
  [ -n "${both%%$'\n'*}" ] && [ -n "${both#*$'\n'}" ] || return 1
  BIONIC_GIT_COMMON="${both%%$'\n'*}"; BIONIC_GIT_ALSO="${both#*$'\n'}"
}

# git_tree_lease <dir> [<root>] -> rc 0 when <dir> sits in a linked worktree whose main checkout is another
# directory, with BIONIC_LEASE_TOP set to the tree's top and BIONIC_LEASE_MAIN to the main checkout, both physical;
# rc 1 and both blank otherwise. A linked worktree's `.git` is a FILE pointing into the shared repository and the
# main checkout's is a directory, the test lib/worktree.sh's land verb makes too. A tree whose top is <root> is a
# project of its own and holds no lease, so it answers rc 1 before the common directory is asked.
git_tree_lease() {
  local top common main
  BIONIC_LEASE_TOP=""; BIONIC_LEASE_MAIN=""
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ] && [ -f "$top/.git" ] || return 1
  top="$(cd "$top" 2>/dev/null && pwd -P)" && [ -n "$top" ] || return 1
  [ "$top" != "${2:-}" ] || return 1
  common="$(git_common_dir "$top")" || return 1
  main="$(cd "$common/.." 2>/dev/null && pwd -P)" && [ -n "$main" ] || return 1
  [ "$main" != "$top" ] || return 1
  BIONIC_LEASE_TOP="$top"; BIONIC_LEASE_MAIN="$main"
}

# git_linked_dir [dir] -> the tree's OWN git directory (`<main>/.git/worktrees/<name>`), absolute, on stdout, where
# a linked worktree keeps what belongs to that tree alone. rc 1 when <dir> is no directory or in no repository, rc 2 with nothing
# printed when it is the main checkout, whose own git directory is the common one `git_common_dir` answers.
git_linked_dir() {
  local d gd common
  [ -d "${1:-$PWD}" ] || return 1
  d="$(_bionic_root_abs "${1:-$PWD}")"
  gd="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" && [ -d "$gd" ] || return 1
  common="$(git_common_dir "$d")" || return 1
  [ "$gd" != "$common" ] || return 2
  printf '%s\n' "$gd"
}

# ─── THE AUDIT STREAM: where a project's findings land, and who writes one ───
# docs_heads -> the directories a path is spelled from when it is written from the docs root.
docs_heads() { printf '%s\n' record specs adrs plans; }

# docs_path <root> <path> -> <path> made absolute, the one reader of a path spelled from the project root or the docs
# root. Absolute stays. A relative path is the project root's when that file is there, else the docs root's when
# it is there, else by its spelling: the docs root's when it starts with a docs head, the project root's when not.
docs_path() {
  local root="$1" p="${2#./}" d h
  case "$p" in '') return 1 ;; /*) printf '%s\n' "$p"; return 0 ;; esac
  bionic_need roots.sh docs_root
  d="$(docs_root "$root")"
  if [ ! -e "$root/$p" ]; then
    [ -e "$d/$p" ] && { printf '%s/%s\n' "$d" "$p"; return 0; }
    for h in $(docs_heads); do case "$p" in "$h"/*) printf '%s/%s\n' "$d" "$p"; return 0 ;; esac; done
  fi
  printf '%s/%s\n' "$root" "$p"
}

#
# ONE DEFINITION EACH, HERE, SINCE epic-23 wave-12-fixit-171 (REQ-8, spec D6). `audit_path`
# had three copies — payload/scripts/lib/walls.sh, payload/scripts/lib/stop.sh and
# hooks/canonical-sdlc-governing-skill.sh — and `log_finding` had two. Every copy's header
# asked the next reader to keep them identical; nothing enforced it until wave-11 pinned the
# three audit_path bodies by checksum (tests/cross-gate-agreement.test.sh §AP) and promoted
# the consolidation rather than doing it. This is it. §AP is now a COUNT — exactly one
# definition of each under hooks/ and payload/ — because copies that agree can part again
# and copies that do not exist cannot.
#
# WHY THIS LIBRARY AND NOT walls.sh, WHICH THE OWNERSHIP TABLE NAMED. walls.sh is 3,461
# lines, and neither hooks/session-poker.sh nor hooks/canonical-sdlc-governing-skill.sh
# sources it or its prerequisites. Owning these there would have added walls.sh to two more
# hooks' `BIONIC_LIB_WANT` — a FAIL-CLOSED list, where one absent file refuses everything
# that hook judges — and parsed all 3,461 lines per Patrol tick and per Write, for three
# small functions. root.sh is already in the WANT of every process that carried a copy and
# is already sourced ABOVE every use site, so this move widened no library list and added no
# source line anywhere.
#
# AND WHY HERE SPECIFICALLY: `audit_path` is a pure function of a project root, and the
# project root is this file's whole subject. The wave's third shared function,
# `normalize_newlines`, is a document read and went to run.sh beside `_run_lines` instead.

# Incident 0001: the audit stream must live where a consuming project cannot commit it,
# whatever that project's .gitignore says. $HOME-rooted, per-project, durable.
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents. cksum and
# basename are POSIX — no new dependency. A project that resolved two different slugs would
# get two audit files, which is the exact divergence the three copies' headers feared.
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

# Log-only finding channel (D14): append one line to the durable audit file AND echo it to
# stderr, then return 0 — a finding NEVER blocks. The mkdir and the append are both
# fail-open; an unwritable destination drops the line and there is deliberately no fallback
# branch, because a fallback is how a finding ends up inside a consuming project's tree.
#
# THE THREE VALUES THAT MADE THE TWO COPIES DIFFERENT ARE NOW THE CALLER'S, declared once
# beside its own resolvers. They are the whole reason the copies were not byte-identical, so
# folding them together silently would have been a behaviour change wearing a
# deduplication's clothes. The caller declares:
#
#   BIONIC_FINDING_CHANNEL   the hook name written into the line — `evidence-gate` for
#                            walls.sh's gate, `governing-skill` for the PreToolUse|Write hook
#   BIONIC_FINDING_SUBJECT   the artifact the finding is about ($PLAN there, $FILE_PATH here)
#   bionic_finding_root      a FUNCTION printing the project root the finding belongs to
#
# THE ROOT IS A FUNCTION WHERE THE SUBJECT IS A VARIABLE, and the asymmetry is deliberate.
# The subject is already in hand at the declaration site and costs nothing to copy. The root
# costs a SUBPROCESS in walls.sh — `audit_root` walks up from the plan's own directory — so
# it stays lazy and is resolved only when a finding actually fires, never on every judged
# command. Both are read through `:-` defaults: these hooks run under `set -u`, and a
# log-only channel that aborted its own hook over a missing declaration would be the one
# fail direction this design has never allowed.
# [INSTRUMENT]
log_finding() {  # $1=check-id  $2=detail — never blocks, always returns 0
  local f
  if f=$(audit_path "$(bionic_finding_root)"); then
    local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) ${BIONIC_FINDING_CHANNEL:-} $1: $2 (${BIONIC_FINDING_SUBJECT:-})"
    mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$line" >> "$f" 2>/dev/null
  fi
  echo "canonical-sdlc [$1]: $2" >&2
  return 0
}

# THE ANSWER LOG (epic-23 wave-25-never-paused, REQ-7, spec D9). hooks/permission-answer.sh
# writes one line per permission answer to `permission-answers.log`, in the SAME directory
# audit_path names — so one slug rule places both, outside every project and every workspace
# (AC-7.2), and the doctor can name the path without a second rule. Derived from audit_path
# rather than restating its slug, so the two can never name different directories.
# [INSTRUMENT]
answers_path() {  # $1=project root → absolute permission-answers log path; rc 1 if no $HOME
  local a
  a=$(audit_path "$1") || return 1
  printf '%s/permission-answers.log' "${a%/*}"
}

# The answer log's appender. UNLIKE log_finding IT ECHOES NOTHING: its caller answers the
# platform on stdout and keeps its stream for that one object. It reports failure, rc 1, and
# does not swallow it, because the caller's rule is "no answer without a line": an allow that
# could not be put on the record is turned into a denial there.
# [INSTRUMENT]
log_answer() {  # $1=project root  $2=the answer line — appends it; rc 1 when it could not
  local f
  f=$(answers_path "$1") || return 1
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 1
  printf '%s\n' "$2" >> "$f" 2>/dev/null
}
