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
# copies (dispatch-preflight.sh:103, session-poker.sh:273, agent-context-guard.sh:109,
# canonical-sdlc-governing-skill.sh:99, canonical-sdlc-evidence-gate.sh:156,
# preflight-probe.sh:146, patrol-revive.sh:178, stop-orders.sh:137) ask git FIRST
# and walk for a `.bionic` ancestor only when no repository exists at all. So a
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
# TWO FUNCTIONS, ONE WALK. `project_root_candidates` prints the whole walk;
# `project_root` prints the path on its last line. They are the same traversal
# by construction, so the answer and the explanation can never disagree — which
# is the property the tick's absent-roster refusal (2.4) and doctor's root row
# are reporting on.
#
#   project_root [cwd]             -> one absolute path on stdout, exit 0 always
#   project_root_candidates [cwd]  -> one line per considered path:
#                                     <path>TAB<tag>
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

# _bionic_root_abs <path> -> absolute, symlink-resolved path
#
# Falls back up the chain when the path does not exist yet: a hook is handed a
# cwd from a tool payload, and a deleted or not-yet-created directory must still
# resolve to the nearest real ancestor rather than aborting the caller.
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
  ( cd "$p" 2>/dev/null && pwd -P ) || printf '%s\n' "$p"
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

# _bionic_root_start <abs cwd> -> the directory the walk begins at (rule 1)
#
# `--path-format=absolute` needs git >= 2.31; the second arm resolves a relative
# answer against the cwd for anything older. A repository is a linked worktree
# exactly when its git dir and its common git dir differ.
#
# BARE EXCEPTION (critic-findings.md wave-1.4.0 issue 2). `dirname(common)` is the
# main repo's working root only when the main repo HAS a working tree. When the
# common dir belongs to a BARE repository, it names a directory holding a `.git`-
# equivalent tree (e.g. `.../bare.git`) with no working tree at all — dirname of
# THAT is just the folder the bare repo happens to sit in, unrelated to any
# checkout. In that case the linked worktree IS the only working tree there is, so
# the walk starts at the cwd instead, exactly as it would with no mapping applied.
_bionic_root_start() {
  local cwd="$1" common gitdir
  common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  gitdir="$(git -C "$cwd" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || gitdir=""
  if [ -z "$common" ] || [ -z "$gitdir" ]; then
    common="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)" || common=""
    gitdir="$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)" || gitdir=""
    case "$common" in ""|/*) ;; *) common="$cwd/$common" ;; esac
    case "$gitdir" in ""|/*) ;; *) gitdir="$cwd/$gitdir" ;; esac
  fi
  if [ -n "$common" ] && [ -n "$gitdir" ]; then
    common="$(_bionic_root_abs "$common")"
    gitdir="$(_bionic_root_abs "$gitdir")"
    if [ "$common" != "$gitdir" ]; then
      if [ "$(git -C "$common" rev-parse --is-bare-repository 2>/dev/null)" != "true" ]; then
        printf '%s\n' "$(dirname "$common")"
        return 0
      fi
    fi
  fi
  printf '%s\n' "$cwd"
}

# _bionic_root_report [cwd] -> the walk, one `<path>TAB<tag>` line each. The
# last line is always terminal (chosen | git-toplevel-fallback | cwd-fallback).
_bionic_root_report() {
  local cwd start home p top
  cwd="$(_bionic_root_abs "${1:-$PWD}")"
  start="$(_bionic_root_start "$cwd")"
  home=""
  [ -n "${HOME:-}" ] && home="$(_bionic_root_abs "$HOME")"

  p="$start"
  while [ -n "$p" ] && [ "$p" != "/" ]; do
    if _bionic_root_is_home_or_above "$p" "$home"; then
      printf '%s\t%s\n' "$p" "above-home"
    elif [ -L "$p/.bionic" ]; then
      printf '%s\t%s\n' "$p" "skipped-symlink"
    elif [ -d "$p/.bionic" ]; then
      printf '%s\t%s\n' "$p" "chosen"
      return 0
    else
      printf '%s\t%s\n' "$p" "candidate"
    fi
    p="$(dirname "$p")"
  done

  top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [ -n "$top" ]; then
    printf '%s\t%s\n' "$(_bionic_root_abs "$top")" "git-toplevel-fallback"
  else
    printf '%s\t%s\n' "$cwd" "cwd-fallback"
  fi
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
# functions cannot drift apart.
project_root() {
  _bionic_root_report "${1:-$PWD}" | awk -F'\t' '{ p = $1 } END { if (p != "") print p }'
}
