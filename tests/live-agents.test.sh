#!/bin/bash
# tests/live-agents.test.sh — payload/scripts/lib/agents.sh: the live-agent set reader
# (wave-roster-lifecycle S4, spec AC-6; design ledger D1′/D2′).
#
# WHAT THIS SUITE OWNS. One question, asked of a transcript file: WHICH AGENTS DID THE
# HARNESS SAY WERE ALIVE, and IS THAT ANSWER STILL THIS TURN'S. Design principle D0 —
# one owner per liveness truth, read at the moment of use — makes this the only parser
# in bionic for the harness's ListAgents answer. dispatch-preflight's budget count,
# stop-guard's and stop-check's resolution, standdown's report and the Patrol tick all
# call it; none of them re-reads the transcript itself.
#
#   live_agents <transcript.jsonl>
#       stdout  one `name|type|status` line per teammate of the NEWEST recorded answer
#               (zero lines when that answer carries no Teammates block)
#       exit 0  FRESH — the answer's entry postdates the last user-prompt entry
#       exit 3  STALE — an answer exists but predates the last user prompt
#       exit 4  NONE  — no usable ListAgents answer in the file
#       stderr  exactly one line: `live-agents: <fresh|stale|none> age=<seconds|none>`
#
#   live_agents_has <transcript.jsonl> <name>
#       exit 0  FRESH and the name appears exactly once
#       exit 1  FRESH and the name is absent
#       exit 2  FRESH and the name appears more than once
#       exit 3/4 propagated from live_agents unchanged
#
# WHY THE ID JOIN IS THE CONTRACT, NOT THE BODY TEXT. A ListAgents answer is located by
# joining a `tool_result`'s `tool_use_id` back to the assistant `tool_use` block whose
# `.name` is `ListAgents`. Content sniffing would let any tool that happened to echo the
# words "Teammates (N):" — a Bash `cat` of this very test file, say — masquerade as the
# harness's answer. §J drives exactly that forgery and requires it to be ignored.
#
# WHY AN UNPARSEABLE ANSWER IS `none` AND NEVER "all gone" (spec §5 Assumptions). The
# expensive failure mode is a silent empty set: a reader that returns zero teammates from
# a body it did not understand tells the dispatch wall the roster is clear and tells the
# stop guard its target is dead. So a body carrying none of the three section markers the
# harness writes is NONE — the callers' refuse-and-name-the-fix path — while a body that
# IS recognisably a ListAgents answer and simply lists no teammates is FRESH with zero
# lines. §D and §F are that pair, and they are the reason both exist.
#
# FIXTURE FIDELITY (declared, per .claude memory fixtures-can-pin-away-the-test). The two
# answer bodies below are REAL, captured verbatim from this project's own session
# transcript into
# `.bionic/docs/record/wave-roster-lifecycle/fixtures/listagents-results.jsonl` (12
# results; the one timestamped 2026-09-05T00:52:23.349Z carries the `Teammates (1):`
# block naming the researcher `research-code-map` running, the earlier ones carry none).
# They are inlined here rather than read from that path because `.bionic/` is gitignored
# — a suite that read it would pass on this machine and fail in a fresh clone. The
# surrounding transcript entries are composed from the real entry shapes: an assistant
# entry whose `.message.content[]` holds `{type:"tool_use", name:"ListAgents", id:…}`, a
# user entry whose `.message.content[]` holds `{type:"tool_result", tool_use_id:…,
# content:…}` with content a string OR an array of `{type:"text",text}`, a user PROMPT
# entry whose `.message.content` is a plain string, and `.timestamp` on every entry.
#
# HERMETIC. Every transcript is built under a mktemp sandbox; nothing reads a real
# session transcript, a real roster or a live wave. `BIONIC_NOW_EPOCH` pins "now" so the
# age arithmetic is a constant, not a clock reading.
#
# Usage: bash tests/live-agents.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/agents.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/live-agents-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }
expect_eq()    { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }
expect_empty() { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }
expect_match() { if printf '%s' "$2" | grep -Eq "$3"; then ok "$1"; else no "$1" "[$2] does not match /$3/"; fi; }

