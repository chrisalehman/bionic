# git-argv.sh — read a Bash command line the way git reads it.
#
# WHAT IT OWNS. One question, for every wall that has to answer "is this
# command a `git <something>`, and what is it doing": how a shell command line
# decomposes into segments and argv words. Two hooks source it —
# hooks/protect-main.sh (is this a push, where to, and from where) and
# hooks/canonical-sdlc-evidence-gate.sh (is this a commit). It is the SSoT for
# that reading; neither hook carries a regex over the raw command any more.
#
# WHY IT EXISTS. Until 1.3.2 both hooks matched the command as TEXT: split on
# && || ; AND newlines, delete every quoted span, then grep for `git push` /
# `git commit` as adjacent words. Measured, that read eleven real pushes to
# main as harmless (`git -C /tmp/r push origin main`, `git push origin "main"`,
# `git push origin feature:refs/heads/main`, ...) and read a heredoc body that
# merely MENTIONED a push as a push (research-b3-b5-b9-cmd-parsing.md §2).
# Both failures come from the same place: a command line is not text, it is
# words, and only the shell's own rules say where the words are.
#
# THE READING, in order. Heredoc bodies come off FIRST — a body can contain
# anything, including unbalanced quotes, so nothing else can be trusted until
# it is gone. Then the remainder is tokenised with single quotes, double quotes
# and backslash escapes honoured, splitting into segments at the operators
# (newline ; & | && ||) that are OUTSIDE quotes. Each segment is one argv.
# Grouping parentheses end a segment too, so `(git push …)` is read. Then, per
# segment, everything before the real argv[0] comes off: shell openers (`{`,
# `then`, `do`, `else`, `!`) and command-taking prefixes (`sudo`, `time`,
# `nice`, `xargs`, `ssh <host>`, `find … -exec`, `env`, `nohup`, `command`,
# `exec`) — see _git_argv_skip. Finally a `sh -c '<string>'` or `eval
# '<string>'` segment is re-read, its string expanded into more segments, to
# depth 2 — see git_argv_expand, which is what the walls iterate.
# Ported from bionic-omni bundle/policies/_shell.py @ 29fc09e, whose Python
# equivalent has been in production there; the port is behavioural, not
# line-by-line — the destination parsing that file keeps in its callers
# (protect_main.py `_destination`/`_refspecs`/`_forces`) is `git_push_targets`
# here.
#
# WHY QUOTES ARE HONOURED RATHER THAN DELETED. Deleting `"main"` leaves
# `git push origin` — a real push whose destination has vanished. Honouring it
# leaves the word `main`. The same rule going the other way is what makes
# `echo 'git push origin main'` harmless: the quoted span is ONE token, and
# argv[0] is `echo`, so no wall looks further. Classification is by argv
# POSITION, never by whether some substring appears somewhere.
#
# FAIL-CLOSED BY CONTRACT. A wall that cannot load this file must REFUSE, not
# allow (Chris, D1 2026-08-30). Each hook's loader is a few lines long and says
# so; the proof that both obey it is tests/git-argv.test.sh Section 2, which
# renames this file away in a copy of the shipped tree and demands two
# refusals.
#
# bash 3.2 (macOS /bin/bash): no associative arrays, no mapfile, no `${x^^}`.
# Token lists travel as US-separated (\037) strings and are unpacked with
# `set --` inside functions, because `${arr[@]}` on an empty array is an
# unbound-variable error under `set -u` in bash before 4.4 — and the evidence
# gate runs `set -u`.
# [WALL: tests/git-argv.test.sh]

