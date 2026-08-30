#!/bin/bash
# Tests for scripts/lib/git-argv.sh — the shared "read a Bash command the way
# git reads it" library, and the two walls that source it.
#
# Four subjects, in the order a reader needs them:
#
#   Section 1  the library itself: segmentation, quoting, heredoc-body removal,
#              global-option skipping, refspec destination parsing (spec R-3).
#   Section 2  FAIL-CLOSED SOURCING (AC-12): a copy of the shipped tree with the
#              library renamed away must make BOTH hooks refuse, not allow. Run
#              in both real layouts — the installed plugin (hooks/ and scripts/
#              as siblings) and this repo (payload/hooks -> ../hooks symlink,
#              library under payload/scripts/lib/).
#   Section 3  every `source`/`.` line in the hooks directory names a file that
#              exists in the shipped library directory (AC-12, second half).
#   Section 4  the evidence gate's command reading (AC-11) — it fires on the
#              git global-option commit spellings and stays silent on prose and
#              heredoc bodies. It lives here, not in the evidence-gate suite,
#              because the behaviour under test is this library.
#
# Usage: bash tests/git-argv.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

PASS=0
FAIL=0
TOTAL=0

US=$'\037'

# ---------- locating the library the same way a hook does ----------
# The hooks try two candidates because the shipped tree has two real shapes:
# the installed plugin root (<root>/hooks + <root>/scripts) and this checkout
# (<repo>/hooks is the physical directory, <repo>/payload/scripts holds the
# library, and <repo>/payload/hooks is a symlink to the former). Resolving the
# library here the same way keeps the suite honest against either.
LIB=""
for cand in "${BIONIC_HOOKS_DIR}/../scripts/lib/git-argv.sh" \
            "${BIONIC_HOOKS_DIR}/../payload/scripts/lib/git-argv.sh"; do
  if [ -r "$cand" ]; then LIB="$cand"; break; fi
done
LIBDIR=""
[ -n "$LIB" ] && LIBDIR="$(cd "$(dirname "$LIB")" && pwd -P)"

if [ -z "$LIB" ]; then
  echo "FAIL: scripts/lib/git-argv.sh not found from ${BIONIC_HOOKS_DIR}"
  echo ""
  echo "========================================"
  echo "Results: 0/1 passed, 1 failed"
  echo "========================================"
  exit 1
fi

# shellcheck source=/dev/null
. "$LIB"

PROTECT_MAIN="${BIONIC_HOOKS_DIR}/protect-main.sh"
EVIDENCE_GATE="${BIONIC_HOOKS_DIR}/canonical-sdlc-evidence-gate.sh"

cleanup_dirs=()
cleanup() {
  local d
  for d in ${cleanup_dirs[@]+"${cleanup_dirs[@]}"}; do rm -rf "$d"; done
}
trap cleanup EXIT

# ---------- assertion helpers ----------

