#!/bin/bash
# Tests for protect-main.sh Claude Code hook.
# Runs the hook against a matrix of push commands x branch states,
# verifying that pushes to main/master are always blocked and
# pushes to feature branches are allowed.
#
# Usage: bash tests/protect-main.test.sh

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HOOK="${BIONIC_HOOKS_DIR}/protect-main.sh"
PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

run_hook() {
  # Feeds a simulated tool_input to the hook on stdin.
  #
  # The payload is built with `jq -n --arg`, not string interpolation: the
  # AC-9/AC-10 cases below carry double quotes and newlines (a heredoc), and
  # hand-built JSON mangles both. Same idiom as
  # tests/canonical-sdlc-evidence-gate.test.sh:run_hook.
  local cmd="$1"
  jq -n --arg c "$cmd" '{tool_input: {command: $c}}' | bash "$HOOK" 2>/dev/null
}

expect_block() {
  local label="$1"
  local cmd="$2"
  TOTAL=$((TOTAL + 1))
  if run_hook "$cmd"; then
    echo "FAIL (expected BLOCK): $label"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

expect_allow() {
  local label="$1"
  local cmd="$2"
  TOTAL=$((TOTAL + 1))
  if run_hook "$cmd"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected ALLOW): $label"
    FAIL=$((FAIL + 1))
  fi
}

# ---------- setup: fake git that reports a controllable branch ----------

FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/git" << 'FAKEGIT'
#!/bin/bash
# Intercept "git symbolic-ref --short HEAD" and return $FAKE_BRANCH.
# Pass everything else through to real git.
if [[ "$*" == "symbolic-ref --short HEAD" ]]; then
  echo "${FAKE_BRANCH:-main}"
  exit 0
fi
# Fall through to real git for any other sub-command
REAL_GIT=$(which -a git | grep -v "$FAKE_BIN" | head -1)
exec "$REAL_GIT" "$@"
FAKEGIT
chmod +x "$FAKE_BIN/git"

# The PATH without the shim, for Section 8: its cases are real repositories
# whose branch is the fact under test, so the shim's controllable answer would
# only hide the reading.
REAL_PATH="$PATH"
export PATH="$FAKE_BIN:$PATH"

cleanup() { rm -rf "$FAKE_BIN"; }
trap cleanup EXIT

# ============================================================
# SECTION 1: On main branch — every push must be blocked
# ============================================================

echo ""
echo "=== Section 1: On 'main' branch (all pushes must be BLOCKED) ==="
export FAKE_BRANCH="main"

expect_block "explicit: push origin main"            "git push origin main"
expect_block "explicit: push upstream main"           "git push upstream main"
expect_block "explicit: push origin master"           "git push origin master"
expect_block "bare push"                              "git push"
expect_block "push origin (implicit branch)"          "git push origin"
expect_block "push origin HEAD"                       "git push origin HEAD"
expect_block "push -u origin main"                    "git push -u origin main"
expect_block "push --set-upstream origin main"        "git push --set-upstream origin main"
expect_block "push origin HEAD:main"                  "git push origin HEAD:main"
expect_block "push origin HEAD:refs/heads/main"       "git push origin HEAD:refs/heads/main"
expect_block "force push -f"                          "git push -f origin main"
expect_block "force push --force"                     "git push --force origin main"
expect_block "force push --force-with-lease"          "git push --force-with-lease origin main"
expect_block "push in compound command"               "cd /tmp && git push origin"
expect_block "push with env prefix"                   "GIT_SSH_COMMAND=ssh git push origin main"
expect_block "compound with ||"                       "false || git push origin main"
expect_block "force push flag at end"                 "git push origin main -f"
expect_block "force push --force at end"              "git push origin feat/x --force"
expect_block "refspec push HEAD:main"                 "git push origin HEAD:main"

# ============================================================
# SECTION 2: On master branch — every push must be blocked
# ============================================================

echo ""
echo "=== Section 2: On 'master' branch (all pushes must be BLOCKED) ==="
export FAKE_BRANCH="master"

expect_block "master: bare push"                      "git push"
expect_block "master: push origin"                    "git push origin"
expect_block "master: push origin HEAD"               "git push origin HEAD"
expect_block "master: push origin master"             "git push origin master"

