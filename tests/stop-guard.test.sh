#!/bin/bash
# Tests for hooks/stop-guard.sh — the STOP GATE, PreToolUse|TaskStop
# (epic-15 wave-01R; recorder arm removed at wave-03 task 4/4).
#
# The gate: D-1 activity-boundary freshness, D-2 consume-on-stop, and — since
# wave-03 task 4/6 — D-3 same-actor, D-6 progress staleness, and the
# foreign-stop rule. Serves wave-01R's AC-4/AC-5 and the stop-side rows of
# AC-8/AC-10, plus wave-03's AC-4 (§8), AC-5 (§9) and AC-6 (§10).
#
# WHAT MOVED OUT. This script used to carry a second arm that WROTE the records
# it now only reads. Those rows live in tests/execution-recorder.test.sh, because
# that is where the writer lives — one writer, one paired suite. The records this
# suite spends are still never hand-written: `observe()` below runs the real
# hooks/stop-check.sh and feeds its real output to the real recorder, so every
# gate row here is discharged through the whole producer→recorder→gate path.
#
# HERMETIC. Every payload is crafted and piped straight into the script under
# test; nothing here invokes the TaskStop tool, touches the live installed hooks,
# or writes outside a mktemp'd sandbox.
#
# Usage: bash tests/stop-guard.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/roster-row.sh"
# NO LANDING MARKER WRITER ANY MORE (epic-23 wave-20 T17, D10). §10(c4) was its one user: it
# closed a name with a `landing-swept/v1|…|state=MET` line, and a MET marker closes nothing
# now — the sweeper's ack does, through `ack_row` below.

HERE="${BIONIC_HOOKS_DIR}"
GUARD="$HERE/stop-guard.sh"
RECORDER="$HERE/execution-recorder.sh"
OBSERVE="$HERE/stop-check.sh"
# `cd … && pwd` normalizes the path: $TMPDIR carries a trailing slash on
# macOS, and a doubled separator would slugify differently from the cwd the
# script under test actually sees.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stop-guard-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------- suite-specific assertions (not framework-owned) ----------

expect_file()     { if [ -f "$2" ]; then ok "$1"; else no "$1" "no such file: $2"; fi; }
expect_no_file()  { if [ -f "$2" ]; then no "$1" "file exists but should not: $2"; else ok "$1"; fi; }

# HELPER-PRESENCE GUARD (S11, spec AC-25). `expect_eq` comes from tests/lib/assert.sh
# and is not defined anywhere in this file — before this task, its one call below
# (":re-engaged: the refusal is byte-identical") ran under `set -uo pipefail` with no
# `-e`, so an undefined `expect_eq` was a silent stderr line and the row asserted
# nothing (the same class of defect r24e was in dispatch-preflight.test.sh,
# research-code-map §6.2). Every helper this file calls is checked to exist as a
# function before the first test runs, so a future undefined call fails the whole
# suite loudly instead of vanishing.
require_helpers ok no expect_status expect_contains expect_regex expect_absent \
  expect_empty expect_file expect_no_file expect_eq

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design).
#
# Source: .bionic/docs/record/epic-15-kill-interception-experiment.md, CLI
# 2.1.220 verbatim captures.
#
#   * PreToolUse|TaskStop payload — FAITHFUL to §2.2, field for field:
#     session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
#     hook_event_name, tool_name, tool_input.task_id, tool_use_id. Critically
#     §2.2 establishes that `tool_input.task_id` is THE CALLER'S STRING AS TYPED
#     ("victim", a name) and that no resolved agent id is present in the
#     payload — the property every resolution test here depends on.
#   * PostToolUse|Bash payload — FAITHFUL to
#     .bionic/docs/record/w3-slice1-posttooluse-probe.md capture A (CLI 2.1.222),
#     field for field including the tool_response object. Used only to drive the
#     recorder that seeds this suite's records.
#   * transcript_path → session directory — FAITHFUL to §2.5, which captures
#     `agent_transcript_path` as "<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl".
#   * meta.json — FAITHFUL to §2.8 (verbatim field set), plus the named
#     in-process-teammate fields read live from this machine on 2026-08-04.
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, message text.
#     None is a platform surface.
#
# The GATE itself never sees a PostToolUse payload: it must decide BEFORE the stop
# happens, so it only ever reads §2.2's unresolved reference.

mk_bash_payload() {  # <sid> <transcript> <cwd> <command>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg cmd "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$cmd}, tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

mk_bash_post() {  # <sid> <transcript> <cwd> <command> <stdout>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg cmd "$4" --arg out "$5" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"598cabc5-2776-479c-abcf-52c540a1c60e",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Bash",
      tool_input:{command:$cmd, description:"observe"},
      tool_response:{stdout:$out, stderr:"", interrupted:false,
                     isImage:false, noOutputExpected:false},
      tool_use_id:"toolu_01HQV9JAFdKC15TLMDKt2QgF", duration_ms:117}'
}