# Idempotent: both hooks may source this, and a test may source it again.
if [ -n "${GIT_ARGV_LIB_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
GIT_ARGV_LIB_LOADED=1

# The unit separator. Chosen because no real command line contains one, and
# because it survives `set -- $var` with IFS set to it (a space or newline
# would not: quoted tokens contain both).
GIT_ARGV_US=$'\037'

# The scanner. It runs as ONE awk process per command — a bash character loop
# over `${s:i:1}` is quadratic in practice, and protect-main.sh runs on every
# Bash tool call in the session.
#
# The program is a quoted heredoc, so apostrophes inside it are safe. That is
# deliberate and it is the reason it is not the usual single-quoted string:
# the heredoc-tag pattern has to name both quote characters. (See
# .claude/rules/hook-authoring.md — an apostrophe inside a SINGLE-QUOTED awk
# program terminates the shell quote and takes the suite with it.)
#
# `read -d ''` returns 1 at EOF by design; the `|| true` keeps a caller
# running under `set -e` alive.
GIT_ARGV_AWK=""
IFS= read -r -d '' GIT_ARGV_AWK <<'GITARGVAWK' || true
BEGIN {
  US = sprintf("%c", 31)
  RS2 = sprintf("%c", 30)
  # META MODE (GIT_ARGV_META=1): each printed segment is prefixed by the
  # grouping depth it ran at and the operator that ended it — see emit().
  meta = (ENVIRON["GIT_ARGV_META"] == "1")
  cmd = ENVIRON["GIT_ARGV_CMD"]
  # Both separators are stripped from the INPUT so neither can be injected:
  # a literal one inside a word would split a line where a reader does not
  # expect it (critic pass 2, F1: `cd x<RS>; git push origin main` hid the
  # push from every block).
  gsub(US, " ", cmd)
  gsub(RS2, " ", cmd)
  gsub(/\r/, "", cmd)

  # ---- 1. remove heredoc bodies -------------------------------------------
  # A body is everything after a `<<TAG` line up to the line that is exactly
  # TAG (leading whitespace tolerated, which also covers `<<-`). Several
  # heredocs may open on one line; they close in the order they opened, so the
  # tags are a queue.
  n = split(cmd, L, "\n")
  body = ""
  qn = 0
  qi = 0
  for (i = 1; i <= n; i++) {
    line = L[i]
    if (qi < qn) {
      t = line
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      if (t == TAG[qi + 1]) {
        qi++
        if (qi >= qn) { qn = 0; qi = 0 }
      }
      continue
    }
    s = strip_heredoc_openers(line)
    body = body s "\n"
  }

  # ---- 2. segments and argv words -----------------------------------------
  tok = ""
  have = 0
  seg = ""
  segn = 0
  gdepth = 0
  Ln = length(body)
  i = 1
  while (i <= Ln) {
    c = substr(body, i, 1)

    if (c == "\\") {
      nx = substr(body, i + 1, 1)
      if (nx == "" || nx == "\n") { i += 2; continue }
      tok = tok nx
      have = 1
      i += 2
      continue
    }

    if (c == "'") {
      j = index(substr(body, i + 1), "'")
      if (j == 0) { tok = tok substr(body, i + 1); have = 1; break }
      tok = tok substr(body, i + 1, j - 1)
      have = 1
      i = i + j + 1
      continue
    }

    if (c == "\"") {
      i++
      while (i <= Ln) {
        c2 = substr(body, i, 1)
        if (c2 == "\\") {
          n2 = substr(body, i + 1, 1)
          if (n2 == "\n") { i += 2; continue }
          tok = tok n2
          i += 2
          continue
        }
        if (c2 == "\"") { i++; break }
        tok = tok c2
        i++
      }
      have = 1
      continue
    }

    # A comment: `#` where a word would start, through the end of the line.
    # The newline is left for the boundary rule below. A `#` inside a word
    # (`foo#bar`, `${#x}`) or inside quotes is a character.
    if (c == "#" && !have) {
      while (i <= Ln && substr(body, i, 1) != "\n") i++
      continue
    }

    # Word separators. Redirection arrows are separators, not segment
    # boundaries: `git push origin main>log` must still yield `main`.
    if (c == " " || c == "\t" || c == "<" || c == ">") {
      if (have) { seg = flush_tok(seg, tok, segn); segn++; tok = ""; have = 0 }
      i++
      continue
    }

    # Segment boundaries. The operator is read whole (`&&` is not `&`,
    # `||` is not `|`) and consumed whole. In meta mode an operator that
    # closes NO segment is still reported, as an empty one: the `||` or `&`
    # after a `)` belongs to the group it follows, and a reader of moves
    # has to see it (critic pass 2, F2-F4).
    if (c == "\n" || c == ";" || c == "&" || c == "|") {
      if (have) { seg = flush_tok(seg, tok, segn); segn++; tok = ""; have = 0 }
      term = (c == "\n") ? "nl" : c
      if ((c == "&" || c == "|") && substr(body, i + 1, 1) == c) { term = c c; i++ }
      if (segn) { emit(seg, gdepth, term) }
      else if (meta) { emit("", gdepth, term) }
      seg = ""
      segn = 0
      i++
      continue
    }

    # GROUPING PARENTHESES are boundaries too (R-12). `(git push origin main)`
    # is a subshell whose first word is `git`, and bash needs no space after
    # the paren — so unless the paren ends a segment here, the token reads
    # `(git` and no wall recognises it. A `(` preceded by `$`, `<` or `>` is
    # NOT grouping: it opens a command substitution or a process substitution,
    # which stay out of scope, so their closing `)` (depth 0) stays a
    # character and `$(git push origin main)` keeps reading as one word.
    if (c == "(" && !have) {
      pv = (i > 1 ? substr(body, i - 1, 1) : "")
      if (pv != "$" && pv != "<" && pv != ">") {
        if (segn) { emit(seg, gdepth, "(") }
        seg = ""; segn = 0; gdepth++
        i++
        continue
      }
    }
    if (c == ")" && gdepth > 0) {
      if (have) { seg = flush_tok(seg, tok, segn); segn++; tok = ""; have = 0 }
      if (segn) { emit(seg, gdepth, ")") }
      seg = ""; segn = 0; gdepth--
      i++
      continue
    }

    tok = tok c
    have = 1
    i++
  }
  if (have) { seg = flush_tok(seg, tok, segn); segn++ }
  if (segn) { emit(seg, gdepth, "eof") }
  exit 0
}

# Prints one finished segment. In meta mode the line is
# `<depth> RS <term> RS <segment>`: the grouping depth the segment ran at
# (0 outside any `( … )`) and the operator that ended it — `;`, `nl`, `&&`,
# `||`, `&`, `|`, `(`, `)` or `eof`. RS is the record separator (\036), the
# same argument as US: no real command line contains one, and the input is
# scrubbed of both so none can be made to.
function emit(s, depth, term) {
  if (!meta) { print s; return }
  print depth RS2 term RS2 s
}

# Finds every heredoc opener on ONE line, appends its tag to the TAG queue, and
# returns the line with the openers removed — so the tag never survives as a
# phantom argv word (`cat > f <<NOTE` is `cat` and `f`).
#
# QUOTE STATE IS THE WHOLE POINT (review-b B-1, 2026-08-30). The scan this
# replaced was a bare `match()` with no quote tracking, so
# `echo "see <<EOF for the heredoc format"` opened a phantom body that swallowed
# every following line — a real push on the next line walked through 1.3.2 and
# was blocked by 1.3.1. A `<<` inside a quoted span is text the command
# receives, never a redirection.
#
# This is the same reading as cmd-class.sh:heredoc_tag, in the same language,
# deliberately not a third shared file: a shared awk snippet would put a THIRD
# fail-closed load path in front of four walls (D1 requires each to name the
# library it could not read). The two are pinned against each other instead, by
# tests/git-argv.test.sh Section 1d. The one difference is scope, not reading:
# this collects EVERY opener on the line, because several heredocs may open at
# once and close in the order they opened; cmd-class needs only the first.
#
# A here-STRING (<<<) has no body. It becomes whitespace so its third angle
# bracket cannot look like a tag introducer; the operand stays a word.
function strip_heredoc_openers(s,   i, L, c, q, j, t, ch, out) {
  L = length(s)
  q = ""
  out = ""
  i = 1
  while (i <= L) {
    c = substr(s, i, 1)
    if (q != "") {
      out = out c
      if (c == q) { q = "" }
      else if (c == "\\" && q == "\"") { i++; out = out substr(s, i, 1) }
      i++
      continue
    }
    if (c == "'" || c == "\"") { q = c; out = out c; i++; continue }
    if (c == "\\") { out = out c; i++; out = out substr(s, i, 1); i++; continue }
    if (c == "<" && substr(s, i + 1, 1) == "<") {
      if (substr(s, i + 2, 1) == "<") { out = out "   "; i += 3; continue }
      j = i + 2
      if (substr(s, j, 1) == "-") j++
      while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
      ch = substr(s, j, 1)
      if (ch == "'" || ch == "\"") j++
      t = ""
      while (j <= L) {
        c = substr(s, j, 1)
        if (c ~ /[A-Za-z0-9_]/) { t = t c; j++ } else break
      }
      if (t != "") {
        if ((ch == "'" || ch == "\"") && substr(s, j, 1) == ch) j++
        qn++
        TAG[qn] = t
        out = out " "
        i = j
        continue
      }
      out = out "<"
      i++
      continue
    }
    out = out c
    i++
  }
  return out
}

# Appends one token to the accumulating segment. A token can carry a newline
# (it came out of a quoted span); the output format is one segment per line, so
# fold it to a space.
function flush_tok(acc, t, count,   US2) {
  US2 = sprintf("%c", 31)
  gsub(/\n/, " ", t)
  if (count == 0) { return t }
  return acc US2 t
}
GITARGVAWK

# git_argv_segments <command>
#
# Prints one line per segment; the argv words of a segment are separated by
# GIT_ARGV_US. Empty segments are not printed.
git_argv_segments() {
  GIT_ARGV_CMD="$1" awk "$GIT_ARGV_AWK"
}

# The record separator: between the fields of a meta line and, in
# git_argv_expand_moves, between a directory and its segment. Chosen for the
# reason GIT_ARGV_US is.
GIT_ARGV_RS=$'\036'

# _git_argv_segments_meta <command>
#
# git_argv_segments with each line prefixed `<depth> RS <term> RS` — the
# grouping depth the segment ran at and the operator that ended it (see the
# scanner's emit()). The reader that needs to know whether a `cd` moved the
# shell for the segments after it.
_git_argv_segments_meta() {
  GIT_ARGV_META=1 GIT_ARGV_CMD="$1" awk "$GIT_ARGV_AWK"
}

# _git_argv_skip <segment-line>
#
# THE SUPERSET RULE (R-12, critic C-1 2026-08-30). Sets GIT_ARGV_REST to the
# segment with everything BEFORE the real argv[0] removed. Always returns 0.
#
# The 1.3.1 walls this library replaced matched `git push` after ANY
# whitespace. Reading argv[0] of a `; && || | &` segment is narrower than that,
# not wider: every construct that opens a command without one of those
# separators (`(`, `{`, `then`, `do`, `else`, `!`) and every command that TAKES
# another command (`sudo`, `time`, `nice`, `xargs`, `ssh`, `find -exec`) leaves
# git at argv[1..n]. Nine push spellings 1.3.1 refused walked through 1.3.2
# before this function existed (critic-step6.md §C-1).
#
# Two kinds of word are removed, in one loop so they compose (`then sudo git
# push`, `( time git push )`):
#   OPENERS — a grouping/keyword word that is not a command at all. `(` and `)`
#     mostly never reach here (the scanner makes grouping parens segment
#     boundaries) but `{`, `}` and the reserved words do, since bash separates
#     them with `;` or whitespace only.
#   PREFIXES — a command whose own argument is the next command. Each is
#     removed WITH its options, and the option that takes a separate value word
#     eats that too, or the value becomes a phantom argv[0]. `ssh` additionally
#     eats one non-option word: the host.
# `find` is the odd one: the command it runs is after `-exec`/`-execdir`, not
# at argv[1], so the scan skips to there and a `find` with no -exec yields
# nothing — which is what keeps `find . -name 'git'` a non-command.
#
# OUT OF SCOPE, deliberately: `$(...)` and backticks. Their contents are a
# command the shell runs, but reading them needs a nesting tokeniser rather
# than a prefix skip, and no AC asks for it (see the report's Assumptions).
_git_argv_skip() {
  local _line="$1" _oldifs="$IFS" _hadf=0 _n=0 _w

  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $_line
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f

  while [ $# -gt 0 ]; do
    case "$1" in
      '('|')'|'{'|'}'|'!'|then|else|elif|do|done|fi|if|while|until|env|command|nohup|exec)
        shift
        ;;
      time)
        shift
        if [ "${1:-}" = "-p" ]; then shift; fi
        ;;
      timeout|gtimeout|*/timeout|*/gtimeout)
        # `timeout [-s SIG] [-k DUR] <duration> <command>` — the duration is a
        # bare word that would otherwise read as argv[0]. cmd-class.sh has
        # stripped this since it was written; git-argv did not (review-a S-1).
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -s|-k|--signal|--kill-after) shift; if [ $# -gt 0 ]; then shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        case "${1:-}" in
          [0-9]*) shift ;;
        esac
        ;;
      nice)
        shift
        case "${1:-}" in
          -n|--adjustment) shift; if [ $# -gt 0 ]; then shift; fi ;;
          --adjustment=*|-[0-9]*|--[0-9]*) shift ;;
        esac
        ;;
      sudo|doas)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -u|-g|-p|-U|-C|-r|-t|-h|-D|-R) shift; if [ $# -gt 0 ]; then shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      xargs)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -I|-i|-n|-L|-P|-s|-E|-a|-d|--replace|--max-args|--max-procs|--max-lines|--arg-file|--delimiter|--eof)
              shift; if [ $# -gt 0 ]; then shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      ssh)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -o|-p|-i|-l|-F|-L|-R|-D|-b|-c|-e|-m|-O|-Q|-S|-W|-w|-J|-E|-B|-I) shift; if [ $# -gt 0 ]; then shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        if [ $# -gt 0 ]; then shift; fi   # the host
        ;;
      find|*/find)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -exec|-execdir|-ok|-okdir) shift; break ;;
            *) shift ;;
          esac
        done
        ;;
      *=*)
        # A leading assignment only — `--git-dir=x` is not one, and neither is
        # anything whose name is not an identifier.
        case "${1%%=*}" in
          ""|*[!A-Za-z0-9_]*) break ;;
          *) shift ;;
        esac
        ;;
      *) break ;;
    esac
  done

  GIT_ARGV_REST=""
  for _w in "$@"; do
    if [ "$_n" -eq 0 ]; then GIT_ARGV_REST="$_w"; else GIT_ARGV_REST="$GIT_ARGV_REST$GIT_ARGV_US$_w"; fi
    _n=$((_n + 1))
  done
  return 0
}

