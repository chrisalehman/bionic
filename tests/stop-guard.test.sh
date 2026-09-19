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
# THE LANDING SWEEP'S OWN MARKER WRITER (S15, tests/lib/swept-marker.sh). §10(c4) needs a
# `landing-swept/v1|…|state=MET` line on a fixture roster — the thing that CLOSES a name's
# contract — and a hand-rolled printf of it would be a second spelling of a schema this repo
# holds to one writer, which is exactly what that library exists to stop.
. "$(dirname "$0")/lib/swept-marker.sh"

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
rigor: audited
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

setup_section "Section 2: WRITING moved out — see tests/execution-recorder.test.sh"
#
# Everything that used to be asserted here — a run records its target, a mention
# records nothing, an unresolvable or ambiguous target records nothing, the state
# is bounded and pruned, no command text leaks into it — is asserted against the
# script that now performs it, hooks/execution-recorder.sh. Duplicating those rows
# here would pin this gate to behaviour it no longer has.
#
# What this suite still owes the reader is that the gate SPENDS a real record, and
# every section below does exactly that: each one seeds through `observe()`, which
# runs the real observation and the real recorder end to end.

setup_section "Section 3: THE OBSERVATION RECORD IS GONE — see Section 5 (epic-23 wave-15)"
#
# This section drove the record's schema: an unknown EXTRA field left the reader working
# (checklist A6's forward compatibility) and an unknown schema VERSION refused the stop. Both
# were claims about a FILE the gate read instead of looking at the target, and ADR-028 ruled
# that a wall asserts only what it can observe at the moment of the act. There is no record,
# no version and no reader; what replaces all three is Section 5.

section "Section 4: fail directions at the stop gate (AC-10, TDD §7)"

# --- before the active-wave verdict: OPEN and SILENT ---
IFS='|' read -r N_REPO N_TR N_SUB <<< "$(make_world nowave no)"
plant_agent "$N_SUB" "aidle-4444444444444444" "idle"
run_guard "$(mk_stop_payload "$SID_A" "$N_TR" "$N_REPO" "idle")"
expect_status "no active wave: the stop passes" 0 "$GUARD_ST"
expect_empty "no active wave: the gate is silent" "$GUARD_ERR"

run_guard "$(jq -n --arg c "$N_REPO" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"TaskStop", tool_input:{task_id:"idle"}}')"
expect_status "no active wave + no session key: still open (pre-verdict)" 0 "$GUARD_ST"
expect_empty "no active wave + no session key: still silent" "$GUARD_ERR"

# A plan that exists but names no step is not a run in progress — AND SINCE
# task-engaged-session THAT IS NO LONGER THIS GATE'S QUESTION. What scopes it is
# ENGAGEMENT: a stop is policed because this session entered bionic, not because the repo
# holds a plan at a particular step. The roster row this gate answers for outlives the run
# that created it, and a run's Step 0 precedes its own plan, so a gate that read the step
# would go quiet at exactly the two moments a landing contract still exists. The fixture is
# kept and its expectation inverted: an ENGAGED session is policed here whatever the plan
# says, and the paired negative below is the marker, not the step.
IFS='|' read -r P_REPO P_TR P_SUB <<< "$(make_world plannostep yes)"
plant_agent "$P_SUB" "aidle-4444444444444444" "idle"
sg_roster_row "$P_REPO" "$SID_A" "idle" "aidle-4444444444444444"
sed -i.bak 's/^current: 4$/current: pending/' "$P_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
rm -f "$P_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md.bak"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_status "an engaged session is policed whatever the plan's step says: REFUSED" 2 "$GUARD_ST"
P_REFUSAL="$GUARD_ERR"

rm -f "$P_REPO/.bionic/tmp/engaged-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_status "…and the same stop unengaged is open" 0 "$GUARD_ST"
expect_empty "…and silent" "$GUARD_ERR"

# a SYMLINK at the marker path reads as ABSENT, never followed.
P_DECOY="$SANDBOX/plannostep-decoy-marker"; printf 'plan=none\n' > "$P_DECOY"
ln -s "$P_DECOY" "$P_REPO/.bionic/tmp/engaged-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_status "a symlink at the marker path is not an engagement: open" 0 "$GUARD_ST"
expect_empty "…and silent" "$GUARD_ERR"
rm -f "$P_REPO/.bionic/tmp/engaged-$SID_A.state"

# ANOTHER session's marker is not this session's.
: > "$P_REPO/.bionic/tmp/engaged-$SID_B.state"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_status "another session's marker is not this session's engagement: open" 0 "$GUARD_ST"
rm -f "$P_REPO/.bionic/tmp/engaged-$SID_B.state"

# restored, the refusal returns byte for byte.
: > "$P_REPO/.bionic/tmp/engaged-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_eq "re-engaged: the refusal is byte-identical" "$P_REFUSAL" "$GUARD_ERR"

# --- after the verdict: CLOSED and LOUD ---
IFS='|' read -r W4_REPO W4_TR W4_SUB <<< "$(make_world w4 yes)"
plant_agent "$W4_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
sg_roster_row "$W4_REPO" "$SID_A" "quiet-reviewer" "aquiet-reviewer-deadbeefdeadbeef"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer")"
expect_status "active wave + a target still working: REFUSED" 2 "$GUARD_ST"

# §7's stop=closed row, and since task-engaged-session it has to be driven on the channel
# that actually carries identity. The gate asks `engaged_session` first, keyed to the
# LIBRARY's session id (env primary, payload witness) — so a payload with no key still
# resolves to a session whenever the environment carries one, which on the machine it
# always does. What §7 pins is unchanged: once this session is known to be engaged, an
# identity the gate cannot read out of its own payload is refused, not waved through.
W4_NOKEY=$(jq -n --arg c "$W4_REPO" --arg t "$W4_TR" \
  '{transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:"TaskStop", tool_input:{task_id:"quiet-reviewer"}}')
GUARD_OUT=$(printf '%s' "$W4_NOKEY" | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$GUARD" 2>"$SANDBOX/.err"); GUARD_ST=$?
GUARD_ERR=$(cat "$SANDBOX/.err")
expect_status "active wave + payload missing its session key: REFUSED (closed)" 2 "$GUARD_ST"

# AND THE ROW BELOW IT, new with the switch: a payload with no key AND no key in the
# environment cannot be shown to belong to an engaged session at all. Engagement is
# open-by-absence by design — the one artifact whose PRESENCE opens walls — so this is
# silent rather than refused, and it is the only direction consistent with a bystander
# session never seeing a refusal it did not consent to.
GUARD_OUT=$(printf '%s' "$W4_NOKEY" | env -u CLAUDE_CODE_SESSION_ID bash "$GUARD" 2>"$SANDBOX/.err"); GUARD_ST=$?
GUARD_ERR=$(cat "$SANDBOX/.err")
expect_status "…and with no session key on EITHER channel: open, engagement unprovable" 0 "$GUARD_ST"
expect_empty "…and silent" "$GUARD_ERR"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "")"
expect_status "active wave + empty task_id: REFUSED" 2 "$GUARD_ST"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "no-such-agent")"
expect_status "active wave + unresolvable name (not address-shaped): REFUSED (D8, T5)" 2 "$GUARD_ST"
expect_regex "…and the one line names the fault" 'no roster row of this session' "$GUARD_ERR"

# THE SAME FIXTURE, RE-POINTED (T22, then D8/T5). Two live agents answering to one name used
# to refuse as an ambiguity. The register decides now, and neither of these two has a row on
# it — so this is the ordinary no-standing case, and the ambiguity it used to produce is
# prevented one event earlier, at the dispatch wall. No-standing REFUSES since D8 (T5); the
# passthrough it used to be survives only for a bash-task-shaped target (§4a below).
plant_agent "$W4_SUB" "adouble-5555555555555555" "twin"
plant_agent "$W4_SUB" "adouble-6666666666666666" "twin"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "twin")"
expect_status "two same-named agents on no roster row of this session: REFUSED (D8, T5)" 2 "$GUARD_ST"
expect_regex "…and the one line names the fault" 'no roster row of this session' "$GUARD_ERR"

# A plan with CR-only line endings is still a plan. `tr -d` on those separators
# collapses the file to one line, the run-state marker goes unseen, and the gate
# quietly reports "no wave" on a repo mid-wave — the fail-dangerous shape that
# bypassed the evidence gate for a whole wave (.claude/rules/hook-authoring.md).
IFS='|' read -r CR_REPO CR_TR CR_SUB <<< "$(make_world crplan yes)"
plant_agent "$CR_SUB" "acrlf-0123456789abcdef" "crlf"
sg_roster_row "$CR_REPO" "$SID_A" "crlf" "acrlf-0123456789abcdef"
CR_PLAN="$CR_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
tr '\n' '\r' < "$CR_PLAN" > "$CR_PLAN.cr" && mv "$CR_PLAN.cr" "$CR_PLAN"
run_guard "$(mk_stop_payload "$SID_A" "$CR_TR" "$CR_REPO" "crlf")"
expect_status "a CR-only plan is still read: the wave is still detected" 2 "$GUARD_ST"

# The positive pair — a wall that refuses everything is equally broken (§9). The SAME world,
# the SAME target, one fact changed: the agent has gone quiet past its cadence.
age_log "$W4_SUB" "aquiet-reviewer-deadbeefdeadbeef"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer")"
expect_status "active wave + the same target gone quiet: PERMITTED" 0 "$GUARD_ST"
expect_contains "a permitted stop carries the look that permitted it" "STOP PERMITTED" "$GUARD_ERR"