# ============================================================
# SECTION 3: On feature branch — non-main pushes must be allowed
# ============================================================

echo ""
echo "=== Section 3: On feature branch (safe pushes must be ALLOWED) ==="
export FAKE_BRANCH="feat/cool-thing"

expect_allow "feature: push origin feat/cool-thing"   "git push origin feat/cool-thing"
expect_allow "feature: push -u origin feat/cool-thing" "git push -u origin feat/cool-thing"
expect_allow "feature: bare push"                     "git push"
expect_allow "feature: push origin"                   "git push origin"
expect_allow "feature: push origin HEAD"              "git push origin HEAD"

# Even from a feature branch, explicit main/master must be blocked
expect_block "feature: push origin main (explicit)"   "git push origin main"
expect_block "feature: push origin master (explicit)"  "git push origin master"

# Force pushes always blocked regardless of branch
expect_block "feature: force push -f"                 "git push -f origin feat/cool-thing"
expect_block "feature: force push --force"            "git push --force origin feat/cool-thing"
expect_block "feature: force push --force-with-lease"  "git push --force-with-lease origin feat/cool-thing"

# Branch names containing "main" as substring should be allowed
expect_allow "feature: push branch with main substring" "git push origin feat/maintain-state"
expect_allow "feature: push domain-main branch"        "git push origin domain-main-fix"

# ============================================================
# SECTION 4: Non-push commands must always pass through
# ============================================================

echo ""
echo "=== Section 4: Non-push commands (must be ALLOWED) ==="
export FAKE_BRANCH="main"

expect_allow "git status"                             "git status"
expect_allow "git log"                                "git log --oneline -5"
expect_allow "git diff"                               "git diff HEAD~1"
expect_allow "git commit"                             "git commit -m 'test'"
expect_allow "git pull"                               "git pull origin main"
expect_allow "git fetch"                              "git fetch origin"
expect_allow "git branch"                             "git branch -a"
expect_allow "echo with push in string"               "echo 'not a git push'"
expect_allow "commit message mentioning push"          "git commit -m 'fix: close git push gaps in hook'"
expect_allow "ls command"                             "ls -la"
expect_allow "grep mentioning git push"               "grep 'git push' README.md"
expect_allow "cat file with push content"             "cat deploy.sh"

# Regression: commands with GIT_ env var prefix that are NOT pushes must pass.
# Previously the ^GIT_ alternative in the segment regex caught any command
# starting with GIT_, even git commit with a GIT_AUTHOR_DATE prefix.
expect_allow "GIT_AUTHOR_DATE prefix on commit"       "GIT_AUTHOR_DATE='2026-04-11' git commit -m 'test'"
expect_allow "GIT_COMMITTER_DATE prefix on commit"    "GIT_COMMITTER_DATE='2026-04-11' git commit -m 'test'"
expect_allow "env GIT_AUTHOR_DATE on commit"          "env GIT_AUTHOR_DATE='2026-04-11' git commit -m 'test'"

# But GIT_ env var prefix on an actual push MUST still be caught by the
# downstream "git push anywhere in segment" check.
expect_block "GIT_SSH_COMMAND prefix on push"         "GIT_SSH_COMMAND=ssh git push origin main"
expect_block "GIT_ASKPASS prefix on push"             "GIT_ASKPASS=cat git push origin main"

# ============================================================
# SECTION 5: spellings git honours and the old string match missed (AC-9)
# ============================================================
#
# Every case below is a real push whose destination is main. The pre-1.3.2 hook
# read the command as text — `git push` had to be two adjacent words, quotes
# were deleted wholesale, and a refspec was matched with a regex — so a global
# option, a quoted branch name or a refs/heads/ spelling walked straight past
# it (research-b3-b5-b9-cmd-parsing.md §2). The branch is a feature branch here
# so Block 3 (any push while on main) cannot mask the result: what these pin is
# the destination reading, nothing else.

echo ""
echo "=== Section 5: git spellings that reach main (all BLOCKED) ==="
export FAKE_BRANCH="feat/cool-thing"