# git_argv_parse <segment-line>
#
# Reads ONE segment (a line from git_argv_segments / git_argv_expand). Returns
# 0 and sets GIT_SUB (the git subcommand), GIT_ARGS (its arguments,
# US-separated) and GIT_C_DIRS (the values of its `-C <dir>` options, in
# order, US-separated) when the segment invokes git; returns 1 otherwise.
#
# Skipped before argv[0]: whatever _git_argv_skip removes — leading VAR=value
# assignments, shell openers and command-taking prefixes — so
# `GIT_SSH_COMMAND=ssh git push ...` and `sudo git push ...` both read as a
# push. Skipped after it: git's own global options. The value-taking ones are
# named so their VALUE is consumed too; every other `-...` word is dropped on
# its own, which is what makes `git --no-pager commit` a commit. Same shape as
# the GIT alternation in _shell.py:35-39.
#
# `-C <dir>` is the one global option whose value is KEPT, not just consumed:
# it says where the command runs, and protect-main's Block 3 judges a push by
# the branch checked out THERE. `git -C a -C b` is a then b (each hop is
# relative to the one before), so the list keeps git's order and a caller
# hands it back to git as-is.
git_argv_parse() {
  GIT_SUB=""
  GIT_ARGS=""
  GIT_C_DIRS=""
  local _oldifs="$IFS" _hadf=0 _n=0 _a

  _git_argv_skip "$1"
  [ -n "$GIT_ARGV_REST" ] || return 1

  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $GIT_ARGV_REST
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f

  [ $# -gt 0 ] || return 1
  case "$1" in
    git|*/git) shift ;;
    *) return 1 ;;
  esac

  while [ $# -gt 0 ]; do
    case "$1" in
      -C)
        shift
        if [ $# -gt 0 ]; then
          if [ -z "$GIT_C_DIRS" ]; then GIT_C_DIRS="$1"; else GIT_C_DIRS="$GIT_C_DIRS$GIT_ARGV_US$1"; fi
          shift
        fi
        ;;
      -c|--namespace|--git-dir|--work-tree|--exec-path|--config-env|--super-prefix)
        shift
        if [ $# -gt 0 ]; then shift; fi
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done

  [ $# -gt 0 ] || return 1
  GIT_SUB="$1"
  shift
  for _a in "$@"; do
    if [ "$_n" -eq 0 ]; then GIT_ARGS="$_a"; else GIT_ARGS="$GIT_ARGS$GIT_ARGV_US$_a"; fi
    _n=$((_n + 1))
  done
  return 0
}

# git_argv_cd_dir <segment-line>
#
# Reads a segment that MOVES THE SHELL. Three answers:
#   0  a `cd <dir>` / `pushd <dir>` whose target this reader can name — the
#      directory is in GIT_CD_DIR;
#   2  a move whose target it cannot name: a bare `cd` (home), `cd -` (the
#      previous directory), `cd a b` (bash's substitution form), `popd`, a
#      bare `pushd` — GIT_CD_DIR is empty, and the directory in effect
#      before it is now STALE, so a caller must drop it;
#   1  not a move at all — `pushd -n` included, which only stacks.
# A variable rather than stdout, the way _git_argv_skip sets GIT_ARGV_REST:
# the caller reads every segment of every command, and a command
# substitution per segment is a fork per segment (critic pass 2, nit 2).
#
# A push runs where the shell IS, and the shell is wherever the last move
# before it went — `cd <repo>/.worktrees/x && git push origin x` is the
# worktree shape, and protect-main's Block 3 judges that push by the branch
# checked out in the worktree, not in the hook's own cwd. The same prefix skip
# as git applies, so `then cd x` and `command cd x` are moves too.
#
# Only ONE PLAIN WORD is a directory read. `cd`'s options take no value
# (`-L -P -e -@`) and `--` ends them. A leading `~` is the home directory:
# the scanner keeps the character the shell would have expanded. A target
# this reader keeps but the shell would have expanded further (`$VAR`,
# `$(…)`) is printed as written; git cannot read it, and the caller's
# fallback is its own cwd — the side that refuses.
git_argv_cd_dir() {
  local _oldifs="$IFS" _hadf=0 _d="" _verb=""
  GIT_CD_DIR=""

  _git_argv_skip "$1"
  [ -n "$GIT_ARGV_REST" ] || return 1

  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $GIT_ARGV_REST
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f

  [ $# -gt 0 ] || return 1
  _verb="$1"
  case "$_verb" in
    cd|pushd) shift ;;
    popd) return 2 ;;
    *) return 1 ;;
  esac

  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; break ;;
      -) break ;;
      -n) [ "$_verb" = "pushd" ] && return 1; shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done

  [ $# -eq 1 ] || return 2
  _d="$1"
  case "$_d" in
    ""|-) return 2 ;;
    "~") _d="$HOME" ;;
    "~/"*) _d="$HOME/${_d#\~/}" ;;
  esac
  GIT_CD_DIR="$_d"
  return 0
}

