#!/bin/bash
# payload/scripts/lib/said.sh — what the user typed (epic-23 wave-28 T42; REQ-8 AC-8.9, D34).
#
# WHAT IT OWNS. One question: do these words stand in a prompt the user typed in this session?
#
#     user_said <text>   0  the text, folded, stands in a typed prompt as WHOLE WORDS, and is enough of them
#                        1  it stands in none as whole words (white space alone says nothing)
#                        2  this session's transcript cannot be found or read; every caller refuses
#                        3  it stands in one as whole words, but is under three words and is no whole prompt
#     said_fold <text>   the one fold, on stdout: runs of white space and control characters become one
#                        space, the ends trimmed (the verb writes the words it proved through it)
#
# WHOLE WORDS (wave-28 T66; D34). A WORD CHARACTER is a letter or digit of any script, `_`, `-` or `'`.
# The folded quote stands in a folded prompt only where the character before it and the one after it
# are not word characters (a prompt's start and end count as neither): `defer it` is in `please defer
# it` and not in `undefer items`, `fix` is not in `prefix`, `defer it` is not in `pre-defer it`. The
# match is case-sensitive. ENOUGH OF THEM: a quote is under three words when its folded text, split
# on spaces, holds fewer than three chunks with a word character in them; such a quote is a decision
# only when it IS a whole typed prompt (the user typed `defer it` alone: that is their word), else rc 3.
# THE LIMIT OF MECHANICAL PROOF: `defer it` quoted out of `do not defer it at all` is whole words and
# three of them (`defer it at all`) passes; whether the quote keeps the sentence's meaning is the
# reader's to judge, from the words= the `moved:` line keeps. The doctrine is to quote the whole sentence.
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
# Also: the slash commands. Typed WITH arguments, a command's entry carries `origin.kind: human` and the
# CLI's wrapper text (`<command-name>`, `<command-args>`) counts as typed; typed WITHOUT, it carries no
# origin and is no typed prompt (fixtures `slash-args`, `slash-bare`).
#
# THE SESSION ID is `session_id` of lib/session.sh (sourced here when the caller has not), as every
# reader of the session key takes it.
#
# Sourced, never executed. Defines functions only; reads nothing at load time. Needs jq (rc 2
# without it). bash 3.2.

# The fold, ONE rule for both sides of the match and for the line a caller writes: runs of white space
# and control characters become one space, the ends trimmed.
_SAID_FOLD_JQ='def fold: gsub("[\\s\\p{Cc}]+"; " ") | sub("^ "; "") | sub(" $"; "");'

# said_fold <text> -> the folded text on stdout.
said_fold() {
  command -v jq >/dev/null 2>&1 || return 2
  jq -nrR --arg n "${1:-}" "$_SAID_FOLD_JQ"' $n | fold'
}

# _said_transcript -> this session's transcript path on stdout; exit 1 when there is none.
_said_transcript() {
  local sid d f
  declare -F session_id >/dev/null 2>&1 || . "${BASH_SOURCE[0]%/*}/session.sh" 2>/dev/null || return 1
  sid="$(session_id 2>/dev/null)" || return 1
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

# user_said <text> -> 0, 1, 2 or 3, as above. One streaming pass: each typed prompt is folded, tried
# whole-word, and the first that is enough ends it.
user_said() {
  local tx out
  tx="$(_said_transcript)" || return 2
  [ -r "$tx" ] && command -v jq >/dev/null 2>&1 || return 2
  out="$(jq -nrR --arg n "${1:-}" "$_SAID_FOLD_JQ"'
    def esc: gsub("(?<c>[\\\\^$.|?*+()\\[\\]{}])"; "\\\(.c)");
    def bounded($w; $p): $p | test("(?<![\\w\\x27-])" + ($w | esc) + "(?![\\w\\x27-])");
    def enough($w; $p): ([$w | split(" ")[] | select(test("\\w"))] | length) >= 3 or $w == $p;
    def words: if type == "string" then . elif type == "array" then [.[] | objects | select(.type == "text") | .text | strings] | join(" ") else "" end;
    def typed:
      if .type == "user" and .isMeta != true and .isSidechain != true and (.origin.kind? // "") == "human" then .message.content | words
      elif .type == "attachment" and .isSidechain != true and .attachment.type? == "queued_command" and .attachment.isMeta != true and (.attachment.origin.kind? // "") == "human" then .attachment.prompt | words
      else empty end;
    ($n | fold) as $w
    | if $w == "" then "none"
      else
        [label $out | inputs | fromjson? | objects | (try typed catch empty)
          | gsub("<pasted_content[^>]*>[\\s\\S]*?</pasted_content>"; " ") | fold
          | select(bounded($w; .)) as $p
          | if enough($w; $p) then ("said", break $out) else "short" end]
        | if index("said") then "said" elif length > 0 then "short" else "none" end
      end' "$tx" 2>/dev/null)" || return 2
  case "$out" in
    said) return 0 ;;
    none) return 1 ;;
    short) return 3 ;;
    *) return 2 ;;
  esac
}