section "Section 4a: unsupervised-target passthrough (T4, AC-6)"
#
# scan_subagent_dirs only ever iterates agent-*.meta.json — the Agent tool's own
# bookkeeping. A background bash task id never gets one (A-D4), so MATCH_COUNT
# was unconditionally 0 for it, forever, with no code path back to
# order_current() — the escape hatch this gate's own header advertises
# (step2-research-a1-a3.md §A3). The ratified carve (session.plan.md ## Design
# ¶T4): refuse only a target wearing an AGENT-ADDRESS shape (`@session-`, or
# transcript-form `a<hex>` / `a<name>-<16hex>`); everything else passes through,
# logged once, never silent.

# THE WORLD'S OWN TARGET IS QUIET AGAIN for the rows below, which are about SHAPE and not
# about liveness: §4 left it aged, and that is the state this section reads it in.
#
# (a) A bash-background-task-shaped id (A-D4 probe evidence: t5triyxvo) carries
# no agent metadata and wears no address shape: PASSES THROUGH.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "t5triyxvo")"
expect_status "a bash-task-shaped target with no metadata: PASSES THROUGH" 0 "$GUARD_ST"
expect_regex "…and the passthrough is logged, never silent" 'PASSTHROUGH' "$GUARD_ERR"

# (a2) AC-5.2: a nine-character lowercase-alnum name leading `a` (not `t`) is NOT
# bash-task-shaped by construction — `is_bash_task_shaped` requires the `t` prefix — so shape
# alone never waves it through. It happens to also satisfy `is_address_shaped`'s hex-id
# pattern (digits 1-8 are valid hex digits), so it is refused on the same unresolved-address
# path as (c) below rather than the new no-row path; either way it is exit 2, never a pass.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "a12345678")"
expect_status "a nine-character name leading 'a': REFUSED, never passes on shape alone (AC-5.2)" 2 "$GUARD_ST"

# (b) An addressing-form target (`name@session-xxxx`) with no metadata IS
# address-shaped: stays REFUSED, the verbatim unresolved-target message unchanged.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "ghost@session-deadbeef")"
expect_status "an addressing-form target with no metadata: still REFUSED" 2 "$GUARD_ST"

# (c) Transcript-form targets (`a`+hex, and `a<name>-<16hex>`) with no metadata
# ARE address-shaped: stay REFUSED.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "af3d9128ea3b393af")"
expect_status "a hex transcript-form target with no metadata: still REFUSED" 2 "$GUARD_ST"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "aghost-0123456789abcdef")"
expect_status "a named transcript-form target with no metadata: still REFUSED" 2 "$GUARD_ST"

# (d) A supervised named target (metadata present) still engages the FULL guard
# path, untouched — the passthrough branch is reached only at MATCH_COUNT=0, and
# a target that resolves to a real agent of this session never gets there.
# DRIVEN (Step-6 review flag 2-C: a bare `ok` here asserted nothing and could not
# fail). Quiet-reviewer's own REFUSED/PERMITTED pair above already proves the
# full path for that name; this plants a SECOND, never-observed teammate in the
# same active-wave world so the assertion here carries its own evidence rather
# than pointing at rows planted for a different purpose.
plant_agent "$W4_SUB" "ahushed-reviewer-7777777777777777" "hushed-reviewer"
sg_roster_row "$W4_REPO" "$SID_A" "hushed-reviewer" "ahushed-reviewer-7777777777777777"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "hushed-reviewer")"
expect_status "a supervised named target still engages the full guard path: REFUSED, it is working" 2 "$GUARD_ST"
expect_absent "…and this is NOT the passthrough branch" "PASSTHROUGH" "$GUARD_ERR"

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
expect_status "AC-2.2 alive inside its cadence, deliverable absent: REFUSED" 2 "$GUARD_ST"
expect_contains "AC-2.2 …and the one line names what was observed" \
  "it is still working, nothing delivered" "$GUARD_ERR"
expect_contains "AC-2.2 fact 1 — the working log's path" \
  "agent-abusy-1212121212121212.jsonl" "$GUARD_VERR"
expect_regex "AC-2.2 fact 2 — its age, against the cadence the row declared" \
  'last write:.*inside the declared cadence of 300s' "$GUARD_VERR"
expect_regex "AC-2.2 fact 3 — the progress artifact's state" \
  'progress: +present' "$GUARD_VERR"
expect_contains "AC-2.2 fact 4 — the deliverable it has not written" \
  ".bionic/docs/record/busy.md" "$GUARD_VERR"

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
expect_status "AC-2.3 (d) a zero-byte artifact leaves the contract undelivered: REFUSED" \
  2 "$GUARD_ST"

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
expect_status "AC-2.3 (e) a silent log but a moving progress artifact is ALIVE: REFUSED" \
  2 "$GUARD_ST"
expect_regex "AC-2.3 (e) …and the refusal names the channel it read" \
  'progress: +present' "$GUARD_VERR"

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
sg_roster_row "$R2_REPO" "$SID_A" "blocked" "ablocked-aaaaaaaaaaaaaaaa"
run_guard "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "blocked")"
expect_status "the stop of a working target is refused (setup for R2)" 2 "$GUARD_ST"
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

setup_section "Section 6b: THE CONSUME IS GONE — nothing is spent by a stop (epic-23 wave-15)"
#
# C3 (a consume that cannot complete must REFUSE) and S2 (the lock wait is bounded) were the
# two failure paths of D-2, one observation discharging one stop. There is no observation to
# spend and no lock to take: the gate reads the target and decides. The state directory it
# still reads THROUGH is covered by §7, and the gate writing nothing at all is §1's row.

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
expect_contains "…for the symlink reason specifically, not a fallback one" \
  "nothing here will read through it" "$GUARD_VERR"

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

setup_section "Sections 8 and 9: D-3 AND D-6 ARE GONE WITH THE RECORD (epic-23 wave-15)"
#
# D-3 asked whether the recorded look was the STOPPER'S OWN, and D-6 whether it had opened the
# contracted progress artifact. Both were questions about a record's provenance, and both are
# answered by construction now: the gate takes the look itself, in its own process, at the
# instant of the stop, and it reads BOTH channels every time — there is no actor to borrow
# from and no channel to skip. §5 (e) is what carries the progress channel forward.

section "Section 10: AC-9 — resolution IS the live set, and the double file is not an ambiguity"
#
# WHAT THIS SECTION USED TO BE, and why it is gone. It drove the OWNING-DIRECTORY rule: an
# agent whose `agent-<id>.meta.json` sat under another session's `subagents/` was FOREIGN and
# a stop of it by name was refused. That rule answered "is this agent mine" from RECORDS on
# disk, and the records outlive the agents — which is how a `/clear` produced the field defect
# this wave exists to fix (report §B-2): the same agent's metadata filed under two session
# directories, MATCH_COUNT=2, and every spelling of a bare name refused as ambiguous while the
# agent was still running and its contract had landed.
#
# WHAT REPLACES IT (D1′/D2′). The live set: the newest recorded ListAgents answer, which is
# the harness's own statement about which teammates exist right now. An agent it names is one
# this session can address; one it does not name is not stoppable here whatever is on disk.
# Ownership by id and the contract still come from the session roster row, which is the only
# thing that ever knew them.

IFS='|' read -r LV_REPO LV_TR LV_SUB <<< "$(make_world liveset yes)"
mkdir -p "$LV_REPO/.bionic/docs/record"
LV_TR_B="${LV_TR%/*}/$SID_B.jsonl"
LV_SUB_B="${LV_TR_B%.jsonl}/subagents"

# (a) THE DOUBLE FILE, the fixture research-code-map §4.4 proved on this machine: ONE agent,
# ONE name, its meta.json BYTE-IDENTICAL in two session directories, its working log in both.
# The live set names it once, so it is one agent — and with a MET contract the stop passes
# with no observation at all (AC-9).
plant_agent "$LV_SUB" "aw1-rc-e0886335875ba2d1" "w1-rc"
cp "$LV_SUB/agent-aw1-rc-e0886335875ba2d1.meta.json" "$LV_SUB_B/agent-aw1-rc-e0886335875ba2d1.meta.json"
cp "$LV_SUB/agent-aw1-rc-e0886335875ba2d1.jsonl"     "$LV_SUB_B/agent-aw1-rc-e0886335875ba2d1.jsonl"
if cmp -s "$LV_SUB/agent-aw1-rc-e0886335875ba2d1.meta.json" \
          "$LV_SUB_B/agent-aw1-rc-e0886335875ba2d1.meta.json"; then
  ok "the double-file fixture is byte-identical in both session directories"
else
  no "the double-file fixture is byte-identical in both session directories"
fi
echo "the delivered artifact" > "$LV_REPO/.bionic/docs/record/w1-rc.md"
# `adopted_from` is what put BOTH directories in scope for the old scan — the successor
# session took the row over after a /clear — and it is what made the double file a
# MATCH_COUNT=2 ambiguity there. It stays on the row: after this task it is read only for
# the session the working log is filed under, never for resolution.
sg_roster_row "$LV_REPO" "$SID_A" "w1-rc" "aw1-rc-e0886335875ba2d1" "" "confirmed" \
  ".bionic/docs/record/w1-rc.md" "" "" "$SID_B"
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "w1-rc")"
expect_status "the double-filed agent, MET, stopped by BARE NAME: PASSES with no observation" \
  0 "$GUARD_ST"