# git_argv_inner <segment-line>
#
# Prints the command STRING a runner segment would execute, and returns 0; on
# any other segment prints nothing and returns 1.
#
# Two runners, both taking one string: `sh|bash|zsh|dash|ksh -c '<string>'` and
# `eval '<string>'`. The scanner has already stripped the quotes, so the string
# arrives as one token and can be re-read by git_argv_segments as-is. The `-c`
# match is `-c` or a short cluster ENDING in c (`-lc`, `-ec`) — never a long
# option that merely contains one, so `bash --norc -c '…'` still finds the
# real `-c`. cmd-class.sh's unwrap_runner is this same reading in awk; the two
# libraries were written in one wave and disagreed about it until R-12
# (critic-step6.md §C-5).
git_argv_inner() {
  local _oldifs="$IFS" _hadf=0 _b _out="" _n=0 _w

  _git_argv_skip "$1"
  [ -n "$GIT_ARGV_REST" ] || return 1

  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $GIT_ARGV_REST
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f

  [ $# -gt 0 ] || return 1
  _b="${1##*/}"
  case "$_b" in
    sh|bash|zsh|dash|ksh|ash)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|-[!-]*c)
            shift
            [ $# -gt 0 ] || return 1
            printf '%s' "$1"
            return 0
            ;;
          -*) shift ;;
          *) return 1 ;;
        esac
      done
      return 1
      ;;
    eval)
      shift
      [ $# -gt 0 ] || return 1
      for _w in "$@"; do
        if [ "$_n" -eq 0 ]; then _out="$_w"; else _out="$_out $_w"; fi
        _n=$((_n + 1))
      done
      printf '%s' "$_out"
      return 0
      ;;
  esac
  return 1
}