mk_stop_payload() {  # <sid> <transcript> <cwd> <task_id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg id "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"TaskStop",
      tool_input:{task_id:$id}, tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

# THE SAME PAYLOADS, INVOKED BY A SUBAGENT (task 4/6, D-3). FAITHFUL to
# .bionic/docs/record/w3-slice1-posttooluse-probe.md captures C and F: a
# subagent-invoked PreToolUse or PostToolUse payload carries top-level `agent_id`
# and `agent_type` alongside every field the orchestrator's payload has, and the
# orchestrator's omits both. That presence/absence IS the actor key — the gate
# reads it out of its own payload and the recorder read it out of its own, so a
# same-actor comparison is one field against one field.
mk_stop_payload_as() {  # <sid> <transcript> <cwd> <task_id> <invoking-agent-id>
  mk_stop_payload "$1" "$2" "$3" "$4" \
    | jq --arg a "$5" '. + {agent_id:$a, agent_type:"general-purpose"}'
}

mk_bash_post_as() {  # <sid> <transcript> <cwd> <command> <stdout> <invoking-agent-id>
  mk_bash_post "$1" "$2" "$3" "$4" "$5" \
    | jq --arg a "$6" '. + {agent_id:$a, agent_type:"general-purpose"}'
}

GUARD_OUT=""; GUARD_ERR=""; GUARD_ST=0
# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2).
# The gate's siblings — the sweeper, stop-check — take the session key from the
# environment, and since bionic 1.4.0 so does the gate, so a driver that left the
# runner's own id there would split one fixture session into two.
GUARD_VERR=""
run_guard() {  # <payload-json>
  local _sid; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  GUARD_OUT=$(printf '%s' "$1" | env CLAUDE_CODE_SESSION_ID="$_sid" bash "$GUARD" 2>"$SANDBOX/.err"); GUARD_ST=$?
  GUARD_ERR=$(cat "$SANDBOX/.err")
  # THE SAME CALL AGAIN, WITH THE KNOB (task 13, ruling D-1). This gate's refusal is
  # now ONE line — `bionic: stop refused — <fact> (<fix>)` — and the twelve-line frame
  # this suite reads for counts, spellings, ages and the pasteable Fix line is `detail`,
  # which reaches a reader only under BIONIC_WALL_VERBOSE=1. `$GUARD_ERR` is therefore
  # the LINE and `$GUARD_VERR` is the line plus the detail; an arm that read the detail
  # off `$GUARD_ERR` would now be asserting that the wall leaks it.
  # ONLY WHEN THE FIRST DRIVE REFUSED: a PERMITTED stop consumes the observation
  # record, and a second drive would consume a second one.
  GUARD_VERR=""
  if [ "$GUARD_ST" -ne 0 ]; then
    GUARD_VERR=$(printf '%s' "$1" | env CLAUDE_CODE_SESSION_ID="$_sid" BIONIC_WALL_VERBOSE=1 \
      bash "$GUARD" 2>&1 >/dev/null)
  fi
  return 0
}

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="11111111-2222-3333-4444-555555555555"

# make_world <name> <active-wave:yes|no> — echoes "<repo>|<transcript>|<subagents>"
make_world() {
  local name="$1" wave="$2"
  local home="$SANDBOX/$name/home" repo="$SANDBOX/$name/repo"
  local proj="$home/.claude/projects/p-$name"
  mkdir -p "$repo" "$proj/$SID_A/subagents" "$proj/$SID_B/subagents"
  : > "$proj/$SID_A.jsonl"
  : > "$proj/$SID_B.jsonl"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  if [ "$wave" = "yes" ]; then
    # ENGAGED (task-engaged-session). Since this wave the hook asks `engaged_session`
    # before anything else, so a fixture without the marker is silent for a reason that has
    # nothing to do with the wall under test. Planted for both fixture sessions, beside the
    # plan, because an engaged session is what a live wave IS.
    mkdir -p "$repo/.bionic/tmp"
    : > "$repo/.bionic/tmp/engaged-$SID_A.state"
    : > "$repo/.bionic/tmp/engaged-$SID_B.state"
    mkdir -p "$repo/.bionic/docs/plans/epic-99-test"
    cat > "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
---

# Test wave plan

## SDLC State

integration-branch: main
current: 4

- Step 4: tasks in flight
PLAN
  fi
  printf '%s|%s|%s\n' "$repo" "$proj/$SID_A.jsonl" "$proj/$SID_A/subagents"
}

# ---------- THE RECORDED ListAgents ANSWER — the live set (S6, D1′) ----------
#
# Since this task the two stop scripts resolve a target against the newest recorded
# ListAgents answer in the session transcript, not against agent-*.meta.json on disk. So a
# fixture world's transcript is no longer an empty file: it carries a prompt, the assistant's
# ListAgents call and the harness's answer, in that order, which is what makes the answer
# FRESH (recorded after the last user prompt).
#
# THE ANSWER BODY'S SHAPE IS THE REAL ONE, copied from tests/live-agents.test.sh, whose two
# bodies are byte-verbatim captures of this project's own transcript (the separator is
# U+00B7, and the `[8895ce]` ref suffix is what the reader strips off a name). Composing a
# body here rather than reading that suite's is the same call S4 made about the fixture file:
# `.bionic/` is gitignored, so anything read from it passes on this machine and fails in a
# fresh clone.
# THE ANSWER BODY IS BUILT BY tests/lib/live-answer.sh (S17, spec AC-27/AC-28): the self
# line, the `Teammates (N):` header and every teammate row come out of the committed corpus
# at tests/fixtures/claude/listagents-answers.jsonl with only this suite's names and
# statuses substituted in place. The private builder that used to sit here re-typed the
# harness's separator, its ref suffix and its recognition anchor — three spellings of that
# anchor across the tree, and the one thing standing between "empty answer" and
# "unrecognised body".
#
# `LIVE_ANSWER_TYPE` is the type the composed rows carry; the two ambiguity sections and
# §I assert on `bionic:senior-implementor`. A bare name is the corpus's own `running`;
# `name:idle` writes the harness's other status — a teammate that finished its turn and
# was never stopped stays listed, because it stays addressable.
LIVE_ANSWER_TYPE="bionic:senior-implementor"

la_body() {  # <name[:status]>... -> one real-shaped ListAgents answer body
  live_answer_body "$@"
}

# plant_live <transcript> <fresh|stale> <name>...  — rewrite a transcript so its newest
# ListAgents answer names exactly these teammates. `stale` appends one more user prompt
# AFTER the answer, which is the whole of what STALE means (D1′).
plant_live() {
  local tr="$1" freshness="$2"; shift 2
  local body; body=$(la_body "$@")
  {
    jq -nc --arg ts "2026-09-05T00:50:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
    jq -nc --arg ts "2026-09-05T00:51:00.000Z" \
      '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01FIXTURELISTAGENTS",name:"ListAgents",input:{}}]}}'
    jq -nc --arg ts "2026-09-05T00:52:23.349Z" --arg b "$body" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01FIXTURELISTAGENTS",content:$b}]}}'
    if [ "$freshness" = "stale" ]; then
      jq -nc --arg ts "2026-09-05T00:53:00.000Z" \
        '{type:"user",timestamp:$ts,message:{role:"user",content:"a later turn"}}'
    fi
  } > "$tr"
  return 0
}

# plant_agent <subagents-dir> <agent-id> <name> [mtime-touch]
#
# Plants the working log the observation reads AND adds the name to its session's live set,
# because after S6 an agent that is not in the newest ListAgents answer does not resolve at
# all. The name list is accumulated in a sidecar so a second call adds to the answer rather
# than replacing it.
plant_agent() {
  local dir="$1" aid="$2" aname="$3" touchts="${4:-}"
  printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0,"model":"opus","taskKind":"in_process_teammate"}\n' \
    "$aname" > "$dir/agent-$aid.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$dir/agent-$aid.jsonl"
  [ -n "$touchts" ] && touch -t "$touchts" "$dir/agent-$aid.jsonl"
  local tr="${dir%/subagents}.jsonl" names=() n
  printf '%s\n' "$aname" >> "${dir%/subagents}.names"
  while IFS= read -r n; do [ -n "$n" ] && names+=("$n"); done < "${dir%/subagents}.names"
  plant_live "$tr" fresh "${names[@]}"
  return 0
}

