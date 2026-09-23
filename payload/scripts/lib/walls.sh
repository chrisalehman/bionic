#!/bin/bash
# payload/scripts/lib/walls.sh — THE FIVE PreToolUse|Bash WALLS, AS FUNCTIONS
# (epic-23 wave-11-lean-spine, REQ-1f (v), AC-1f.5; ADR-004; user ruling A-50
# "Option 3", 2026-09-12: the fold is ONE event-agnostic mechanism).
#
# WHAT THIS FILE IS. Five hook files used to fire on every Bash tool call —
# hooks/protect-main.sh, hooks/protect-database.sh,
# hooks/canonical-sdlc-evidence-gate.sh, hooks/farm-out-reminder.sh and
# hooks/background-suite-guard.sh — each paying the loader and the preamble, each
# answering the harness separately, and NO RULE saying how five answers combine. The
# bodies are here now, one function each, and payload/scripts/lib/fold.sh composes
# what they say by the rule T12 wrote for the four Stop walls:
#
#     any block is a block · all reasons print · blocks before advisories
#
# THE CONTRACT EACH FUNCTION SIGNS (fold.sh's, unchanged): it never renders and never
# exits. It stages with `fold_block <mode> <verb> <fact> <fix> <detail>` and returns 2,
# or `fold_advise`/`fold_context` and returns 1, or stages nothing and returns 0 — and
# THE RETURN CODE IS THE VERDICT while the staged text is only the words for it.
#
# WHAT MOVED OUT OF THE BODIES AND INTO hooks/bash-walls.sh, ONCE. The payload read,
# the command read, `bionic_context`, and the engagement predicate
# `[ "$BIONIC_ENGAGED" = 1 ]` — five identical spellings of one question, which is
# what the merge was for. Each function keeps the WORDS that say why its scope is what
# it is; only the duplicated line is gone.
#
# THEY SHARE A SHELL, SO THEY SHARE A NAMESPACE. Every value a body assigns is
# `local` to its function, and two shell OPTIONS are restored on every exit path
# rather than at the end of a file that no longer ends the process — see
# `wall_background_suite_guard`'s `set -f`. The one thing a wall may leave behind is a
# file it wrote, which is what it always was.
#
# THE ORDER IS THE MANIFEST'S, and hooks/bash-walls.sh spells it: protect-main,
# protect-database, the evidence gate, farm-out-reminder, background-suite-guard. The
# functions are independent — none reads state another writes during one event — so
# the order decides how a composed refusal READS, not what it decides.
#
# FOUR OF THE FIVE REFUSE BY exit 2 WITH THE TEXT ON STDERR; farm-out-reminder alone
# answers on stdout as JSON (`deny` for a block, `hookSpecificOutput.additionalContext`
# for a nudge). That difference is preserved to the byte: `refuse` is still the one
# renderer, `bionic_fold` still makes exactly one call to it, and the nudge rides
# `fold_context`, which is the channel this wave added to the fold for exactly this
# wall (A-53, T23 ruling R3).
#
# NO PRODUCER PROCESS MAY OUTLIVE A QUITTING `grep -q` (T37, wave-14). Every membership
# test in this file reads its subject from a HERE-STRING — `grep -qE PAT <<< "$VAR"` —
# and never from `echo "$VAR" | grep -q`. hooks/bash-walls.sh sources this file under
# `set -uo pipefail` (:86). `grep -q` exits at its FIRST match; when the subject is
# larger than the 64 KB pipe buffer the producer is still writing, takes SIGPIPE, and
# exits 141 — and `pipefail` promotes that 141 over grep's own 0, so `if !` reads a
# MATCH as a failure. That is not theoretical: the evidence gate refused every commit in
# this repo once the plan's `## Verification Matrix` section passed 64 KB, on a plan
# whose `stack-health:` line was present and valid. A here-string has no second process
# to lose, and it forks one fewer than the pipeline did. The same rule holds in
# hooks/dispatch-preflight.sh (:1200) and hooks/stop-guard.sh, the other readers under
# `pipefail`; tests/cross-gate-agreement.test.sh pins the idiom's absence repo-wide.
#
# ONE CAVEAT THE PIPELINE DID NOT HAVE: `<<<` APPENDS A NEWLINE to its word, so an empty
# subject becomes one empty line. Only a pattern that can match empty notices — in
# practice `grep -qxF -- "$needle"` with an empty needle — so a whole-line membership
# test guards its needle as well as its haystack (hooks/session-sweeper.sh `row_acked`).
#
# BASH 3.2. SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME — the rule every
# library in this directory follows, for lib/context.sh's reason: callers read library
# answers through `$( )` and anything printed on the way in corrupts the first field
# of every one.
#
# [WALL: tests/bash-walls.test.sh]
# [WALL: tests/protect-main.test.sh]
# [WALL: tests/protect-database.test.sh]
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
# [WALL: tests/farm-out-reminder.test.sh]
# [WALL: tests/background-suite-guard.test.sh]

# ─── THE PER-WALL LIBRARY DECLARATION (A-56.1, A-56.2) ───────────────────────
#
# ONE TABLE, TWO READERS, AND IT IS WHY THE COMPOUND DOES NOT FAIL CLOSED ON A
# LIBRARY ONLY AN ADVISORY WALL WANTS. The five hooks each declared their own
# `BIONIC_LIB_WANT`; folding them made hooks/bash-walls.sh's WANT the UNION of
# five lists, and a union is fail-closed at its widest member — `cmd-class.sh`
# absent refused EVERY Bash command in every project, where before it only made
# farm-out-reminder and background-suite-guard step aside (measured: cmd-class
# C5, runner-T23-suites at 5a6e053). R4 says fail-closed is per wall, so the
# carrier's WANT is the two closed walls' union and NOTHING ELSE, and a library
# only an advisory wall needs is sourced by that wall's own function, below.
#
# THE ROWS ARE THE PRE-FOLD `BIONIC_LIB_WANT` LINES, unchanged — read them back
# with `git show 60c528b:hooks/<wall>.sh | grep BIONIC_LIB_WANT=`. They do NOT
# name fold.sh or walls.sh: those two are what the COMPOUND is made of rather
# than what a wall asks for, and hooks/bash-walls.sh declares them itself.
#
# THE SECOND READER IS DOCTOR. payload/scripts/lib/checks.sh builds
# BIONIC_WALL_HOOKS out of these variable names, so doctor's walls row stays
# PER WALL — five verdicts, each naming the wall and the library it wanted —
# rather than collapsing to one row for the carrier that would tell a reader
# "bash-walls cannot load cmd-class.sh" and leave them to guess which of five
# behaviours that costs them.
#
# THE NAME MANGLE IS THE FUNCTION NAMES' OWN: `-` becomes `_`, exactly as
# `wall_farm_out_reminder` spells `farm-out-reminder`. No wall name carries an
# underscore, so the inverse is unambiguous and checks.sh takes it.
BIONIC_WALL_LIBS_protect_main="context.sh git-argv.sh refuse.sh root.sh run.sh session.sh"
BIONIC_WALL_LIBS_protect_database="context.sh refuse.sh root.sh run.sh session.sh"
BIONIC_WALL_LIBS_canonical_sdlc_evidence_gate="context.sh git-argv.sh refuse.sh root.sh run.sh session.sh units.sh"
BIONIC_WALL_LIBS_farm_out_reminder="cmd-class.sh context.sh refuse.sh root.sh run.sh session.sh"
BIONIC_WALL_LIBS_background_suite_guard="cmd-class.sh context.sh refuse.sh root.sh run.sh session.sh"

# THE HOOK THAT CARRIES ALL FIVE, declared here because the table's other reader
# has to turn a wall NAME into a file on disk and there is exactly one answer.
BIONIC_WALL_CARRIER="bash-walls"

# ─── wall_libs — an advisory wall's own loader, for the files the carrier did
#     not demand ─────────────────────────────────────────────────────────────
#
# THE LINE IT PRINTS IS THE LINE THE HOOK PRINTED. `loader_fail_open` in every
# pre-fold hook said exactly this, with the hook's own name in front:
#
#     farm-out-reminder: library cmd-class.sh not found at <candidates> —
#     hook stepping aside; run /bionic:doctor
#
# so a user who has seen a broken install before sees the same sentence, and the
# WALL is named rather than the compound — which is the whole point of keeping
# this per wall. (The fail-CLOSED refusal names `bash-walls`, per A-54, because
# there it really is the compound that refused.)
#
# ONE LINE PER WALL, NOT ONE PER PROCESS. Two advisory walls wanting the same
# absent file say so twice, once each, because they are two walls that stepped
# aside and a reader who is told once cannot tell which. The sourcing itself is
# done at most once per file per process — the message is the part that repeats.
_bionic_wall_sourced=" "
wall_libs() {  # <wall name> <basename>… -> 0 all sourced · 1 one named, caller returns 0
  local who="$1"; shift
  local f
  for f in "$@"; do
    [ -r "$BIONIC_LIB/$f" ] && continue
    echo "$who: library $f not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
    return 1
  done
  for f in "$@"; do
    case "$_bionic_wall_sourced" in *" $f "*) continue ;; esac
    # shellcheck source=/dev/null
    . "$BIONIC_LIB/$f" || return 1
    _bionic_wall_sourced="${_bionic_wall_sourced}${f} "
  done
  return 0
}

# ─── _wall_flatten — the one-line form of a command, without a pipeline ──────
#
# Sets `_WALL_FLAT` to `$1` with every run of whitespace collapsed to one space
# and the ends trimmed. It replaces, character for character in its output, the
# three-fork pipeline two walls carried:
#
#     printf '%s' "$c" | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' \
#       | tr '\n' ' ' | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//'
#
# THE CR PASS DISAPPEARS BECAUSE THE SQUEEZE SWALLOWS IT (REQ-10, T11). awk
# turned CRLF into one newline and a lone CR into another, `tr` turned every
# newline into a space, and `sed` then collapsed every run of whitespace to a
# single space — so the CR normalisation could only ever decide whether a run of
# whitespace was one character or two, which the squeeze erases either way. What
# is left is exactly "split on whitespace, join with one space", and that is
# shell word-splitting.
#
# IFS CARRIES ALL SIX CHARACTERS `[[:space:]]` NAMES — space, tab, newline,
# carriage return, vertical tab, form feed — because `sed`'s squeeze did, and a
# narrower IFS would leave a form feed sitting inside a token that used to be a
# separator.
#
# `set -f` IS NOT OPTIONAL. Unquoted word-splitting also globs, and this function
# is handed command lines: `ls *.sh` would come back as the directory listing. The
# previous setting is restored rather than assumed, so a caller that had already
# disabled globbing keeps it disabled.
#
# IT ASSIGNS RATHER THAN PRINTS, so no caller needs a command substitution: the
# pipeline it replaces cost three forks and the `$( )` around it a fourth.
_WALL_FLAT=""
_wall_flatten() {  # <text> -> sets _WALL_FLAT
  local _w _out="" _glob=0 IFS=$' \t\n\r\v\f'
  case $- in *f*) _glob=1 ;; esac
  set -f
  for _w in $1; do
    if [ -z "$_out" ]; then _out="$_w"; else _out="$_out $_w"; fi
  done
  [ "$_glob" = 1 ] || set +f
  _WALL_FLAT="$_out"
}

# ─── _wall_mentions_git — the cheap superset of "this could be a git command" ─
#
# 0 when `git` could still be argv[0] of some segment of `$1`, 1 when the parser
# in payload/scripts/lib/git-argv.sh provably cannot find one (REQ-10, T11).
#
# WHY A SUPERSET IS SOUND HERE, AND WHY IT IS SPELLED LIKE THIS. `git_argv_parse`
# accepts argv[0] only as the literal `git` or a path ending `/git`
# (git-argv.sh's `git|*/git) shift`), and the only transformation between the
# command TEXT and that token is unquoting: the parser strips backslashes and
# quote characters and does not expand variables, globs or `$'…'`. So the three
# characters `git` must survive in the text with nothing but backslashes and
# quotes between them — which is what removing those three characters first and
# then looking for the substring tests. `\g\i\t push`, `'g'it push` and
# `"gi"t push` all still reach the parser; a command with no `git` in it at any
# spelling the parser can read skips two full awk passes.
#
# THE ONE TRANSFORMATION THAT IS NOT UNQUOTING (wave-14 T24, security 1b). A backslash
# followed by a NEWLINE is a line continuation: the shell joins the two lines and the
# newline goes with the backslash. Removing the backslash alone left the newline standing
# between `g` and `it`, so the screen answered "provably not" for `g\<newline>it commit`
# while `git_argv_has_sub` answered `commit` for the same string — the whole evidence gate
# skipped for a real commit, and a `g\<newline>it push origin main` invisible to
# protect-main. The pair is removed FIRST, before the lone backslashes, because after they
# are gone the continuation is indistinguishable from a newline that separates two
# commands. Both readers of this screen are fixed by that one line.
#
# IT IS A SCREEN, NEVER A VERDICT. A hit runs the real parser and the parser
# decides; only a miss short-circuits, and a miss is the case the parser was
# always going to answer "no push, no commit" to.
_wall_mentions_git() {  # <command text> -> 0 maybe · 1 provably not
  local _p="$1"
  _p="${_p//\\$'\n'/}"
  _p="${_p//\\/}"; _p="${_p//\'/}"; _p="${_p//\"/}"
  case "$_p" in *git*) return 0 ;; esac
  return 1
}

# ─── _wall_cmd_fill — ONE fill for the farm-out wall's three classifier readings ─
#
# THE THREE READINGS ARE ONE COMMAND READ THREE WAYS (epic-23 wave-14 T17, REQ-4;
# T4 §5 / A-T4.2). `wall_farm_out` asks the classifier three questions — the whole
# command's class (tier 1), each `&&` segment's class (the chain arm) and the
# reduced head (tier 2) — and each one used to arrive through its own command
# substitution over its own string: `$(cmd_strip_heredocs …)`, `$(cmd_unwrap_head …)`,
# an `awk` and a `grep` for the chain split, and a `sed` per segment to trim it.
# Measured on the bench payload (`ls -la`, tests/bench/hook-latency.sh), that was
# TWO awk execs and four bash forks on the hottest path in the tree, of which
# exactly one awk exec — the class reading — could change the answer.
#
# THIS FUNCTION ASSIGNS RATHER THAN PRINTS, the way `_wall_flatten` does, so no
# caller needs a command substitution to read it. It sets four values:
#
#   _WALL_SAFE_FLAT   the heredoc-free, whitespace-squeezed one-line command
#   _WALL_HEAD        the tier-2 head reduction, or "" when tier 2 provably cannot fire
#   _WALL_CHAIN_SEGS  the `&&` segments, newline-joined, untrimmed
#   _WALL_CHAIN_COUNT how many of them carry a non-blank character
#
# WHAT IS SKIPPED, AND WHY EACH SKIP IS SOUND — none of them is a new reading, and
# none of them narrows what the wall can see:
#
#  1. `cmd_strip_heredocs` IS THE IDENTITY for a command whose text holds no `<<`;
#     its own fast path says so and byte-identically (cmd-class.sh). So the `$( )`
#     around it is skipped for such a command rather than made to return its input.
#
#  2. THE HEAD REDUCTION IS COMPUTED ONLY WHEN TIER 2 COULD STILL FIRE, screened the
#     way `_wall_mentions_git` screens the git parser. `classify_tier2`'s own first
#     act is `case "$c" in git*|docker*|npx*|uvx*)` — all four matchers are anchored
#     at `^`, so nothing else can match — and the head reduction is a SUBSTRING of
#     the flattened command with at most one leading and one trailing quote
#     character removed: `strip_leading`, `skip_opts`, `drop_word` and `after_exec`
#     all return suffixes, and `unwrap_runner` returns a suffix, a `dequote_whole`
#     of one, or the literal prefix `bash `. So if the head starts with one of those
#     four words, those letters survive in the text with nothing but quotes and
#     backslashes between them — which is exactly what removing those characters and
#     then looking for the substring tests. A miss cannot be a tier-2 match, and the
#     empty head it leaves takes `classify_tier2`'s own `*) return 1` arm.
#
#  3. THE `&&` SPLIT IS SHELL, NOT `awk` + `grep`. `_WALL_SAFE_FLAT` has been through
#     `_wall_flatten`, whose IFS carries all six characters `[[:space:]]` names — so
#     it holds no newline, tab, CR, VT or FF at all, and the newline-joined segment
#     list is unambiguous by construction. The split is left-to-right and
#     non-overlapping on the literal two characters `&&`, which is what
#     `gsub(/&&/, "\n")` did, `&&&&` included; the count is of segments carrying a
#     non-blank character, which is what `grep -cE '[^[:space:]]'` counted.
#
# IT IS A FILL, NEVER A VERDICT. Every class this wall acts on still comes from
# `cmd_class` — one reader, cmd-class.sh — over the same strings as before.
_WALL_SAFE_FLAT=""; _WALL_HEAD=""; _WALL_CHAIN_SEGS=""; _WALL_CHAIN_COUNT=0
_wall_cmd_fill() {  # <raw command text> -> sets the four values above
  local _p _rest _seg _segs=""

  case "$1" in
    *'<<'*) _wall_flatten "$(cmd_strip_heredocs "$1")" ;;
    *)      _wall_flatten "$1" ;;
  esac
  _WALL_SAFE_FLAT="$_WALL_FLAT"

  _p="$_WALL_SAFE_FLAT"
  _p="${_p//\\/}"; _p="${_p//\'/}"; _p="${_p//\"/}"
  case "$_p" in
    *git*|*docker*|*npx*|*uvx*) _WALL_HEAD=$(cmd_unwrap_head "$_WALL_SAFE_FLAT") ;;
    *)                          _WALL_HEAD="" ;;
  esac

  _WALL_CHAIN_SEGS=""; _WALL_CHAIN_COUNT=0
  case "$_WALL_SAFE_FLAT" in
    *"&&"*)
      _rest="$_WALL_SAFE_FLAT"
      while :; do
        case "$_rest" in
          *"&&"*) _seg="${_rest%%&&*}"; _rest="${_rest#*&&}" ;;
          *)      _seg="$_rest"; _rest=""; _segs="$_segs$_seg"
                  case "$_seg" in *[![:space:]]*) _WALL_CHAIN_COUNT=$(( _WALL_CHAIN_COUNT + 1 )) ;; esac
                  break ;;
        esac
        _segs="$_segs$_seg"$'\n'
        case "$_seg" in *[![:space:]]*) _WALL_CHAIN_COUNT=$(( _WALL_CHAIN_COUNT + 1 )) ;; esac
      done
      _WALL_CHAIN_SEGS="$_segs"
      ;;
  esac
}

# ─── wall_protect_main — hooks/protect-main.sh ───────────────────────────────
#
# HARD BLOCK: Prevents AI from pushing to main/master branches.
# The user must push to main manually from their own terminal.
# [WALL: tests/protect-main.test.sh]
#
# THE COMMAND READER. Everything below asks the library what the words of this
# command line are; nothing here greps the raw text. Until 1.3.2 it did, and
# `git -C /tmp/r push origin main`, `git push origin "main"` and
# `git push origin feature:refs/heads/main` all walked past this wall while a
# heredoc that merely MENTIONED a push was refused.
#
# THE COMMAND IS STILL READ BEFORE THE LIBRARY IS, in hooks/bash-walls.sh and not
# here: the repair allowlist in `loader_fail_closed` needs the text, and it has to be
# consulted BEFORE the compound decides to refuse.
#
# FAIL-CLOSED (design ledger S4, Chris D1 2026-08-30): a wall over an IRREVERSIBLE
# action that cannot load its library refuses, because a wall that cannot read a
# command must not wave it through. That arm is the compound's now — one process
# either loads the library or does not — and this wall is the reason the compound
# has it at all, together with the evidence gate.
wall_protect_main() {  # <event> -> 0 nothing · 2 block

# ---------- THE ENGAGEMENT GUARD (AC-20): is this session bionic's at all? ----------
#
# FIRST, above every other scoping question this hook asks. Chris, 2026-09-03: "all
# guardrails imposed by bionic should only apply when exercising bionic. Nothing should
# apply until bionic is triggered" — and the trigger is the canonical-sdlc skill, which
# writes `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. A session that
# never invoked it is one this hook has nothing to say to, and it says nothing: exit 0,
# no stdout, no stderr.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — absent marker, a symlink at the path, a
# foreign or unshaped session key, no key at all. The marker is the one artifact whose
# PRESENCE opens a wall, so the fail direction is inverted here on purpose: the arming
# partition is the consent boundary (1.3.2 close-out), and a wall that binds a session
# which never consented is the defect this guard exists to remove.
# [WALL: tests/protect-main.test.sh]
#
# THE LOADER REFUSAL ABOVE IS NOT SCOPED BY THIS and cannot be: the predicate lives in
# the library that just failed to load. A broken plugin still refuses a push in any
# session, engaged or not — the one place this wall outruns the ruling, and the price of
# a fail-closed wall that cannot read its own scope.
#
# ASKED ONCE, IN hooks/bash-walls.sh, FOR ALL FIVE (T23). `bionic_context` and this
# predicate were spelled identically in each of the five walls and are now read once
# ahead of the fold — five identical answers to one question is what the merge was for.
# The words stay here because they are this wall's scope, not the caller's.

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
local IS_PUSH=0 segment rest dest CURRENT_BRANCH

# THE SCREEN BEFORE THE PARSE (REQ-10, T11). `git_argv_expand` is an awk pass over
# the whole command line and this wall runs on EVERY Bash tool call; a command that
# cannot contain a git invocation at all does not need one. `_wall_mentions_git`
# states the superset argument. `IS_PUSH` would have stayed 0 through the loop
# below and this function returns 0 either way.
_wall_mentions_git "$COMMAND" || return 0

while IFS= read -r segment; do
  [ -n "$segment" ] || continue
  git_argv_parse "$segment" || continue
  [ "$GIT_SUB" = "push" ] || continue
  IS_PUSH=1
  git_push_targets

  # Block 1: this push writes to a protected branch. GIT_DESTS is US-separated;
  # each destination is asked of git_branch_protected, which is the ONE place
  # `main` and `master` are named — payload/scripts/lib/worktree.sh's land wall
  # asks the same function about the branch it is about to merge into, and a
  # second copy of the list here is how the two would drift apart.
  # The split is pure parameter expansion: no subshell on the hot path of a hook
  # that runs on every Bash call. `topic/main` and `main-fixes` are their own
  # branches and stay allowed, because the predicate matches the whole name.
  # [WALL: tests/protect-main.test.sh]
  rest="$GIT_DESTS"
  while [ -n "$rest" ]; do
    dest="${rest%%"$GIT_ARGV_US"*}"
    if [ "$dest" = "$rest" ]; then rest=""; else rest="${rest#*"$GIT_ARGV_US"}"; fi
    [ -n "$dest" ] || continue
    if git_branch_protected "$dest"; then
      fold_block exit2 push "main is a protected branch here" "push from your own terminal" \
        "A push to main is the user's own act, never Claude's. The destination this segment resolved to is \"$dest\"."
      return 2
    fi
  done

  # Block 2: force pushes (always dangerous) [WALL: tests/protect-main.test.sh]
  if [ "$GIT_FORCE" -eq 1 ]; then
    fold_block exit2 push "this is a force push" "push from your own terminal" \
      "A force push rewrites published history and has no undo from here. Run it from your own terminal if you mean it."
    return 2
  fi
done <<< "$(git_argv_expand "$COMMAND")"

# Skip if no actual push command found
if [ "$IS_PUSH" -eq 0 ]; then
  return 0
fi

# Block 3: Any push while on main/master branch (catches implicit pushes
# like "git push origin", "git push origin HEAD", bare "git push")
#
# THE BRANCH ASKED ABOUT IS THE PAYLOAD'S, NOT THE HOOK PROCESS'S OWN (D2, REQ-5;
# P-B: a wall reads facts from its input, never from ambient process state). BIONIC_CWD
# is `bionic_context`'s resolved payload cwd (lib/context.sh rung 2), set once in
# hooks/bash-walls.sh before any wall runs. The hook process's own `pwd` is an accident
# of how the CLI launched it and is ordinarily the same directory (A2) — which is why
# this bug was invisible outside a test that deliberately makes the two differ.
#
# THE FALLBACK IS TODAY'S EXACT BEHAVIOUR, kept for the one case BIONIC_CWD cannot rule
# out: an empty or non-existent value. In practice `bionic_context`'s own rung 3 already
# defaults to `pwd`, so this branch is a defensive mirror of that default rather than a
# path this wall expects to take on its own.
# [WALL: tests/protect-main.test.sh, tests/bash-walls.test.sh §cwd-split]
if [ -n "${BIONIC_CWD:-}" ] && [ -d "${BIONIC_CWD:-}" ]; then
  CURRENT_BRANCH=$(git -C "$BIONIC_CWD" symbolic-ref --short HEAD 2>/dev/null || echo "")
else
  CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
fi
if [ -n "$CURRENT_BRANCH" ] && git_branch_protected "$CURRENT_BRANCH"; then
  fold_block exit2 push "the current branch is protected" "switch to a feature branch" \
    "The current branch is \"$CURRENT_BRANCH\". Switch to a feature branch, or push by hand from your own terminal."
  return 2
fi

return 0
}

# ─── wall_protect_database — hooks/protect-database.sh ───────────────────────
#
# HARD BLOCK: Prevents AI from running destructive database operations.
# Catches DROP, TRUNCATE, DELETE without WHERE, and ALTER TABLE...DROP
# via psql, mysql, sqlite3, and other common DB CLIs.
# [WALL: tests/protect-database.test.sh]
#
# FAIL OPEN (task-engaged-session, 2026-09-03). This wall carried no library at all
# until the engagement predicate arrived, and refusing every database command in
# every project on the machine because one file is missing would arm it in exactly
# the sessions Chris's ruling takes it out of. The direction is chosen by the cost of
# the mistake: a destructive command that slips through a broken plugin is one
# command, and the plugin being broken is loud. In the compound that reads as "this
# wall is not one of the two that hold the fail-closed arm".
wall_protect_database() {  # <event> -> 0 nothing · 2 block
  [ -n "$COMMAND" ] || return 0

# ---------- THE ENGAGEMENT GUARD (AC-20): is this session bionic's at all? ----------
#
# FIRST, above every other question this hook asks. Chris, 2026-09-03: "all guardrails
# imposed by bionic should only apply when exercising bionic. Nothing should apply until
# bionic is triggered" — and the trigger is the canonical-sdlc skill, which writes
# `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. A session that never
# invoked it is one this wall has nothing to say to, and it says nothing: exit 0, no
# stdout, no stderr.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — absent marker, a symlink at the path, a
# foreign or unshaped session key, no key at all. The marker is the one artifact whose
# PRESENCE opens a wall, so the fail direction is inverted here on purpose: the arming
# partition is the consent boundary (1.3.2 close-out), and a wall that binds a session
# which never consented is the defect this guard exists to remove.
# [WALL: tests/protect-database.test.sh]
#
# ASKED ONCE, IN hooks/bash-walls.sh, FOR ALL FIVE (T23) — see wall_protect_main.


# Uppercase for case-insensitive matching
#
# COMPUTED WHERE IT IS FIRST NEEDED, NOT AT THE TOP (REQ-10, T11). `tr` is a fork
# and this wall runs on every Bash tool call; every use of CMD_UPPER below sits
# behind a test on the RAW command, so the overwhelmingly common command — one
# that mentions no database client and no destructive SQL verb — now pays nothing
# for an uppercase copy nothing reads.
local CMD_UPPER="" stmt stmt_upper _db_maybe

# Check if this involves a database CLI
#
# THE BUILTIN SCREEN IS A SUPERSET OF THE GREP BELOW (REQ-10, T11). `grep -qEi`
# can only match when one of its literal alternatives appears in the command,
# case-insensitively; the `case` states exactly that and nothing more, so a miss
# is a guaranteed grep miss and a hit still hands the decision to the grep, which
# keeps the word-boundary rule. The bracket spelling is how bash 3.2 asks a
# case-insensitive question without `shopt -s nocasematch`, which is process-wide
# state this wall has no business changing.
case "$COMMAND" in
  *[Pp][Ss][Qq][Ll]*|*[Mm][Yy][Ss][Qq][Ll]*|*[Ss][Qq][Ll][Ii][Tt][Ee]3*|\
  *[Mm][Oo][Nn][Gg][Oo]*|*[Cc][Ll][Ii][Cc][Kk][Hh][Oo][Uu][Ss][Ee]-[Cc][Ll][Ii][Ee][Nn][Tt]*|\
  *[Cc][Qq][Ll][Ss][Hh]*|*[Cc][Oo][Cc][Kk][Rr][Oo][Aa][Cc][Hh]\ [Ss][Qq][Ll]*|\
  *[Pp][Gg]_*|*[Mm][Aa][Rr][Ii][Aa][Dd][Bb]*) _db_maybe=1 ;;
  *) _db_maybe=0 ;;
esac
if [ "$_db_maybe" = 1 ] && grep -qEi '(psql|mysql|sqlite3|mongosh|mongo |clickhouse-client|cqlsh|cockroach sql|pg_|mariadb)\b' <<< "$COMMAND"; then
  CMD_UPPER=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')

  # DROP TABLE / DATABASE / SCHEMA / INDEX / COLLECTION / VIEW / FUNCTION / TRIGGER / PROCEDURE / SEQUENCE / TYPE
  # [WALL: tests/protect-database.test.sh]
  if grep -qE 'DROP\s+(TABLE|DATABASE|SCHEMA|INDEX|COLLECTION|VIEW|FUNCTION|TRIGGER|PROCEDURE|SEQUENCE|TYPE)' <<< "$CMD_UPPER"; then
    fold_block exit2 sql "this command DROPs a database object" "run the migration yourself" \
      "The matched pattern is a DROP of a table, database, schema, index, collection, view, function, trigger, procedure, sequence or type. A migration run from your own terminal is the route."
    return 2
  fi

  # TRUNCATE [WALL: tests/protect-database.test.sh]
  if grep -qE 'TRUNCATE\s' <<< "$CMD_UPPER"; then
    fold_block exit2 sql "this command TRUNCATEs a table" "run the migration yourself" \
      "The matched pattern is TRUNCATE. A migration run from your own terminal is the route."
    return 2
  fi

  # DELETE without WHERE (mass delete) — check per-statement to avoid multi-statement bypass
  # [WALL: tests/protect-database.test.sh]
  while IFS= read -r stmt; do
    stmt_upper=$(echo "$stmt" | tr '[:lower:]' '[:upper:]')
    if grep -qE 'DELETE\s+FROM\s' <<< "$stmt_upper" && ! grep -qE 'DELETE\s+FROM\s+\S+\s+WHERE\s' <<< "$stmt_upper"; then
      fold_block exit2 sql "this DELETE has no WHERE clause" "add a WHERE clause" \
        "The matched pattern is a DELETE FROM with no WHERE in the same statement. An unbounded DELETE empties the table."
      return 2
    fi
  done <<< "$(echo "$CMD_UPPER" | tr ';' '\n')"

  # ALTER TABLE ... DROP COLUMN [WALL: tests/protect-database.test.sh]
  if grep -qE 'ALTER\s+TABLE\s+.*DROP\s' <<< "$CMD_UPPER"; then
    fold_block exit2 sql "this ALTER TABLE drops a column or key" "run the migration yourself" \
      "The matched pattern is an ALTER TABLE that DROPs. A migration run from your own terminal is the route."
    return 2
  fi

  # MongoDB destructive operations (JavaScript method calls)
  # [WALL: tests/protect-database.test.sh]
  if grep -qEi '(\.drop\(\)|\.dropDatabase\(\)|\.deleteMany\(\s*\{\s*\}\s*\))' <<< "$COMMAND"; then
    fold_block exit2 sql "this drops or wipes a MongoDB collection" "run it from your own terminal" \
      "The matched pattern is a collection drop, a database drop, or an unfiltered many-document delete. Run it from your own terminal if you mean it."
    return 2
  fi
fi

# Also catch raw SQL piped or passed inline (e.g., echo "DROP TABLE..." | psql)
# [WALL: tests/protect-database.test.sh]
#
# THE TWO CONJUNCTS ARE REORDERED AND SCREENED (REQ-10, T11). `&&` is commutative
# over two pure predicates — neither grep writes anything — so which one is asked
# first is a cost decision, not a behaviour one, and the verdict is identical
# either way. The `case` is the builtin superset of the FIRST conjunct: the grep
# needs the literal `DROP` or `TRUNCATE` (uppercased, so any case in the raw
# text), and without one of them in the command no uppercase copy is made and
# neither grep runs.
case "$COMMAND" in
  *[Dd][Rr][Oo][Pp]*|*[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]*) _db_maybe=1 ;;
  *) _db_maybe=0 ;;
esac
if [ "$_db_maybe" = 1 ]; then
  [ -n "$CMD_UPPER" ] || CMD_UPPER=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')
fi
if [ "$_db_maybe" = 1 ] && grep -qE '(DROP\s+(TABLE|DATABASE|SCHEMA|VIEW|FUNCTION|TRIGGER|PROCEDURE)|TRUNCATE\s)' <<< "$CMD_UPPER" && grep -qEi '(\|\s*(psql|mysql|sqlite3|mongosh)|<< )' <<< "$COMMAND"; then
  fold_block exit2 sql "destructive SQL is piped to a db client" "run the migration yourself" \
    "The matched pattern is a DROP or TRUNCATE piped or heredoc-fed into psql, mysql, sqlite3 or mongosh. Piping hides the statement from the argv check."
  return 2
fi

return 0
}