expect_block "AC-9 -C <dir> global option"        "git -C /tmp/r push origin main"
expect_block "AC-9 -c <cfg> global option"        "git -c user.name=x push origin main"
expect_block "AC-9 HEAD:refs/heads/main"          "git push origin HEAD:refs/heads/main"
expect_block "AC-9 delete refspec :main"          "git push origin :main"
expect_block "AC-9 force refspec +main"           "git push origin +main"
expect_block "AC-9 double-quoted main"            'git push origin "main"'
expect_block "AC-9 single-quoted main"            "git push origin 'main'"
expect_block "AC-9 refs/heads/main"               "git push origin refs/heads/main"
expect_block "AC-9 feature:refs/heads/main"       "git push origin feature:refs/heads/main"
expect_block "AC-9 force-with-lease onto main"    "git push --force-with-lease origin main"
expect_block "AC-9 -C <dir> force push of main"   "git -C /tmp/r push --force origin main"

# The force wall is a wall wherever the flag sits, including behind a global
# option — research measured `git -C /tmp/r push --force origin feature` as a
# clean miss.
expect_block "AC-9 -C <dir> force push of a feature branch" \
                                                  "git -C /tmp/r push --force origin feature"

# ============================================================
# SECTION 6: spellings that only LOOK like a main push (AC-10)
# ============================================================
#
# The mirror image. `topic/main` and `main-fixes` are ordinary branches;
# `echo` and a heredoc body are text the shell prints or writes, not a push it
# runs. The heredoc case is the one the old hook got backwards: it split
# segments on newlines, so every line of a body became a candidate command and
# a document that MENTIONED a main push was refused as if it were one.

echo ""
echo "=== Section 6: near-misses and prose (all ALLOWED) ==="
export FAKE_BRANCH="feat/cool-thing"

expect_allow "AC-10 topic/main is its own branch"  "git push origin topic/main"
expect_allow "AC-10 main-fixes is its own branch"  "git push origin main-fixes"
expect_allow "AC-10 HEAD:refs/heads/feature/main"  "git push origin HEAD:refs/heads/feature/main"
expect_allow "AC-10 echo of a push line"           "echo 'git push origin main'"

HEREDOC_PUSH=$(printf 'cat > /tmp/note.txt <<%sNOTE%s\ngit push origin main\nNOTE\n' "'" "'")
expect_allow "AC-10 heredoc body containing a push line" "$HEREDOC_PUSH"

# A heredoc must not swallow the command that follows it either.
HEREDOC_THEN_PUSH=$(printf 'cat > /tmp/note.txt <<%sNOTE%s\nnothing to see\nNOTE\ngit push origin main\n' "'" "'")
expect_block "after a heredoc, a real main push is still blocked" "$HEREDOC_THEN_PUSH"

# ============================================================
# SECTION 7: shell constructs and command-taking prefixes (AC-9, R-12)
# ============================================================
#
# THE REGRESSION THIS SECTION EXISTS FOR (critic C-1, 2026-08-30). The 1.3.2
# rewrite reads argv[0] of a segment split on `; && || | &`. The 1.3.1 hook it
# replaced matched `(^|[[:space:]])git[[:space:]]+push` — the token after ANY
# whitespace. So every construct that starts a new command WITHOUT one of those
# separators (`(`, `{`, `then`, `do`), and every command that takes another
# command as its argument (`sudo`, `time`, `xargs`, `find -exec`, `ssh`), put
# `git` at argv[1..n] where the new reader does not look. Nine spellings 1.3.1
# refused walked through 1.3.2 (critic-step6.md §C-1 Repro 1). R-12 makes the
# argv reading a SUPERSET: openers are skipped before argv[0] is read, prefixes
# are skipped with their own options, and `sh -c`/`eval` strings are re-read.
#
# Feature branch again, so Block 3 cannot mask the result.

echo ""
echo "=== Section 7: openers, prefixes and runner strings (all BLOCKED) ==="
export FAKE_BRANCH="feat/cool-thing"