# THE PATH THE OBSERVATION RECORD USED TO LIVE AT (epic-23 wave-15, REQ-2). Nothing writes
# it and nothing reads it since ADR-028; it survives here as ONE assertion in §1 — that the
# gate never starts writing it again.
STATE_REL=".bionic/tmp/stop-check.state"

# THE PRODUCER→RECORDER PATH IS GONE WITH THE RECORD. `observe()` and `observe_as()` ran the
# real hooks/stop-check.sh and fed its machine line to the real recorder, so that every gate
# row was discharged through the whole producer→recorder→gate path. The gate takes its own
# look now: what makes a target stoppable is what is TRUE of it, and the two helpers below
# are how this suite says so.
#
# A TARGET GOES QUIET. `plant_agent` writes a working log with a current mtime, so a planted
# agent is ALIVE by default — which is the state this gate refuses and therefore the right
# default for a suite full of refusals. `age_log` pushes that log far enough back that no
# cadence could still call it alive.
age_log() {  # <subagents-dir> <agent-id>
  touch -t 202601010000 "$1/agent-$2.jsonl" 2>/dev/null
  return 0
}

# …and the other direction, for a fixture that needs a target to be working RIGHT NOW after
# something else aged it.
wake_log() {  # <subagents-dir> <agent-id>
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"still here"}]}}\n' \
    >> "$1/agent-$2.jsonl"
  touch "$1/agent-$2.jsonl"
  return 0
}

# THE SESSION ROSTER, planted as the PRECONDITION it is at a real stop.# THE SESSION ROSTER, planted as the PRECONDITION it is at a real stop. Row shape
# FAITHFUL to the writer, hooks/dispatch-preflight.sh's `ROW=` line (field for
# field, in order); the writer itself is driven by its own suite and the two
# shapes are held together by tests/cross-gate-agreement.test.sh. Since task 4/9
# a row is no longer what makes a target ours — its directory is — so a world that
# plants none is a perfectly ordinary one. What a row still carries is the
# CONTRACT, and, when `confirmed`, ownership of a target filed elsewhere.
#
# The CONTRACT FIELDS (deliverable, waiver, teammate_id) are optional trailing
# arguments rather than a second helper: epic-16 wave-02 task S3 made the row's
# contract the thing that discharges a stop, so a suite that could only plant
# contract-less rows could not express the discharging case at all. Every call
# written before that task passes none of them and gets the identical row it got
# before — an empty `deliverable=` is what the writer emits for a dispatch that
# declared nothing.
# `adopted_from=` is the tenth optional argument for the same reason the contract fields
# are the seventh through ninth: hooks/session-poker.sh's `adopt` writes it onto a row in
# the ADOPTING session's roster, and a suite that could only plant rows without it could not
# express a taken-over agent at all — which is exactly the state §14 is about.
# RENAMED OFF THE WRITER'S NAME (S17): `roster_row` is the production writer
# (payload/scripts/lib/roster.sh), and a private definition of that name would shadow the
# one writer with a fixture.
# `cadence` is the ELEVENTH optional argument, and it is here for the same reason the
# contract fields are the seventh through ninth: since REQ-2 the gate measures the target's
# quiet against the number its own dispatch declared, so a suite that could only plant rows
# without one could not express the boundary at all. Absent, the library's own default
# stands — which is what every row written before this wave gets, unchanged.
sg_roster_row() {  # <repo> <sid> <name> <agent-id> [progress] [status] [deliverable] [waiver] [teammate-id] [adopted-from] [cadence]
  local repo="$1" sid="$2" name="$3" aid="$4" prog="${5:-}" status="${6:-confirmed}"
  local deliv="${7:-}" waiver="${8:-}" tmid="${9:-}" afrom="${10:-}" cad="${11:-}"
  local f="$repo/.bionic/tmp/roster-$sid.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture status="$status" session="$sid" name="$name" agent_id="$aid" \
    launched_at=2026-08-05T00:00:00Z deliverable="$deliv" progress="$prog" \
    waiver="$waiver" teammate_id="$tmid" adopted_from="$afrom" cadence="$cad" >> "$f"
  return 0
}