# ─── wall_evidence_gate — hooks/canonical-sdlc-evidence-gate.sh ──────────────
#
# EVIDENCE GATE: blocks git commits during a canonical-sdlc run when the plan file's
# `## SDLC State` section is missing the current step's evidence. The rule is: the
# evidence artifact must be recorded in the plan file *before* the commit that closes
# the step. Plans without `## SDLC State` pass through unblocked — this wall only
# enforces against canonical-sdlc runs.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# FAIL-CLOSED (design ledger S4, Chris D1 2026-08-30): a wall over an IRREVERSIBLE
# action refuses rather than waving through a command it cannot read. That arm is the
# compound's now, in hooks/bash-walls.sh, after the four repair commands are matched
# as whole strings.
#
# ── WHY THIS ONE WALL IS RUN IN A SUBSHELL, AND THE OTHER FOUR ARE NOT ───────
#
# The fold's contract is that a folded function stages a refusal and RETURNS, never
# exits. protect-main, protect-database, farm-out-reminder and background-suite-guard
# each have between one and six refusal sites, all within one or two call frames, and
# each was converted to `fold_block … ; return 2` with every caller propagating — the
# mechanical change T12 made to the four Stop walls.
#
# THIS BODY HAS 32, at up to four frames deep, and 32 of them are inside `validate_matrix`
# alone — a 300-line function whose refusals fire from inside loops, through helper
# frames (`block_matrix`, `ledger_shape_fail`, `shape_block`) that were written knowing
# `refuse` never returns. Propagating a return through every one of those call sites is
# ~50 edits in which a single miss converts a BLOCK into a silent pass: the wall keeps
# running, the next `fold_block` overwrites the staged object, and the function returns
# 0 with the refusal discarded. That is the fail-OPEN direction, on the wall that stands
# over `git commit`, and no suite can prove the absence of the miss it did not think to
# drive.
#
# So the body is carried VERBATIM — every `exit`, every frame, every refusal site — and
# run in a subshell where `refuse` is shimmed to RECORD the object and exit, which is
# exactly what the library's `refuse` does minus the rendering. The abort semantics are
# the ones the 32 sites were written against, unchanged and unaudited-for, and the
# parent stages the recorded object through `fold_block` like every other wall. The
# differential (T23 §7) is the proof: on a payload where only this wall speaks, the
# bytes on both streams are the ones the hook produced.
#
# WHAT THE SUBSHELL COSTS, SAID OUT LOUD. One fork per Bash tool call in an engaged
# session — no exec, no re-parse, no second loader run, against the five execs and five
# loader runs the merge removes. The body may not hand shell state to a later wall, and
# it never did: what it leaves behind is the audit file it wrote, which is a file.
#
# THE STAGING IS FIVE FILES AND NOT ONE, because `detail` carries newlines and blank
# lines by design and any single-file encoding would need an escape this can do without.
# `$( cat )` strips trailing newlines, which is what `bionic_fold` does to `detail`
# anyway, and `mode`, `verb`, `fact` and `fix` cannot contain a newline — `refuse`
# refuses its own caller for that.
#
# THE DIRECTORY IS CREATED HERE, EXCLUSIVELY, AND ONLY ON THE REFUSAL PATH (security F-1,
# performance A-1). `mkdir -p` accepted whatever was already at the name — a symlink planted
# by anyone who could guess `$$` and one `$RANDOM` draw was followed and its target
# truncated, and a regular file planted there was read back on the NEXT Bash call as a
# refusal this gate never made. Plain `mkdir` is atomic and fails when anything already
# holds the name, so a squatter gets a refusal whose words degrade to the malformed-refusal
# arm below — fail-closed, never a truncation and never attacker-authored prose. `-m 700`
# means nothing can be planted inside it afterwards either.
#
# AND IT RUNS NOWHERE ELSE. A Bash call this gate does not refuse never reaches this
# function, so it creates nothing, and the caller's cleanup has nothing to remove — which is
# the fork the old unconditional `rm -rf` paid on every Bash tool call in every engaged
# session.
#
# RC IS THE SIGNAL, because a subshell cannot hand a variable back. 0 means the five files
# are there and the caller may read them; 1 means they are not and the caller must not.
# [WALL: tests/bash-walls.test.sh §11]
# ─── evidence_line_field — a key read ANYWHERE on a line, not only at its start ───────
#
# WHY IT IS NOT `grep -E '^[[:space:]]*<key>:'` (wave-16 REQ-3, AC-3.3; seed B B11). A
# `## SDLC State` evidence line is a SEMICOLON-SEPARATED RECORD, not a one-key line:
#
#     - Step 1: opened 2026-09-19T22:00Z; requirements: specs/<epic>/<wave>.requirements.md; card approved
#
# Every pointer read in this file anchored its key at line start, so a record whose pointer
# is not the FIRST field carried a perfectly good path the gate could not see, and the
# commit was refused "Step 1's evidence names no requirements file". The value still ends
# at the first `;` — that truncation has been the contract since plan assumption A17 — and
# the continuation-line shape (`  requirements: …` on its own line) is unaffected, because
# a key at line start is a key anywhere on the line.
#
# THE LEFT BOUNDARY IS WHAT KEEPS IT HONEST: `pre-requirements:` and `walk-artifact-sha:`
# are different fields, so the key must be preceded by the start of the line or by a
# character that cannot be part of a key, and followed by optional blanks and a colon.
# awk's `match` takes the LEFTMOST match, so a record naming the key twice reads the first.
#
# A HERE-STRING, not a pipe: `awk … exit` quits early, and walls.sh header's SIGPIPE rule
# (T37, wave-14) applies to every early-quitting reader under `pipefail`, not only grep.
evidence_line_field() {  # <text> <key> -> the value, or empty
  awk -v k="$2" '
    {
      if (match($0, "(^|[^-_[:alnum:]])" k "[[:space:]]*:[[:space:]]*")) {
        v = substr($0, RSTART + RLENGTH)
        sub(/;.*$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    }' <<< "$1"
}

# ─── plan_bring_forward — every version-14 shape fault, in one pass ──────────
#
# WHAT IT IS FOR (spec D8; REQ-3, AC-3.1; research R2 §2c-2d). A plan whose frontmatter
# says it is at the supported contract version and whose BODY is pre-14 used to meet the fleet one arm
# at a time — `requirements:`, then `approved-by:`, then `fails-when:`, then the Tasks shape
# — because every arm refuses by calling `refuse`, and `refuse` EXITS (refuse.sh:91-94).
# Worse, the reveal order was data-dependent on the previous repair: the "row ahead of the
# run" arm reads cells a pre-14 table does not have, so widening the table is what CREATES
# the next refusal (R2 §2d). A writer paid one round trip per fault and could not see the
# size of the job from the first one.
#
# SO IT VALIDATES THE TARGET SHAPE, NOT THE CURRENT ONE, and it is a PREDICATE: it prints,
# it never refuses, and the two callers — the governing-skill hook at Write/Edit and the
# evidence gate at commit — render the identical list through the channel ADR-030 opened.
#
# WHEN IT FIRES, AND WHY THE TRIGGER IS NARROW. Two conditions, together:
#   (a) the `## Tasks` table is MISSING at least one required column — the structural
#       signature of a pre-14 body, and the one fault that cannot be an ordinary typo; and
#   (b) at least one of the version-14 KEYS the plan owes at this step is absent.
# Either alone is an ordinary fault with an arm of its own that names the repair better
# than a list can, and those arms are untouched: a ten-column table with one bad row still
# gets `units_validate`'s own refusal, and a plan missing only `approved-by:` still gets
# the arm that explains what an approval is. This is the summary for the case where a
# reader needs the SHAPE of the job, not the next line of it.
#
# THE LANE GUARD IS validate_dispatch_ledger's, verbatim (D7): wave|epic + `rigor: audited`
# + `multi_agent: true`. Below it the checks this function folds are themselves inert, so
# firing there would invent enforcement rather than summarise it.
#
# AT WALLS.SH TOP LEVEL, OUTSIDE `_eg_body`, ON PURPOSE. Sourcing this file must define
# this function and nothing else the governing-skill hook could collide with — every helper
# `_eg_body` carries (`frontmatter_get`, `block_get`, `is_placeholder_value`, …) is nested
# inside it and is not defined by a source. Which is also why this function re-reads the
# plan from the PATH instead of using them: it is a pure read-only validator over the
# target shape (research R2 §3(d) route 2), and its callers hand it a path — the gate the
# bound plan, the hook a temp copy of the posted content.
#
# AND IT DERIVES THE STEP ITSELF (wave-16 T25, Step-6 critic §C1). It used to be HANDED the
# step, and the two callers handed it different facts: the gate passed the body's
# `current:`, the hook passed the frontmatter's `sdlc-step:`. A frontmatter stamp is written
# once at Step 0 and almost never moved — this repo's own archive carries `sdlc-step: 3`
# beside `current: 9` — so the Write-side arm computed against step 3 for the life of the
# plan, the two `>= 4` classes below were unreachable there, and AC-3.1's "identical lists
# from both callers" could not hold past Step 3. It failed SILENTLY: the hook simply printed
# a shorter list. The step is a fact about the plan TEXT this function already holds, so it
# reads it where the gate reads it — `current:` under `## SDLC State`, `a`/`b` suffix
# stripped — and no caller can hand it the wrong one.
_bf_fm_get() {  # <plan text> <frontmatter key> -> its value, or empty
  awk -v k="$2" '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { exit }
    {
      if (match($0, "^[[:space:]]*" k "[[:space:]]*:[[:space:]]*")) {
        v = substr($0, RSTART + RLENGTH); sub(/[[:space:]]+$/, "", v); print v; exit
      }
    }' <<< "$1"
}

_bf_section() {  # <plan text> <exact "## Heading"> -> that section body, fence-aware
  awk -v want="$2" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ {
      if (f) exit
      if ($0 == want || index($0, want " ") == 1) { f = 1 }
      next
    }
    f { print }
  ' <<< "$1"
}

plan_bring_forward() {  # <plan file> -> the list on stdout; rc 1 when it fires
  # A STRAY SECOND ARGUMENT IS IGNORED, not used, for one release: both callers dropped it
  # in this task, and a caller this tree has not seen must degrade to the derived step
  # rather than to a silently different answer.
  #
  # THE LIST IS JUDGED AT THE PLAN'S OWN `current:` LINE, ALWAYS — deliberately, not by
  # omission (wave-16 T27, Step-6 critic §C8, A-T27.1). The evidence gate substitutes
  # `CURRENT="$_EG_RSTEP"` (walls.sh ~:2430) when a commit comes from a linked worktree
  # whose `## Tasks` row names a step below the run's `current:`, so that OTHER arms judge
  # that commit at the row's step — but that substituted value never reaches this function,
  # with no argument to carry it even if it did. Passing it back in would reopen exactly the
  # second-source hazard T25/§C1 closed (two callers, two facts); direction is fail-closed,
  # since a plan-shape summary judged at a later `current:` can only ask for MORE, never
  # fewer, than the row's own step would.
  local plan="${1:-}" step
  local scale rigor multi units_out missing rowfaults
  local plan_text state b1 matrix first_heading goal_body
  local faults="" keys=0

  [ -n "$plan" ] && [ -f "$plan" ] || return 0

  # NORMALIZED ONCE, HERE, BEFORE ANY READ (wave-16 T27, Step-6 critic §C7). Every helper
  # below — `_bf_fm_get`, `_bf_section`, the `first_heading` awk, the `current:` derivation
  # — now reads `$plan_text`, never the path, so a CRLF plan's headings and keys match the
  # same way an LF plan's do. Before this, `_bf_section` and `first_heading` read the file
  # RAW and matched `## SDLC State` by string equality: on a CRLF plan the heading arrived
  # as `## SDLC State\r`, matched nothing, `state` came back empty, `step` fell through to
  # 0, `keys` stayed 0, and the predicate returned rc=0 with NOTHING — silently admitting a
  # pre-14 CRLF plan the same body's LF twin refuses. Inlined rather than calling
  # `normalize_newlines` (run.sh) by name: this file does not source run.sh, one caller (the
  # evidence gate) sources both but the other (the governing-skill hook) sources this file
  # lazily on its own, and a bare function name would make plan_bring_forward's correctness
  # depend on sourcing order this file does not control. Same translation, same reason
  # `_units_read` (units.sh:118) and `normalize_newlines` (run.sh:97) already use it: `sub`
  # trims a trailing CR, `gsub` re-splits a CR-only file into real lines rather than
  # collapsing it to one — `tr -d '\r'` would do the latter and read a live CR-only plan as
  # closed, the fail-dangerous direction (.claude/rules/hook-authoring.md).
  # THE BOM (T8, REQ-11; wave-16 critic-b77d5aa C10; research R4 §D3). `NR==1` compares the
  # first record to "---" with `==`, which is BOM-insensitive, but every reader downstream
  # (`_bf_fm_get`, `first_heading`) matches an ANCHORED regex, which a leading BOM defeats —
  # so a BOM-prefixed pre-14 plan admitted silently until this line stripped it. A STRING
  # compare, not a regex: octal and `\x` escapes inside an awk REGEX LITERAL do not strip a
  # BOM on awk 20200816 (measured, R4 D3.4); only `substr`/`==` against the octal STRING
  # `"\357\273\277"` does. Ordered before the CR translation on the same record so a
  # BOM+CRLF plan strips both.
  plan_text="$(awk 'NR==1 && substr($0,1,3)=="\357\273\277" { $0 = substr($0,4) }
                    { sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$plan")"

  case "$(_bf_fm_get "$plan_text" scale)" in wave|epic) : ;; *) return 0 ;; esac
  [ "$(_bf_fm_get "$plan_text" rigor)" = "audited" ] || return 0
  [ "$(_bf_fm_get "$plan_text" multi_agent)" = "true" ] || return 0

  # (a) THE PRE-14 TABLE. `units_validate` is the one reader of `## Tasks` and already
  # reports EVERY fault rather than the first (units.sh's own note) — it is the model this
  # function generalises, and the only public verb that answers both halves here.
  units_out="$(units_validate "$plan" 2>/dev/null)" || true
  missing="$(printf '%s\n' "$units_out" | sed -n 's/^## Tasks: missing column //p' \
             | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
  [ -n "$missing" ] || return 0
  rowfaults="$(printf '%s\n' "$units_out" | grep -v '^## Tasks: missing column ' || true)"

  # (b) THE KEYS, each under the step guard its own arm carries: `requirements:` from
  # current 2 (validate_requirements_pointer), `approved-by:` and `fails-when:` from 4
  # (validate_approved_by, validate_fails_when). A key not yet owed is not a fault.
  state="$(_bf_section "$plan_text" '## SDLC State')"
  # THE ONE SOURCE. Same read as the evidence gate's own `CURRENT` (the `current:` line of
  # `## SDLC State`, first hit, whitespace stripped) and the same `a`/`b` strip the gate
  # applies at the call site — including the line-ending normalization: `plan_text` above
  # was already put through the same translation `normalize_newlines` (run.sh) applies to
  # build the gate's own `SECTION` (walls.sh:1709), so a CRLF plan's `## SDLC State` heading
  # and its `current:` line are seen exactly as the gate sees them, not raw. Anything else —
  # absent, `T<n>`, a word — reads as 0, which is the fallback the old `${2:-0}` default gave
  # a caller that passed nothing.
  step="$(printf '%s\n' "$state" \
          | grep -E '^[[:space:]]*current[[:space:]]*:' \
          | head -1 \
          | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
          | tr -d '[:space:]' \
          | sed -E 's/[ab]$//')"
  case "$step" in ''|*[!0-9]*) step=0 ;; esac
  if [ "$step" -ge 2 ]; then
    b1="$(awk '
      /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+1[[:space:]]*:/ { f = 1; print; next }
      f {
        if ($0 ~ /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+[0-9]+[ab]?[[:space:]]*:/) exit
        if ($0 ~ /^[^[:space:]]/) exit
        print
      }' <<< "$state")"
    if [ -z "$(evidence_line_field "$b1" requirements)" ]; then
      faults="${faults}## SDLC State: the Step 1 evidence names no 'requirements:' pointer
"
      keys=$((keys + 1))
    fi
  fi
  if [ "$step" -ge 4 ]; then
    if [ -z "$(evidence_line_field "$state" approved-by)" ]; then
      faults="${faults}## SDLC State: no 'approved-by:' line
"
      keys=$((keys + 1))
    fi
    # THE MATRIX HALF IS COARSER THAN validate_fails_when ON PURPOSE (A-T5): that arm
    # judges each AC BLOCK and names the row; this one asks whether the section carries the
    # key AT ALL, which is the question a pre-14 matrix answers no to. Naming one row here
    # would duplicate `matrix_block` — the twin-that-drifts this repo spends real effort
    # avoiding — for a list that exists to size the job, not to walk it.
    matrix="$(_bf_section "$plan_text" '## Verification Matrix')"
    if grep -qE '^[[:space:]]*\|' <<< "$matrix" \
       && ! grep -qE '(^|[^-_[:alnum:]])fails-when[[:space:]]*:' <<< "$matrix"; then
      faults="${faults}## Verification Matrix: no AC block names a 'fails-when:'
"
      keys=$((keys + 1))
    fi
  fi

  # `## Goal` IS IN THE LIST BUT NOT IN THE TRIGGER. It is a Write-side arm (AC-K5.4) with
  # no twin at the gate, so letting it ARM this predicate would make the gate refuse plans
  # it admits today; reporting it once the predicate has already fired costs nothing and is
  # what makes the Write-side and commit-side lists identical (AC-3.1).
  first_heading="$(awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## / { print; exit }' <<< "$plan_text")"
  case "$first_heading" in
    '## Goal'|'## Goal '*)
      goal_body="$(_bf_section "$plan_text" '## Goal')"
      grep -qE '[^[:space:]]' <<< "$goal_body" || faults="${faults}## Goal: the section is empty
" ;;
    *) faults="${faults}## Goal: the first section is not '## Goal'
" ;;
  esac

  [ "$keys" -ge 1 ] || return 0

  printf '## Tasks: the table is missing columns: %s\n' "$missing"
  [ -n "$rowfaults" ] && printf '%s\n' "$rowfaults"
  printf '%s' "$faults"
  return 1
}

_eg_stage_refusal() {  # <dir> <mode> <verb> <fact> <fix> <detail> -> 0 staged · 1 not
  local d="${1:-}" i=1 a
  shift
  [ -n "$d" ] || return 1
  mkdir -m 700 "$d" 2>/dev/null || return 1
  for a in "$@"; do
    printf '%s' "$a" > "$d/$i" 2>/dev/null || return 1
    i=$((i + 1))
  done
  return 0
}

wall_evidence_gate() {  # <event> -> 0 nothing · 2 block
  # Not a Bash tool call or an empty command — nothing to gate.
  [ -n "$COMMAND" ] || return 0

  local _eg_stage _eg_rc
  # NO FORK TO NAME IT. The name is a string this process already knows; what makes it safe
  # is that `_eg_stage_refusal` CREATES it exclusively, and only when there is a refusal to
  # stage. `$RANDOM` bought nothing once creation is exclusive, and it cost one guessable
  # name per pid while it was there.
  _eg_stage="${TMPDIR:-/tmp}/bionic-gate-$$"
  (
    # THE SHIM, and the only line of this wall that is not the hook's own. It has
    # `refuse`'s signature and `refuse`'s abort, and it renders nothing: the parent
    # makes the one `refuse` call through `bionic_fold`, so the channel rule holds
    # (cross-gate §Refuse: no hook prints a refusal directly).
    #
    # TWO ABORT CODES, because the staging can fail and the parent has to be able to tell.
    # 2 is "the five files are written, read them"; 3 is "this was a refusal and its words
    # are gone", which the malformed-refusal arm below turns into a refusal that still holds.
    refuse() { _eg_stage_refusal "$_eg_stage" "$@" && exit 2; exit 3; }
    _eg_body
  )
  _eg_rc=$?

  if [ "$_eg_rc" -eq 2 ] && [ -f "$_eg_stage/1" ]; then
    fold_block "$(cat "$_eg_stage/1" 2>/dev/null)" "$(cat "$_eg_stage/2" 2>/dev/null)" \
               "$(cat "$_eg_stage/3" 2>/dev/null)" "$(cat "$_eg_stage/4" 2>/dev/null)" \
               "$(cat "$_eg_stage/5" 2>/dev/null)"
    rm -rf "$_eg_stage" 2>/dev/null
    return 2
  fi
  # GUARDED, so the path that staged nothing forks nothing (performance A-1).
  [ -d "$_eg_stage" ] && rm -rf "$_eg_stage" 2>/dev/null

  # A NON-ZERO EXIT WITH NOTHING STAGED has two causes and one answer. Either `refuse`
  # refused its own caller — a malformed refusal, whose complaint is already on stderr in
  # the library's own format — or the staging itself could not be made (exit 3: the name
  # was already taken, or the temp directory is unwritable). `_refuse_selfrefuse` exits 2 "because the wall the caller was building
  # must still hold", and it holds here: the commit is refused, and the refusal says
  # which failure this is rather than inheriting an empty object.
  if [ "$_eg_rc" -ne 0 ]; then
    fold_block exit2 commit "the evidence gate's own refusal is malformed" "run /bionic:doctor" \
      "The gate refused this commit and the refusal it built was rejected by the one
renderer; the library's complaint is on the stream above this line. The commit is
still refused — a wall whose words are broken is not a wall that waves things past."
    return 2
  fi
  return 0
}

# ── the hook's body, carried whole ───────────────────────────────────────────
#
# EVERYTHING BELOW IS hooks/canonical-sdlc-evidence-gate.sh FROM ITS LAST `. "$BIONIC_LIB/…"`
# LINE TO ITS LAST `exit 0`, with ONE deletion: the `audit_path` copy, which is at file
# scope now. Its `exit` statements are load-bearing and deliberate — see the subshell
# note above — and its margin is column zero because `tests/cross-gate-agreement.test.sh`
# and `tests/docs-pins.test.sh` read literals out of it with `^`-anchored extractions.
_eg_body() {

# Is any segment of the command a `git commit`? The library answers by argv
# position: git must be argv[0] (after leading VAR=value assignments and git's
# own global options) and `commit` the subcommand. That is what makes
# `git -C <dir> commit`, `git -c user.name=x commit` and
# `git --no-pager commit` commits — all three were invisible to the string
# match this replaced — while `echo "we will git commit later"` and a heredoc
# body naming a commit stay silent.
# [WALL: tests/git-argv.test.sh]
IS_COMMIT=0
# THE SAME SCREEN wall_protect_main takes (REQ-10, T11) — `git_argv_has_sub` runs
# `git_argv_expand`, a second awk pass over the same command line, and a command
# with no readable `git` token in it has no commit for the parser to find.
if _wall_mentions_git "$COMMAND" && git_argv_has_sub "$COMMAND" commit; then
  IS_COMMIT=1
fi

if [ "$IS_COMMIT" -eq 0 ]; then
  exit 0
fi

# Locate the newest plan file across THIS PROJECT's plan directories:
#   - <docs-root>/plans/      (bionic canonical-sdlc convention)
#   - <docs-root>/incidents/  (incident-response runs)
#
# Picks the newest .md across those that exist. If none exist, this isn't a
# canonical-sdlc session — let the commit through (see ABSENT vs MISPLACED
# below).
#
# NOT searched, deliberately: `~/.claude/plans/` and
# `<project>/docs/superpowers/plans/`. Both were in the search set until
# 2026-07-28; bionic gates bionic's plans, full stop (user ruling). The global
# directory is the harness's own, project-AGNOSTIC one — Claude Code's plan mode
# drops unrelated notes there routinely, and selection takes the newest .md
# across the whole set. One such note therefore won selection, carried no
# `## SDLC State`, and this hook exited 0: every commit in that project ran
# ungated. The superpowers directory was the same pre-`.bionic/docs` vestige
# (the root `docs/` tree was deleted 2026-07-16); nothing writes canonical plans
# to either.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# THE CONTEXT, RESOLVED AGAIN HERE, AND THAT IS THE POINT (REQ-1f, lib/context.sh).
# The POSITION below the commit arm is this gate's own and it was a cost argument when
# this body was its own process: a non-commit Bash command must not pay for a root walk.
# THE CARRIER NO LONGER HONOURS THAT. hooks/bash-walls.sh calls `bionic_context` for
# every Bash tool call in an engaged session, before any wall is entered, so the walk is
# already paid by the time this line is reached and the deferral buys nothing.
#
# THE CALL STAYS ANYWAY, for a reason that outranks the walk it repeats: this body is
# carried into the library VERBATIM from the hook it replaced, and the differential T23
# rests on is a differential against that text. Deleting a line the subshell would have
# inherited from its parent is a behaviour-preserving edit that nothing here proves is
# behaviour-preserving. The values cannot disagree — same payload, same environment, and
# `bionic_context` is a pure function of both — so the duplicate costs one root walk on
# commit commands and nothing else. Consolidating it belongs with the verbatim-carry
# guarantee it would break, not beside it. It adopts the BIONIC_INPUT read before the loader (R1) — stdin is spent, and
# `loader_fail_closed` needed the command text before any library existed.
#
# THE CWD LADDER IS THE LIBRARY'S, and is named nowhere else in this file but the
# fail-closed pre-check above — which restates it by hand for the one reason that
# block exists at all: the file that owns the rule is exactly what failed to load.
#
# THE ROOT used to be a private `resolve_project_root()` — one of eight byte-identical
# copies across hooks/, held together by an agreement suite that could only ever prove
# they had not drifted YET. The eight are gone; `project_root` is the one answer, and a
# strictly better one: the old copy asked git for the root and stopped there, so a
# project whose `.bionic/` sat ABOVE the repo (a repo nested in a workspace) resolved to
# the repo and every artifact path this gate checks landed in the wrong tree. THE
# WORKTREE CASE, which the old copy did get right and this one keeps: a linked worktree
# maps back onto its main repository, so every worktree of one repo resolves to ONE root
# and therefore one audit file, one docs root, one plan.
bionic_context 2>/dev/null || exit 0

# ---------- THE ENGAGEMENT GUARD (AC-6): is this session bionic's at all? ----------
#
# FIRST, above everything this gate decides — above the plan hygiene below, above the
# misplacement sweep, above the run predicate. Chris, 2026-09-03: "all guardrails
# imposed by bionic should only apply when exercising bionic. Nothing should apply until
# bionic is triggered" — and the trigger is the canonical-sdlc skill, which writes
# `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. A commit from a session
# that never invoked it is not this gate's business: exit 0, no stdout, no stderr.
#
# THE ORDERING CONTRACT BELOW IS UNCHANGED, and this guard does not join it. Plan hygiene
# still sits ABOVE the run predicate, so an engaged session committing against a
# malformed plan is still refused whether or not a run is open — the question this line
# asks is not "is there a run" but "is this session bionic's at all", and it is prior to
# both.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — absent marker, a symlink at the path, a
# foreign or unshaped session key, no key at all. The marker is the one artifact whose
# PRESENCE opens a wall, so the fail direction is inverted here on purpose, and it is
# inverted against this file's own fail-CLOSED posture on the library: the arming
# partition is the consent boundary (1.3.2 close-out), and a wall that binds a session
# which never consented is the defect this guard exists to remove.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# ---------- JURISDICTION (wave-19 REQ-9, D10; ADR-031 amended): whose repository is this? ----------
#
# SECOND, right under the engagement guard and above every plan read — the plan hygiene, the
# misplacement sweep, the run predicate and every step arm all read `$PLAN`, and none of them
# has anything to say about a commit that lands in another repository. Until this arm the gate
# resolved the plan from the ENGAGED ROOT first and asked which directory the commit runs in
# some fifteen hundred lines later, so `git -C <scratch repo> commit` from an engaged session
# was judged against this run's plan and refused for this run's evidence (A-T11.1, wave-18;
# reproduced twice, R3 Q3). A repository `git init`-ed under the root's own record directory —
# a test bed — drew the identical refusal: the gate never looked at the commit's directory.
#
# THE QUESTION IS THE REPOSITORY, NOT THE PATH. The commit's directory — the three spellings
# `_eg_commit_cwd` reads, `-C` first — is handed to git, and git's COMMON DIR is compared to
# the engaged root's. Common dir, never toplevel: a LINKED WORKTREE of this repository has a
# toplevel of its own and shares the common dir, so every writer's tree stays inside and keeps
# today's path (the row fork, the ambiguity arm, `_eg_git_wt_name`) exactly as it was. A
# repository NESTED under the root has a common dir of its own and is outside, which is
# AC-9.3; another repository's linked worktree is outside too and leaves here, ahead of the
# rc-4 arm that used to catch it further down. The comparison is physical — the string, then
# `-ef` — so a symlinked spelling of the root is the root.
#
# ONLY A POSITIVE ANSWER EXEMPTS. No git, a directory git places in no repository, a root
# whose common dir cannot be read (a `.bionic/` above the repository), a relative directory,
# a command that names two directories before the commit: each keeps today's verdict and is
# judged below. A wall that cannot place a commit does not wave it through; only git naming a
# DIFFERENT repository does. The two-directory case is the one that matters — `cd <scratch>
# && cd <root> && git commit` commits in the root, and the leading `cd` must not buy it an
# exemption; the ambiguity arm further down refuses it as before.
#
# AND A POSITIVE ANSWER IS ABOUT ONE COMMIT. `_eg_commit_cwd` places the FIRST commit the text
# carries — the first `git -C <abs> commit`, else the leading `cd` — and says nothing about any
# commit after it. So the arm exempts only a command whose text carries EXACTLY ONE commit
# segment (`_eg_commit_count`, over the same `sh -c`/`eval`-expanded segment list every wall
# reads) and places that one outside. Two or more commit segments are judged as before, even
# when every one of them lands outside: `git -C <scratch> commit && git commit` and `cd
# <scratch> && git commit && cd <root> && git commit` both commit in the root the second time,
# and counting is what tells them apart from a single commit without placing each one (review
# R1, wave-19). Zero is judged too — a commit this reader cannot see is not one it can place.
#
# AND THE ONE COMMIT MUST BE PLACED EXACTLY AS GIT WILL PLACE IT (critic C1, wave-19). The reader
# names the FIRST absolute `-C`, the leading `cd` or the payload cwd; git obeys the LAST `-C`,
# `--git-dir`/`--work-tree`/`GIT_DIR` name the repository outright, and a `pushd`, a nested
# `bash -c 'cd …'` or a piped `cd` moves the shell where the reader never looks. Every one of
# those single commits was exempted for a scratch repository while it landed in the root.
# `_eg_placed` admits only the three shapes the reader reads exactly: one `-C`, a leading `cd`,
# or the payload cwd. Each holds only when every other segment of the text starts with `git`,
# `true`, `:` or `exit` (`_eg_git_only`), with no `(`, `{` or backtick anywhere. That is an
# ALLOW-LIST (review R2-2): `if cd <root>; then :; fi; git commit`, `time cd <root> && git
# commit` and a function named `git` all cost the exemption because their first word is not on
# it, not because a list of moves names them. Everything else is judged below. The exotic
# spellings are not resolved; they are not exempted.
#
# NOT A NEW REACH (the D11 freeze, .claude/rules/hook-authoring.md). It is the repair of the
# gate's existing foreign-repository check — `_eg_git_wt_name` already asks git this question,
# for linked worktrees only — widened to every repository git can place, as D10 ratified.
#
# AND IT EXEMPTS THIS GATE ALONE, as the rc-4 arm does: the `exit 0` leaves `_eg_body`'s
# subshell, and the walls folded beside it in hooks/bash-walls.sh — protect-main, the
# read-only-role arm, the background-suite guard — keep their verdicts wherever the commit
# lands (tests/bash-walls.test.sh §18).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
# _eg_cd_targets <command text> -> sets _EG_CDS to EVERY directory the text changes into
# before the commit AFTER the leading one, in the order the shell would obey them, one per
# line; empty when the text names only the leading directory.
#
# WHY A SECOND `cd` IS A REFUSAL AND NOT A TIE-BREAK (critic issue 1, FAIL-OPEN). Branch (2)
# below reads the LEADING `cd` and truncates at the first `;`, `&`, `|` or newline, so every
# later `cd` in the command was invisible to it — and `cd <worktree> && cd <main> && git
# commit` was attributed to the worktree while the commit landed in main, at the worktree
# row's lower step. Nothing in the TEXT says which directory the shell is standing in when
# the commit finally runs: a `||`, a failed `cd`, a subshell and a plain `&&` all read alike
# here, and this repo's own dispatch block warns about the neighbouring hazard (A-46, "a
# failed cd with `;`-chained commands runs them in the main checkout"). So the arm stops
# guessing: two named directories is an ambiguity the writer can spell away, and a wall that
# cannot tell refuses.
#
# ONLY WHAT PRECEDES THE COMMIT COUNTS. A `cd` after the commit cannot move a commit that has
# already run, so the scan stops at the first `git` in the text. If the text carries none this
# reader can see — a spelling only `git_argv_expand` resolves — the whole remainder is
# scanned, which refuses rather than allows.
#
# EVERY TARGET, NOT THE FIRST OF THEM (W6, the re-walk at 4e2ac66). This reader used to take
# the first `cd` after the first separator and return, which cost nothing while the PRESENCE
# of a second `cd` refused: the command was already refused before a third target could
# matter. Once two targets that fold alike became one directory (C3), `cd X && cd X && cd Y
# && git commit` walked through the arm and was judged at X's row with Y never read — while
# the shell commits in Y, which another row owns at another step. That is the fail-open this
# arm exists to close, one `&&` away from the shape it does close. So the scan collects the
# whole list and the caller folds all of it.
#
# ONE PER LINE, AND THE SEPARATOR IS SAFE BY CONSTRUCTION: a newline is one of the four
# characters this scan splits segments on, so no target it yields can contain one. A path
# holding a space or a glob character is carried intact, and `_eg_path_fold`'s own `set -f`
# guard is what keeps it intact downstream.
_EG_CDS=""
_eg_cd_targets() {
  local _t="${1:-}" _rest _seg _p
  _EG_CDS=""
  case "$_t" in
    *[\;\&\|$'\n']*) _rest="${_t#*[;&|$'\n']}" ;;
    *) return 0 ;;
  esac
  case "$_rest" in *git*) _rest="${_rest%%git*}" ;; esac
  while [ -n "$_rest" ]; do
    case "$_rest" in
      *[\;\&\|$'\n']*) _seg="${_rest%%[;&|$'\n']*}"; _rest="${_rest#*[;&|$'\n']}" ;;
      *) _seg="$_rest"; _rest="" ;;
    esac
    while [ -n "$_seg" ]; do
      case "$_seg" in
        ' '*|'	'*|'('*|'{'*) _seg="${_seg#?}" ;;
        *) break ;;
      esac
    done
    case "$_seg" in
      'cd'|'cd '*|'cd	'*)
        _p="${_seg#cd}"
        while [ "${_p# }" != "$_p" ]; do _p="${_p# }"; done
        while [ "${_p#	}" != "$_p" ]; do _p="${_p#	}"; done
        while [ "${_p% }" != "$_p" ]; do _p="${_p% }"; done
        case "$_p" in
          '"'*'"') _p="${_p#\"}"; _p="${_p%\"}" ;;
          "'"*"'") _p="${_p#\'}"; _p="${_p%\'}" ;;
        esac
        [ -n "$_p" ] || _p='~'
        _EG_CDS="${_EG_CDS}${_p}"$'\n'
        ;;
    esac
  done
  return 0
}

# _eg_path_fold <path> -> _EG_FOLD, the same path with its empty and `.` components folded
# away, so `/a/b`, `/a//b`, `/a/b/` and `/a/./b` are one string.
#
# LEXICAL, AND THAT IS THE WHOLE CONTRACT. `..` is deliberately NOT folded: through a symlink
# only a stat could say which directory `/a/b/..` is, and the freeze (D11) forbids a wall
# fetching its own facts. So a path carrying `..` never folds onto another one, and the caller
# below keeps refusing it — the direction a wall that cannot tell has to take.
#
# IT ASSIGNS RATHER THAN PRINTS, like every reader around it: a command substitution here
# would be one fork per commit for a pure string operation.
_EG_FOLD=""
_eg_path_fold() {
  local _in="${1:-}" _seg _out="" _oldifs="$IFS" _hadf=0
  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS='/'
  # shellcheck disable=SC2086  # deliberate split on '/' with globbing disabled
  set -- $_in
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f
  for _seg in "$@"; do
    case "$_seg" in ''|'.') continue ;; esac
    _out="$_out/$_seg"
  done
  _EG_FOLD="${_out:-/}"
}

