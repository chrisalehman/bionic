#!/bin/bash
# run-session.sh <dest> <plugin copy> <prompt file> <output file>
#
# Starts ONE headless Claude session on the built project at <dest>, loading the plugin copy at
# <plugin copy> by --plugin-dir and giving it the prompt in <prompt file> (gen-prompt.sh writes
# one). README step 3 is the interactive form of the same thing.
#   <output file>        the session's JSON result (stdout); it names the session id
#   <output file>.err    the session's stderr
#   <output file>.time   start and end times, seconds and the CLI's exit status
# Exit status: the CLI's, or 2 when an input is missing.
#
# THIS SCRIPT WIDENS NOTHING. The session is started with -p, --plugin-dir and --output-format
# json and no other flag, and no setting is read or written. A session or a reader that is
# denied a tool is reported to the user, who decides; it is never worked round, and nothing
# here, or in a prompt, may be changed to get past a denial.
set -u
dest="${1:-}" plugin="${2:-}" prompt="${3:-}" out="${4:-}"
[ "$#" -eq 4 ] && [ -d "$dest" ] && [ -d "$plugin" ] && [ -r "$prompt" ] && [ -d "$(dirname "$out")" ] \
  || { echo "usage: run-session.sh <dest> <plugin copy> <prompt file> <output file>" >&2; exit 2; }
# The session changes directory, so every path it is given is made absolute first.
for v in dest plugin prompt out; do
  case "${!v}" in /*) ;; *) printf -v "$v" '%s/%s' "$PWD" "${!v}" ;; esac
done
# The CLI binary on PATH, never a shell function of the same name: a login shell may define one
# that adds flags, and `env` below runs only a program.
claude_bin="$(type -P claude)" || { echo "run-session.sh: no claude binary on PATH" >&2; exit 2; }

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