# The sweeper's own ack verb, run for real against the fixture repo — never a
# hand-written ledger line. An ack is the ONLY thing that closes a row which
# declared no machine-visible artifact, so the gate's ack discharge has to be
# driven through the writer that actually ships.
ack_row() {  # <repo> <sid> <name>
  ( cd "$1" && CLAUDE_CODE_SESSION_ID="$2" bash "$HERE/session-sweeper.sh" ack "$3" ) >/dev/null 2>&1
  return 0
}

# A user's stop order, recorded through the shipped helper for the same reason.
order_stop() {  # <repo> <sid> <target> [--at <epoch>]
  ( cd "$1" && CLAUDE_CODE_SESSION_ID="$2" bash "$HERE/stop-orders.sh" order "${@:3}" ) >/dev/null 2>&1
  return 0
}

section "Section 1: the hot path — relevance before any plan walk (checklist A7)"

IFS='|' read -r W1_REPO W1_TR W1_SUB <<< "$(make_world w1 yes)"
plant_agent "$W1_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"

run_guard "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Read", tool_input:{file_path:"/tmp/x"}}')"
expect_status "an unrelated TOOL passes untouched" 0 "$GUARD_ST"
expect_no_file "an unrelated tool writes no state" "$W1_REPO/$STATE_REL"

# A Bash call is no longer this script's business AT ALL (task 4/4 moved the
# recorder out). It must pass untouched and, more importantly, write nothing:
# a settings file that still carries the retired PreToolUse|Bash registration
# must produce silence rather than a second writer of the same state.
run_guard "$(mk_bash_payload "$SID_A" "$W1_TR" "$W1_REPO" "ls -la && git status")"
expect_status "an unrelated Bash command passes untouched" 0 "$GUARD_ST"
expect_no_file "an unrelated Bash command writes no state" "$W1_REPO/$STATE_REL"

run_guard "$(mk_bash_payload "$SID_A" "$W1_TR" "$W1_REPO" "bash ~/.claude/hooks/stop-check.sh quiet-reviewer")"
expect_status "a REAL observation command is no longer this gate's business" 0 "$GUARD_ST"
# THE RECORD MUST NEVER COME BACK (epic-23 wave-15, REQ-2). This row used to say "one
# writer, and it is not this gate"; it says something stronger now, because there is no
# writer at all and the path is state nothing in the tree produces.
expect_no_file "the stop gate writes no observation record, ever" "$W1_REPO/$STATE_REL"

run_guard "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent", tool_input:{prompt:"go"}}')"
expect_status "the Agent tool is not this gate's business" 0 "$GUARD_ST"

# Static order pin: the cheap relevance test must precede the plan-directory
# walk in the source, not merely produce the same answer (arch-perf F8/F9 — the
# defect was cost, which behavior alone cannot detect). The relevance test is now
# the tool-name check itself.
_rel_line=$(grep -n 'TOOL_NAME" = "TaskStop" \] || exit 0' "$GUARD" | head -1 | cut -d: -f1)
# The expensive work used to begin at the plan walk; since task-engaged-session this gate
# reads no plan at all, and the first thing it pays for is resolving its context — the
# ancestor walk, the session id and every state path below them (RE-POINTED epic-23
# wave-11-lean-spine, REQ-1f: that resolution is `bionic_context`).
#
# BOTH LINE NUMBERS ARE ASSERTED FINDABLE FIRST. A grep whose literal has left the file
# yields the empty string, and an order pin over two empty values pins nothing while
# reading exactly like one that holds.
_walk_line=$(grep -n '^bionic_context' "$GUARD" | head -1 | cut -d: -f1)
expect_nonempty "the relevance test is findable in the guard's source" "$_rel_line"
expect_nonempty "the context resolution is findable in the guard's source" "$_walk_line"
if [ -n "$_rel_line" ] && [ -n "$_walk_line" ] && [ "$_rel_line" -lt "$_walk_line" ]; then
  ok "relevance check precedes the context resolution in source order"
else
  no "relevance check precedes the context resolution in source order" "relevance@${_rel_line:-none} walk@${_walk_line:-none}"
fi

section "§BID — a background shell id is the one the TRANSCRIPT recorded, else a 9-character [bt] id (wave-24 T10; REQ-7 AC-7.4; D12, research R4 §3)"
#
# The harness names a background shell `b<8 chars>` since 2026-09-03 (`t<8>` before), and records
# the id it handed out as `"backgroundTaskId":"<id>"`. The carve used to be `^t[a-z0-9]{8,}$`,
# so every real id was refused as "on no roster row". Standing is still asked FIRST: a name this
# session's roster carries is guarded whatever it is spelled like.

IFS='|' read -r W4_REPO W4_TR W4_SUB <<< "$(make_world w4 yes)"
plant_agent "$W4_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
sg_roster_row "$W4_REPO" "$SID_A" "quiet-reviewer" "aquiet-reviewer-deadbeefdeadbeef"

# bid1 — the id the harness handed out, `b` and nine characters: passes through, logged.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "b66vjp0ok")"
expect_status "bid1 a harness-spelled id (b66vjp0ok) with no row: PASSES THROUGH" 0 "$GUARD_ST"
expect_regex "bid1 …and the passthrough is logged, never silent" 'PASSTHROUGH' "$GUARD_ERR"