# _eg_cd_one_dir -> 0 when EVERY `cd` target the text names RESOLVES to ONE directory, and
# 1 with _EG_CD_DIFF set to the first target that does not — the one the refusal names.
#
# THE ARM FIRED ON THE SECOND `cd` TOKEN, NEVER ON A DIFFERENCE (critic C3). `cd X && cd X`
# and `cd X && cd .` were both refused, and the refusal read "the command changes into 'X'
# and then into 'X'" — a sentence that answers its own complaint. D4 ratified that the gate
# does not interpret the shell; comparing targets it has ALREADY extracted is not
# interpretation, and every value is in hand here.
#
# ALL OF THEM, IN ORDER (W6). Reading only the first two let a third `cd` into another
# directory through: two matching targets answered for a command that goes on to name a
# third. So the whole list is walked and the command names one directory only when every
# target folds onto the leading one. Each target is read as the leading one is, and a
# relative target is joined to the directory the PREVIOUS target left the shell standing in.
# The walk stops at the first difference, so that previous directory is always the leading
# one — a relative target after a divergence is never resolved against a guess.
#
# NOTHING IS STAT-ED AND NOTHING IS EXPANDED, so `~`, an unexpanded variable and any `..`
# component stay a second directory and stay refused (A-T22.2, and the D11 freeze).
#
# IT NAMES THE PAIR THAT DISAGREES rather than the first two tokens: the refusal's detail is
# built from `_EG_CWD` and `_EG_CD_DIFF`, so a reader is always shown a real disagreement.
_EG_CD_DIFF=""
_eg_cd_one_dir() {
  local _first _prev _rest _one
  _EG_CD_DIFF=""
  _eg_path_fold "$_EG_CWD"; _first="$_EG_FOLD"; _prev="$_first"
  _rest="$_EG_CDS"
  while [ -n "$_rest" ]; do
    # THE LIST IS CONSUMED WITHOUT ASSUMING ITS SHAPE. Every entry `_eg_cd_targets` writes is
    # newline-TERMINATED, so the `*` branch is unreachable today — and a `${_rest#*NL}` on a
    # string carrying no newline returns it unchanged, which is a wall that never returns and
    # therefore a commit that never lands. The branch costs one `case` and removes that class.
    case "$_rest" in
      *$'\n'*) _one="${_rest%%$'\n'*}"; _rest="${_rest#*$'\n'}" ;;
      *)        _one="$_rest"; _rest="" ;;
    esac
    [ -n "$_one" ] || continue
    case "$_one" in
      /*) _eg_path_fold "$_one" ;;
      *)  _eg_path_fold "${_prev%/}/${_one}" ;;
    esac
    if [ "$_EG_FOLD" != "$_first" ]; then
      _EG_CD_DIFF="$_one"
      return 1
    fi
    _prev="$_EG_FOLD"
  done
  return 0
}

# _eg_commit_cwd -> sets _EG_CWD (the directory the commit is made IN), _EG_CWD_SRC (which
# of the three spellings answered) and, through `_eg_cd_targets`, _EG_CDS.
#
# THREE SPELLINGS, IN PRECEDENCE ORDER, and the order is which one the commit actually obeys:
#   1. `git -C <dir> commit` — git's own cwd override, and it wins over everything;
#   2. a LEADING `cd <absolute dir>` — the shape every bionic writer brief mandates
#      (`cd <worktree> || exit 1` as the first statement). The harness posts the SESSION's
#      cwd in the payload and the `cd` runs afterwards, so without this the dominant real
#      shape would read as a main-root commit and REQ-2 would hold only for fixtures;
#   3. the payload's `.cwd`.
# Only an ABSOLUTE path is taken from the command: a relative path is resolved against a cwd
# this hook would have to re-derive, and guessing it wrong is how a commit gets judged at
# another task's step. Anything unreadable falls through to (3), which is today's answer.
#
# A RELATIVE `-C` FALLS THROUGH RATHER THAN ANSWERING (critic issue 2, wave-14 T24). Branch
# (1) used to return `.` or `sub` verbatim; `_eg_wt_name` then rejected it for not starting
# with `/` and the row was LOST, so `git -C . commit` from inside a worktree was refused for
# Step-5 evidence that cannot exist yet — the exact failure REQ-2 exists to remove, and the
# same commit spelled `git commit` was allowed. A relative `-C` resolves against the shell's
# cwd at that moment, which is precisely what (2) and (3) answer, so it defers to them.
#
# IT ASSIGNS RATHER THAN PRINTS (the `_wall_flatten` pattern, and now a correctness
# requirement rather than a saved fork): two of its three answers are facts about the
# COMMAND that only the caller can act on — an ambiguously named directory is a refusal, not
# a cwd — and a command substitution would leave them behind in a subshell.
_eg_commit_cwd() {
  local _line _oldifs _hadf _p _c _gc
  _EG_CWD=""; _EG_CWD_SRC=""; _EG_CDS=""
  # (1) — prechecked on the raw string so an ordinary commit pays for no second argv pass.
  case " $COMMAND " in
    *" -C "*|*" -C"[\"\']*|*env*)
      _oldifs="$IFS"; _hadf=0
      while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        git_argv_parse "$_line" || continue
        [ "$GIT_SUB" = commit ] || continue
        _git_argv_skip "$_line"
        [ -n "$GIT_ARGV_REST" ] || break
        case "$-" in *f*) _hadf=1 ;; esac
        set -f
        IFS="$GIT_ARGV_US"
        # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
        set -- $GIT_ARGV_REST
        IFS="$_oldifs"
        [ "$_hadf" -eq 1 ] || set +f
        shift   # argv[0], the git binary
        _gc=""
        while [ $# -gt 0 ]; do
          case "$1" in
            -C) shift
                if [ $# -gt 0 ]; then _gc="$1"; fi
                break ;;
            -c|--namespace|--git-dir|--work-tree|--exec-path|--config-env|--super-prefix)
              shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        case "$_gc" in /*) _EG_CWD="$_gc"; _EG_CWD_SRC="-C"; return 0 ;; esac
        # `env -C <dir>` / `env --chdir=<dir>` (wave-20 T3, REQ-3, D3): the argv reader
        # records env's directory, and an ABSOLUTE one is where the commit runs — joined
        # with git's own relative `-C` when there is one, since git resolves that against
        # the directory env moved to. `env-C` is a source `_eg_placed` never admits, so an
        # env spelling is judged against this run's plan and is never exempted as outside
        # the repository (D3-3); the directory it names still picks the task row.
        case "$GIT_ARGV_ENV_CHDIR" in
          /*) if [ -n "$_gc" ]; then _EG_CWD="${GIT_ARGV_ENV_CHDIR%/}/$_gc"; else _EG_CWD="$GIT_ARGV_ENV_CHDIR"; fi
              _EG_CWD_SRC="env-C"; return 0 ;;
        esac
        break
      done <<< "$(git_argv_expand "$COMMAND")"
      ;;
  esac
  # (2) — the leading `cd`, read off the front of the command and nowhere else.
  _c="$COMMAND"
  while [ "${_c# }" != "$_c" ]; do _c="${_c# }"; done
  while [ "${_c#	}" != "$_c" ]; do _c="${_c#	}"; done
  case "$_c" in
    'cd '*|'cd	'*)
      _p="${_c#cd}"
      while [ "${_p# }" != "$_p" ]; do _p="${_p# }"; done
      while [ "${_p#	}" != "$_p" ]; do _p="${_p#	}"; done
      _p="${_p%%[;&|$'\n']*}"
      while [ "${_p% }" != "$_p" ]; do _p="${_p% }"; done
      case "$_p" in
        '"'*'"') _p="${_p#\"}"; _p="${_p%\"}" ;;
        "'"*"'") _p="${_p#\'}"; _p="${_p%\'}" ;;
      esac
      case "$_p" in
        /*) if [ -d "$_p" ]; then
              _EG_CWD="$_p"; _EG_CWD_SRC="cd"
              _eg_cd_targets "$_c"
              return 0
            fi ;;
      esac
      ;;
  esac
  # (3)
  _EG_CWD="$(bionic_jq .cwd)"
  _EG_CWD_SRC="payload"
  return 0
}

# _eg_outside_root <dir> -> 0 with _EG_JUR_TOP set to the repository's toplevel when git
# places <dir> in a repository whose common dir is NOT the engaged root's; 1 for inside AND
# for every failure (no git, no repository, an unreadable root) — the caller judges those.
_EG_JUR_TOP=""
_eg_outside_root() {
  local _d="${1:-}" _both _common _main
  _EG_JUR_TOP=""
  case "$_d" in /*) : ;; *) return 1 ;; esac
  _both="$(git -C "$_d" rev-parse --path-format=absolute --git-common-dir --show-toplevel 2>/dev/null)" || return 1
  _common="${_both%%$'\n'*}"
  [ "$_common" != "$_both" ] || return 1
  _EG_JUR_TOP="${_both#*$'\n'}"
  [ -n "$_common" ] && [ -n "$_EG_JUR_TOP" ] || { _EG_JUR_TOP=""; return 1; }
  if [ -d "$BIONIC_ROOT/.git" ]; then
    _main="$BIONIC_ROOT/.git"
  else
    _main="$(git -C "$BIONIC_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { _EG_JUR_TOP=""; return 1; }
    _main="${_main%%$'\n'*}"
  fi
  if [ -z "$_main" ] || [ "$_common" = "$_main" ] || [ "$_common" -ef "$_main" ]; then
    _EG_JUR_TOP=""
    return 1
  fi
  return 0
}

# _eg_commit_count -> sets _EG_COMMITS to the number of `git … commit` segments in the command
# text, `sh -c`/`eval` strings included (the jurisdiction arm exempts only when it is 1), and
# _EG_COMMIT_NC to the number of `-C` options among the GLOBAL options of the last one counted
# — git's own cwd overrides, before the subcommand, never commit's `-C <commit>` after it —
# plus one for an `env -C`/`--chdir` in front of it (wave-20 T3).
# Assigns rather than prints, like `_eg_commit_cwd`, and forks nothing git-side: it is the
# same pure-shell segment pass the other walls make.
_EG_COMMITS=0
_EG_COMMIT_NC=0
_eg_commit_count() {
  local _line _oldifs="$IFS" _hadf
  _EG_COMMITS=0; _EG_COMMIT_NC=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    git_argv_parse "$_line" || continue
    [ "$GIT_SUB" = commit ] || continue
    _EG_COMMITS=$((_EG_COMMITS + 1))
    _EG_COMMIT_NC=0
    _git_argv_skip "$_line"
    [ -n "$GIT_ARGV_REST" ] || continue
    # env's `-C`/`--chdir` is a directory override too (wave-20 T3, D3).
    [ -z "$GIT_ARGV_ENV_CHDIR" ] || _EG_COMMIT_NC=$((_EG_COMMIT_NC + 1))
    _hadf=0
    case "$-" in *f*) _hadf=1 ;; esac
    set -f
    IFS="$GIT_ARGV_US"
    # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
    set -- $GIT_ARGV_REST
    IFS="$_oldifs"
    [ "$_hadf" -eq 1 ] || set +f
    shift   # argv[0], the git binary
    while [ $# -gt 0 ]; do
      case "$1" in
        -C) _EG_COMMIT_NC=$((_EG_COMMIT_NC + 1)); shift; [ $# -gt 0 ] && shift ;;
        -c|--namespace|--git-dir|--work-tree|--exec-path|--config-env|--super-prefix)
          shift; [ $# -gt 0 ] && shift ;;
        -*) shift ;;
        *) break ;;
      esac
    done
  done <<< "$(git_argv_expand "$COMMAND")"
  return 0
}

# _eg_git_only <text> -> 0 when every segment of <text> is a simple command whose first word
# is `git`, `true`, `:` or `exit`; 1 for anything else.
#
# AN ALLOW-LIST, NOT A DENY-LIST (review R2-2, wave-19 T6e). This reader used to name the words
# that move the shell (`cd`, `pushd`, `eval`, a shell) and pass everything else. That was
# patched three times (R1, C1, R2-2) and was still open: a `cd` behind a reserved word (`if cd`,
# `while ! cd`, `until cd`, `! cd`, `time cd`) runs in the current shell, and its first word was
# on no list. So it now names what IS safe and judges everything else. `git` is the commit and
# its neighbours. `true` and `:` do nothing. `exit` ends the shell before any later commit
# runs. Every other first word costs the exemption: a reserved word, `eval`, `exec`, `env`,
# `xargs`, a shell, a `NAME=value` prefix, a function name.
#
# A SEGMENT SCAN, NOT A PARSER. The text is cut on `;`, `&`, `|` and a newline, and each
# piece's first word is read. A redirection's `>&`, `<&` or `&>` is folded to a plain `>` or
# `<` first, so `2>&1` does not start a segment named `1`. A `(`, `)`, `{`, `}` or backtick
# anywhere costs the exemption outright. Each opens a subshell, a group or a function body
# (`git() { … }` shadows the binary), and none is worth reading. An `sh -c` anywhere costs
# it too, even inside a `git -c` value. The WHOLE text is scanned, before and after the
# commit. Words inside a quoted commit message are read as words, which is the fail-closed
# direction; a writer commits with `-F`.
_eg_git_only() {
  local _t="${1:-}" _seg _w
  case "$_t" in
    *'sh -c'*|*'sh	-c'*) return 1 ;;
    *[\(\)\{\}\`]*) return 1 ;;
  esac
  _t="${_t//">&"/>}"; _t="${_t//"<&"/<}"; _t="${_t//"&>"/>}"
  while [ -n "$_t" ]; do
    case "$_t" in
      *[\;\&\|$'\n']*) _seg="${_t%%[;&|$'\n']*}"; _t="${_t#*[;&|$'\n']}" ;;
      *) _seg="$_t"; _t="" ;;
    esac
    while [ "${_seg# }" != "$_seg" ] || [ "${_seg#	}" != "$_seg" ]; do
      _seg="${_seg# }"; _seg="${_seg#	}"
    done
    _w="${_seg%%[ 	]*}"
    case "$_w" in
      ''|git|true|:|exit) : ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# _eg_placed -> 0 when the ONE commit's directory was read in a shape git obeys exactly as the
# reader does, and 1 for every other shape (critic C1, review R2-2, wave-19). Only these three
# place, and each needs `_eg_git_only` to hold over the text it names:
#   (a) `git -C <absolute dir> commit`. The commit's global options carry exactly ONE `-C`,
#       because git takes the LAST of several and the reader took the first. The WHOLE text
#       must pass `_eg_git_only`, so a function named `git` cannot redirect the commit.
#   (b) a leading `cd <absolute dir>` followed by `&&`, `||`, `;` or a newline. A pipe or a
#       lone `&` runs the `cd` in a subshell that moves nothing, so neither places. The commit
#       carries no `-C`, and everything after the separator must pass `_eg_git_only`.
#   (c) the payload cwd. The commit carries no `-C`, and the whole text must pass
#       `_eg_git_only`. This is the writer standing in the scratch repository or the nested
#       bed (AC-9.1, AC-9.3).
# And in all three, no `--git-dir`, `--work-tree`, `GIT_DIR`, `GIT_WORK_TREE` or
# `GIT_COMMON_DIR` anywhere in the command: each names the repository outright, whatever
# directory the commit runs in. The check is on the raw text, so the words inside a commit
# message cost the exemption too — the fail-closed direction, and a writer commits with `-F`.
#
# THE DISQUALIFIER ALSO READS A DE-QUOTED COPY (audit V3-1, wave-19 T6f). A `"`, `'` or `\`
# dropped into the middle of the flag's name (`--git-d""ir`, `--git-di\r`) defeats the raw
# substring match above while the shell still hands git the flag whole once it strips the
# quote or backslash, so the commit really lands in the named (root) repository. This is not
# shell parsing — it strips every `"`, `'` and `\` character from the text with no attempt at
# fidelity, and any spelling that COULD reach the disqualifier once they are gone is treated
# as the disqualifier. Both the raw text and this stripped view are tested; either one
# matching costs the exemption (fail-closed, review R2-2's direction). `_eg_git_only`'s
# allow-list needs no matching change: it already fails closed on any first word that is not
# byte-for-byte `git`, `true`, `:` or `exit`, so a quote- or backslash-split `git` itself is
# already judged rather than exempted (A-T6.13).
_eg_placed() {
  local _c _sep _dq
  _dq="${COMMAND//\"/}"
  _dq="${_dq//\'/}"
  _dq="${_dq//\\/}"
  case "$COMMAND" in
    *--git-dir*|*--work-tree*|*GIT_DIR*|*GIT_WORK_TREE*|*GIT_COMMON_DIR*) return 1 ;;
  esac
  case "$_dq" in
    *--git-dir*|*--work-tree*|*GIT_DIR*|*GIT_WORK_TREE*|*GIT_COMMON_DIR*) return 1 ;;
  esac
  case "$_EG_CWD_SRC" in
    -C) [ "$_EG_COMMIT_NC" -eq 1 ] && _eg_git_only "$COMMAND" ;;
    cd)
      [ "$_EG_COMMIT_NC" -eq 0 ] || return 1
      _c="$COMMAND"
      while [ "${_c# }" != "$_c" ] || [ "${_c#	}" != "$_c" ]; do _c="${_c# }"; _c="${_c#	}"; done
      _sep="${_c#"${_c%%[;&|$'\n']*}"}"
      case "$_sep" in
        '&&'*) _sep="${_sep#&&}" ;;
        '||'*) _sep="${_sep#||}" ;;
        ';'*|$'\n'*) _sep="${_sep#?}" ;;
        *) return 1 ;;
      esac
      _eg_git_only "$_sep" ;;
    payload)
      [ "$_EG_COMMIT_NC" -eq 0 ] && _eg_git_only "$COMMAND" ;;
    *) return 1 ;;
  esac
}

_eg_commit_cwd                       # sets _EG_CWD, _EG_CWD_SRC and _EG_CDS — once, for this arm and every reader below
_eg_commit_count                     # sets _EG_COMMITS and _EG_COMMIT_NC — only ONE commit can be placed outside
if [ "$_EG_COMMITS" -eq 1 ] \
   && _eg_placed \
   && _eg_outside_root "$_EG_CWD"; then
  printf 'evidence-gate: %s is outside the engaged repository (%s); the evidence gate has no plan here\n' \
    "$_EG_JUR_TOP" "$BIONIC_ROOT" >&2
  exit 0
fi

# THE DOCS ROOT, FROM THE LIBRARY. This hook carried `resolve_docs_root()` and was the
# designated ORIGIN of the four hook copies cross-gate §R held body-for-body. There are no
# copies now: lib/roots.sh's `docs_root` is the one definition and every former carrier is
# a caller, held by cross-gate §Roots (epic-22 wave-01, N1).
#
# Read unconditionally, next to the other globals: this hook runs `set -u`, and
# a variable bound on only some code paths crashes the others. See
# `.claude/rules/hook-authoring.md` § "`set -u` and conditionally-bound variables".
# The misplacement sweep below is this value's only remaining consumer — plan
# SELECTION moved to the library.
DOCS_ROOT=$(docs_root "$BIONIC_ROOT")

# THE PLAN, from the library (lib/run.sh's `active_plan`). This used to be a private
# `has_sdlc_state()` plus a newest-.md walk — one of five copies of one question
# ("which plan is the active one") that every wall in the fleet asked separately. A
# wall that picks a different plan than the predicate that armed it is a wall
# enforcing against a run nobody is in, so the two facts now come from one reader.
#
# A CANDIDATE IS STILL A PLAN ONLY IF IT CARRIES A `## SDLC State` HEADING. Without
# that filter a stray marker-less *.md that happens to be newest under plans/ — a
# continuation note, a Step-9 artifact, a probe scrap — wins the newest race,
# `current:` parses empty, and every wall reading it passes silently while a wave is
# live. That is measured, not hypothetical: it disarmed the dispatch wall repo-wide
# for ~15 minutes on 2026-08-15 (record/session-20260815-landing-supervision/
# t8-forensic-read.md). The filter lives in `active_plan` now.
#
# WHICH plan, THOUGH, IS THE SESSION'S OWN QUESTION SINCE wave-session-bound-run
# (2026-09-04, spec AC-1/AC-3/AC-6). `active_plan` answers a ROOT: the newest plan under
# this project's docs root. Engagement is keyed to a SESSION. Two engaged sessions in one
# repository therefore shared one run identity, and this gate — whose whole subject is the
# plan a commit is measured against — measured both sessions' commits against whichever
# plan was newest. `session_run` is the reader that asks the session's own marker first;
# its verdict is taken ONCE here and consumed at both of this hook's resolution sites, so
# the file that gets validated and the run that decides whether to enforce can never
# disagree about which run this session is in.
#
#   bound-open <p>    this session's own plan, open      -> <p> is THE plan; enforce
#   bound-closed <p>  its own plan, delivered/gone       -> <p> is THE plan; do not enforce
#   fallback <p>      no binding: today's newest-plan    -> announced, then today's path
#   none              no binding and no open run         -> today's path, unchanged
#
# A BOUND SESSION NEVER FALLS THROUGH TO ANOTHER PLAN (AC-6). `bound-closed` is a terminal
# answer, not a miss to recover from: the moment a run closes is exactly the moment a scan
# would hand its session somebody else's run, which is the failure this wave was opened on.
# So the closed plan stays THE plan here — the hygiene refusals below still judge it,
# because a plan that lies is a defect in every state and this hook's ordering contract
# says so — and nothing else in the root is read to replace it.
EG_RUN=$(session_run "$BIONIC_ROOT" "$BIONIC_SID")
EG_VERDICT="${EG_RUN%% *}"
EG_VPATH=""
case "$EG_RUN" in *' '*) EG_VPATH="${EG_RUN#* }" ;; esac

case "$EG_VERDICT" in
  bound-open|bound-closed)
    PLAN="$EG_VPATH"
    ;;
  *)
    # UNBOUND: today's line, untouched, and reached by exactly the same code that
    # reached it before this wave. `fallback` and `none` both mean "no binding", and
    # AC-3's promise is that such a session behaves EXACTLY as it did — so the promise is
    # kept by running the old path rather than by a new one that agrees with it.
    PLAN=$(active_plan "$BIONIC_ROOT") || PLAN=""
    ;;
esac

# THE ANNOUNCEMENT, ONCE PER INVOCATION AND NOT ONCE PER SITE (AC-3, AC-6). It is emitted
# where the resolution happens, not where each site consumes it, because the fact being
# reported is the resolution and there is only one of those. Both lines are reports on the
# hook's only channel — never a refusal, and never an exit.
case "$EG_VERDICT" in
  fallback)
    echo "evidence-gate: run resolved by newest-plan fallback (session unbound) — $PLAN" >&2
    ;;
  bound-closed)
    echo "evidence-gate: bound plan closed — $PLAN; this session has no open run" >&2
    ;;
esac

# ---------- AC-13: misplacement blocks; absence never does ----------
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# No plan file was found in this project's plan directories. That used to be an
# unconditional `exit 0`, and it is this hook's fail-open — a structurally
# different one from the governing-skill hook's, which is why the two are fixed
# and tested independently. This one never tests `.bionic/` at all: every
# candidate directory is skipped by `[ -d "$d" ] || continue`, PLAN comes back
# empty, and the commit passes ungated.
#
# The guard was PROJECT_PLAN from the Step-6 C1/S2 repair until 2026-07-28,
# because PLAN then meant "no plan in ANY searched directory" and the first
# directory searched was the project-agnostic `~/.claude/plans/`: one unrelated
# `.md` there made PLAN non-empty and this whole block dead. Deleting that
# directory from the search set fixes the same hole at its root, so the guard is
# back on PLAN — which now means what C1/S2 needed it to mean.
#
# ABSENT is not an error and must never block. No plan anywhere is every commit
# in every project that does not use this lifecycle, plus the normal first-run
# state of one that does.
#
# MISPLACED is: a plan carrying the run-state marker exists inside the project
# but outside every directory this gate searches. The gate is then silently
# disabled — precisely the failure the AC exists to convert into a block.
#
# Scoping, deliberately narrow, because a false positive here walls off every
# commit in the project:
#   - `*.plan.md` only. The gate consumes plans. A misplaced file under the
#     flat `~/.claude/plans/<name>.md` convention is not covered — that whole
#     directory is already searched.
#   - The LEADING frontmatter must declare `canonical_sdlc_version`, the
#     run-state marker (never `governing-skill`, the artifact-author field —
#     see `.claude/rules/hook-authoring.md` — machine-local, gitignored,
#     authored in place; no script recreates it). Reading only the leading block is
#     what keeps a fenced example in a documentation page from counting.
#   - The whole docs root is "placed", not just plans/ and incidents/:
#     <docs-root>/spikes/ and <docs-root>/record/ hold real artifacts carrying
#     this frontmatter, and the governing-skill hook treats them as placed too.
#   - Bounded walk: `.git` and `node_modules` pruned, depth 5, filename match
#     first. It runs only when no plan was found at all, so a project in an
#     active canonical-sdlc run never pays for it.
#
# THE GUARD IS `[ -z "$PLAN" ]` AND NOTHING ELSE (S10a, critic C-1). It read
# `[ -z "$PLAN" ] || [ ! -f "$PLAN" ]` until this wave made the second half
# reachable. Before the wave `PLAN` came from `active_plan`, which reports only
# files `find -type f` had just produced, so a non-empty `PLAN` naming a missing
# file did not exist and the two conditions were one. A BINDING OUTLIVES THE FILE
# IT NAMES: `session_run` answers `bound-closed <p>` when the bound plan has been
# deleted, moved into another epic directory, or restored away, and that path is
# taken as `PLAN` above. It walked in here and turned this sweep — six hundred
# lines above the `bound-closed → exit 0` escape — into a live commit blocker for
# a session whose own plan is simply gone, naming an unrelated stray file and
# telling the operator to move it. The two conditions are different questions now
# and they get different answers: NO PLAN AT ALL is the sweep's question, and a
# bound plan that is not on disk is the arm below it.
if [ -z "$PLAN" ]; then
  MISPLACED_PLAN=""
  if [ -d "$BIONIC_ROOT" ]; then
    while IFS= read -r -d '' f; do
      case "$f" in "$DOCS_ROOT"/*) continue ;; esac
      if head -c 8192 "$f" \
         | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' \
         | awk 'NR == 1 && $0 == "---" { inside = 1; next }
                inside && $0 == "---" { exit }
                inside { print }' \
         | grep -qE '^[[:space:]]*canonical_sdlc_version[[:space:]]*:'; then
        MISPLACED_PLAN="$f"
        break
      fi
    done < <(find "$BIONIC_ROOT" -maxdepth 5 \
               \( -name .git -o -name node_modules \) -prune -o \
               -type f -name '*.plan.md' -print0 2>/dev/null)
  fi

  if [ -n "$MISPLACED_PLAN" ]; then
    _eg_detail="a canonical-sdlc plan is misplaced — this commit would pass ungated.
Misplaced plan: $MISPLACED_PLAN
Docs root:      $DOCS_ROOT
The evidence gate searches only the plan directories for this project, so a plan
outside them silently disables it — no step evidence is checked at all.
Fix: move it under $DOCS_ROOT/plans/ (or $DOCS_ROOT/incidents/ for an incident run)."
    refuse exit2 commit "a plan sits outside the docs root" "move the plan under docs root" "$_eg_detail"
  fi

  # ABSENCE: nothing misplaced and nothing to validate. Never blocks — this is
  # every commit in every project that does not use the lifecycle, plus the
  # normal first-run state of one that does. This exit lived in a second `if`
  # on its own until 2026-07-28, when the sweep's guard was the narrower
  # PROJECT_PLAN and the two conditions could differ; on one guard they cannot,
  # so the sweep and its fall-through are one block.
  exit 0
fi

# THE PLAN IS NAMED BUT NOT ON DISK (S10a, critic C-1). Reachable only through a
# binding — see the guard above for why. This is engaged-with-no-run, the same
# state `bound-closed` reaches at the enforcement gate below, so the answer is the
# same: allow, and say why. It cannot be the misplacement sweep's answer, because
# nothing is misplaced; and it cannot be the hygiene refusals' answer either,
# because every one of them reads a file that is not there.
#
# THE RECOVERY IS NAMED, because it is not guessable and it is not what it was.
# Re-invoking the skill USED to rewrite a `bound-closed` marker by the count rule;
# since S10a a binding survives re-engagement open or closed (review C-1), so the
# only route back is the operator naming a live run. `poker bind` refuses a plan
# that is not an open run of this root, which is exactly what makes it the right
# instrument here: it cannot re-create this state.
if [ ! -f "$PLAN" ]; then
  echo "evidence-gate: the plan this session is bound to is not on disk — $PLAN" >&2
  echo "  Nothing is validated for this commit. Name a live run for this session with:" >&2
  echo "    bash $(dirname "$0")/session-poker.sh bind <plan>" >&2
  exit 0
fi

# The newest plan has no ## SDLC State section → not a canonical-sdlc run.
# Fence-aware (matches the SECTION extraction below): a `## SDLC State` heading
# that appears ONLY inside a ``` fenced example is documentation, not state, so
# the file passes through as non-canonical rather than being parsed and then
# false-blocked on the empty extraction. Line endings normalized (CRLF and
# CR-only) to real newlines first — see normalize_newlines.
if [ -z "$(normalize_newlines "$PLAN" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { print "yes"; exit }
')" ]; then
  exit 0
fi

# Extract YAML frontmatter (between first two `---` lines at column 0)
# if the plan has any. Used to read the version marker, the triple, and the
# discriminator flags the checks below key off.
#
# CRLF/CR-only plans would otherwise defeat the exact-match `$0=="---"`
# comparison ("---\r" != "---"), so line endings are normalized to \n before
# every awk pass (normalize_newlines) — meaning every downstream parse
# (frontmatter values, SECTION lines, CURRENT, evidence blocks) sees plain
# \n text regardless of the file's original line-ending style.
FRONTMATTER=$(normalize_newlines "$PLAN" | awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f')

frontmatter_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' \
    | sed -E "s/^['\"]//;s/['\"]\$//"
}

DEPLOY_TARGET=$(frontmatter_get deploy_target)
SDLC_VERSION=$(frontmatter_get canonical_sdlc_version)
USE_WORKTREE=$(frontmatter_get use_worktree)
SCALE=$(frontmatter_get scale)
INTENT=$(frontmatter_get intent)
RIGOR=$(frontmatter_get rigor)
MULTI_AGENT=$(frontmatter_get multi_agent)

# ONE supported version. Anything else — an older number, a typo, an empty
# value, garbage — blocks. Symmetric with the governing-skill hook. There is
# no version dispatch anywhere below this line, so there is also no path that
# reaches `exit 0` by matching no arm.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
SUPPORTED_SDLC_VERSION=14

if [ "$SDLC_VERSION" != "$SUPPORTED_SDLC_VERSION" ]; then
  _eg_detail="canonical-sdlc evidence-gate: plan declares canonical_sdlc_version: '$SDLC_VERSION'.
Plan: $PLAN
Fix: set 'canonical_sdlc_version: ${SUPPORTED_SDLC_VERSION}' — the only supported version."
  refuse exit2 commit "this plan declares an unsupported sdlc version" "set the supported version" "$_eg_detail"
fi

# Whole-value placeholder test: trim leading/trailing whitespace, lowercase,
# then require whole-value EQUALITY against the known token set. A token that
# merely appears as a substring of a longer value ("resolved TODOs",
# "*.example placeholders", "status pending → done") is legal evidence.
# "in progress" and its whitespace-free "inprogress" are both listed so
# either spelling of the value matches. Defined here (ahead of the Step-line
# checks) so the task-ledger validator, which runs before them, can reuse it.
is_placeholder_value() {
  local v
  v=$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')
  case "$v" in
    todo|pending|"in progress"|inprogress|xxx|tbd|placeholder) return 0 ;;
    *) return 1 ;;
  esac
}

# Audit dir follows the PLAN's own project, not necessarily the invoking one:
# findings live with the project that owns the artifact, and every worktree of one
# repo shares one audit file. `project_root` always answers (falling back to the
# path's own directory), so there is no fallback arm left to get wrong — the old
# copy's second argument existed only because its git call could fail silently.
# [INSTRUMENT]
# A TABLE CELL THAT MEANS "NOTHING HERE" (wave-16 REQ-12, AC-12.2; carry-over 20).
#
# The ten-column `## Tasks` contract spells "none" as an em dash in its `deps` and
# `worktree` cells, and a table author carries that spelling into every other free-text
# cell — including the Verification Matrix's `auditor` cell, where "no verdict yet" is the
# ordinary state of a T4 row. The T4 exemption asks for an auditor cell that is EMPTY or
# `CONFIRMED` (see the arm below), so `—` took a row nobody had ruled on to the refusal
# written for a STANDING FINDING, and told its author to settle a verdict that did not
# exist. Three spellings fold: the em dash, a bare ASCII hyphen, and `n/a` in any case.
#
# WHAT DOES NOT FOLD is anything with content — `REFUTED`, `UNVERIFIABLE`, `n/a: <reason>`
# — because those are verdicts, and the arm that exists for them must still meet them.
# Both readers of an auditor cell fold the same way, which is the agreement D15 names.
placeholder_cell() {  # $1 = a cell's text -> the text, or empty when it means "none"
  case "$1" in
    '—'|'-'|'n/a'|'N/A'|'n/A'|'N/a') printf '' ;;
    *) printf '%s' "$1" ;;
  esac
}

audit_root() {
  local r
  r=$(project_root "$(dirname "$PLAN")")
  # project_root ALWAYS answers: with no `.bionic` ancestor it falls back to the git
  # toplevel, then to the path itself. Those fallbacks name a directory, not a
  # project, so the finding would land keyed on a tree that owns nothing. When the
  # answer is not a real project, the invoking project (itself library-resolved) is
  # the honest owner — which is the fail-open the walk-up this replaced also had.
  if [ -d "$r/.bionic" ]; then printf '%s\n' "$r"; else printf '%s\n' "$BIONIC_ROOT"; fi
}

# `audit_path` AND `log_finding` LIVE IN payload/scripts/lib/root.sh NOW (epic-23
# wave-12-fixit-171, REQ-8, spec D6) — one definition each for the three processes that used
# to carry a copy, COUNTED rather than compared by tests/cross-gate-agreement.test.sh §AP.
# hooks/bash-walls.sh sources root.sh at :205, above this library at :217, so both are in
# hand here and no library list widened to make that true.
#
# WHAT STAYS BEHIND IS THIS GATE'S HALF OF log_finding's CONTRACT: the three values that
# made the two copies differ — the channel name, the subject, and the root — declared once,
# here, where `$PLAN` is already resolved and `audit_root` is already defined.
#
# `audit_root` (directly above) still selects WHICH project a finding belongs to, and it
# stays a FUNCTION rather than a captured value because it walks up from the plan's own
# directory and costs a subprocess: the shared log_finding resolves it only when a finding
# actually fires, never on every judged command. Incident 0001 moved WHERE the file for that
# project lives — $HOME/.claude/logs/<project-slug>/, outside every consuming project tree,
# never .bionic/memory/ again.
# [INSTRUMENT]
BIONIC_FINDING_CHANNEL="evidence-gate"
BIONIC_FINDING_SUBJECT="$PLAN"
bionic_finding_root() { audit_root; }

# Normalize a task row's rigor cell to its effective rigor lane. Whole-value
# `case` equality against the rigor enum (bash-3.2 safe — no associative arrays,
# same idiom as is_r7_key below): a cell already naming a lane passes through; a
# non-empty cell outside the enum is INVALID; an empty cell inherits the
# plan-level RIGOR when that itself names a lane, else defaults to `tested` (the
# floor — see plan Assumption A3). Defined ahead of validate_task_ledger (which
# runs at the `current: T<n>` branch, before is_r7_key is defined below) so the
# validator can call it — same placement rationale as is_placeholder_value.
effective_row_rigor() {  # $1 = row's rigor cell
  local cell
  cell=$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$cell" in
    tested|peer-reviewed|audited) echo "$cell"; return ;;
    "") : ;;
    *) echo "INVALID"; return ;;
  esac
  case "$RIGOR" in
    tested|peer-reviewed|audited) echo "$RIGOR" ;;
    *) echo "tested" ;;
  esac
}

# Total order over the rigor enum, for the per-row FLOOR check (task 4/8).
# tested < peer-reviewed < audited. An empty/unknown value maps to 0 (the tested
# floor) so an unset frontmatter rigor never manufactures a phantom downgrade.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
# Mirrors the governing-skill hook's ord map at its rigor check (kept in sync by
# hand, not imported — the two hooks share no source). bash-3.2 safe whole-value
# `case`, same idiom as effective_row_rigor above.
rigor_ord() {  # $1 = a rigor lane name (or empty)
  case "$1" in
    peer-reviewed) echo 1 ;;
    audited)       echo 2 ;;
    *)             echo 0 ;;  # tested, empty, or unknown → the floor
  esac
}

# Is the independent auditor's verdict a WALL on this run? (B-10 / R-11.)
# SKILL.md's rigor table: `tested` = "Both independent assurance roles.
# Self-review only." — no auditor is ever sent, so demanding an auditor
# CONFIRMED on every matrix row (and an `auditor:` pointer in the Step-5 block)
# refused a `tested` run for the absence of a verdict its own rigor says nobody
# was commissioned to write. B-10's repro: a bugfix · tested · task run refused
# at current: 9 on "matrix row 'AC-1' auditor verdict is 'empty'".
#
# At `tested` the matrix's auditor column is NOT READ — any value, empty
# included, passes — and the Step-5 pointer is not demanded. At
# `peer-reviewed` (which adds the auditor) and `audited` both walls stand
# unchanged.
#
# FAIL-CLOSED on an unknown or missing value: a plan that does not say what
# rigor it runs at has not bought the relaxation, and a typo must not become a
# bypass (same rationale as walk_mode's off-enum arm). This is deliberately
# ASYMMETRIC with effective_row_rigor, which resolves an unknown frontmatter
# rigor DOWN to the tested floor: there, the fallback picks a lane for a row
# that must run in one; here, the fallback decides whether a wall stands.
#
# Scope: the MATRIX wall and the Step-5 pointer only. The task-ledger lanes
# (apply_rigor_lanes) were already rigor-keyed and read EFFECTIVE row rigor, so
# a row whose own cell raises it above the frontmatter keeps its auditor/critic
# demand there — the matrix carries no per-row rigor cell to raise.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
matrix_auditor_required() {
  case "$RIGOR" in
    tested) return 1 ;;
    *)      return 0 ;;  # peer-reviewed, audited, and anything unrecognized
  esac
}

# Proof-shape test (D-task 4/2): an evidence value counts as "proof-shaped"
# — a command invocation + result counts, not prose — iff it contains BOTH
# at least one digit AND at least one command token. A command token is any
# of: a backtick; a literal '/' anywhere (a path, e.g. 'hooks/foo.sh'); or a
# whole-word match against the fixed runner list (bash-3.2 safe — no
# associative arrays, `grep -Ew` for the bounded whole-word match so `test`
# matches in "bash test.sh 12/12" but `testing` never triggers on a `test`
# substring). Returns 0 (proof-shaped) / 1 (not) — never blocks itself; the
# caller (apply_rigor_lanes) decides what a failure means.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
is_proof_shaped() {  # $1 = evidence value
  local v="$1"
  grep -qE '[0-9]' <<< "$v" || return 1
  if grep -q '`' <<< "$v"; then
    return 0
  fi
  if grep -qF '/' <<< "$v"; then
    return 0
  fi
  if grep -Ewq 'bash|sh|npm|pnpm|yarn|make|pytest|go|cargo|git|test' <<< "$v"; then
    return 0
  fi
  return 1
}

# Rigor-keyed evidence lanes (D-task 4/2, TASK SCALE ONLY). Applies to
# the addressed row (any status) and to every OTHER row with status `done`
# that has a non-empty, non-placeholder evidence line — the caller only
# invokes this once those upstream 4/1 presence/placeholder checks (and, for
# the addressed row, the rigor-enum check) have already passed. BLOCKS
# (exit 2) on any lane breach:
#   - effective rigor peer-reviewed or audited: evidence must be proof-shaped.
#   - status done AND effective rigor >= peer-reviewed AND the run has
#     reached Step 6: evidence must name an `auditor` verdict.
#   - status done AND effective rigor audited AND the run has reached Step 6:
#     evidence must ALSO name a `critic` verdict.
# The `tested` floor carries none of these demands — 4/1's presence +
# placeholder checks are its entire contract (plan Assumption A4: the literal
# substrings are sufficient tokens, no pointer-format sub-schema).
#
# THE VERDICT LANES ARE STEP-GATED, NOT STATUS-GATED (wave-18 REQ-1, D1, ADR-033).
# `done` is the one terminal word at task scale and it means the work is finished
# and the tree released — a fact about the ROW. An auditor verdict and a critic
# verdict are facts about the RUN: Step 5 produces the first and Step 6 the
# second, so before Step 6 no honest row can carry them. Demanding them of a
# `done` row at `current: T<n>` left a finished task with no word it could truthfully
# write (`active` on a released tree is false, `done` was refused), and a consumer
# run spawned six worktrees for two lines of work to get around it. The arms
# below therefore ask `_eg_verdicts_owed` — the plan's own declared `current:`,
# numeric and >= 6 — before they ask anything of the evidence. Everything else
# here is unchanged: the proof-shape lane is not a verdict and fires at every
# `current:`, and a `done` row ALWAYS owes its `- T<n>:` evidence line (the
# presence/placeholder arms above this call).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# THE RUN'S OWN `current:`, never the substituted one. `_EG_DECLARED_CURRENT` is
# recorded where `CURRENT` is first parsed and is not touched by either subject
# substitution below (a row's step, or a task row's id), because the question this
# answers is "has the run reached the step that produces verdicts", which no
# per-commit subject can move.
_eg_verdicts_owed() {
  local _c="${_EG_DECLARED_CURRENT%[ab]}"
  case "$_c" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_c" -ge 6 ]
}

apply_rigor_lanes() {  # $1=id $2=status $3=effective-rigor $4=evidence-value
  local id="$1" status="$2" eff="$3" ev="$4"
  case "$eff" in
    peer-reviewed|audited)
      if ! is_proof_shaped "$ev"; then
        _eg_detail="canonical-sdlc task ${id} evidence must show a command + counts, not prose, at rigor '${eff}' ('${ev}').
Plan: $PLAN
Fix: replace the '- ${id}:' evidence with the actual command invocation and result counts (e.g. 'bash test.sh 12/12 green')."
        refuse exit2 commit "that task's evidence is prose" "record the command and counts" "$_eg_detail"
      fi
      ;;
  esac
  if [ "$status" = "done" ] && _eg_verdicts_owed; then
    case "$eff" in
      peer-reviewed|audited)
        if ! grep -Ewq 'auditor' <<< "$ev"; then
          _eg_detail="canonical-sdlc task ${id} is done at rigor '${eff}' but its evidence has no 'auditor' verdict ('${ev}').
Plan: $PLAN
Fix: record the independent auditor's verdict in the '- ${id}:' evidence line before marking done."
          refuse exit2 commit "that task is done with no auditor verdict" "record the auditor's verdict" "$_eg_detail"
        fi
        ;;
    esac
    if [ "$eff" = "audited" ]; then
      if ! grep -Ewq 'critic' <<< "$ev"; then
        _eg_detail="canonical-sdlc task ${id} is done at rigor 'audited' but its evidence has no 'critic' verdict ('${ev}').
Plan: $PLAN
Fix: record the adversarial critic's verdict in the '- ${id}:' evidence line before marking done."
        refuse exit2 commit "that task is done with no critic verdict" "record the critic's verdict" "$_eg_detail"
      fi
    fi
  fi
}

# Per-row rigor FLOOR check (task 4/8, A15 — user-ratified, momentous). The
# per-row `rigor` cell is a FLOOR unified with the run-rigor floor model: a
# cell RAISING a row above the frontmatter rigor is always allowed (the cell
# drives the heavier lane, 4/4), but a cell LOWERING it below the frontmatter
# rigor is a DOWNGRADE — a recorded decision, never silent. A downgrade BLOCKS
# (exit 2) UNLESS the row's `- T<n>:` evidence line carries a whole-word `waiver`
# marker (Waiver Protocol — same `grep -Ewq` word-boundary idiom as the lane
# token checks), in which case the row proceeds at its (lower) cell lane.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# Called on exactly the rows the rigor lanes cover — the addressed unit (any
# status) and non-addressed `done` rows with real evidence — AFTER their
# presence/placeholder checks and the per-row INVALID guard, and BEFORE
# apply_rigor_lanes. Ordering rationale: a missing/placeholder evidence block
# (addressed unit, or audited non-addressed via ledger_shape_fail) and the
# INVALID-cell block both fire upstream of this, so they still win — a row with
# no evidence line never reaches here (there is no line to hold a waiver, and its
# absence already blocks or logs). `eff` is the RESOLVED effective rigor: an
# empty cell resolves to the frontmatter rigor, so rigor_ord(eff) ==
# rigor_ord(RIGOR) and no phantom downgrade fires — only an explicit lower cell
# trips it. A cell EQUAL to the frontmatter is not a downgrade (strict `<`).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
enforce_rigor_floor() {  # $1=id  $2=effective-rigor  $3=evidence-value
  local id="$1" eff="$2" ev="$3"
  [ "$(rigor_ord "$eff")" -lt "$(rigor_ord "$RIGOR")" ] || return 0
  if grep -Ewq 'waiver' <<< "$ev"; then
    return 0  # recorded downgrade — proceed at the lower cell lane
  fi
  _eg_detail="canonical-sdlc task ${id} lowers rigor from '${RIGOR}' to '${eff}', below the plan's floor.
Plan: $PLAN
Fix: raise the cell to at least '${RIGOR}', or record a downgrade: add 'waiver: <user> <date> <reason>' to the '- ${id}:' evidence line (Waiver Protocol)."
  refuse exit2 commit "that task lowers rigor below the floor" "raise the rigor, or waive it" "$_eg_detail"
}

# Router for the previously-log-only NON-addressed-row ledger-shape checks
# (D-task 4/3, task scale). On a frontmatter `rigor: audited` plan these
# promote to BLOCKING (exit 2); at any other rigor they stay log-only findings
# (D14, unchanged). The detail string is authored once by the caller and used
# verbatim in whichever channel fires. The addressed-unit floor (4/1) and the
# rigor lanes (4/2) are NOT routed through here — they already block
# unconditionally where they should.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
ledger_shape_fail() {  # <fact> <fix> <observation>
  # TWO EXITS AND ONLY ONE IS A REFUSAL (F-P2). At `rigor: audited` this blocks; at any
  # other rigor it logs a finding and RETURNS. `refuse` always exits, so it goes INSIDE
  # the audited branch — a frame-level substitution would turn every log-only finding
  # into a hard block. The policy sentence the frame used to print as its Fix is about
  # audited rigor, not about repairing the row, so under D-1 it becomes `detail` and the
  # caller supplies a real repair (F-P7).
  if [ "$RIGOR" = audited ]; then
    refuse exit2 commit "$1" "$2" "canonical-sdlc task-ledger: $3
Plan: $PLAN
Audited rigor makes the ledger-shape checks blocking; a non-audited plan would log this as a finding instead."
  fi
  log_finding task-ledger "$3"
}

# Task-scale ledger validation (D12). Reads the `## Tasks` registration
# table (fence-aware, the matrix_section idiom) and the per-task `- T<n>:`
# evidence lines in the ## SDLC State section (SECTION, already newline-normalized).
#
# Two lanes (task 4/1), plus rigor-keyed lanes on top (task 4/2):
#   - THE ADDRESSED UNIT — the `T<n>` named by `current: T<n>` — is BLOCKING at
#     the tested floor: its row must exist in `## Tasks`, carry a non-placeholder
#     `- T<n>:` evidence line, and have a rigor cell that resolves (its cell
#     names a lane, or is empty; a non-empty cell outside the enum is INVALID).
#     Any breach emits a 3-line block message and exit 2. Once past the floor,
#     apply_rigor_lanes (4/2) applies the proof-shape/auditor/critic lanes keyed
#     to its effective rigor.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
#   - EVERY OTHER row stays LOG-ONLY (D14, check-id `task-ledger`) for status
#     and presence/placeholder: status outside {pending,active,done,dropped},
#     or an active/done task with no `- T<n>:` line or a placeholder/empty
#     value, each append one finding and never block. Missing `## Tasks`
#     entirely is also log-only here. A `done` row that DOES have a non-empty,
#     non-placeholder evidence line resolves its effective rigor and is
#     additionally passed through apply_rigor_lanes (4/2) — BLOCKING, since a
#     done claim at peer-reviewed+ rigor without real evidence is a false-done
#     claim, not a bookkeeping gap. A malformed (off-enum) rigor cell on ANY row
#     — addressed or not, at ANY status (done, active, pending, dropped) — is
#     caught earlier by the per-row INVALID guard (4/7), which resolves the cell
#     and BLOCKS unconditionally at any frontmatter rigor before this
#     status-based branching; see that guard for the rationale.
# [INSTRUMENT]
# ---------- the per-row evidence-line obligation (wave-17 REQ-5, AC-5.1) ----------
#
# ONE LINE PER `## Tasks` ROW, and the refusal says so. Two arms check it — the addressed
# unit's at task scale, and every dispatched row's at wave scale — and both used to name
# ONE id and ask for "a '- <id>:' evidence line". An author owing eighteen of them learned
# of the second only after landing the first (wave-16's A-orch-10 is that specimen), and
# neither arm ever said the obligation was per row. So the COUNT and the IDS come from the
# whole table in one pass, whichever arm fires.
#
# THE TRIGGER DOES NOT MOVE. At task scale the arm still fires on the ADDRESSED unit's
# missing line — a non-addressed `active|done` row short of one is a different refusal
# (ledger_shape_fail, blocking only at audited rigor) and stays that way. What changed is
# what the refusal then says.
#
# NO NEW FACT IS FETCHED (D11): the rows are the caller's own `units_rows` output and the
# lookup is the same anchored grep over `$SECTION` both arms already ran, asked once per
# row instead of once.
missing_evidence_ids() {  # $1 = units_rows output -> the T-ids with no line, one per line
  local line id ev
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(units_field "$line" id)
    case "$id" in T[0-9]*) : ;; *) continue ;; esac
    ev=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:" | head -1 \
         | sed -E "s/^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    [ -n "$ev" ] || printf '%s\n' "$id"
  done <<< "$1"
}

# Refuse for EVERY row short of its evidence line, or return 0 if none is. The id list is
# printed as the lines the author has to write, so the repair is a copy out of the refusal;
# it sits LAST so refuse.sh's twelve-line fold (BIONIC_REFUSE_DETAIL_LINES, a ratified
# bound this does not move) bites the list rather than the instruction above it.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
refuse_missing_evidence_lines() {  # $1 = units_rows output
  local ids count subject verdict
  ids="$(missing_evidence_ids "$1")"
  [ -n "$ids" ] || return 0
  count=$(printf '%s\n' "$ids" | wc -l | tr -d ' ')
  if [ "$count" -eq 1 ]; then
    verdict="1 task has no evidence line"
    subject="1 '## Tasks' row has"
  else
    verdict="${count} tasks have no evidence line"
    subject="${count} '## Tasks' rows have"
  fi
  _eg_detail="canonical-sdlc: ${subject} no '- T<id>:' evidence line in '## SDLC State'.
Plan: $PLAN
Fix: add one line per row named below, each recording what proves that row, before committing.
$(printf '%s\n' "$ids" | sed -E 's/^/- /; s/$/:/')"
  # THE FIX FIELD IS SIX WORDS AND FORTY COLUMNS (refuse.sh's own self-check, ratified
  # constants this does not move), so the `## Tasks` half of the rule rides the detail
  # above rather than the one line: "per row" is the part a committer acts on.
  refuse exit2 commit "$verdict" "add one '- T<id>:' per row" "$_eg_detail"
}

validate_task_ledger() {
  local rows rc line id status rigor_cell ev eff addressed_found=0
  # THE ROWS COME FROM lib/units.sh (REQ-1e, AC-1e.1), header-keyed. The cells this
  # function wants are slot 1 `id`, slot 10 `status` and slot 3 — which the widened
  # wave schema spells `kind` and this task-scale registration table spells `rigor`,
  # one slot under two names (see units.sh's header). The read it replaces took
  # `$2`/`$6`/`$4` by COLUMN POSITION, which is the defect measured at
  # record/wave-11-lean-spine/step1-measure-1a-1e.md §4.3.
  #
  # THE TASK-SCALE ENUMS STAY HERE, NOT IN `units_validate` (T8 ruling, recorded in
  # record/wave-11-lean-spine/assumptions.md). `units_validate` enforces the
  # WAVE schema — ten columns, status `landed` — and this table is the five-column
  # `| id | intent | rigor | description | status |` ledger with `done` in it, which
  # REQ-1e does not widen. Delegating here would refuse every task-scale plan for
  # eight columns it was never asked to carry.
  #
  # A NON-ZERO rc IS AN ABSENT TABLE; zero rows is a PRESENT but empty one, which
  # falls through to the addressed-unit check at the bottom. The distinction is the
  # old `[ -z "$tasks" ]` test, kept: "no ledger yet" and "your row is missing" are
  # different findings.
  rows="$(units_rows "$PLAN")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ledger_shape_fail "this task-scale plan has no tasks table yet" "add a row per task" \
      "task-scale plan has no '## Tasks' registration section"
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(units_field "$line" id)
    # T-IDS ONLY, as the `| T[0-9]+` row grep this replaced demanded: a `## Tasks`
    # table may carry a legend or a non-unit row, and the evidence lines this
    # function looks up are `- T<n>:` by name.
    case "$id" in T[0-9]*) : ;; *) continue ;; esac
    status=$(units_field "$line" status)
    rigor_cell=$(units_field "$line" rigor)
    # status enum — routed through ledger_shape_fail (4/3): blocking on audited
    # plans, log-only otherwise (was unconditionally log-only in D12).
    case "$status" in
      pending|active|done|dropped) : ;;
      *) ledger_shape_fail "task ${id}'s status is unknown" "use pending, active, done or dropped" \
        "task ${id} has invalid status '${status:-empty}' (want pending|active|done|dropped)" ;;
    esac
    # Per-row INVALID rigor-cell guard (4/7): resolve this row's rigor cell and
    # block if it is off-enum. A malformed rigor cell makes the row's lane
    # indeterminate — a hard STRUCTURAL error, the exact sibling of the
    # status-enum check above (both are whole-value enum equality on a single
    # cell, validated per-row REGARDLESS of the row's status). So it blocks
    # UNIFORMLY: on ANY row (addressed or not; done, active, pending, dropped)
    # and at ANY frontmatter rigor — NOT routed through the audited-only
    # ledger_shape_fail. Placed here, before the evidence extraction and the
    # addressed-vs-other branching, so this ONE guard covers every row —
    # consolidating the former per-branch INVALID checks (4/1 addressed unit,
    # 4/6 non-addressed done) that left non-addressed active/pending rows
    # unchecked. `eff` is reused by both branches below (never INVALID past
    # here). Order vs the status-enum check: status first, then rigor — a row
    # with BOTH defects may block on either; this order is pinned for determinism.
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    eff=$(effective_row_rigor "$rigor_cell")
    if [ "$eff" = "INVALID" ]; then
      _eg_detail="canonical-sdlc task ${id} has an invalid rigor '${rigor_cell}' (want tested|peer-reviewed|audited).
Plan: $PLAN
Fix: set the '${id}' row's rigor cell to one of tested, peer-reviewed, audited before committing."
      refuse exit2 commit "that task's rigor value is not valid" "use tested, peer-reviewed or audited" "$_eg_detail"
    fi
    # Evidence line for this task in ## SDLC State (anchored so T2 never matches T20).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    ev=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:" | head -1 \
         | sed -E "s/^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    if [ "$id" = "$CURRENT" ]; then
      # THE ADDRESSED UNIT: the tested floor is BLOCKING (task 4/1).
      addressed_found=1
      if [ -z "$ev" ]; then
        # The addressed unit is short, which is what fires the arm; the refusal then
        # names EVERY row that is (AC-5.1), the addressed one among them.
        refuse_missing_evidence_lines "$rows"
      fi
      if is_placeholder_value "$ev"; then
        _eg_detail="canonical-sdlc task ${id} evidence line is a placeholder ('${ev}').
Plan: $PLAN
Fix: replace the '- ${id}:' placeholder with the actual evidence artifact before committing."
        refuse exit2 commit "that task's evidence line is a placeholder" "replace it with real evidence" "$_eg_detail"
      fi
      # 4/8: FLOOR check — a cell lowering this row below the frontmatter rigor
      # blocks unless the evidence line records a waiver. Runs after the
      # presence/placeholder blocks above (so those win) and before the lanes.
      enforce_rigor_floor "$id" "$eff" "$ev"
      # 4/2: rigor-keyed proof-shape/auditor/critic lanes on top of the tested
      # floor above. `eff` was resolved and INVALID-guarded at the per-row guard
      # (4/7); it names a valid lane here. Applies regardless of this row's own
      # status — the addressed unit is always in scope.
      # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
      apply_rigor_lanes "$id" "$status" "$eff" "$ev"
    else
      # Every OTHER row's presence/placeholder checks route through
      # ledger_shape_fail (4/3): blocking on audited plans, log-only otherwise.
      case "$status" in
        active|done)
          if [ -z "$ev" ]; then
            ledger_shape_fail "task ${id} is ${status} and shows no evidence" "record what proves it" \
              "task ${id} is ${status} but has no evidence on a '- ${id}:' line in ## SDLC State"
          elif is_placeholder_value "$ev"; then
            ledger_shape_fail "task ${id}'s evidence is still a placeholder" "record what actually ran" \
              "task ${id} is ${status} but its evidence is a placeholder ('${ev}')"
          elif [ "$status" = "done" ]; then
            # 4/2: a done row WITH real evidence is in scope for the
            # rigor-keyed lanes (BLOCKING) — a false-done claim at
            # peer-reviewed+ rigor, not a bookkeeping gap. A done row with
            # NO evidence line stays log-only above (4/3 territory). `eff` was
            # resolved and INVALID-guarded at the per-row guard (4/7 — was a
            # done-only guard under 4/6; now uniform across statuses), so it
            # names a valid lane here.
            # 4/8: FLOOR check first — a done row whose cell lowers it below the
            # frontmatter rigor blocks unless its evidence line records a waiver.
            enforce_rigor_floor "$id" "$eff" "$ev"
            apply_rigor_lanes "$id" "$status" "$eff" "$ev"
          fi
          ;;
      esac
    fi
  done <<< "$rows"
  # The addressed unit (current: T<n>) must have a row in ## Tasks (BLOCKING).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
  if [ "$addressed_found" -eq 0 ]; then
    _eg_detail="canonical-sdlc task ${CURRENT} has no row in the '## Tasks' registration table.
Plan: $PLAN
Fix: add a '| ${CURRENT} | <intent> | <rigor> | <description> | <status> |' row to '## Tasks' before committing."
    refuse exit2 commit "that task has no row in '## Tasks'" "add the task's registration row" "$_eg_detail"
  fi
  return 0
}

# Extract the ## SDLC State section (from its header up to the next ##
# header or EOF). Line endings normalized here too (normalize_newlines), for
# the same reason as FRONTMATTER above. Fence-aware (same idiom as matrix_section): lines inside
# ``` fenced code blocks are skipped, so a plan documenting the D12 task-scale
# schema in a fenced example — a `## SDLC State` heading with `current: T<n>` —
# does not shadow the REAL section (which would mis-parse `current:` and false-
# block). Fence state is tracked across the whole file so section detection
# stays fence-aware.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
SECTION=$(normalize_newlines "$PLAN" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { flag=1; next }
  /^## / { flag=0 }
  flag')

if [ -z "$SECTION" ]; then
  _eg_detail="canonical-sdlc plan file has an empty '## SDLC State' section.
Plan: $PLAN
Fix: populate the section with 'current: N' and per-step evidence lines."
  refuse exit2 commit "'## SDLC State' is empty" "add current: and the step lines" "$_eg_detail"
fi

# The `## Verification Matrix` section body (newline-normalized, like SECTION at
# the top of the hook — a separate awk pass over the whole plan). Lines inside
# ``` fenced code blocks are dropped so a jq/shell pipeline written in
# leading-pipe continuation style is never mistaken for a table row; every
# downstream matrix parse (rows, stack-health, false-green, AC blocks) reads
# this body, so scoping the fence-skip here covers all of them. Fence state
# is tracked across the whole file so section detection stays fence-aware.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
matrix_section() {
  normalize_newlines "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Verification Matrix/ { f=1; next }
    /^## / { f=0 }
    f'
}

# The indented evidence block under "<AC-id>:" within MATRIX (up to the next
# non-indented line). index()==1 anchors at line start without regex-escaping
# the AC id, so AC-1 never matches the AC-11 block.
#
# A markdown list leader before the header is tolerated: `- AC-1:` reads exactly
# like `AC-1:`. Without this, a list-shaped block extracted as EMPTY and every
# consumer below went silent at once — the provenance arm saw no citation, the
# per-tier key loop saw no keys and blocked a conformant plan, and both
# `waiver:` exemptions (per-tier and post-Verify CONFIRMED) lost their token.
# One extractor, four behaviors, so the leader was a whole-contract bypass.
# The strip runs on a COPY (`hdr`), which keeps two invariants: the terminator
# below still tests the RAW line, so a following list item still ends the
# previous block; and the index test still runs against a line that begins with
# the AC id, so AC-1 still does not match `- AC-11:`. Accepted: the three
# CommonMark bullet markers plus at least one space, flush left — `-AC-1:` is
# not a list item, and an INDENTED header is refused on purpose because the
# terminator could never end a block it introduced.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
matrix_block() {
  echo "$MATRIX" | awk -v ac="$1:" '
    { hdr = $0; sub(/^[-*+][[:space:]]+/, "", hdr) }
    index(hdr, ac)==1 {f=1; next}
    /^[^[:space:]]/ {f=0}
    f'
}

# ================================================== THE TWO STEP-4 ARMS (epic-22 K2, K2.5)
#
# Defined HERE, directly before `CURRENT` is parsed — earlier than a numbered-step-only
# wall would need to be. The reason is the task-scale branch a few lines below: epic-22
# K2.5 calls these same two arms from inside the `current: T<n>` branch, which used to
# `exit 0` before ever reaching them (they used to live between the matrix extractors and
# the pointer-step exit, reachable only by the numbered-step path). Moving the DEFINITIONS
# up costs nothing — `matrix_section`/`matrix_block` need only `$PLAN`, which is set long
# before this point — and it lets one pair of checks serve both scales instead of a second
# copy of either. The numbered-step CALL still runs in its original place, right before the
# pointer-step exit below; this is only the definitions moving.
#
# THE STEP NUMBER IS READ AS A NUMBER, ONCE. `CURRENT` reaches here as `4`, `8b`, `10` or a
# task-scale `T<n>`. Numbered steps are read digit-first, the leftmost run before any letter
# (`4`, `8b` → `8`); a value whose digits cannot be read leaves both arms unmeasured rather
# than refusing on a question they cannot ask — the fail direction every start-side
# ambiguity in this tree takes. Task-scale is the one case that is NOT "read the digits":
# `T1`'s leading `T` would strip to empty and read as unmeasured, which is exactly the gap
# K2.5 closes — a task-scale plan is always mid-execution, never mid-authoring, so ANY
# `current: T<n>` (n >= 1) reads as past Step 3 and both arms bind on it the same way they
# do from `current: 4` onward.
k2_step_num() {
  case "$CURRENT" in
    T[0-9]*) printf '4'; return ;;
  esac
  local n="${CURRENT%%[!0-9]*}"
  case "$n" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$n" ;; esac
}

# ---------- the approval arm (AC-K2.4, AC-K2.5, design decision 2) ----------
#
# WHAT `approved` BINDS. Step 3 ends at one approval checkpoint, and until this arm
# existed the user's word left no trace: a run could be building at Step 4 with nobody
# able to say whether the plan had ever been ratified, and the only backstop was the
# Patrol's below-Step-4 fill refusal, which asks a different question. Decision 2 settled
# the recording — on the user's LITERAL `approved` the orchestrator writes
#
#     approved-by: <user> <ISO-UTC> "<verbatim reply>"
#
# into `## SDLC State` — and this is the wall that makes its absence cost something.
# Silence, a question, or a partial reply is never transcribed as approval, so PRESENCE
# is the whole check: nothing here grades the quote, and nothing here can tell a
# transcription from an invention. What it can tell is that nobody wrote one down.
#
# INERT BELOW STEP 4, by construction and not by accident. Steps 0-3 are where the plan
# is authored, and the approval is asked for at the END of Step 3 — a wall there would
# refuse the very commit that writes the plan the user is about to approve.
#
# DURABLE FROM 4 ONWARD, the same shape the matrix prefix check has: deleting the line at
# Step 6 loses the same fact it would have lost at Step 4. AT TASK SCALE (K2.5) there is no
# "below Step 4" — `k2_step_num` reads every `current: T<n>` as past Step 3, so this arm is
# durable from a task-scale plan's first commit onward.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_approved_by() {
  local step approved
  step=$(k2_step_num)
  [ -n "$step" ] || return 0
  [ "$step" -ge 4 ] || return 0

  approved=$(echo "$SECTION" | grep -E '^[[:space:]]*approved-by[[:space:]]*:' | head -1 \
    | sed -E 's/^[[:space:]]*approved-by[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  [ -n "$approved" ] && return 0

  _eg_detail="canonical-sdlc step ${CURRENT} — '## SDLC State' carries no 'approved-by:' line; the Step-3 approval is what admits Step 4.
Plan: $PLAN
Fix: on the user's literal 'approved', record 'approved-by: <user> <ISO-UTC> \"<verbatim reply>\"' under '## SDLC State' — never on silence, a question, or a partial reply."
  refuse exit2 commit "'## SDLC State' has no 'approved-by:' line" "record the literal approval" "$_eg_detail"
}

# ---------- the fails-when arm (AC-K2.3, AC-K2.5) ----------
#
# AN EVAL WITH NO NAMEABLE FAILURE IS NOT AN EVAL. A matrix row that cannot say what
# planted defect it must go red on is a row that will be green whatever the code does,
# and the gate cannot tell the two apart at discharge time — which is the whole reason
# the column is authored at Step 2, in the spec's `## Eval design`, and merely RENDERED
# into the plan's matrix at Step 3. By Step 4 every AC block has one, or a step was
# skipped; so this arm is the receipt for that authoring order rather than a new demand.
# AT TASK SCALE (K2.5) the same receipt is owed from a plan's first `current: T<n>`
# commit — a task-scale plan carrying a `## Verification Matrix` is held to the identical
# standard as a numbered-step plan at `current: 4`+.
#
# IT JUDGES BLOCKS, NOT ROWS. A matrix row with no AC block underneath it is not a
# fails-when finding: there is no block to lack the key, and the per-tier evidence loop
# at the Verify gate is what owns that gap. Nor does a plan with no `## Verification
# Matrix` at all become one — a Step-4 plan may not have written the section yet, and
# demanding it here would be the Verify gate's demand moved four steps early.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_fails_when() {
  local step rows line ac block_txt fw
  step=$(k2_step_num)
  [ -n "$step" ] || return 0
  [ "$step" -ge 4 ] || return 0

  MATRIX=$(matrix_section)
  [ -n "$MATRIX" ] || return 0
  rows=$(echo "$MATRIX" | grep -E '^[[:space:]]*\|')
  [ -n "$rows" ] || return 0

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -qE '^[[:space:]]*\|[-|:[:space:]]*$' <<< "$line" && continue
    ac=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    [ "$ac" = "AC" ] && continue
    [ -n "$ac" ] || continue
    block_txt=$(matrix_block "$ac")
    [ -n "$block_txt" ] || continue
    fw=$(echo "$block_txt" | grep -E '^[[:space:]]*fails-when[[:space:]]*:' | head -1 \
      | sed -E 's/^[[:space:]]*fails-when[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
    [ -n "$fw" ] && continue
    _eg_detail="canonical-sdlc step ${CURRENT} — matrix row '${ac}' names no 'fails-when:'; an eval with no nameable failure is not an eval.
Plan: $PLAN
Fix: add 'fails-when: <the planted defect this eval must go red on>' to the '${ac}:' block — it is authored in the spec's '## Eval design' and rendered here."
    refuse exit2 commit "that matrix row names no 'fails-when:'" "add a 'fails-when:' line" "$_eg_detail"
  done <<< "$rows"
  return 0
}

# ---------- the prototype no-row arm (AC-K4.2, epic-22 K4 + K2.5) ----------
#
# A PROTOTYPE NEVER DISCHARGES A MATRIX ROW (design decision D7). Its output is a
# design ruling written back to the spec, not a shipped behavior — nothing about a
# throwaway is provable by an eval, so a `kind: prototype` task that also owns a
# Verification Matrix AC block is a category error the gate can catch structurally:
# the `## Tasks` table names which tasks are prototypes, and each AC block's own
# `task:` field names which task discharges it. Reads the matrix the same way
# `validate_fails_when` does — rows first, then the block underneath each row — so
# an AC id absent from the row table (and therefore from the matrix entirely)
# cannot be judged here either.
#
# THE FOURTH READER REQ-1e RE-POINTS (measure §5, blocker 4). It used to read a
# section of its own, under the heading this wave retired, by COLUMN POSITION: `$2`
# for the number and `$4` for the kind. The section is `## Tasks` now, the rows come
# from lib/units.sh header-keyed, the number is an id, and the matrix field it
# cross-references is `task:`.
#
# INERT BELOW STEP 4 (numbered) OR BELOW `current: T<n>` (task-scale, epic-22 K2.5),
# same reasoning as the two arms above: the Tasks table and the Verification Matrix
# are both Step-3 artifacts, not necessarily complete before then, and a task-scale
# plan carries no `kind` cell at all — `units_field ... kind` reads empty and this
# is a no-op.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_prototype_no_matrix_row() {
  local step task_rows proto_ids line id rows ac block_txt ac_task n
  step=$(k2_step_num)
  [ -n "$step" ] || return 0
  [ "$step" -ge 4 ] || return 0

  task_rows="$(units_rows "$PLAN")" || return 0
  [ -n "$task_rows" ] || return 0

  proto_ids=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$(units_field "$line" kind)" = "prototype" ] || continue
    id=$(units_field "$line" id)
    [ -n "$id" ] || continue
    proto_ids="$proto_ids $id"
  done <<< "$task_rows"
  [ -n "$proto_ids" ] || return 0

  MATRIX=$(matrix_section)
  [ -n "$MATRIX" ] || return 0
  rows=$(echo "$MATRIX" | grep -E '^[[:space:]]*\|')
  [ -n "$rows" ] || return 0

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -qE '^[[:space:]]*\|[-|:[:space:]]*$' <<< "$line" && continue
    ac=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    [ "$ac" = "AC" ] && continue
    [ -n "$ac" ] || continue
    block_txt=$(matrix_block "$ac")
    [ -n "$block_txt" ] || continue
    ac_task=$(echo "$block_txt" | grep -E '^[[:space:]]*task[[:space:]]*:' | head -1 \
      | sed -E 's/^[[:space:]]*task[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
    [ -n "$ac_task" ] || continue
    for n in $proto_ids; do
      [ "$ac_task" = "$n" ] || continue
      _eg_detail="canonical-sdlc step ${CURRENT} — matrix row '${ac}' names 'task: ${ac_task}', a 'kind: prototype' row in '## Tasks'; a prototype ships nothing and never discharges a matrix row.
Plan: $PLAN
Fix: remove the '${ac}:' block, or repoint its 'task:' to the build task that cites the prototype's ruling — the prototype's own output is a design decision written to the spec, never a matrix discharge."
      refuse exit2 commit "that row's task ships nothing" "point it at a shipping task" "$_eg_detail"
    done
  done <<< "$rows"
  return 0
}

# Parse current step. Accepts integers (1-13) and the 8b adversarial
# critic step.
CURRENT=$(echo "$SECTION" \
          | grep -E '^[[:space:]]*current[[:space:]]*:' \
          | head -1 \
          | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
          | tr -d '[:space:]')

# THE VALUE THE PLAN DECLARED, kept before anything substitutes a subject (wave-18
# REQ-1, D1). Two arms below replace `CURRENT` for the length of one commit — a row's
# own step, and a task row's id — and both are answers to "whose obligations does this
# commit discharge". `_eg_verdicts_owed` asks a different question, "has this RUN reached
# the step that produces an auditor and a critic", and it must read the run's own word.
_EG_DECLARED_CURRENT="$CURRENT"

# Task-scale plans address a ledger TASK, not a numbered step:
# `current: T<n>` with evidence on `- T<n>:` lines (no `Step N:` line). Validate
# the ledger (log-only, D12/D14), then — epic-22 K2.5 — run the SAME three Step-4
# arms a numbered-step plan runs below: a task-scale plan is always mid-execution,
# never mid-authoring, so `current: T<n>` (any n >= 1) reads as past Step 3 and the
# approved-by / fails-when / prototype-no-row walls bind on it exactly as they do
# from `current: 4` onward (`k2_step_num`, above, recognises the T-format
# directly). A `current: T<n>` on a non-task plan is NOT accepted here; it falls
# through to the numeric check below and blocks (T-format is scale: task only).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
if grep -qE '^T[0-9]+$' <<< "$CURRENT" && [ "$SCALE" = "task" ]; then
  validate_task_ledger
  validate_approved_by
  validate_fails_when
  validate_prototype_no_matrix_row
  exit 0
fi

if [ -z "$CURRENT" ] || ! grep -qE '^[0-9]+[ab]?$' <<< "$CURRENT"; then
  _eg_detail="canonical-sdlc plan file's '## SDLC State' section is missing a valid 'current: N' line.
Plan: $PLAN
Fix: add a line like 'current: 5' (or 'current: 8b') before committing."
  refuse exit2 commit "'## SDLC State' has no valid 'current:' line" "add a 'current: N' line" "$_eg_detail"
fi

# ---------- THE RUN PREDICATE (AC-7, AC-8): no open run, nothing to gate ----------
#
# The plan is now known to be well-formed — it carries an unfenced `## SDLC State`
# and a `current:` this gate recognises. Whether there is a RUN is a different
# question, and it is the one every always-on hook asks before doing its own work:
# `active_run` is true while `current:` is below 9, or 9 with no `delivered:` Step-9
# line, and the plan carries no `abandoned:` frontmatter line.
#
# IT SITS HERE AND NOT EARLIER, and the order is the whole point. Everything above
# is the gate's judgment about the PLAN — a misplaced plan, a malformed `current:`,
# a task ledger — and those refusals are owed whether or not a wave is live: a plan
# that lies is a defect in every state. Everything below is enforcement against a
# STEP, which is owed only while the run is open. Move this line up and a project
# whose plan is merely malformed goes ungated; move it down and a shipped wave keeps
# refusing commits forever.
#
# THE VERDICT IS THE SESSION'S, taken at the top with the plan it names
# (wave-session-bound-run, AC-1/AC-3/AC-6): a bound session enforces against its OWN open
# run and against nothing else, and `bound-closed` — its plan delivered, abandoned or gone
# — takes this same exit, the engaged-with-no-run branch, rather than resolving a second
# time and landing on somebody else's wave. The unbound arm still asks `active_run` here,
# in this position, exactly as it did before the wave: that is AC-3's "behaves exactly as
# today", kept by running the old predicate rather than by trusting a new one to agree.
case "$EG_VERDICT" in
  bound-open)   : ;;
  bound-closed) exit 0 ;;
  *)            active_run "$BIONIC_ROOT" >/dev/null || exit 0 ;;
esac

# ---------- THE ROW'S STEP IS THE JUDGMENT (wave-14 REQ-2, ADR-027) ----------
#
# WHAT THIS FIXES. Everything above judges the commit against the run's single `current:`,
# which was true while one writer worked at a time. Parallel writers broke it: several tasks
# are in flight at once, each at its own step, each in its own worktree, and a Step-4 writer
# committing while the run sits at Step 5 was refused for Step-5 evidence that cannot exist
# yet. In wave-13 the orchestrator regressed `current:` BY HAND to land such a commit
# (A-orch-43) — a run-wide fact edited to clear one writer, which is the damage this arm
# removes.
#
# THE REGISTER IS THE `## Tasks` TABLE (ADR-027). The dispatcher writes the tree it created
# into the row's `worktree` cell at the moment it creates it, so the binding from a checkout
# to the task that owns it lives in the one place that already knows the task's step and
# status, readable by `lib/units.sh`, which every other consumer already parses the plan
# through.
#
# FOUR CASES, AND THE THREE THAT ARE NOT THE FIRST ARE WHY THIS IS SAFE:
#   · the commit is made from a linked worktree a row owns, at a step BEHIND `current:`
#     → judge at the row's step (the `Step N:` lookup below, the placeholder ban and
#       `dispatch` all run against it);
#   · that row's step is AHEAD of `current:` → refuse, naming the row and both steps: the
#     register says nobody should be committing from that tree yet;
#   · a linked worktree no row owns → judge at `current:`, today's behaviour exactly, plus
#     one line on stderr naming the tree, so a writer whose row was never ledgered learns it
#     from the wall rather than from the verdict;
#   · the MAIN checkout → not one byte of this block runs.
#
# IT SITS BELOW THE RUN PREDICATE on purpose. A closed run gates nothing, and a refusal owed
# to a register is owed only while there is a run to be at a step of.
#
# WHY NOT `BIONIC_WORKTREE` ALONE (A-T2.5, T2's own seam). `lib/root.sh` publishes it, but
# for the cwd the CONTEXT LADDER took — and rung 1 is `CLAUDE_PROJECT_DIR`, which on a real
# dispatched writer names the session's project, the MAIN checkout. The variable then reads
# empty while the writer is standing in a worktree. The honest signal is the payload's own
# `.cwd`, already cached by `_bionic_jq_fill`, so reading it costs no fork; `BIONIC_WORKTREE`
# is taken as a fast path only where it cannot disagree — when the ladder's cwd and the
# payload's cwd are the same directory.
#
# ONE `git` CALL, AND ONLY WHERE A COMMIT IS BEING JUDGED (REQ-4, AC-4.3 caps ROOT
# RESOLUTION at one ask per hook invocation; this is not that ask). A linked worktree's
# `.git` is a FILE holding one `gitdir:` line, and reading it is one bash `read` — but a
# file is text, and wave-14's security review drove a hand-written one that named a plan
# row's tree, pointed at a path no repository has ever had, and lowered `current:` for a
# commit landing in the main checkout. So the read stays as the PRE-FILTER it is good at,
# where it costs the main-root path nothing, and git answers the question the row lookup
# keys on (`_eg_git_wt_name`). Every non-commit Bash event still leaves this file having
# forked git exactly once, for the root walk, because none of them reach this block:
# `_eg_body` exits at IS_COMMIT long before it.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]

# _eg_wt_name <dir> -> the LINKED WORKTREE's name for that directory, empty otherwise.
#
# Walks up to the nearest `.git` entry, exactly as git does. A DIRECTORY there is an ordinary
# checkout (the main one, or a standalone clone) and answers empty — that is the main-root
# case, and it is the one that must cost nothing and change nothing. A FILE there is a linked
# worktree, a submodule, or something else entirely, so the `gitdir:` target is required to
# carry a `/worktrees/` segment before its basename is believed: a submodule's
# `<super>/.git/modules/<name>` is not a worktree and must not be read as one.
#
# IT IS A PRE-FILTER AND NOT THE ANSWER (wave-14 T24). Its whole value is what it rules out
# for the price of one `read` and no fork — the main checkout, every submodule, every
# ordinary directory — which is what keeps a main-root commit free. What it CANNOT do is
# establish that a directory is a worktree, or that it is THIS repository's: the file it
# reads is ordinary text and anyone who can write the command can write the file. A name it
# answers is a candidate; `_eg_git_wt_name` turns a candidate into an answer.
_eg_wt_name() {
  local _d="${1:-}" _g
  case "$_d" in /*) : ;; *) return 0 ;; esac
  while [ -n "$_d" ] && [ "$_d" != "/" ]; do
    if [ -d "$_d/.git" ]; then
      return 0
    elif [ -f "$_d/.git" ]; then
      IFS= read -r _g < "$_d/.git" 2>/dev/null || return 0
      case "$_g" in gitdir:*) _g="${_g#gitdir:}" ;; *) return 0 ;; esac
      while [ "${_g# }" != "$_g" ]; do _g="${_g# }"; done
      _g="${_g%$'\r'}"
      while [ "${_g% }" != "$_g" ]; do _g="${_g% }"; done
      _g="${_g%/}"
      case "$_g" in */worktrees/*) printf '%s' "${_g##*/}" ;; esac
      return 0
    fi
    _d="${_d%/*}"
  done
  return 0
}

