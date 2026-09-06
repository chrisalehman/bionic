# tests/lib/live-answer.sh — the one ListAgents-answer builder, pinned to a committed
# corpus (wave-verification-cannot-lie S16, spec AC-27; design ledger D3).
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR is set
#     . "$(dirname "$0")/lib/live-answer.sh"
#
# WHY THE CORPUS IS THE OWNER, NOT A PRODUCTION FUNCTION (D3). Every other shape bionic
# writes has an in-tree writer a fixture can delegate to (see tests/lib/bound-marker.sh).
# The ListAgents answer has none: it is written by the Claude Code harness into the
# session transcript, never by bionic (payload/scripts/lib/agents.sh:4-7). So there is
# nothing for this file to call — the fixture-fidelity anchor is instead the CORPUS,
# committed at tests/fixtures/claude/listagents-answers.jsonl (the path names the
# adapter: the parser is core, the surface it reads is Claude-only). 26 real answers,
# captured verbatim from this project's own orchestrator session
# (`.bionic/docs/record/wave-roster-lifecycle/fixtures/listagents-results-all.jsonl`,
# machine-local — this is the committed copy the D3 consequence requires), carrying 44
# teammate rows: 33 `running`, 11 `idle` (research-code-map §2.a; verified again in
# tests/live-agents.test.sh §W). One of the 26 (index 1) is a real captured body the
# parser does NOT recognise as a ListAgents answer at all — kept as-is, because it is
# the one corpus-sourced way to exercise NONE without inventing a body.
#
# WHAT THIS FILE REPLACES. Eight suites each hand-write a three-entry ListAgents
# transcript with their own teammate-line spelling (research-code-map §2.a: four of the
# eight cannot express `idle`, three cannot express STALE). None of them is touched here
# — collapsing them onto this builder is S17's sweep. This file is the target they
# collapse onto.
#
# EVERY BODY THIS FILE EMITS IS A CORPUS LINE, VERBATIM. The self line, the ref suffix
# and every status word come from `live_answer_content`, never from a literal typed here.
# Only the ENVELOPE around a body — the assistant tool_use entry, the user tool_result
# entry, an optional trailing prompt entry — is synthesised, because the corpus itself
# records only `{ts, tool_use_id, content}` per answer, not a full transcript. Envelope
# timestamps that do not come from the corpus (the STALE wrapper's trailing prompt) are
# mechanical scaffolding, not an invented answer.
#
#   live_answer_count                    -> the corpus's line count (26)
#   live_answer_content   <n>            -> corpus line <n>'s answer body, verbatim
#   live_answer_ts        <n>            -> corpus line <n>'s captured timestamp
#   live_answer_tool_use_id <n>          -> corpus line <n>'s captured tool_use_id
#
#   live_answer_build <out> <n> [prompt_ts]
#       Writes a transcript at <out> carrying corpus line <n> as the sole ListAgents
#       answer: an assistant tool_use entry (the corpus's own id) and a user tool_result
#       entry (the corpus's own ts and content). With <prompt_ts>, a trailing user
#       prompt entry at that timestamp is appended too — freshness is measured against
#       the last prompt (payload/scripts/lib/agents.sh `_la_read`), so a prompt AFTER the
#       answer's own ts is the one way to make it STALE.
#
#   live_answer_running <out>   -> FRESH, one teammate, running (corpus line 0)
#   live_answer_idle    <out>   -> FRESH, one teammate, idle    (corpus line 8)
#   live_answer_stale   <out>   -> STALE: corpus line 0's real body, read after a later
#                                  prompt
#   live_answer_absent  <out>   -> ensures no file exists at <out> at all (NONE, exit 4,
#                                  the "absent file" arm of the parser's own contract)
#   live_answer_none    <out>   -> NONE, a real captured body the parser does not
#                                  recognise (corpus line 1; exit 4, the "unrecognised
#                                  body" arm)
#
# BASH 3.2, jq. Sourcing this file prints nothing and touches nothing beyond resolving
# BIONIC_SCRIPTS_DIR — it must already be set (source lib/resolve-roots.sh first).

if [ -z "${BIONIC_SCRIPTS_DIR:-}" ]; then
  echo "live-answer.sh: BIONIC_SCRIPTS_DIR unset — source lib/resolve-roots.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

# The five named states, each anchored to one committed corpus line — see the header.
LIVE_ANSWER_RUNNING_LINE=0
LIVE_ANSWER_IDLE_LINE=8
LIVE_ANSWER_NONE_LINE=1

live_answer_corpus_path() {
  printf '%s/tests/fixtures/claude/listagents-answers.jsonl' "$BIONIC_SCRIPTS_DIR"
}