# bid2 — an id that is off the fallback shape is refused until the transcript records it, and
# passes the moment it does. Same payload, same roster: the transcript line is the only change.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "xq7mkd2wx")"
expect_status "bid2 an off-shape id the transcript never recorded: REFUSED" 2 "$GUARD_ST"
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_bid2","content":"Command running in background with ID: xq7mkd2wx"}]},"toolUseResult":{"stdout":"","backgroundTaskId":"xq7mkd2wx"}}' >> "$W4_TR"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "xq7mkd2wx")"
expect_status "bid2b …and once the transcript records backgroundTaskId xq7mkd2wx: PASSES THROUGH" 0 "$GUARD_ST"
expect_regex "bid2b …logged" 'PASSTHROUGH' "$GUARD_ERR"
# …EXACTLY that id: a prefix of a recorded id is a different id.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "xq7mkd2")"
expect_status "bid2c a prefix of a recorded id: REFUSED" 2 "$GUARD_ST"

# bid3 — a rostered name that wears the fallback shape (`b` + eight) is guarded, not waved
# through: standing is asked first. The agent is working, so the guard refuses it.
plant_agent "$W4_SUB" "abootstrap1-8888888888888888" "bootstrap1"
sg_roster_row "$W4_REPO" "$SID_A" "bootstrap1" "abootstrap1-8888888888888888"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "bootstrap1")"
expect_status "bid3 a ROSTERED 9-character b-name (bootstrap1): still guarded, the look taken (wave-31 T32: allowed, its verdict recorded as reason=)" 0 "$GUARD_ST"
expect_contains "bid3 …the guarded path's own line" "STOP ALLOWED" "$GUARD_ERR"
expect_absent "bid3 …and this is NOT the passthrough branch" "PASSTHROUGH" "$GUARD_ERR"
# …even when the transcript records that very string as a background id.
printf '%s\n' '{"toolUseResult":{"backgroundTaskId":"bootstrap1"}}' >> "$W4_TR"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "bootstrap1")"
expect_status "bid3b …and a transcript record of it does not take it out of the guard" 0 "$GUARD_ST"
expect_contains "bid3b …the guarded path's own line" "STOP ALLOWED" "$GUARD_ERR"
expect_absent "bid3b …nor reach the passthrough" "PASSTHROUGH" "$GUARD_ERR"

# bid4 — an unrostered name that is a name and not an id: refused (a hyphen is no id).
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "backlog-census")"
expect_status "bid4 an unrostered name (backlog-census): REFUSED" 2 "$GUARD_ST"

# bid5 — the fallback is exactly nine: a longer `b`/`t` run is not an id the harness hands out.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "b66vjp0okz")"
expect_status "bid5 a ten-character b-run: REFUSED" 2 "$GUARD_ST"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "tvivnv41s")"
expect_status "bid5b …and the old t-spelling, nine characters, still passes" 0 "$GUARD_ST"

section "Section 5: THE GATE LOOKS FOR ITSELF (REQ-2, AC-2.1/2.2/2.3; ADR-028)"
#
# WHAT THIS REPLACES. Sections 5, 6, 6b, 8 and 9 drove the record's five rules — D-1 activity
# freshness, D-2 consume-on-stop, the consume's own failure paths, D-3 same-actor and D-6
# progress staleness. Every one of them was a claim about the RECORD, and the field defect
# they added up to was the gate refusing a correct stop with "no observation exists in this
# repo" because nobody had run the verb (2026-09-15). The gate reads the target now, at the
# instant of the stop, and refuses ONE observed state: alive and undelivered.
#
# THE THREE FIXTURES BELOW ARE THE WHOLE OF THE CHANGE. At the parent commit the first is
# refused for want of a record, the second is refused for the wrong reason and prints none of
# the four facts, and the third is refused twice over.

# --- AC-2.1: NO RECORD IS NEEDED, because no record exists ---
#
# A rostered agent, an empty state directory, an idle target. The founding incident in one
# fixture: before this wave the answer was "No observation has been recorded in this repo at
# all", which is a fact about this repo's bookkeeping and not about the agent being stopped.
IFS='|' read -r A21_REPO A21_TR A21_SUB <<< "$(make_world ac21 yes)"
plant_agent "$A21_SUB" "aworker-7777777777777777" "worker"
sg_roster_row "$A21_REPO" "$SID_A" "worker" "aworker-7777777777777777"
age_log "$A21_SUB" "aworker-7777777777777777"
expect_no_file "AC-2.1 precondition: no observation record exists in this repo" \
  "$A21_REPO/$STATE_REL"
run_guard "$(mk_stop_payload "$SID_A" "$A21_TR" "$A21_REPO" "worker")"
expect_status "AC-2.1 a rostered, idle target with NO record anywhere: PERMITTED" 0 "$GUARD_ST"
expect_absent "AC-2.1 …and no refusal mentions a missing observation" \
  "No observation" "$GUARD_ERR"
expect_contains "AC-2.1 …and the look the gate took is on stderr" "STOP PERMITTED" "$GUARD_ERR"
expect_no_file "AC-2.1 …and permitting one wrote no record either" "$A21_REPO/$STATE_REL"

# --- AC-2.2: ALIVE AND UNDELIVERED IS THE ONE REFUSAL ---
#
# The log was touched ten seconds ago, the row declares a cadence of 300 seconds and names a
# deliverable that is not on disk. That is the case this wall exists for, and the refusal owes
# the reader the four facts it was made of (ADR-028).
IFS='|' read -r A22_REPO A22_TR A22_SUB <<< "$(make_world ac22 yes)"
mkdir -p "$A22_REPO/.bionic/docs/record" "$A22_REPO/.bionic/tmp"
plant_agent "$A22_SUB" "abusy-1212121212121212" "busy"
printf 'stage 1\n' > "$A22_REPO/.bionic/tmp/busy.progress"
sg_roster_row "$A22_REPO" "$SID_A" "busy" "abusy-1212121212121212" ".bionic/tmp/busy.progress" \
  "confirmed" ".bionic/docs/record/busy.md" "" "" "" "300 seconds"