expect_empty "…and the gate is silent — no ambiguity refusal anywhere" "$GUARD_ERR"

# …and the same double file with an UNMET contract meets the ordinary ceremony, not an
# ambiguity refusal. Without this pair the pass above is equally green on a gate that has
# stopped deciding anything.
plant_agent "$LV_SUB" "aw2-rc-e0886335875ba2d2" "w2-rc"
cp "$LV_SUB/agent-aw2-rc-e0886335875ba2d2.meta.json" "$LV_SUB_B/agent-aw2-rc-e0886335875ba2d2.meta.json"
cp "$LV_SUB/agent-aw2-rc-e0886335875ba2d2.jsonl"     "$LV_SUB_B/agent-aw2-rc-e0886335875ba2d2.jsonl"
sg_roster_row "$LV_REPO" "$SID_A" "w2-rc" "aw2-rc-e0886335875ba2d2" "" "confirmed" \
  ".bionic/docs/record/w2-rc.md" "" "" "$SID_B"
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "w2-rc")"
expect_status "the same double file, contract UNMET and the agent working: REFUSED" 2 "$GUARD_ST"
expect_contains "…and it is the target's own liveness, not an ambiguity" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"
expect_absent "…nothing calls the double file ambiguous" "ambiguous" "$GUARD_ERR"

# (b) A NAME THE ANSWER DOES NOT CARRY is not live, and the refusal says so. `ghost` is on
# disk in this world's other session directory and in nobody's live set.
plant_agent "$LV_SUB_B" "aghost-9999999999999999" "ghost"
# RE-POINTED AT THE ROSTER (T22). The live set is gone from this gate, so what answers an
# `@session-` target is the alias rule — is there a roster in this root, belonging to the
# session the suffix names, carrying this name? For `ghost` there is not, and that is the
# fact. The old arm refused it for want of a fresh panel reading, which was a statement
# about the transcript rather than about this target.
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "ghost@session-${SID_B:0:8}")"
expect_status "an alias naming a session whose roster never carried it: REFUSED" 2 "$GUARD_ST"
expect_contains "…and the refusal names the register's own answer" \
  "is not an accepted alias" "$GUARD_VERR"
expect_absent "…and never calls it foreign — that rule is gone" "FOREIGN" "$GUARD_ERR"
expect_absent "…and never asks for a ListAgents call" "ListAgents" "$GUARD_VERR"

# (c) TWO LIVE ENTRIES OF ONE NAME. The refusal names both, and it does NOT offer the
# `@session-` alias as a way out: an alias must resolve to the same SINGLE entry (AC-11), so
# there is no spelling of this target the gate can accept.
IFS='|' read -r TW_REPO TW_TR TW_SUB <<< "$(make_world twolaunchers yes)"
plant_agent "$TW_SUB" "atwin-1111111111111111" "twin"
plant_agent "$TW_SUB" "atwin-2222222222222222" "twin"
sg_roster_row "$TW_REPO" "$SID_A" "twin" "atwin-1111111111111111"
# THE AMBIGUITY ARM IS RETIRED (T22). It existed because a NAME was not an identity: the
# live set could carry two `twin`s and the gate had no way to choose. The door is shut one
# event earlier now — `hooks/dispatch-preflight.sh` refuses a dispatch whose name already
# has an open row on this session's roster — so one name means one row, the row carries the
# id, and there is nothing left here to be ambiguous about. The same fixture that used to
# produce an ambiguity refusal now resolves through the roster and meets the ordinary
# ceremony.
run_guard "$(mk_stop_payload "$SID_A" "$TW_TR" "$TW_REPO" "twin")"
expect_status "a name the live set carries twice resolves on the ROSTER: the look, not an ambiguity" \
  2 "$GUARD_ST"
expect_contains "…and the refusal is the target's liveness" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"
expect_absent "…nothing calls it ambiguous any more" "ambiguous" "$GUARD_ERR"
run_guard "$(mk_stop_payload "$SID_A" "$TW_TR" "$TW_REPO" "twin@session-${SID_A:0:8}")"
expect_status "…and the alias spelling resolves the same way" 2 "$GUARD_ST"
expect_contains "…to the same liveness refusal" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"

# (c3) TWO LIVE ROWS, ONE BARE NAME — THE AMBIGUITY TRANSLATED TO THE REGISTER (T29).
#
# The arm (c) retired was the LIVE SET's: two teammates of one name in the harness's answer,
# and nothing on the roster. §7's cell never moved — the stop gate is CLOSED and loud on an
# ambiguous identity, because a stop is irreversible — so what had to move with the resolver
# is where the ambiguity is COUNTED. On the register it is two rows of one name both under an
# OPEN contract (intended/confirmed/identified, no `landing-swept/v1|…|state=MET` marker
# closing them) carrying two different agent ids: one name, two live contracts, two processes.
#
# IT IS REACHABLE AT THIS HEAD, which is why this is an arm and not a retirement. The
# dispatch wall's name-in-flight arm shuts the door on a second DISPATCH under a live name,
# but it is not the only writer of live rows: `hooks/session-poker.sh`'s `adopt_write_row`
# journals a predecessor's agent onto this session's roster as `status=identified`, and its
# idempotence check is `agent_id` + `adopted_from` — never whether this session already
# carries a live row of that NAME. A session that dispatched `twin` and then adopted a
# predecessor which had also run one produces exactly the file below.
sg_roster_row "$TW_REPO" "$SID_A" "twin" "atwin-2222222222222222" "" "identified" \
  "" "" "" "$SID_B"
# THE ADOPTED ROW'S WORKING LOG IS FILED UNDER ITS LAUNCHER, which is the whole of what
# `adopted_from` means — so the second twin is planted there, or the look would resolve a log
# that is not on disk and read the target as idle for a reason this section is not about.
plant_agent "${TW_TR%/*}/$SID_B/subagents" "atwin-2222222222222222" "twin"
run_guard "$(mk_stop_payload "$SID_A" "$TW_TR" "$TW_REPO" "twin")"
expect_status "a bare name carrying TWO live roster rows: REFUSED (§7 — CLOSED, loud)" 2 "$GUARD_ST"
expect_regex "…and the one line names the fault" 'more than one live row' "$GUARD_ERR"
expect_contains "…and the detail calls the target ambiguous" "is ambiguous" "$GUARD_VERR"
expect_contains "…and names the first agent id as an unambiguous spelling" \
  "atwin-1111111111111111" "$GUARD_VERR"
expect_contains "…and the second one too" "atwin-2222222222222222" "$GUARD_VERR"
expect_absent "…and it is not the liveness refusal: resolution never got that far" \
  "is ALIVE" "$GUARD_VERR"

# …and the ALIAS cannot separate them, exactly as it could not separate two live teammates:
# the suffix names the session that LAUNCHED an agent, and both of these rows are addressed
# from here. The spelling that does separate them is the agent id, which is what the refusal
# offers.
run_guard "$(mk_stop_payload "$SID_A" "$TW_TR" "$TW_REPO" "twin@session-${SID_A:0:8}")"
expect_status "…and the @session- alias of an ambiguous name: REFUSED too" 2 "$GUARD_ST"
expect_regex "…with the same fault, not the alias rule" 'more than one live row' "$GUARD_ERR"

# …while the ID spelling resolves, because it is the escape hatch the refusal names. An
# agent id is unambiguous against the register by construction: exactly one row carries it.
# Without this row the arm above is equally green on a gate that refuses every spelling.
run_guard "$(mk_stop_payload "$SID_A" "$TW_TR" "$TW_REPO" "atwin-2222222222222222")"
expect_status "…while the full agent id resolves and meets the ordinary look" 2 "$GUARD_ST"
expect_contains "…which is the target's liveness, not an ambiguity" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"
expect_absent "…nothing calls the id ambiguous" "more than one live row" "$GUARD_ERR"

# (c5) THE ID THE AMBIGUITY REFUSAL PRESCRIBES REACHES THE ROW IT NAMES (T31; delta review D1).
#
# (c3) proves an agent id is not REFUSED. It never proved the id RESOLVES to its own row, and
# until T31 it did not: `AGENT_ID` came off `ROW_WITH_ID`, the LAST confirmed/identified row
# of the NAME, which the second walk recomputes once an id has been translated into that name.
# On an ambiguous roster both ids therefore landed on whichever row is last — so the
# observation channel, the contract row and the working-log path all belonged to the OTHER
# agent, and the way out this refusal prints ("name the full agent id") led straight into it:
# a look at one twin discharged a stop of the other. That is an irreversible act on an agent
# nobody looked at, in exactly the state §7 puts this gate on the CLOSED side of.
#
# The world below is (c3)'s state with ONE twin QUIET: `atwin-2222…` has gone idle and
# `atwin-1111…` is still writing. The working twin must be refused and the quiet one
# permitted, and each answer must be about the row the typed id names — before T31 the first
# drive PERMITTED the stop by reading the OTHER row's facts, which is the two halves failing
# together.
IFS='|' read -r TI_REPO TI_TR TI_SUB <<< "$(make_world typedid yes)"
plant_agent "$TI_SUB" "atwin-1111111111111111" "twin"
plant_agent "$TI_SUB" "atwin-2222222222222222" "twin"
sg_roster_row "$TI_REPO" "$SID_A" "twin" "atwin-1111111111111111" "" "identified"
sg_roster_row "$TI_REPO" "$SID_A" "twin" "atwin-2222222222222222" "" "identified"
age_log "$TI_SUB" "atwin-2222222222222222"