# ============================================================
echo "=== §A — the library exists, parses, and is safe to source ==="
# ============================================================
if [ -f "$LIB" ]; then ok "payload/scripts/lib/agents.sh is on disk"; else
  no "payload/scripts/lib/agents.sh is on disk" "$LIB"
fi
if bash -n "$LIB" 2>"$SANDBOX/.syn"; then ok "the library parses (bash -n)"; else
  no "the library parses (bash -n)" "$(cat "$SANDBOX/.syn" 2>/dev/null)"
fi

# It is sourced by hooks that run under `set -u` and print their own single line; a
# library that emitted anything, or tripped on an unset variable, would corrupt every
# one of them.
SRC_OUT="$(env -u BIONIC_NOW_EPOCH bash -c 'set -u; . "$1"; echo READY' _ "$LIB" 2>"$SANDBOX/.srcerr")"
expect_eq "sourcing under set -u succeeds" "READY" "$SRC_OUT"
expect_empty "sourcing prints nothing on stderr" "$(cat "$SANDBOX/.srcerr" 2>/dev/null)"

# Defines functions only: no stray global state, and both entry points exist.
DEFS="$(bash -c 'set -u; . "$1"; type -t live_agents; type -t live_agents_has' _ "$LIB" 2>/dev/null)"
expect_eq "defines live_agents and live_agents_has as functions" \
  "$(printf 'function\nfunction')" "$DEFS"

# ------------------------------------------------------------
# Fixture builders. Every transcript is a jsonl file assembled from real entry shapes.
# ------------------------------------------------------------

# The peer-session block the harness prints under every answer, captured verbatim.
PEERS='Peer sessions (15):
  Measure 8 epic 20 w2 [345484]  ·  Remote Control  ·  offline
  Canonical-sdlc skill invocation [ac9e21]  ·  Remote Control  ·  offline
  Canonical-sdlc skill invocation [8c374a]  ·  Remote Control  ·  offline
  mac-mini-local-golden-honey [24fd6f]  ·  Remote Control  ·  offline
  mac-mini-local-cached-castle [0af035]  ·  Remote Control  ·  offline
  mac-mini-local-synchronous-snail [cfbb0d]  ·  Remote Control  ·  offline
  mac-mini-local-humble-elephant [4c7c86]  ·  Remote Control  ·  offline
  mac-mini-local-declarative-wind [fae635]  ·  Remote Control  ·  offline
  mac-mini-local-playful-nest [6f58d1]  ·  Remote Control  ·  offline
  mac-mini-local-golden-crab [03c842]  ·  Remote Control  ·  offline
  Epic 17 wave 3 command surface implementation [90bc8a]  ·  Remote Control  ·  offline
  Clarify blocking status [7f6b8a]  ·  Remote Control  ·  offline
  macbookair-localdomain-playful-hartmanis [30d4c0]  ·  Remote Control  ·  offline
  Reframe decision at higher conceptual level [9ccc08]  ·  Remote Control  ·  offline
  Review elephant SVG shape variants and motif coverage [c6289b]  ·  Remote Control  ·  offline'

SELFLINE='This session is bionic-02 [fc3e2d] — the name other sessions use to message it (it is not listed below; a message to it would be a message to yourself).'

# BODY_RUNNING — the real 2026-09-05T00:52:23.349Z answer: one teammate, running.
BODY_RUNNING="$SELFLINE

Teammates (1):
  research-code-map [8895ce]  ·  bionic:researcher  ·  running  ·  started 7m ago

$PEERS"

# BODY_NOTEAMMATES — the real earlier answer: recognisably a ListAgents answer, no
# Teammates block at all (the researcher had not been dispatched yet).
BODY_NOTEAMMATES="$SELFLINE

$PEERS"

# BODY_TWO — the same real shape with a second teammate, and BODY_DUP with the same name
# twice (two sessions in one root launching same-named agents — the ambiguity D2′ keeps).
BODY_TWO="$SELFLINE