wake_log "$A22_SUB" "abusy-1212121212121212"
run_guard "$(mk_stop_payload "$SID_A" "$A22_TR" "$A22_REPO" "busy")"
expect_status "AC-2.2 alive inside its cadence, deliverable absent (wave-31 T32: allowed, its verdict recorded as reason=)" 0 "$GUARD_ST"
expect_contains "AC-2.2 fact 1 — the working log's path" \
  "agent-abusy-1212121212121212.jsonl" "$GUARD_ERR"
expect_regex "AC-2.2 fact 2 — its age, against the cadence the row declared" \
  'last write:.*inside the declared cadence of 300s' "$GUARD_ERR"
expect_regex "AC-2.2 fact 3 — the progress artifact's state" \
  'progress: +present' "$GUARD_ERR"
expect_contains "AC-2.2 fact 4 — the deliverable it has not written" \
  ".bionic/docs/record/busy.md" "$GUARD_ERR"

# THE CADENCE IS THE ROW'S OWN, and that is what makes "alive" a fact rather than a clock.
# The identical world with a cadence of five seconds reads the same log as IDLE, and the stop
# goes through. Without this pair the row above is green on a gate with a hardcoded window.
IFS='|' read -r A22B_REPO A22B_TR A22B_SUB <<< "$(make_world ac22b yes)"
mkdir -p "$A22B_REPO/.bionic/docs/record"
plant_agent "$A22B_SUB" "abusy-1313131313131313" "busy"
sg_roster_row "$A22B_REPO" "$SID_A" "busy" "abusy-1313131313131313" "" \
  "confirmed" ".bionic/docs/record/busy2.md" "" "" "" "1 second"
# `touch -t` READS A LOCAL-TIME STAMP, so the stamp is computed in local time too — a
# `date -u` value applied here is off by the machine's offset, and on a machine behind UTC
# that puts the mtime in the FUTURE and the target reads as alive for the wrong reason.
touch -t "$(date -v-60S +%Y%m%d%H%M.%S 2>/dev/null || date -d '60 seconds ago' +%Y%m%d%H%M.%S)" \
  "$A22B_SUB/agent-abusy-1313131313131313.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$A22B_TR" "$A22B_REPO" "busy")"
expect_status "AC-2.2 control: a minute of quiet against a one-second cadence is IDLE: PERMITTED" \
  0 "$GUARD_ST"

# --- AC-2.3: IDLE, DELIVERED AND LANDED ALL PASS ---
IFS='|' read -r A23_REPO A23_TR A23_SUB <<< "$(make_world ac23 yes)"
mkdir -p "$A23_REPO/.bionic/docs/record"

# (a) IDLE: quiet for fifteen minutes against a five-minute cadence.
plant_agent "$A23_SUB" "aquiet-2121212121212121" "quiet"
sg_roster_row "$A23_REPO" "$SID_A" "quiet" "aquiet-2121212121212121" "" \
  "confirmed" ".bionic/docs/record/quiet.md" "" "" "" "5 min"
touch -t "$(date -v-900S +%Y%m%d%H%M.%S 2>/dev/null || date -d '900 seconds ago' +%Y%m%d%H%M.%S)" \
  "$A23_SUB/agent-aquiet-2121212121212121.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$A23_TR" "$A23_REPO" "quiet")"
expect_status "AC-2.3 (a) idle beyond its cadence: PERMITTED" 0 "$GUARD_ST"
expect_contains "AC-2.3 (a) …with the look on stderr" "is idle:" "$GUARD_ERR"

# (b) DELIVERED: the artifact is on disk, and the agent is working ANYWAY. The landing
# verdict has not called this contract MET — the artifact predates the launch reference — so
# this is the look's own answer and not the discharge one screen above it.
plant_agent "$A23_SUB" "adelivered-2222222222222222" "delivered-one"
printf 'the artifact\n' > "$A23_REPO/.bionic/docs/record/delivered.md"
touch -t 202601010000 "$A23_REPO/.bionic/docs/record/delivered.md"
sg_roster_row "$A23_REPO" "$SID_A" "delivered-one" "adelivered-2222222222222222" "" \
  "confirmed" ".bionic/docs/record/delivered.md" "" "" "" "5 min"
wake_log "$A23_SUB" "adelivered-2222222222222222"
run_guard "$(mk_stop_payload "$SID_A" "$A23_TR" "$A23_REPO" "delivered-one")"
expect_status "AC-2.3 (b) alive but DELIVERED: PERMITTED" 0 "$GUARD_ST"
expect_contains "AC-2.3 (b) …and the look says so" "is delivered:" "$GUARD_ERR"

# (c) LANDED: the row's contract is MET, which discharges the stop before any look is taken —
# the rule epic-16 wave-02 R2 established and this wave leaves exactly where it was.
plant_agent "$A23_SUB" "alanded-2323232323232323" "landed-one"
printf 'the artifact\n' > "$A23_REPO/.bionic/docs/record/landed.md"
sg_roster_row "$A23_REPO" "$SID_A" "landed-one" "alanded-2323232323232323" "" "confirmed" \
  ".bionic/docs/record/landed.md"
wake_log "$A23_SUB" "alanded-2323232323232323"
run_guard "$(mk_stop_payload "$SID_A" "$A23_TR" "$A23_REPO" "landed-one")"
expect_status "AC-2.3 (c) a LANDED row, alive or not: PERMITTED" 0 "$GUARD_ST"
expect_empty "AC-2.3 (c) …and the landing discharges it before any look, in silence" "$GUARD_ERR"

# (d) AN EMPTY ARTIFACT IS NOT A DELIVERY. The closed direction, and the pair that keeps (b)
# from being "any path the roster names".
plant_agent "$A23_SUB" "aempty-2424242424242424" "empty-one"
: > "$A23_REPO/.bionic/docs/record/empty.md"
sg_roster_row "$A23_REPO" "$SID_A" "empty-one" "aempty-2424242424242424" "" \
  "confirmed" ".bionic/docs/record/empty.md" "" "" "" "5 min"
