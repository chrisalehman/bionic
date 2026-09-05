# payload/scripts/lib/agents.sh — the live-agent set (wave-roster-lifecycle S4,
# spec AC-6; design ledger D1′/D2′, spec ## Design §2 "Live-agents reader").
#
# THE RULE (D0). One owner per liveness truth, read at the moment of use. The truth
# about which agents exist belongs to the harness, and only the model can ask it. So
# the model calls ListAgents and the harness records the answer in the session
# transcript every hook is handed; this library is the ONE parser of that recording.
# `dispatch-preflight.sh` (budget count), `stop-guard.sh` and `stop-check.sh`
# (resolution), `stop-orders.sh standdown` (report) and `session-poker.sh tick` (the
# fill it prints) all call these functions. None of them re-reads a transcript itself,
# so a change to the harness's output format moves every reader at once.
#
# ONE LEVEL UP FROM THE READER there is one DERIVED question, and it has one owner too:
# `live_row_open` (bottom of this file), which answers "does this roster row still hold
# a writer slot". The budget wall and the Patrol tick both ask it, and S19 exists because
# they used to answer it separately.
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
#   P <ts>                     a user PROMPT entry
#
# WHAT COUNTS AS A PROMPT, AND WHY IT IS NOT "content is a string" (Step-6 review
# S-1 = C-3). It was exactly that, and the harness writes a prompt carrying a pasted
# image as an ARRAY of content blocks — `{type:"text"}` beside `{type:"image"}`. Those
# entries fell through both branches, so the freshness comparison at the bottom of
# `live_agents` measured the answer against some OLDER prompt and called a stale answer
# FRESH: the fail-OPEN direction, on the one rule AC-8's refusal and the stop guard's
# resolution both rest on. A user entry is now a prompt when its content is a string,
# OR when its content array carries at least one `text` block and NO `tool_result`
# block. The `tool_result` exclusion is load-bearing: every tool result in the session
# is a user entry with array content, and counting one as a prompt would stale every
# answer the instant the next tool ran. Over-counting prompts — a skill injection, say,
# which arrives as a bare `text` array — fails toward STALE, and STALE is the side that
# refuses and names its own repair.
_la_scan() {  # <transcript>
  jq -Rr '
    (fromjson? // empty) as $e
    | ($e.timestamp // "") as $ts
    | if ($e.type? == "assistant") and (($e.message?.content? // null) | type == "array") then
        $e.message.content[]
        | select((.type? == "tool_use") and (.name? == "ListAgents"))
        | "U\t" + (.id // "")
      elif ($e.type? == "user") and (($e.message?.content? // null) | type == "array") then
        ($e.message.content) as $c
        | if ([ $c[] | select(.type? == "tool_result") ] | length) > 0 then
            $c[]
            | select(.type? == "tool_result")
            | "R\t" + (.tool_use_id // "") + "\t" + $ts
          elif ([ $c[] | select(.type? == "text") ] | length) > 0 then
            "P\t" + $ts
          else empty
          end
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
    BEGIN { inblk = 0; recog = 0; seen = 0 }
    /^This session is / { recog = 1 }
    # ANCHORED ON THE FIRST HEADER (Step-6 review S-2). This used to re-open the block on
    # ANY flush-left `Teammates (N):` line, anywhere in the body, including after
    # `Peer sessions`. The body carries free-form operator-visible text — the session name
    # and the peer titles — and a newline embedded in either produces a flush-left line, so
    # a second header could forge a teammate into the live set. The format the harness
    # writes was the only thing keeping the parser honest. One block per answer, the first.
    /^Teammates \([0-9]+\):[ \t]*$/ {
      recog = 1
      if (!seen) { seen = 1; inblk = 1 } else { inblk = 0 }
      next
    }
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

# ONE PARSE PER PROCESS, PER FILE STATE (Step-6 review P-1 = P-4). Every consumer that
# asks about more than one name paid a full parse per question: the budget wall calls
# `live_row_open` once per roster row and the Patrol tick once per open row, and each of
# those is two whole-file `jq` passes plus nine process spawns. Measured on a 4.1 MB
# transcript and 12 rows: 1.22 s, over the ~1 s budget for a hook that fronts every
# dispatch, and the row count grows for the life of a session while the transcript does
# too. The answer is memoized here rather than in either caller, because both callers ask
# the same question of the same file and a cache in one of them would leave the other slow.
#
# THE KEY IS PATH + SIZE + MTIME, WHICH IS WHY THIS IS NOT A BEHAVIOUR CHANGE. Transcripts
# are appended to live, so a file that grew between two calls has a different size and
# re-parses. The stop path deliberately reads the transcript twice in one process
# (`live_agents_has`, then `live_agents` again for the duplicate count) and that pair still
# sees any append that landed between them — the perf reviewer's critic note asked for
# exactly this to be preserved rather than smuggled shut.
#
# ONE SLOT, AND IT LIVES FOR ONE PROCESS. bash 3.2 has no associative arrays and one
# invocation reads one transcript, so a single slot is enough. It is NEVER written to disk
# and never shared between invocations: a cross-invocation cache would answer a later hook
# from an earlier hook's reading of a file that has since moved, which is the one thing
# this reader exists not to do.
_LA_CACHE_KEY=""
_LA_CACHE_OUT=""
_LA_CACHE_ERR=""
_LA_CACHE_RC=0

_la_cache_key() {  # <transcript> -> path|bytes|mtime, empty when the file cannot be read
  local f="${1:-}" fact
  [ -n "$f" ] && [ -r "$f" ] || return 0
  # ONE spawn, not two: BSD stat first, GNU stat as the fallback, the same idiom
  # payload/scripts/lib/run.sh uses for mtime.
  fact="$(stat -f '%z|%m' "$f" 2>/dev/null || stat -c '%s|%Y' "$f" 2>/dev/null)" || fact=""
  case "$fact" in ''|*'|') return 0 ;; esac
  printf '%s|%s' "$f" "$fact"
}

# THE CACHE FILL, AND IT MUST NOT RUN IN A SUBSHELL. `_la_read` below does the work and
# answers into the three cache variables instead of into stdout/stderr, so one parse can be
# replayed to every caller in one process. Every consumer therefore goes through THIS
# function rather than through `$(live_agents …)`: a command substitution forks, and a
# subshell's cache write dies with it — the reason `live_agents_status` reads
# `$_LA_CACHE_OUT` directly below instead of capturing `live_agents`'s stdout the way it
# used to. It emits the one stderr line and returns the reader's own exit code.
_la_ensure() {  # <transcript.jsonl>
  local key
  key="$(_la_cache_key "${1:-}")" || key=""
  if [ -z "$key" ] || [ "$key" != "$_LA_CACHE_KEY" ]; then
    _la_read "${1:-}"
    _LA_CACHE_KEY="$key"
  fi
  printf '%s\n' "$_LA_CACHE_ERR" >&2
  return "$_LA_CACHE_RC"
}

live_agents() {  # <transcript.jsonl>
  local rc=0
  _la_ensure "${1:-}" || rc=$?
  [ -z "$_LA_CACHE_OUT" ] || printf '%s\n' "$_LA_CACHE_OUT"
  return "$rc"
}

_la_read() {  # <transcript.jsonl> -> sets _LA_CACHE_OUT / _LA_CACHE_ERR / _LA_CACHE_RC
  local transcript="${1:-}"
  local scan index ans_id ans_ts last_prompt body set_out state age epoch now prc

  _LA_CACHE_OUT=""
  _LA_CACHE_ERR="live-agents: none age=none"
  _LA_CACHE_RC=4

  if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
    return 0
  fi

  scan="$(_la_scan "$transcript")" || scan=""

  # Newest ListAgents answer, and the last user prompt, in one pass over the index.
  #
  # BOTH COMPARISONS ARE ON THE NORMALISED TIMESTAMP (Step-6 review C-4). Lexicographic
  # order IS chronological for UTC ISO-8601, but only once the fractional part has a fixed
  # width: `…:23.45Z` sorts BELOW `…:23.4Z` as a raw string, because `5` < `Z`. That is
  # precisely why `_la_norm_ts` exists for the fresh/stale test 60 lines below — and this
  # reducer, which decides WHICH answer is newest and WHICH prompt is last, did the raw
  # compare the normaliser was written to prevent. `nts` here is `_la_norm_ts` transcribed
  # into awk; the raw value is what is emitted, so the age arithmetic still reads the
  # timestamp the harness wrote.
  index="$(printf '%s\n' "$scan" | LC_ALL=C awk -F'\t' '
    function nts(t,   i, base, frac) {
      if (t == "") return ""
      i = index(t, ".")
      if (i > 0) { base = substr(t, 1, i - 1); frac = substr(t, i + 1) }
      else       { base = t;                   frac = "" }
      sub(/Z$/, "", base)
      sub(/Z$/, "", frac)
      frac = frac "000"
      return base "." substr(frac, 1, 3)
    }
    $1 == "U" { ids[$2] = 1; next }
    $1 == "R" {
      if (($2 in ids) && $3 != "") {
        k = nts($3)
        if (k >= ans_k) { ans_k = k; ans_ts = $3; ans_id = $2 }
      }
      next
    }
    $1 == "P" { k = nts($2); if (k > last_k) { last_k = k; last_p = $2 } next }
    END { printf "%s\t%s\t%s\n", ans_id, ans_ts, last_p }
  ')" || index=""

  ans_id="$(printf '%s' "$index" | cut -f1)" || ans_id=""
  ans_ts="$(printf '%s' "$index" | cut -f2)" || ans_ts=""
  last_prompt="$(printf '%s' "$index" | cut -f3)" || last_prompt=""

  if [ -z "$ans_id" ]; then
    return 0
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
    return 0
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

  _LA_CACHE_ERR="live-agents: ${state} age=${age}"
  _LA_CACHE_OUT="$set_out"
  if [ "$state" = "fresh" ]; then
    _LA_CACHE_RC=0
  else
    _LA_CACHE_RC=3
  fi
  return 0
}

# THE STATUS OF ONE NAME, off the SAME parse `live_agents_has` reads (spec R2, AC-27).
#
# R2 names two ways an agent goes: "delivered and stopped, or finished and never stopped".
# The harness keeps LISTING the second kind — status `idle` — because it stays addressable:
# a SendMessage would resume it. So presence answers "is this name still on the roster the
# harness prints", and it is the right question for a STOP (an idle agent is exactly the one
# you stop). It is the wrong question for a BUDGET, which wants to know whether the row is
# still a writer. That is a question about the status, and this is where it is answered —
# from one `live_agents` call, so the two consumers can never disagree about who is listed.
#
# Same exit codes as `live_agents_has`, deliberately: a caller that switches between them
# branches identically, and only the stdout differs.
#
#   exit 0  the name is present exactly once   — its status word on stdout
#   exit 1  the name is absent (or empty)      — no stdout
#   exit 2  the name is present more than once — no stdout, nothing to report
#   exit 3/4 propagated from live_agents unchanged
# `_LA_STATUS_WORD` carries the status word to a caller in the SAME process, beside the
# stdout copy. `live_row_open` reads it rather than `$(live_agents_status …)` for the
# reason `_la_ensure` exists: a command substitution forks, and the fork would leave the
# parse cache cold for every row after the first.
_LA_STATUS_WORD=""

live_agents_status() {  # <transcript.jsonl> <name>
  local transcript="${1:-}" want="${2:-}" set_out rc pair count st

  _LA_STATUS_WORD=""
  rc=0
  _la_ensure "$transcript" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  set_out="$_LA_CACHE_OUT"

  [ -n "$want" ] || return 1

  # Count and status in ONE pass, on two lines. The counting predicate is character for
  # character `live_agents_has`'s, so the two can never disagree about WHO is listed — only
  # about what the status means. Two lines rather than one joined field because a status is
  # whatever the harness printed between two middots: never assume it holds no separator,
  # and never make a tab in this file's source load-bearing.
  pair="$(printf '%s\n' "$set_out" | LC_ALL=C awk -F'|' -v want="$want" '
    NF >= 1 && $1 == want { n++; st = $3 }
    END { print n + 0; print st }
  ')" || pair=""

  count="$(printf '%s\n' "$pair" | sed -n '1p')" || count=""
  st="$(printf '%s\n' "$pair" | sed -n '2p')" || st=""

  case "$count" in
    0|"") return 1 ;;
    1)     _LA_STATUS_WORD="$st"; printf '%s\n' "$st"; return 0 ;;
    *)     return 2 ;;
  esac
}

live_agents_has() {  # <transcript.jsonl> <name>
  local transcript="${1:-}" want="${2:-}" set_out rc count

  rc=0
  _la_ensure "$transcript" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  set_out="$_LA_CACHE_OUT"

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

# ROW-OPENNESS: THE ONE PREDICATE, AND IT FAILS CLOSED (spec R2, AC-27; S19, closing the
# Step-5 auditor's F-13/F-14).
#
# THE QUESTION. "Does this roster row still hold a writer slot?" Two consumers ask it —
# hooks/dispatch-preflight.sh's budget wall, which refuses a dispatch on the answer, and
# hooks/session-poker.sh's tick, which sizes the FILL it prints. They asked it in two
# places until S19, and a disagreement between them is a Patrol advertising a dispatch the
# wall is about to refuse. One owner, here.
#
# THE RULE IS AN INVERSION, and the inversion is the fix. S16 wrote "open iff the status is
# exactly `running`", inline in the budget. That is fail-OPEN: a status word this parser has
# never seen — a renamed one, a third one the harness starts printing — read as CLOSED and
# handed out a writer slot, in the same function whose ambiguity arm deliberately spends one.
# So the rule is now "open unless the harness said `idle`".
#
# THE CORPUS THE RULE RESTS ON. 26 real ListAgents answers captured from this project's own
# orchestrator session carry 44 teammate rows and exactly two status words — 33 `running`,
# 11 `idle` (Step-5 auditor pass 2, Level 1; the capture is
# `.bionic/docs/record/wave-roster-lifecycle/fixtures/listagents-results-all.jsonl`). `idle`
# is the ONE word the harness has been observed to use for "finished its turn, still
# addressable", so it is the one word this predicate is entitled to read as closed.
# Everything else is a reading nobody has taken, and spending a slot on it costs a dispatch
# that waits; freeing one costs a wave that over-dispatches past its own ceiling.
#
# AMBIGUITY IS OPEN, for the same asymmetry `live_agents_status` already documents: a name
# the reader could not resolve is not a name it called finished.
#
# STALE AND NONE PROPAGATE VERBATIM (3/4), never collapsing into "not open". Freshness is a
# property of the transcript, not of any one name, and each caller owns what it does about
# it — the wall refuses the whole dispatch, the tick falls back to its roster and says so.
#
#   live_row_open <transcript.jsonl> <name>
#     exit 0  OPEN     — present exactly once with a status that is NOT `idle`, or present
#                        more than once (unresolvable)
#     exit 1  NOT OPEN — absent, empty name, or present exactly once with status `idle`
#     exit 3  STALE    — propagated from live_agents unchanged
#     exit 4  NONE     — propagated from live_agents unchanged
#     prints nothing on stdout; live_agents' one stderr line passes through.
_LA_ROW_CLOSED_STATUS="idle"

live_row_open() {  # <transcript.jsonl> <name>
  local rc
  rc=0
  # NOT `$(live_agents_status …)`: the substitution would fork, and the parse cache the
  # fork fills dies with it — which is the whole of P-1 for a caller asking about N rows.
  # The status word comes back in `_LA_STATUS_WORD`, set on the same arm that prints it.
  live_agents_status "$1" "${2:-}" >/dev/null || rc=$?
  case "$rc" in
    0)
      # Present exactly once. Only the one observed closed word closes the row.
      if [ "$_LA_STATUS_WORD" = "$_LA_ROW_CLOSED_STATUS" ]; then return 1; fi
      return 0
      ;;
    1) return 1 ;;
    2) return 0 ;;
    *) return "$rc" ;;
  esac
}