# git_argv_expand <command>
#
# The segment list every wall reads: git_argv_segments of the command, PLUS the
# segments of any `sh -c` / `eval` string inside it, recursively, to depth 2.
# Depth 2 because one wrapper is the shape a model writes and two is already a
# deliberate evasion; unbounded recursion would make a self-referential string
# loop forever.
git_argv_expand() {
  _git_argv_expand_at "$1" 0
}

_git_argv_expand_at() {
  local _cmd="$1" _depth="$2" _line _inner
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    printf '%s\n' "$_line"
    if [ "$_depth" -lt 2 ]; then
      _inner="$(git_argv_inner "$_line")" || continue
      [ -n "$_inner" ] || continue
      _git_argv_expand_at "$_inner" $((_depth + 1))
    fi
  done <<< "$(git_argv_segments "$_cmd")"
  return 0
}

# git_argv_expand_moves <command>
#
# git_argv_expand for the wall that needs to know WHERE each segment runs:
# every line is `<dir> RS <segment>`, where <dir> is the directory the shell
# is in when that segment runs — empty for "wherever the caller is". Same
# lines, same order, same depth-2 re-reading of `sh -c` / `eval` strings.
#
# THE SHELL'S OWN RULES, and nothing looser (critic, 2026-09-02, two passes:
# a reading that took every `cd` as a move opened `cd wt & git push` and
# `( cd wt ) && git push` from main; one that cancelled a move only on its
# own segment opened `cd wt && true & git push`, `( cd wt ); ( git push )`
# and `cd main || cd wt; git push`). A `cd` moves the segments after it only
# when the shell itself keeps the move:
#   `;`, `&&`, newline   the move holds; `;` and newline also END the and-or
#                        list, so the list's starting directory moves up;
#   `||`                 the NEXT segment runs only if this one FAILED. A cd
#                        is taken to succeed, so that segment is judged where
#                        the shell was before the last move and its own
#                        effects are not applied; a chain of `||` stays
#                        skipped (`cd a || cd b || cd c` leaves the shell in
#                        a); the move holds again after `;` (`cd x || exit 1;
#                        git push`). The same rule after a `)`: the group is
#                        taken to succeed;
#   `&`                  backgrounds the WHOLE and-or list before it: every
#                        move since the list began is discarded;
#   `|`                  a pipeline binds tighter than && and ||, and each of
#                        its elements is a subshell: the element before the
#                        `|` and the one after it move nothing; the rest of
#                        the list is unaffected;
#   `( … )`              a group starts where its parent is, and every move
#                        made inside it ends with it;
#   `sh -c '…'`          a child shell starting where its parent is, whose
#                        moves never come back;
#   `eval '…'`           the CURRENT shell: its moves do come back.
# A move the reader cannot name (git_argv_cd_dir returns 2) EMPTIES the
# directory: the shell went somewhere, so what was in effect is stale, and
# the caller's own cwd is the side that refuses. The same is true of a
# target the scanner keeps as written (`cd "$WT"`): the caller cannot read
# it and falls back.
#
# NOT MODELLED, deliberately: conditions. `if false; then cd wt; fi` reads
# as a move because the reader does not evaluate `false` — the same line
# the library draws for `$(…)`. A wall that must refuse it has Block 1.
git_argv_expand_moves() {
  _git_argv_moves_at "$1" "" 0
}