# _eg_git_wt_name <dir> -> sets _EG_GITWT to the name GIT gives that directory as a linked
# worktree OF THIS REPOSITORY, empty for everything else. One `git` fork, commit path only.
#
# THE DEFECT IT CLOSES (security 1a, HIGH). The arm judged a commit at a plan row's step,
# and it picked the row from a name it took out of a `.git` FILE — so the OBJECT of the
# judgement (a commit, landing in some tree) and its SUBJECT (a row, chosen from a string)
# were two different things and nothing reconciled them. A directory holding the single line
# `gitdir: /nowhere/at/all/.git/worktrees/14-T6` was accepted as row T6's tree although git
# never made it, the target does not exist, and the directory need not even be inside the
# repository. Against the live plan that lowered `current:` from 5 to 4 for a MAIN-checkout
# commit, and step 4 takes the gate's early exit, so the entire Step-5 verify shape was
# never reached — with no artifact left behind: the plan still read `current: 5`.
#
# WHAT GIT IS ASKED, AND WHY THOSE TWO PATHS ANSWER IT:
#   · `--git-common-dir` is the repository every worktree of it shares. It must be THIS
#     repository's, or the tree belongs to another repository (or to none) and this plan's
#     register has nothing to say about it;
#   · `--git-dir` inside a linked worktree is `<main>/.git/worktrees/<name>` — so it differs
#     from the common dir, carries a `/worktrees/` segment, and its basename IS the name
#     `git worktree list` prints and `spawn-worktree.sh` created the tree under. That
#     basename, not the file's, is what the row lookup keys on.
# One line back is not two answers: it would read as "git dir equals common dir" and demote
# a linked worktree to an ordinary checkout, so it is declined instead.
#
# THE MAIN ROOT'S COMMON DIR COSTS NO SECOND FORK in the ordinary topology — `$BIONIC_ROOT/.git`
# is a directory in every checkout that is not itself a linked worktree, and the root walk
# already maps a worktree cwd back to the main root. The `else` exists for the topology where
# it is not (a project root that is itself a linked worktree) and is the only path in this
# file that can fork git twice. The comparison falls back to `-ef` — same device, same inode,
# a shell builtin and no fork — so a symlinked root, a `//` or a `..` in either path compares
# as the directory it is rather than as the string it was spelled with.
#
# EVERY FAILURE IS A DECLINE, never a lowered step: no git, an older git with no
# `--path-format`, a deleted directory, a bare repository. The caller then judges at
# `current:` and says so, which is what the gate did before this register existed.
#
# WITH ONE ANSWER THAT IS NOT A FAILURE (wave-17 REQ-4, T1; bug 7). Another repository's
# linked worktree used to leave by the same `return 0` as all of those, and the caller could
# not tell the two apart: a FORGED `.git` file is a directory git refused to place at all,
# while a foreign tree is one git placed precisely — in a repository this plan's register has
# nothing to say about. Both arrived as an empty `_EG_GITWT`, and the second was then judged
# by this run's step arms, which is the defect. So this one path returns **4** and publishes
# the common dir git named in `_EG_GITWT_FOREIGN`: the fact is already in hand at the
# comparison below and nothing new is fetched for it (the D11 freeze,
# .claude/rules/hook-authoring.md). `_EG_GITWT` stays EMPTY on that path, so every reader
# that only asks "is this a tree of mine" keeps today's answer; only a caller that reads the
# status learns the difference.
_EG_GITWT=""
_EG_GITWT_FOREIGN=""
_eg_git_wt_name() {
  local _d="${1:-}" _both _common _gitdir _main
  _EG_GITWT=""; _EG_GITWT_FOREIGN=""
  case "$_d" in /*) : ;; *) return 0 ;; esac
  _both="$(git -C "$_d" rev-parse --path-format=absolute --git-common-dir --git-dir 2>/dev/null)" || return 0
  _common="${_both%%$'\n'*}"
  _gitdir="${_both#*$'\n'}"
  [ "$_common" != "$_both" ] || return 0
  [ -n "$_common" ] && [ -n "$_gitdir" ] || return 0
  [ "$_common" != "$_gitdir" ] || return 0
  case "$_gitdir" in */worktrees/*) : ;; *) return 0 ;; esac
  if [ -d "$BIONIC_ROOT/.git" ]; then
    _main="$BIONIC_ROOT/.git"
  else
    _main="$(git -C "$BIONIC_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
    _main="${_main%%$'\n'*}"
  fi
  [ -n "$_main" ] || return 0
  if [ "$_common" != "$_main" ] && ! [ "$_common" -ef "$_main" ]; then
    # GIT ANSWERED, AND IT ANSWERED SOMEWHERE ELSE. Everything above has already established
    # that this directory IS a linked worktree — git resolved it, the git dir differs from
    # the common dir and carries a `/worktrees/` segment — so the only thing left in doubt
    # was whose, and this line is where that is settled. Rc 4, not an empty name, because
    # "placed in another repository" and "not placed at all" are different facts and the
    # caller acts differently on them.
    _EG_GITWT_FOREIGN="$_common"
    return 4
  fi
  _EG_GITWT="${_gitdir##*/}"
  return 0
}