# --- shell constructs that open a command without a separator ---
expect_block "AC-9 subshell ( … )"                "( git push origin main )"
expect_block "AC-9 subshell without spaces"       "(git push origin main)"
expect_block "AC-9 group { …; }"                  "{ git push origin main; }"
expect_block "AC-9 if/then"                       "if true; then git push origin main; fi"
expect_block "AC-9 if <command> directly"         "if git push origin main; then echo ok; fi"
expect_block "AC-9 for/do"                        "for i in 1; do git push origin main; done"
expect_block "AC-9 while/do"                      "while false; do git push origin main; done"
expect_block "AC-9 else branch"                   "if false; then true; else git push origin main; fi"
expect_block "AC-9 negation !"                    "! git push origin main"
expect_block "AC-9 background & is a separator"   "true & git push origin main"

# --- commands whose argument is another command ---
expect_block "AC-9 sudo"                          "sudo git push origin main"
expect_block "AC-9 sudo -u <user>"                "sudo -u ci git push origin main"
expect_block "AC-9 sudo --"                       "sudo -- git push origin main"
expect_block "AC-9 time"                          "time git push origin main"
expect_block "AC-9 time -p"                       "time -p git push origin main"
expect_block "AC-9 nice -n <N>"                   "nice -n 10 git push origin main"
expect_block "AC-9 nice (bare)"                   "nice git push origin main"
expect_block "AC-9 timeout <N>"                   "timeout 60 git push origin main"
expect_block "AC-9 gtimeout <N>"                  "gtimeout 60 git push origin main"
expect_block "AC-9 timeout -s KILL <N>"           "timeout -s KILL 60 git push origin main"
expect_block "AC-9 timeout 30s (suffixed)"        "timeout 30s git push origin main"
expect_block "AC-9 nohup"                         "nohup git push origin main"
expect_block "AC-9 exec"                          "exec git push origin main"
expect_block "AC-9 command"                       "command git push origin main"
expect_block "AC-9 env VAR=v"                     "env GIT_ASKPASS=cat git push origin main"
expect_block "AC-9 xargs"                         "xargs git push origin main"
expect_block "AC-9 xargs -I{}"                    "xargs -I{} git push origin main"
expect_block "AC-9 xargs -I {} (separate value)"  "xargs -I {} git push origin main"
expect_block "AC-9 xargs -n 1 -0"                 "xargs -n 1 -0 git push origin main"
expect_block "AC-9 find … -exec … \\;"            "find . -exec git push origin main \\;"
expect_block "AC-9 find … -execdir … \\;"         "find . -execdir git push origin main \\;"
expect_block "AC-9 ssh <host>"                    "ssh box git push origin main"
expect_block "AC-9 ssh -p <port> <host>"          "ssh -p 22 box git push origin main"

# --- runner strings: one level of re-reading (C-5) ---
expect_block "AC-9 sh -c '<string>'"              "sh -c 'git push origin main'"
expect_block "AC-9 bash -c \"<string>\""          'bash -c "git push origin main"'
expect_block "AC-9 zsh -c '<string>'"             "zsh -c 'git push origin main'"
expect_block "AC-9 dash -c '<string>'"            "dash -c 'git push origin main'"
expect_block "AC-9 eval \"<string>\""             'eval "git push origin main"'
expect_block "AC-9 eval '<string>'"               "eval 'git push origin main'"
expect_block "AC-9 sh -c over a construct"        "sh -c '( git push origin main )'"

# --- stacked: a prefix in front of a construct, and vice versa ---
expect_block "AC-9 then + sudo"                   "if true; then sudo git push origin main; fi"
expect_block "AC-9 subshell + time"               "( time git push origin main )"

# --- and the negatives stay negative ---
expect_allow "AC-10 echo of a sudo push line"     'echo "sudo git push origin main"'
expect_allow "AC-10 echo of a subshell push line" "echo '( git push origin main )'"
expect_allow "AC-10 find with no -exec"           "find . -name 'git'"
expect_allow "AC-10 find -name git push"          "find . -name 'git push'"
expect_allow "AC-10 sudo of a non-push"           "sudo git status"
expect_allow "AC-10 xargs of a non-push"          "xargs git log"
expect_allow "AC-10 sudo push to a topic branch"  "sudo git push origin topic/main"
expect_allow "AC-10 then + push to a topic branch" "if true; then git push origin topic/main; fi"
expect_allow "AC-10 ssh to a host called main"    "ssh main ls"
expect_allow "AC-10 a heredoc body with a sudo push" \
  "$(printf 'cat > /tmp/note.txt <<%sNOTE%s\nsudo git push origin main\nNOTE\n' "'" "'")"
