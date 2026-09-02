#!/bin/bash
# HARD BLOCK: Prevents AI from pushing to main/master branches.
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# The user must push to main manually from their own terminal.
# [WALL: tests/protect-main.test.sh]
# Registered always-on in hooks/hooks.json; runs from the mounted plugin payload.

# The command reader. Everything below asks the library what the words of this
# command line are; nothing here greps the raw text. Until 1.3.2 it did, and
# `git -C /tmp/r push origin main`, `git push origin "main"` and
# `git push origin feature:refs/heads/main` all walked past this wall while a
# heredoc that merely MENTIONED a push was refused.
#
# FAIL-CLOSED (Chris, D1 2026-08-30): a wall that cannot load its library
# REFUSES. Two candidate paths because the shipped tree has two real shapes —
# the installed plugin root (hooks/ and scripts/ as siblings) and this repo,
# where payload/hooks is a symlink to the top-level hooks/ and the library
# lives under payload/scripts/lib/. `..` is resolved by the kernel AFTER the
# symlink, so the first candidate alone would refuse every command in a
# directory-source session. Byte-identical twin of the loader in
# canonical-sdlc-evidence-gate.sh.
#
# ONE LOADER IDIOM ACROSS THE FOUR LIBRARY-SOURCING WALLS (review-b B-4c):
# `$(dirname "$0")` for the directory — the idiom the other eleven hooks here
# already use and the one tests/cmd-class.test.sh §C6 extracts — and `-r` for
# the readability test, which is what actually predicts whether `.` succeeds.
# [WALL: tests/git-argv.test.sh]
_pm_dir="$(dirname "$0")"
_pm_lib=""
for _pm_cand in "$_pm_dir/../scripts/lib/git-argv.sh" "$_pm_dir/../payload/scripts/lib/git-argv.sh"; do
  if [ -r "$_pm_cand" ]; then _pm_lib="$_pm_cand"; break; fi
done
if [ -z "$_pm_lib" ]; then
  echo "BLOCKED: protect-main.sh cannot read commands — its library is missing." >&2
  echo "Expected scripts/lib/git-argv.sh beside $_pm_dir/.. — reinstall the bionic plugin." >&2
  exit 2