live_answer_count() {
  wc -l < "$(live_answer_corpus_path)" | tr -d ' '
}

# The raw json line <n> (0-indexed) of the corpus, unparsed.
_live_answer_raw() {  # <n>
  sed -n "$(( ${1:-0} + 1 ))p" "$(live_answer_corpus_path)"
}

live_answer_content() {  # <n> -> the answer body, verbatim
  _live_answer_raw "$1" | jq -r '.content'
}

live_answer_ts() {  # <n> -> the captured timestamp
  _live_answer_raw "$1" | jq -r '.ts'
}

live_answer_tool_use_id() {  # <n> -> the captured tool_use_id
  _live_answer_raw "$1" | jq -r '.tool_use_id'
}

# jq -Rs turns an arbitrary shell string into a JSON string literal, so a body's real em
# dashes, middots and newlines survive into the transcript byte-for-byte (the same idiom
# tests/live-agents.test.sh's own json_str uses).
_live_answer_json_str() { printf '%s' "$1" | jq -Rs .; }

_live_answer_entry_tool_use() {  # <ts> <tool_use_id>
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"ListAgents","input":{}}]}}\n' \
    "$1" "$2"
}

_live_answer_entry_tool_result() {  # <ts> <tool_use_id> <content>
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":%s}]}}\n' \
    "$1" "$2" "$(_live_answer_json_str "$3")"
}

_live_answer_entry_prompt() {  # <ts> <text>
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":%s}}\n' \
    "$1" "$(_live_answer_json_str "$2")"
}

live_answer_build() {  # <out> <n> [prompt_ts]
  local out="$1" n="$2" prompt_ts="${3:-}" ts tid content
  ts="$(live_answer_ts "$n")"
  tid="$(live_answer_tool_use_id "$n")"
  content="$(live_answer_content "$n")"
  mkdir -p "$(dirname "$out")"
  {
    _live_answer_entry_tool_use "$ts" "$tid"
    _live_answer_entry_tool_result "$ts" "$tid" "$content"
    [ -z "$prompt_ts" ] || _live_answer_entry_prompt "$prompt_ts" "a later turn"
  } > "$out"
}

live_answer_running() { live_answer_build "$1" "$LIVE_ANSWER_RUNNING_LINE"; }
live_answer_idle()    { live_answer_build "$1" "$LIVE_ANSWER_IDLE_LINE"; }

# Corpus line 0's own real answer is timestamped 2026-09-05T00:52:23.349Z. Any prompt
# after that makes it STALE; the trailing prompt's own timestamp is envelope scaffolding,
# not an invented answer (see header).
live_answer_stale() { live_answer_build "$1" "$LIVE_ANSWER_RUNNING_LINE" "2026-09-05T01:00:00.000Z"; }

live_answer_absent() { rm -f "$1"; }

live_answer_none() { live_answer_build "$1" "$LIVE_ANSWER_NONE_LINE"; }

# ---------------------------------------------------------------------------
# COMPOSING AN ANSWER THAT NAMES THE SUITE'S OWN TEAMMATES (S17, spec AC-28)
#
# The eight private builders this file replaces did not want a corpus line — they wanted
# an answer naming `alpha`, `battery`, `w1r-slice-4-3`, whatever the case under test had
# just written a roster row for. That is why each of them hand-wrote a teammate line, and
# why the tree ended up with three spellings of the recognition anchor and two of the ref
# suffix.
#
# So the composer below builds the answer out of the corpus's OWN LINES and substitutes
# only the values a case names: the self line is corpus line 0's first line verbatim; the
# `Teammates (N):` header is corpus line 0's header with its count replaced; each teammate
# row is corpus line 0's teammate row with the name, type and status replaced IN PLACE —
# the indent, the ref suffix, the middot separator and the `started …` tail all stay the
# bytes the harness wrote. Nothing here types a separator or a suffix; every one of them is
# read back out of the corpus at call time, so the day the harness changes its row format
# the fixtures change with it (which is the whole of D3).
#
# WHAT IT DELIBERATELY CANNOT DO. It cannot emit a second `Teammates (N):` header, a
# reordered block, a truncated self line or a body with the middot replaced — the malformed
# shapes `tests/live-agents.test.sh` feeds the parser. Those are the PARSER's inputs, not
# fixtures for anything else, and a builder able to produce them would be able to produce
# them by accident. They stay hand-written in that one suite; see the AC-28 section of
# tests/cross-gate-agreement.test.sh, which names the exemption and holds it to one file.
#
#   live_answer_self_line                    -> the corpus's recognition anchor, verbatim
#   live_answer_block_header <n>             -> the corpus's block header, count replaced
#   live_answer_teammate_line <name> [status] [type]
#                                            -> the corpus's teammate row, values replaced
#   live_answer_body <name[:status[:type]]>...
#                                            -> a whole answer body; with NO names, the
#                                               self line alone (recognisable, zero
#                                               teammates — the shape a session with no
#                                               live agents gets)
#
# `LIVE_ANSWER_TYPE` sets the type every row carries when a caller does not name one, so a
# suite whose assertions pin `bionic:senior-implementor` sets it once. Unset, the rows carry
# the corpus's own type.