expect_allow "AC-10 echo of a timeout push line"  'echo "timeout 60 git push origin main"'

# --- B-1 (review-b): a QUOTED <<WORD must not open a phantom heredoc ---
# `echo "see <<EOF for the format"` had no quote state in the heredoc scan, so
# every following line was read as body — a real push on the next line walked
# through 1.3.2 and was blocked by 1.3.1.
expect_block "B-1 a quoted <<WORD does not swallow the next line" \
  "$(printf 'echo "see <<EOF for the heredoc format"\ngit push origin main\n')"
expect_block "B-1 …single-quoted too" \
  "$(printf "echo 'run <<EOF to open a heredoc'\ngit push origin main\n")"
# PAIRED POSITIVE: a real unquoted opener still hides its body.
expect_allow "B-1 an UNQUOTED heredoc body is still ignored" \
  "$(printf 'cat > /tmp/n.txt <<EOF\ngit push origin main\nEOF\n')"

# ============================================================
# SECTION 8: Block 3 judges the branch WHERE THE PUSH RUNS (real repos)
# ============================================================
#
# THE FALSE BLOCK THIS SECTION EXISTS FOR. Block 3 read HEAD in the hook's own
# cwd. The hook's cwd is the session's — the main checkout, on main — while a
# worktree push moves first: `cd <repo>/.worktrees/x && git push origin x`, or
# `git -C <worktree> push origin x`. Every such push was refused as "Cannot
# push while on 'main'" (three in one day on 2026-08-05; upstream PR #16). The
# same reading, run the other way, is a wall: a `cd <main checkout>` in front
# of a bare push from a feature-branch cwd IS a push from main and must be
# blocked. Block 1 and Block 2 are untouched by any of this — an explicit main
# destination or a force stays refused wherever the push runs.
#
# No shim here (REAL_PATH): the repositories are real and their branch is the
# fact under test. The hook is run with a chosen cwd, because that is the
# variable the defect was about.

