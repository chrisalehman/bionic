#!/bin/bash
# hooks/opening-line.sh — THE TOOL SHOWS THE VERSION LINE when the method is invoked.
#
# The person sees which bionic runs before the model says a word: on the method's invocation this
# prints one JSON object, `{"systemMessage": "<line>"}`, the line being what scripts/version.sh
# prints (the same line `/bionic:version` shows). The hooks reference (code.claude.com/docs/en/hooks,
# JSON output) reads `systemMessage` as a message shown to the user, drawn under the typed prompt
# as `UserPromptExpansion says: <line>` or under the Skill call. Plain stdout and
# `hookSpecificOutput.additionalContext` are added to the model's context and show the person
# nothing, so neither is ever printed here.
#
# TWO PATHS, the two an invocation takes (hooks/engage.sh's header says why):
#   UserPromptExpansion / command_name                  the typed command. hooks.json matches it to
#                                                       `^(bionic:)?canonical-sdlc$`, so the platform
#                                                       starts this for no other command or prompt.
#   PreToolUse / tool_name "Skill" / tool_input.skill   the model's own call. The matcher there sees
#                                                       the tool, not the skill, so the name test
#                                                       below is what keeps every other skill silent.
# The name test is engage.sh's, spelling for spelling (qualified or bare, the typed form's leading
# slash dropped); tests/opening-line.test.sh feeds both hooks the same names and holds them equal.
#
# IT NEVER STANDS IN FRONT OF THE METHOD. Exit 0 on every path. A version command that is missing,
# fails, or prints nothing gives nothing at all: a line saying the read broke would stand where the
# version should, and doctor is where a broken install is diagnosed. It writes no state and asks
# nothing of engagement, so it needs no library and carries no loader.
#
# [WALL: tests/opening-line.test.sh]

set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

NAME=""
case "$(_jq '.hook_event_name')" in
  UserPromptExpansion) NAME="$(_jq '.command_name')" ;;
  PreToolUse)
    [ "$(_jq '.tool_name')" = "Skill" ] || exit 0
    NAME="$(_jq '.tool_input.skill')"
    ;;
  *) exit 0 ;;
esac
case "${NAME#/}" in
  canonical-sdlc|bionic:canonical-sdlc) ;;
  *) exit 0 ;;
esac

# The version command beside this hook: `<root>/scripts` in an installed plugin, where hooks/ is
# a directory of the root; `<repo>/payload/scripts` in a checkout, where payload/hooks links to
# the repository's hooks/ and the physical parent is the repository.
_ol_dir="$(dirname "$0")"
_ol_version="$_ol_dir/../scripts/version.sh"
[ -f "$_ol_version" ] || _ol_version="$_ol_dir/../payload/scripts/version.sh"
[ -f "$_ol_version" ] || exit 0

# Run from the hook's own directory, which the platform sets to the session's: version.sh reads
# the project from its cwd to say whether this session runs a checkout in place.
LINE="$(bash "$_ol_version" 2>/dev/null)" || exit 0
[ -n "$LINE" ] || exit 0
jq -nc --arg l "$LINE" '{systemMessage: $l}' 2>/dev/null
exit 0
