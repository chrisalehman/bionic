#!/bin/bash
# payload/scripts/lib/said.sh — what the user typed (epic-23 wave-28 T42; REQ-8 AC-8.9, D34).
#
# WHAT IT OWNS. One question: do these words stand in a prompt the user typed in this run?
#
#     user_said <text> [<plan>]
#                        0  the text, folded, stands in a typed prompt as WHOLE WORDS, and is enough of them
#                        1  it stands in none as whole words (white space alone says nothing)
#                        2  no transcript of the sessions read can be found or read; every caller refuses
#                        3  it stands in one as whole words, but is under SAID_MIN_WORDS words and is no
#                           whole prompt
#                        and, beside the status, three variables (it prints nothing):
#                        SAID_SESSION   on 0, the session whose transcript holds the words; else empty
#                        SAID_SESSIONS  the sessions whose transcripts were read, space-separated, in order
#                        SAID_TRIED     the sessions asked for, space-separated, in order (read or not)
#                        SAID_REFUSED   the sessions the project does not witness, one `<sid> (<reason>)` per
#                                       line, in order; never read (below)
#
# EVERY RECORDED SESSION OF THE RUN (wave-36 T9; spec D10, design ledger Δ3 "D5 1"; AC-4.2). A `/clear`
# re-keys the session, and the words typed before it stand in the predecessor's transcript. With a <plan>,
# the sessions read are the plan's `- session:` lines (lib/binding.sh `bind_sessions`, the one reader of
# what the binding acts write), in the order they bound, then this session when the plan does not record
# it; with none, this session alone, as before. The first session, in that order, whose transcript holds
# the words as enough whole words answers 0 and is named in SAID_SESSION; else a quote that is short in
# any of them is 3; else 1. A recorded session whose transcript is gone is skipped; 2 only when none of
# them can be read. The verbs quote the session beside the words: `words="<words>" session=<sid>`.
#
# THE PROJECT WITNESSES A SESSION (wave-37 T5; D9, ADR-058). A `- session:` line is plan text, and one a
# hand or an agent appends reads exactly as one a binding act wrote; so the plan only NAMES a session, and
# the project proves it. A session, the plan's or this one, is read only when (1) `.bionic/tmp/loaded-<sid>
# .state` exists under this root (session-start writes it at every start, and it is no sweep class), and
# (2) its transcript is under this project's own directory: `<config>/projects/<project_slug root>/<sid>
# .jsonl`, else `<config>/projects/<project_slug cwd>/<sid>.jsonl` where cwd is the start directory that
# load record names (a session started in a subdirectory or a worktree files it there). Exactly those two
# names, by equality, never a prefix (`bionic2` is not `bionic`) and never a walk of every project. A
# session failing either is refused, not read, and lands in SAID_REFUSED as `<sid> (no loaded-<sid>.state)`
# or `<sid> (no transcript under <slug>[ or <slug>])`; the verb's refusal prints them beside the sessions
# read. THIS ROOT is `project_root` of the working directory, physical, the root the three verbs act in.
# The threat is a plan line appended by hand, not a forger editing the config directory (spec §5).
#     said_fold <text>   the one fold, on stdout: runs of white space and control characters become one
#                        space, the ends trimmed (the verb writes the words it proved, its why and its
#                        author through it, and the deferral's sentence the changelog is read through)
#     SAID_MIN_WORDS     the fewest words a quote may be unless it is a whole prompt (three): the one
#                        constant this rule and the verb's refusal text both read
#
# WHOLE WORDS (wave-28 T66, T74; D34). A WORD CHARACTER is a letter or digit of any script, `_`, `-`, the
# apostrophe `'` or the typographic apostrophe U+2019 (`wc` in the jq program, spelled once: the
# boundary test and the word count are made with it). The folded quote stands in a folded prompt only
# where the character before it and the one after it are not word characters (a prompt's start and end
# count as neither): `defer it` is in `please defer it` and not in `undefer items`, `fix` is not in
# `prefix`, `defer it` is not in `pre-defer it`, `t defer it now` is not in `don't defer it now`
# (either apostrophe). The match is case-sensitive. ENOUGH OF THEM: a quote is under SAID_MIN_WORDS
# words when its folded text, split on spaces, holds fewer chunks with a word character in them; such
# a quote is a decision only when it IS a whole typed prompt (the user typed `defer it` alone: that is
# their word; for a slash command typed with arguments, the whole prompt is the ARGUMENTS), else rc 3.
# THE LIMIT OF MECHANICAL PROOF: `defer it` quoted out of `do not defer it at all` is whole words and
# three of them (`defer it at all`) passes; whether the quote keeps the sentence's meaning is the
# reader's to judge, from the words= the `moved:` line keeps. The doctrine is to quote the whole sentence.
#
# THE TRANSCRIPT is the CLI's own record of a session, `<config>/projects/<slug>/<session id>.jsonl`
# (`<config>` is CLAUDE_CONFIG_DIR, else ~/.claude; the session id is CLAUDE_CODE_SESSION_ID). It is
# opened at the two names above alone, the slug being lib/detect.sh `project_slug`'s, and a symbolic
# link at that name is not the session's. Nothing else is read. This differs on purpose from
# hooks/session-poker.sh `session_transcript`, which still scans every project directory: that one
# finds a session's observe address, it decides no trust (wave-37 A-T5-7).
#
# A TYPED PROMPT, AND NOTHING ELSE, BY THE KEYS THE CLI WRITES (measured on 2.1.291; the shapes are in
# tests/fixtures/transcript-move/README.md). It is a main-thread entry carrying `origin.kind: human`:
# a `user` entry whose `message.content` is the prompt, or a `queued_command` attachment (a prompt
# typed while a turn ran) whose `prompt` is. Everything else never counts: a tool's result, a
# teammate's message and another session's message (no origin, or `origin.kind: peer`), a hook's
# added context and a system reminder (attachments, `isMeta` entries, `system` entries), the
# orchestrator's own text (`assistant`), a compaction summary, a dispatched agent's prompt
# (`isSidechain`), and any block pasted into a typed prompt (`<pasted_content id="…">` to
# `</pasted_content id="…">`; the CLI closes the block WITH the id, wave-28 T74), which carries
# someone's words but not the user's own. Each entry is parsed as JSON, so a word
# inside a string can never forge a key; a line torn mid-write is skipped, not fatal.
#
# Also: the slash commands. Typed WITH arguments, a command's entry carries `origin.kind: human` and the
# CLI's wrapper text (`<command-name>`, `<command-args>`) counts as typed words; the whole-prompt rule
# above compares against the arguments alone. Typed WITHOUT, it carries no origin and is no typed
# prompt (fixtures `slash-args`, `slash-bare`).
#
# THE SESSION ID is `session_id` of lib/session.sh, as every reader of the session key takes it. It is
# sourced from this file's own directory when the caller has not, the directory RESOLVED AT SOURCE TIME
# as lib/context.sh resolves its own (a call-time `${BASH_SOURCE[0]%/*}` is relative to a working
# directory the caller may have left, and a bare name has none).
#
# Sourced, never executed. Defines functions and one constant; the only thing it reads at load time
# is the path of session.sh. Needs jq (rc 2 without it). bash 3.2. lib/root.sh (`project_root`) is
# sourced from here as session.sh is; lib/detect.sh (`project_slug`) when user_said first runs, since
# it is a larger library and only the three verbs need it.