run_guard "$(mk_stop_payload "$SID_A" "$TI_TR" "$TI_REPO" "atwin-1111111111111111")"
expect_status "the id of the WORKING twin: REFUSED, never let through by its twin's quiet" \
  2 "$GUARD_ST"
# The id inside the parentheses is what the gate RESOLVED. Printing the typed id back beside
# itself is the whole claim: before T31 this line read `(atwin-2222222222222222)`, naming the
# row whose facts were read while permitting a stop of the other one.
expect_contains "…and the refusal names the id that was typed, resolved to itself" \
  "'atwin-1111111111111111' (atwin-1111111111111111) is ALIVE" "$GUARD_VERR"
expect_absent "…and the other row's id is nowhere in the refusal" \
  "atwin-2222222222222222" "$GUARD_VERR"

# THE PAIRED CONTROL, and what makes the arm above a RESOLUTION rule rather than a ban on
# ids: the id that IS quiet is stoppable. A gate that refused every id on an ambiguous roster
# passes all three assertions above and fails this one.
run_guard "$(mk_stop_payload "$SID_A" "$TI_TR" "$TI_REPO" "atwin-2222222222222222")"
expect_status "…while the twin that has gone quiet is stoppable by its own id" 0 "$GUARD_ST"
expect_contains "…and the look names the row it resolved" \
  "STOP PERMITTED" "$GUARD_ERR"

# (c4) THE CONTROL — A LANDED ROW BESIDE A LIVE ONE IS NOT AN AMBIGUITY (T26's reading).
#
# A name that landed and was dispatched AGAIN carries two rows and two ids, and only the row
# BELOW the MET marker is under an open contract. Read as a set that file is (c3); read in
# ORDER — which is what T26 fixed in both roster walls — the marker closes the id above it
# and the live row below it is the one identity there is. Without this row the arm above is
# green on a gate that refuses every re-run of every task, which is the latch C1 named.
IFS='|' read -r RL_REPO RL_TR RL_SUB <<< "$(make_world relaunched yes)"
plant_agent "$RL_SUB" "arerun-1111111111111111" "rerun"
plant_agent "$RL_SUB" "arerun-2222222222222222" "rerun"
sg_roster_row "$RL_REPO" "$SID_A" "rerun" "arerun-1111111111111111"
swept_marker_write "$RL_REPO/.bionic/tmp/roster-$SID_A.state" \
  "2026-09-14T00:00:00Z" "$SID_A" "rerun" "arerun-1111111111111111" "MET"
sg_roster_row "$RL_REPO" "$SID_A" "rerun" "arerun-2222222222222222"
# A BYSTANDER WITH A ROW OF ITS OWN, kept from the world this case was first written in: it
# is what proves the refusal below is about the re-run's own row rather than about anything
# repo-wide.
plant_agent "$RL_SUB" "abystander-3333333333333333" "bystander"
sg_roster_row "$RL_REPO" "$SID_A" "bystander" "abystander-3333333333333333"
run_guard "$(mk_stop_payload "$SID_A" "$RL_TR" "$RL_REPO" "rerun")"
expect_status "a landed row beside the re-run's live row: NOT ambiguous — the live row answers" \
  2 "$GUARD_ST"
expect_absent "…nothing calls the re-run ambiguous" "more than one live row" "$GUARD_ERR"
expect_contains "…and resolution lands on the LIVE row's id" \
  "arerun-2222222222222222" "$GUARD_VERR"
expect_absent "…never on the id the MET marker closed" "arerun-1111111111111111" "$GUARD_VERR"

# (c2) A NAME CARRYING A REGEX METACHARACTER must count and list ONLY its own two entries,
# never a bystander name that merely LOOKS like it under BRE matching (Step-6 security review
# S-5, third instance). `a.b`'s `.` would match any single character, so an unfixed reader
# widens both the count and the listing to include `axb` — a name nobody asked about.
IFS='|' read -r RX_REPO RX_TR RX_SUB <<< "$(make_world regexambig yes)"
plant_agent "$RX_SUB" "arxa-1111111111111111" "a.b"
plant_agent "$RX_SUB" "arxb-2222222222222222" "a.b"
plant_agent "$RX_SUB" "arxc-3333333333333333" "axb"
sg_roster_row "$RX_REPO" "$SID_A" "a.b" "arxa-1111111111111111"
# THE METACHARACTER ROW SURVIVES THE ARM IT WAS WRITTEN FOR (T22). Its point was that a
# `.` in a typed name must never widen a match, and the roster walk it now runs through
# compares by FIELD EQUALITY exactly as the retired listing did — `a.b` resolves to the row
# named `a.b` and never to the bystander `axb`.
run_guard "$(mk_stop_payload "$SID_A" "$RX_TR" "$RX_REPO" "a.b")"
expect_status "a name with a regex metacharacter resolves on the roster: the look" 2 "$GUARD_ST"
expect_contains "…and the refusal is the target's liveness" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"
expect_absent "…never widened to the bystander name the dot happens to match" \
  "axb" "$GUARD_ERR"

# (d) A LIVE AGENT THIS SESSION'S ROSTER CARRIES NO ID FOR cannot be observed — the working
# log is `<session>/subagents/agent-<id>.jsonl` and the roster row is the only thing that
# knows the id once the directory scan is gone. It is refused, and the refusal says which
# fact is missing rather than demanding a look that cannot be taken.
# RE-POINTED (T22), then RE-POINTED AGAIN (D8, T5). A bare name with NO row of any status on
# this session's roster is not this session's dispatch — the preflight opens a row before it
# allows one — so the gate has no standing over it, and since D8 that is a REFUSAL rather than
# a passthrough: only a background bash task id still gets the T4/AC-6 carve (§4a). What still
# refuses for the missing id, on a DIFFERENT fact, is a name the register DOES carry, on the
# `intended` row below.
plant_agent "$LV_SUB" "aunrostered-8888888888888888" "unrostered"
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "unrostered")"
expect_status "a bare name on no roster row of this session: REFUSED (D8, T5)" 2 "$GUARD_ST"
expect_regex "…and the one line names the fault" 'no roster row of this session' "$GUARD_ERR"

# …and an `intended` row is still not an ownership claim: its id is a claim about a launch
# nothing has observed. Unchanged from task 4/9, on the channel that now carries it.
sg_roster_row "$LV_REPO" "$SID_A" "unrostered" "aunrostered-8888888888888888" "" "intended"
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "unrostered")"
expect_status "an INTENDED row's id establishes nothing: still REFUSED" 2 "$GUARD_ST"
expect_contains "…for the same missing fact" "no agent id" "$GUARD_VERR"

# …and the paired positive: the same row `identified` carries the id, and the ordinary
# ceremony resumes.
sg_roster_row "$LV_REPO" "$SID_A" "unrostered" "aunrostered-8888888888888888" "" "identified"
age_log "$LV_SUB" "aunrostered-8888888888888888"
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "unrostered")"
expect_status "an IDENTIFIED row's id makes the target observable: PERMITTED" 0 "$GUARD_ST"
expect_contains "…and the look it made possible is on stderr" "STOP PERMITTED" "$GUARD_ERR"

# (e) THE TRANSCRIPT-FORM ID still addresses an agent, by way of the roster row that carries
# it — this task moved where the id comes from, it did not retire the spelling.
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "aunrostered-8888888888888888")"
expect_status "the transcript-form id resolves through the roster row: PERMITTED" 0 "$GUARD_ST"

# …and an id NO row carries resolves to nothing, address-shaped, so it is refused.
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "anobody-0000000000000000")"
expect_status "a transcript-form id no roster row carries: REFUSED" 2 "$GUARD_ST"

# (f) `name@team` is not an address form this gate accepts — the suffix must name a session.
run_guard "$(mk_stop_payload "$SID_A" "$LV_TR" "$LV_REPO" "unrostered@team")"
expect_status "name@team is not an accepted alias: REFUSED" 2 "$GUARD_ST"
expect_contains "…and the refusal names the accepted form" "@session-" "$GUARD_VERR"

section "Section 11: FACTS DISCHARGE THE STOP (epic-16 w2 S3, AC-1/AC-2, R2)"
#
# The ceremony was never the point — the point was that a stop not destroy work
# nobody had looked at. When the contract has LANDED, the artifact on disk is a
# better answer to that question than any look, and it cannot go stale. So the
# discharge set is a fact set: the sweeper's verdict says MET against a declared
# artifact, or WAIVED, or the orchestrator has acked the row. Everything else is
# unchanged — Sections 4 through 10 above are the same arc they were, and they
# still pass, which is the paired positive for "ceremony survives".

IFS='|' read -r F_REPO F_TR F_SUB <<< "$(make_world facts yes)"
mkdir -p "$F_REPO/.bionic/docs/record"

# --- MET: the artifact is on disk, written after the launch ---
plant_agent "$F_SUB" "alander-1111111111111111" "lander"
echo "the delivered artifact" > "$F_REPO/.bionic/docs/record/lander.md"
sg_roster_row "$F_REPO" "$SID_A" "lander" "alander-1111111111111111" "" "confirmed" \
  ".bionic/docs/record/lander.md"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "lander")"
expect_status "MET contract: the stop passes with NO observation ever taken" 0 "$GUARD_ST"
expect_empty "…and the gate says nothing at all — zero ceremony" "$GUARD_ERR"

