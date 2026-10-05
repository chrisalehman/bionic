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
# THREE REFUSALS, each before anything runs and each writing nothing, status 2:
#   - a fifth argument: nothing is passed through to the CLI.
#   - a <dest> that is this checkout or lies inside it (found from this file's own place, by
#     physical path): a session started there sits beside every answer. A copy of this file
#     outside any checkout cannot know where it is, so it does not refuse on that ground.
#   - a claude that is not an absolute path outside <dest>: a PATH holding `.`, an empty entry
#     or any relative one answers a path the session's own directory can supply, and a file
#     inside <dest> is the built project's, which is not trusted to supply the CLI.
set -u
dest="${1:-}" plugin="${2:-}" prompt="${3:-}" out="${4:-}"
[ "$#" -eq 4 ] && [ -d "$dest" ] && [ -d "$plugin" ] && [ -r "$prompt" ] && [ -d "$(dirname "$out")" ] \
  || { echo "usage: run-session.sh <dest> <plugin copy> <prompt file> <output file>" >&2; exit 2; }
# The session changes directory, so every path it is given is made absolute first.
for v in dest plugin prompt out; do
  case "${!v}" in /*) ;; *) printf -v "$v" '%s/%s' "$PWD" "${!v}" ;; esac
done
refuse() { printf 'run-session.sh: refused — %s\n  %s\n' "$1" "$2" >&2; exit 2; }
# Where <dest> really is, and where this checkout is, both physical.
dest_real="$(cd -P "$dest" && pwd -P)" || exit 2
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 2
top="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$here" rev-parse --show-toplevel 2>/dev/null)" \
  && top="$(cd -P "$top" && pwd -P)" || top=""
if [ -n "$top" ]; then
  case "$dest_real/" in
    "$top"/*) refuse "a session never sits inside the checkout that holds the answers" \
                     "$dest is $dest_real, which is this checkout ($top) or inside it" ;;
  esac
fi
# The CLI binary on PATH, never a shell function of the same name: a login shell may define one
# that adds flags, and `env` below runs only a program. The lookup is made here, entry by entry
# as the shell does, so that an entry which is not absolute (`.`, an empty one, a relative one)
# is named and refused instead of being followed into the project.
claude_bin="" rest="$PATH:"
while [ -n "$rest" ]; do
  entry="${rest%%:*}"; rest="${rest#*:}"
  [ -f "${entry:-.}/claude" ] && [ -x "${entry:-.}/claude" ] || continue
  case "$entry" in
    /*) claude_bin="$entry/claude" ;;
    "") refuse "an empty PATH entry gives claude a relative path" \
                "a session's project is not trusted to supply the CLI; put an absolute directory first on PATH" ;;
    *)  refuse "PATH entry '$entry' gives claude a relative path" \
                "a session's project is not trusted to supply the CLI; put an absolute directory first on PATH" ;;
  esac
  break
done
[ -n "$claude_bin" ] || { echo "run-session.sh: no claude binary on PATH" >&2; exit 2; }
# Its physical place, links followed: the file itself may be a link into <dest>.
claude_real="$claude_bin"
while [ -L "$claude_real" ]; do
  link="$(readlink "$claude_real")"
  case "$link" in /*) claude_real="$link" ;; *) claude_real="${claude_real%/*}/$link" ;; esac
done
claude_real="$(cd -P "${claude_real%/*}" && pwd -P)/${claude_real##*/}" || exit 2
case "$claude_real" in
  "$dest_real"/*) refuse "the claude on PATH is a file inside the built project" \
                         "$claude_bin is inside $dest; the project is not trusted to supply the CLI" ;;
esac

start=$(date -u +%FT%TZ); s0=$(date +%s)
echo "start=$start" > "$out.time"
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
# env block are left as they are.
cd "$dest" && env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_CHILD_SESSION \
  -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_PID -u CLAUDE_PLUGIN_DATA -u CLAUDE_CODE_ENTRYPOINT \
  -u CLAUDE_CODE_EXECPATH -u CLAUDE_EFFORT \
  "$claude_bin" -p --plugin-dir "$plugin" --output-format json "$(cat "$prompt")" \
  > "$out" 2> "$out.err"
rc=$?
echo "end=$(date -u +%FT%TZ) seconds=$(( $(date +%s) - s0 )) rc=$rc" >> "$out.time"
cat "$out.time"
exit $rc