Teammates (2):
  research-code-map [8895ce]  ·  bionic:researcher  ·  running  ·  started 7m ago
  s1-run-library [4b21aa]  ·  bionic:senior-implementor  ·  running  ·  started 2m ago

$PEERS"

BODY_DUP="$SELFLINE

Teammates (2):
  research-code-map [8895ce]  ·  bionic:researcher  ·  running  ·  started 7m ago
  research-code-map [77c310]  ·  bionic:researcher  ·  running  ·  started 1m ago

$PEERS"

# jq -Rs turns an arbitrary shell string into a JSON string literal, so a body's real
# em dashes, middots and newlines survive into the fixture byte-for-byte.
json_str() { printf '%s' "$1" | jq -Rs .; }

# An assistant entry issuing a tool call. <ts> <tool-name> <tool_use_id>
entry_tool_use() {
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"%s","input":{}}]}}\n' \
    "$1" "$3" "$2"
}

# A user entry carrying a tool_result with a STRING content. <ts> <tool_use_id> <body>
entry_tool_result() {
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":%s}]}}\n' \
    "$1" "$2" "$(json_str "$3")"
}

# The same, with content as an ARRAY of text blocks — the other real shape.
entry_tool_result_array() {
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":[{"type":"text","text":%s}]}]}}\n' \
    "$1" "$2" "$(json_str "$3")"
}

# A user PROMPT entry: type user, .message.content a plain string. <ts> <text>
entry_prompt() {
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":%s}}\n' \
    "$1" "$(json_str "$2")"
}

# An assistant entry of plain text — noise between the load-bearing entries.
entry_text() {
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' \
    "$1" "$(json_str "$2")"
}

# Drive the reader in a subshell so a `return` from the library cannot end this suite,
# and so stdout and stderr are captured apart. Sets OUT, ERR, ST.
call_live_agents() {  # <transcript>
  OUT="$(bash -c 'set -u; . "$1"; live_agents "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")"
  ST=$?
  ERR="$(cat "$SANDBOX/.err" 2>/dev/null)"
}

call_live_agents_has() {  # <transcript> <name>
  HOUT="$(bash -c 'set -u; . "$1"; live_agents_has "$2" "$3"' _ "$LIB" "$1" "$2" 2>"$SANDBOX/.herr")"
  HST=$?
  HERR="$(cat "$SANDBOX/.herr" 2>/dev/null)"
}

# "Now" is pinned for the whole suite so `age=` is arithmetic, not a clock reading.
# 2026-09-05T01:00:00Z.
export BIONIC_NOW_EPOCH=1788570000

# ============================================================
echo
echo "=== §B — (a) prompt then a fresh answer: FRESH, one teammate line ==="
# ============================================================
T_FRESH="$SANDBOX/fresh.jsonl"
{
  entry_prompt        "2026-09-05T00:50:00.000Z" "dispatch the code-map researcher"
  entry_text          "2026-09-05T00:52:20.000Z" "Checking the roster."
  entry_tool_use      "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_01E6AEt34433u6NazVYnRk32"
  entry_tool_result   "2026-09-05T00:52:23.349Z" "toolu_01E6AEt34433u6NazVYnRk32" "$BODY_RUNNING"
} > "$T_FRESH"

call_live_agents "$T_FRESH"
expect_eq "fresh answer -> exit 0" 0 "$ST"
expect_eq "fresh answer -> the running researcher, name|type|status" \
  "research-code-map|bionic:researcher|running" "$OUT"
# 01:00:00Z minus 00:52:23Z = 457 s.
expect_eq "fresh answer -> stderr names the state and the age" \
  "live-agents: fresh age=457" "$ERR"

# The peer-session block is NOT the teammate block: fifteen peers, zero extra lines.
expect_eq "fresh answer -> peer sessions are not teammates (exactly one line)" \
  1 "$(printf '%s\n' "$OUT" | grep -c .)"