# The fewest words a quote may be unless it is a whole typed prompt. The jq program below and the verb's
# refusal text (hooks/session-poker.sh finding-move) both read this one number.
SAID_MIN_WORDS=3

_said_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
# RESOLVED AT SOURCE TIME, for the reason lib/context.sh states at `_CONTEXT_LIB_DIR`.
_SAID_LIB_DIR="$(cd "$(_said_self_dir)" 2>/dev/null && pwd -P)"
if ! declare -F session_id >/dev/null 2>&1 && [ -n "$_SAID_LIB_DIR" ] && [ -f "$_SAID_LIB_DIR/session.sh" ]; then
  # shellcheck source=/dev/null
  . "$_SAID_LIB_DIR/session.sh"
fi
# The run's sessions are read by binding.sh's one reader; it is sourced from here when the caller has not
# (functions only, nothing runs at source time).
if ! declare -F bind_sessions >/dev/null 2>&1 && [ -n "$_SAID_LIB_DIR" ] && [ -f "$_SAID_LIB_DIR/binding.sh" ]; then
  # shellcheck source=/dev/null
  . "$_SAID_LIB_DIR/binding.sh"
fi
# The root the words are held in is root.sh's one reader's (functions only).
if ! declare -F project_root >/dev/null 2>&1 && [ -n "$_SAID_LIB_DIR" ] && [ -f "$_SAID_LIB_DIR/root.sh" ]; then
  # shellcheck source=/dev/null
  . "$_SAID_LIB_DIR/root.sh"
