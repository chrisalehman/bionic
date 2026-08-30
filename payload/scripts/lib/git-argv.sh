# git-argv.sh — read a Bash command line the way git reads it.
#
# WHAT IT OWNS. One question, for every wall that has to answer "is this
# command a `git <something>`, and what is it doing": how a shell command line
# decomposes into segments and argv words. Two hooks source it —
# hooks/protect-main.sh (is this a push, and where to) and
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
  cmd = ENVIRON["GIT_ARGV_CMD"]
  gsub(US, " ", cmd)
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
    s = line
    # A here-STRING (<<<) has no body. Blank it before scanning so its third
    # angle bracket cannot look like a tag introducer. Its operand stays a
    # word on this line, which is what it is.
    gsub(/<<</, "   ", s)
    # The opener itself is removed as it is recognised, so the tag does not
    # survive as a phantom argv word: `cat > f <<NOTE` is `cat` and `f`.
    while (match(s, /(^|[ \t])<<-?[ \t]*["']?[A-Za-z_][A-Za-z0-9_]*["']?([ \t]|$)/)) {
      tag = substr(s, RSTART, RLENGTH)
      s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
      sub(/^[ \t]*<<-?[ \t]*/, "", tag)
      gsub(/["' \t]/, "", tag)
      qn++
      TAG[qn] = tag
    }
    body = body s "\n"
  }

  # ---- 2. segments and argv words -----------------------------------------
  tok = ""
  have = 0
  seg = ""
  segn = 0
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

    # Word separators. Redirection arrows are separators, not segment
    # boundaries: `git push origin main>log` must still yield `main`.
    if (c == " " || c == "\t" || c == "<" || c == ">") {
      if (have) { seg = flush_tok(seg, tok, segn); segn++; tok = ""; have = 0 }
      i++
      continue
    }

    # Segment boundaries.
    if (c == "\n" || c == ";" || c == "&" || c == "|") {
      if (have) { seg = flush_tok(seg, tok, segn); segn++; tok = ""; have = 0 }
      if (segn) { print seg }
      seg = ""
      segn = 0
      i++
      continue
    }

    tok = tok c
    have = 1
    i++
  }
  if (have) { seg = flush_tok(seg, tok, segn); segn++ }
  if (segn) { print seg }
  exit 0
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

# git_argv_parse <segment-line>
#
# Reads ONE segment (a line from git_argv_segments). Returns 0 and sets
# GIT_SUB (the git subcommand) and GIT_ARGS (its arguments, US-separated) when
# the segment invokes git; returns 1 otherwise.
#
# Skipped before argv[0]: leading VAR=value assignments and an `env`/`command`/
# `nohup` runner, so `GIT_SSH_COMMAND=ssh git push ...` reads as a push.
# Skipped after it: git's own global options. The value-taking ones are named
# so their VALUE is consumed too; every other `-...` word is dropped on its
# own, which is what makes `git --no-pager commit` a commit. Same shape as the
# GIT alternation in _shell.py:35-39.
git_argv_parse() {
  GIT_SUB=""
  GIT_ARGS=""
  local _line="$1" _oldifs="$IFS" _hadf=0 _n=0 _a

  case "$-" in *f*) _hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $_line
  IFS="$_oldifs"
  [ "$_hadf" -eq 1 ] || set +f

  while [ $# -gt 0 ]; do
    case "$1" in
      env|command|nohup) shift ;;
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

  [ $# -gt 0 ] || return 1
  case "$1" in
    git|*/git) shift ;;
    *) return 1 ;;
  esac

  while [ $# -gt 0 ]; do
    case "$1" in
      -C|-c|--namespace|--git-dir|--work-tree|--exec-path|--config-env|--super-prefix)
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
  done <<< "$(git_argv_segments "$_cmd")"
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
