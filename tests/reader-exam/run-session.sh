#!/bin/bash
# run-session.sh <dest> <plugin copy> <prompt file> <output file>
#
# Starts ONE headless Claude session on the built project at <dest>, loading the plugin copy at
# <plugin copy> by --plugin-dir and giving it the prompt in <prompt file> (gen-prompt.sh writes
# one). README step 3 is the interactive form of the same thing.
#   <output file>        the session's JSON result (stdout); it names the session id
#   <output file>.err    the session's stderr
#   <output file>.time   start and end times, seconds and the CLI's exit status
# Exit status: the CLI's, or 2 when an input is missing or the call is refused (below).
#
# THIS SCRIPT WIDENS NOTHING. The session is started with -p, --plugin-dir and --output-format
# json and no other flag, and no setting is read or written. A session or a reader that is
# denied a tool is reported to the user, who decides; it is never worked round, and nothing
# here, or in a prompt, may be changed to get past a denial.
#
# WHAT IT TRUSTS of its caller: the four arguments, and the PATH it searches for claude. It
# runs itself again at once under an environment it makes (`/usr/bin/env -i`, PATH
# /usr/bin:/bin, no CDPATH, no BASH_ENV, none of the caller's functions or aliases), so every
# step of its own runs a program from /usr/bin or /bin. The caller's environment is read as
# data and handed to the session alone. Each path it is given is resolved once, physically,
# and the resolved path is the one checked and the one used. "Inside" means that one of a
# path's physical ancestors IS the directory (`-ef`: device and inode), so letter case, a
# link or `/var` against `/private/var` never tell two spellings of one place apart.
#
# REFUSALS, each made before it runs the CLI or writes anything, each status 2:
#   - a fifth argument: nothing is passed through to the CLI.
#   - a PATH holding an entry that is not an absolute directory (`.`, an empty entry, any
#     relative one), whether or not a claude is there: the session inherits PATH, and its own
#     children search a relative entry from the built project.
#   - a claude on PATH that is a file inside <dest>: the built project is not trusted to supply
#     the CLI.
#   - a <dest>, or an <output file>, inside any worktree of the repository this file lies in
#     (`git worktree list`): a session started there sits beside every answer. A copy of this
#     file that lies in no checkout cannot know where the answers are, so it does not refuse on
#     that ground; one that lies in a checkout whose lookup fails refuses, saying so.
#   - an <output file> inside <dest>, or one (or its .err or .time) that exists as anything but
#     a regular file: nothing is written through a link or over a directory.
main() {
  set -u
  usage() { echo "usage: run-session.sh <dest> <plugin copy> <prompt file> <output file>" >&2; exit 2; }
  refuse() { printf 'run-session.sh: refused — %s\n  %s\n' "$1" "$2" >&2; exit 2; }
  # phys <dir> — its physical path; nothing when it cannot be entered.
  phys() { (cd -P -- "$1" 2>/dev/null && pwd -P); }
  # inside <path> <dir> — true when <path>, or one of its ancestors, is <dir> itself.
  inside() {
    local d="$1"
    while :; do
      [ "$d" -ef "$2" ] && return 0
      [ -n "$d" ] && [ "$d" != / ] || return 1
      d="${d%/*}"; d="${d:-/}"
    done
  }
  local dest="${1:-}" plugin="${2:-}" prompt="${3:-}" out="${4:-}" base pdir
  base="${out##*/}"
  [ "$#" -eq 4 ] && [ -d "$dest" ] && [ -d "$plugin" ] && [ -r "$prompt" ] && [ -n "$base" ] \
    && [ "$base" != . ] && [ "$base" != .. ] || usage
  case "$out" in */*) out="${out%/*}" ;; *) out=. ;; esac
  [ -d "${out:-/}" ] || usage
  # Each path once, physically; only these values are used from here on.
  dest="$(phys "$dest")" && plugin="$(phys "$plugin")" && out="$(phys "${out:-/}")/$base" || usage
  case "$prompt" in */*) pdir="${prompt%/*}" ;; *) pdir=. ;; esac
  prompt="$(phys "${pdir:-/}")/${prompt##*/}" || usage

  # The caller's environment, as data: it reaches the session and nothing here.
  local -a caller_env=() session_env=()
  local kv caller_path="" have_path=""
  if { : <&3; } 2>/dev/null; then
    while IFS= read -r -d '' kv; do caller_env+=("$kv"); done <&3
  fi
  for kv in ${caller_env[@]+"${caller_env[@]}"}; do
    case "$kv" in PATH=*) caller_path="${kv#PATH=}" have_path=1 ;; esac
  done
  [ -n "$have_path" ] || { echo "run-session.sh: no claude binary on PATH" >&2; exit 2; }
  local entry rest="$caller_path:"
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"; rest="${rest#*:}"
    case "$entry" in
      /*) ;;
      "") refuse "PATH holds an entry that is not an absolute directory" \
                 "PATH entry '' (empty, which is the working directory); the session inherits PATH" ;;
      *) refuse "PATH holds an entry that is not an absolute directory" \
                "PATH entry '$entry'; the session inherits PATH and searches it from the built project" ;;
    esac
  done

  # Every worktree of the repository this file lies in, physical. None for a copy in no checkout.
  local -a trees=()
  worktrees
  local w
  for w in ${trees[@]+"${trees[@]}"}; do
    inside "$dest" "$w" && refuse "a session never sits inside the checkout that holds the answers" \
      "$dest is inside the worktree $w"
    inside "${out%/*}" "$w" && refuse "an output file never lies in a checkout or in the built project" \
      "$out is inside the worktree $w"
  done
  inside "${out%/*}" "$dest" && refuse "an output file never lies in a checkout or in the built project" \
    "$out is inside the built project $dest"
  for w in "$out" "$out.err" "$out.time"; do
    { [ -L "$w" ] || { [ -e "$w" ] && [ ! -f "$w" ]; }; } \
      && refuse "an output file exists and is not a regular file" "$w"
  done

  # The CLI binary on PATH, never a shell function of the same name: a login shell may define one
  # that adds flags, and only a program is run below.
  local claude_bin="" claude_real link
  rest="$caller_path:"
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"; rest="${rest#*:}"
    [ -f "$entry/claude" ] && [ -x "$entry/claude" ] && { claude_bin="$entry/claude"; break; }
  done
  [ -n "$claude_bin" ] || { echo "run-session.sh: no claude binary on PATH" >&2; exit 2; }
  # Its physical place, links followed: the file itself may be a link into <dest>.
  claude_real="$claude_bin"
  while [ -L "$claude_real" ]; do
    link="$(readlink "$claude_real")"
    case "$link" in /*) claude_real="$link" ;; *) claude_real="${claude_real%/*}/$link" ;; esac
  done
  inside "$(phys "${claude_real%/*}")" "$dest" && refuse "the claude on PATH is a file inside the built project" \
    "$claude_bin is inside $dest; the project is not trusted to supply the CLI"

# The parent session's own identity is not handed down: a session opened in a terminal carries
# none of these.
#   CLAUDECODE                              marks the process as running inside another session
#   CLAUDE_CODE_CHILD_SESSION               marks the session as another session's child
#   CLAUDE_CODE_SESSION_ID                  bionic reads it as the session's id (lib/session.sh), so
#                                           an inherited one ties this build's markers to the parent
#   CLAUDE_CODE_BRIDGE_SESSION_ID           the parent's bridge session, not this one's
#   CLAUDE_CODE_MESSAGING_SOCKET            would tie this session to the parent's team messaging
#   CLAUDE_CODE_MESSAGING_TOKEN             the credential for that same messaging channel
#   CLAUDE_CODE_SESSION_ATTENDED            the parent's attended state, not this one's
#   CLAUDE_PID                              the parent's process id
#   CLAUDE_PLUGIN_DATA                      the parent's plugin data directory
#   CLAUDE_CODE_ENTRYPOINT                  how the parent was started
#   CLAUDE_CODE_EXECPATH                    where the parent's binary was found
#   CLAUDE_EFFORT                           the parent's effort level
# Nothing that grants a permission is touched: settings, CLAUDE_CONFIG_DIR and the settings' own
# env block are left as they are. PWD is the built project, as a `cd` into it would leave it.
  for kv in ${caller_env[@]+"${caller_env[@]}"}; do
    case "$kv" in
      CLAUDECODE=*|CLAUDE_CODE_SESSION_ID=*|CLAUDE_CODE_BRIDGE_SESSION_ID=*) ;;
      CLAUDE_CODE_MESSAGING_SOCKET=*|CLAUDE_CODE_MESSAGING_TOKEN=*|CLAUDE_CODE_CHILD_SESSION=*) ;;
      CLAUDE_CODE_SESSION_ATTENDED=*|CLAUDE_PID=*|CLAUDE_PLUGIN_DATA=*|CLAUDE_CODE_ENTRYPOINT=*) ;;
      CLAUDE_CODE_EXECPATH=*|CLAUDE_EFFORT=*|PWD=*) ;;
      [A-Za-z_]*=*) session_env+=("$kv") ;;
    esac
  done
  session_env+=("PWD=$dest")
  local prompt_text start s0 rc
  prompt_text="$(< "$prompt")"
  start=$(date -u +%FT%TZ); s0=$(date +%s)
  echo "start=$start" > "$out.time"
  cd -- "$dest" && /usr/bin/env -i "${session_env[@]}" \
    "$claude_bin" -p --plugin-dir "$plugin" --output-format json "$prompt_text" \
    > "$out" 2> "$out.err"
  rc=$?
  echo "end=$(date -u +%FT%TZ) seconds=$(( $(date +%s) - s0 )) rc=$rc" >> "$out.time"
  cat "$out.time"
  exit $rc
}

# worktrees — sets `trees` to every worktree of the repository this file lies in, each by its
# physical path. A file with no `.git` above it lies in no checkout: no worktree, nothing said.
# One with a `.git` above it whose git cannot name its top and its worktrees is refused: an
# empty or many-lined answer is never read as "no checkout".
worktrees() {
  local here d git_at="" top line w listed
  case "${BASH_SOURCE[0]}" in */*) here="${BASH_SOURCE[0]%/*}" ;; *) here=. ;; esac
  here="$(phys "${here:-/}")"
  [ -n "$here" ] || refuse "the lookup of this file's checkout failed" "its own directory cannot be entered"
  d="$here"
  while :; do
    [ -e "$d/.git" ] && { git_at="$d"; break; }
    [ "$d" != / ] || break
    d="${d%/*}"; d="${d:-/}"
  done
  [ -n "$git_at" ] || return 0
  top="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" || top=""
  case "$top" in
    ""|*$'\n'*) refuse "the lookup of this file's checkout failed" \
                  "$git_at/.git lies above it, and git on PATH=$PATH named no single top" ;;
  esac
  [ -d "$top" ] && inside "$here" "$top" || refuse "the lookup of this file's checkout failed" \
    "git named $top, which does not hold $here"
  # Each worktree's physical path on a line of its own; a path that holds a newline is a line
  # that does not open with `/`, and is refused rather than read as two.
  listed="$(git -C "$top" worktree list --porcelain -z 2>/dev/null | while IFS= read -r -d '' line; do
    case "$line" in
      (*$'\n'*) echo "a worktree's path holds a newline" ;;
      ("worktree "*) w="$(phys "${line#worktree }")"; [ -z "$w" ] || printf '%s\n' "$w" ;;
    esac
  done)"
  while IFS= read -r w; do
    case "$w" in
      /*) trees+=("$w") ;;
      ?*) refuse "the lookup of this file's checkout failed" "$w" ;;
    esac
  done <<<"$listed"
  for w in ${trees[@]+"${trees[@]}"}; do [ "$w" -ef "$top" ] && return 0; done
  refuse "the lookup of this file's checkout failed" "git did not list $top among its worktrees"
}

# The helper runs itself again under an environment made here, before any step of its own: from
# this line on, only an absolute path is run, which no function of the caller's can stand in
# for. The caller's environment travels on fd 3, read by `/usr/bin/env -0`, for the session.
case "${RUN_SESSION_ENV-}" in
  made) main "$@" ;;
  *) { /usr/bin/env -0 | /usr/bin/env -i RUN_SESSION_ENV=made PATH=/usr/bin:/bin LC_ALL=C \
         /bin/bash --noprofile --norc -- "${BASH_SOURCE:-$0}" "$@" 3<&0 0<&4 4<&-; } 4<&0 ;;
esac