# Corpus line 0 is the template for every composed row: one running teammate, the shape the
# harness writes. `_LIVE_ANSWER_ROW` / `_LIVE_ANSWER_SELF` / `_LIVE_ANSWER_HDR` cache the
# three pieces, because composing an answer is on the inner loop of several suites and each
# read is a `sed` plus a `jq` over the corpus.
_LIVE_ANSWER_SELF=""
_LIVE_ANSWER_HDR=""
_LIVE_ANSWER_ROW=""

# The real 03:07:41.801Z answer: one writer idle beside one running. The one corpus line
# that carries two teammates in different states, which is what the budget's open-count
# cases need.
LIVE_ANSWER_MIXED_LINE=7

_live_answer_template() {
  [ -n "$_LIVE_ANSWER_SELF" ] && return 0
  local body
  body="$(live_answer_content "$LIVE_ANSWER_RUNNING_LINE")"
  _LIVE_ANSWER_SELF="$(printf '%s\n' "$body" | sed -n '1p')"
  _LIVE_ANSWER_HDR="$(printf '%s\n' "$body" | LC_ALL=C awk '/^Teammates \([0-9]+\):[ \t]*$/ { print; exit }')"
  _LIVE_ANSWER_ROW="$(printf '%s\n' "$body" | LC_ALL=C awk '
    /^Teammates \([0-9]+\):[ \t]*$/ { f = 1; next }
    f && /^[ \t]+[^ \t]/            { print; exit }')"
  [ -n "$_LIVE_ANSWER_SELF" ] && [ -n "$_LIVE_ANSWER_HDR" ] && [ -n "$_LIVE_ANSWER_ROW" ]
}

live_answer_self_line() {
  _live_answer_template || return 1
  printf '%s\n' "$_LIVE_ANSWER_SELF"
}

live_answer_block_header() {  # <count> -> the corpus header with its count replaced
  _live_answer_template || return 1
  printf '%s\n' "$_LIVE_ANSWER_HDR" | sed "s/([0-9][0-9]*)/(${1:-1})/"
}

# The corpus's own teammate row with the name, type and status substituted in place. Every
# byte that is not one of those three — the indent, the whitespace before the ref bracket,
# the ref itself, the separator, the `started …` tail — is carried over from the corpus row
# by position, never re-typed.
live_answer_teammate_line() {  # <name> [status] [type]
  _live_answer_template || return 1
  printf '%s\n' "$_LIVE_ANSWER_ROW" | LC_ALL=C awk \
    -v nm="$1" -v st="${2:-}" -v ty="${3:-${LIVE_ANSWER_TYPE:-}}" '
    {
      line = $0
      match(line, /^[ \t]*/); indent = substr(line, 1, RLENGTH)
      line = substr(line, RLENGTH + 1)
      match(line, /[ \t]*·[ \t]*/); sep = substr(line, RSTART, RLENGTH)
      n = split(line, p, /[ \t]*·[ \t]*/)
      if (nm != "") {
        ref = ""
        if (match(p[1], /[ \t]*\[[^]]*\][ \t]*$/)) ref = substr(p[1], RSTART)
        p[1] = nm ref
      }
      if (ty != "" && n >= 2) p[2] = ty
      if (st != "" && n >= 3) p[3] = st
      out = p[1]
      for (i = 2; i <= n; i++) out = out sep p[i]
      print indent out
    }'
}

# live_answer_body <name[:status[:type]]>... -> a whole answer body on stdout.
live_answer_body() {
  _live_answer_template || return 1
  live_answer_self_line
  [ "$#" -gt 0 ] || return 0
  printf '\n'
  live_answer_block_header "$#"
  local spec nm rest st ty
  for spec in "$@"; do
    nm="${spec%%:*}"; rest="${spec#*:}"
    st=""; ty=""
    if [ "$rest" != "$spec" ]; then
      st="${rest%%:*}"
      ty="${rest#*:}"
      [ "$ty" = "$rest" ] && ty=""
    fi
    live_answer_teammate_line "$nm" "$st" "$ty"
  done
}