fi
# shellcheck source=/dev/null
if ! . "$_pm_lib"; then
  echo "BLOCKED: protect-main.sh cannot read commands — $_pm_lib failed to load." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Read every segment. A segment is a push only when git is argv[0] (after
# leading VAR=value assignments, shell openers, command-taking prefixes and
# git's own global options) and `push` is the subcommand — so
# `echo 'git push origin main'`, `grep 'git push' README.md` and a heredoc body
# are not pushes, and `git -C <dir> push`, `sudo git push`,
# `if …; then git push …; fi` and `sh -c 'git push …'` are.
#
# git_argv_expand_moves, not git_argv_segments: the expanded list adds the
# segments of any `sh -c` / `eval` string, which the segment list on its own
# leaves as a single opaque token (R-12, critic C-1/C-5) — and the moves
# variant prefixes each segment with the directory the shell is in when it
# runs, which Block 3 needs (see there).
#
# EVERY PUSH IS JUDGED, inside the loop, by all three blocks. A command may
# carry two pushes that run in two places (`git push && cd wt && git push`);
# a block that ran once after the loop judged only the last (critic,
# 2026-09-02). A command with no push falls out of the loop and is allowed.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  PUSH_AT="${line%%"$GIT_ARGV_RS"*}"
  segment="${line#*"$GIT_ARGV_RS"}"
  git_argv_parse "$segment" || continue
  [ "$GIT_SUB" = "push" ] || continue
  git_push_targets

  # Block 1: this push writes to main/master. GIT_DESTS is US-separated, so
  # bracketing it with separators makes an exact whole-word membership test —
  # `topic/main` and `main-fixes` are their own branches and stay allowed.
  # [WALL: tests/protect-main.test.sh]
  case "$GIT_ARGV_US$GIT_DESTS$GIT_ARGV_US" in
    *"${GIT_ARGV_US}main${GIT_ARGV_US}"*|*"${GIT_ARGV_US}master${GIT_ARGV_US}"*)
      echo "BLOCKED: Pushing to main/master is not allowed from Claude Code." >&2
      echo "Push to main must be done manually by the user." >&2
      exit 2
      ;;
  esac

  # Block 2: force pushes (always dangerous) [WALL: tests/protect-main.test.sh]
  if [ "$GIT_FORCE" -eq 1 ]; then
    echo "BLOCKED: Force pushing is not allowed from Claude Code." >&2
    exit 2
  fi

  # Block 3: Any push while on main/master branch (catches implicit pushes
  # like "git push origin", "git push origin HEAD", bare "git push")
  # [WALL: tests/protect-main.test.sh]
  #
  # JUDGED WHERE THE PUSH RUNS, not where this hook runs. The hook's cwd is
  # the session's — the main checkout, on main — and a worktree push moves
  # first: `cd <repo>/.worktrees/x && git push origin x`, or
  # `git -C <worktree> push`. Until this read the command's own moves, every
  # such push was refused as a push from main (three false blocks in one day,
  # 2026-08-05; PR #16 carried the same fix against the pre-1.3.2 text
  # matcher). Where the shell is when this segment runs is the library's
  # reading (PUSH_AT, from git_argv_expand_moves — it applies the shell's own
  # rules for `&&`, `||`, `&`, `|`, `( … )`, `sh -c` and an unnameable `cd`);
  # git's own `-C` hops come after it, in git's order (`git -C a -C b` is a
  # then b), so the whole list goes to git as-is.
  #
  # FAIL-CLOSED: a target git cannot read (no such directory, not a
  # repository, a `cd "$VAR"` the reader kept as written) falls back to the
  # hook's own cwd — the side that refuses. A real repository with no branch
  # (detached HEAD) is judged on its own state: no branch is not main. Block 1
  # refuses an explicit main destination whatever the cwd, so this reading
  # only ever decides the IMPLICIT push.
  #
  # NOT MODELLED, deliberately: a `cd` target the shell would expand (`$VAR`,
  # `$(…)`) — read as written, so it falls back to the hook cwd, which
  # refuses; write the path. And conditions: `if false; then cd wt; fi` reads
  # as a move, because nothing here evaluates `false` — the line the library
  # draws for `$(…)` too. Both are named in git_argv_expand_moves.
  CURRENT_BRANCH=""
  _pm_resolved=0
  _pm_hops="$PUSH_AT"
  if [ -n "$GIT_C_DIRS" ]; then
    if [ -n "$_pm_hops" ]; then _pm_hops="$_pm_hops$GIT_ARGV_US$GIT_C_DIRS"; else _pm_hops="$GIT_C_DIRS"; fi
  fi
  if [ -n "$_pm_hops" ]; then
    _pm_oldifs="$IFS"
    set -f
    IFS="$GIT_ARGV_US"
    # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
    set -- $_pm_hops
    IFS="$_pm_oldifs"
    set +f
    # Rewrite the hop list in place as `-C <hop>` pairs (bash 3.2: no arrays).
    _pm_n=$#
    while [ "$_pm_n" -gt 0 ]; do
      set -- "$@" -C "$1"
      shift
      _pm_n=$((_pm_n - 1))
    done
    if git "$@" rev-parse --git-dir >/dev/null 2>&1; then
      _pm_resolved=1
      CURRENT_BRANCH=$(git "$@" symbolic-ref --short HEAD 2>/dev/null || echo "")
    fi
  fi
  if [ "$_pm_resolved" -eq 0 ]; then
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
  fi
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    echo "BLOCKED: Cannot push while on '$CURRENT_BRANCH' branch from Claude Code." >&2
    echo "Switch to a feature branch or push manually from your terminal." >&2
    exit 2
  fi
done <<< "$(git_argv_expand_moves "$COMMAND")"

exit 0