run_hook_in() {  # <hook cwd> <command> [HOME for the hook]
  local dir="$1" cmd="$2" home="${3:-$HOME}"
  ( cd "$dir" && jq -n --arg c "$cmd" '{tool_input: {command: $c}}' \
      | PATH="$REAL_PATH" HOME="$home" bash "$HOOK" 2>/dev/null )
}
expect_block_in() {  # <label> <hook cwd> <command> [HOME]
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if run_hook_in "$2" "$3" "${4:-$HOME}"; then
    echo "FAIL (expected BLOCK): $label"; FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"; PASS=$((PASS + 1))
  fi
}
expect_allow_in() {  # <label> <hook cwd> <command> [HOME]
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if run_hook_in "$2" "$3" "${4:-$HOME}"; then
    echo "PASS: $label"; PASS=$((PASS + 1))
  else
    echo "FAIL (expected ALLOW): $label"; FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== Section 8: the branch where the push runs (real repos, no shim) ==="

S8=$(mktemp -d)
S8_MAIN="$S8/main"                    # the main checkout, on master
S8_WT="$S8_MAIN/.worktrees/feat"      # a linked worktree, on feat
S8_DETACHED="$S8/detached"            # a real repo with no branch at all
S8_NOREPO="$S8/notrepo"               # a directory git knows nothing about
_s8_git() { PATH="$REAL_PATH" git -c user.email=t@t -c user.name=t "$@"; }
_s8_git init -q -b master "$S8_MAIN"
_s8_git -C "$S8_MAIN" commit -q --allow-empty -m init
_s8_git -C "$S8_MAIN" worktree add -q "$S8_WT" -b feat
_s8_git init -q -b master "$S8_DETACHED"
_s8_git -C "$S8_DETACHED" commit -q --allow-empty -m init
_s8_git -C "$S8_DETACHED" checkout -q --detach
mkdir -p "$S8_NOREPO"
cleanup() { rm -rf "$FAKE_BIN" "$S8"; }

# --- the baseline both directions rest on ---
expect_block_in "S8 from the main checkout, a push is judged on master" \
  "$S8_MAIN" "git push origin feat"
expect_allow_in "S8 from the worktree, a push is judged on feat" \
  "$S8_WT"   "git push origin feat"

# --- the worktree shape: judged where the push runs, not where the hook is ---
expect_allow_in "S8 cd <worktree> && push, from the main checkout" \
  "$S8_MAIN" "cd $S8_WT && git push origin feat"
expect_allow_in "S8 cd <worktree> && bare push" \
  "$S8_MAIN" "cd $S8_WT && git push"
expect_allow_in "S8 cd <worktree> && push -u" \
  "$S8_MAIN" "cd $S8_WT && git push -u origin feat"
expect_allow_in "S8 git -C <worktree> push" \
  "$S8_MAIN" "git -C $S8_WT push origin feat"
expect_allow_in "S8 git -C <worktree> bare push" \
  "$S8_MAIN" "git -C $S8_WT push"
expect_allow_in "S8 a relative cd (.worktrees/feat)" \
  "$S8_MAIN" "cd .worktrees/feat && git push origin feat"
expect_allow_in "S8 a quoted cd with a trailing space" \
  "$S8_MAIN" "cd \"$S8_WT\" && git push origin feat"
expect_allow_in "S8 a ~-rooted cd is expanded" \
  "$S8_MAIN" "cd ~/main/.worktrees/feat && git push origin feat" "$S8"
expect_allow_in "S8 cd then -C compose (cd <root> && git -C main/.worktrees/feat)" \
  "$S8_MAIN" "cd $S8 && git -C main/.worktrees/feat push origin feat"
expect_allow_in "S8 the push inside sh -c is read where it runs" \
  "$S8_MAIN" "sh -c 'cd $S8_WT && git push origin feat'"
expect_allow_in "S8 a real repo with no branch (detached HEAD) is not main" \
  "$S8_MAIN" "cd $S8_DETACHED && git push origin HEAD:feat/x"

# --- the same reading is a wall in the other direction ---
expect_block_in "S8 cd <main checkout> && bare push, from the worktree" \
  "$S8_WT"   "cd $S8_MAIN && git push"
expect_block_in "S8 git -C <main checkout> push origin, from the worktree" \
  "$S8_WT"   "git -C $S8_MAIN push origin"
expect_block_in "S8 the LAST cd decides (worktree, then main checkout)" \
  "$S8_WT"   "cd $S8_WT && cd $S8_MAIN && git push origin feat"

# --- every push is judged where IT runs, not where the last one does ---
expect_block_in "S8 two pushes: the first runs on master" \
  "$S8_MAIN" "git push && cd $S8_WT && git push"
expect_block_in "S8 two pushes: the second runs on master" \
  "$S8_WT"   "cd $S8_WT && git push origin feat && cd $S8_MAIN && git push"

# --- a move the shell itself discards, or cannot be named, is no move ---
expect_block_in "S8 cd <worktree> & push: the cd ran in the background" \
  "$S8_MAIN" "cd $S8_WT & git push"
expect_block_in "S8 cd <worktree> | push: the cd ran in a pipe" \
  "$S8_MAIN" "cd $S8_WT | git push"
expect_block_in "S8 cd <worktree> || push: runs only if the cd failed" \
  "$S8_MAIN" "cd $S8_WT || git push"
expect_allow_in "S8 cd <worktree> || exit 1; push: the guard shape" \
  "$S8_MAIN" "cd $S8_WT || exit 1; git push origin feat"
expect_block_in "S8 cd <worktree> && cd - && push: back somewhere unknown" \
  "$S8_MAIN" "cd $S8_WT && cd - && git push"
expect_block_in "S8 pushd <worktree> && popd && push" \
  "$S8_MAIN" "pushd $S8_WT && popd && git push"
expect_block_in "S8 ( cd <worktree> ) && push: the group's move ends with it" \
  "$S8_MAIN" "( cd $S8_WT ) && git push"
expect_allow_in "S8 ( cd <worktree> && push ): the move holds inside the group" \
  "$S8_MAIN" "( cd $S8_WT && git push origin feat )"
expect_allow_in "S8 cd <worktree> && ( push ): the group starts where its parent is" \
  "$S8_MAIN" "cd $S8_WT && ( git push origin feat )"
expect_block_in "S8 sh -c 'cd <worktree>' && push: a child shell's move never comes back" \
  "$S8_MAIN" "sh -c 'cd $S8_WT' && git push"

# --- second critic pass (2026-09-02): the shell's rules, not a looser reading ---
S8_RS=$'\036'
expect_block_in "S8 a literal RS cannot hide an explicit main push from Block 1" \
  "$S8_WT"   "cd x${S8_RS}; git push origin main"
expect_block_in "S8 a literal RS cannot hide a force push from Block 2" \
  "$S8_WT"   "cd x${S8_RS}; git push --force origin feat"
expect_allow_in "S8 a literal RS in the cd target is a space (the move still reads)" \
  "$S8_MAIN" "cd ${S8_WT}${S8_RS} && git push origin feat"
expect_block_in "S8 ( cd <worktree> ); ( push ): sibling groups do not share a move" \
  "$S8_MAIN" "( cd $S8_WT ); ( git push )"
expect_block_in "S8 ( cd <worktree> ) && ( push )" \
  "$S8_MAIN" "( cd $S8_WT ) && ( git push )"
expect_block_in "S8 ( ( cd <worktree> ) ); ( push )" \
  "$S8_MAIN" "( ( cd $S8_WT ) ); ( git push )"
expect_block_in "S8 cd <main> || cd <worktree>; push: the shell is in main" \
  "$S8_WT"   "cd $S8_MAIN || cd $S8_WT; git push"
expect_allow_in "S8 cd <worktree> || cd <main>; push: the shell is in the worktree" \
  "$S8_MAIN" "cd $S8_WT || cd $S8_MAIN; git push origin feat"
expect_block_in "S8 ( cd <main> ) || cd <worktree>; push: the group succeeded" \
  "$S8_MAIN" "( cd $S8_MAIN ) || cd $S8_WT; git push"
expect_block_in "S8 cd <worktree> && cmd & push: the whole list ran in the background" \
  "$S8_MAIN" "cd $S8_WT && git status & git push"
expect_allow_in "S8 cd <worktree> && push &: that push runs in the worktree" \
  "$S8_MAIN" "cd $S8_WT && git push origin feat &"
expect_allow_in "S8 cd <worktree> && a | b; push: a pipeline inside the list keeps the move" \
  "$S8_MAIN" "cd $S8_WT && echo x | grep x; git push origin feat"
expect_block_in "S8 cd <worktree> && eval 'cd <main>' && push: eval moved the shell" \
  "$S8_MAIN" "cd $S8_WT && eval 'cd $S8_MAIN' && git push"
expect_allow_in "S8 eval 'cd <worktree>' && push: eval's move holds" \
  "$S8_MAIN" "eval 'cd $S8_WT' && git push origin feat"
expect_block_in "S8 pushd -n <worktree> && push: -n only stacks" \
  "$S8_MAIN" "pushd -n $S8_WT && git push"
expect_allow_in "S8 a # comment on the cd line" \
  "$S8_MAIN" "$(printf 'cd %s  # into the worktree\ngit push origin feat' "$S8_WT")"

# --- fail-closed: a target git cannot read falls back to the hook cwd ---
expect_block_in "S8 cd to a directory that is not a repo" \
  "$S8_MAIN" "cd $S8_NOREPO && git push origin feat"
expect_block_in "S8 cd to a directory that does not exist" \
  "$S8_MAIN" "cd $S8/nowhere && git push origin feat"
expect_block_in "S8 git -C a directory that does not exist" \
  "$S8_MAIN" "git -C $S8/nowhere push origin feat"

# --- Blocks 1 and 2 do not move ---
expect_block_in "S8 an explicit master refspec from the worktree" \
  "$S8_MAIN" "cd $S8_WT && git push origin HEAD:master"
expect_block_in "S8 an explicit main destination via -C" \
  "$S8_MAIN" "git -C $S8_WT push origin main"
expect_block_in "S8 a force push from the worktree" \
  "$S8_MAIN" "cd $S8_WT && git push --force origin feat"

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