ok() {
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"
}
no() {
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"
  [ $# -gt 1 ] && echo "  $2"
  return 0
}
eq() {  # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2] got [$3]"; fi
}

# Renders the library's segment/token output in a readable form: one segment
# per line, tokens joined by `|`.
segs() { git_argv_segments "$1" | tr "$US" '|'; }

# Parses the FIRST git segment of a whole command line.
parse_cmd() {
  local line
  GIT_SUB=""; GIT_ARGS=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if git_argv_parse "$line"; then return 0; fi
  done <<< "$(git_argv_segments "$1")"
  return 1
}

# ============================================================
# Section 1: the library
# ============================================================

echo ""
echo "=== Section 1: segmentation, quoting, heredoc bodies ==="

eq "plain command tokenises" \
   "git|push|origin|main" "$(segs 'git push origin main')"

eq "double quotes are honoured, not dropped" \
   "git|push|origin|main" "$(segs 'git push origin "main"')"

eq "single quotes are honoured, not dropped" \
   "git|push|origin|main" "$(segs "git push origin 'main'")"

eq "a quoted span with spaces stays ONE token" \
   "echo|git push origin main" "$(segs "echo 'git push origin main'")"

eq "operators are segment boundaries" \
   "$(printf 'a\nb|x\nc\nd|y')" "$(segs 'a && b x ; c || d y')"

eq "a pipe is a segment boundary" \
   "$(printf 'cat|f\ngrep|x')" "$(segs 'cat f | grep x')"

eq "an operator inside quotes is NOT a boundary" \
   "echo|a && b" "$(segs 'echo "a && b"')"

# The heredoc body is removed BEFORE tokenising: a push line inside a body is
# text the shell writes to a file, not a command it runs. This is the AC-10
# false-positive the old newline-is-a-boundary split produced.
HD_PUSH=$(printf 'cat > /tmp/n.txt <<%sNOTE%s\ngit push origin main\nNOTE\n' "'" "'")
eq "heredoc body is removed (push)" \
   "$(printf 'cat|/tmp/n.txt')" "$(segs "$HD_PUSH")"

HD_COMMIT=$(printf 'cat > /tmp/n.txt <<%sNOTE%s\ngit commit -m x\nNOTE\n' "'" "'")
eq "heredoc body is removed (commit)" \
   "$(printf 'cat|/tmp/n.txt')" "$(segs "$HD_COMMIT")"

HD_TABS=$(printf 'cat <<-EOF\n\tgit commit -m x\n\tEOF\n')
eq "heredoc body is removed (<<- with tab-indented terminator)" \
   "cat" "$(segs "$HD_TABS")"

HD_AFTER=$(printf 'cat > /tmp/n.txt <<%sNOTE%s\ngit commit -m x\nNOTE\ngit status\n' "'" "'")
eq "the command AFTER a heredoc still parses" \
   "$(printf 'cat|/tmp/n.txt\ngit|status')" "$(segs "$HD_AFTER")"

# `<<<` is a here-STRING: no body, no terminator, and its operand is an
# ordinary word on that line. What matters is that it does not open a body and
# swallow the command on the next line.
eq "a here-string is not a heredoc opener" \
   "$(printf 'grep|x|y\ngit|status')" "$(segs "$(printf 'grep x <<< y\ngit status\n')")"

echo ""
echo "=== Section 1b: git global options and the subcommand ==="

parse_cmd 'git -C /tmp/r push origin main' && eq "-C <dir> is skipped with its value" "push" "$GIT_SUB" \
  || no "-C <dir> is skipped with its value" "no git segment parsed"
parse_cmd 'git -c user.name=x push origin main' && eq "-c <cfg> is skipped with its value" "push" "$GIT_SUB" \
  || no "-c <cfg> is skipped with its value" "no git segment parsed"
parse_cmd 'git --no-pager commit -m x' && eq "--no-pager (bare global) is skipped" "commit" "$GIT_SUB" \
  || no "--no-pager (bare global) is skipped" "no git segment parsed"
parse_cmd 'git --git-dir=/tmp/r/.git commit -m x' && eq "--git-dir=<v> consumes no extra word" "commit" "$GIT_SUB" \
  || no "--git-dir=<v> consumes no extra word" "no git segment parsed"
parse_cmd 'GIT_SSH_COMMAND=ssh git push origin main' && eq "leading VAR=value assignment is skipped" "push" "$GIT_SUB" \
  || no "leading VAR=value assignment is skipped" "no git segment parsed"
parse_cmd "env GIT_AUTHOR_DATE='2026-04-11' git commit -m x" && eq "env prefix is skipped" "commit" "$GIT_SUB" \
  || no "env prefix is skipped" "no git segment parsed"
parse_cmd '/usr/bin/git commit -m x' && eq "an absolute git path still parses" "commit" "$GIT_SUB" \
  || no "an absolute git path still parses" "no git segment parsed"

if parse_cmd "echo 'git push origin main'"; then
  no "quoted prose is not a git command" "parsed as git ${GIT_SUB}"
else
  ok "quoted prose is not a git command"
fi
if parse_cmd "grep 'git push' README.md"; then
  no "grep over a file naming a push is not a git command" "parsed as git ${GIT_SUB}"
else
  ok "grep over a file naming a push is not a git command"
fi
if parse_cmd "$HD_PUSH"; then
  no "a heredoc body is not a git command" "parsed as git ${GIT_SUB}"
else
  ok "a heredoc body is not a git command"
fi

echo ""
echo "=== Section 1c: git_push_targets — destinations and force ==="

dests_of() {  # <command> -> destinations joined by `|`
  parse_cmd "$1" || { echo "<not-a-git-command>"; return 0; }
  git_push_targets
  printf '%s' "$GIT_DESTS" | tr "$US" '|'
}
force_of() {
  parse_cmd "$1" || { echo "?"; return 0; }
  git_push_targets
  printf '%s' "$GIT_FORCE"
}

eq "plain refspec"                 "origin|main"        "$(dests_of 'git push origin main')"
eq "refs/heads/ prefix is stripped" "origin|main"       "$(dests_of 'git push origin refs/heads/main')"
eq "HEAD:refs/heads/main -> main"  "origin|main"        "$(dests_of 'git push origin HEAD:refs/heads/main')"
eq "feature:refs/heads/main -> main" "origin|main"      "$(dests_of 'git push origin feature:refs/heads/main')"
eq "HEAD:refs/heads/feature/main -> feature/main" "origin|feature/main" \
   "$(dests_of 'git push origin HEAD:refs/heads/feature/main')"
eq "delete refspec :main -> main"  "origin|main"        "$(dests_of 'git push origin :main')"
eq "leading + is stripped"         "origin|main"        "$(dests_of 'git push origin +main')"
eq "topic/main is its own branch"  "origin|topic/main"  "$(dests_of 'git push origin topic/main')"
eq "main-fixes is its own branch"  "origin|main-fixes"  "$(dests_of 'git push origin main-fixes')"
eq "-u is not a destination"       "origin|main"        "$(dests_of 'git push -u origin main')"

eq "no force by default"           "0" "$(force_of 'git push origin main')"
eq "-f sets force"                 "1" "$(force_of 'git push -f origin feature')"
eq "--force sets force"            "1" "$(force_of 'git push --force origin feature')"
eq "--force-with-lease sets force" "1" "$(force_of 'git push --force-with-lease origin feature')"
eq "--force-with-lease=<ref> sets force" "1" "$(force_of 'git push --force-with-lease=main origin feature')"
eq "a leading + sets force"        "1" "$(force_of 'git push origin +main')"
eq "-C <dir> does not hide --force" "1" "$(force_of 'git -C /tmp/r push --force origin feature')"

# ============================================================
# Section 2: fail-closed sourcing (AC-12)
# ============================================================
#
# Chris's D1 ruling: a wall that cannot load its library REFUSES. The proof is
# a copy of the shipped tree with the library renamed away — each hook must
# exit non-zero on a command it would otherwise wave through.

echo ""
echo "=== Section 2: a hook whose library is missing REFUSES ==="

run_hook_at() {  # <hook path> <command> -> sets RC and ERRTXT
  local hook="$1" cmd="$2" input tmp_err
  input=$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')
  tmp_err=$(mktemp)
  if printf '%s' "$input" | bash "$hook" >/dev/null 2>"$tmp_err"; then RC=0; else RC=$?; fi
  ERRTXT=$(cat "$tmp_err"); rm -f "$tmp_err"
}

make_layout() {  # <style: installed|payload> -> echoes the tree root
  local style="$1" root libdir
  root=$(mktemp -d); cleanup_dirs+=("$root")
  mkdir -p "$root/hooks"
  cp "$PROTECT_MAIN" "$root/hooks/protect-main.sh"
  cp "$EVIDENCE_GATE" "$root/hooks/canonical-sdlc-evidence-gate.sh"
  if [ "$style" = "installed" ]; then
    libdir="$root/scripts/lib"
  else
    libdir="$root/payload/scripts/lib"
    mkdir -p "$root/payload"
    ln -s ../hooks "$root/payload/hooks"
  fi
  mkdir -p "$libdir"
  cp "$LIB" "$libdir/git-argv.sh"
  echo "$root"
}

for style in installed payload; do
  root=$(make_layout "$style")
  if [ "$style" = "installed" ]; then hookdir="$root/hooks"; else hookdir="$root/payload/hooks"; fi

  # Positive control first — the copied tree WORKS, so a later refusal is the
  # missing library and not a broken fixture.
  run_hook_at "$hookdir/protect-main.sh" "ls -la"
  if [ "$RC" -eq 0 ]; then ok "$style layout: protect-main loads its library and allows 'ls -la'"
  else no "$style layout: protect-main loads its library and allows 'ls -la'" "rc=$RC err='$ERRTXT'"; fi

  run_hook_at "$hookdir/canonical-sdlc-evidence-gate.sh" "ls -la"
  if [ "$RC" -eq 0 ]; then ok "$style layout: evidence gate loads its library and allows 'ls -la'"
  else no "$style layout: evidence gate loads its library and allows 'ls -la'" "rc=$RC err='$ERRTXT'"; fi

  # And it still reads commands correctly through this layout.
  run_hook_at "$hookdir/protect-main.sh" 'git push origin main'
  if [ "$RC" -ne 0 ]; then ok "$style layout: protect-main still blocks an explicit main push"
  else no "$style layout: protect-main still blocks an explicit main push" "rc=0"; fi

  # Now rename the library away.
  if [ "$style" = "installed" ]; then libfile="$root/scripts/lib/git-argv.sh"
  else libfile="$root/payload/scripts/lib/git-argv.sh"; fi
  mv "$libfile" "$libfile.renamed"

  run_hook_at "$hookdir/protect-main.sh" "ls -la"
  if [ "$RC" -ne 0 ] && printf '%s' "$ERRTXT" | grep -q 'git-argv.sh'; then
    ok "$style layout: protect-main REFUSES with the library renamed away, naming the path"
  else
    no "$style layout: protect-main REFUSES with the library renamed away, naming the path" "rc=$RC err='$ERRTXT'"
  fi

  run_hook_at "$hookdir/canonical-sdlc-evidence-gate.sh" "ls -la"
  if [ "$RC" -ne 0 ] && printf '%s' "$ERRTXT" | grep -q 'git-argv.sh'; then
    ok "$style layout: evidence gate REFUSES with the library renamed away, naming the path"
  else
    no "$style layout: evidence gate REFUSES with the library renamed away, naming the path" "rc=$RC err='$ERRTXT'"
  fi
done

# ============================================================
# Section 3: every source line resolves inside the shipped tree
# ============================================================

echo ""
echo "=== Section 3: hook source lines name shipped library files ==="

# Two halves, because a hook's `source` names a VARIABLE and the path it holds
# is written elsewhere:
#   (a) every hook that loads a library at all — the `.`/`source` command, not
#       a mention in a comment;
#   (b) every literal library path expression in the hooks. Each must live
#       under scripts/lib/, must be relative to the hook's own directory
#       (never absolute, never $HOME, never ~), and must name a file that
#       exists in the shipped library directory.
# Section 2 proves the runtime half — that those expressions actually resolve
# through both real tree shapes, and that a hook refuses when they do not.

SOURCERS=0
for hook in "${BIONIC_HOOKS_DIR}"/*.sh; do
  n=$(grep -cE '(^|[[:space:]]|;)(\.|source)[[:space:]]+["$/]' "$hook" || true)
  if [ "${n:-0}" -gt 0 ]; then SOURCERS=$((SOURCERS + 1)); fi
done

if [ "$SOURCERS" -ge 2 ]; then
  ok "at least two hooks load a library (found $SOURCERS)"
else
  no "at least two hooks load a library (found $SOURCERS)" \
     "protect-main.sh and canonical-sdlc-evidence-gate.sh must each source git-argv.sh"
fi

LIB_REFS=0
BAD_SOURCE=""
for hook in "${BIONIC_HOOKS_DIR}"/*.sh; do
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    LIB_REFS=$((LIB_REFS + 1))
    case "$ref" in
      /*|'~'*|*'$HOME'*|*'${HOME}'*)
        BAD_SOURCE="$BAD_SOURCE$(basename "$hook"): $ref (not hook-relative)"$'\n' ;;
    esac
    base="${ref##*/}"
    if [ ! -f "$LIBDIR/$base" ]; then
      BAD_SOURCE="$BAD_SOURCE$(basename "$hook"): $ref (no $base in $LIBDIR)"$'\n'
    fi
  done <<< "$(grep -ohE '[^ "'"'"']*scripts/lib/[A-Za-z0-9._-]+\.sh' "$hook" || true)"