# --- paired negative: same world, same everything, artifact absent ---
plant_agent "$F_SUB" "aslacker-2222222222222222" "slacker"
sg_roster_row "$F_REPO" "$SID_A" "slacker" "aslacker-2222222222222222" "" "confirmed" \
  ".bionic/docs/record/slacker.md"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "slacker")"
expect_status "UNMET contract and the agent still writing: REFUSED" 2 "$GUARD_ST"
expect_contains "…on the look, not on the landing verdict" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"

# --- WAIVED: an explicit designation discharges as surely as an artifact ---
plant_agent "$F_SUB" "awaived-3333333333333333" "waived-one"
sg_roster_row "$F_REPO" "$SID_A" "waived-one" "awaived-3333333333333333" "" "confirmed" \
  "" "this dispatch produces nothing durable"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "waived-one")"
expect_status "WAIVED contract: the stop passes with no observation" 0 "$GUARD_ST"
expect_empty "…and silently" "$GUARD_ERR"

# --- ACKED: the orchestrator's verification, made durable, closes the row ---
#
# This is the case the field kept paying for: an agent that finished, was
# verified and was acked still cost an observation, a staleness round and four
# calls to stop. The ack is invisible to `verdict` by wave-01 design (a contract
# is met by artifacts or it is not), so the gate reads the sweeper's LEDGER —
# and it reads a ledger this suite makes the real `ack` verb write.
plant_agent "$F_SUB" "aacked-4444444444444444" "acked-one"
sg_roster_row "$F_REPO" "$SID_A" "acked-one" "aacked-4444444444444444" "" "confirmed" \
  ".bionic/docs/record/never-written.md"
ack_row "$F_REPO" "$SID_A" "acked-one"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "acked-one")"
expect_status "ACKED row: the stop passes though the contract is UNMET" 0 "$GUARD_ST"
expect_empty "…and silently" "$GUARD_ERR"

# An ack of a DIFFERENT row closes nothing here — whole-name match, never a
# substring, and never the whole roster.
plant_agent "$F_SUB" "aacked-5555555555555555" "acked-one-more"
sg_roster_row "$F_REPO" "$SID_A" "acked-one-more" "aacked-5555555555555555" "" "confirmed" \
  ".bionic/docs/record/never-written-2.md"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "acked-one-more")"
expect_status "a neighbouring ack does not discharge this row: REFUSED, it is working" 2 "$GUARD_ST"

# --- the VACUOUS MET keeps its ceremony ---
#
# `verdict` calls a row that declared no artifact MET, correctly — it names
# nothing to hold the agent to. That is not a landing, and treating it as one
# would discharge every contract-less dispatch on a fact nobody produced. AC-1
# says MET means "artifact delivered"; ack is what closes the rest.
plant_agent "$F_SUB" "anothing-6666666666666666" "declares-nothing"
sg_roster_row "$F_REPO" "$SID_A" "declares-nothing" "anothing-6666666666666666"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "declares-nothing")"
expect_status "a row that declared NOTHING is not discharged by its vacuous MET" 2 "$GUARD_ST"
# …and the paired positive, which is what keeps the row above from being "everything is
# refused": the same contract-less row, quiet, is stoppable.
age_log "$F_SUB" "anothing-6666666666666666"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "declares-nothing")"
expect_status "…and the same row, gone quiet: PERMITTED" 0 "$GUARD_ST"

# --- a repo-controlled ledger cannot open this gate ---
#
# The CLOSED half of the pair whose open half is at the landing gate
# (tests/landing-gate.test.sh §8f). A repo owns its own .bionic/, so a symlinked ledger is
# a set of acks nobody in this session recorded: the sweeper — the ONE reader of that file
# since S9 — refuses to answer over it at all, so no `acked=` reaches this gate, and this
# gate, which is CLOSED and loud after the active-wave verdict, refuses the stop even though
# the artifact is on disk. That last part is the point: the refusal costs a re-run, and the
# alternative was letting a repo choose which acks this session recorded. The same fixture
# passes at the landing gate,
# which is fail-open by design. Opposite directions, one fixture, both deliberate.
plant_agent "$F_SUB" "alinked-8888888888888888" "linked-ledger"
sg_roster_row "$F_REPO" "$SID_A" "linked-ledger" "alinked-8888888888888888" "" "confirmed" \
  ".bionic/docs/record/lander.md"
mkdir -p "$SANDBOX/elsewhere"
printf '# bionic sweeper ledger — schema sweeper-ledger/v1\nsweeper-ledger/v1|event=ack|at=2026-08-11T00:00:00Z|epoch=1|pid=1|session=%s|name=linked-ledger\n' \
  "$SID_A" > "$SANDBOX/elsewhere/ledger.state"
ln -sf "$SANDBOX/elsewhere/ledger.state" "$F_REPO/.bionic/tmp/sweeper-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "linked-ledger")"
rm -f "$F_REPO/.bionic/tmp/sweeper-$SID_A.state"

# --- no roster row at all: no standing, and since D8 (T5) that REFUSES ---
plant_agent "$F_SUB" "aunrostered-777777777777" "unrostered"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "unrostered")"
expect_status "a target on no roster row is unchanged by any of this: no standing (T22, D8)" 2 "$GUARD_ST"
expect_regex "…and the one line names the fault" 'no roster row of this session' "$GUARD_ERR"

# --- an ack for a name NO ROSTER ROW carries closes nothing here (epic-16 w2 S9) ---
#
# The one behavioural delta of S9's `acked=` promotion, pinned rather than left to be
# discovered. This gate used to open the ledger itself and match a bare name in it, so an
# ack recorded for a name the roster never carried discharged the stop. The ack now reaches
# it as a field on the verdict line for a ROW, and there is no row — so the ceremony stands.
#
# That is the ack verb's OWN semantics, which the gate had been the odd one out on: an ack
# for an unknown name is recorded with a warning and is "exempt the moment a row of that
# name appears" (session-sweeper.sh's ack verb, and tests/session-sweeper.test.sh §4). The
# landing gate has always passed such a stop for an unrelated reason (a name on no row makes
# the verb exit 0 and the gate fail open), and the stand-down never sees one, so this is the
# reading all three now share.
# RE-POINTED (T22), then RE-POINTED AGAIN (D8, T5): a name on no roster row has no standing
# here at all, so the ack cannot discharge anything because there is nothing to discharge —
# and since D8 "not this gate's" is a REFUSAL, not a wave-through. The ack-over-a-real-row
# case, which is the one the discharge rule is about, is above.
plant_agent "$F_SUB" "aackless-9999999999999999" "acked-but-rowless"
ack_row "$F_REPO" "$SID_A" "acked-but-rowless"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "acked-but-rowless")"
expect_status "an ack over a name no roster row carries reaches no discharge rule at all" 2 "$GUARD_ST"
expect_regex "…because the gate has no standing over it" 'no roster row of this session' "$GUARD_ERR"
# The paired positive is one case up: the SAME ack verb, over a name that HAS a row, passes
# the same gate silently ("ACKED row: the stop passes though the contract is UNMET").

section "Section 12: the USER-ORDERED stop executes, and reports (R3, AC-2)"
#
# A human order is not evidence and it is not a discharge of the contract: it is
# an INSTRUCTION, and the gate's job in front of one is to get out of the way and
# say what is being given up. Never a refusal — a wall that argues with the
# person it exists to serve has mistaken who it works for.

IFS='|' read -r O_REPO O_TR O_SUB <<< "$(make_world orders yes)"
mkdir -p "$O_REPO/.bionic/docs/record"
plant_agent "$O_SUB" "aordered-1111111111111111" "ordered"
sg_roster_row "$O_REPO" "$SID_A" "ordered" "aordered-1111111111111111" "" "confirmed" \
  ".bionic/docs/record/ordered.md"

# Precondition: without the order this is the ordinary live+unmet refusal.
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "ordered")"
expect_status "precondition — unmet and unordered: REFUSED" 2 "$GUARD_ST"

order_stop "$O_REPO" "$SID_A" "ordered"
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "ordered")"
expect_status "a user-ordered stop EXECUTES: permitted, no observation" 0 "$GUARD_ST"
expect_contains "…and the line says who ordered it" "STOP ORDERED (by human)" "$GUARD_ERR"

# WHO ORDERED IT IS PART OF THE REPORT (AC-1.1; T1, D1). An order means one of two things
# now — a human said stop, or a verified landing did (the Patrol writes one for a MET row
# whose agent is still on the panel, so the TaskStop it asks for is not refused a moment
# later). The gate's reading is unchanged: it discharges either. What changes is that the one
# line it prints back names the author, so a stop nobody remembers typing is explicable.
plant_agent "$O_SUB" "apatrolled-44444444444" "patrolled"
sg_roster_row "$O_REPO" "$SID_A" "patrolled" "apatrolled-44444444444" "" "confirmed" \
  ".bionic/docs/record/patrolled.md"
order_stop "$O_REPO" "$SID_A" "patrolled" --by patrol
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "patrolled")"
expect_status "a PATROL-ordered stop executes exactly as a human's does" 0 "$GUARD_ST"
expect_contains "…and the line says the Patrol ordered it" "STOP ORDERED (by patrol)" "$GUARD_ERR"
expect_contains "…and still says what is being given up" "giving up" "$GUARD_ERR"