# Same answer delivered in the array content shape — the reader must not care.
T_ARR="$SANDBOX/fresh-array.jsonl"
{
  entry_prompt            "2026-09-05T00:50:00.000Z" "dispatch the code-map researcher"
  entry_tool_use          "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_arrayshape0000000001"
  entry_tool_result_array "2026-09-05T00:52:23.349Z" "toolu_arrayshape0000000001" "$BODY_RUNNING"
} > "$T_ARR"
call_live_agents "$T_ARR"
expect_eq "array-shaped tool_result content -> exit 0" 0 "$ST"
expect_eq "array-shaped tool_result content -> same one line" \
  "research-code-map|bionic:researcher|running" "$OUT"

# Two teammates, in the order the harness printed them.
T_TWO="$SANDBOX/two.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "who is running"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_twoteammates00000001"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_twoteammates00000001" "$BODY_TWO"
} > "$T_TWO"
call_live_agents "$T_TWO"
expect_eq "two teammates -> exit 0" 0 "$ST"
expect_eq "two teammates -> both lines, in answer order" \
  "$(printf 'research-code-map|bionic:researcher|running\ns1-run-library|bionic:senior-implementor|running')" "$OUT"

# ============================================================
echo
echo "=== §C — (b) a prompt after the answer makes it STALE ==="
# ============================================================
T_STALE="$SANDBOX/stale.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "dispatch the code-map researcher"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_01E6AEt34433u6NazVYnRk32"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_01E6AEt34433u6NazVYnRk32" "$BODY_RUNNING"
  entry_prompt      "2026-09-05T00:58:00.000Z" "now stop it"
} > "$T_STALE"

call_live_agents "$T_STALE"
expect_eq "answer predating the last prompt -> exit 3 (STALE)" 3 "$ST"
expect_eq "STALE -> stderr names the state and the answer's age" \
  "live-agents: stale age=457" "$ERR"
# STALE STILL PRINTS THE ANSWER. Which stdout is safe here is a design decision, and
# the asymmetry decides it: a caller that read the status wrongly and got an EMPTY set
# would tell the budget the roster is clear (over-dispatch) and the stop guard its
# target is dead (a valid stop refused). The same caller getting the stale set
# over-counts the budget and stops an agent that may already be gone — both harmless.
# So the reader never manufactures an empty set; only the status says "do not act".
expect_eq "STALE is not reported as a fresh empty set" 3 "$ST"
expect_eq "STALE still prints the newest answer's teammates" \
  "research-code-map|bionic:researcher|running" "$OUT"

# ============================================================
echo
echo "=== §D — (d) a real answer with no Teammates block: FRESH, zero lines ==="
# ============================================================
T_EMPTY="$SANDBOX/empty.jsonl"
{
  entry_prompt      "2026-09-05T00:20:00.000Z" "anything running?"
  entry_tool_use    "2026-09-05T00:38:56.000Z" "ListAgents" "toolu_01P5RJ8N617Tw45VVRaUfyrh"
  entry_tool_result "2026-09-05T00:38:57.460Z" "toolu_01P5RJ8N617Tw45VVRaUfyrh" "$BODY_NOTEAMMATES"
} > "$T_EMPTY"

call_live_agents "$T_EMPTY"
expect_eq "answer with no Teammates block -> exit 0 (FRESH, empty is a real answer)" 0 "$ST"
expect_empty "answer with no Teammates block -> zero lines" "$OUT"
# 01:00:00Z minus 00:38:57Z = 1263 s.
expect_eq "empty answer -> stderr still fresh, with its age" \
  "live-agents: fresh age=1263" "$ERR"

# ============================================================
echo
echo "=== §E — (c) no ListAgents answer at all: NONE ==="
# ============================================================
T_NONE="$SANDBOX/none.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "get on with it"
  entry_text        "2026-09-05T00:51:00.000Z" "Working."
  entry_tool_use    "2026-09-05T00:51:10.000Z" "Bash" "toolu_bashonly000000000001"
  entry_tool_result "2026-09-05T00:51:11.000Z" "toolu_bashonly000000000001" "total 0"
} > "$T_NONE"

call_live_agents "$T_NONE"
expect_eq "no ListAgents answer -> exit 4 (NONE)" 4 "$ST"
expect_empty "NONE -> no stdout" "$OUT"
expect_eq "NONE -> stderr says none with no age" "live-agents: none age=none" "$ERR"