done

if [ "$LIB_REFS" -ge 2 ]; then
  ok "the hooks name at least two library paths (found $LIB_REFS)"
else
  no "the hooks name at least two library paths (found $LIB_REFS)" "expected the git-argv.sh candidates"
fi

if [ -z "$BAD_SOURCE" ]; then
  ok "every library path a hook names is hook-relative and exists in the shipped tree"
else
  no "every library path a hook names is hook-relative and exists in the shipped tree" "$BAD_SOURCE"
fi

# ============================================================
# Section 4: the evidence gate's command reading (AC-11)
# ============================================================

echo ""
echo "=== Section 4: evidence gate fires on git global-option commit forms ==="

FM='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: tested
scale: wave
deploy_target: none
use_worktree: false
has_ui: false
---'

EG_HOME=$(mktemp -d); cleanup_dirs+=("$EG_HOME")
mkdir -p "$EG_HOME/.claude/plans" "$EG_HOME/.bionic/docs/plans"
printf '%s\n' "$FM
## SDLC State
current: 5
Step 5: TODO" > "$EG_HOME/.bionic/docs/plans/active.md"

run_gate() {  # <command>
  local input tmp_err
  input=$(jq -n --arg c "$1" --arg cwd "$EG_HOME" '{tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp)
  if HOME="$EG_HOME" CLAUDE_PROJECT_DIR="" bash "$EVIDENCE_GATE" <<< "$input" >/dev/null 2>"$tmp_err"; then
    RC=0
  else
    RC=$?
  fi
  ERRTXT=$(cat "$tmp_err"); rm -f "$tmp_err"
}

gate_fires() {
  local label="$1" cmd="$2"
  run_gate "$cmd"
  if [ "$RC" -eq 2 ]; then ok "$label"; else no "$label" "rc=$RC err='$ERRTXT'"; fi
}
gate_silent() {
  local label="$1" cmd="$2"
  run_gate "$cmd"
  if [ "$RC" -eq 0 ] && [ -z "$ERRTXT" ]; then ok "$label"; else no "$label" "rc=$RC err='$ERRTXT'"; fi
}

# Positive control: the fixture blocks a plain commit, so a silence below is
# the command reading and not an inert plan.
gate_fires  "plain git commit blocks (positive control)" 'git commit -m x'
gate_fires  "git -C <dir> commit blocks"                 'git -C /tmp/r commit -m x'
gate_fires  "git -c <cfg> commit blocks"                 'git -c user.name=x commit -m x'
gate_fires  "git --no-pager commit blocks"               'git --no-pager commit -m x'
gate_silent "echo naming a commit is silent"             'echo "we will git commit later"'
gate_silent "a heredoc body naming a commit is silent"   "$HD_COMMIT"
gate_silent "git status is silent"                       'git status'
gate_silent "a push is not a commit"                     'git push origin feature'

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