# An order names ONE target. A stop of a different agent is not covered by it.
plant_agent "$O_SUB" "aunordered-22222222222" "unordered"
sg_roster_row "$O_REPO" "$SID_A" "unordered" "aunordered-22222222222" "" "confirmed" \
  ".bionic/docs/record/unordered.md"
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "unordered")"
expect_status "an order for another target discharges nothing here: REFUSED" 2 "$GUARD_ST"

# AN ORDER IS A LIVE INSTRUCTION, NOT A STANDING ONE. It is bounded in time on
# purpose — the one place in this gate where a clock is right, because what is
# being bounded is an instruction's currency and not evidence's freshness. An
# expired order leaves the ceremony exactly where it was.
plant_agent "$O_SUB" "astale-333333333333333" "stale-order"
sg_roster_row "$O_REPO" "$SID_A" "stale-order" "astale-333333333333333" "" "confirmed" \
  ".bionic/docs/record/stale-order.md"
order_stop "$O_REPO" "$SID_A" "stale-order" --at $(( $(date -u +%s) - 86400 ))
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "stale-order")"
expect_status "an EXPIRED order does not discharge: REFUSED" 2 "$GUARD_ST"

section "Section 12b: the order is read BEFORE roster standing (D14, REQ-6; AC-6.1/AC-6.2)"
#
# THE ESCAPE HATCH REACHES THE ONE TARGET ITS OWN REFUSAL NAMES. Every fixture in Section 12
# plants a roster row before ordering a stop, so order_current() — which used to run some
# 240 lines after the "no roster row of this session" deny — could never rescue the target
# that refusal actually names. This section is that fixture: a name this session's roster
# carries NO row for at all.

# Precondition — row-less and unordered: the ordinary refusal, unchanged (AC-6.2).
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "R5")"
expect_status "precondition — no row, no order: REFUSED" 2 "$GUARD_ST"
expect_regex "…and the one line names the fault" 'no roster row of this session' "$GUARD_ERR"

# The order is recorded through the shipped verb, over a name that carries no roster row —
# `stop-orders.sh order` never required one (it is only ever read, never gated on a row).
order_stop "$O_REPO" "$SID_A" "R5"
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "R5")"
expect_status "a row-less name with an order within its TTL: PERMITTED (AC-6.1)" 0 "$GUARD_ST"
expect_contains "…and the order is named on stderr" "STOP ORDERED (by human)" "$GUARD_ERR"
expect_contains "…the verdict degrades to the no-contract branch this early" \
  "No contract row of this name is on the session roster" "$GUARD_ERR"

# A DIFFERENT row-less name, never ordered, is still refused exactly as before (AC-6.2): the
# early order read changes nothing about the deny for a target that has none.
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "R5-unordered")"
expect_status "a different row-less name, never ordered: still REFUSED (AC-6.2)" 2 "$GUARD_ST"
expect_regex "…same fault" 'no roster row of this session' "$GUARD_ERR"

section "Section 13: name@session-<launcher> is an ALIAS, checked against that roster (AC-11)"
#
# The suffix is the spelling the platform's stop primitive takes for a teammate, and it is
# the one an operator can actually type (field data 2026-08-11). It is NOT a second way to
# resolve: D2′ keeps it only as an alias that must land on the same single live entry the
# bare name lands on. What the suffix is checked against is the named LAUNCHER's roster —
# `roster-<sid>*.state` carrying `|name=<base>|` — because a suffix naming a session that
# never launched anything of that name is a guess wearing an id's shape.

IFS='|' read -r AL_REPO AL_TR AL_SUB <<< "$(make_world aliasform yes)"
plant_agent "$AL_SUB" "aroamer-1111111111111111" "roamer"
# The LAUNCHER's roster — another session's file, in this repo's own state directory.
sg_roster_row "$AL_REPO" "$SID_B" "roamer" "aroamer-1111111111111111" "" "identified"
# Ours is what carries the id and the contract for the row we answer for.
sg_roster_row "$AL_REPO" "$SID_A" "roamer" "aroamer-1111111111111111" "" "identified"

# The BARE NAME resolves — that is the B-2 fix, and it is the ordinary path. The target is
# quiet, which is what makes every PERMITTED row in this section about the ADDRESS rather
# than about the agent's state.
age_log "$AL_SUB" "aroamer-1111111111111111"
run_guard "$(mk_stop_payload "$SID_A" "$AL_TR" "$AL_REPO" "roamer")"
expect_status "the bare name of a single live entry: PERMITTED" 0 "$GUARD_ST"

# The ALIAS resolves to the same entry, and says nothing about whether the stop is allowed.
run_guard "$(mk_stop_payload "$SID_A" "$AL_TR" "$AL_REPO" "roamer@session-${SID_B:0:8}")"
expect_status "the alias whose launcher roster carries the base name: PERMITTED" 0 "$GUARD_ST"
expect_contains "…with the same look the bare name got" "STOP PERMITTED" "$GUARD_ERR"

# A suffix naming a launcher whose roster does NOT carry the name is refused — and the
# refusal prints the spellings this gate does accept, which is the one spelling
# hooks/stop-check.sh prints for a candidate and `session-poker.sh adopt` prints for an
# adopted row (cross-gate Section R).
run_guard "$(mk_stop_payload "$SID_A" "$AL_TR" "$AL_REPO" "roamer@session-deadbeef")"
expect_status "an alias naming a launcher with no such row: REFUSED" 2 "$GUARD_ST"
expect_contains "…and the refusal says the launcher's roster does not carry the name" \
  "does not carry" "$GUARD_VERR"
expect_contains "…and prints an accepted spelling" "roamer@session-${SID_B:0:8}" "$GUARD_VERR"
expect_contains "…including this session's own" "roamer@session-${SID_A:0:8}" "$GUARD_VERR"

# The refusal above changed nothing on disk — this gate spends no evidence and writes no
# state — so the very next well-spelled stop is answered on the target's own facts.
run_guard "$(mk_stop_payload "$SID_A" "$AL_TR" "$AL_REPO" "roamer@session-${SID_A:0:8}")"
expect_status "the alias naming THIS session, whose roster carries the name: PERMITTED" 0 "$GUARD_ST"

section "Section 14: an ADOPTED agent is stoppable BY BARE NAME (the /clear defect, B-2)"
#
# THE DEFECT, from the field (epic-20 W1, 2026-08-30; re-diagnosed for this wave as B-2).
# After a `/clear`+resume the agents a predecessor launched are still running — the same
# processes, still listed as this session's teammates by the harness — but their metadata is
# filed under the PREDECESSOR's directory, and one of them had its meta.json in two
# directories at once. Resolution walked directories, so a bare name was either unresolved
# or ambiguous, and the operator could not stop a finished, verified agent at all.
#
# With resolution taken from the live set the bare name simply works. What the roster row
# still supplies is the id and the session the working log is filed under (`adopted_from`),
# which no scan is needed to learn.

IFS='|' read -r AD_REPO AD_TR AD_SUB <<< "$(make_world adoptstop yes)"
AD_TR_B="${AD_TR%/*}/$SID_B.jsonl"
AD_SUB_B="${AD_TR_B%.jsonl}/subagents"

# The agent is filed under the PREDECESSOR ($SID_B) and named in the SUCCESSOR's live set.
plant_agent "$AD_SUB_B" "aadoptee-1111111111111111" "adoptee"
plant_live "$AD_TR" fresh "adoptee"
sg_roster_row "$AD_REPO" "$SID_A" "adoptee" "aadoptee-1111111111111111" "" "identified" "" "" \
  "adoptee@session-${SID_B:0:8}" "$SID_B"

# THE LOG IS THE PREDECESSOR'S, and aging it is how this section says the agent has gone
# quiet — which also proves the look followed `adopted_from` to the right directory.
age_log "$AD_SUB_B" "aadoptee-1111111111111111"
run_guard "$(mk_stop_payload "$SID_A" "$AD_TR" "$AD_REPO" "adoptee")"
expect_status "a quiet ADOPTED agent is stoppable BY BARE NAME after a /clear" 0 "$GUARD_ST"
expect_contains "…and the look names the log under the session that launched it" \
  "$SID_B" "$GUARD_ERR"

# The address `adopt` prints for the same row resolves as well, through the recorded
# teammate address on the row itself.
run_guard "$(mk_stop_payload "$SID_A" "$AD_TR" "$AD_REPO" "adoptee@session-${SID_B:0:8}")"
expect_status "…and so does the address adopt prints for it" 0 "$GUARD_ST"

# THE GUARD IS UNCHANGED FOR A WORKING AGENT: a second adopted agent, still writing to the
# log filed under its launcher, is refused — and for its own liveness, which is the half a
# status assertion alone cannot tell from the defect.
plant_agent "$AD_SUB_B" "aadoptee-2222222222222222" "adoptee2"
plant_live "$AD_TR" fresh "adoptee" "adoptee2"
sg_roster_row "$AD_REPO" "$SID_A" "adoptee2" "aadoptee-2222222222222222" "" "identified" "" "" \
  "adoptee2@session-${SID_B:0:8}" "$SID_B"
run_guard "$(mk_stop_payload "$SID_A" "$AD_TR" "$AD_REPO" "adoptee2")"
expect_status "a WORKING adopted agent is still refused" 2 "$GUARD_ST"
expect_contains "…and the refusal is its liveness, not an unresolved address" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"

