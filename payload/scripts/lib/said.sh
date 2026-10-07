#!/bin/bash
# payload/scripts/lib/said.sh — what the user typed (epic-23 wave-28 T42; REQ-8 AC-8.9, D34).
#
# WHAT IT OWNS. One question: do these words stand in a prompt the user typed in this session?
#
#     user_said <text>   0  the text, its runs of white space folded, stands inside a typed prompt
#                        1  it stands in none (white space alone says nothing)
#                        2  this session's transcript cannot be found or read; every caller refuses
#
# THE TRANSCRIPT is the CLI's own record of the session, `<config>/projects/<slug>/<session id>.jsonl`
# (`<config>` is CLAUDE_CONFIG_DIR, else ~/.claude; the session id is CLAUDE_CODE_SESSION_ID). It is
# found as hooks/session-poker.sh `session_transcript` finds it: scanned across the project
# directories, never derived from a slugged cwd, and a symbolic link at that name is not the
# session's. Nothing else is read.
#
# A TYPED PROMPT, AND NOTHING ELSE, BY THE KEYS THE CLI WRITES (measured on 2.1.291; the shapes are in
# tests/fixtures/transcript-move/README.md). It is a main-thread entry carrying `origin.kind: human`:
# a `user` entry whose `message.content` is the prompt, or a `queued_command` attachment (a prompt
# typed while a turn ran) whose `prompt` is. Everything else never counts: a tool's result, a
# teammate's message and another session's message (no origin, or `origin.kind: peer`), a hook's
# added context and a system reminder (attachments, `isMeta` entries, `system` entries), the
# orchestrator's own text (`assistant`), a compaction summary, a dispatched agent's prompt
# (`isSidechain`), and any block pasted into a typed prompt (`<pasted_content …>…</pasted_content>`),
# which carries someone's words but not the user's own. Each entry is parsed as JSON, so a word
# inside a string can never forge a key; a line torn mid-write is skipped, not fatal.
#
# Sourced, never executed. Defines functions only; reads nothing at load time. Needs jq (rc 2
# without it). bash 3.2.

# _said_transcript -> this session's transcript path on stdout; exit 1 when there is none.
_said_transcript() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}" d f
  [ -n "$sid" ] || return 1
  for d in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/; do
    f="${d}${sid}.jsonl"
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

# user_said <text> -> 0, 1 or 2, as above.
user_said() {
  local tx out
  tx="$(_said_transcript)" || return 2
  [ -r "$tx" ] && command -v jq >/dev/null 2>&1 || return 2
  out="$(jq -nrR --arg n "${1:-}" '
    def fold: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
    def words: if type == "string" then . elif type == "array" then [.[] | objects | select(.type == "text") | .text | strings] | join(" ") else "" end;
    def typed:
      if .type == "user" and .isMeta != true and .isSidechain != true and (.origin.kind? // "") == "human" then .message.content | words
      elif .type == "attachment" and .isSidechain != true and .attachment.type? == "queued_command" and .attachment.isMeta != true and (.attachment.origin.kind? // "") == "human" then .attachment.prompt | words
      else empty end;
    ($n | fold) as $w
    | if $w == "" then empty
      else first(inputs | fromjson? | objects | (try typed catch empty) | gsub("<pasted_content[^>]*>[\\s\\S]*?</pasted_content>"; " ") | fold | select(contains($w))) | "said"
      end' "$tx" 2>/dev/null)" || return 2
  [ "$out" = said ]
}
