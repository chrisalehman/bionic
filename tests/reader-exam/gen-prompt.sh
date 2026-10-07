#!/bin/bash
# gen-prompt.sh <brief file>...
#
# Writes, on stdout, the prompt for one headless session (run-session.sh gives it to the CLI).
# The session dispatches each brief to a reader and does nothing else. README step 3 shows the
# command that uses it.
#
# A brief file's FIRST LINE is `subagent_type: <agent type>`, such as
# `subagent_type: bionic:critic`. Every line after it is the brief, which the session dispatches
# exactly as written: that first line is for this script and is not part of it.
#
# The briefs given to one call are readers that share one build, so they go TOGETHER, all in one
# message and in the foreground: started one after another, the second would read the first's
# record. One brief is one dispatch. Readers that must not share a build get a call each.
#
# Environment:
#   PLUGIN=<dir>  (required) the plugin copy of README step 1, an absolute path. Each brief ends with
#                the files its reader is to read, by path in that copy and never pasted: the checks
#                file of each question its `Questions:` line names, then the severity scale. They are
#                the files the recorder pushes a reader at start (hooks/execution-recorder.sh,
#                `start_pushed`), and the scale goes to every reader, because every reader is asked
#                to write its findings as finding lines (wave-28 T18, D22), the one that is dealt
#                `evidence` alone included.
#   STEP_ZERO=1  before any dispatch, the session lists the Agent tool's descriptions of
#                bionic:reviewer and bionic:critic, quoted exactly as the tool gives them.
#
# The prompt says nothing about the project: everything the session knows comes from the briefs.
set -euo pipefail
[ "$#" -ge 1 ] || { echo "usage: gen-prompt.sh <brief file>..." >&2; exit 2; }
[ -n "${PLUGIN:-}" ] || { echo "gen-prompt.sh: PLUGIN is not set; give the plugin copy of README step 1 as PLUGIN=<dir>" >&2; exit 2; }
case "$PLUGIN" in /*) ;; *) echo "gen-prompt.sh: PLUGIN=$PLUGIN is not an absolute path" >&2; exit 2 ;; esac
plug="${PLUGIN%/}"

# brief_questions <brief file> — the questions its `Questions:` line names, one line, blank-joined.
brief_questions() {
  sed -n 's/^Questions:[[:blank:]]*//p' "$1" | head -n 1 | tr -d '\r' | tr ',' ' ' | tr -s '[:blank:]' ' ' | sed 's/^ //; s/ $//'
}

for f in "$@"; do
  [ -r "$f" ] || { echo "gen-prompt.sh: cannot read $f" >&2; exit 2; }
  head -n 1 "$f" | grep -Eq '^subagent_type: [A-Za-z0-9:_-]+$' \
    || { echo "gen-prompt.sh: line 1 of $f is not 'subagent_type: <agent type>'" >&2; exit 2; }
  [ "$(wc -l < "$f")" -ge 2 ] || { echo "gen-prompt.sh: $f holds no brief after line 1" >&2; exit 2; }
  qs="$(brief_questions "$f")"
  [ -n "$qs" ] || { echo "gen-prompt.sh: $f has no Questions: line" >&2; exit 2; }
  for q in $qs; do
    case "$q" in
      evidence|adversarial|structure) ;;
      *) echo "gen-prompt.sh: $f names the question '$q', which is none of evidence, adversarial, structure" >&2; exit 2 ;;
    esac
    [ -r "$plug/context/checks-$q.md" ] || { echo "gen-prompt.sh: $plug/context/checks-$q.md cannot be read" >&2; exit 2; }
  done
  [ -r "$plug/context/severity.md" ] || { echo "gen-prompt.sh: $plug/context/severity.md cannot be read" >&2; exit 2; }
done

printf '%s\n\n' "/bionic:canonical-sdlc This session starts no run: do not carry out any step of the skill, write no plan, and change no file of this repository outside .bionic/docs/record/. Do only the following."
if [ "${STEP_ZERO:-}" = 1 ]; then
  printf '%s\n\n' "0. Before any dispatch, list every agent type the Agent tool offers whose name is bionic:reviewer or bionic:critic, quoting each one's description exactly as the tool gives it."
fi
n=$#
if [ "$n" -gt 1 ]; then
  how="Dispatch the $n briefs below together, in one message."
else
  how="Dispatch the brief below."
fi
cat <<EOF
1. $how Use the Agent tool with the subagent_type each brief gives, and as its prompt the text between that brief's BEGIN and END lines, exactly as written: add nothing, drop nothing, change nothing. Do not give it a name and do not run it in the background. Wait for each to finish.
2. If a dispatch is refused or a tool is denied, do not change the brief and do not try again: quote the refusal exactly as printed, and stop.
3. When a reader has finished: if a record path its brief names does not exist and the reader returned that record in its reply, save the record exactly as the reader returned it at that path. Do not edit any record.
4. Reply with each record path the briefs name and whether that file exists.

EOF
i=0
for f in "$@"; do
  i=$((i + 1))
  echo "=== Brief $i — $(head -n 1 "$f") ==="
  echo "BEGIN"
  tail -n +2 "$f"
  [ -z "$(tail -c 1 "$f")" ] || echo
  qs="$(brief_questions "$f")"
  printf '\nRead each of these files in full before you start; the plugin ships them and they bind this review:\n'
  for q in evidence adversarial structure; do
    case " $qs " in *" $q "*) printf '%s/context/checks-%s.md\n' "$plug" "$q" ;; esac
  done
  printf '%s/context/severity.md\n' "$plug"
  echo "END"
  echo
done