fi

# _said_need_slug -> 0 when lib/detect.sh `project_slug` is defined, sourcing it from this file's own
# directory first when the caller has not. Called in the caller's shell (user_said), so the readers below,
# which run in command substitutions, inherit it rather than load it once per session.
_said_need_slug() {
  if ! declare -F project_slug >/dev/null 2>&1 && [ -n "$_SAID_LIB_DIR" ] && [ -f "$_SAID_LIB_DIR/detect.sh" ]; then
    # shellcheck source=/dev/null
    . "$_SAID_LIB_DIR/detect.sh" >/dev/null 2>&1
  fi
  declare -F project_slug >/dev/null 2>&1
}

# _said_root -> this root, physical, on stdout: project_root of the working directory, as the verbs take it.
_said_root() {
  local r
  declare -F project_root >/dev/null 2>&1 || return 1
  r="$(project_root "$PWD")"
  [ -n "$r" ] && (cd "$r" 2>/dev/null && pwd -P)
}

# _said_loaded <sid> <root> -> the session's load record under <root> on stdout; exit 1 when there is none
# (a symbolic link at that name is not the session's).
_said_loaded() {
  local f="${2:-}/.bionic/tmp/loaded-${1:-}.state"
  [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -f "$f" ] && [ ! -L "$f" ] || return 1
  printf '%s' "$f"
}

# The fold, ONE rule for both sides of the match and for every line a caller writes: runs of white space
# and control characters become one space, the ends trimmed.
_SAID_FOLD_JQ='def fold: gsub("[\\s\\p{Cc}]+"; " ") | sub("^ "; "") | sub(" $"; "");'

# said_fold <text> -> the folded text on stdout. The text goes in on standard input, not as an argument:
# a changelog folded through it is longer than one argument may be.
said_fold() {
  command -v jq >/dev/null 2>&1 || return 2
  printf '%s' "${1:-}" | jq -Rrs "$_SAID_FOLD_JQ"' fold'
}

# _said_sessions [<plan>] -> the sessions asked for, one per line: the plan's recorded sessions in the
# order they bound, then this session when the plan does not record it (no plan, or no reader: this
# session alone). Each the project witnesses is printed bare; each it does not, as `<sid> (<reason>)`,
# which user_said files in SAID_REFUSED and never reads. The root is user_said's (_SAID_ROOT).
_said_sessions() {
  local plan="${1:-}" rec="" me="" sid root="${_SAID_ROOT:-}" names
  if [ -n "$plan" ] && declare -F bind_sessions >/dev/null 2>&1; then
    rec="$(bind_sessions "$plan" 2>/dev/null)" || rec=""
  fi
  declare -F session_id >/dev/null 2>&1 && me="$(session_id 2>/dev/null)" || me=""
  { [ -z "$rec" ] || printf '%s\n' "$rec"
    if [ -n "$me" ] && ! grep -qxF -- "$me" <<<"$rec"; then printf '%s\n' "$me"; fi
  } | while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    case "$sid" in *[!A-Za-z0-9_-]*) printf '%s (not a session id)\n' "${sid//[!A-Za-z0-9_-]/?}"; continue ;; esac
    if ! _said_loaded "$sid" "$root" >/dev/null; then printf '%s (no loaded-%s.state)\n' "$sid" "$sid"; continue; fi
    if ! _said_transcript "$sid" "$root" >/dev/null; then
      names="$(_said_names "$sid" "$root" | paste -sd' ' - | sed 's/ / or /g')"
      printf '%s (no transcript under %s)\n' "$sid" "${names:-this project}"
      continue
    fi
    printf '%s\n' "$sid"
  done
}

