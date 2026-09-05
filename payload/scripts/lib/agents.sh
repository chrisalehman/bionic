# payload/scripts/lib/agents.sh — the live-agent set (wave-roster-lifecycle S4,
# spec AC-6; design ledger D1′/D2′, spec ## Design §2 "Live-agents reader").
#
# THE RULE (D0). One owner per liveness truth, read at the moment of use. The truth
# about which agents exist belongs to the harness, and only the model can ask it. So
# the model calls ListAgents and the harness records the answer in the session
# transcript every hook is handed; this library is the ONE parser of that recording.
# `dispatch-preflight.sh` (budget count), `stop-guard.sh` and `stop-check.sh`
# (resolution), `stop-orders.sh standdown` (report) and `session-poker.sh tick` all
# call these two functions. None of them re-reads a transcript itself, so a change to
# the harness's output format moves every reader at once.
#
# WHY NOT THE ROSTER, THE Stop PAYLOAD, OR A MARKER. The roster records that a
# dispatch happened, never that an agent is alive. The Stop payload's
# `background_tasks[]` is a history for teammates — a finished agent stays
# `status:"running"` until the session ends, and its rows carry no name (measured:
# t1-probe-report §2.3, landing-gate.sh:185-190). A closure marker written at stop is
# a copy flipped by observable events and cannot express finished-but-unstopped, which
# IS the reported bug. All three were rejected in D1′.
#
#   live_agents <transcript.jsonl>
#     stdout  one `name|type|status` line per teammate of the NEWEST recorded
#             ListAgents answer, in the order the harness printed them; zero lines
#             when that answer carries no Teammates block.
#     exit 0  FRESH — the answer's entry timestamp is later than the last user-prompt
#             entry's, i.e. it was recorded this turn.
#     exit 3  STALE — an answer exists but does not postdate the last user prompt.
#     exit 4  NONE  — no usable ListAgents answer (absent file, no ListAgents call, a
#             call whose result never arrived, or a body this parser does not
#             recognise).
#     stderr  exactly one line: `live-agents: <fresh|stale|none> age=<seconds|none>`
#
#   live_agents_has <transcript.jsonl> <name>
#     exit 0  FRESH and <name> is one teammate, exactly once
#     exit 1  FRESH and <name> is not a teammate
#     exit 2  <name> names more than one teammate (two sessions in one root can launch
#             same-named agents — the ambiguity D2′ preserves rather than guesses at)
#     exit 3/4 propagated from live_agents unchanged
#     prints nothing on stdout; live_agents' one stderr line passes through.
#
# THE ANSWER IS FOUND BY THE ID JOIN. A tool_result is a ListAgents answer iff its
# `tool_use_id` matches an assistant `tool_use` block whose `.name` is `ListAgents`.
# Body sniffing would let any tool that echoed the words "Teammates (N):" — a Bash
# `cat` of the test fixture, say — impersonate the harness.
#
# AN UNRECOGNISED BODY IS `none`, NEVER "all gone" (spec §5 Assumptions). The
# expensive failure is a silent empty set: zero teammates read out of a body we did
# not understand tells the dispatch wall the roster is clear and tells the stop guard
# its target is dead. A body carrying none of the harness's section markers is
# therefore NONE — the callers' refuse-and-name-the-fix path — while a body that IS a
# recognisable answer listing no teammates is FRESH with zero lines. Empty answer ≠
# absent answer.
#
# A STALE ANSWER STILL PRINTS ITS SET, for the same asymmetry. A caller that misread
# the status and got an empty set would over-dispatch and refuse valid stops; the same
# caller getting the stale set merely over-counts the budget and stops an agent that
# may already be gone. Only the exit status ever says "do not act".
#
# BASH 3.2, jq, awk. Sourcing this file prints nothing, touches nothing and defines
# only the functions below — it is sourced by hooks running under `set -u`.