# _eg_row_for_worktree <name> -> sets _EG_ROW to "<id><TAB><step><TAB><status><TAB><kind>" for
# the ONE `## Tasks` row
# whose `worktree` cell names that tree, and _EG_ROW_DUP to the ids when more than one does.
# Returns 1 for "this plan has no register", 3 for "the register is ambiguous", 0 otherwise.
#
# THE CELL IS COMPARED BY BASENAME on the row's side, so a plan that spells the tree as a
# path (`.worktrees/14-T3`) or as its branch (`wt/14-T3`) still resolves to the tree git
# named `14-T3`. The comparison is never loosened on the DERIVED side: that value is git's
# own, and matching it loosely is how a commit reaches another task's step.
#
# AND THAT LOOSENING IS EXACTLY WHY A COLLISION IS POSSIBLE (correctness F4, wave-14 T24).
# `wt/14-T6` and `.worktrees/14-T6` are different cells with one basename, the spec's domain
# model states "a worktree names at most one unit" as an invariant, and `units_validate`
# deliberately declines to enforce it (units.sh's own note) — so the register CAN say two
# things and the plan is the only place that can be repaired. Taking the first row in table
# order picked a step by the accident of write order and said nothing: if the second row were
# the real owner and it sat AHEAD of the run, the refusal AC-2.3 exists for would never fire.
# A wall that cannot tell which row owns the tree does not choose one; it declines to the
# run's own `current:` and names both rows so the table can be fixed.
#
# IT ASSIGNS RATHER THAN PRINTS for the reason `_eg_commit_cwd` does: the collision is a
# second answer, and a command substitution would strand it in a subshell.
_eg_row_for_worktree() {
  local _want="${1:-}" _rows _line _cell _id
  _EG_ROW=""; _EG_ROW_DUP=""; _EG_ROW_COLLIDED=0
  [ -n "$_want" ] || return 0
  _rows="$(units_rows "$PLAN")" || return 1
  [ -n "$_rows" ] || return 0
  # THE TWIN OF stop.sh's `_lg_row_for_tree` FOLD (L1, wave-17 T41, critic C14; both sides
  # T50, T47's floor RED): that function folds both sides and this one now does too, for
  # the reason case-folding always needs both sides folded — `$_want` is the literal
  # basename git gave the tree, and that basename carries the tree's REAL case (a real
  # dispatch tree is always `<NN>-T<n>`, capital T), while the cell is authored text that
  # can drift in case either direction. Folding only the cell does not make the compare
  # case-insensitive; it makes it fail on every mixed-case tree, including an EXACT match,
  # because a lowercased cell can never equal an unlowercased `$_want`. Both walls must
  # fold the same way to keep one plan from giving two answers for which row owns a tree.
  _want="$(printf '%s' "$_want" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _cell="$(units_field "$_line" worktree)"
    [ -n "$_cell" ] || continue
    _cell="${_cell%/}"
    [ "$(printf '%s' "${_cell##*/}" | tr '[:upper:]' '[:lower:]')" = "$_want" ] || continue
    _id="$(units_field "$_line" id)"
    if [ -z "$_EG_ROW" ]; then
      # THREE CELLS, TAB-SEPARATED: id, step, status (wave-17 REQ-1, D1, ADR-031). The
      # status cell has been validated since wave-11 and read by nothing; it is what says
      # whether a commit out of this tree discharges the obligations of the TASK or of the
      # RUN, and the fork below cannot ask that question of a value it was never handed.
      # One more cell of a table this function already parses — no new fact is fetched
      # (the D11 freeze, .claude/rules/hook-authoring.md).
      # AND A FOURTH, THE KIND (wave-20 REQ-5, Δ6). A row ahead of the run is judged by its
      # task arms when a writer is at work in it — unless it is a gate act (`integrate`,
      # `close`), whose commit must wait for the run to reach its step — so the fork needs
      # the row's kind as well as its status.
      _EG_ROW="$_id	$(units_field "$_line" step)	$(units_field "$_line" status)	$(units_field "$_line" kind)"
      _EG_ROW_DUP="$_id"
    else
      _EG_ROW_DUP="$_EG_ROW_DUP, $_id"
      _EG_ROW_COLLIDED=1
    fi
  done <<< "$_rows"
  if [ "${_EG_ROW_COLLIDED:-0}" = 1 ]; then
    _EG_ROW=""
    return 3
  fi
  _EG_ROW_DUP=""
  return 0
}

_EG_WT=""
_EG_SUBSTITUTED=0    # set by BOTH substitution forks below (step-below, active-status); read at the pointer-step exit (D7)
# _EG_CWD, _EG_CWD_SRC and _EG_CDS were set by `_eg_commit_cwd` at the jurisdiction arm, above
# the plan read (wave-19 REQ-9); the command and the payload have not changed since.

# WHICH DIRECTORY DOES THIS COMMIT RUN IN? (critic issue 1; wave-17 REQ-3, D4.) When the
# command text names a second directory before the commit, no reading of the text answers
# that, so the arm refuses and names both rather than judging at the first one.
#
# ASKED BEFORE ANY DIRECTORY IS RESOLVED, AND THAT IS THE REPAIR (bug 6). The arm used to sit
# inside the `if [ -n "$_EG_WT" ]` block below, so it was reached only when git had already
# confirmed the FIRST directory as a linked worktree of this repository. Every other first
# directory — the main checkout, a record/ directory under it, /tmp — left `_EG_WT` empty,
# skipped the whole block, and the commit was judged at the run's `current:` with nothing said
# about the second `cd`: fail-open for `cd <records-dir>; …; cd <tree> && git commit`, which is
# the shape a consumer actually wrote. THE AMBIGUITY IS THE COMMAND'S PROPERTY, not the first
# directory's: a `;` runs the rest wherever the shell is standing, a failed `cd` leaves it
# where it was, and a `&&` only looks decisive. So the question is asked of the text, here,
# where it costs no `read` and no fork and reaches every first directory alike.
#
# `_EG_CDS` IS SET ONLY BY THE LEADING-`cd` BRANCH of `_eg_commit_cwd` — a `git -C <dir>`
# commit never consults it — so the `_EG_CWD_SRC` test names the branch that answered rather
# than narrowing the arm.
#
# TWO TOKENS ARE NOT TWO DIRECTORIES (critic C3). `cd X && cd X` and `cd X && cd .` name one
# directory twice, and the arm used to refuse them with a sentence that answered its own
# complaint. `_eg_cd_one_dir` compares the RESOLVED targets — the values this arm already
# prints — and only a real difference is an ambiguity.
#
# AND IT COMPARES EVERY ONE OF THEM (W6). The reader behind C3's fix stopped at the first
# `cd` after the leading one, so `cd X && cd X && cd Y && git commit` was allowed and judged
# at X while the shell commits in Y: two matching targets answered for a command that goes
# on to name a third. `_eg_cd_one_dir` now walks the whole list and the arm fires on the
# FIRST target that disagrees with the leading directory, which is the pair the detail names.
# A `git -C <dir> commit` still overrides all of it — branch (1) answers before this list is
# ever built, which is why the Fix line below can offer that spelling as the way out.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
if [ "$_EG_CWD_SRC" = "cd" ] && [ -n "$_EG_CDS" ] && ! _eg_cd_one_dir; then
  _eg_detail="canonical-sdlc cannot tell which directory this commit runs in: the command changes into '${_EG_CWD}' and then into '${_EG_CD_DIFF}' before committing, and a commit is judged at the step of the '## Tasks' row that owns the tree it lands in.
Plan: $PLAN
Fix: commit from one directory — split the command in two, or spell it 'git -C <dir> commit' so git names the tree itself."
  refuse exit2 commit "two directories are named before the commit" "name one directory" "$_eg_detail"
fi

if [ -n "$BIONIC_WORKTREE" ] && [ "$_EG_CWD" = "$BIONIC_CWD" ]; then
  _EG_WT="$BIONIC_WORKTREE"          # the ladder already asked GIT about this very directory
elif [ -n "$_EG_CWD" ] && [ -n "$(_eg_wt_name "$_EG_CWD")" ]; then
  # THE FILE READ SCREENS, GIT ANSWERS (wave-14 T24, security 1a). `_eg_wt_name` has said the
  # directory MIGHT be a linked worktree, for the price of one `read` and no fork; every
  # main-root commit and every ordinary directory has already left without paying for a git
  # call. What remains is the small set worth one fork, and git decides it.
  _eg_git_wt_name "$_EG_CWD"; _EG_GITWT_RC=$?
  _EG_WT="$_EG_GITWT"
  if [ "$_EG_GITWT_RC" -eq 4 ]; then
    # OUTSIDE THE RUN, NOT BEHIND IT (wave-17 REQ-4, T1; bug 7). Git placed this tree in
    # another repository, so nothing in THIS plan describes the work it holds: its `## Tasks`
    # register cannot name the tree, its `current:` is not the step that commit is part of,
    # and its Step-5 floor is a floor that commit has no part in producing. Until this line
    # the gate said all of that out loud — the announce below has named the boundary since
    # wave-14 — and then judged the commit at `current:` anyway, refusing another
    # repository's work for this run's evidence. A wall that has just admitted it cannot
    # place a commit does not go on to sentence it.
    #
    # EXEMPTION, NEVER ADOPTION. The commit is not matched to a row, not judged at a lowered
    # step and not allowed by any arm — this gate simply has no jurisdiction and says so.
    # Matching a foreign tree against this plan's rows is out of scope by the charter, and
    # the note at `_eg_row_for_worktree` says why: loose matching on the derived side is how
    # a commit reaches another task's step.
    #
    # AND IT EXEMPTS THIS GATE ALONE. The `exit 0` leaves `_eg_body`, which runs in
    # `wall_evidence_gate`'s subshell; the walls folded beside it in hooks/bash-walls.sh —
    # protect-main, protect-database, farm-out, the background-suite guard — never see it and
    # keep their verdicts, which is what 25g(q) pins.
    #
    # SHADOWED SINCE wave-19 REQ-9. The jurisdiction arm above the plan read asks the same
    # common-dir question of every commit and exits first for another repository's tree, so
    # this line is reached only if git answers there and not here; it stays as the backstop
    # until a later wave retires it with its pins (T6 carry-over).
    printf "evidence-gate: %s is a linked worktree of another repository (%s) — this run's step arms do not apply\n" \
      "$_EG_CWD" "$_EG_GITWT_FOREIGN" >&2
    exit 0
  fi
  if [ -z "$_EG_WT" ]; then
    # NOT SILENCE. A `.git` file that names a worktree git does not know is an anomaly
    # wherever it came from — a moved tree, a forged one, or one whose target is gone — and
    # the reader needs to know the register was not consulted for this commit. A tree of
    # another repository no longer arrives here: git placed it, and it left above.
    printf 'evidence-gate: %s is not a linked worktree of this repository — judging at current: %s\n' \
      "$_EG_CWD" "$CURRENT" >&2
  fi
fi

if [ -n "$_EG_WT" ]; then
  # A plan with NO `## Tasks` table has no register, and there is nothing to say about a tree
  # it does not claim to track — `_eg_row_for_worktree` returns 1 for that, and this arm stays
  # silent, which is what keeps a solo-writer project's worktree commits byte-identical to
  # today's.
  _eg_row_for_worktree "$_EG_WT"; _EG_REG=$?
  if [ "$_EG_REG" -eq 3 ]; then
    printf 'evidence-gate: worktree %s is named by more than one ## Tasks row (%s) — judging at current: %s\n' \
      "$_EG_WT" "$_EG_ROW_DUP" "$CURRENT" >&2
  elif [ "$_EG_REG" -eq 0 ] && [ -z "$_EG_ROW" ]; then
    # AC-3.2: "no row names this tree" and "this table has no `worktree` column" are two
    # different facts and the lead-in used to print the first for both. `units_field <row>
    # worktree` reads slot 11, which a header without the column leaves EMPTY on every row,
    # so the loop above skipped every row and landed here — on a table that never claimed
    # to track trees (research R2 row 6a). `units_has_column` is the discriminator, and the
    # shape fault prints instead, from plan_bring_forward or from units_validate's own arm.
    if units_has_column "$PLAN" worktree; then
      printf 'evidence-gate: no ## Tasks row names worktree %s — judging at current: %s\n' \
        "$_EG_WT" "$CURRENT" >&2
    fi
  elif [ -n "$_EG_ROW" ]; then
    _EG_RID="${_EG_ROW%%	*}"
    _EG_RSTEP="${_EG_ROW#*	}"
    _EG_RSTATUS="${_EG_RSTEP#*	}"   # third field — empty on a table whose rows are short
    _EG_RSTEP="${_EG_RSTEP%%	*}"
    _EG_RKIND="${_EG_RSTATUS#*	}"   # fourth field (wave-20 Δ6)
    _EG_RSTATUS="${_EG_RSTATUS%%	*}"
    _EG_CURNUM="${CURRENT%[ab]}"
    case "$_EG_RSTEP" in
      ''|*[!0-9]*)
        # A TASK-SCALE TABLE HAS NO STEP CELL, AND THAT IS NOT AN UNUSABLE ONE (wave-18
        # REQ-11, D3, ADR-033). The six-column task ledger is `id | intent | rigor |
        # description | status | worktree`: there is no `step` column to read, so every row
        # arrived here with an empty cell, this arm decided nothing, and a commit from a
        # row's own tree was judged by the RUN's numbered-step block — a fixup writer at
        # `current: 5` refused for a Verify floor its own task exists to produce, which a
        # consumer answered by hand-writing a mid-discharge Step-5 block. ADR-031's rule is
        # not wave-only: a row's tree is judged by its row at task scale too. The arms are
        # the SAME four the `current: T<n>` early exit runs above, reached by naming the row
        # as the addressed unit — no second arm table, for the reason `CURRENT=4` is spelled
        # that way at the wave fork below.
        #
        # THE DISCRIMINATOR IS THE TABLE'S HEADER, not the empty cell: `units_has_column`
        # separates "this table never had a step column" from "this row's step cell is
        # blank or malformed", which is a shape fault `units_validate` reports at the step
        # that writes the plan and which keeps today's silence here. `scale: task` is asked
        # too — a wave table missing its step column is a broken wave table, not a task
        # ledger, and judging it by task arms would answer a shape fault with a verdict.
        if [ "$SCALE" = "task" ] && ! units_has_column "$PLAN" step; then
          # THE NOTE IS MANDATORY, for the reason the wave fork's is: this is a wall judging
          # a commit by something other than the run's declared `current:`, and it names the
          # ROW, because the row is the subject. Printed before the substitution, so
          # `current:` reads as the run declared it.
          printf "evidence-gate: judged by row %s's task arms (run at current: %s)\n" \
            "$_EG_RID" "$CURRENT" >&2
          CURRENT="$_EG_RID"
          validate_task_ledger
          validate_approved_by
          validate_fails_when
          validate_prototype_no_matrix_row
          exit 0
        fi
        : ;;
      *)
        if [ "$_EG_RSTEP" -lt "$_EG_CURNUM" ] 2>/dev/null; then
          # THE ALLOW PATH SPEAKS TOO (architecture review §4.1). Until this line the gate
          # announced the case where it DECLINED to use the register and went silent on the
          # case where it used it — so the only place in the fleet where a wall substitutes a
          # different value for the run's declared `current:` was the one place with no record
          # of having done so, and the operator who cannot explain why a commit passed had the
          # same two choices as the one wave-13's A-orch-43 incident left: read the source, or
          # edit the plan. Printed BEFORE the substitution, so the line names the step the run
          # declared. Where the row's step EQUALS `current:` nothing was substituted and
          # nothing is printed — that is the common case and it stays byte-identical.
          printf "evidence-gate: judged at row %s's step %s (run at current: %s)\n" \
            "$_EG_RID" "$_EG_RSTEP" "$CURRENT" >&2
          CURRENT="$_EG_RSTEP"
          # A SUBSTITUTED STEP IS NOT A POINTER STEP HERE EITHER (critic C1; wave-18 REQ-11,
          # D7). This arm substitutes `CURRENT` exactly as the `active`-status arm below does,
          # and D7's rule is about "a substituted step", not about which of the two forks did
          # the substituting — so it is flagged the same way, guarded the same way (only at
          # step 4, the one pointer step the substitution can land on; every other substituted
          # step stays byte-identical), for the pointer exit a few hundred lines below to read.
          [ "$_EG_RSTEP" = 4 ] && _EG_SUBSTITUTED=1
        elif [ "$_EG_RSTEP" -gt "$_EG_CURNUM" ] 2>/dev/null \
             && [ "$_EG_RSTATUS" = "active" ] && [ "$_EG_CURNUM" -ge 4 ] 2>/dev/null \
             && [ "$_EG_RKIND" != "integrate" ] && [ "$_EG_RKIND" != "close" ]; then
          # A WORK ROW AHEAD OF THE RUN, WITH A WRITER AT WORK IN IT (wave-20 REQ-5, AC-5.1;
          # Δ1, Δ6; ADR-036). Readiness is the prerequisite graph now: a Step-6 review whose
          # deps have landed IS dispatched while the run sits at Step 5, and the refusal below
          # would leave its writer finished and unable to commit — the fill's own dead end.
          # So an `active` row ahead of `current:` is judged exactly as an in-step `active`
          # row is, by the TASK arms (`CURRENT=4`, the note, the substitution flag), for the
          # reasons that arm's docblock gives below.
          #
          # THREE THINGS KEEP THE REFUSAL, and each is the case the refusal was right about:
          # a row that is NOT `active` (no writer was dispatched into that tree, so nobody
          # should be committing from it); an `integrate` or `close` row (a gate act, whose
          # real prerequisite is a gate passing — the merge must not commit before Verify
          # has); and a run below Step 4 (nothing fills before Step-3 approval, so nothing
          # can legitimately be ahead of it).
          printf "evidence-gate: judged by row %s's task arms (run at current: %s)\n" \
            "$_EG_RID" "$CURRENT" >&2
          CURRENT=4
          _EG_SUBSTITUTED=1
        elif [ "$_EG_RSTEP" -gt "$_EG_CURNUM" ] 2>/dev/null; then
          _eg_detail="canonical-sdlc worktree '${_EG_WT}' belongs to '## Tasks' row ${_EG_RID}, whose step is ${_EG_RSTEP}; the run is at current: ${CURRENT}.
Plan: $PLAN
Fix: this tree's task is scheduled for step ${_EG_RSTEP} and the run has not reached it — advance the run to step ${_EG_RSTEP}, or correct row ${_EG_RID}'s step cell, before committing from ${_EG_WT}."
          refuse exit2 commit "that worktree's task is ahead of the run" "advance the run first" "$_eg_detail"
        elif [ "$_EG_RSTATUS" = "active" ] && [ "$_EG_RSTEP" -ge 4 ]; then
          # A COMMIT HAS ONE OF TWO SUBJECTS (wave-17 REQ-1, D1, ADR-031). The row stands
          # exactly where the run stands, so there is no step to substitute — and that is
          # the case the whole catch-22 lived in: a writer dispatched at Step 5, whose row
          # therefore reads 5, was judged by the run's Verify arm and refused for the green
          # floor that writer's own task exists to produce (bug 2; carry-over 1; three D10
          # `current:` regressions in wave-16). The row's `status` is what resolves it: this
          # tree has a writer in it, so this commit discharges the TASK's obligations, and
          # the arms it owes are the task arms.
          #
          # WHY THAT IS SPELLED `CURRENT=4` AND NOT A SECOND ARM TABLE. The task arms
          # already have a home: `dispatch`'s `4)` case is `shape_block worktree base-sha
          # branch`, and the matrix `fails-when:` presence arm runs for every commit at
          # step ≥ 4 regardless. Step 4 IS the arm set a task owes, so naming it is the
          # whole implementation — a parallel dispatcher would be a second place to keep in
          # step with the first. The run's arms (the floor block, the walk artifact, the
          # auditor cell, the ADR, the merge, the ship) all hang off steps 5 and up and are
          # simply never reached.
          #
          # THE NOTE IS MANDATORY, for the reason the step substitution's note above is:
          # this is a wall judging a commit by something other than the run's declared
          # `current:`, and it says so, naming the ROW — because the row is the subject.
          # Printed BEFORE the substitution, so `current:` reads as the run declared it.
          #
          # ONLY `active`, AND ONLY AT THE ROW'S OWN STEP. A `pending`, `landed` or
          # `dropped` row is nobody at work: its tree falls through to `current:` exactly as
          # it does today (25g(k2)). A row AHEAD of the run is the arm above: judged the same
          # way when it is an active work row (wave-20 Δ6), refused otherwise. A
          # row BEHIND the run keeps the wave-14 substitution and its wording, which for the
          # step-4 rows that make up every real task batch resolves to these same task arms
          # — see A-T1.2 for the residual case that leaves open.
          #
          # AND ONLY FROM STEP 4 UP (critic C1). `CURRENT=4` is a LOWERING for every row the
          # register admits above step 4 and a no-op at 4 — but `units_validate` admits a
          # step cell of 3, where it is a RAISE: a run at `current: 3` with an active step-3
          # row was judged at a step the run had not started and refused for a `Step 4:`
          # evidence line its author could only write by claiming Step 4 in a Step-3 plan.
          # That is REQ-1 inverted — the requirement exists so a task commit is not held to
          # the arms of a LATER step. Below 4 the row keeps today's `current:` path, which is
          # the behaviour the design already blesses for every other status (25g(r)).
          printf "evidence-gate: judged by row %s's task arms (run at current: %s)\n" \
            "$_EG_RID" "$CURRENT" >&2
          CURRENT=4
          # A SUBSTITUTED STEP IS NOT A POINTER STEP (wave-18 REQ-11, D7, backlog row 3).
          # Step 4 is on POINTER_STEPS, so without this flag the pointer exit a few hundred
          # lines below took `exit 0` on the step this line just substituted — unless the
          # frontmatter happened to say `use_worktree: true`. The one arm the substitution
          # exists to reach, `shape_block worktree base-sha branch`, was therefore skipped on
          # every `use_worktree: false` plan and the note above promised arms that never ran.
          # The fork owns the arms it announces. THIS IS THE SAME RULE THE step-below ARM
          # ABOVE NOW CARRIES (critic C1): D7 is about "a substituted step", not about which
          # of the two forks did the substituting, and both set `CURRENT=4`/`$_EG_RSTEP=4`
          # without ever asking which arm they came from — so both set the flag.
          _EG_SUBSTITUTED=1
        fi
        ;;
    esac
  fi
fi

# Find the evidence line for the current step: a "Step N:" line, with or
# without a leading list marker.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
LINE=$(echo "$SECTION" \
       | grep -E "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+${CURRENT}[[:space:]]*:" \
       | head -1)

if [ -z "$LINE" ]; then
  _eg_detail="canonical-sdlc plan file has no 'Step ${CURRENT}:' line in '## SDLC State'.
Plan: $PLAN
Fix: add the evidence artifact for step ${CURRENT} before committing."
  refuse exit2 commit "the plan has no line for the current step" "add the step's evidence line" "$_eg_detail"
fi

RAW_VALUE=$(echo "$LINE" | sed -E "s/^[[:space:]]*-?[[:space:]]*Step[[:space:]]+${CURRENT}[[:space:]]*:[[:space:]]*//")

# Multi-line form: when the Step line has no inline content, evidence lives on
# indented continuation lines below. Collect them so the rest of the hook treats
# `Step N:\n  field: value\n  ...` as non-empty evidence.
extract_continuation() {
  local section="$1" step="$2"
  local sline
  sline=$(echo "$section" | grep -nE "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+${step}[[:space:]]*:" | head -1 | cut -d: -f1)
  [ -z "$sline" ] && return
  echo "$section" | awk -v start="$sline" '
    NR > start {
      if ($0 ~ /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+[0-9]+[ab]?[[:space:]]*:/) exit
      if ($0 ~ /^[^[:space:]]/) exit
      if ($0 ~ /^[[:space:]]*$/) next
      print $0
    }
  '
}

CONTINUATION=$(extract_continuation "$SECTION" "$CURRENT")

# Combined block used for empty/placeholder/shape checks.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
BLOCK=$RAW_VALUE
if [ -n "$CONTINUATION" ]; then
  BLOCK="${BLOCK}
${CONTINUATION}"
fi
BLOCK_STRIPPED=$(echo "$BLOCK" | tr -d '[:space:]')

if [ -z "$BLOCK_STRIPPED" ]; then
  _eg_detail="canonical-sdlc step ${CURRENT} evidence line is empty in '## SDLC State'.
Plan: $PLAN
Fix: record the evidence artifact (commit SHA, path, link) for step ${CURRENT} before committing."
  refuse exit2 commit "this step's evidence line is empty" "record the step's evidence" "$_eg_detail"
fi

# R7 intent-scoped Step-5 keys (D14 log-only — see validate_intent_evidence
# below). A whole-value match against this exact key name exempts the line from
# the universal placeholder ban; the R7 contract is enforced instead by
# validate_intent_evidence, which logs a finding but never blocks.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
is_r7_key() {
  case "$1" in
    behavior-preservation|compat-matrix|revert-plan|baseline|target|re-measure) return 0 ;;
    *) return 1 ;;
  esac
}