# A transcript that does not exist, and one that is empty, are the same NONE — a reader
# that crashed here would take its caller's hook down with it.
call_live_agents "$SANDBOX/does-not-exist.jsonl"
expect_eq "missing transcript -> exit 4 (NONE)" 4 "$ST"
expect_eq "missing transcript -> stderr says none" "live-agents: none age=none" "$ERR"

: > "$SANDBOX/blank.jsonl"
call_live_agents "$SANDBOX/blank.jsonl"
expect_eq "empty transcript -> exit 4 (NONE)" 4 "$ST"

# ============================================================
echo
echo "=== §F — (f) an unparseable answer body is NONE, never 'all gone' ==="
# ============================================================
# The tool call WAS ListAgents and the id joins, so §J's forgery rule is not what is
# under test here: this is a body the reader does not recognise. Returning zero
# teammates would tell the dispatch wall the roster is clear and the stop guard its
# target is dead. It must be NONE, which is the callers' refuse-and-name-the-fix path.
T_GARBAGE="$SANDBOX/garbage.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "who is running"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_garbagebody0000000001"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_garbagebody0000000001" \
    "Error: the agent service is unavailable (503). Try again."
} > "$T_GARBAGE"

call_live_agents "$T_GARBAGE"
expect_eq "unrecognised answer body -> exit 4 (NONE)" 4 "$ST"
expect_empty "unrecognised answer body -> no stdout" "$OUT"
expect_eq "unrecognised answer body -> stderr says none" "live-agents: none age=none" "$ERR"

# ANTI-VACUITY for §F: the identical fixture whose body IS a recognisable answer is
# FRESH with the teammate. So the NONE above measured the body, not a broken fixture.
T_GARBAGE_OK="$SANDBOX/garbage-control.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "who is running"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_garbagebody0000000001"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_garbagebody0000000001" "$BODY_RUNNING"
} > "$T_GARBAGE_OK"
call_live_agents "$T_GARBAGE_OK"
expect_eq "…the same fixture with a real body -> exit 0" 0 "$ST"
expect_eq "…the same fixture with a real body -> the teammate" \
  "research-code-map|bionic:researcher|running" "$OUT"

# ============================================================
echo
echo "=== §G — the NEWEST answer wins, and it is the whole answer ==="
# ============================================================
# The reported field failure this wave exists to fix: an agent present in an older
# answer and absent from the newest must read as GONE. Both answers are real bodies.
T_NEWEST="$SANDBOX/newest.jsonl"
{
  entry_prompt      "2026-09-05T00:45:00.000Z" "dispatch, then check twice"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_01E6AEt34433u6NazVYnRk32"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_01E6AEt34433u6NazVYnRk32" "$BODY_RUNNING"
  entry_tool_use    "2026-09-05T00:58:56.000Z" "ListAgents" "toolu_01P5RJ8N617Tw45VVRaUfyrh"
  entry_tool_result "2026-09-05T00:58:57.460Z" "toolu_01P5RJ8N617Tw45VVRaUfyrh" "$BODY_NOTEAMMATES"
} > "$T_NEWEST"

call_live_agents "$T_NEWEST"
expect_eq "older answer named it, newest does not -> exit 0" 0 "$ST"
expect_empty "…the researcher is gone, because the NEWEST answer is the whole answer" "$OUT"
# 01:00:00Z minus 00:58:57Z = 63 s: the age is the NEWEST answer's, not the older one's.
expect_eq "…the age is the newest answer's" "live-agents: fresh age=63" "$ERR"

# And the other direction on the same file shape: newest names it, older did not.
T_NEWEST2="$SANDBOX/newest2.jsonl"
{
  entry_prompt      "2026-09-05T00:45:00.000Z" "dispatch, then check twice"
  entry_tool_use    "2026-09-05T00:38:56.000Z" "ListAgents" "toolu_01P5RJ8N617Tw45VVRaUfyrh"
  entry_tool_result "2026-09-05T00:38:57.460Z" "toolu_01P5RJ8N617Tw45VVRaUfyrh" "$BODY_NOTEAMMATES"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_01E6AEt34433u6NazVYnRk32"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_01E6AEt34433u6NazVYnRk32" "$BODY_RUNNING"
} > "$T_NEWEST2"
call_live_agents "$T_NEWEST2"
expect_eq "newest answer names it, older did not -> the researcher is live" \
  "research-code-map|bionic:researcher|running" "$OUT"