wake_log "$A23_SUB" "aempty-2424242424242424"
run_guard "$(mk_stop_payload "$SID_A" "$A23_TR" "$A23_REPO" "empty-one")"
expect_status "AC-2.3 (d) a zero-byte artifact leaves the contract undelivered (wave-31 T32: allowed, its verdict recorded as reason=)" \
  0 "$GUARD_ST"

# (e) THE PROGRESS ARTIFACT IS THE SECOND CHANNEL, and it is the one that keeps an agent
# inside a forty-minute tool call from reading as idle. The working log is ancient; the
# contracted progress file moved a moment ago.
plant_agent "$A23_SUB" "alongcall-2525252525252525" "long-call"
mkdir -p "$A23_REPO/.bionic/tmp"
printf 'stage 1\n' > "$A23_REPO/.bionic/tmp/long.progress"
sg_roster_row "$A23_REPO" "$SID_A" "long-call" "alongcall-2525252525252525" \
  ".bionic/tmp/long.progress" "confirmed" ".bionic/docs/record/long.md" "" "" "" "5 min"
age_log "$A23_SUB" "alongcall-2525252525252525"
run_guard "$(mk_stop_payload "$SID_A" "$A23_TR" "$A23_REPO" "long-call")"
expect_status "AC-2.3 (e) a silent log but a moving progress artifact is ALIVE (wave-31 T32: allowed, its verdict recorded as reason=)" \
  0 "$GUARD_ST"
expect_regex "AC-2.3 (e) …and the verdict names the channel it read" \
  'progress: +present' "$GUARD_ERR"

# …and its pair: the same world with the progress artifact as old as the log.
touch -t 202601010000 "$A23_REPO/.bionic/tmp/long.progress"
run_guard "$(mk_stop_payload "$SID_A" "$A23_TR" "$A23_REPO" "long-call")"
expect_status "AC-2.3 (e) control: both channels quiet past the cadence: PERMITTED" 0 "$GUARD_ST"

section "Section 6a: the refusal's Fix line is runnable AS PRINTED (R2)"
#
# The ownership table names one test for fix-command text across TWO rendering
# gates, and it drove only the start gate's (Step-6 duplication review, row 5).
# This is the stop side's counterpart: capture the literal line a blocked
# orchestrator sees and EXECUTE it, from a non-repo cwd, against a staged copy
# of the real observation. The defect it pins: bracketed placeholders on the
# command line became positional arguments the observation reported as three
# absent deliverables (R2) — a refusal that teaches the reader something false.
IFS='|' read -r R2_REPO R2_TR R2_SUB <<< "$(make_world r2 yes)"
plant_agent "$R2_SUB" "ablocked-aaaaaaaaaaaaaaaa" "blocked"
# THE REFUSAL IS ONE THAT REMAINS (wave-31 T32): the stop of a working target is allowed now, so the
# Fix line is read off the refusal of a target whose row carries no agent id (`intended`).
sg_roster_row "$R2_REPO" "$SID_A" "blocked" "" "" "intended"
run_guard "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "blocked")"
expect_status "the stop of a target the roster holds no id for is refused (setup for R2)" 2 "$GUARD_ST"
# THE PASTEABLE FIX LINE IS IN THE DETAIL NOW (task 13, D-1): the user line names the
# repair in six words and the runnable command is what the knob carries, so this is read
# off the verbose stream. That it still EXECUTES is what the three arms below prove.
FIXLINE=$(printf '%s\n' "$GUARD_VERR" | grep '^Fix: ' | sed 's/^Fix: //')
expect_contains "a fix line was captured to execute" "stop-check.sh" "$FIXLINE"

# The world's OWN home, so the observation genuinely resolves the target and
# reaches its Deliverables section — otherwise it exits at "unresolved" and the
# fabricated-deliverable assertion below is vacuous.
R2_HOME="${R2_TR%%/.claude/projects/*}"
mkdir -p "$R2_HOME/.claude/hooks" "$SANDBOX/r2run/nowhere"
cp "$(dirname "$GUARD")/stop-check.sh" "$R2_HOME/.claude/hooks/stop-check.sh"
R2_OUT=$( cd "$SANDBOX/r2run/nowhere" && HOME="$R2_HOME" bash -c "$FIXLINE" 2>&1 )
R2_ST=$?
if [ "$R2_ST" -eq 127 ] || [ "$R2_ST" -eq 126 ]; then
  no "the captured fix line executes from a non-repo cwd" "exit $R2_ST: $R2_OUT"
else
  ok "the captured fix line executes from a non-repo cwd"
fi
expect_absent "running the fix line as printed produces no usage error" "Usage:" "$R2_OUT"

section "Section 7: hostile repo (AC-8, TDD §8, checklist A2/A3)"

# Predictable temp names + symlink-following writes were a PROVEN arbitrary-file
# overwrite in the discarded run (corr-sec S1/S2). Both levels are replanted.
IFS='|' read -r S_REPO S_TR S_SUB <<< "$(make_world sec yes)"
plant_agent "$S_SUB" "avictim-ffffffffffffffff" "victim"
sg_roster_row "$S_REPO" "$SID_A" "victim" "avictim-ffffffffffffffff"
mkdir -p "$S_REPO/.bionic/tmp"

# THE SYMLINKED STATE **FILE** CASE IS GONE WITH THE FILE IT GUARDED (epic-23 wave-15).
# A link planted at `.bionic/tmp/stop-check.state` let a repo choose which file this gate
# read its evidence out of — the OPEN direction §8 forbids — and the gate declined to read
# through it. The gate reads no such file now. The two levels it still reads THROUGH are the
# state directory and `.bionic` itself, and the directory case immediately below is the one
# that carries this claim forward.