# Placeholder detection. Each line of the block is checked as a whole value:
# the text after the first ':' on a "key: value" continuation line, or the
# whole line when it has no colon (the single-line "Step N: <value>" case,
# which arrives here as RAW_VALUE). ${_bline#*:} yields the after-colon text
# on colon lines and the unchanged line otherwise.
while IFS= read -r _bline; do
  _bkey=$(printf '%s' "$_bline" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*:.*$//')
  if is_r7_key "$_bkey"; then
    continue
  fi
  if is_placeholder_value "${_bline#*:}"; then
    _eg_detail="canonical-sdlc step ${CURRENT} evidence line is a placeholder (\"${BLOCK}\").
Plan: $PLAN
Fix: replace with the actual evidence artifact before committing."
    refuse exit2 commit "this step's evidence line is a placeholder" "replace it with real evidence" "$_eg_detail"
  fi
done <<< "$BLOCK"

# ---------- K5 / AC-K5.2: Step-1 'requirements:' pointer (durable, current: 2+) ----------
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# K5 fixes three artifacts to three steps (design ledger K5; ADR-001): Step 1 authors
# the wave's `*.requirements.md`, and the Step-1 evidence line is where that artifact's
# path is recorded — once, at Step 1, and never revisited. This arm reads THAT line (not
# the current step's own line) at every commit from current: 2 onward, so a plan cannot
# progress past Step 1 without a resolving pointer and cannot lose it later — the same
# durable-prefix shape validate_walk_artifact uses for the Step-5 walk narration (A5).
# Inert at current: 1 — Step 1 is still being written, and POINTER_STEPS below is what
# governs Step 1's own commit.
#
# SCOPE: rigor:audited + multi_agent:true + scale wave|epic — the same guard
# validate_dispatch_ledger uses (D7) to keep wave-lane machinery that predates a new
# requirement out of the way of fixtures that are not about it. This suite's shared FM
# (rigor: tested) and frontmatter() (no multi_agent: line, so MULTI_AGENT reads empty)
# are both guaranteed no-ops under this guard by the same construction the D7 comment
# documents; only a fixture that opts in — this wave's own plan among them (rigor:
# audited, multi_agent: true) — exercises it. Judgment call recorded because AC-K5.2's
# text names no such guard; the alternative (firing on every wave/epic plan regardless of
# rigor) blocked 170/316 of this suite's pre-existing cases on first RED and is not what
# "touch only your own span" can mean here.
step1_evidence_block() {
  local line raw cont
  line=$(echo "$SECTION" | grep -E '^[[:space:]]*-?[[:space:]]*Step[[:space:]]+1[[:space:]]*:' | head -1)
  [ -n "$line" ] || return 0
  raw=$(echo "$line" | sed -E 's/^[[:space:]]*-?[[:space:]]*Step[[:space:]]+1[[:space:]]*:[[:space:]]*//')
  cont=$(extract_continuation "$SECTION" "1")
  printf '%s\n%s\n' "$raw" "$cont"
}

# Resolution mirrors resolve_walk_path: absolute stands, a `specs/` leader is
# docs-root-relative (the form K5's layout names — requirements live beside the spec
# under specs/epic-NN-<slug>/), anything else is project-relative.
resolve_requirements_path() {  # $1 = raw requirements: value
  case "$1" in
    /*)      printf '%s\n' "$1" ;;
    specs/*) printf '%s/%s\n' "$DOCS_ROOT" "$1" ;;
    *)       printf '%s/%s\n' "$BIONIC_ROOT" "$1" ;;
  esac
}

validate_requirements_pointer() {
  local current_num b1 raw abs
  case "$SCALE" in wave|epic) : ;; *) return 0 ;; esac
  [ "$RIGOR" = "audited" ] || return 0
  [ "$MULTI_AGENT" = "true" ] || return 0
  current_num=$(echo "$CURRENT" | sed -E 's/[ab]$//')
  [ "$current_num" -ge 2 ] 2>/dev/null || return 0

  b1=$(step1_evidence_block)
  # ANYWHERE ON THE LINE (AC-3.3, seed B B11). The Step-1 evidence is a semicolon-separated
  # record and the pointer is rarely its first field; see evidence_line_field's docblock for why the
  # old line-start anchor refused a plan that named its requirements perfectly well.
  raw=$(evidence_line_field "$b1" requirements)
  if [ -z "$raw" ]; then
    _eg_detail="canonical-sdlc step ${CURRENT} — the Step 1 evidence has no 'requirements:' field.
Plan: $PLAN
Fix: add 'requirements: specs/<epic>/<wave>.requirements.md' to the Step 1 line, naming the Step-1 artifact (K5)."
    refuse exit2 commit "Step 1's evidence names no requirements file" "add a 'requirements:' field" "$_eg_detail"
  fi

  if grep -qE '(^|/)\.\.(/|$)' <<< "$raw"; then
    _eg_detail="canonical-sdlc step ${CURRENT} — Step 1 'requirements: ${raw}' climbs out with a '..' component.
Plan: $PLAN
Fix: name the requirements file relative to the docs root, e.g. 'requirements: specs/<epic>/<wave>.requirements.md'."
    refuse exit2 commit "the requirements path climbs out with '..'" "name it under the docs root" "$_eg_detail"
  fi
  abs=$(resolve_requirements_path "$raw")
  if [ ! -f "$abs" ]; then
    _eg_detail="canonical-sdlc step ${CURRENT} — Step 1 'requirements: ${raw}' does not resolve to a real file (resolved to ${abs}).
Plan: $PLAN
Fix: write the requirements document at that path (K5 Step-1 artifact) before committing at step ${CURRENT}."
    refuse exit2 commit "the named requirements file does not exist" "write the requirements file" "$_eg_detail"
  fi
  return 0
}

# ---------- REQ-3 / AC-3.1: the bring-forward arm, ahead of the arms it folds ----------
#
# HERE, AND NOT LOWER, because the first arm it summarises is the one on the next line. Every
# arm below refuses by calling `refuse`, which exits, so a summary written after any of them
# would only ever be reached by a plan that did not need it.
#
# IT SPEAKS ONLY FOR A BODY THAT IS PRE-14 — a `## Tasks` table missing required columns AND
# at least one version-14 key absent (plan_bring_forward's own trigger). Every other plan
# falls straight through to the arms below, byte for byte as it does today.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
_eg_bf="$(plan_bring_forward "$PLAN")" || {
  _eg_detail="canonical-sdlc this plan declares canonical_sdlc_version: ${SUPPORTED_SDLC_VERSION} and its body does not match it:
${_eg_bf}
Plan: $PLAN
Fix: repair every line above in one pass — each is a separate arm that would otherwise refuse the next commit in turn."
  refuse exit2 commit "this plan's body is not at contract version ${SUPPORTED_SDLC_VERSION}" "bring the plan forward" "$_eg_detail"
}

validate_requirements_pointer

# A pointer step records a link/path (not shaped fields); having passed the
# presence + placeholder checks above, it needs no shape check, so allow the
# commit. Step 4 is the exception: when use_worktree=true it carries worktree
# fields and must fall through to the shape check below.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
POINTER_STEPS="1 2 3 4"  # Step 6 must reach dispatch for the matrix prefix check

# WHERE THE POINTER-STEP EXIT WENT (epic-22 K2). The loop that used to sit here now
# runs a few hundred lines below, immediately after the two arms this wave added — and
# the move is the whole reason those arms are reachable at all. Steps 1-4 take that
# `exit 0`, so ANY wall written below it is dead at exactly the step it was written for:
# `current: 4` is a pointer step. Everything between here and the new position is
# function definitions and nothing else, so no other behaviour moved with it.

# Extract a value for a key from the BLOCK ("key: value" lines or
# "key: value" appearing on the Step line directly). Returns empty if
# not found.
block_get() {
  local key="$1"
  echo "$BLOCK" \
    | grep -E "^[[:space:]]*${key}[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

block_has() {
  grep -qE "^[[:space:]]*$1[[:space:]]*:" <<< "$BLOCK"
}

block_has_na() {
  block_has "n/a"
}

# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
shape_block() {
  local missing=()
  for f in "$@"; do
    if ! block_has "$f"; then
      missing+=("$f")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    _eg_detail="canonical-sdlc step ${CURRENT} evidence missing required field(s): ${missing[*]}
Plan: $PLAN
Required for step ${CURRENT}: $*
Fix: rewrite the Step ${CURRENT} block as multi-line YAML-style fields. See canonical-sdlc/SKILL.md \"Evidence (two tiers)\" → verification shape table."
    refuse exit2 commit "this step's evidence is missing fields" "add the fields the step owes" "$_eg_detail"
  fi
}

# ---------- shared per-step validators ----------

# Compose the "canonical-sdlc step <N>" message prefix.
step_prefix() {
  echo "canonical-sdlc step $1"
}

# Tests modality: cmd/pass/total/output present, pass and total integers,
# pass==total. Used by the Step-5 verify gate.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_tests_block() {
  local step="$1" pass total prefix advisory
  shape_block cmd pass total output
  pass=$(block_get pass)
  total=$(block_get total)
  # THE GATE RECORDS THE ADVISORY COUNTER AND NEVER JUDGES IT (wave-17 REQ-10, AC-10.2).
  # `pass:`/`total:` are the GATING rows — the ones a red suite fails on. An advisory
  # reading is a measurement the framework took and nothing gated on (tests/run.sh prints
  # `Advisory: N readings, M exceeded` beneath `Gating:` when one was taken), so the block
  # may carry it and this function reads it into nothing: it appears in no comparison
  # below, and a block that omits it is the pre-wave block, unchanged. The key was already
  # INERT — shape_block asserts presence and there is no unknown-key arm anywhere in this
  # file — so this read is the CONTRACT made explicit, not a new refusal.
  advisory=$(block_get 'advisory-exceeded')
  : "$advisory"
  prefix=$(step_prefix "$step")
  if ! grep -qE '^[0-9]+$' <<< "$pass" || ! grep -qE '^[0-9]+$' <<< "$total"; then
    _eg_detail="${prefix} 'pass:' and 'total:' must be integers (got pass='${pass}', total='${total}').
Plan: $PLAN"
    refuse exit2 commit "'pass:' and 'total:' are not both integers" "write both as integers" "$_eg_detail"
  fi
  if [ "$pass" -ne "$total" ]; then
    _eg_detail="${prefix} evidence has pass=${pass} but total=${total}; the suite is not fully green.
Plan: $PLAN
Fix: do not commit step ${step} until pass equals total."
    refuse exit2 commit "the suite is not fully green" "make pass equal total" "$_eg_detail"
  fi
}

# Document step: adr OR rca OR n/a.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_document_step() {
  local step="$1" prefix
  if ! block_has adr && ! block_has rca && ! block_has_na; then
    prefix=$(step_prefix "$step")
    _eg_detail="${prefix} evidence requires 'adr: <path>', 'rca: <path>' (incident-response mode), or 'n/a: <reason>'.
Plan: $PLAN"
    refuse exit2 commit "this step names no adr, rca or n/a" "add adr:, rca: or n/a:" "$_eg_detail"
  fi
}

# Integrate & close: merge/worktree-removed always; then the cleanup triple,
# OR an explicit `cleanup: n/a` marker (cleanup_on_finish=false).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_integrate_step() {
  local cleanup_val
  shape_block merge worktree-removed
  cleanup_val=$(block_get cleanup)
  case "$cleanup_val" in
    n/a|n/a:*)
      : # cleanup_on_finish=false / already-cleaned case (reason optional)
      ;;
    *)
      shape_block cleanup tmp-wiped tasks-completed
      ;;
  esac
}

# Does frontmatter name a LIVE surface this run operates? The default answer
# is no. `deploy_target` is n/a by default and is never inferred from deploy
# signals — a target exists only when the user names one — so an absent line,
# `none`, and `n/a` (with or without a trailing reason) all read as "no live
# surface". Case-insensitive, matching every other value comparison in this
# hook.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
deploy_target_named() {
  case "$(printf '%s' "$DEPLOY_TARGET" | tr '[:upper:]' '[:lower:]')" in
    ""|none|n/a|n/a:*) return 1 ;;
    *)                 return 0 ;;
  esac
}

# Close-out step (v14 contract, ratified 2026-08-19):
#
#   `delivered:` ALWAYS — the terminal state of the work. Step 9's default
#   endpoint is a PR open and ready for a human to review, or commits landed
#   locally and ready to push; everything past that boundary is the human's
#   process, not the run's to claim.
#
#   `deployed:` / `verified:` / `monitored:` owed EXACTLY when a deploy_target
#   is named — the run that operates its own live surface (bionic's own
#   dogfood is the example).
#
# Supersedes v13, where the trio was owed whenever any target existed and
# `n/a:` discharged the step at `deploy_target: none`. That rule encoded
# wave==release, which is the exception and not the rule, and it let a run
# with no live surface close without ever naming what it delivered.
#
# An UNOWED trio is tolerated, not refused: a run that deployed something
# without having declared a target and says so is recording more than it owes,
# and refusing that commit would punish honesty. The wall is on the absent
# claim, never on the extra one.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_ship_step() {
  local step="$1" prefix f
  local missing=()
  shape_block delivered
  deploy_target_named || return 0
  for f in deployed verified monitored; do
    block_has "$f" || missing+=("$f")
  done
  [ "${#missing[@]}" -eq 0 ] && return 0
  prefix=$(step_prefix "$step")
  _eg_detail="${prefix} frontmatter names deploy_target=${DEPLOY_TARGET}, so the close-out owes the deploy trio; missing: ${missing[*]}
Plan: $PLAN
Fix: add 'deployed:', 'verified:', and 'monitored:' to the Step ${step} block — or, if this run operates no live surface, set 'deploy_target: n/a' in frontmatter (the trio is owed exactly when a target is named)."
  refuse exit2 commit "the close-out owes the deploy trio" "add deployed:, verified:, monitored:" "$_eg_detail"
}

# ---------- pre-registered Verification Matrix ----------
# The Verify gate discharges a Verification Matrix stored in a top-level
# `## Verification Matrix` section of the plan (separate from ## SDLC State).
# validate_matrix parses that section — a per-session stack-health line, a
# tier table (one row per AC), and one indented per-AC evidence block per
# non-waived row — and fires at current: 5 (via the Step-5 validator) and as a
# prefix check for current: 6..9 (via the dispatcher).
#
# Mid-discharge commits: at current: 5, rows with status
# pending/blocked skip the per-tier key check, and the Step-5 `auditor:`
# pointer is required only when no such row remains. The full contract —
# per-tier keys, plus (at peer-reviewed/audited rigor) CONFIRMED on every
# non-waived row — bites on the 5→6 advance via the 6..9 prefix check. At
# `tested` rigor the auditor column is not a wall at all: see
# matrix_auditor_required. The status cell is enum-checked
# (pending|blocked|discharged|waived) since the relaxation makes it
# load-bearing.
#
# Close-out criteria: a T0 row whose AC block carries `task: 9` keeps that
# same relaxation ALL THE WAY to current: 9 — both the per-tier keys and the
# CONFIRMED wall — because its evidence is a Step-9 artifact that does not
# exist yet. It is two exemptions, not one: the key loop and the CONFIRMED
# arm are separate branches, and a row exempted from only the first still
# meets the second at current: 6. At current: 9 the tag stops exempting
# anything. See the tag's own note inside validate_matrix.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]

# Per-tier required evidence keys — MIRROR of the canonical table in
# skills/canonical-sdlc/steps/5.md ("Per-tier required keys"). Change THAT
# table first; this function follows it. (R27)
#
# `evidence` (1a, D5) is the one SHARED key every tier owes on top of its own
# — the AC block's record/ proof path — and it is listed LAST in every arm so
# the loop that walks this list still blocks on a tier-specific key first when
# one is missing (see the 'evidence' branch inside validate_matrix's loop).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
keys_for_tier() {
  case "$1" in
    T0|T1) echo "tier-run readback evidence" ;;
    T2)    echo "tier-run readback fixture-fidelity evidence" ;;
    T3)    echo "tier-run fresh cold-client contact readback evidence" ;;
    T4)    echo "user-confirmed evidence" ;;
  esac
}

# THE THREE STEP-4 ARMS (epic-22 K2, K4, K2.5): `matrix_section`, `matrix_block`,
# `slices_section`, `k2_step_num`, `validate_approved_by`, `validate_fails_when` and
# `validate_prototype_no_matrix_row` are now all defined just before `CURRENT` is
# parsed, above — moved there so the task-scale `current: T<n>` branch can call them
# too, instead of `exit 0`ing before ever reaching them. This is the numbered-step
# call: it still runs in the same place it always has, right before the pointer-step
# exit below.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_approved_by
validate_fails_when
validate_prototype_no_matrix_row

# THE POINTER-STEP EXIT, relocated from above (epic-22 K2). A pointer step records a
# link or a path rather than shaped fields; having passed the presence and placeholder
# checks, and now the two arms above, it needs no shape check. Step 4 is the exception:
# with use_worktree=true it carries worktree fields and falls through to the shape check.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
# AND A SUBSTITUTED STEP IS NOT A POINTER STEP (wave-18 REQ-11, D7). When the fork above
# replaced the run's `current:` with Step 4 it announced that this commit is judged by the
# row's TASK arms; the shape check below IS that arm set, so the exit is not taken on a
# substituted step whatever `use_worktree` says. On an unsubstituted Step 4 the frontmatter
# key still decides, exactly as before.
for _ps in $POINTER_STEPS; do
  [ "$CURRENT" = "$_ps" ] || continue
  if [ "$_ps" = "4" ] && { [ "$USE_WORKTREE" = "true" ] || [ "${_EG_SUBSTITUTED:-0}" = "1" ]; }; then
    break  # fall through to the Step-4 worktree shape check below
  fi
  exit 0
done

# The `user-confirmed:` value out of an AC block (empty when absent).
user_confirmed_value() {
  echo "$1" | grep -E '^[[:space:]]*user-confirmed[[:space:]]*:' | head -1 \
    | sed -E 's/^[[:space:]]*user-confirmed[[:space:]]*:[[:space:]]*//' \
    | sed -E 's/[[:space:]]+$//'
}

# Is an AC block's `user-confirmed:` in the attributed form
# `<user> <YYYY-MM-DD> <what>`? This is what lets a T4 row discharge without a
# waiver below, so it is the one place the shape is checked rather than merely
# recorded — unlike `waiver:` and `rigor-override:`, whose presence is the whole
# test because a human wrote them by definition.
#
# What the form buys: a record naming WHO confirmed and WHEN. What it cannot
# buy, and is not sold as buying: whether the named human actually said it. A
# fabricated `chris 2026-08-19 ...` passes here. The check refuses the shape an
# agent's own claim naturally takes — "confirmed after the re-render",
# "2026-08-18 the wall renders" — which is the failure mode that was actually
# observed, not a defense against a determined forger.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
user_confirmed_form_ok() {
  echo "$(user_confirmed_value "$1")" \
    | grep -qE '^[A-Za-z][A-Za-z0-9._-]*[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[^[:space:]]'
}

# The plan is read off disk when the CALL starts (PLAN is resolved at :245
# before any of the command runs). So a single Bash call that edits the plan
# and THEN commits is judged against the pre-edit plan: the fix the agent just
# wrote is invisible to every arm below, and the refusal reads as though it had
# never been made. The observed reflex on that refusal is to re-run the same
# combined call, which fails identically forever. When the refused command's
# text names the plan, say so. Matched against the absolute path and against
# the path relative to the project root — the two spellings an agent writes.
# A commit MESSAGE that merely quotes the path also matches; the line is
# advice appended to an already-refused call, so a false positive costs a
# sentence and a false negative costs the loop this exists to break.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
plan_write_note() {
  local rel="$PLAN"
  [ -n "$PLAN" ] || return 0
  case "$PLAN" in "$BIONIC_ROOT"/*) rel="${PLAN#"$BIONIC_ROOT"/}" ;; esac
  case "$COMMAND" in
    *"$PLAN"*|*"$rel"*)
      echo "Note: this command also writes the plan — run the edit first, then commit in a separate call." ;;
  esac
}

# 3-line BLOCKED/Plan/Fix emit for the matrix arm (mirrors the pattern
# every other validator uses), plus the edit-then-commit note when the refused
# command also writes the plan. $1 = message tail, $2 = fix line.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
block_matrix() {  # <fact> <fix> <observation> <repair prose>
  # THE FRAME KEEPS ITS PARAMETERS AND LOSES ITS VOICE (task 13, ruling D-1, parametric
  # table v2). $1 and $2 are the ruled fact and fix and render as the one user line; the
  # step number, the caller's long observation — the only place ${ac}, ${tier}, ${key},
  # ${val}, ${aud}, the walk paths and the environment lists are spelled — the plan path,
  # the caller's own repair prose and the plan-write note all become `detail` (F-P1, F-P3).
  refuse exit2 commit "$1" "$2" "canonical-sdlc step ${CURRENT} — $3
Plan: $PLAN
Fix: $4
$(plan_write_note 2>&1)"
}

# Placeholder-token test on a single field value. The matrix section lives
# outside ## SDLC State, so the upstream ban does not cover it; this reuses
# the same whole-value equality test (is_placeholder_value, defined above).
matrix_is_placeholder() {
  is_placeholder_value "$1"
}

validate_matrix() {
  local sh rows line ncols ac tier status ev aud block_txt key val val_lc prov_val prov_val_lc task_val task9 row_is_waived ev_abs

  # Set while any row is still pending/blocked at current: 5. The
  # Step-5 validator reads it to keep the `auditor:` pointer optional
  # mid-walk (the auditor is the exit gate — it has not run yet).
  UNDISCHARGED=0
  MATRIX=$(matrix_section)
  if [ -z "$MATRIX" ]; then
    block_matrix "this plan has no verification matrix yet" "add one row per criterion" \
      "the Verify gate requires a '## Verification Matrix' section." \
      "add the '## Verification Matrix' section: a stack-health line, the AC tier table, and one per-AC evidence block. See canonical-sdlc/SKILL.md Step 5."
  fi

  # stack-health: non-empty proof, or `n/a: <reason>` with a reason.
  # A HERE-STRING, NOT A PIPE — see the header. $MATRIX is a whole plan section and
  # routinely exceeds the pipe buffer; `echo "$MATRIX" | grep -q` turned a present
  # stack-health line into a refusal of every commit (T37).
  if ! grep -qE '^[[:space:]]*stack-health[[:space:]]*:' <<< "$MATRIX"; then
    block_matrix "the matrix says nothing about stack health" "add a before/after snapshot" \
      "'## Verification Matrix' is missing the 'stack-health:' line." \
      "add 'stack-health: <before/after snapshot>' or 'stack-health: n/a: <reason>' above the table."
  fi
  sh=$(echo "$MATRIX" | grep -E '^[[:space:]]*stack-health[[:space:]]*:' | head -1 \
       | sed -E 's/^[[:space:]]*stack-health[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  case "$sh" in
    ""|n/a|n/a:)
      block_matrix "the health snapshot is empty or a bare n/a" "paste it, or say why not" \
        "'stack-health:' needs a non-empty snapshot, or 'n/a: <reason>' with a non-empty reason." \
        "paste the before/after snapshot showing no delta, or give the reason stack-health does not apply." ;;
  esac

  # false-green two-part rule: any `false-green:` entry must have a paired
  # `rewritten:` entry, or the gate blocks (Assumption 12a).
  # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
  if grep -qE '^[[:space:]]*false-green[[:space:]]*:' <<< "$MATRIX"; then
    if ! grep -qE '^[[:space:]]*rewritten[[:space:]]*:' <<< "$MATRIX"; then
      block_matrix "a false green is logged but never rewritten" "rewrite it, then say where" \
        "a 'false-green:' entry in the matrix has no paired 'rewritten:' entry." \
        "add 'rewritten: <commit/test ref>' for the false-green test — a logged-but-unfixed false green is a blocking defect."
    fi
  fi

  rows=$(echo "$MATRIX" | grep -E '^[[:space:]]*\|')
  if [ -z "$rows" ]; then
    block_matrix "the verification matrix has no rows" "add one row per criterion" \
      "'## Verification Matrix' has no tier table rows." \
      "add the '| AC | tier | status | evidence | auditor |' table with one row per AC."
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # separator row (only pipes/dashes/colons/spaces) → skip
    grep -qE '^[[:space:]]*\|[-|:[:space:]]*$' <<< "$line" && continue
    ncols=$(echo "$line" | awk -F'|' '{print NF}')
    ac=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    tier=$(echo "$line"   | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')
    ev=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5); print $5}')
    aud=$(placeholder_cell "$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')")
    # header row → skip
    [ "$ac" = "AC" ] && continue
    # malformed: a well-formed 5-cell row splits into exactly 7 fields on '|'.
    if [ "$ncols" -ne 7 ]; then
      block_matrix "row ${ac} does not have five cells" "give it five cells" \
        "matrix row for '${ac}' is malformed (wrong cell count — no literal '|' inside cells)." \
        "write the row as '| AC | tier | status | evidence | auditor |' with exactly five cells and no literal pipe inside any cell."
    fi
    # tier enum
    if ! grep -qE '^T[0-4]$' <<< "$tier"; then
      block_matrix "${ac}'s tier is unknown" "use T0 through T4" \
        "matrix row for '${ac}' has an invalid tier '${tier}' (want T0..T4)." \
        "set the tier cell to one of T0, T1, T2, T3, T4."
    fi
    # status enum — the status cell is load-bearing (pending/blocked
    # relax the Verify gate; waived relaxes everything), so a typo must
    # block, not silently read as discharged-like.
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    case "$status" in
      pending|blocked|discharged|waived) : ;;
      *)
        block_matrix "${ac}'s status is unknown" "use pending, blocked, discharged, waived" \
          "matrix row '${ac}' has an invalid status '${status:-empty}' (want pending|blocked|discharged|waived)." \
          "set the status cell to one of: pending, blocked, discharged, waived." ;;
    esac
    block_txt=$(matrix_block "$ac")
    # Is this row WAIVED? A `waiver:` token in the evidence cell or a
    # `waiver:` line in the AC block — the loop's long-standing test, hoisted
    # into one flag (review-a C-2) so every per-row demand below reads the same
    # fact. Deliberately NOT the status cell alone: a row that says `waived`
    # while recording no waiver has not been through the Waiver Protocol, and
    # the per-tier key loop has always demanded its evidence anyway.
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    row_is_waived=0
    if grep -qE 'waiver:' <<< "$ev" \
       || grep -qE '^[[:space:]]*waiver[[:space:]]*:' <<< "$block_txt"; then
      row_is_waived=1
    fi
    # provenance arm (epic-14 W1, AC-5): the literal value `provenance:
    # implementation` in an AC block is circular — it names the change as the
    # source of its own requirement, which is unfalsifiable by construction.
    # Whole-value match after whitespace-trimming; a citation that merely
    # CONTAINS the word ("implementation-first rewrite of spec §3") is a real
    # citation and passes. A missing `provenance:` line does not block (plan
    # assumption A4 — presence is a W+1 candidate, not this wave's). Fires for
    # every row regardless of tier/status, since the spec (AC-5) says "any AC
    # block" — unlike the tier-key checks below, it does not sit behind the
    # waived/undischarged branches. Compared case-insensitively, matching the
    # placeholder and live-tier n/a checks a few lines below in this same loop.
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    prov_val=$(echo "$block_txt" | grep -E '^[[:space:]]*provenance[[:space:]]*:' | head -1 \
      | sed -E 's/^[[:space:]]*provenance[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
    prov_val_lc=$(echo "$prov_val" | tr '[:upper:]' '[:lower:]')
    if [ "$prov_val_lc" = "implementation" ]; then
      block_matrix "row ${ac} cites the code as its own source" "cite what asked for it" \
        "matrix row '${ac}' cites 'provenance: implementation' — the implementation cannot be the source of its own requirement." \
        "cite the real requirement source (user quote, spec section, ticket, report) for '${ac}', not the implementation itself."
    fi
    # `task: 9` (B-2, 2026-08-30): a criterion whose only evidence is a Step-9
    # lifecycle artifact — the close-out report, continuation.md, the ADR the
    # close-out writes — cannot be discharged at Steps 5..8, because the thing
    # it would cite does not exist yet. Such a row had only dishonest homes: a
    # `waiver:` that records the criterion as let go, or a discharged row
    # citing an artifact nobody had written. The tag is an AC-block line parsed
    # exactly like `provenance:` above — never a sixth table cell, which the
    # 7-field row pin a few lines up would refuse on every row.
    #
    # It exempts the row from TWO SEPARATE ARMS while current < 9: the per-tier
    # key loop below, and the CONFIRMED/auditor wall further down. Exempting
    # only the first leaves the row blocking at current: 6 on an empty auditor
    # cell, which is the same wall wearing a different refusal.
    #
    # T0-ONLY. Every other tier names evidence that exists before Step 9 (a
    # suite run, a live surface, the user's own word), so `task: 9` there is a
    # mis-tag rather than a deferral: it blocks at ANY step, naming the tier —
    # including current: 5, where a pending row is otherwise exempt from
    # everything and the mis-tag would sit unread until the 5→6 advance.
    # Only the exact value `9` means anything; `task: 4` is an ordinary
    # annotation this hook does not read.
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    task_val=$(echo "$block_txt" | grep -E '^[[:space:]]*task[[:space:]]*:' | head -1 \
      | sed -E 's/^[[:space:]]*task[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
    task9=0
    if [ "$task_val" = "9" ]; then
      # A WAIVED row is exempt from the tier refusal (review-a C-2). The tag on
      # a non-T0 row is a mis-tag, but a waiver has already dissolved that
      # row's evidence contract — every other per-row demand in this loop
      # (per-tier keys, the CONFIRMED wall) yields to it, and refusing here
      # left a waived row with no way out but retiering a criterion nobody
      # intends to discharge. The unwaived mis-tag still blocks at every step.
      # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
      if [ "$tier" != "T0" ] && [ "$row_is_waived" = "0" ]; then
        block_matrix "row ${ac} defers its evidence to close-out" "prove it now, or retier T0" \
          "matrix row '${ac}' is ${tier} and carries 'task: 9' — only a T0 row defers its evidence to the close-out." \
          "a ${tier} row's evidence exists before Step 9 — discharge '${ac}' at its own tier, or retier the row to T0 if the criterion really is a close-out obligation."
      fi
      task9=1
    fi
    # waived rows (evidence cell or the AC block carries a `waiver:` entry) are
    # exempt from the per-tier evidence requirement.
    if [ "$row_is_waived" = "1" ]; then
      :
    elif [ "$CURRENT" = "5" ] && { [ "$status" = "pending" ] || [ "$status" = "blocked" ]; }; then
      # A row still being discharged carries no evidence contract at
      # the Verify gate itself — its per-tier keys bite on the 5→6 advance
      # (the 6..9 prefix check), mirroring the CONFIRMED rule. This is what
      # gives a mid-walk corrective commit an honest home at current: 5.
      UNDISCHARGED=1
    elif [ "$task9" = "1" ] && [ "$CURRENT" -lt 9 ] 2>/dev/null \
         && { [ "$status" = "pending" ] || [ "$status" = "blocked" ]; }; then
      # Close-out row before Step 9 — see the `task: 9` note above. Sits
      # BELOW the current: 5 arm on purpose: at the Verify gate the existing
      # relaxation must still set UNDISCHARGED, which keeps the Step-5
      # `auditor:` pointer optional while any row is undischarged.
      # A non-numeric CURRENT makes `-lt` fail, so the exemption is
      # fail-closed on a malformed step.
      :
    else
      for key in $(keys_for_tier "$tier"); do
        if ! grep -qE "^[[:space:]]*${key}[[:space:]]*:" <<< "$block_txt"; then
          block_matrix "row ${ac} has no ${key} evidence" "record it, or waive the row" \
            "matrix row '${ac}' (${tier}) is missing evidence key '${key}' in its AC block." \
            "add '${key}: <evidence>' to the '${ac}:' block, or waive the row via the Waiver Protocol."
        fi
        val=$(echo "$block_txt" | grep -E "^[[:space:]]*${key}[[:space:]]*:" | head -1 \
              | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
        if [ -z "$val" ]; then
          block_matrix "${ac}'s ${key} evidence is blank" "record it, or waive the row" \
            "matrix row '${ac}' (${tier}) evidence key '${key}' is empty." \
            "record the evidence for '${key}' in the '${ac}:' block, or waive the row."
        fi
        if matrix_is_placeholder "$val"; then
          block_matrix "${ac} has placeholder ${key} evidence" "record what actually ran" \
            "matrix row '${ac}' (${tier}) evidence key '${key}' is a placeholder (\"${val}\")." \
            "replace '${key}' with the real evidence before committing."
        fi
        # live-tier (T3/T4) fields cannot be self-written n/a — that is a
        # downgrade, which is a user decision via the Waiver Protocol.
        # Case-insensitive: 'N/A' is the same downgrade as 'n/a' (matches
        # matrix_is_placeholder's lowercasing). The tier CELL is not checked
        # here: retyping T3 to T2 is a downgrade this hook does not see.
        # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
        val_lc=$(echo "$val" | tr '[:upper:]' '[:lower:]')
        case "$tier" in
          T3|T4)
            case "$val_lc" in
              n/a|n/a:*)
                block_matrix "${ac} calls its ${key} evidence n/a" "record it, or waive the row" \
                  "matrix row '${ac}' (${tier}) key '${key}' is a self-written 'n/a' on a live tier." \
                  "a live-tier field cannot be n/a — downgrade the row via the Waiver Protocol (record 'waiver: <user> <date> <reason>'), a user decision." ;;
            esac ;;
        esac
        # The 'evidence:' key (1a, D5) is the plan-holds-claims/record-holds-proof
        # boundary: its value must resolve to a real file under
        # <docs-root>/record/, reusing resolve_walk_path()'s own template
        # (record/<file> against the docs root, a bare path against the project
        # root, absolute as written) and the walk arm's '..' refusal — one
        # resolution rule for both citations, rather than a second copy of it.
        # It sits LAST in keys_for_tier()'s per-tier list (R27's table), so a
        # block that is missing some OTHER required key still blocks on that
        # key first; this branch only bites a block that was otherwise complete.
        # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
        if [ "$key" = "evidence" ]; then
          # THE CELL MAY CARRY A TRAILING NOTE (wave-18 REQ-9, D13, AC-9.1). Split on the
          # FIRST ' — ' (space, em dash, space) before either test below: the path half is
          # all the ';' check and the resolver ever see, so a note that itself carries a
          # ';' (e.g. 'RED on a; GREEN on b') never trips the "more than one path" refusal.
          # The note half is discarded right here — never parsed, never resolved, never
          # required to name anything.
          # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
          case "$val" in
            *" — "*) val="${val%% — *}" ;;
          esac
          # ONE PATH PER AC, AND A `;` IS NOT A SEPARATOR (wave-17 REQ-5, AC-5.3). The
          # path half — see the split above — is tested here, so `a.md; b.md` was
          # handed to the resolver entire, missed, and refused as "names no real file",
          # which sent the author to write a file at a path nobody meant to name. The
          # sibling reader of the walk artifact has truncated at the first `;` since
          # epic-14 (evidence_line_field); this cell is the outlier, and the repair is to
          # say the rule rather than to start splitting. FIRST in the branch, ahead of the
          # climb-out and file tests: a cell holding two paths has no single path for
          # either of them to be asked about.
          # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
          case "$val" in
            *\;*)
              block_matrix "evidence: names more than one path" "one path under record/ per AC" \
                "matrix row '${ac}' evidence '${val}' names more than one path (the value carries a ';')." \
                "the '${ac}:' block's evidence key takes exactly ONE path under record/. Cite the one file that proves this criterion; a second artifact belongs inside that file, or in its own AC row." ;;
          esac
          if grep -qE '(^|/)\.\.(/|$)' <<< "$val"; then
            block_matrix "${ac}'s evidence path climbs out of record/" "name it under record/" \
              "matrix row '${ac}' evidence '${val}' climbs out of the record directory and so does not resolve under ${DOCS_ROOT}/record/." \
              "point '${ac}:' evidence at a path under record/, e.g. 'evidence: record/<wave>/evidence/${ac}.md'."
          fi
          ev_abs=$(resolve_walk_path "$val")
          case "$ev_abs" in
            "$DOCS_ROOT"/record/*) : ;;
            *)
              block_matrix "${ac}'s evidence sits outside record/" "move it into record/" \
                "matrix row '${ac}' evidence '${val}' does not resolve under ${DOCS_ROOT}/record/ (resolved to ${ev_abs})." \
                "move the proof file into <docs-root>/record/ and point '${ac}:' evidence there." ;;
          esac
          if [ ! -f "$ev_abs" ]; then
            block_matrix "${ac}'s evidence names no real file" "write the proof file there" \
              "matrix row '${ac}' evidence '${val}' is named but no file exists at ${ev_abs}." \
              "write the proof for '${ac}' to that path before discharging the row."
          fi
        fi
      done
    fi
    # Once past the Verify gate, every non-waived row must be CONFIRMED —
    # at peer-reviewed and audited rigor. At `tested` no auditor was ever
    # commissioned (SKILL.md's rigor table), so this whole arm stands down;
    # matrix_auditor_required is the predicate and carries the reasoning.
    #
    # T4 is the exception, and it is not a relaxation. T4's evidence IS the
    # user's own confirmation — an independent auditor sent at it can only
    # re-read what the user said, which is transcription, not independence. So
    # a legitimately user-confirmed row used to have exactly one way past this
    # arm: the Waiver Protocol, which recorded a waiver where nothing had been
    # waived (epic-17 W4 paid its AC-7 in that form, and the row reads forever
    # as if the criterion had been let go). A T4 row carrying a well-formed
    # `user-confirmed: <user> <date> <what>` now discharges on that value —
    # the same value keys_for_tier already demanded of it — and an
    # agent-shaped claim with no attributed human still meets the wall.
    #
    # WHAT THE EXEMPTION REPLACES IS THE WAIVER FORM, NOT THE AUDITOR (critic
    # C-1, W5). Those are two authorities and only the first substitution was
    # ratified. So the exemption is scoped to an auditor cell that is EMPTY —
    # nobody has ruled, which is the ordinary state of a T4 row — or CONFIRMED,
    # where the two authorities agree. A STANDING REFUTED or UNVERIFIABLE is a
    # positive finding on the record (this wave's own first audit pass produced
    # three), and a user's confirmation does not overturn one: the row meets
    # the wall, and the refusal names the FINDING rather than the attribution,
    # because the attribution is correct and sending the user to rewrite it
    # would point them at the one thing that is not broken.
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    if [ "$CURRENT" -gt 5 ] 2>/dev/null && matrix_auditor_required; then
      if [ "$status" = "waived" ] || [ "$row_is_waived" = "1" ]; then
        :
      elif [ "$task9" = "1" ] && [ "$CURRENT" -lt 9 ] 2>/dev/null \
           && { [ "$status" = "pending" ] || [ "$status" = "blocked" ]; }; then
        # The second of the `task: 9` tag's two arms. An auditor cannot
        # CONFIRM a row whose evidence Step 9 has not produced; demanding it
        # here would re-impose the wall the key-loop exemption just lifted.
        :
      elif [ "$tier" = "T4" ] && user_confirmed_form_ok "$block_txt" \
           && { [ -z "$aud" ] || [ "$aud" = "CONFIRMED" ]; }; then
        :
      elif [ "$aud" != "CONFIRMED" ]; then
        # THE CELL IS AN EQUALITY, AND THE VERDICT NOW SAYS WHICH FAULT IT IS (wave-17
        # REQ-5, AC-5.4). `CONFIRMED (audit-b3b87dc.md)` refused with "the auditor has not
        # confirmed <AC>" — a sentence that reads as "no audit happened" to the one person
        # who knows one did and annotated the cell with its path. The equality does not
        # move: an annotated cell still refuses, because a reader scanning the column has
        # to be able to compare it, and the audit's own path has a key of its own. A cell
        # that does NOT start with the token is a different fact (no verdict, or a
        # standing one) and keeps the verdict it has always had, below.
        #
        # AHEAD OF THE T4 BRANCHES ON PURPOSE: the shape fault is the same fault whatever
        # the row's tier, and a T4 row annotated past the token would otherwise be told
        # its user-confirmation was the problem.
        # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
        case "$aud" in
          CONFIRMED*)
            block_matrix "the auditor cell is not the bare token" "write CONFIRMED; cite in evidence:" \
              "matrix row '${ac}' auditor cell is '${aud}' — it starts with CONFIRMED but is not the bare token, at step ${CURRENT}." \
              "write exactly 'CONFIRMED' in the auditor cell and cite the audit's own path in the row's 'evidence:' key — the column is compared, not read." ;;
        esac
        if [ "$tier" = "T4" ]; then
          if user_confirmed_form_ok "$block_txt"; then
            block_matrix "the auditor's finding on ${ac} stands" "settle it with the auditor" \
              "matrix row '${ac}' (T4) carries a well-formed 'user-confirmed:', but the independent auditor's standing verdict on it is '${aud}', at step ${CURRENT}." \
              "a user's confirmation does not overturn an auditor's finding — it replaces the WAIVER a T4 row used to need, not the audit. Resolve the '${aud}' verdict (re-run the audit and record CONFIRMED, or clear the cell if the finding was withdrawn), or waive the row."
          fi
          block_matrix "${ac} says confirmed but names nobody" "name who confirmed it, and when" \
            "matrix row '${ac}' (T4) auditor verdict is '${aud:-empty}', not CONFIRMED, and its 'user-confirmed:' names no attributed user, at step ${CURRENT}." \
            "record the user's own confirmation as 'user-confirmed: <user> <date> <what they confirmed>' in the '${ac}:' block — a T4 row discharges on that, no waiver needed. An unattributed or agent-written claim is not one."
        fi
        block_matrix "the auditor has not confirmed ${ac}" "get the auditor to confirm it" \
          "matrix row '${ac}' auditor verdict is '${aud:-empty}', not CONFIRMED, at step ${CURRENT}." \
          "the independent auditor must CONFIRM every non-waived row before advancing past the Verify gate, or the row must be waived."
      fi
    fi
  done <<< "$rows"
}

# ---------- walk-first artifact arm (epic-14 W1) ----------
# Verification opens with a walk: an agent narrates the real running surface
# without having read the acceptance criteria, and its narration lands in
# <docs-root>/record/ BEFORE any matrix row discharges. Existence is the wall;
# temporal order stays discipline, since no hook can see when the walk happened.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
#
# FAIL-CLOSED (plan assumption A1, user-ratified): frontmatter `walk: exempt`
# makes the arm inert; `walk: required` OR AN ABSENT KEY arms it. An exemption
# is a Step-0 ratification, never something inferred from an omission — so a
# plan that simply never mentions the key meets this arm at its next Step-5
# commit. A value outside the enum also arms it; validating that enum belongs to
# the governing-skill hook (it gates artifact writes), and treating an
# unrecognized value as "exempt" here would hand every typo a bypass.
walk_mode() {
  case "$(frontmatter_get walk)" in
    exempt) echo exempt ;;
    *)      echo required ;;
  esac
}

# The Step-5 evidence block, read at ANY current step. The module-level BLOCK
# holds the CURRENT step's evidence, so at current: 6..9 it is the Step-6..9
# block and cannot answer for the walk; this extractor re-reads Step 5 out of
# SECTION with the same line + continuation grammar the top of the hook uses.
# Empty when the plan carries no Step-5 line at all — which, post-Verify, is
# itself a missing walk artifact.
step5_evidence_block() {
  local line raw cont
  line=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+5[[:space:]]*:" | head -1)
  [ -n "$line" ] || return 0
  raw=$(echo "$line" | sed -E "s/^[[:space:]]*-?[[:space:]]*Step[[:space:]]+5[[:space:]]*:[[:space:]]*//")
  cont=$(extract_continuation "$SECTION" "5")
  printf '%s\n%s\n' "$raw" "$cont"
}

# Resolve a `walk-artifact:` value to an absolute path. Absolute passes through;
# a `record/...` value is docs-root-relative (the form the Step-5 contract
# names); anything else is project-relative, so the fully-spelled
# `.bionic/docs/record/<file>.md` a plan author is likely to paste also lands in
# the right place. Containment is checked by the caller — this only resolves.
resolve_walk_path() {  # $1 = raw walk-artifact value
  case "$1" in
    /*)       printf '%s\n' "$1" ;;
    record/*) printf '%s/%s\n' "$DOCS_ROOT" "$1" ;;
    *)        printf '%s/%s\n' "$BIONIC_ROOT" "$1" ;;
  esac
}

# The arm itself. Fires at current: 5..9 (the Verify gate and, as a durable
# prefix condition — plan assumption A5 — every step after it, so the artifact
# cannot be deleted once Verify is behind you). Trigger: at least one matrix row
# with status `discharged`. Rows that are only pending/blocked leave it silent,
# which is what keeps a mid-discharge corrective commit legal. `waived` is NOT a
# trigger: the spec arms this on discharge, and a wave whose every row is waived
# has verified nothing to narrate.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_walk_artifact() {
  local discharged b5 raw abs
  case "$CURRENT" in 5|6|7|8|9) : ;; *) return 0 ;; esac
  [ "$(walk_mode)" = required ] || return 0
  # Reuses the $MATRIX cache validate_matrix() fills. It runs immediately before
  # this arm at both call sites (validate_verify_step, dispatch's 6..9 case) and
  # hard-blocks on an empty matrix, so the cache is populated by the time we get
  # here. The `:-` fallback keeps that an optimization rather than a trap: a
  # third call site that forgot the ordering would re-read the section instead
  # of crashing under `set -u` or, worse, reading an empty matrix as "nothing
  # discharged" and letting the walk gate fall open.
  discharged=$(echo "${MATRIX:-$(matrix_section)}" | grep -E '^[[:space:]]*\|' \
    | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}' \
    | grep -cx 'discharged')
  [ "$discharged" -gt 0 ] || return 0

  # Truncated at the first ';' below: sibling extractors in this hook already
  # tolerate a Step-5 line with more fields packed after the value
  # (`walk-artifact: record/x.md; cmd: ...`); this one was the outlier,
  # greedy to end-of-line, and swallowed the packed remainder as part of the
  # "path" (plan assumption A17). The dedicated continuation-line shape has
  # no ';' in it, so the truncation is a no-op there.
  b5=$(step5_evidence_block)
  # THE SIBLING POINTER READ (AC-3.3). Same record shape, same tolerance: `evidence_line_field`
  # keeps the first-`;` truncation this read already had and drops only the line-start
  # anchor, so a Step-5 line that opens with `cmd: …` no longer hides its walk artifact.
  raw=$(evidence_line_field "$b5" walk-artifact)
  if [ -z "$raw" ]; then
    block_matrix "rows are discharged with no walk recorded" "walk it, then name the file" \
      "the walk gate: matrix rows are discharged but the Step 5 evidence has no 'walk-artifact:' line." \
      "run the walk first and record 'walk-artifact: record/<file>.md' in the Step 5 block. Frontmatter 'walk: exempt' is the only way past this arm, and it is a Step-0 decision."
  fi

  # Containment. A `..` component is refused outright rather than normalized:
  # the artifact belongs in record/, and a path that climbs out of it is a
  # placement error whatever it lands on.
  if grep -qE '(^|/)\.\.(/|$)' <<< "$raw"; then
    block_matrix "the walk file's path climbs out of record/" "name it under record/" \
      "the walk gate: walk-artifact '${raw}' climbs out of the record directory and so does not resolve under ${DOCS_ROOT}/record/." \
      "name the walk narration relative to the docs root, e.g. 'walk-artifact: record/<file>.md'."
  fi
  abs=$(resolve_walk_path "$raw")
  case "$abs" in
    "$DOCS_ROOT"/record/*) : ;;
    *)
      block_matrix "the walk file sits outside record/" "move it into record/" \
        "the walk gate: walk-artifact '${raw}' does not resolve under ${DOCS_ROOT}/record/ (resolved to ${abs})." \
        "move the walk narration into <docs-root>/record/ and name it there, e.g. 'walk-artifact: record/<file>.md'." ;;
  esac
  if [ ! -f "$abs" ]; then
    block_matrix "no file exists where the walk should be" "write the walk narration there" \
      "the walk gate: walk-artifact '${raw}' is named in the Step 5 evidence but no file exists at ${abs}." \
      "write the walk narration to that path before discharging any matrix row (and do not delete it afterwards — the arm re-checks at every later step)."
  elif [ ! -s "$abs" ]; then
    block_matrix "the walk file is empty" "narrate what you drove" \
      "the walk gate: walk-artifact '${raw}' is named in the Step 5 evidence but the file is empty at ${abs}." \
      "write real narration into the walk artifact before discharging any matrix row — an empty file is not a walk."
  fi

  # The walk narrates a running surface; it never checklists acceptance
  # criteria. An AC identifier in the artifact is the tell that it was written
  # with the criteria in hand, which is exactly the power the walk is meant to
  # have. This grep is the whole enforcement.
  # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
  if grep -qE 'AC-[0-9]' "$abs" 2>/dev/null; then
    block_matrix "the walk narration names acceptance criteria" "drop the criteria names" \
      "the walk gate: walk artifact ${abs} names acceptance criteria (matched 'AC-<n>')." \
      "rewrite the walk as narration of what was driven and what came back, with no AC identifiers — the walk is written without reading the criteria."
  fi
  return 0
}

# S3 (AC-4, AC-23; wave-01-verification-cannot-lie, D-S1b): environments —
# declared, covered, fog. Frontmatter `environments:` is one line naming the
# set this wave's Step-5 tests floor claims to run on, entries joined by
# " · ", each `<name> (covered...)` or `<name> (fog — cure: <text>)`. A plan
# that never mentions the key makes no environment claim at all: the arm
# no-ops. Most plans never declare it (this repo's own wave-01 plan is the
# exception, not the rule), so the no-op is recorded to the durable audit
# file only (log_finding_quiet, below) and never echoed to stderr — an
# ordinary commit stays exactly as silent as it is today. Declared, it
# requires the Step-5 evidence to carry an `environments-covered:` line
# naming every non-fog environment, and blocks a fog entry that names no
# cure — both are real refusals, spoken the normal BLOCKED way.
#
# AC-23: this arm reads only the DECLARATION and the Step-5
# `environments-covered:` line — never a derived suite set. It is
# independent of validate_tests_block, which is what actually requires the
# unconditional whole-suite floor run; nothing here substitutes for that,
# and nothing here is consulted by it.
#
# Fires at current: 5..9, the same durable-prefix span as
# validate_walk_artifact: the covered claim cannot quietly go stale once
# Verify is behind you.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
env_split_entries() {  # $1 = raw `environments:` value -> "name<TAB>descriptor" lines
  printf '%s\n' "$1" | awk '
    {
      n = split($0, parts, /[ \t]*·[ \t]*/)
      for (i = 1; i <= n; i++) {
        entry = parts[i]
        gsub(/^[ \t]+|[ \t]+$/, "", entry)
        if (entry == "") continue
        name = entry
        sub(/[ \t]*\(.*/, "", name)
        desc = entry
        sub(/^[^(]*\(/, "", desc)
        sub(/\)[ \t]*$/, "", desc)
        if (name != "") print name "\t" desc
      }
    }'
}

# Same audit-file write as log_finding, but WITHOUT the stderr echo. The
# absent-`environments:` case fires on nearly every ordinary commit in
# nearly every bionic-using repo (the key is opt-in), so surfacing it there
# the way an actionable finding is surfaced would be noise, not information.
# The durable file still gets the line — "log-only" — but only a plan that
# actually declared the key can make this arm speak on stderr.
# [INSTRUMENT]
log_finding_quiet() {  # $1=check-id  $2=detail
  local f
  if f=$(audit_path "$(audit_root)"); then
    local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) evidence-gate $1: $2 ($PLAN)"
    mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$line" >> "$f" 2>/dev/null
  fi
  return 0
}