# THE DISCRIMINATOR. An agent sitting in the predecessor's directory that this session's
# live set does not name stays invisible — the scope is the harness's statement, not the
# disk, so no widening by directory can creep back in.
plant_agent "$AD_SUB_B" "astranger-4444444444444444" "stranger"
plant_live "$AD_TR" fresh "adoptee" "adoptee2"
sg_roster_row "$AD_REPO" "$SID_A" "stranger" "astranger-4444444444444444" "" "identified"
# RE-POINTED (T22): the scope is THIS SESSION'S ROSTER, not the harness's answer. `stranger`
# has a row here but NOT on the roster of the session its alias names, so the alias rule —
# which has always been a roster reading — is what refuses it. Closed side either way; what
# changed is that the reason is now a fact about the register instead of about a transcript.
run_guard "$(mk_stop_payload "$SID_A" "$AD_TR" "$AD_REPO" "stranger@session-${SID_B:0:8}")"
expect_status "an alias whose named session's roster never carried it: REFUSED" 2 "$GUARD_ST"
expect_contains "…for the alias, which the roster answers" "is not an accepted alias" "$GUARD_VERR"
expect_absent "…and never for a liveness reading" "not live" "$GUARD_VERR"

section "Section 15: the transcript's freshness is not a precondition of a stop (T22, AC-4.4)"
#
# WHAT THIS SECTION USED TO BE. The live set was only a statement about NOW if it was
# recorded this turn, so a STALE or absent ListAgents answer refused the whole stop and told
# the model to go call the tool. That is a chore demanded before a gate will judge a
# different act — ADR-024's P-A, the rule this wave finishes — and Chris's ruling
# (2026-09-14, A-orch-33) is that the live set is IMMATERIAL to stopping: the two things the
# gate ever used it for were resolving a bare name to an id and refusing ambiguity, and the
# roster answers both.
#
# WHAT IT IS NOW. The same four transcript states, driven against the same roster, all
# PERMITTED. Freshness moved out of the resolution entirely; what decides the stop is what is
# TRUE of the target, and the target here is quiet throughout, so the transcript is the only
# variable in the section. Three of these four rows are the whole RED of that change: a gate
# that still read the answer's state fails them and passes the first.

IFS='|' read -r FR_REPO FR_TR FR_SUB <<< "$(make_world freshness yes)"
plant_agent "$FR_SUB" "aworker-1111111111111111" "worker"
sg_roster_row "$FR_REPO" "$SID_A" "worker" "aworker-1111111111111111"
age_log "$FR_SUB" "aworker-1111111111111111"

# FRESH — the positive this section's negatives are measured against.
run_guard "$(mk_stop_payload "$SID_A" "$FR_TR" "$FR_REPO" "worker")"
expect_status "a fresh answer naming the target: PERMITTED" 0 "$GUARD_ST"

# STALE — the same world, the same answer, one more user prompt after it.
plant_live "$FR_TR" stale "worker"
run_guard "$(mk_stop_payload "$SID_A" "$FR_TR" "$FR_REPO" "worker")"
expect_status "a STALE answer does not stand between a roster row and its stop" 0 "$GUARD_ST"
expect_absent "…and nothing asks for a ListAgents call" "ListAgents" "$GUARD_ERR"

# NONE — no ListAgents answer in the transcript at all. This is the FIRST stop of every
# session, and it used to be refused.
: > "$FR_TR"
run_guard "$(mk_stop_payload "$SID_A" "$FR_TR" "$FR_REPO" "worker")"
expect_status "a transcript with no answer at all does not stand in the way either" 0 "$GUARD_ST"
expect_absent "…and names no tool call" "ListAgents" "$GUARD_ERR"

# A GARBLED newest answer is `none`, never "all gone" (S4 §F): the reader recognises no
# section marker, so the gate refuses rather than reading an empty roster out of it.
plant_live "$FR_TR" fresh "worker"
# THE GARBLE IS APPLIED TO THE HEADER THE BUILDER JUST WROTE, taken back off the corpus
# rather than re-typed here (S17): a mutation arm that spells its own target is green the
# day the target changes shape, because it damages a line the fixture no longer contains.
FR_HDR="$(live_answer_block_header 1)"
sed -i.bak "s/${FR_HDR}/Tea mates (1):/; s/This session is /Thus session is /" "$FR_TR"
rm -f "$FR_TR.bak"
run_guard "$(mk_stop_payload "$SID_A" "$FR_TR" "$FR_REPO" "worker")"
expect_status "a garbled answer is not read at all, so it cannot refuse a stop" 0 "$GUARD_ST"
expect_absent "…and nothing on the user stream mentions the panel" "ListAgents" "$GUARD_ERR"

# The paired positive: the fixture is not simply broken — the restored answer changes
# nothing, which is exactly the claim ("immaterial to stopping").
plant_live "$FR_TR" fresh "worker"
run_guard "$(mk_stop_payload "$SID_A" "$FR_TR" "$FR_REPO" "worker")"
expect_status "…and with the answer restored the same stop is PERMITTED, unchanged" 0 "$GUARD_ST"

section "Section 16: an IDLE agent is exactly the one you stop (spec R2, AC-27; S16)"
#
# S16 splits the two questions the live set is asked. The DISPATCH BUDGET stops counting a
# row once its agent reads `idle` — a teammate that finished its turn and was never stopped
# is not a writer, and holding a slot for it is B-1's stuck slot in a new coat. THE STOP
# GUARD must not follow it there. It resolves on PRESENCE, and an idle agent is precisely
# the target a stop exists for: the harness still lists it because it is still addressable,
# and somebody has to close it. A guard that read the budget's rule would refuse to stop
# the very agents the budget just stopped counting, and the finished agent would be
# unstoppable AND uncounted.
#
# One positive, one control. Both drive the shipped guard end to end, by bare name.

IFS='|' read -r I_REPO I_TR I_SUB <<< "$(make_world idlestop yes)"
mkdir -p "$I_REPO/.bionic/docs/record"

plant_agent "$I_SUB" "aidle-7777777777777777" "finished-writer"
echo "the delivered artifact" > "$I_REPO/.bionic/docs/record/finished-writer.md"
sg_roster_row "$I_REPO" "$SID_A" "finished-writer" "aidle-7777777777777777" "" "confirmed" \
  ".bionic/docs/record/finished-writer.md"

# The answer now names it IDLE — plant_agent wrote it running, which is the control below.
plant_live "$I_TR" fresh "finished-writer:idle"
expect_contains "meta: the planted answer really does say idle, not running" \
  "finished-writer [8895ce]  ·  bionic:senior-implementor  ·  idle" "$(cat "$I_TR")"

run_guard "$(mk_stop_payload "$SID_A" "$I_TR" "$I_REPO" "finished-writer")"
expect_status "an IDLE agent with a MET contract is still stoppable BY BARE NAME" 0 "$GUARD_ST"
expect_empty "…and silently, exactly as the running case does" "$GUARD_ERR"

# THE CONTROL, on the same world and the same name: running instead of idle. If this
# differed, the row above would be reporting the status and not the resolution.
plant_live "$I_TR" fresh "finished-writer"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR" "$I_REPO" "finished-writer")"
expect_status "…the same stop with the same name RUNNING also passes (status is not the gate)" \
  0 "$GUARD_ST"

# RE-POINTED (T22). "Absent from the newest answer" is no longer a fact this gate consults:
# the roster resolves the name and the MET contract discharges the stop, whatever the panel
# happens to say. The vacuity guard the old row provided is carried by `idle-slacker` below,
# whose UNMET contract refuses on the same roster.
plant_live "$I_TR" fresh "somebody-else"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR" "$I_REPO" "finished-writer")"
expect_status "…and a name ABSENT from the newest answer stops exactly the same way" \
  0 "$GUARD_ST"

# AN IDLE AGENT WITH AN UNMET CONTRACT IS STOPPABLE, and since epic-23 wave-15 that is the
# rule rather than an exception to it (REQ-2). It used to keep the whole ceremony: an
# observation, a staleness round and a second stop, for an agent that had stopped writing.
# What this gate refuses now is the one state it can see a reason to refuse — still working,
# nothing delivered — and "finished empty-handed" is not that state. The contract is still
# unmet and the landing gate still says so; this gate is not what answers for it.
plant_agent "$I_SUB" "aidle-8888888888888888" "idle-slacker"
sg_roster_row "$I_REPO" "$SID_A" "idle-slacker" "aidle-8888888888888888" "" "confirmed" \
  ".bionic/docs/record/never-delivered.md"
plant_live "$I_TR" fresh "idle-slacker:idle"
age_log "$I_SUB" "aidle-8888888888888888"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR" "$I_REPO" "idle-slacker")"
expect_status "an IDLE agent with an UNMET contract: PERMITTED — it is the one you stop" \
  0 "$GUARD_ST"
expect_contains "…and the look says what is being given up" "deliverable pending" "$GUARD_ERR"

# THE CONTROL, and the discrimination this section rests on: the SAME row, the SAME unmet
# contract, one fact changed — the agent is writing again. A gate that had simply stopped
# deciding passes the row above and fails this one.
wake_log "$I_SUB" "aidle-8888888888888888"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR" "$I_REPO" "idle-slacker")"
expect_status "…while the same agent WRITING with the same unmet contract: REFUSED" 2 "$GUARD_ST"
expect_contains "…naming what it observed, not a missing record" \
  "is ALIVE and its contract is undelivered" "$GUARD_VERR"