# _said_names <sid> <root> -> the project directory names a witnessed session's transcript may sit under,
# one per line, in the order they are tried: this root's, then the start cwd's when its load record names
# one that differs.
_said_names() {
  local rec cwd a b=""
  declare -F project_slug >/dev/null 2>&1 || return 1
  a="$(project_slug "${2:-}")" || a=""
  if rec="$(_said_loaded "${1:-}" "${2:-}")"; then
    cwd="$(sed -n 's/^cwd=//p' "$rec" 2>/dev/null | head -1)"
    [ -z "$cwd" ] || b="$(project_slug "$cwd")" || b=""
  fi
  [ -z "$a" ] || printf '%s\n' "$a"
  [ -z "$b" ] || [ "$b" = "$a" ] || printf '%s\n' "$b"
}

# _said_transcript <sid> <root> -> that session's transcript path on stdout; exit 1 when there is none.
# Exactly the names _said_names gives, by equality; nothing else is opened.
_said_transcript() {
  local sid="${1:-}" dir s f
  case "$sid" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  declare -F project_slug >/dev/null 2>&1 || return 1
  dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    f="$dir/$s/$sid.jsonl"
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done <<SAID_NAMES
$(_said_names "$sid" "${2:-}")
SAID_NAMES
  return 1
}

# _said_in <text> <transcript> -> said, short or none on stdout; exit non-zero when it cannot be read.
# One streaming pass: each typed prompt is folded, tried whole-word, and the first that is enough ends it.
_said_in() {
  jq -nrR --arg n "${1:-}" --argjson min "$SAID_MIN_WORDS" "$_SAID_FOLD_JQ"'
    def wc: "[\\w\\x27’-]";
    def esc: gsub("(?<c>[\\\\^$.|?*+()\\[\\]{}])"; "\\\(.c)");
    def bounded($w; $p): $p | test("(?<!" + wc + ")" + ($w | esc) + "(?!" + wc + ")");
    def whole: (capture("<command-args>(?<a>[\\s\\S]*?)</command-args>") | .a | fold) // .;
    def enough($w; $p): ([$w | split(" ")[] | select(test(wc))] | length) >= $min or $w == ($p | whole);
    def words: if type == "string" then . elif type == "array" then [.[] | objects | select(.type == "text") | .text | strings] | join(" ") else "" end;
    def typed:
      if .type == "user" and .isMeta != true and .isSidechain != true and (.origin.kind? // "") == "human" then .message.content | words
      elif .type == "attachment" and .isSidechain != true and .attachment.type? == "queued_command" and .attachment.isMeta != true and (.attachment.origin.kind? // "") == "human" then .attachment.prompt | words
      else empty end;
    ($n | fold) as $w
    | if $w == "" then "none"
      else
        [label $out | inputs | fromjson? | objects | (try typed catch empty)
          | gsub("<pasted_content[^>]*>[\\s\\S]*?</pasted_content\\b[^>]*>"; " ") | fold
          | select(bounded($w; .)) as $p
          | if enough($w; $p) then ("said", break $out) else "short" end]
        | if index("said") then "said" elif length > 0 then "short" else "none" end
      end' "$2" 2>/dev/null
}

# user_said <text> [<plan>] -> 0, 1, 2 or 3, and SAID_SESSION, SAID_SESSIONS, SAID_TRIED, SAID_REFUSED,
# as above.
user_said() {
  local line sid tx out short=0
  SAID_SESSION=""; SAID_SESSIONS=""; SAID_TRIED=""; SAID_REFUSED=""
  command -v jq >/dev/null 2>&1 || return 2
  _said_need_slug || return 2
  _SAID_ROOT="$(_said_root)" || _SAID_ROOT=""
  _SAID_SIDS="$(_said_sessions "${2:-}")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sid="${line%% *}"
    SAID_TRIED="${SAID_TRIED:+$SAID_TRIED }$sid"
    if [ "$sid" != "$line" ]; then
      SAID_REFUSED="${SAID_REFUSED:+$SAID_REFUSED
}$line"
      continue
    fi
    tx="$(_said_transcript "$sid" "$_SAID_ROOT")" && [ -r "$tx" ] || continue
    out="$(_said_in "${1:-}" "$tx")" || continue
    SAID_SESSIONS="${SAID_SESSIONS:+$SAID_SESSIONS }$sid"
    case "$out" in
      said) SAID_SESSION="$sid"; return 0 ;;
      short) short=1 ;;
      none) : ;;
      *) return 2 ;;
    esac
  done <<SAID_SIDS
$_SAID_SIDS
SAID_SIDS
  [ -n "$SAID_SESSIONS" ] || return 2
  [ "$short" -eq 0 ] || return 3
  return 1
}