validate_environments() {
  local raw entries name desc cure covered_names fog_names fog_missing_cure
  local b5 covered_line covered_norm missing claimed_fog claimed_undeclared
  case "$CURRENT" in 5|6|7|8|9) : ;; *) return 0 ;; esac
  raw=$(frontmatter_get environments)
  if [ -z "$raw" ]; then
    log_finding_quiet environments "no 'environments:' declared in frontmatter — the covered/fog check is a no-op"
    return 0
  fi

  entries=$(env_split_entries "$raw")
  covered_names=""
  fog_names=""
  fog_missing_cure=""
  while IFS=$'\t' read -r name desc; do
    [ -n "$name" ] || continue
    case "$desc" in
      fog*)
        fog_names="${fog_names:+$fog_names }$name"
        cure=""
        case "$desc" in
          *cure:*) cure=$(printf '%s' "$desc" | sed -E 's/^.*cure:[[:space:]]*//' | sed -E 's/[[:space:]]+$//') ;;
        esac
        [ -n "$cure" ] || fog_missing_cure="${fog_missing_cure:+$fog_missing_cure }$name"
        ;;
      *)
        covered_names="${covered_names:+$covered_names }$name"
        ;;
    esac
  done <<< "$entries"

  if [ -n "$fog_missing_cure" ]; then
    block_matrix "a fog environment names no way to cover it" "say how it gets covered" \
      "environments: fog entry with no cure named: ${fog_missing_cure} (declared: '${raw}')." \
      "name each fog environment's cure in the frontmatter, e.g. '<name> (fog — cure: <how it gets covered>)'."
  fi

  if [ -n "$covered_names" ]; then
    b5=$(step5_evidence_block)
    covered_line=$(echo "$b5" | grep -E '^[[:space:]]*environments-covered[[:space:]]*:' | head -1 \
      | sed -E 's/^[[:space:]]*environments-covered[[:space:]]*:[[:space:]]*//' \
      | sed -E 's/;.*$//' | sed -E 's/[[:space:]]+$//')
    if [ -z "$covered_line" ]; then
      block_matrix "the plan never says which environments ran" "list what you covered" \
        "environments: declared covered set (${covered_names}) but the Step 5 evidence has no 'environments-covered:' line." \
        "record 'environments-covered: <name>[, <name>...]' in the Step 5 block naming every declared non-fog environment."
    fi
    covered_norm=$(printf '%s' "$covered_line" | tr ',' ' ' | tr -s '[:space:]' ' ')
    missing=""
    for name in $covered_names; do
      case " $covered_norm " in
        *" $name "*) : ;;
        *) missing="${missing:+$missing }$name" ;;
      esac
    done
    if [ -n "$missing" ]; then
      block_matrix "a declared environment went uncovered" "cover it, or mark it fog" \
        "environments-covered '${covered_line}' omits declared environment(s): ${missing} (declared covered set: ${covered_names}; fog: ${fog_names:-none})." \
        "run the Step-5 tests floor on every declared non-fog environment and list it in 'environments-covered:', or move it to a fog entry naming its cure."
    fi

    # THE OTHER DIRECTION — OVER-CLAIMING (critic K-5). The loop above walks the DECLARED
    # non-fog names and requires each to be covered. Nothing walked the covered names, so a
    # plan could claim coverage it does not have and the arm was silent: this wave's own
    # frontmatter passes `environments-covered: macos-system, linux-system` while
    # linux-system is declared FOG, and a fog entry's entire meaning is "not covered". A
    # name that was never declared at all (`freebsd`) was equally silent. The ownership row
    # states the containment in this direction — covered ⊆ declared — and until now only
    # the opposite one was implemented.
    claimed_fog=""
    claimed_undeclared=""
    for name in $covered_norm; do
      case " $covered_names " in *" $name "*) continue ;; esac
      case " $fog_names " in
        *" $name "*) claimed_fog="${claimed_fog:+$claimed_fog }$name"; continue ;;
      esac
      claimed_undeclared="${claimed_undeclared:+$claimed_undeclared }$name"
    done
    if [ -n "$claimed_fog" ]; then
      block_matrix "a fog environment is claimed as covered" "drop it, or test it there" \
        "environments-covered '${covered_line}' claims coverage of environment(s) this plan declares as FOG: ${claimed_fog} (fog: ${fog_names:-none})." \
        "a fog entry means NOT covered — either drop the name from 'environments-covered:', or run the Step-5 tests floor there and move it out of fog in the frontmatter."
    fi
    if [ -n "$claimed_undeclared" ]; then
      block_matrix "the covered list names an undeclared environment" "declare it, or drop it" \
        "environments-covered '${covered_line}' names environment(s) the frontmatter never declared: ${claimed_undeclared} (declared: '${raw}')." \
        "declare the environment in the frontmatter's 'environments:' list, or drop it from 'environments-covered:' — the covered set is a subset of the declared one."
    fi
  fi
  return 0
}

# Verify gate: tests floor, the Verification Matrix, and — at peer-reviewed or
# audited rigor, once no row is still pending — a non-empty `auditor:` pointer.
# At `tested` that pointer is not demanded (matrix_auditor_required).
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_verify_step() {
  local aud
  validate_tests_block 5
  validate_environments
  validate_matrix
  # Walk-first: the narration must already exist once anything has discharged.
  validate_walk_artifact
  # The auditor is the Step-5 exit gate — it cannot have run while
  # rows are still pending/blocked, so the pointer is required only once
  # every row is discharged or waived, and only where an auditor exists at
  # all (matrix_auditor_required: never at `tested`).
  # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
  if [ "$UNDISCHARGED" -eq 0 ] && matrix_auditor_required; then
    if ! block_has auditor; then
      block_matrix "this plan has no auditor verdict yet" "record what the auditor said" \
        "the Verify gate requires 'auditor: <verdict summary + report pointer>' in the Step 5 block." \
        "record the independent auditor's one-line verdict summary and report pointer as 'auditor: ...'."
    fi
    # THE SECOND READER OF AN AUDITOR CELL, folding the same way (D15). `auditor: —` in the
    # Step-5 block is the absence `block_has` cannot see, and reading it as a verdict let a
    # plan past the Verify gate with no audit recorded at all.
    aud=$(placeholder_cell "$(block_get auditor)")
    if [ -z "$aud" ]; then
      block_matrix "the auditor verdict is blank" "record what the auditor said" \
        "the Step 5 'auditor:' pointer is empty." \
        "record the auditor's verdict summary and report pointer."
    fi
  fi
}

# Epic merge-target consistency (LOG-ONLY; D14, check-id `merge-target`).
# On a wave-scale plan naming an `epic:`, when the epic plan exists and
# declares an `integration-branch:` in its ## SDLC State, a mismatch with this
# plan's integration-branch logs a finding. Never blocks. First cross-file read
# in this hook — read-only, fail-open (missing epic plan / missing key → no
# finding). Fires at the integrate step.
# [INSTRUMENT]
validate_merge_target() {
  local epic epic_plan epic_branch this_branch
  epic=$(frontmatter_get epic)
  [ -n "$epic" ] || return 0
  epic_plan="$DOCS_ROOT/plans/$epic/epic.plan.md"
  [ -r "$epic_plan" ] || return 0
  # Fence-aware (matches the SECTION extraction): an epic plan documenting a
  # `## SDLC State` example in a ``` fence must not shadow its real section.
  # [INSTRUMENT]
  epic_branch=$(normalize_newlines "$epic_plan" \
    | awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^## SDLC State/ { f=1; next }
      /^## / { f=0 }
      f' \
    | grep -E '^[[:space:]]*integration-branch[[:space:]]*:' | head -1 \
    | sed -E 's/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  [ -n "$epic_branch" ] || return 0
  this_branch=$(echo "$SECTION" | grep -E '^[[:space:]]*integration-branch[[:space:]]*:' | head -1 \
    | sed -E 's/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  if [ -n "$this_branch" ] && [ "$this_branch" != "$epic_branch" ]; then
    log_finding merge-target "plan integration-branch '$this_branch' != epic '$epic' integration-branch '$epic_branch'"
  fi
  return 0
}

# Intent-scoped Step-5 evidence keys (R7) — LOG-ONLY (D14; check-ids
# `refactor-evidence`, `tune-evidence`). Fires on plans whose
# declared intent carries a conditional key set; never blocks. Reuses the
# Step-5 BLOCK/block_has/block_get accessors already populated for the
# current step's evidence (same accessors validate_verify_step uses),
# so this validator is only meaningful when called at current: 5.
# [INSTRUMENT]
validate_intent_evidence() {
  local key val
  case "$INTENT" in
    refactor)
      if ! block_has behavior-preservation || [ -z "$(block_get behavior-preservation)" ] \
         || is_placeholder_value "$(block_get behavior-preservation)"; then
        log_finding refactor-evidence "refactor plan Step 5 missing 'behavior-preservation:' evidence"
      fi
      for key in compat-matrix revert-plan; do
        if block_has "$key"; then
          val=$(block_get "$key")
          if [ -z "$val" ] || is_placeholder_value "$val"; then
            log_finding refactor-evidence "refactor plan Step 5 '${key}:' present but empty"
          fi
        fi
      done
      ;;
    tune)
      for key in baseline target re-measure; do
        val=$(block_get "$key")
        if ! block_has "$key" || [ -z "$val" ] || is_placeholder_value "$val"; then
          log_finding tune-evidence "tune plan Step 5 missing '${key}:' evidence"
        fi
      done
      ;;
  esac
  return 0
}

# Wave-scale D7 dispatched-task ledger PRESENCE (D-task 4/3). Guarded to
# scale:wave + frontmatter rigor:audited + multi_agent:true plans; for
# every other plan it is a no-op (return 0). scale:epic is intentionally OUT —
# epic plans legitimately dispatch research, not task-shaped units, so demanding
# a dispatched-task ledger there would false-block scoping runs (plan Assumption
# A8). Called from dispatch_modern, so it runs at EVERY step that reaches the
# dispatcher (plan Assumption A5): the ledger is commit-time bookkeeping (D7:
# ledger before marking complete), demanded from the first gated commit.
#
# TESTED-FLOOR SHAPE ONLY (plan Assumption A2): the wave's own Step-5 auditor /
# Step-6 critic are the assurance roles at wave scale, so per-row auditor/critic
# tokens (task-scale machinery) are NOT demanded here.
#   1. `## Tasks` section ABSENT OR EMPTY -> exit 2 (the audited multi_agent wave
#      must carry its dispatched-task ledger home).
#   2. NO TABLE, OR A TABLE WITH ZERO DATA ROWS -> SATISFIED (a human
#      `none dispatched` prose line is documentation, not required by the
#      parser — the shape this refusal's own Fix text advertises). return 0.
#   3. Each data row: the Task invariants, delegated to `units_validate` (REQ-1e)
#      — status in {pending,active,landed,dropped} among them — else exit 2; a
#      non-placeholder `- T<n>:` evidence line must exist in the ## SDLC State
#      section (SECTION) else exit 2.
# [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
validate_dispatch_ledger() {
  [ "$SCALE" = "wave" ] || return 0
  [ "$RIGOR" = "audited" ] || return 0
  [ "$MULTI_AGENT" = "true" ] || return 0

  local tasks rows line id ev violations
  # THE ROWS AND THE INVARIANTS BOTH COME FROM lib/units.sh (REQ-1e, spec §2 D3).
  # This is the check the widened table breaks hardest: `| id | step | kind | task |
  # agent | deps | size | serves | Files | status |` puts `agent` at the `$6` this
  # function used to read as a status, so every row of an ordinary wave plan failed
  # the enum — on the wave's own plan, at its own next commit
  # (record/wave-11-lean-spine/step1-measure-1a-1e.md §4.3, and fixture 22e1).
  #
  # DELEGATED, NOT RESTATED. The status enum this function carried is one of the
  # Task invariants `units_validate` now owns, and it owns the rest of them too —
  # id shape, step range, kind vocabulary, deps that resolve, and the Step-5+ rows
  # depending transitively on every Step-4 row. One violation line per fault, each
  # naming its id and its rule, is what the writer gets back.
  #
  # WHAT STAYS HERE is the pair of facts units.sh cannot know: that this plan owes a
  # ledger at all (the D7 PRESENCE rule, guarded to the triple above), and that every
  # row's evidence has actually been written on a `- T<n>:` line in ## SDLC State.
  #
  # PRESENCE IS A QUESTION ABOUT THE SECTION, NOT ABOUT THE TABLE, and the base's
  # own fence-aware extractor is what answers it (correctness F-1, A-68.1). Asking
  # `units_rows` instead moved the basis: that reader exits 1 for a section carrying
  # PROSE and no header row, a shape the docblock above calls SATISFIED and this
  # refusal's own Fix text advertises ("a header plus a 'none dispatched' line is
  # fine"). The next audited multi_agent wave that wrote it would have been unable
  # to commit. Same extractor as validate_task_ledger, and the same one the pre-wave
  # hook carried at 84da6b5.
  tasks=$(normalize_newlines "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Tasks/ { f=1; next }
    /^## / { f=0 }
    f')
  if [ -z "$tasks" ]; then
    _eg_detail="canonical-sdlc audited multi_agent wave plan has no '## Tasks' dispatched-task ledger section.
Plan: $PLAN
Fix: add a '## Tasks' section (a header plus a 'none dispatched' line is fine); the orchestrator appends one row per dispatched task-shaped unit (D7)."
    refuse exit2 commit "this wave plan has no '## Tasks' ledger" "add a '## Tasks' section" "$_eg_detail"
  fi
  # THE SECTION IS PRESENT. What is left is the TABLE, and a section without one is
  # rule 2 — satisfied, and returned BEFORE `units_validate`, which has no rows to
  # judge and would only restate the absence as an invariant violation.
  rows="$(units_rows "$PLAN")" || return 0
  [ -n "$rows" ] || return 0
  # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
  violations="$(units_validate "$PLAN")" || true
  if [ -n "$violations" ]; then
    _eg_detail="canonical-sdlc audited multi_agent wave plan's '## Tasks' table breaks the Task invariants:
${violations}
Plan: $PLAN
Fix: repair each row named above; the columns are id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status."
    refuse exit2 commit "that dispatched task's row is invalid" "fix the row the detail names" "$_eg_detail"
  fi
  # PRESENCE IS ASKED OF THE WHOLE TABLE AT ONCE (AC-5.1). This loop used to refuse at the
  # first id it found short, so a wave owing three lines paid three refused commits; the
  # shared arm below counts every row and prints the lines the author owes. It runs ahead
  # of the placeholder walk: "you wrote nothing" and "you wrote a placeholder" are two
  # findings, and the first is the one a whole-table answer can give.
  # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
  refuse_missing_evidence_lines "$rows"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(units_field "$line" id)
    case "$id" in T[0-9]*) : ;; *) continue ;; esac
    # Evidence line in ## SDLC State (anchored, same lookup as task scale).
    # [WALL: tests/canonical-sdlc-evidence-gate.test.sh]
    ev=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:" | head -1 \
         | sed -E "s/^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    if is_placeholder_value "$ev"; then
      _eg_detail="canonical-sdlc dispatched task ${id} evidence line is a placeholder ('${ev}').
Plan: $PLAN
Fix: replace the '- ${id}:' placeholder with the actual evidence artifact before committing."
      refuse exit2 commit "the dispatched task's evidence is a placeholder" "replace it with evidence" "$_eg_detail"
    fi
  done <<< "$rows"
  return 0
}

# Step numbering: 4 worktree · 5 Verify gate · 7 Document · 8 Integrate &
# close · 9 Close-out. Steps 1/2/3/6 are pointer steps handled upstream, except
# that Step 6 reaches here so the matrix prefix check can fire.
INTEGRATE_STEP=8
SHIP_STEP=9

dispatch() {
  # Audited multi_agent wave: D7 dispatched-task ledger PRESENCE, at every step
  # that reaches this dispatcher (guarded internally; no-op otherwise).
  validate_dispatch_ledger
  # The Verification Matrix is a prefix contract for every step from the Verify
  # gate on — current: 5 validates it inside validate_verify_step; current: 6..9
  # validate it here, so a REFUTED auditor blocks post-Verify commits too.
  # The walk artifact is a durable prefix condition alongside it (A5): deleting
  # the narration after the Verify gate blocks every later commit. The
  # environments claim (S3, AC-4) is the same shape: covered ⊆ declared and
  # every fog entry's cure stay true across the whole post-Verify span.
  case "$CURRENT" in
    6|7|8|9) validate_matrix; validate_walk_artifact; validate_environments ;;
  esac
  # Log-only epic merge-target check at the integrate step.
  [ "$CURRENT" = "$INTEGRATE_STEP" ] && validate_merge_target
  case "$CURRENT" in
    4) shape_block worktree base-sha branch ;;
    5)
      validate_verify_step
      validate_intent_evidence
      ;;
    7) validate_document_step 7 ;;
    *)
      if [ "$CURRENT" = "$INTEGRATE_STEP" ]; then
        validate_integrate_step
      elif [ "$CURRENT" = "$SHIP_STEP" ]; then
        validate_ship_step "$SHIP_STEP"
      fi
      ;;
  esac
}

dispatch
exit 0
}

# ─── wall_farm_out_reminder — hooks/farm-out-reminder.sh ─────────────────────
#
# FARM-OUT: tiered enforcement — long-running main-thread commands DENY with a
# redirect to the right role; fuzzy production-shaped commands get ONE
# additionalContext nudge per class per session; every tier-1/tier-2 event logs one
# line to $HOME/.claude/logs/<project-slug>/sdlc-audit.md — outside every consuming
# project tree (incident 0001) — via audit_path().
#
# ENFORCEMENT LIVES IN STDOUT JSON ONLY, never exit 2 (epic-08 wave-04 ADR-002;
# amends D14 per user ratification 2026-07-20). It is the one wall of the five that
# answers on that wire, and the fold keeps the distinction rather than averaging it
# away: `deny` for a block, `fold_context` for a nudge.
# [UNENFORCED]
#
# Thread discrimination (epic-08 Q1 spike + hooks docs): agent_type non-empty →
# subagent → silent. Missing keys classify as MAIN THREAD.
# [WALL: tests/farm-out-reminder.test.sh]
wall_farm_out_reminder() {  # <event> -> 0 nothing · 1 nudge · 2 deny
  local AGENT_TYPE TOOL_NAME CMD
  AGENT_TYPE=$(bionic_jq .agent_type);   [ -n "$AGENT_TYPE" ] && return 0
  TOOL_NAME=$(bionic_jq .tool_name);     [ "$TOOL_NAME" = "Bash" ] || return 0
  CMD="$COMMAND";                        [ -n "$CMD" ] || return 0

  # THE CLASSIFIER IS THIS WALL'S OWN TO FIND (A-56.1). hooks/bash-walls.sh does
  # not demand cmd-class.sh, because a wall that steps aside over a missing file
  # must not make the two walls over irreversible actions refuse everything. So
  # this function asks for it here, at the point it has decided it has work to
  # do, and steps aside naming the file when it is not there — which is what the
  # hook did, in the same words.
  wall_libs farm-out-reminder cmd-class.sh || return 0

# ASKED ONCE, IN hooks/bash-walls.sh, FOR ALL FIVE (T23). The root and the session id
# come from their one owner (REQ-1f, lib/context.sh).
# `project_root` walks to the nearest real `.bionic` ancestor rather than trusting
# whatever directory invoked the hook — the audit file and the config below both hang
# off the answer, and a worktree that answered with its own tree would write a second
# audit stream for one project.
#
# THE `unknown` SUBSTITUTION IS GONE (REQ-1h). An empty session id used to become that
# literal and carry on to be refused by name one guard later; the library returns 1 and
# this hook exits, which is the same silence by a route that never forms a state path
# out of a value it has already judged unusable.

# ---------- THE ENGAGEMENT GUARD (AC-6): is this session bionic's at all? ----------
#
# FIRST, above the run predicate and above the FARM_OUT_ALLOW override both. Chris,
# 2026-09-03: "all guardrails imposed by bionic should only apply when exercising
# bionic. Nothing should apply until bionic is triggered" — and the trigger is the
# canonical-sdlc skill, which writes `.bionic/tmp/engaged-<sid>.state` at the instant it
# is invoked. A session that never invoked it gets no nudge, no deny and no audit line:
# exit 0, no stdout, no stderr.
#
# ABOVE THE OVERRIDE for the same reason the run predicate is: FARM_OUT_ALLOW=1 exists
# to bypass a wall that is binding, and where the wall is inert there is nothing to
# bypass. An audit line recording an "override" of a wall that was never going to fire
# is noise in the one stream that has to stay readable.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — an absent marker, a symlink at the path,
# a foreign key — because the arming partition is the consent boundary (1.3.2 close-out).
# An unshaped key never reaches here at all: `bionic_context` refused it above.
# [WALL: tests/cmd-class.test.sh]

# ── NO RUN PREDICATE HERE, DELIBERATELY (step-6 review R-1) ──────────────────
#
# This hook used to ask `active_run` for an open canonical-sdlc run and exit silently
# without one. That gate is gone. The nudge is PLAN-FREE: engagement decides whether a
# bionic wall speaks at all, and knowing that a suite command belongs in a subagent
# needs no plan — the sessions most in need of the reminder are the ones in Step 0
# through Step 3, which have not written one yet. Adding the predicate back would
# re-open the hole R-1 named.
# [WALL: tests/cmd-class.test.sh]



local MODE FLAT SAFE_FLAT TARGET CLASS ROLE CHAIN_SEGS CHAIN_COUNT CHAIN_ROLE
local _cfg _seg _has_nonexempt
MODE="block"
if [ -f "$BIONIC_ROOT/.bionic/config.yaml" ]; then
  _cfg=$(grep -E '^farm-out-mode:' "$BIONIC_ROOT/.bionic/config.yaml" 2>/dev/null | head -1 \
    | sed 's/^farm-out-mode:[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')
  case "$_cfg" in block|advisory|off) MODE="$_cfg" ;; esac
fi
[ "$MODE" = "off" ] && return 0

# Normalized single-line form for matching + the scrubbed deny reason (CR translate).
# THREE FORKS AND A SUBSHELL BECOME ONE BUILTIN LOOP (REQ-10, T11) — see
# `_wall_flatten` at the top of this file for why the CR pass was redundant once
# the whitespace squeeze ran.
_wall_flatten "$CMD"; FLAT="$_WALL_FLAT"

# `audit_path` IS AT FILE SCOPE NOW, once for the two walls that carried a copy — see
# the top of this file. The copies were byte-identical and had to be, or one project
# would get two audit files; one definition is that guarantee rather than a comment
# asking for it.

log_event() {  # $1=event $2=class
  # No command-derived text: `class=<c> mode=<m>` is the complete payload.
  # A length bound is not a sanitizer — incident 0001 leaked a live credential
  # through the former `cut -c1-120` excerpt of the raw command.
  local f
  if f=$(audit_path "$BIONIC_ROOT"); then
    local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) farm-out $1: class=$2 mode=$MODE"
    mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$line" >> "$f" 2>/dev/null
  fi
  echo "farm-out [$1] class=$2" >&2
  return 0
}

# [WALL: tests/farm-out-reminder.test.sh]
emit_deny() {  # $1=class $2=role
  # THROUGH THE ONE RENDERER (task 13, table row 106). `deny` is the mode this hook has
  # always used and the one the E1 measurement showed carries a model-only channel, so
  # the user gets the single line and the whole existing instruction rides the JSON
  # reason unchanged. `refuse` EXITS — with status 0 on this mode, which is what the
  # JSON verdict needs. Under the fold the object is STAGED and `bionic_fold` makes the
  # one `refuse` call, so the mode, the words and the wire are unchanged and only the
  # moment of rendering moved (A-53).
  fold_block deny run "this command belongs in a subagent" "dispatch it with the Agent tool" \
    "$(deny_reason "$1" "$2")"
  return 2
}

emit_nudge() {  # $1=class $2=role
  # THE MODEL'S CHANNEL, STAGED (T23, fold.sh's `fold_context`). This hook built the
  # `hookSpecificOutput` object itself because it was the only process on the wire; five
  # walls in one process can reach for the same object, and several JSON documents on one
  # stdout is a wire nothing parses. The text is unchanged to the byte and the fold emits
  # it through the same `jq -n`, so a lone nudge is the object this line used to print.
  fold_context "farm-out checkpoint: $1-class command on the main thread — production-shaped work belongs in a subagent. Fix: dispatch via Agent(subagent_type: $2) when you can. This protects your own context budget; a stuck orchestrator cannot process completions. Advisory only."
  return 1
}

# Pattern scrub for command-derived text (incident 0001). Two shapes:
# a hex run of 32+ (API keys, tokens, hashes) and an explicit
# KEY=/TOKEN=/SECRET= assignment. This is deliberately farm-out-local —
# no other hook in this repo interpolates raw command text.
scrub_secrets() {  # stdin → stdout
  sed -E -e 's/[A-Fa-f0-9]{32,}/[REDACTED]/g' \
         -e 's/([A-Za-z0-9_]*(KEY|TOKEN|SECRET)=)[^[:space:]]+/\1[REDACTED]/g'
}

deny_reason() {  # $1=class $2=role
  # Scrub BEFORE truncating: truncating first can split a hex run below the
  # 32-char threshold and leak a prefix.
  local safe; safe=$(printf '%s' "$FLAT" | scrub_secrets | cut -c1-120)
  printf '%s' "farm-out checkpoint: this $1-class command doesn't belong on the orchestrator thread (a stuck orchestrator is unavailable and cannot process subagent completions — this protects your own context budget). Fix: dispatch it — Agent(subagent_type: $2, prompt carrying the command from this tool call): $safe — scrubbed and truncated for the log; the agent returns the result summary. If this genuinely cannot be dispatched (needs this session's state), re-run prefixed FARM_OUT_ALLOW=1 — the override is sanctioned and audited."
}

# ── classification (B-5: argv positions, read by scripts/lib/cmd-class.sh) ───────
# override check + wrapper unwrap precede classification.

# The sed twins that used to live here — strip_prefixes() and unwrap() — are
# GONE (review-b B-4a). They were hand-rolled copies of the library's
# strip_leading()/unwrap_runner() with their own smaller rule set: the prefix
# strip knew only `env`, `FARM_OUT_*=`, `nohup` and `timeout <n>`, so a `sudo`,
# a `time`, an `xargs` or an ordinary `FOO=1` left the wrapper sitting at
# argv[0] and the tier-2 matcher below never fired. Tier-2 now reads
# cmd_unwrap_head, which is the same reduction cmd_class itself performs — one
# reader, one set of rules, and the R-12 superset applies to the nudge tier too.
# [WALL: tests/cmd-class.test.sh]

role_for_class() {  # $1=class → the role a redirect names
  case "$1" in suite) printf 'test-runner' ;; *) printf 'implementor' ;; esac
}

classify_tier1() {  # $1=command text → sets CLASS ROLE, rc 0 on match
  # ONE READER, argv-positional (payload/scripts/lib/cmd-class.sh). The regex classifier
  # this replaced matched mid-string after any space, so `make( +[^ ]+)?` denied
  # `git commit -m "make the row green"` as class=build and a heredoc body carrying
  # `bash tests/run.sh` denied as class=suite — both measured, research-b3 §2. Prose,
  # quoted strings and heredoc bodies are never argv[0], so they no longer classify.
  # A short (<3-segment) chain that carries a tier-1 command still denies here on
  # purpose; the ≥3-segment chain is a separate arm (class=chain) reached only when
  # this one skips.
  # [WALL: tests/cmd-class.test.sh]
  local c
  c=$(cmd_class "$1")
  [ "$c" = "none" ] && return 1
  CLASS="$c"; ROLE=$(role_for_class "$c")
  return 0
}

emit_tier1() {  # $1=class $2=role — deny, or downgrade to a nudge under advisory
  if [ "$MODE" = "advisory" ]; then
    log_event "deny-downgraded" "$1"; emit_nudge "$1" "$2"; return 1
  fi
  log_event "deny" "$1"; emit_deny "$1" "$2"
}

classify_tier2() {  # $1=flat cmd → sets CLASS ROLE, rc 0 on match
  # THREE ANCHORED REGEXES, THREE FORKS, AND ALMOST ALWAYS THREE MISSES (REQ-10,
  # T11). Every one is anchored at `^`, so the command has to START with the
  # matcher's first word for any of them to fire; the `case` asks exactly that
  # with a builtin and lets the greps decide only when one of them still can.
  # A command that begins with none of the four words is the overwhelming case
  # and now costs nothing.
  local c="$1"
  case "$c" in
    git*|docker*|npx*|uvx*) : ;;
    *) return 1 ;;
  esac
  if grep -qE '^git +clone([;&| ]|$)' <<< "$c"; then CLASS="clone"; ROLE="implementor"; return 0; fi
  if grep -qE '^docker +(run|pull)([;&| ]|$)' <<< "$c"; then CLASS="docker-run"; ROLE="implementor"; return 0; fi
  if grep -qE '^(npx|uvx) +' <<< "$c"; then CLASS="pkg-exec"; ROLE="implementor"; return 0; fi
  return 1
}

nudge_once() {  # $1=class $2=role — ONE nudge per (session, class); repeat = suppressed
  local state="$BIONIC_ROOT/.bionic/tmp/farm-out.state"
  mkdir -p "$BIONIC_ROOT/.bionic/tmp" 2>/dev/null
  if [ -f "$state" ] && grep -qF "$BIONIC_SID	$1" "$state" 2>/dev/null; then
    log_event "suppressed" "$1"; return 0
  fi
  printf '%s\t%s\n' "$BIONIC_SID" "$1" >> "$state" 2>/dev/null || true
  log_event "nudge" "$1"; emit_nudge "$1" "$2"; return 1
}

# ── main flow: override → unwrap → tier-1 deny → tier-2 nudge (single + chain) ──
# Chain-aware: the override token is honored ANYWHERE in the invocation —
# leading, after a separator (;/&/|), or as an env-prefix mid-chain
# (`cd x && FARM_OUT_ALLOW=1 bash tests/run.sh`) — not only in leading
# position. W4's false fire was exactly this shape: a 2-segment &&-chain hit
# the single-command tier-1 arm before the old leading-only case ever ran.
#
# SCREENED ON THE LITERAL TOKEN FIRST (REQ-10, T11). The regex cannot match
# without `FARM_OUT_ALLOW=1` present verbatim — the surrounding groups only test
# what borders it — so a command without that substring skips the grep, and a
# command with it still gets the full positional answer.
case "$FLAT" in
  *FARM_OUT_ALLOW=1*)
    if grep -qE '(^|[;&| ])FARM_OUT_ALLOW=1([;&| ]|$)' <<< "$FLAT"; then
      log_event "override" "user-sanctioned"; return 0
    fi
    ;;
esac

# THE HEREDOC-FREE FORM, THE TIER-2 HEAD AND THE CHAIN SEGMENTS, IN ONE FILL
# (epic-23 wave-14 T17, REQ-4; T4 §5 / A-T4.2). Chain segmentation and the tier-2
# matcher read the heredoc-free form rather than FLAT, so a `&&` or an `npx` inside a
# heredoc body cannot reshape the decision any more than it can classify. All three
# readings now arrive from `_wall_cmd_fill` — see it at the top of this file for what
# each skip costs and why none of them can narrow what the wall sees. Nothing here forks.
_wall_cmd_fill "$CMD"
SAFE_FLAT="$_WALL_SAFE_FLAT"
TARGET="$_WALL_HEAD"
CHAIN_SEGS="$_WALL_CHAIN_SEGS"; CHAIN_COUNT="$_WALL_CHAIN_COUNT"
CLASS=""; ROLE=""

# Tier-1 single command → deny (advisory-downgrades to a nudge inside emit_tier1).
# A ≥3-segment && chain defers to the chain tier-1 arm below so it keeps its
# class=chain label: now that install/build share the suite/bootstrap segment
# anchoring, an unguarded single-command match would relabel those chains.
if [ "${CHAIN_COUNT:-0}" -lt 3 ] && classify_tier1 "$CMD"; then
  emit_tier1 "$CLASS" "$ROLE"; return $?
fi

# Chain tier-1 arm: ANY stripped/unwrapped segment matches tier-1 → deny as
# class=chain, role taken from the matching segment.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  CHAIN_ROLE=""
  while IFS= read -r _seg; do
    # TRIMMED IN THE SHELL, not through a `sed` per segment: `_WALL_SAFE_FLAT` has
    # been squeezed by `_wall_flatten`, so the only whitespace a segment can carry at
    # either end is single spaces.
    while :; do
      case "$_seg" in
        ' '*) _seg="${_seg# }" ;;
        *' ') _seg="${_seg% }" ;;
        *)    break ;;
      esac
    done
    [ -n "$_seg" ] || continue
    if classify_tier1 "$_seg"; then
      CHAIN_ROLE="$ROLE"; break
    fi
  done <<EOF
$CHAIN_SEGS
EOF
  if [ -n "$CHAIN_ROLE" ]; then emit_tier1 "chain" "$CHAIN_ROLE"; return $?; fi
fi

# Tier-2 single command → nudge once per (session, class).
if classify_tier2 "$TARGET"; then
  nudge_once "$CLASS" "$ROLE"; return $?
fi

# Chain tier-2 arm: ≥3 segments, NO tier-1 segment (the tier-1 arm above would
# have exited otherwise), ≥1 non-exempt segment → nudge as class=chain.
if [ "${CHAIN_COUNT:-0}" -ge 3 ]; then
  _has_nonexempt=""
  while IFS= read -r _seg; do
    # TRIMMED IN THE SHELL, not through a `sed` per segment: `_WALL_SAFE_FLAT` has
    # been squeezed by `_wall_flatten`, so the only whitespace a segment can carry at
    # either end is single spaces.
    while :; do
      case "$_seg" in
        ' '*) _seg="${_seg# }" ;;
        *' ') _seg="${_seg% }" ;;
        *)    break ;;
      esac
    done
    [ -n "$_seg" ] || continue
    # THE SAME EXEMPT SET, ASKED WITH A BUILTIN. The regex was anchored at `^` over
    # literal words each followed by a literal space, which is exactly what these
    # patterns are — a bare `git` with no argument stays non-exempt in both spellings.
    case "$_seg" in
      'git '*|'ls '*|'cat '*|'head '*|'tail '*|'wc '*|'grep '*|'rg '*|'find '*|'awk '*|\
      'sed '*|'mkdir '*|'cp '*|'mv '*|'rm '*|'touch '*|'echo '*|'printf '*|'test '*|\
      'cd '*|'pwd '*|'which '*|'command '*|'true '*|'false '*) : ;;
      *) _has_nonexempt=1; break ;;
    esac
  done <<EOF
$CHAIN_SEGS
EOF
  if [ -n "$_has_nonexempt" ]; then nudge_once "chain" "implementor"; return $?; fi
fi

return 0
}

# ─── wall_background_suite_guard — hooks/background-suite-guard.sh ───────────
#
# A subagent may not run a suite where nobody reads the output (B-9,
# wave-bionic-1.3.2; spec R-9, AC-23/AC-24).
#
# THE DEFECT. A dispatched agent that runs `bash tests/run.sh` with the Bash tool's
# `run_in_background: true` gets a shell id back instead of a result. The suite runs,
# the agent's turn ends, and the evidence the task was dispatched to produce exists
# nowhere: no file, no transcript, no exit status anyone read.
#
# ABSENT, NOT FALSE. The CLI omits `run_in_background` from `tool_input` when the
# caller did not set it (@anthropic-ai/claude-code 2.1.251, sdk-tools.d.ts:722
# declares it optional on the Bash tool input), so the test is `== true` and never
# `!= false`.
#
# THE PARTITION IS A GATE HERE NOW (T23 ruling R2). This wall was registered BEHIND
# hooks/agent-context-guard.sh, which ran it only inside an agent context of an armed
# session — and that wrapper was the only thing keeping arm 1 off the main thread:
# driven straight, this wall refuses a main-thread backgrounded suite; driven through
# the guard it did not (measured 2026-09-12, T23 report §2). A wrapper around the
# COMPOUND would silence protect-main, protect-database, the evidence gate and
# farm-out-reminder on every main-thread call, so the predicate is asked here, of
# this one function, and the guard file stays registered on SubagentStop untouched.
# [WALL: tests/background-suite-guard.test.sh]
# [WALL: tests/cmd-class.test.sh]
wall_background_suite_guard() {  # <event> -> 0 nothing · 2 block
  local IS_BACKGROUND ACTOR _bsg_roster
  [ "$(bionic_jq .tool_name)" = "Bash" ] || return 0
  [ -n "$COMMAND" ] || return 0

  # THREE REFUSING ARMS LIVE IN THIS FUNCTION, and the cheap pre-filter is their union. (A
  # fourth, ARM R, repairs rather than refuses and rides the same union — it needs no gate of
  # its own; see its header, below ARM 2.)
  #
  #   B-9 (AC-23)  a BACKGROUNDED suite — nobody reads the result.
  #   S13 (AC-21)  a suite OUTSIDE THE ROW'S BUDGET, inside a dispatched agent —
  #                foreground or not, because an extra full-tree run costs 40 minutes
  #                either way.
  #   ARM C        a `git commit` from a READ-ONLY ROLE's row (wave-19 REQ-8) — inside a
  #                dispatched agent only, answered below the partition.
  IS_BACKGROUND=no
  [ "$(bionic_jq '.tool_input.run_in_background|tostring')" = "true" ] && IS_BACKGROUND=yes
  # THE ACTOR (design D1, task 4/1 probe): an agent-context payload carries a top-level
  # `agent_id`, a main-thread one does not. hooks/stop-guard.sh reads the same field the
  # same way.
  ACTOR=$(bionic_jq .agent_id)
  [ "$IS_BACKGROUND" = yes ] || [ -n "$ACTOR" ] || return 0

  # ── THE PARTITION, verbatim from hooks/agent-context-guard.sh's predicate ──
  #
  # 1. an agent context at all — main-thread payloads carry no top-level `agent_id`
  #    (t1 §3, `ctx = .agent_id // "MAIN"`).
  # 2. a root that exists, and no symlink anywhere on the arming path — the same
  #    three levels the attestation gets in hooks/dispatch-preflight.sh. A repo
  #    pointing this wall at another tree's arming fact is a repo deciding which
  #    session it belongs to.
  # 3. this session is ARMED: the roster file the dispatch wall wrote. An unarmed
  #    session fails on one stat and pays nothing else, which is what kept an
  #    always-on registration from re-globalising a deliberately scoped wall.
  #
  # Anything else — ambiguity included — returns 0 in silence. This gate never
  # refuses on its own account and never prints.
  [ -n "$ACTOR" ] || return 0
  [ -d "$BIONIC_ROOT" ] || return 0
  [ ! -L "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic/tmp" ] || return 0
  _bsg_roster="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
  [ ! -L "$_bsg_roster" ] && [ -f "$_bsg_roster" ] || return 0

  # ---------- ARM C (wave-19 REQ-8, D9): a read-only role never commits ----------
  #
  # THE BREACH (wave-18 T7c-green). The four read-only roles carry `disallowedTools: Write,
  # Edit, NotebookEdit` and never `Bash`, so "never commits" was prose: a `bionic:test-runner`
  # committed its own green run. This arm makes the promise a wall.
  #
  # ABOVE THE SUITE FILTER, because a commit is not a suite and everything below returns 0
  # on a non-suite command. The screen is the evidence gate's reader (`_wall_mentions_git`
  # then the argv parser), so `git -C <dir> commit` is a commit and a quoted "git commit" is
  # not.
  #
  # EVERY VERB THAT MAKES A COMMIT, NOT ONLY `commit` (wave-20 T3, REQ-3, AC-3.2). `revert`,
  # `cherry-pick`, `merge`, `am`, `rebase`, `commit-tree` and `update-ref` each write history
  # the arm never saw, and `env -C <dir> git …` hid even `commit` until the reader learned env.
  # The set is this arm's alone: the evidence gate's own verb stays `commit`, because the
  # orchestrator lands with `git merge`, and a writer's merge of its wave head is its brief.
  #
  # THE ROLE IS THE ROSTER ROW'S `subagent_type=`, READ BY THE SAME JOIN ARM 2 MAKES — the
  # last row carrying this `agent_id` wins. Never the payload's `agent_type`: for a teammate
  # it is the dispatch NAME (R3 Q2), and a name like `x-runner` is not a role. The match is
  # the exact plugin-qualified spelling, so a consumer's own `acme:test-runner` is not ours.
  # No row, or a row with no role → no statement about this agent, and silence.
  if _wall_mentions_git "$COMMAND" \
     && git_argv_has_any_sub "$COMMAND" "commit merge revert cherry-pick am rebase commit-tree update-ref"; then
    local _bsg_role
    _bsg_role=$(awk -F'|' -v id="$ACTOR" '
      /^roster-state\// {
        hit = 0; role = ""
        for (i = 1; i <= NF; i++) {
          if ($i == "agent_id=" id) hit = 1
          else if ($i ~ /^subagent_type=/) role = substr($i, 15)
        }
        if (hit) last = role
      }
      END { print last }
    ' "$_bsg_roster" 2>/dev/null)
    case "$_bsg_role" in
      bionic:test-runner|bionic:researcher|bionic:auditor|bionic:critic)
        fold_block exit2 commit "$_bsg_role: a read-only role never commits" "send your report" \
          "Your roster row names you $_bsg_role, and a read-only role's deliverable is its report,