# Sets GIT_ARGV_MOVES_END to the directory the shell is in when the command
# finishes — what an `eval` hands back to its caller.
GIT_ARGV_MOVES_END=""
_git_argv_moves_at() {
  local _cmd="$1" _cur="$2" _depth="$3"
  local _line _d _rest _term _seg _at _inner _rc _kind
  local _stack="" _lstack="" _sdepth=0 _base="$2" _skip=0 _skipat="" _skipset=0 _pipe=0
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _d="${_line%%"$GIT_ARGV_RS"*}"
    _rest="${_line#*"$GIT_ARGV_RS"}"
    _term="${_rest%%"$GIT_ARGV_RS"*}"
    _seg="${_rest#*"$GIT_ARGV_RS"}"

    # Entering a group inherits the current directory and starts a list
    # there; leaving one restores what the parent had, list start included.
    # The stacks are US-joined strings (bash 3.2). An operator that follows
    # a `)` arrives as an empty segment at the parent's depth, which is what
    # pops the group before the operator is applied.
    while [ "$_d" -gt "$_sdepth" ]; do
      _stack="$_stack$GIT_ARGV_US$_cur"
      _lstack="$_lstack$GIT_ARGV_US$_base"
      _base="$_cur"
      _sdepth=$((_sdepth + 1))
    done
    while [ "$_d" -lt "$_sdepth" ]; do
      _cur="${_stack##*"$GIT_ARGV_US"}"; _stack="${_stack%"$GIT_ARGV_US"*}"
      _base="${_lstack##*"$GIT_ARGV_US"}"; _lstack="${_lstack%"$GIT_ARGV_US"*}"
      _sdepth=$((_sdepth - 1))
    done

    # Where this segment runs, and whether its effects count. A segment
    # after `||` is judged where the shell was before the last move and
    # changes nothing; a pipeline element changes nothing either.
    _at="$_cur"
    if [ "$_skip" -eq 1 ]; then _at="$_skipat"; fi
    [ -z "$_seg" ] || printf '%s%s%s\n' "$_at" "$GIT_ARGV_RS" "$_seg"

    if [ -n "$_seg" ]; then
      _kind=""
      if [ "$_depth" -lt 2 ]; then
        if _inner="$(git_argv_inner "$_seg")" && [ -n "$_inner" ]; then
          _kind="child"
          _git_argv_skip "$_seg"   # git_argv_inner ran in a subshell; re-read argv[0] here
          case "${GIT_ARGV_REST%%"$GIT_ARGV_US"*}" in eval) _kind="eval" ;; esac
          _git_argv_moves_at "$_inner" "$_at" $((_depth + 1))
          if [ "$_kind" = "eval" ] && [ "$_skip" -eq 0 ] && [ "$_pipe" -eq 0 ] \
             && [ "$_term" != "|" ]; then
            _cur="$GIT_ARGV_MOVES_END"
          fi
        fi
      fi
      if [ -z "$_kind" ] && [ "$_skip" -eq 0 ] && [ "$_pipe" -eq 0 ] \
         && [ "$_term" != "|" ]; then
        git_argv_cd_dir "$_seg"; _rc=$?
        if [ "$_rc" -eq 0 ]; then _skipat="$_cur"; _skipset=1; _cur="$GIT_CD_DIR"
        elif [ "$_rc" -eq 2 ]; then _skipat="$_cur"; _skipset=1; _cur=""
        fi
      fi
    fi

    # What the operator does to the segments after it. (The "where the
    # shell was before" of a `||` is a flag plus a value, not a value alone:
    # the empty string — the caller's own cwd — is a real answer.)
    _pipe=0
    case "$_term" in
      '||')
        if [ "$_skip" -eq 0 ] && [ "$_skipset" -eq 0 ]; then _skipat="$_cur"; fi
        _skip=1
        continue
        ;;
      '&')  _skip=0; _cur="$_base" ;;
      '|')  _skip=0; _pipe=1 ;;
      ';'|nl|eof) _skip=0; _base="$_cur" ;;
      *)    _skip=0 ;;
    esac
    _skipat=""; _skipset=0
  done <<< "$(_git_argv_segments_meta "$_cmd")"

  # Close any group the input left open, then hand the caller the result.
  while [ "$_sdepth" -gt 0 ]; do
    _cur="${_stack##*"$GIT_ARGV_US"}"; _stack="${_stack%"$GIT_ARGV_US"*}"
    _sdepth=$((_sdepth - 1))
  done
  GIT_ARGV_MOVES_END="$_cur"
  return 0
}