# Now, in epoch seconds. `BIONIC_NOW_EPOCH` pins it so suites are arithmetic, not
# clock readings — the same idiom resources.sh and run.sh use.
_la_now_epoch() {
  if [ -n "${BIONIC_NOW_EPOCH:-}" ]; then
    printf '%s' "$BIONIC_NOW_EPOCH"
  else
    date -u +%s
  fi
}

# <ISO-8601 with optional fraction> -> epoch seconds, empty when unreadable.
_la_iso_epoch() {
  local ts="${1:-}"
  [ -n "$ts" ] || return 0
  ts="${ts%%.*}"
  case "$ts" in
    *Z) : ;;
    *)  ts="${ts}Z" ;;
  esac
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null \
    || date -u -d "$ts" +%s 2>/dev/null \
    || true
}

# Timestamps are compared as strings — lexicographic order IS chronological for UTC
# ISO-8601 — but only once the fractional part has a fixed width, or `…:23.4Z` would
# sort below `…:23.35Z`. Normalise to exactly three fractional digits.
_la_norm_ts() {
  local ts="${1:-}" base frac
  [ -n "$ts" ] || return 0
  base="${ts%%.*}"
  base="${base%Z}"
  case "$ts" in
    *.*) frac="${ts#*.}"; frac="${frac%Z}" ;;
    *)   frac="" ;;
  esac
  frac="${frac}000"
  printf '%s.%s' "$base" "${frac:0:3}"
}