section "Section T22: the roster is the identity register (AC-4.4, A-orch-33)"
#
# The whole of resolution, in three rows and their controls. A NAME is resolved against THIS
# session's roster — the recorder's `identified`/`confirmed` rows, and the rows `adopt`
# journalled for a predecessor's agents. One row resolves it. No row on any roster of this
# session, and no agent-address shape, means the target is not this gate's to guard and the
# stop proceeds untouched.
#
# NOTHING HERE READS A TRANSCRIPT ANSWER. Every world below is driven with the transcript in
# whatever state it happens to be; the assertions never plant one, and the sweep at the end
# of this suite proves no refusal anywhere in it names a ListAgents call.

IFS='|' read -r T22_REPO T22_TR T22_SUB <<< "$(make_world t22register yes)"
mkdir -p "$T22_REPO/.bionic/docs/record"

# (1) ONE ROW RESOLVES IT — and a MET contract discharges the stop with no observation and
# no panel reading at all.
plant_agent "$T22_SUB" "aregistered-1010101010101010" "registered"
echo "the delivered artifact" > "$T22_REPO/.bionic/docs/record/registered.md"
sg_roster_row "$T22_REPO" "$SID_A" "registered" "aregistered-1010101010101010" "" "identified" \
  ".bionic/docs/record/registered.md"
run_guard "$(mk_stop_payload "$SID_A" "$T22_TR" "$T22_REPO" "registered")"
expect_status "T22-1 a name with one identified row and a MET contract: PERMITTED" 0 "$GUARD_ST"
expect_empty "…silently" "$GUARD_ERR"

# (2) NO ROW ON ANY ROSTER OF THIS SESSION, no agent-address shape, and (D8, T5) no
# bash-task-id shape either ("bash-task-42" carries a hyphen and a leading "b" — neither
# `is_address_shaped` nor `is_bash_task_shaped` accepts it): NOT OURS, and since D8 that is a
# REFUSAL, named in one line rather than waved through.
run_guard "$(mk_stop_payload "$SID_A" "$T22_TR" "$T22_REPO" "bash-task-42")"
expect_status "T22-2 a target on no roster of this session is not ours: REFUSED (D8, T5)" \
  2 "$GUARD_ST"
expect_contains "…and says so, naming the fact rather than passing in silence" "no roster row of this session" "$GUARD_ERR"

# (3) AN `intended` ROW IS NOT AN IDENTITY. Its id is a claim about a launch nothing has
# observed, so it resolves no id and the refusal names the missing fact (Step-6 review C-2,
# unchanged by this task — the status filter is the one thing resolution always keyed on).
sg_roster_row "$T22_REPO" "$SID_A" "claimed" "aclaimed-2020202020202020" "" "intended" \
  ".bionic/docs/record/claimed.md"
run_guard "$(mk_stop_payload "$SID_A" "$T22_TR" "$T22_REPO" "claimed")"
expect_status "T22-3 an intended row resolves no id: REFUSED" 2 "$GUARD_ST"
expect_contains "…naming the register's own gap" "no agent id" "$GUARD_VERR"

# (4) THE TRANSCRIPT IS IRRELEVANT, PROVEN BY SUBSTITUTION. The same target, the same
# roster, the same contract — driven once with no transcript file at all and once with a
# fresh answer that does not name it. Both behave identically, which is what "immaterial to
# stopping" means as a testable claim.
echo "the delivered artifact" > "$T22_REPO/.bionic/docs/record/registered2.md"
plant_agent "$T22_SUB" "aregistered2-3030303030303030" "registered2"
sg_roster_row "$T22_REPO" "$SID_A" "registered2" "aregistered2-3030303030303030" "" "confirmed" \
  ".bionic/docs/record/registered2.md"
: > "$T22_TR"
run_guard "$(mk_stop_payload "$SID_A" "$T22_TR" "$T22_REPO" "registered2")"
expect_status "T22-4a an empty transcript: PERMITTED" 0 "$GUARD_ST"
plant_live "$T22_TR" fresh "somebody-else"
run_guard "$(mk_stop_payload "$SID_A" "$T22_TR" "$T22_REPO" "registered2")"
expect_status "T22-4b an answer naming somebody else: PERMITTED, identically" 0 "$GUARD_ST"

# (5) THE SOURCE ITSELF. AC-4.4's grep, over the one file this section is about.
expect_eq "T22-5 hooks/stop-guard.sh instructs no ListAgents call anywhere" \
  "0" "$(grep -c 'call ListAgents' "$GUARD")"

section "AC-E1.3/E1.5 — every refusal this gate makes is one line, in the shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`.
#
# WHY A SWEEP AND NOT ONE ROW PER SITE. All twenty-two of this gate's refusals go
# through one frame (`deny`), and the sweep below re-drives EVERY refusal this suite
# already sets up: `run_guard` is wrapped so that each refusing call is checked, so the
# arms are as many as the suite has refusals and no site can be migrated without one.
# The three rows the ruled table puts at exactly 100 columns (draft F-9) are among them,
# which is the reason the check is on columns and not on bytes.

SG_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"

SG_SEEN=0; SG_BAD_SHAPE=""; SG_BAD_LINES=""; SG_BAD_COLS=""; SG_FACTS=""
sg_check() {  # <stderr> — called for every refusing run_guard below
  local err="$1" n cols
  n="$(printf '%s\n' "$err" | wc -l | tr -d ' ')"
  cols="$(bionic_cols "$err")"
  SG_SEEN=$((SG_SEEN + 1))
  printf '%s' "$err" | /usr/bin/grep -qE "$SG_RE" || SG_BAD_SHAPE="${SG_BAD_SHAPE}[$err] "
  [ "$n" = "1" ] || SG_BAD_LINES="${SG_BAD_LINES}[$err] "
  [ "${cols:-999}" -le 100 ] || SG_BAD_COLS="${SG_BAD_COLS}[$cols: $err] "
  SG_FACTS="${SG_FACTS}${err}
"
}

# Re-drive the refusals this suite already builds worlds for, through the same driver.
sg_sweep() {  # <payload>
  run_guard "$1"
  [ "$GUARD_ST" = "2" ] && sg_check "$GUARD_ERR"
  return 0
}

sg_sweep "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "blocked")"
sg_sweep "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "")"
sg_sweep "$(mk_stop_payload "$SID_A" "$S_TR" "$S_REPO" "victim")"
sg_sweep "$(mk_stop_payload "$SID_A" "$S2_TR" "$S2_REPO" "victim")"
sg_sweep "$(mk_stop_payload "$SID_A" "$TW_TR" "$TW_REPO" "twin")"
sg_sweep "$(jq -n --arg c "$R2_REPO" --arg t "$R2_TR" \
  '{cwd:$c, transcript_path:$t, hook_event_name:"PreToolUse", tool_name:"TaskStop",
    tool_input:{task_id:"blocked"}}')"

expect_eq "E1.3 the sweep drove real refusals (not counting over air)" "yes" \
  "$([ "$SG_SEEN" -ge 4 ] && echo yes || echo no)"
expect_eq "E1.3 every refusal matched the criterion's shape" "" "$SG_BAD_SHAPE"
expect_eq "E1.3 every refusal was exactly one line" "" "$SG_BAD_LINES"
expect_eq "E1.3 every refusal fitted the 100-column budget" "" "$SG_BAD_COLS"
expect_contains "E1.3 …and the facts are this gate's own, from the ruled table" \
  "bionic: stop refused — " "$SG_FACTS"

# THE TABLE'S EXACT WORDING at three sites, one per shape of reason: a missing target,
# a symlinked state path, an ambiguous name.
run_guard "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "")"
expect_eq "E1.3 row 15 (no target) is the table's line" \
  "bionic: stop refused — this stop names no target (name the agent to stop)" "$GUARD_ERR"
# ROW 18 MOVED WITH THE FILE IT NAMED (epic-23 wave-15). The ruled table's symlink line was
# about the observation record's own path; the record is gone and the level this gate still
# declines to read through is the state DIRECTORY, so the row is driven against that world.
run_guard "$(mk_stop_payload "$SID_A" "$S2_TR" "$S2_REPO" "victim")"
expect_eq "E1.3 row 18 (a symlinked state directory) is the table's line" \
  "bionic: stop refused — the state directory is a symlink (remove that symlink)" "$GUARD_ERR"
# ROW 20 IS RETIRED WITH ITS ARM (T22). The ruled table's ambiguous-name line had exactly
# one site and that site is gone; the third shape of reason is now the roster's own — a
# target this session's register carries no id for.
run_guard "$(mk_stop_payload "$SID_A" "$T22_TR" "$T22_REPO" "claimed")"
expect_eq "E1.3 the third shape (no id on the register) is the table's line" \
  "bionic: stop refused — the session roster carries no id for it (stop it yourself or order it)" \
  "$GUARD_ERR"

# AC-E1.5, the pair: the frame's twelve lines are off the user stream and on the knob.
expect_absent "E1.5 the pasteable observe command is NOT on the user stream" \
  "Fix: " "$GUARD_ERR"
expect_contains "E1.5 …and BIONIC_WALL_VERBOSE=1 puts it back" "Fix: " "$GUARD_VERR"
expect_contains "E1.5 …along with the human-order route the frame teaches" \
  "If a human ordered this stop" "$GUARD_VERR"
expect_eq "E1.5 …with the one line still first" \
  "bionic: stop refused — the session roster carries no id for it (stop it yourself or order it)" \
  "$(printf '%s\n' "$GUARD_VERR" | head -1)"

finish