IFS='|' read -r S2_REPO S2_TR S2_SUB <<< "$(make_world sec2 yes)"
plant_agent "$S2_SUB" "avictim-ffffffffffffffff" "victim"
OUTSIDE_DIR="$SANDBOX/sec2-outside-dir"
mkdir -p "$OUTSIDE_DIR" "$S2_REPO/.bionic"
# make_world plants a real .bionic/tmp (the engagement marker lives there); it has to GO,
# or `ln -s` lands the link INSIDE it and the hostile shape under test never exists — the
# same trap tests/dispatch-preflight.test.sh records at its own directory-symlink case.
rm -rf "$S2_REPO/.bionic/tmp"
ln -s "$OUTSIDE_DIR" "$S2_REPO/.bionic/tmp"
# The engagement marker travels to the far side with everything else this case redirects
# (task-engaged-session): the gate asks `engaged_session` first and its path runs through
# the redirected directory, so without it the gate would exit at the switch and the claim
# under test — that the state path is not read THROUGH a directory symlink — would be
# proven by an exit that never reached the state path.
: > "$OUTSIDE_DIR/engaged-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$S2_TR" "$S2_REPO" "victim")"
expect_status "a symlinked state DIRECTORY refuses the stop" 2 "$GUARD_ST"

# The ROSTER is repo-controlled state too, so a symlink at its own level would let
# a repo choose which file answers a question the gate asks — the OPEN direction §8
# forbids a repo from reaching. Since S6 the roster is where the agent ID comes from,
# which is what the observation channel is keyed on, so a planted roster is a repo
# naming the log a look would be compared against. Refusing to read through the link
# leaves the id unestablished, which is the closed side: the target resolves as live
# and the stop is refused for want of the one fact only a real row could supply.
IFS='|' read -r SR_REPO SR_TR SR_SUB <<< "$(make_world secroster yes)"
SR_TR_B="${SR_TR%/*}/$SID_B.jsonl"
plant_agent "${SR_TR_B%.jsonl}/subagents" "avictim-1818181818181818" "victim"
sg_roster_row "$SANDBOX/plantedroster" "$SID_A" "victim" "avictim-1818181818181818"
mkdir -p "$SR_REPO/.bionic/tmp"
ln -s "$SANDBOX/plantedroster/.bionic/tmp/roster-$SID_A.state" \
  "$SR_REPO/.bionic/tmp/roster-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$SR_TR_B" "$SR_REPO" "victim")"
expect_status "a symlinked roster refuses the stop" 2 "$GUARD_ST"
expect_contains "…because it was not read through: the id claim is never made" \
  "no agent id" "$GUARD_VERR"

# A ROSTER THAT EXISTS AND CANNOT BE READ IS THE SAME FACT (delta review S1). The symlink
# above is one way the register goes unreadable; a mode the gate's own uid cannot open is
# another, and the code's comment ("A roster this gate cannot read through is not a licence
# to pass") claimed both while the predicate tested only the first. At c19c16e this was
# closed by accident — standing came from the live set, so an unreadable roster left a live
# name refused for its missing id — and T22's move to the register turned the accident into
# a hole: every bare-name stop of every agent this session dispatched passed unguarded.
#
# THE DEGRADED MODE IS REAL: a hook process running under a different uid (a sandbox, a
# `sudo` shell, a half-finished permission repair) reads nothing and says nothing.
#
# ROOT READS THROUGH ANY MODE, so under uid 0 there is no unreadable file to make and the
# case is announced rather than faked — a mode-000 fixture that root can read would assert
# the OPPOSITE of this rule and pass for the wrong reason.
if [ "$(id -u)" -ne 0 ]; then
  IFS='|' read -r UR_REPO UR_TR UR_SUB <<< "$(make_world unreadroster yes)"
  plant_agent "$UR_SUB" "avictim2-1919191919191919" "victim2"
  sg_roster_row "$UR_REPO" "$SID_A" "victim2" "avictim2-1919191919191919" "" "identified"
  chmod 000 "$UR_REPO/.bionic/tmp/roster-$SID_A.state"
  run_guard "$(mk_stop_payload "$SID_A" "$UR_TR" "$UR_REPO" "victim2")"
  chmod 644 "$UR_REPO/.bionic/tmp/roster-$SID_A.state"
  expect_status "an UNREADABLE roster refuses the stop, exactly as a symlinked one does" \
    2 "$GUARD_ST"
  expect_contains "…because it was not read: the id claim is never made" \
    "no agent id" "$GUARD_VERR"
  expect_absent "…and it is never waved through as nobody's dispatch" \
    "PASSTHROUGH" "$GUARD_ERR"
else
  printf 'SKIPPED: the unreadable-roster case needs a non-root uid (root reads mode 000)\n' >&2
fi

# THE TEMP FILE IS GONE, WHICH IS STRONGER THAN NAMING IT WELL. The predictable-temp-name
# plus planted-symlink shape was a proven arbitrary-file overwrite in the discarded run
# (corr-sec S1/S2), and the answer then was an mktemp X-template. This gate writes NOTHING
# now — no record, no temp, no lock — so the class is closed by absence rather than by
# careful naming, and these two rows are what keep it that way.
expect_absent "the gate creates no temp file at all" "mktemp" "$(cat "$GUARD")"
expect_absent "no PID-based temp filename" '.tmp.$$' "$(cat "$GUARD")"

# The gate reads the working log; it must never quote it. (§8 keeps that
# disclosure in the observation, whose whole purpose is to show it to a reader.)
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"CANARY_LOG_BODY"}]}}\n' \
  >> "$S_SUB/agent-avictim-ffffffffffffffff.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$S_TR" "$S_REPO" "victim")"
expect_absent "the refusal prints no working-log contents" "CANARY_LOG_BODY" "$GUARD_ERR"

finish