never a commit. Leave the tree as it is and send the report; the orchestrator lands the work."
        return 2 ;;
    esac
  fi

# ---------- THE ENGAGEMENT GUARD (AC-20): is this session bionic's at all? ----------
#
# FIRST, above every other scoping question this hook asks. Chris, 2026-09-03: "all
# guardrails imposed by bionic should only apply when exercising bionic. Nothing should
# apply until bionic is triggered" — and the trigger is the canonical-sdlc skill, which
# writes `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. A session that
# never invoked it is one this hook has nothing to say to, and it says nothing: exit 0,
# no stdout, no stderr.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — absent marker, a symlink at the path, a
# foreign or unshaped session key, no key at all. The marker is the one artifact whose
# PRESENCE opens a wall, so the fail direction is inverted here on purpose: the arming
# partition is the consent boundary (1.3.2 close-out), and a wall that binds a session
# which never consented is the defect this guard exists to remove.
# [WALL: tests/cmd-class.test.sh]
#
# THE GUARD IN FRONT IS GONE AND ITS PREDICATE IS ABOVE (T23/R2). It could not wrap the
# compound — it would have silenced the other four walls on every main-thread call — so
# it is the first thing this ONE function asks, which is the same scope by a route that
# reaches no other wall.
#
# ASKED ONCE, IN hooks/bash-walls.sh, FOR ALL FIVE (T23) — see wall_protect_main. The
# shape guard this wall used to apply LATE, at the roster read, still lives in
# `bionic_context` (REQ-1h), so BIONIC_SID cannot be unusable by the time it is a path.

# THE CLASSIFIER IS THIS WALL'S OWN TO FIND (A-56.1) — see wall_farm_out_reminder.
# BELOW THE PARTITION, deliberately: a main-thread or unarmed call has already been
# answered "not live here" and has nothing to classify, so it neither pays for the
# source nor prints a line about a file it was never going to read.
wall_libs background-suite-guard cmd-class.sh || return 0

[ "$(cmd_class "$COMMAND")" = "suite" ] || return 0

# A SHELL-BACKGROUNDED SUITE IS CAUGHT LIKE A TOOL-BACKGROUNDED ONE (D8, REQ-6). The tool
# flag read above sees only `run_in_background: true`; it has never seen `bash
# tests/run.sh &`, a `nohup`/`setsid` wrapper, or a suite trailing a bare `&` behind a
# redirect or a `while … done`. `cmd_backgrounded` reads the TEXT for exactly that, the
# same positional discipline as `cmd_class` itself, and can only be asked once the library
# above is loaded — this is the first point in the function where it is. Read AFTER the
# suite check, not before: the predicate is real work only a suite command ever pays for.
if [ "$IS_BACKGROUND" != yes ] && cmd_backgrounded "$COMMAND"; then
  IS_BACKGROUND=yes
fi

# ---------- ARM 1 (B-9, AC-23): refuse, naming the shape that works ----------
#
# FIRST OF THREE, because it is the widest refusal: a backgrounded suite is refused whether
# or not it is on the budget, and being on the budget is no answer to "nobody read the
# result". ARM 2 (the budget) is next and ARM R (the timeout repair) is last — see ARM R's
# own header for why a refused call must never reach it (T13, A-orch-39).
#
# The command is echoed back so the fix is a copy-paste rather than a retype. It is the
# agent's own text going back to the agent — no third party reads this stream — so it is
# quoted whole rather than scrubbed and truncated the way farm-out-reminder.sh's audit
# line is.
#
# THE REMEDY IS THE RUN, NOT THE COMMAND (wave-20 T4; REQ-7, D7; triage-B B2). It used to echo
# `$COMMAND` whole — the trailing `&`, the `nohup`, the redirect into a log nobody reads — so
# the line this arm offered as the fix tripped this arm again when pasted. What is echoed now
# is each suite claim's RUN (`cmd_suite_claims` column 3): the segment the classifier read,
# with its wrappers stripped and its trailing redirections normalised off, which is the text
# the budget arm below compares. A pasted remedy is therefore foreground by construction and
# on the budget exactly when the run is.
if [ "$IS_BACKGROUND" = yes ]; then
  _bg_fix=""
  while IFS=$'\t' read -r _bg_k _bg_t _bg_run; do
    [ -n "$_bg_run" ] || continue
    _bg_fix="${_bg_fix}    $_bg_run 2>&1 | tee <evidence log>"$'\n'
  done <<< "$(cmd_suite_claims "$COMMAND")"
  [ -n "$_bg_fix" ] || _bg_fix="    <your suite command> 2>&1 | tee <evidence log>"$'\n'
  fold_block exit2 suite-run "a backgrounded suite's result is never read" "run it in the foreground" \
    "A backgrounded suite returns a shell id, not an outcome. Your turn can end before it
finishes, and then the evidence this task exists to produce lives nowhere: no file, no
exit status anyone saw. Reports are turn-scoped; files are not.

Run it in the FOREGROUND instead: no trailing &, no nohup, and the Bash tool's
run_in_background: false (or the parameter left out). Bound it by the tool's own timeout
parameter (never a timeout/gtimeout binary), with the output tee'd to the evidence log
your brief names:

${_bg_fix}
Then read the log and quote the pass/total line. If the suite is genuinely longer than any
timeout you can set, say so in your report and stop — do not background it."
  return 2
fi

# ---------- ARM 2 (S13, AC-21): THE BUDGET ARM ----------
#
# BEFORE ARM R, THE REPAIR (T13, A-orch-39). It shipped after it and that was the defect: a
# refused call must never be repaired, and this is where that is decided. Read ARM R's own
# header for the measurement.
#
# INSIDE A DISPATCHED AGENT ONLY. `hooks/dispatch-preflight.sh` wrote this agent`s budget
# onto the roster row at launch — `suites_allowed=`, derived from the tree by the impact
# command or declared by the brief — and this is the wall that holds it there. On the
# orchestrator`s own thread hooks/farm-out-reminder.sh owns the same question and answers
# it differently (dispatch it, or take the audited override), so this arm never speaks
# there: no `agent_id`, no arm.
#
# THIS IS A BUDGET, NOT A SAFETY WALL, and the refusal says so in that word (ADR-002). An
# extra suite run is undoable and visible — it costs compute and forty minutes of a
# machine, never a byte of anyone`s work — so the fail directions below are chosen by what
# a wrong answer costs rather than uniformly:
#
#   no row for this agent, or a row with no `suites_allowed` key at all
#       A row is written for every dispatch that passes the wall, so its absence means the
#       journal failed or the row predates the wall. Refusing every suite would punish an
#       agent for a bookkeeping failure it did not cause, so a NAMED suite passes in
#       silence. `tests/run.sh` still does not: a full-tree run is the one act the standing
#       ruling caps at one per run, and no row is not a licence to spend it.
#
#   `suites_allowed=` present but EMPTY
#       A budget was stated and came out empty — the impact command failed or derived
#       nothing, and the dispatch warned about it. Read exactly as the absent case above.
#
#   `suites_allowed=none`
#       The explicit `Suites: none` waiver. A brief that declared it runs no suite at all,
#       and every suite is refused, `tests/run.sh` included.
#
#   a set of basenames
#       Each suite the command names must be in it.
#
# A SUITE-CLASS COMMAND THAT NAMES NO FILE — `pytest`, `make test`, `npm test` — has no
# basename to compare and passes. This repo budgets by suite file; a project that does not
# is not one this row can speak about, and inventing a refusal for it would be the wall
# guessing.
#
# FARM_OUT_ALLOW IS NOT READ HERE, AND THAT IS THE POINT. The override exists so the
# ORCHESTRATOR can run something on its own thread when dispatching it genuinely will not
# work; it is farm-out-reminder.sh`s escape from farm-out-reminder.sh`s wall. A writer that
# could set an environment variable on itself to widen its own instrument would have a
# budget in name only — that is a wish, not a wall — so nothing in this arm looks at it.
[ -n "$ACTOR" ] || return 0

# THE SHAPE RULE IS ALREADY SPENT (REQ-1h). `session_id` returns the host-supplied value
# verbatim — it validates nothing — and this line turns it into a path. The rule that made
# that safe used to live here, blanking the id and carrying on; it lives in `bionic_context`
# now and ENDS the hook instead, so BIONIC_SID cannot be unusable by the time it reaches
# this line. The reason is hooks/landing-gate.sh:284's about `agent_id`: a key carrying path
# separators does not trip the symlink guards, it reads outside the directory those guards
# protect.
local ROSTER_FILE BUDGET_STATED SUITES_ALLOWED RE_EXECUTES BUDGET_LINE
local _CLAIMS _kind _target _run _shown
ROSTER_FILE="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
BUDGET_STATED=no
SUITES_ALLOWED=""
RE_EXECUTES=""
if [ -n "$BIONIC_SID" ] && [ ! -L "$ROSTER_FILE" ] && [ -f "$ROSTER_FILE" ]; then
  # THE LAST ROW CARRYING THIS ID WINS, which is the whole fleet`s reading of the roster
  # (hooks/stop-guard.sh, hooks/session-poker.sh: "the last row carrying a name wins"). A
  # launch row is later joined by the recorder`s `status=confirmed` copy and, across a
  # /clear, by the poker`s adopted row; each carries the budget forward, and the newest is
  # the current statement about this agent.
  #
  # TWO FIELDS, ONE READ (REQ-1 AC-1.5). `re_executes=` is the same statement in the
  # spelling a repository whose tests are not shell suites can make — the author-marked
  # runs its brief declared under `Re-executes:`, marks kept and space-joined (A-T1.4) —
  # and it is read off the SAME winning row, because a budget assembled from two different
  # rows would hold an agent to a contract no single dispatch ever wrote. The answer comes
  # back as two lines: the `<stated>:<allowed>` pair this arm has always read, then the
  # declared runs behind an `R:` marker (a run may hold any character but `|` and a
  # newline, both refused at the lift, so a marker is the only safe join).
  BUDGET_LINE=$(awk -F'|' -v id="$ACTOR" '
    /^roster-state\// {
      hit = 0; stated = 0; allowed = ""; runs = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "agent_id=" id) hit = 1
        else if ($i ~ /^suites_allowed=/) { stated = 1; allowed = substr($i, 16) }
        else if ($i ~ /^re_executes=/) { runs = substr($i, 13) }
      }
      if (hit) { last = stated ":" allowed; lastruns = runs }
    }
    END { if (last != "") { print last; print "R:" lastruns } }
  ' "$ROSTER_FILE" 2>/dev/null)
  case "$BUDGET_LINE" in
    1:*) BUDGET_STATED=yes
         SUITES_ALLOWED="${BUDGET_LINE%%$'\n'*}"
         SUITES_ALLOWED="${SUITES_ALLOWED#1:}" ;;
  esac
  case "$BUDGET_LINE" in
    *$'\n'R:*) RE_EXECUTES="${BUDGET_LINE#*$'\n'R:}" ;;
  esac
  # DECODED ONCE, HERE, BEFORE ANYTHING READS IT (T4; REQ-7, D4). The row stores this field
  # percent-encoded because the line is pipe-delimited and a declared run may legitimately
  # hold a pipe inside quotes — `payload/scripts/lib/roster.sh` owns that encoding and
  # carries the reasoning; `roster_pipe_escape`/`roster_pipe_unescape` there are these two
  # expansions, and the pair is the definition this copy answers to.
  #
  # SPELLED HERE RATHER THAN SOURCED. This file runs inside `hooks/bash-walls.sh`, whose
  # `BIONIC_LIB_WANT` does not carry `roster.sh`; adding it would grow the wall-library
  # table and the loader contract for two parameter expansions. The twin is the posture
  # `sanitize`/`clean` and `parse_seconds` already hold in this fleet.
  #
  # ONE DECODE, NOT ONE PER READER. `_run_is_declared` compares against this variable and
  # `budget_refuse` PRINTS it to a reader who is about to retype the command — so decoding
  # inside the compare would leave the refusal advertising a command no shell can run,
  # while decoding in both places would turn a literal `%7C` in a command into a pipe.
  RE_EXECUTES="${RE_EXECUTES//\%7C/|}"
  RE_EXECUTES="${RE_EXECUTES//\%25/%}"
  # AND NORMALISED, AT THE SAME ONE DECODE (wave-20 T4; REQ-7, D7). The claim side builds
  # its run with `cmdnorm_run` (payload/scripts/lib/cmd-class.sh, loaded above ARM 1), which
  # takes trailing redirections, `| tee` and `|| true` off; the declared side goes through
  # the same rule here, once per hook call, so `_run_is_declared` compares two readings of
  # one rule and never a raw declaration against a normalised claim. For a row the lift
  # wrote this is the identity — the lift refuses a redirection in a declaration and runs
  # the same rule before it stores one — and `cmd_runs_norm` skips its fork when the field
  # holds nothing the rule could act on.
  RE_EXECUTES=$(cmd_runs_norm "$RE_EXECUTES")
fi
[ -n "$SUITES_ALLOWED" ] || BUDGET_STATED=no

# `none` is a STATED empty set and reads as one: nothing is on the budget, so the loop
# below refuses every target it is handed.
case "$SUITES_ALLOWED" in none) SUITES_ALLOWED="" ;; *) : ;; esac

# ---------- AC-5.2: the allowed set on the WIRE, not just in `detail` ----------
#
# T7's repro (record/wave-14-tune-181/T7-req5-repro.md §4): "On the budget: …" has
# lived in `detail` since c789e22, and refuse.sh's channel table marks exit2's
# `detail_to_user` `no` (ruling D-1) — a dispatched writer's own tool_result on a
# budget refusal never carried it, only the fact/fix ONE LINE did, and that line
# named no set. This puts the set (or as much as the line has room for) onto
# `fact`, which exit2 DOES relay (refuse.sh:271-278) — the whole line stays under
# `BIONIC_LINE_WIDTH` because `refuse()` still checks it, so a wrong estimate here
# self-refuses loudly (refuse.sh's own `_refuse_selfrefuse`) rather than silently
# overflowing. `bionic_cols`/`bionic_trunc`/`BIONIC_LINE_WIDTH` are refuse.sh's own
# soft-sourced width.sh (hooks/bash-walls.sh sources refuse.sh before walls.sh,
# `:202`/`:213`) — nothing new is sourced, and refuse.sh itself is unchanged.
#
# TOKEN BOUNDARIES, NEVER A CHARACTER CUT. A budget of 38 suites (A-orch-17's own
# incident) cannot fit on any one line; showing the first few WHOLE tokens plus a
# "+N more" count (research-R2-preflight.md Q6) beats a mid-name ellipsis, which
# would print a truncated, unrunnable suite name. `none` is reserved for a
# genuinely EMPTY set — a non-empty set that has no room at all (cols<=0, or not
# even its first token fits) renders as a bare count ("N suites") instead, which
# is honest either way `none` is not: it does not claim the budget is empty, and
# it does not cut a name mid-word. Review-correctness-d3930dd.md F3 (mid-name
# ellipsis via `bionic_trunc`) and F7 (`none` for a non-empty set at cols<=0) are
# both this shape; fixed together here rather than patched at each call site.
#
# A DECLARED RUN IS ONE ITEM, NOT ITS WORDS (wave-20 T4; REQ-7, D7; triage-B B3). The set
# this renders is not always suite basenames: a run claim's refusal hands it the row's
# declared runs, backtick-marked and holding spaces. Split on whitespace, `npx jest
# --testPathPatterns 'x'` became four "suites", and the line printed an unclosed mark and
# half a command — `allowed: \`npx jest +3 more` — a remedy nobody could run. The set is
# read into ITEMS first: a marked run whole, marks kept, every other word alone, one per
# line. Everything below counts and places items, so "token boundary" now means what the
# header above always promised, for both kinds. The split lives INSIDE this function, not
# beside it: tests/bash-walls.test.sh 15g lifts this function alone by its own braces, and
# a helper it called would be missing from the lift.
_budget_wire_list() {  # <allowed text: suites and/or marked runs, may be empty> <column budget> -> text
  local set="${1:-}" cols="${2:-0}"
  if [ -z "$set" ]; then printf 'none'; return; fi
  local items="" total=0 nruns=0 tok rest="$set" bt='`' pre w
  local -a words
  while :; do
    case "$rest" in *"$bt"*"$bt"*) : ;; *) break ;; esac
    pre="${rest%%"$bt"*}"; rest="${rest#*"$bt"}"
    tok="${rest%%"$bt"*}"; rest="${rest#*"$bt"}"
    read -r -a words <<< "$pre"
    for w in ${words[@]+"${words[@]}"}; do items="$items$w"$'\n'; done
    items="$items$bt$tok$bt"$'\n'
  done
  read -r -a words <<< "$rest"
  for w in ${words[@]+"${words[@]}"}; do items="$items$w"$'\n'; done
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    total=$((total + 1))
    case "$tok" in '`'*) nruns=$((nruns + 1)) ;; esac
  done <<< "$items"
  [ "$total" -gt 0 ] || { printf 'none'; return; }
  # THE COUNT NAMES WHAT IT COUNTS. Suites, runs, or — when a runner's refusal shows both
  # halves of the budget — entries.
  local word=suites
  if [ "$nruns" -eq "$total" ]; then word=runs
  elif [ "$nruns" -gt 0 ]; then word=entries; fi
  [ "$total" -eq 1 ] && word="${word%s}"
  [ "$word" = entrie ] && word=entry
  if [ "$cols" -le 0 ]; then
    # NO ROOM AT ALL (F7). The set is NOT empty, so `none` would lie; name the
    # count instead. `_budget_wire_fact`'s caller-side self-refuse (refuse.sh's
    # own line-width check) is what catches an overlong line from here, per
    # A-T8.1 — this function's job is to be honest, not to guarantee a fit.
    printf '%d %s' "$total" "$word"
    return
  fi
  local joined="" first=""
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ -n "$first" ] || first="$tok"
    joined="${joined:+$joined }$tok"
  done <<< "$items"
  if [ "$(bionic_cols "$joined")" -le "$cols" ]; then
    printf '%s' "$joined"
    return
  fi
  local out="" shown=0 cand remain tail
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if [ -z "$out" ]; then cand="$tok"; else cand="$out $tok"; fi
    remain=$((total - shown - 1))
    tail=""
    [ "$remain" -gt 0 ] && tail=" +$remain more"
    if [ "$(bionic_cols "$cand$tail")" -le "$cols" ]; then
      out="$cand"; shown=$((shown + 1))
    else
      break
    fi
  done <<< "$items"
  remain=$((total - shown))
  if [ -z "$out" ]; then
    # Not even one whole token fits ALONGSIDE its own "+N more" count. Try the
    # first token bare, count dropped — a real suite name beats one padded
    # with a count it has no room for.
    if [ "$(bionic_cols "$first")" -le "$cols" ]; then
      printf '%s' "$first"
      return
    fi
    # NOT EVEN ONE TOKEN FITS BARE (F3). A character cut here would print a
    # truncated, unrunnable suite name — exactly what token-boundary rendering
    # exists to avoid — so the honest floor is the bare count, same as cols<=0.
    printf '%d %s' "$total" "$word"
  elif [ "$remain" -gt 0 ]; then
    printf '%s +%d more' "$out" "$remain"
  else
    printf '%s' "$out"
  fi
}

# _budget_wire_fact <label, ending ": "> <verb> <fix> <allowed set> -> a `fact`
# string carrying `label` plus as much of `allowed` as fits beside `verb` and
# `fix` inside refuse()'s one line. Computed fresh each call (not a hardcoded
# column count), so a reword of `fix` cannot silently overrun the budget AT THIS
# CALL — the safety this buys is real but partial: `fix` is spelled a second time at
# each call site, once as this function's own argument and once as `fold_block`'s
# (`:4114`/`:4115`, `:4130`/`:4131`, `:4161`/`:4162`), and rewording one without the
# other still miscomputes the room silently. Keeping the two literals in step at
# each site is on the caller.
_budget_wire_fact() {
  local label="$1" verb="$2" fix="$3" allowed="$4"
  local prefix="bionic: $verb refused — " suffix=" ($fix)"
  local overhead=$(( $(bionic_cols "$prefix") + $(bionic_cols "$label") + $(bionic_cols "$suffix") ))
  local room=$((BIONIC_LINE_WIDTH - overhead))
  [ "$room" -gt 0 ] || room=0
  printf '%s%s' "$label" "$(_budget_wire_list "$allowed" "$room")"
}

# _run_is_declared <run> <the row's re_executes= field, DECODED> -> 0 when the row declared
# EXACTLY this run (REQ-1 AC-1.5).
#
# THE FIELD ARRIVES PLAIN (T4; REQ-7, D4). The row stores it percent-encoded, and the one
# read of that row decodes it before this function or any refusal sees it — see the decode
# beside `BUDGET_LINE` above for why there is exactly one decode and not one per reader. A
# caller that hands this function a raw row field compares against the storage spelling and
# will not match a command holding a pipe.
#
# THE FIELD KEEPS THE AUTHOR S MARKS, space-joined (A-T1.4): `` `npx jest x` `pytest tests` ``.
# The marks are what make it self-delimiting — a run holds spaces, commas and quotes, so no
# punctuation separator is unambiguous, and a backtick cannot occur INSIDE a run because a
# backtick is what ends one. So the split is on the marks and never on whitespace.
#
# EXACTLY, not a prefix. `npx jest` and `npx jest --testPathPatterns 'x'` are different
# spends — the first runs the whole tree — and a match that accepted one for the other would
# lose the one-regression rule to a spelling. Both sides are already collapsed by the time
# they meet: the lift collapses each marked run before writing it
# (hooks/dispatch-preflight.sh `collapse()`), the classifier collapses the argv text it read
# (payload/scripts/lib/cmd-class.sh `ws1()`), and those two are the same rule written once
# on each side of the roster row.
_run_is_declared() {  # <run> <re_executes field>
  local _want="$1" _rest="$2" _tok _bt
  [ -n "$_want" ] && [ -n "$_rest" ] || return 1
  _bt='`'
  while :; do
    case "$_rest" in *"$_bt"*) : ;; *) return 1 ;; esac
    _rest="${_rest#*"$_bt"}"
    case "$_rest" in *"$_bt"*) : ;; *) return 1 ;; esac
    _tok="${_rest%%"$_bt"*}"
    _rest="${_rest#*"$_bt"}"
    [ "$_tok" = "$_want" ] && return 0
  done
}

budget_refuse() {  # <suite basename>
  # A NAME THE SHELL HAS NOT EXPANDED YET IS A DIFFERENT REFUSAL (review-c C-5, A-35c). A
  # hook sees the command TEXT, so `for s in a b; do bash "tests/$s.test.sh"; done` reaches
  # here as the literal `$s.test.sh`. Refusing is right — the hook cannot check what it
  # cannot read — but the ordinary headline is false in exactly this case: every one of
  # those suites may be on the budget, and it sends the reader to audit a set that is not
  # the problem. Two readers hit it before this branch existed.
  case "$1" in
    *'$'*|*'`'*)
      fold_block exit2 suite-run \
        "$(_budget_wire_fact "unexpanded name; allowed: " suite-run "spell each suite literally" "$2")" \
        "spell each suite literally" \
        "The name as read: $1

This command names its suite with a shell variable, and this wall reads your command
text BEFORE the shell expands it — so the name never resolves to a suite it can check
against your budget. It may well be on it; nothing here can tell.

Spell the suite literally, one per call:
    bash tests/alpha.test.sh
    bash tests/beta.test.sh

On the budget: ${2:-(nothing — this brief declared Suites: none)}"
      return 2 ;;
  esac
  fold_block exit2 suite-run \
    "$(_budget_wire_fact "allowed: " suite-run "run only the budgeted suites" "$2")" \
    "run only the budgeted suites" \
    "This is a BUDGET arm, not a safety wall: an extra suite run breaks nothing, it spends
forty minutes of a machine nobody else can use. The set was recorded on this agent's
roster row at dispatch, from the files its brief declared.

On the budget: ${2:-(nothing — this brief declared Suites: none)}
You asked for: $1

Run only what is on it. If the change genuinely reaches further than the brief said,
say so in your report and let the orchestrator widen the brief — a wider instrument is
its decision to make, and it is the one holding the one-regression budget for the run."
  return 2
}

# THE READING IS SCOPED TO THIS REPOSITORY. `$BIONIC_ROOT` is what turns "a file named
# x.test.sh" into "this row's suite x.test.sh" (critic K-2). The library answers one CLAIM
# per suite-class segment: `file` with the suite basename, for the shell suites this repo
# budgets by, or `run` with the collapsed command, for a segment that runs a suite without
# naming one of them — `pytest`, `npm test`, `npx jest`. Both carry the run beside the
# target, so this loop can ask each of the row's two statements its own question.
#
# `set -f` IS GONE WITH THE SPLIT IT PROTECTED (it guarded `for _target in $_TARGETS`
# against a target carrying a glob metacharacter — `bash tests/*.test.sh` reads as the
# literal `*.test.sh`, review-a A-7b). `read` neither word-splits on anything but the tab
# nor globs, so the metacharacter arrives literal with no process state touched at all —
# which is the better answer to T23's finding that five walls share one shell. The sibling
# site at hooks/dispatch-preflight.sh still splits and still guards.
_CLAIMS=$(cmd_suite_claims "$COMMAND" "$BIONIC_ROOT")
while IFS=$'\t' read -r _kind _target _run; do
  [ -n "$_kind" ] || continue

  # ---------- THE FULL TREE, FIRST AND FAIL-CLOSED ----------
  #
  # AHEAD OF THE DECLARED RUNS, and that order is the whole of the one-regression rule.
  # `tests/run.sh` is counted at dispatch by `regression_rows()`, which reads the `run.sh`
  # token in `suites_allowed=` and nothing else — so a brief that declared the full tree
  # under `Re-executes:` instead would be uncounted there AND admitted here, and one
  # spelling would spend a budget the standing ruling caps at one per run. The full tree
  # goes on a row that NAMES it, in the field the counter reads.
  if [ "$_kind" = "file" ] && [ "$_target" = "run.sh" ]; then
    # AC-21: "tests/run.sh is refused unless the row carries it."
    case " $SUITES_ALLOWED " in
      *" run.sh "*) continue ;;
    esac
    # THE SPELLING THAT SPENDS THE BUDGET, NAMED (wave-20 T4; REQ-7, D7; triage-B B1a). The
    # refusal used to name the budget and not the command shape that spends it, so a writer
    # who reached for `tests/run.sh --one <suite>` learned only that it was refused. The
    # first budgeted suite, spelled the one way this arm admits, is the remedy; with no suite
    # on the row the slot stays a slot.
    _ft_first="${SUITES_ALLOWED%% *}"
    fold_block exit2 suite-run \
      "$(_budget_wire_fact "full tree refused; allowed: " suite-run "run your brief's suites" "$SUITES_ALLOWED")" \
      "run your brief's suites" \
      "This is a BUDGET arm, not a safety wall. One regression means one: the whole tree is
proved once per run, by one dispatched runner whose row carries tests/run.sh, at
integration close. A second full run costs forty minutes and proves what the first one
already did.

On the budget: ${SUITES_ALLOWED:-(nothing — no set was recorded for this agent)}

Run the suites your brief named instead, one call each, by the suite file itself:
    bash tests/${_ft_first:-<suite>.test.sh}
\`tests/run.sh --one\` is not that spelling: it is the runner's internal worker mode, fed a
queue only the runner itself builds, and it is the full-tree runner as far as this budget
is concerned. If the tree genuinely must be re-proved, say so in your report: the
orchestrator records the cause on the plan and dispatches the runner."
    return 2
  fi
  # ---------- WHAT THE BRIEF SAID IT WOULD RUN, RUNS (REQ-1 AC-1.5) ----------
  #
  # `re_executes=` is a DECLARATION the dispatch wall already admitted, so a command that
  # matches one exactly is a spend the orchestrator has already priced. It admits the runner
  # spelling and the shell spelling alike, because `Suites:` and `Re-executes:` are two
  # spellings of one statement (AC-1.2) and an arm honouring only one of them would refuse
  # at run time what the dispatch wall let through. It does NOT admit the full tree: that
  # arm ran above it, for the reason written there.
  if _run_is_declared "$_run" "$RE_EXECUTES"; then continue; fi

  # ---------- A RUNNER FORM IS HELD TO THAT DECLARATION (REQ-1 AC-1.5) ----------
  #
  # A suite-class command naming no file this repo budgets by used to pass in silence, on
  # the reasoning that a repository bionic has no row about is not one this arm can speak
  # for. The measurement says otherwise (research R1 Q2): the arm was not standing aside,
  # it could not SEE the command — `pytest` and `npx jest` carried no target at all — so a
  # writer in a jest repository had a budget in name only, and `Suites: none` did not mean
  # what AC-1.7 says it means ("admitted at dispatch, every suite refused at run time").
  # The row's declared runs are the whole set for this spelling: `suites_allowed=` holds
  # shell-suite basenames and a run can never be on it, so there is no second set to ask.
  #
  # THE FAIL DIRECTION IS UNCHANGED. A row with NEITHER statement — no `suites_allowed=`
  # key and no declared runs — is a bookkeeping failure the agent did not cause, and a
  # named run passes in silence exactly as a named suite does.
  if [ "$_kind" != "file" ]; then
    [ "$BUDGET_STATED" = yes ] || [ -n "$RE_EXECUTES" ] || continue
    # BOTH STATEMENTS ON THE WIRE, runs first: the reader ran a runner form, so the runs
    # are the half of the budget that can answer it.
    _shown="$RE_EXECUTES"
    [ -z "$SUITES_ALLOWED" ] || _shown="${_shown:+$_shown }$SUITES_ALLOWED"
    budget_refuse "$_run" "$_shown"
    return 2
  fi

  [ "$BUDGET_STATED" = yes ] || continue
  case " $SUITES_ALLOWED " in
    *" $_target "*) : ;;
    *) budget_refuse "$_target" "$SUITES_ALLOWED"; return 2 ;;
  esac
done <<< "$_CLAIMS"

# ---------- ARM R (REQ-3, D4): repair a suite timeout below the harness maximum ----------
#
# NOT A SAFETY WALL — A REPAIR. `agents-src/blocks/survival.md` names two minutes as the
# default when a caller sets no `timeout` at all, and that default kills a real suite
# before it finishes: the evidence a dispatched task exists to produce is a truncated log,
# the same failure ARM 1 exists for by a different door. The fix costs nothing to apply and
# nothing to undo — it changes how long the caller waits, never what the command does
# (record/wave-13-fixit-180/prototype-hook-rewrite-timeout.md: the harness honors a
# PreToolUse hook's `updatedInput`, measured on CLI 2.1.270) — so this arm corrects the call
# rather than refusing it.
#
# BOTH GATES THIS ARM NEEDS ARE ALREADY PAID: `$ACTOR` is non-empty (the partition above,
# repeated right before ARM 1) and `cmd_class "$COMMAND"` = suite (just above ARM 1). A
# main-thread call never reaches here — it returned at the partition, long before ARM 1.
#
# LAST OF THE THREE, AND THAT ORDER IS THE RULE (T13, A-orch-39). A REFUSED CALL IS NEVER
# REPAIRED. This arm shipped (T3) between ARM 1 and ARM 2, and it `return`s the moment it
# stages a rewrite — so a subagent suite call carrying no `timeout` never reached the budget
# arm at all, and an OFF-BUDGET suite was repaired and allowed instead of refused. A-T3.1
# named the interaction and did not close it; `tests/agent-context-guard.test.sh` §G9 caught
# it at this wave's Step-5 floor.
#
# ORDER, NOT A FLAG, IS WHAT ENFORCES IT. `fold.sh` already drops a staged `updatedInput`
# whenever anything blocked (`bionic_fold`'s `BIONIC_FOLD_BLOCKS -eq 0` branch is its only
# reader), so letting this arm stage and fall through into ARM 2 would get the STDOUT half
# right on its own — but measured, the other two halves still escape: `log_finding` below
# has already printed `suite-timeout repaired` on stderr and written the audit line by the
# time the fold decides, and neither is recallable. A repair that leaves its trace on a call
# the same function then refuses is the defect wearing a smaller coat. Running ARM 2 first
# means the refusing path never enters this arm, on any of the three wires.
#
# NOTHING ABOVE MOVED. ARM 1 is still first (a backgrounded suite is refused whether or not
# it is on the budget, and whether or not its timeout would have been raised), and the
# partition is untouched. An ON-BUDGET call with an absent or too-small `timeout` is repaired
# exactly as it was — reaching here is now proof the budget arm had nothing to say.
#
# `.tool_input.timeout` IS READ RAW, not through the small cache table `bionic_jq` answers
# from memory (context.sh:240-257) — this key is not one of the cached ones, so the call
# falls through to that function's generic `jq -r '<path> // empty'` arm, same as any other
# not-yet-cached field. ABSENT, NON-NUMERIC AND UNDER THE MAX ALL REPAIR THE SAME WAY: a
# caller that named no ceiling and one that named a low one are both a worker about to be
# killed before its suite finishes, and the fix is identical either way.
local _BSG_MAX _BSG_TIMEOUT _BSG_UPDATED
_BSG_MAX="${BASH_MAX_TIMEOUT_MS:-600000}"
_BSG_TIMEOUT=$(bionic_jq '.tool_input.timeout')
case "$_BSG_TIMEOUT" in
  ''|*[!0-9]*) _BSG_TIMEOUT="" ;;
esac
if [ -z "$_BSG_TIMEOUT" ] || [ "$_BSG_TIMEOUT" -lt "$_BSG_MAX" ]; then
  # BUILT FROM THE ORIGINAL `tool_input`, WHOLE — `command`, `run_in_background` (`false`
  # here; ARM 1 above already returned on `true`) and anything else the call carried ride
  # through unchanged, so the repair is meaning-preserving by construction rather than by a
  # field list this arm has to keep in step with the Bash tool's own schema. `$BIONIC_INPUT`
  # is read directly, not through `bionic_jq`: that helper appends `// empty` to whatever
  # filter it is given and returns text through `-r`, neither of which this arm wants for
  # building an object.
  _BSG_UPDATED=$(printf '%s' "${BIONIC_INPUT:-}" | jq -c --argjson t "$_BSG_MAX" \
    '.tool_input + {timeout: $t}' 2>/dev/null)
  if [ -n "$_BSG_UPDATED" ]; then
    # STAGED, NEVER PRINTED DIRECTLY (fold.sh's contract, header comment above `wall_libs`
    # earlier in this file). This function shares one shell and one stdout with four other
    # walls; `fold_update_input` is the seam fold.sh gained (T3, D4) so this object and
    # farm-out-reminder's `additionalContext` can both reach the wire without one silently
    # overwriting the other — see fold.sh `_fold_emit_context`. `return 1`, not `return 0`:
    # the fold discards a function's staged text on a silent `return 0`, so a repair must
    # answer as an advisory to survive the fold at all, even though nothing here is refused.
    fold_update_input "$_BSG_UPDATED"
    # `log_finding`'s CHANNEL, SUBJECT AND ROOT (root.sh:251-267) ARE NOT GLOBAL DEFAULTS —
    # they are DECLARED LAZILY, as a side effect of `_eg_body` (this file's evidence-gate
    # body, above) reaching its own commit-class validation far enough to need them. A
    # suite command never takes that path, so `bionic_finding_root` is undefined in this
    # process by the time this arm runs (measured: calling `log_finding` without this guard
    # fails `bionic_finding_root: command not found`, from inside the `$(…)` `log_finding`
    # itself swallows — the stderr line this arm exists to print still appears, but the
    # audit-file half silently never writes, plus a stray error a reader would have to
    # explain). Declared here, the same way hooks/canonical-sdlc-governing-skill.sh declares
    # its own copy at its own top level, naming THIS wall rather than leaving whatever
    # evidence-gate last set (or never set) on a finding it did not produce.
    BIONIC_FINDING_CHANNEL="background-suite-guard"
    BIONIC_FINDING_SUBJECT="$COMMAND"
    bionic_finding_root() { printf '%s' "$BIONIC_ROOT"; }
    log_finding suite-timeout "repaired from=${_BSG_TIMEOUT:-absent} to=$_BSG_MAX agent=$ACTOR"
    return 1
  fi
  # `jq` BUILT NOTHING — a payload shape no earlier reader in this hook caught either.
  # Falling through to this function's own `return 0` is the same unreachable this file
  # leaves every other builder failure to: `jq` is confirmed on PATH before this hook
  # sources anything at all (hooks/bash-walls.sh's own preamble), so this line is not
  # expected to run. The call is allowed UNREPAIRED, never refused — it already passed the
  # budget arm above, and a repair this arm could not build is not a reason to block.
fi

return 0
}
