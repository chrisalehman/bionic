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
# git_argv_EXPAND, not git_argv_segments: the expanded list adds the segments
# of any `sh -c` / `eval` string, which the segment list on its own leaves as a
# single opaque token (R-12, critic C-1/C-5).
IS_PUSH=0
while IFS= read -r segment; do
  [ -n "$segment" ] || continue
  git_argv_parse "$segment" || continue
  [ "$GIT_SUB" = "push" ] || continue
  IS_PUSH=1
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
done <<< "$(git_argv_expand "$COMMAND")"

# Skip if no actual push command found
if [ "$IS_PUSH" -eq 0 ]; then
  exit 0
fi

# Block 3: Any push while on main/master branch (catches implicit pushes
# like "git push origin", "git push origin HEAD", bare "git push")
# [WALL: tests/protect-main.test.sh]
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "BLOCKED: Cannot push while on '$CURRENT_BRANCH' branch from Claude Code." >&2
  echo "Switch to a feature branch or push manually from your terminal." >&2
  exit 2
fi

exit 0