# Pass 1 over the transcript: one tab-separated record per interesting entry, WITHOUT
# any answer bodies. Transcripts run to tens of megabytes, and only one body is ever
# needed. `jq -R` with `fromjson?` reads line by line and drops anything that is not
# valid JSON, so a torn final line (transcripts are appended to live) costs nothing.
#
#   U <tool_use_id>            an assistant ListAgents call
#   R <tool_use_id> <ts>       a tool_result entry, with its entry timestamp
#   P <ts>                     a user PROMPT entry (.message.content a plain string)
_la_scan() {  # <transcript>
  jq -Rr '
    (fromjson? // empty) as $e
    | ($e.timestamp // "") as $ts
    | if ($e.type? == "assistant") and (($e.message?.content? // null) | type == "array") then
        $e.message.content[]
        | select((.type? == "tool_use") and (.name? == "ListAgents"))
        | "U\t" + (.id // "")
      elif ($e.type? == "user") and (($e.message?.content? // null) | type == "array") then
        $e.message.content[]
        | select(.type? == "tool_result")
        | "R\t" + (.tool_use_id // "") + "\t" + $ts
      elif ($e.type? == "user") and (($e.message?.content? // null) | type == "string") then
        "P\t" + $ts
      else empty
      end
  ' "$1" 2>/dev/null
}

# Pass 2: the body of one known tool_result, joined by id. `content` is a string in
# most entries and an array of text blocks in some; both are real shapes.
_la_body() {  # <transcript> <tool_use_id>
  jq -Rr --arg id "$2" '
    (fromjson? // empty)
    | select(.type? == "user")
    | select((.message?.content? // null) | type == "array")
    | .message.content[]
    | select((.type? == "tool_result") and (.tool_use_id? == $id))
    | (.content // "")
    | if type == "string" then .
      elif type == "array" then ([ .[] | select(.type? == "text") | (.text // "") ] | join("\n"))
      else "" end
  ' "$1" 2>/dev/null
}

# The Teammates block, on stdin -> `name|type|status` lines. Exit 9 when the body
# carries none of the harness's section markers, i.e. this is not an answer we can
# read. LC_ALL=C so the middot separator is compared as its two UTF-8 bytes and a
# body with any invalid sequence in it cannot abort the parse.
_la_parse_teammates() {
  LC_ALL=C awk '
    BEGIN { inblk = 0; recog = 0 }
    /^This session is / { recog = 1 }
    /^Teammates \([0-9]+\):[ \t]*$/    { recog = 1; inblk = 1; next }
    /^Peer sessions \([0-9]+\):[ \t]*$/ { recog = 1; inblk = 0; next }
    {
      if (!inblk) next
      # A blank line or any flush-left line closes the block.
      if ($0 !~ /^[ \t]+[^ \t]/) { inblk = 0; next }
      line = $0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      n = split(line, p, /[ \t]*·[ \t]*/)
      if (n < 3) next
      name = p[1]
      sub(/[ \t]*\[[^]]*\][ \t]*$/, "", name)   # drop the harness ref suffix
      sub(/[ \t]+$/, "", name)
      type = p[2]; sub(/^[ \t]+/, "", type); sub(/[ \t]+$/, "", type)
      status = p[3]; sub(/^[ \t]+/, "", status); sub(/[ \t]+$/, "", status)
      if (name != "") print name "|" type "|" status
    }
    END { if (!recog) exit 9 }
  '
}

live_agents() {  # <transcript.jsonl>
  local transcript="${1:-}"
  local scan index ans_id ans_ts last_prompt body set_out state age epoch now prc

  if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
    echo "live-agents: none age=none" >&2
    return 4
  fi

  scan="$(_la_scan "$transcript")" || scan=""

  # Newest ListAgents answer, and the last user prompt, in one pass over the index.
  index="$(printf '%s\n' "$scan" | LC_ALL=C awk -F'\t' '
    $1 == "U" { ids[$2] = 1; next }
    $1 == "R" { if (($2 in ids) && $3 != "" && $3 >= ans_ts) { ans_ts = $3; ans_id = $2 } next }
    $1 == "P" { if ($2 > last_p) last_p = $2; next }
    END { printf "%s\t%s\t%s\n", ans_id, ans_ts, last_p }
  ')" || index=""

  ans_id="$(printf '%s' "$index" | cut -f1)" || ans_id=""
  ans_ts="$(printf '%s' "$index" | cut -f2)" || ans_ts=""
  last_prompt="$(printf '%s' "$index" | cut -f3)" || last_prompt=""

  if [ -z "$ans_id" ]; then
    echo "live-agents: none age=none" >&2
    return 4
  fi

  # EVERY command substitution below is guarded with `|| var=…`. A hook may run
  # `set -euo pipefail`, and an unguarded assignment whose command exits non-zero — the
  # parser's own exit 9, which is a RESULT here, not a failure — would kill the caller
  # before it could print the refusal this reader exists to justify.
  body="$(_la_body "$transcript" "$ans_id")" || body=""
  prc=0
  set_out="$(printf '%s\n' "$body" | _la_parse_teammates)" || prc=$?
  if [ "$prc" -ne 0 ]; then
    # Recognisably not an answer: refuse rather than report an empty roster.
    echo "live-agents: none age=none" >&2
    return 4
  fi

  now="$(_la_now_epoch)" || now=""
  epoch="$(_la_iso_epoch "$ans_ts")" || epoch=""
  if [ -n "$epoch" ] && [ -n "$now" ]; then
    age=$(( now - epoch ))
    [ "$age" -ge 0 ] || age=0
  else
    age="none"
  fi

  if [ "$(_la_norm_ts "$ans_ts")" \> "$(_la_norm_ts "$last_prompt")" ]; then
    state="fresh"
  else
    state="stale"
  fi

  echo "live-agents: ${state} age=${age}" >&2
  [ -z "$set_out" ] || printf '%s\n' "$set_out"

  if [ "$state" = "fresh" ]; then
    return 0
  fi
  return 3
}

live_agents_has() {  # <transcript.jsonl> <name>
  local transcript="${1:-}" want="${2:-}" set_out rc count

  rc=0
  set_out="$(live_agents "$transcript")" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"

  [ -n "$want" ] || return 1

  count="$(printf '%s\n' "$set_out" | LC_ALL=C awk -F'|' -v want="$want" '
    NF >= 1 && $1 == want { n++ } END { print n + 0 }
  ')" || count=""

  case "$count" in
    0|"") return 1 ;;
    1)     return 0 ;;
    *)     return 2 ;;
  esac
}