# ============================================================
echo
echo "=== §H — freshness is measured against the LAST user prompt ==="
# ============================================================
# Two prompts, two answers, interleaved: the answer after the SECOND prompt is what
# makes the file fresh. An implementation comparing against the FIRST prompt would call
# the stale file fresh, which is the whole point of D1′.
T_INTER="$SANDBOX/interleaved.jsonl"
{
  entry_prompt      "2026-09-05T00:40:00.000Z" "first turn"
  entry_tool_use    "2026-09-05T00:38:56.000Z" "ListAgents" "toolu_01P5RJ8N617Tw45VVRaUfyrh"
  entry_tool_result "2026-09-05T00:41:00.000Z" "toolu_01P5RJ8N617Tw45VVRaUfyrh" "$BODY_NOTEAMMATES"
  entry_prompt      "2026-09-05T00:50:00.000Z" "second turn"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_01E6AEt34433u6NazVYnRk32"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_01E6AEt34433u6NazVYnRk32" "$BODY_RUNNING"
} > "$T_INTER"
call_live_agents "$T_INTER"
expect_eq "an answer after the last of two prompts -> exit 0" 0 "$ST"
expect_eq "…and it is the second answer's set" \
  "research-code-map|bionic:researcher|running" "$OUT"

# The same file with one more prompt appended: now nothing postdates the last prompt.
cp "$T_INTER" "$SANDBOX/interleaved-stale.jsonl"
entry_prompt "2026-09-05T00:55:00.000Z" "third turn" >> "$SANDBOX/interleaved-stale.jsonl"
call_live_agents "$SANDBOX/interleaved-stale.jsonl"
expect_eq "…one more prompt appended -> exit 3 (STALE)" 3 "$ST"

# A tool_result is NOT a prompt, even though its entry is `type:"user"`: the array-vs-
# string content shape is the whole discriminator. If it were read as a prompt, §B's
# fresh answer would have been stale against itself.
call_live_agents "$T_FRESH"
expect_eq "a tool_result entry is not counted as a user prompt" 0 "$ST"

# ============================================================
echo
echo "=== §J — the answer is located by the tool_use_id join, never by body text ==="
# ============================================================
# A Bash tool_result whose body is a byte-perfect copy of a real ListAgents answer —
# the file could have been `cat`ed. Sniffing for "Teammates (" would adopt it. Joining
# on the id cannot: no ListAgents tool_use carries that id.
T_FORGE="$SANDBOX/forged.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "cat the fixture"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "Bash" "toolu_forgedbybash00000001"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_forgedbybash00000001" "$BODY_RUNNING"
} > "$T_FORGE"
call_live_agents "$T_FORGE"
expect_eq "a Bash result echoing a real answer body -> exit 4 (NONE), not adopted" 4 "$ST"
expect_empty "…and it contributes no teammates" "$OUT"

# ANTI-VACUITY: the same file with the tool renamed ListAgents IS adopted, so the
# refusal above measured the join and not something else about the fixture.
T_FORGE_OK="$SANDBOX/forged-control.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "cat the fixture"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_forgedbybash00000001"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_forgedbybash00000001" "$BODY_RUNNING"
} > "$T_FORGE_OK"
call_live_agents "$T_FORGE_OK"
expect_eq "…the identical file with name=ListAgents -> exit 0" 0 "$ST"
expect_eq "…and the teammate is read" "research-code-map|bionic:researcher|running" "$OUT"

# A ListAgents tool_use whose result never arrived (the turn was interrupted) is not an
# answer: there is nothing to read.
T_ORPHAN="$SANDBOX/orphan.jsonl"
{
  entry_prompt   "2026-09-05T00:50:00.000Z" "who is running"
  entry_tool_use "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_orphancall0000000001"
} > "$T_ORPHAN"
call_live_agents "$T_ORPHAN"
expect_eq "a ListAgents call with no recorded result -> exit 4 (NONE)" 4 "$ST"