# git_argv_has_sub <command> <subcommand>
#
# Returns 0 if any segment of the command invokes `git <subcommand>`. On
# success GIT_SUB/GIT_ARGS describe the segment that matched.
git_argv_has_sub() {
  local _cmd="$1" _want="$2" _line
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    git_argv_parse "$_line" || continue
    if [ "$GIT_SUB" = "$_want" ]; then return 0; fi
  done <<< "$(git_argv_expand "$_cmd")"
  return 1
}

# git_push_targets
#
# Reads GIT_ARGS (set by git_argv_parse on a `push` segment) and sets:
#   GIT_DESTS   the branch names this push writes to, US-separated
#   GIT_FORCE   1 if the push is a force in any spelling, else 0
#
# Every non-option word is a candidate destination, the remote name included —
# deliberately, exactly as _shell.py's caller does it. A remote called `main`
# is not a thing worth being clever about, and reading one extra word costs
# nothing while missing one costs the branch.
#
# One refspec becomes one destination by: strip a leading `+` (and record the
# force it means), take the part after the LAST colon, fall back to the source
# name when that part is empty (`main:` is a push TO main), then strip the
# ref-namespace prefixes. So `feature:refs/heads/main` is a push to `main`, and
# `HEAD:refs/heads/feature/main` is a push to `feature/main`.
git_push_targets() {
  GIT_DESTS=""
  GIT_FORCE=0
  local _oldifs="$IFS" _hadf=0 _n=0 _w _d _src

  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $GIT_ARGS
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f

  while [ $# -gt 0 ]; do
    _w="$1"
    shift
    case "$_w" in
      "") continue ;;
      -f|--force|--force-with-lease|--force-with-lease=*|--force-if-includes)
        GIT_FORCE=1
        continue
        ;;
      --repo|-o|--push-option|--receive-pack|--exec)
        if [ $# -gt 0 ]; then shift; fi
        continue
        ;;
      -*) continue ;;
    esac
    case "$_w" in
      +*) GIT_FORCE=1; _w="${_w#+}" ;;
    esac
    case "$_w" in
      *:*)
        _src="${_w%%:*}"
        _d="${_w##*:}"
        [ -n "$_d" ] || _d="$_src"
        ;;
      *) _d="$_w" ;;
    esac
    _d="${_d#refs/heads/}"
    _d="${_d#refs/remotes/}"
    _d="${_d#heads/}"
    if [ "$_n" -eq 0 ]; then GIT_DESTS="$_d"; else GIT_DESTS="$GIT_DESTS$GIT_ARGV_US$_d"; fi
    _n=$((_n + 1))
  done
}