# ============================================================
echo
echo "=== §K — malformed lines do not stop the reader ==="
# ============================================================
# Transcripts are appended to live; a torn last line and harness bookkeeping entries
# with no .timestamp both occur. Neither may cost the reader the answer.
T_DIRTY="$SANDBOX/dirty.jsonl"
{
  printf '{"type":"summary","leafUuid":"aaaa","summary":"earlier work"}\n'
  entry_prompt      "2026-09-05T00:50:00.000Z" "who is running"
  printf 'not json at all\n'
  printf '\n'
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_01E6AEt34433u6NazVYnRk32"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_01E6AEt34433u6NazVYnRk32" "$BODY_RUNNING"
  printf '{"type":"assistant","timestamp":"2026-09-05T00:5\n'
} > "$T_DIRTY"
call_live_agents "$T_DIRTY"
expect_eq "malformed and untimestamped lines -> the answer is still read, exit 0" 0 "$ST"
expect_eq "…and it is the real teammate line" \
  "research-code-map|bionic:researcher|running" "$OUT"

# ============================================================
echo
echo "=== §L — (e) live_agents_has: 0 once, 1 absent, 2 twice, 3/4 propagate ==="
# ============================================================
call_live_agents_has "$T_FRESH" "research-code-map"
expect_eq "live_agents_has: present exactly once -> exit 0" 0 "$HST"

call_live_agents_has "$T_FRESH" "s1-run-library"
expect_eq "live_agents_has: absent from a fresh answer -> exit 1" 1 "$HST"

# A name that is a PREFIX of a live one is absent: the match is on the whole name, or
# `s1` would stop `s1-run-library`.
call_live_agents_has "$T_TWO" "s1"
expect_eq "live_agents_has: a prefix of a live name is absent -> exit 1" 1 "$HST"
call_live_agents_has "$T_TWO" "s1-run-library"
expect_eq "…while the whole name is present -> exit 0" 0 "$HST"

# A PEER session's name is not a teammate, however prominently the answer prints it.
call_live_agents_has "$T_FRESH" "Clarify blocking status"
expect_eq "live_agents_has: a peer session is not a teammate -> exit 1" 1 "$HST"

T_DUP="$SANDBOX/dup.jsonl"
{
  entry_prompt      "2026-09-05T00:50:00.000Z" "who is running"
  entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "toolu_dupnames00000000001"
  entry_tool_result "2026-09-05T00:52:23.349Z" "toolu_dupnames00000000001" "$BODY_DUP"
} > "$T_DUP"
call_live_agents_has "$T_DUP" "research-code-map"
expect_eq "live_agents_has: the same name twice -> exit 2 (ambiguous)" 2 "$HST"
# …and the other teammate in the same answer is still unambiguous, so exit 2 measured
# the duplication and not the fixture.
call_live_agents_has "$T_TWO" "research-code-map"
expect_eq "…while a singly-named agent in a two-teammate answer -> exit 0" 0 "$HST"

call_live_agents_has "$T_STALE" "research-code-map"
expect_eq "live_agents_has: STALE propagates as exit 3" 3 "$HST"
expect_eq "…and the state line is the reader's own" "live-agents: stale age=457" "$HERR"

call_live_agents_has "$T_NONE" "research-code-map"
expect_eq "live_agents_has: NONE propagates as exit 4" 4 "$HST"

call_live_agents_has "$T_GARBAGE" "research-code-map"
expect_eq "live_agents_has: an unparseable answer propagates as exit 4, not 1" 4 "$HST"

# The newest-answer rule reaches the predicate: named in the old answer, gone from the
# new one, and `has` says absent. This is the roster-row bug in one assertion.
call_live_agents_has "$T_NEWEST" "research-code-map"
expect_eq "live_agents_has: present in the older answer only -> exit 1 (gone)" 1 "$HST"

expect_empty "live_agents_has prints nothing on stdout" "$HOUT"

# ============================================================
echo
echo "=== §M — one stderr line, exactly, on every path ==="
# ============================================================
# The callers append this line to a refusal a human reads. Two lines, or none, is a
# defect in every one of them at once.
for f in "$T_FRESH" "$T_STALE" "$T_NONE" "$T_GARBAGE" "$T_EMPTY"; do
  call_live_agents "$f"
  expect_eq "stderr is exactly one line for $(basename "$f")" 1 "$(printf '%s\n' "$ERR" | grep -c .)"
  expect_match "…and it is the contract line for $(basename "$f")" "$ERR" \
    '^live-agents: (fresh|stale|none) age=([0-9]+|none)$'
done

# ============================================================
echo
echo "=== §N — every path survives a caller running set -euo pipefail ==="
# ============================================================
# `.claude/rules/test-harness.md` records this trap by name: a suite runs
# `set -uo pipefail` while the script it exercises runs `set -euo pipefail`, so errexit
# behaviour goes untested and a non-zero status from an inner pipeline kills the caller
# instead of being returned. This library's whole job is to return 3 and 4, and both
# reach the caller through a command substitution, so a hook that sets errexit — none
# does today, and nothing stops the next one — would die on the refuse path rather than
# print its refusal. Each arm asserts the STATUS the caller sees and that the contract
# line was still written.
#
# THE CALL IS BARE, and it has to be. Wrapping it in `if` would suspend errexit for the
# whole call — the exemption reaches into the function body — and the probe would pass
# against a library that aborts. So the reader is called as a hook would call it before
# reading `$?`, and what is asserted is the status the CALLER'S SHELL ends up with:
# either the reader returned it, or errexit killed the shell with whatever an inner
# pipeline happened to exit with.
errexit_probe() {  # <transcript> -> ERC, EERR
  EERR="$(bash -c '
    set -euo pipefail
    . "$1"
    live_agents "$2" >/dev/null
  ' _ "$LIB" "$1" 2>&1 >/dev/null)"
  ERC=$?
}

errexit_probe "$T_FRESH"
expect_eq "set -e caller: FRESH returns 0" "0" "$ERC"
errexit_probe "$T_STALE"
expect_eq "set -e caller: STALE returns 3, it does not abort the caller" "3" "$ERC"
errexit_probe "$T_NONE"
expect_eq "set -e caller: NONE returns 4" "4" "$ERC"
errexit_probe "$T_GARBAGE"
expect_eq "set -e caller: an unparseable body returns 4, it does not abort the caller" "4" "$ERC"
expect_match "set -e caller: …and the contract line was still written" "$EERR" \
  '^live-agents: none age=none$'
errexit_probe "$SANDBOX/does-not-exist.jsonl"
expect_eq "set -e caller: a missing transcript returns 4" "4" "$ERC"

# live_agents_has propagates 1/2/3/4 to an errexit caller for the same reason.
has_errexit_probe() {  # <transcript> <name> -> HERC
  bash -c '
    set -euo pipefail
    . "$1"
    live_agents_has "$2" "$3"
  ' _ "$LIB" "$1" "$2" >/dev/null 2>&1
  HERC=$?
}
has_errexit_probe "$T_FRESH" "research-code-map"
expect_eq "set -e caller: live_agents_has present -> 0" "0" "$HERC"
has_errexit_probe "$T_FRESH" "s1-run-library"
expect_eq "set -e caller: live_agents_has absent -> 1" "1" "$HERC"
has_errexit_probe "$T_DUP" "research-code-map"
expect_eq "set -e caller: live_agents_has ambiguous -> 2" "2" "$HERC"
has_errexit_probe "$T_STALE" "research-code-map"
expect_eq "set -e caller: live_agents_has STALE -> 3" "3" "$HERC"
has_errexit_probe "$T_GARBAGE" "research-code-map"
expect_eq "set -e caller: live_agents_has unparseable -> 4" "4" "$HERC"

# ============================================================
echo
echo "=== live-agents: $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ] || echo "FAILURES: $FAIL"
[ "$FAIL" -eq 0 ]
