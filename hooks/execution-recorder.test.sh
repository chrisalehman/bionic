#!/bin/bash
# Tests for hooks/execution-recorder.sh — ONE script, TWO arms (epic-15 wave-03,
# slice 4/4).
#
#   PostToolUse|Bash  — the OBSERVATION arm. Turns hooks/stop-check.sh's printed
#                       machine line into the record a stop spends. Never blocks.
#   PostToolUse|Agent — the ROSTER arm. Completes the `intended` row a dispatch
#                       wrote at launch with the spawned agent's full id.
#
# Serves AC-3 (an observation exists only if one ran, and carries the observer)
# and AC-1's confirmation half.
#
# HERMETIC. Every payload is crafted and piped straight into the script under
# test; nothing here invokes a tool, touches the installed hooks under
# ~/.claude/hooks/, or writes outside a mktemp'd sandbox. The observation arm is
# driven with the REAL producer's REAL stdout — hooks/stop-check.sh is executed
# against the fixture world and its output becomes the payload — because the
# whole thesis of this slice is that one program's output is the other's input,
# and a synthesized machine line would test the two halves apart.
#
# Usage: bash hooks/execution-recorder.test.sh

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REC="$HERE/execution-recorder.sh"
OBSERVE="$HERE/stop-check.sh"
PASS=0
FAIL=0
TOTAL=0

# `cd … && pwd` normalizes the path: $TMPDIR carries a trailing slash on macOS,
# and a doubled separator would slugify differently from the cwd the scripts
# under test actually see.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-recorder-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------- assertions ----------

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_matches()  { if printf '%s' "$3" | grep -qE -- "$2"; then ok "$1"; else no "$1" "no match: $2"; fi; }
expect_absent()   { if printf '%s' "$3" | grep -qF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
expect_file()     { if [ -f "$2" ]; then ok "$1"; else no "$1" "no such file: $2"; fi; }
expect_no_file()  { if [ -f "$2" ]; then no "$1" "file exists but should not: $2"; else ok "$1"; fi; }

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design).
#
# Source: .bionic/docs/record/w3-slice1-posttooluse-probe.md §2, the verbatim
# PostToolUse payloads captured live on CLI 2.1.222 for this slice. Every payload
# builder below DERIVES from those captures:
#
#   * PostToolUse|Bash, orchestrator-invoked — FAITHFUL to capture A, field for
#     field: session_id, transcript_path, cwd, prompt_id, permission_mode,
#     effort, hook_event_name, tool_name, tool_input.command, tool_response
#     {stdout, stderr, interrupted, isImage, noOutputExpected}, tool_use_id,
#     duration_ms. Critically, capture A carries NO top-level agent_id — the
#     property the observer field depends on.
#   * PostToolUse|Bash, subagent-invoked — FAITHFUL to capture B/F: the same
#     field set PLUS top-level `agent_id` and `agent_type`. Captures B (foreground
#     subagent) and F (background subagent) are identical in this respect, and §3
#     records the computed diff: those two keys are the ONLY difference between
#     an orchestrator-invoked and a subagent-invoked payload.
#   * PostToolUse|Agent — FAITHFUL to capture E (the background dispatch this
#     repo actually uses): tool_input {description, prompt, subagent_type,
#     run_in_background, name} and tool_response {isAsync, status, agentId,
#     description, resolvedModel, prompt, outputFile, canReadOutputFile}, plus
#     tool_use_id. Capture D (synchronous) differs only in the response shape and
#     is exercised by the `status: completed` row below.
#   * transcript_path → session directory — FAITHFUL to §2.5 of
#     record/epic-15-kill-interception-experiment.md, which captures
#     `agent_transcript_path` as "<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl".
#   * meta.json — FAITHFUL to that record's §2.8 field set.
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, repo contents,
#     stdout bodies in the forgery rows. None is a platform surface.
#
# The stdout of a REAL observation is never synthesized here: the machine line
# under test is produced by running hooks/stop-check.sh itself.

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="11111111-2222-3333-4444-555555555555"
SUB_AGENT_ID="a6bc0caf11962bbb6"

mk_bash_post() {  # <sid> <transcript> <cwd> <command> <stdout> [invoker-agent-id]
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg cmd "$4" --arg out "$5" --arg ag "${6:-}" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"598cabc5-2776-479c-abcf-52c540a1c60e",
      permission_mode:"bypassPermissions"}
     + (if $ag == "" then {} else {agent_id:$ag, agent_type:"general-purpose"} end)
     + {effort:{level:"high"},
        hook_event_name:"PostToolUse", tool_name:"Bash",
        tool_input:{command:$cmd, description:"observe"},
        tool_response:{stdout:$out, stderr:"", interrupted:false,
                       isImage:false, noOutputExpected:false},
        tool_use_id:"toolu_01HQV9JAFdKC15TLMDKt2QgF", duration_ms:117}'
}

mk_agent_post() {  # <sid> <transcript> <cwd> <name> <agentId> <tool_use_id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg n "$4" --arg a "$5" --arg u "$6" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"33f36a9c-ad3b-4bb4-afbd-325a18e62a9e",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go",
                  subagent_type:"implementor", run_in_background:true, name:$n},
      tool_response:{isAsync:true, status:"async_launched", agentId:$a,
                     description:"a dispatch", resolvedModel:"claude-sonnet-5",
                     prompt:"go", outputFile:"/tmp/tasks/\($a).output",
                     canReadOutputFile:true},
      tool_use_id:$u, duration_ms:6}'
}

REC_OUT=""; REC_ERR=""; REC_ST=0
run_rec() {  # <payload-json>
  REC_OUT=$(printf '%s' "$1" | bash "$REC" 2>"$SANDBOX/.err"); REC_ST=$?
  REC_ERR=$(cat "$SANDBOX/.err")
  return 0
}

# make_world <name> <active-wave:yes|no> — echoes "<repo>|<transcript>|<subagents>|<config-dir>"
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
    mkdir -p "$repo/.bionic/docs/plans/epic-99-test"
    cat > "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 13
intent: build
rigor: audited
scale: wave
---

# Test wave plan

## SDLC State

integration-branch: main
current: 4

- Step 4: slices in flight
PLAN
  fi
  printf '%s|%s|%s|%s\n' "$repo" "$proj/$SID_A.jsonl" "$proj/$SID_A/subagents" "$home/.claude"
}

# plant_agent <subagents-dir> <agent-id> <name>
plant_agent() {
  local dir="$1" aid="$2" aname="$3"
  printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0,"model":"opus","taskKind":"in_process_teammate"}\n' \
    "$aname" > "$dir/agent-$aid.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$dir/agent-$aid.jsonl"
  return 0
}

STATE_REL=".bionic/tmp/stop-check.state"

# THE REAL PRODUCER, RUN FOR REAL. Its stdout — whatever it is, including nothing
# machine-readable at all — becomes the tool_response the recorder reads.
# CLAUDE_CONFIG_DIR is what hooks/stop-check.sh resolves its metadata root
# through, so the fixture world is reachable without touching $HOME.
OBS_OUT=""; OBS_ST=0
run_observation() {  # <config-dir> <repo> <args…>
  local cfg="$1" repo="$2"; shift 2
  # CLAUDE_CODE_SESSION_ID pinned empty: since slice 4/5 the real stop-check.sh
  # reads it to classify the target against ITS OWN session's roster, and this
  # suite runs inside a real Claude Code session that exports a real one. Left
  # unpinned, the observation's output — and so the record this arm's assertions
  # inspect — would silently vary with whichever session happens to run the
  # suite (none of this file's fixtures set up a roster, so the intended,
  # always-reachable answer is UNKNOWN, not a leaked ambient session).
  OBS_OUT=$(cd "$repo" && CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID= \
    bash "$OBSERVE" "$@" 2>/dev/null); OBS_ST=$?
  return 0
}

# observe <sid> <cfg> <repo> <transcript> <args…> — producer then recorder, end to end
observe() {
  local sid="$1" cfg="$2" repo="$3" tr="$4"; shift 4
  run_observation "$cfg" "$repo" "$@"
  run_rec "$(mk_bash_post "$sid" "$tr" "$repo" "bash ~/.claude/hooks/stop-check.sh $*" "$OBS_OUT")"
}

# ============================================================
echo ""
echo "=== Section 1: the hot path — relevance before any plan walk (checklist A7) ==="
# ============================================================

IFS='|' read -r W1_REPO W1_TR W1_SUB W1_CFG <<< "$(make_world w1 yes)"
plant_agent "$W1_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"

run_rec "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PostToolUse", tool_name:"Read", tool_input:{file_path:"/tmp/x"}, tool_response:{}}')"
expect_status "an unrelated TOOL passes untouched" 0 "$REC_ST"
expect_no_file "an unrelated tool writes no state" "$W1_REPO/$STATE_REL"

run_rec "$(mk_bash_post "$SID_A" "$W1_TR" "$W1_REPO" "ls -la && git status" "README.md")"
expect_status "a Bash call with no machine line in its output passes untouched" 0 "$REC_ST"
expect_no_file "a Bash call with no machine line writes no state" "$W1_REPO/$STATE_REL"

# Static order pin: the cheap relevance test must PRECEDE the plan-directory walk
# in the source, not merely produce the same answer (arch-perf F8/F9 — the defect
# was cost, which behaviour alone cannot detect). This script is registered on
# every Bash call in the session, so the walk on the unrelated path is the whole
# cost.
_rel_line=$(grep -n 'MLINES=' "$REC" | head -1 | cut -d: -f1)
_walk_line=$(grep -nE '^[[:space:]]*(PLAN=|for d in "\$DOCS_ROOT)' "$REC" | head -1 | cut -d: -f1)
if [ -n "$_rel_line" ] && [ -n "$_walk_line" ] && [ "$_rel_line" -lt "$_walk_line" ]; then
  ok "relevance check precedes the plan walk in source order"
else
  no "relevance check precedes the plan walk in source order" "relevance@${_rel_line:-none} walk@${_walk_line:-none}"
fi

# Outside an active wave the script is inert, like every other gate in this
# family (spec §Component boundaries: "Inert when no wave is active").
IFS='|' read -r NW_REPO NW_TR NW_SUB NW_CFG <<< "$(make_world nowave no)"
plant_agent "$NW_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
observe "$SID_A" "$NW_CFG" "$NW_REPO" "$NW_TR" quiet-reviewer
expect_status "no active wave: the recorder is inert" 0 "$REC_ST"
expect_no_file "no active wave: nothing is recorded" "$NW_REPO/$STATE_REL"

# ============================================================
echo ""
echo "=== Section 2: a run that produced evidence is recorded (AC-3, positive) ==="
# ============================================================

observe "$SID_A" "$W1_CFG" "$W1_REPO" "$W1_TR" quiet-reviewer
expect_status "recording an observation never blocks" 0 "$REC_ST"
expect_eq "the producer succeeded, so a machine line existed" "0" "$OBS_ST"
expect_file "an observation run writes state" "$W1_REPO/$STATE_REL"
STATE=$(cat "$W1_REPO/$STATE_REL" 2>/dev/null)
expect_contains "the record names the RESOLVED target" "aquiet-reviewer-deadbeefdeadbeef" "$STATE"
expect_contains "the record names the observing session" "$SID_A" "$STATE"
expect_contains "the record names the target AS TYPED" "typed=quiet-reviewer" "$STATE"
expect_matches "the record carries the activity level seen (log mtime)" 'mtime=[0-9]+' "$STATE"
expect_matches "the record carries the activity level seen (log size)" 'size=[0-9]+' "$STATE"

# THE FILE FACTS ARE THE PRODUCER'S, NOT A SECOND COMPUTATION. What the operator
# read as the working log's size is the number stored, because there is only one
# reader of that file now (the F-1 divergence class has no second parser left to
# diverge).
OBS_SIZE=$(printf '%s' "$OBS_OUT" | grep -E '^  size:' | grep -oE '[0-9]+' | head -1)
REC_SIZE=$(printf '%s' "$STATE" | grep -F 'target=aquiet-reviewer-deadbeefdeadbeef' \
  | tr '|' '\n' | grep '^size=' | cut -d= -f2)
expect_eq "the size the observation PRINTED is the size the recorder STORED" "$OBS_SIZE" "$REC_SIZE"

# Two chained runs in one Bash call print two machine lines and record two
# observations.
IFS='|' read -r W2_REPO W2_TR W2_SUB W2_CFG <<< "$(make_world w2 yes)"
plant_agent "$W2_SUB" "aone-1111111111111111" "one"
plant_agent "$W2_SUB" "atwo-2222222222222222" "two"
run_observation "$W2_CFG" "$W2_REPO" one;  CHAIN="$OBS_OUT"
run_observation "$W2_CFG" "$W2_REPO" two;  CHAIN="$CHAIN
$OBS_OUT"
run_rec "$(mk_bash_post "$SID_A" "$W2_TR" "$W2_REPO" \
  "bash ~/.claude/hooks/stop-check.sh one && bash ~/.claude/hooks/stop-check.sh two" "$CHAIN")"
STATE=$(cat "$W2_REPO/$STATE_REL" 2>/dev/null)
expect_contains "two chained runs record the first target" "aone-1111111111111111" "$STATE"
expect_contains "two chained runs record the second target" "atwo-2222222222222222" "$STATE"

# The contract state the observation displayed rides into the record: slices 4/5
# and 4/6 compare the progress artifact's mtime against the look, so the look has
# to have written down what it saw (D-6).
IFS='|' read -r D6_REPO D6_TR D6_SUB D6_CFG <<< "$(make_world d6 yes)"
plant_agent "$D6_SUB" "aworker-1111111111111111" "worker"
mkdir -p "$D6_REPO/.bionic/tmp"
printf 'stage 1\n' > "$D6_REPO/.bionic/tmp/w.progress"
printf 'a report\n' > "$D6_REPO/report.md"
observe "$SID_A" "$D6_CFG" "$D6_REPO" "$D6_TR" worker report.md missing.md --progress "$D6_REPO/.bionic/tmp/w.progress"
STATE=$(cat "$D6_REPO/$STATE_REL" 2>/dev/null)
expect_contains "the record carries each deliverable's state" "present:report.md" "$STATE"
expect_contains "the record carries an absent deliverable as absent" "absent:missing.md" "$STATE"
expect_contains "the record carries the progress artifact's state" "progress_state=present" "$STATE"
expect_matches "the record carries the progress artifact's mtime" 'progress_mtime=[0-9]+' "$STATE"

# A contract that named NO progress artifact is distinguishable from one whose
# artifact is missing — the D-6 distinction a blank value would erase.
observe "$SID_A" "$W1_CFG" "$W1_REPO" "$W1_TR" quiet-reviewer
expect_contains "an unnamed progress artifact is its own state, not a blank" \
  "progress_state=unnamed" "$(cat "$W1_REPO/$STATE_REL")"

# Credential-leak class (§8, AC-8): no command text reaches the state file.
run_observation "$W2_CFG" "$W2_REPO" one
run_rec "$(mk_bash_post "$SID_A" "$W2_TR" "$W2_REPO" \
  "AWS_SECRET=hunter2 bash ~/.claude/hooks/stop-check.sh one" "$OBS_OUT")"
expect_absent "no command text reaches the state file" "hunter2" "$(cat "$W2_REPO/$STATE_REL")"

# ============================================================
echo ""
echo "=== Section 3: no successful run, no record (AC-3, the C6 closure) ==="
# ============================================================
#
# This is the section the slice exists for. The predecessor recorded from
# PreToolUse by re-parsing the command TEXT, so a command the operator watched
# FAIL still left a record naming a live agent, carrying that agent's log mtime
# and size — the exact facts the stop gate spends (critic finding A, pinned as a
# residual in tests/cross-gate-agreement.test.sh §C case 6). Every row below is a
# command whose operator saw a refusal and no evidence tier.

IFS='|' read -r C6_REPO C6_TR C6_SUB C6_CFG <<< "$(make_world c6 yes)"
plant_agent "$C6_SUB" "aworker-7777777777777777" "worker"
plant_agent "$C6_SUB" "asolo-1111111111111111" "solo"
GPROG="$C6_REPO/.bionic/tmp/w-grammar.progress"
mkdir -p "$C6_REPO/.bionic/tmp"; printf 'step 1\n' > "$GPROG"

recorded_target() {  # -> the agent id recorded, or "nothing"
  local rec
  rec=$(grep '^v1|' "$C6_REPO/$STATE_REL" 2>/dev/null \
    | tr '|' '\n' | grep '^target=' | cut -d= -f2 | head -1)
  [ -n "$rec" ] && echo "$rec" || echo nothing
}

for bad in \
  "worker --progres $GPROG" \
  "worker --progress=$GPROG" \
  "--progress $GPROG worker" \
  "--progress solo worker" \
  "worker --unknown-flag" \
  "ghost" \
  ""
do
  rm -f "$C6_REPO/$STATE_REL"
  # shellcheck disable=SC2086
  observe "$SID_A" "$C6_CFG" "$C6_REPO" "$C6_TR" $bad
  expect_status "a refused observation never blocks: '${bad:-<no args>}'" 0 "$REC_ST"
  expect_eq "a refused observation records NOTHING: '${bad:-<no args>}'" "nothing" "$(recorded_target)"
done

# The positive pair for the same grammar, so this is a discriminating wall rather
# than one that refuses everything (TDD §9): the documented interface line
# records, and records the agent the operator actually looked at.
rm -f "$C6_REPO/$STATE_REL"
observe "$SID_A" "$C6_CFG" "$C6_REPO" "$C6_TR" worker report.md --progress "$GPROG"
expect_eq "the documented command line still records its target (C6 positive pair)" \
  "aworker-7777777777777777" "$(recorded_target)"

# A MENTION IS NOT A RUN, and now for a structural reason rather than a parsed
# one: a command that names the script without running it produces no machine
# line, so there is nothing to copy. No command-word grammar is involved.
for mention in \
  "cat hooks/stop-check.sh" \
  "echo stop-check.sh worker" \
  "grep -n stop-check.sh hooks/stop-guard.sh" \
  "# bash ~/.claude/hooks/stop-check.sh worker"
do
  rm -f "$C6_REPO/$STATE_REL"
  run_rec "$(mk_bash_post "$SID_A" "$C6_TR" "$C6_REPO" "$mention" "$mention")"
  expect_eq "a mention is not a run: ${mention:0:34}" "nothing" "$(recorded_target)"
done

# A command that was never dispatched at all fires no PostToolUse event — slice
# 4/1 §5 captured the harness rejecting one and neither hook firing. The
# equivalent here is the absence of any call into this script; asserted as the
# invariant it is, that state on disk is unchanged by an event that never arrives.
rm -f "$C6_REPO/$STATE_REL"
expect_eq "an event that never fires leaves nothing behind" "nothing" "$(recorded_target)"

# An observation that resolved for the OPERATOR but names another session's agent
# is not dischargeable evidence here: a session can only stop its own tasks, so a
# record the gate could never match must not be written.
IFS='|' read -r FS_REPO FS_TR FS_SUB FS_CFG <<< "$(make_world foreignsub yes)"
plant_agent "${FS_TR%/*}/$SID_B/subagents" "aforeign-3333333333333333" "foreign"
observe "$SID_A" "$FS_CFG" "$FS_REPO" "$FS_TR" foreign
expect_eq "the producer DID resolve it for the operator" "0" "$OBS_ST"
if [ -f "$FS_REPO/$STATE_REL" ]; then
  expect_absent "a target resolving only in ANOTHER session records nothing" \
    "target=aforeign-3333333333333333" "$(cat "$FS_REPO/$STATE_REL")"
else
  ok "a target resolving only in ANOTHER session records nothing"
fi

# ============================================================
echo ""
echo "=== Section 4: the observer (AC-3's third field, slice 4/1 assumption A) ==="
# ============================================================
#
# Capture A vs capture B: the same command, the same session, the same turn,
# differing only in a top-level `agent_id`. That single key is what lets slice
# 4/6 refuse a stop discharged by somebody else's look (D-3).

IFS='|' read -r OB_REPO OB_TR OB_SUB OB_CFG <<< "$(make_world observer yes)"
plant_agent "$OB_SUB" "aworker-1111111111111111" "worker"

run_observation "$OB_CFG" "$OB_REPO" worker
run_rec "$(mk_bash_post "$SID_A" "$OB_TR" "$OB_REPO" "bash ~/.claude/hooks/stop-check.sh worker" "$OBS_OUT")"
expect_contains "a payload with NO agent_id records the orchestrator as observer" \
  "observer=orchestrator" "$(cat "$OB_REPO/$STATE_REL")"

run_observation "$OB_CFG" "$OB_REPO" worker
run_rec "$(mk_bash_post "$SID_A" "$OB_TR" "$OB_REPO" "bash ~/.claude/hooks/stop-check.sh worker" "$OBS_OUT" "$SUB_AGENT_ID")"
expect_contains "a payload WITH agent_id records that subagent as observer" \
  "observer=$SUB_AGENT_ID" "$(cat "$OB_REPO/$STATE_REL")"
expect_absent "and no longer claims the orchestrator looked" \
  "observer=orchestrator" "$(cat "$OB_REPO/$STATE_REL")"

# ============================================================
echo ""
echo "=== Section 5: the record is VERSIONED, key-addressed and BOUNDED ==="
# ============================================================

STATE=$(cat "$OB_REPO/$STATE_REL")
expect_matches "the record leads with a schema version token" '(^|\|)v1(\||$)' "$STATE"
expect_matches "fields are key=value, not positional" 'target=' "$STATE"
expect_contains "the file carries its schema in a header comment" \
  "schema stop-check-state/v1" "$STATE"

# One live record per (session, target): re-observing REPLACES, so a second stop
# can never find a second copy of the same look (D-2's precondition).
COUNT=$(grep -c "target=aworker-1111111111111111" "$OB_REPO/$STATE_REL")
expect_eq "re-observing the same target REPLACES its record" "1" "$COUNT"

# P2: the state must not grow without bound — every stop walks it line by line.
IFS='|' read -r P2_REPO P2_TR P2_SUB P2_CFG <<< "$(make_world p2 yes)"
plant_agent "$P2_SUB" "akeeper-7777777777777777" "keeper"
mkdir -p "$P2_REPO/.bionic/tmp"
{
  printf '# bionic observation records — schema stop-check-state/v1\n'
  _i=0
  while [ "$_i" -lt 300 ]; do
    # live-looking foreign records: their session directory still exists, so only
    # the hard cap can drop them
    printf 'v1|session=dead-%s|target=aghost-%s|typed=ghost|log=%s/agent-aghost-%s.jsonl|mtime=1|size=1\n' \
      "$_i" "$_i" "$P2_SUB" "$_i"
    _i=$((_i + 1))
  done
} > "$P2_REPO/$STATE_REL"
observe "$SID_A" "$P2_CFG" "$P2_REPO" "$P2_TR" keeper
P2_COUNT=$(grep -c '^v1|' "$P2_REPO/$STATE_REL" 2>/dev/null || echo 0)
if [ "$P2_COUNT" -le 200 ]; then
  ok "the observation state is bounded, not unbounded (P2): $P2_COUNT records"
else
  no "the observation state is bounded, not unbounded (P2)" "$P2_COUNT records retained"
fi
expect_contains "the record just written survives the bound" \
  "akeeper-7777777777777777" "$(cat "$P2_REPO/$STATE_REL" 2>/dev/null)"

# A record whose session's subagents directory is gone can never discharge
# anything — the gate resolves targets only through that directory — so it is
# inert weight and gets dropped on the next write.
IFS='|' read -r P2B_REPO P2B_TR P2B_SUB P2B_CFG <<< "$(make_world p2b yes)"
plant_agent "$P2B_SUB" "alive-8888888888888888" "alive"
mkdir -p "$P2B_REPO/.bionic/tmp"
printf '# bionic observation records — schema stop-check-state/v1\nv1|session=gone|target=avanished-9999999999999999|typed=vanished|log=/no/such/session/subagents/agent-avanished-9999999999999999.jsonl|mtime=1|size=1\n' \
  > "$P2B_REPO/$STATE_REL"
observe "$SID_A" "$P2B_CFG" "$P2B_REPO" "$P2B_TR" alive
expect_absent "a record whose session directory is gone is pruned (P2)" \
  "avanished-9999999999999999" "$(cat "$P2B_REPO/$STATE_REL" 2>/dev/null)"
expect_contains "pruning does not disturb the record being written" \
  "alive-8888888888888888" "$(cat "$P2B_REPO/$STATE_REL" 2>/dev/null)"

# ============================================================
echo ""
echo "=== Section 6: the roster arm — intended → confirmed (AC-1, confirmation half) ==="
# ============================================================

TUID="toolu_01QhBXwHyZfMQNmS571fqmg8"
NEW_AID="a26bd30bf8616411b"

# The intended row EXACTLY as hooks/dispatch-preflight.sh writes it (slice 4/3,
# schema roster-state/v1 — the field order and header are that script's).
seed_roster() {  # <repo> <sid> <name> <tool_use_id>
  local repo="$1" sid="$2" name="$3" tuid="$4"
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
    printf 'roster-state/v1|status=intended|session=%s|name=%s|agent_id=|launched_at=2026-08-05T12:00:00Z|subagent_type=implementor|model=|deliverable=.bionic/docs/record/w99.txt|duration=~25 minutes.|progress=.bionic/tmp/w99.progress|absent=|tool_use_id=%s\n' \
      "$sid" "$name" "$tuid"
  } > "$repo/.bionic/tmp/roster-${sid}.state"
}

IFS='|' read -r R_REPO R_TR R_SUB R_CFG <<< "$(make_world roster yes)"
seed_roster "$R_REPO" "$SID_A" "w99-impl" "$TUID"
ROSTER="$R_REPO/.bionic/tmp/roster-${SID_A}.state"

run_rec "$(mk_agent_post "$SID_A" "$R_TR" "$R_REPO" "w99-impl" "$NEW_AID" "$TUID")"
expect_status "confirming a roster row never blocks" 0 "$REC_ST"
CONFIRMED=$(grep 'status=confirmed' "$ROSTER" 2>/dev/null)
expect_contains "the row flips to confirmed" "status=confirmed" "$CONFIRMED"
expect_contains "the row gains the full agent id from the tool response" \
  "agent_id=$NEW_AID" "$CONFIRMED"
expect_contains "the completed row still names the agent" "name=w99-impl" "$CONFIRMED"
expect_contains "the completed row keeps the launch timestamp" \
  "launched_at=2026-08-05T12:00:00Z" "$CONFIRMED"
expect_contains "the completed row keeps the contract state the brief carried" \
  "deliverable=.bionic/docs/record/w99.txt" "$CONFIRMED"
expect_contains "the completed row keeps the correlation key" "tool_use_id=$TUID" "$CONFIRMED"
expect_eq "the intended row is not rewritten in place — completion is an append" \
  "1" "$(grep -c 'status=intended' "$ROSTER")"

# The synchronous dispatch shape (capture D): a different tool_response, the same
# agentId key, so the same completion.
IFS='|' read -r RS_REPO RS_TR RS_SUB RS_CFG <<< "$(make_world rostersync yes)"
seed_roster "$RS_REPO" "$SID_A" "sync-child" "$TUID"
run_rec "$(jq -n --arg s "$SID_A" --arg t "$RS_TR" --arg c "$RS_REPO" --arg u "$TUID" \
  '{session_id:$s, transcript_path:$t, cwd:$c, permission_mode:"bypassPermissions",
    effort:{level:"high"}, hook_event_name:"PostToolUse", tool_name:"Agent",
    tool_input:{description:"probe child", prompt:"go", subagent_type:"general-purpose",
                run_in_background:false},
    tool_response:{status:"completed", prompt:"go", agentId:"a6bc0caf11962bbb6",
                   agentType:"general-purpose", content:[{type:"text",text:"DONE"}],
                   resolvedModel:"claude-sonnet-5", totalDurationMs:4791},
    tool_use_id:$u, duration_ms:4795}')"
expect_contains "a synchronous dispatch confirms the same way (capture D shape)" \
  "agent_id=a6bc0caf11962bbb6" "$(grep 'status=confirmed' "$RS_REPO/.bionic/tmp/roster-${SID_A}.state")"

# A ROW NEVER CONFIRMED IS LEFT AS IS. That absence is the signal — the live
# exhibit is a dispatch that returned "spawned successfully" and never produced an
# agent (plan §Tasks T7). Nothing is fabricated in its place.
IFS='|' read -r RN_REPO RN_TR RN_SUB RN_CFG <<< "$(make_world rosternone yes)"
seed_roster "$RN_REPO" "$SID_A" "never-born" "$TUID"
RN_ROSTER="$RN_REPO/.bionic/tmp/roster-${SID_A}.state"

run_rec "$(mk_agent_post "$SID_A" "$RN_TR" "$RN_REPO" "other" "$NEW_AID" "toolu_SOMEOTHERCALL")"
expect_status "a response whose tool_use_id matches no row never blocks" 0 "$REC_ST"
expect_absent "a response correlating to no launched row confirms nothing" \
  "status=confirmed" "$(cat "$RN_ROSTER")"
expect_contains "the unconfirmed row is left exactly as the launch wrote it" \
  "status=intended" "$(cat "$RN_ROSTER")"

# A response carrying no agentId — nothing to fill the row with — writes nothing.
run_rec "$(jq -n --arg s "$SID_A" --arg t "$RN_TR" --arg c "$RN_REPO" --arg u "$TUID" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PostToolUse",
    tool_name:"Agent", tool_input:{description:"d", prompt:"go"},
    tool_response:{status:"error", error:"spawn failed"}, tool_use_id:$u}')"
expect_absent "a response with no agentId confirms nothing" \
  "status=confirmed" "$(cat "$RN_ROSTER")"

# The roster is per-session (D-5): another session's confirmation never completes
# this session's row, and never writes to this session's file.
run_rec "$(mk_agent_post "$SID_B" "$RN_TR" "$RN_REPO" "never-born" "$NEW_AID" "$TUID")"
expect_absent "a foreign session's confirmation does not complete our row" \
  "status=confirmed" "$(cat "$RN_ROSTER")"
expect_no_file "a foreign session's confirmation creates no roster of ours" \
  "$RN_REPO/.bionic/tmp/roster-${SID_B}.state"

# No roster at all — a dispatch the start gate never journalled — writes nothing
# rather than inventing a launch record.
IFS='|' read -r RX_REPO RX_TR RX_SUB RX_CFG <<< "$(make_world rosterabsent yes)"
run_rec "$(mk_agent_post "$SID_A" "$RX_TR" "$RX_REPO" "orphan" "$NEW_AID" "$TUID")"
expect_status "a dispatch with no roster on disk never blocks" 0 "$REC_ST"
expect_no_file "a dispatch with no roster on disk invents no roster" \
  "$RX_REPO/.bionic/tmp/roster-${SID_A}.state"

# ============================================================
echo ""
echo "=== Section 7: hostile repo (AC-8, TDD §8, checklist A2/A3) ==="
# ============================================================

# Predictable temp names + symlink-following writes were a PROVEN arbitrary-file
# overwrite in the discarded run (corr-sec S1/S2). Every level is replanted.
IFS='|' read -r S_REPO S_TR S_SUB S_CFG <<< "$(make_world sec yes)"
plant_agent "$S_SUB" "avictim-ffffffffffffffff" "victim"
mkdir -p "$S_REPO/.bionic/tmp"
VICTIM_FILE="$SANDBOX/sec-outside-file.txt"
echo "ORIGINAL CONTENT" > "$VICTIM_FILE"
ln -s "$VICTIM_FILE" "$S_REPO/$STATE_REL"
observe "$SID_A" "$S_CFG" "$S_REPO" "$S_TR" victim
expect_status "a planted state SYMLINK does not crash the recorder" 0 "$REC_ST"
expect_contains "a planted state symlink is not written through (file level)" \
  "ORIGINAL CONTENT" "$(cat "$VICTIM_FILE")"

IFS='|' read -r S2_REPO S2_TR S2_SUB S2_CFG <<< "$(make_world sec2 yes)"
plant_agent "$S2_SUB" "avictim-ffffffffffffffff" "victim"
OUTSIDE_DIR="$SANDBOX/sec2-outside-dir"
mkdir -p "$OUTSIDE_DIR" "$S2_REPO/.bionic"
ln -s "$OUTSIDE_DIR" "$S2_REPO/.bionic/tmp"
observe "$SID_A" "$S2_CFG" "$S2_REPO" "$S2_TR" victim
expect_status "a planted state DIRECTORY symlink does not crash the recorder" 0 "$REC_ST"
if [ -z "$(ls -A "$OUTSIDE_DIR")" ]; then
  ok "a planted directory symlink is not written through (directory level)"
else
  no "a planted directory symlink is not written through (directory level)" "$(ls -A "$OUTSIDE_DIR")"
fi

# The roster path gets the same treatment: a symlinked roster is never appended
# through, so a hostile repo cannot turn a dispatch into a write anywhere it likes.
IFS='|' read -r S3_REPO S3_TR S3_SUB S3_CFG <<< "$(make_world sec3 yes)"
mkdir -p "$S3_REPO/.bionic/tmp"
ROSTER_VICTIM="$SANDBOX/sec3-roster-victim.txt"
echo "ROSTER ORIGINAL" > "$ROSTER_VICTIM"
ln -s "$ROSTER_VICTIM" "$S3_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_agent_post "$SID_A" "$S3_TR" "$S3_REPO" "w99-impl" "$NEW_AID" "$TUID")"
expect_status "a planted roster SYMLINK does not crash the recorder" 0 "$REC_ST"
expect_eq "a planted roster symlink is not appended through" \
  "ROSTER ORIGINAL" "$(cat "$ROSTER_VICTIM")"

# Unpredictable temp names: mktemp with an X-template, and no PID-based name.
expect_matches "temp files use an mktemp X-template" 'mktemp.*XXXXXX' "$(cat "$REC")"
expect_absent "no PID-based temp filename" '.tmp.$$' "$(cat "$REC")"

# A field-forging value must not be able to manufacture a second record. The
# producer normalizes `|` out of every operator-supplied value; this asserts the
# consumer is not the only thing standing between a crafted name and a forged row.
IFS='|' read -r FG_REPO FG_TR FG_SUB FG_CFG <<< "$(make_world forge yes)"
plant_agent "$FG_SUB" "aworker-1111111111111111" "worker"
run_rec "$(mk_bash_post "$SID_A" "$FG_TR" "$FG_REPO" "bash stop-check.sh x" \
  "stop-check-observation/v1|target=aworker-1111111111111111|typed=x|log=$FG_SUB/agent-aworker-1111111111111111.jsonl|mtime=notanumber|size=1|deliverables=|progress=|progress_mtime=0|progress_state=unnamed")"
expect_absent "a non-numeric activity level is refused, not stored" \
  "aworker-1111111111111111" "$(cat "$FG_REPO/$STATE_REL" 2>/dev/null)"

# A machine line naming a log OUTSIDE this session's subagents directory is not
# dischargeable evidence and is not stored, however well-formed it is.
run_rec "$(mk_bash_post "$SID_A" "$FG_TR" "$FG_REPO" "bash stop-check.sh x" \
  "stop-check-observation/v1|target=aelsewhere-2222222222222222|typed=x|log=/etc/passwd|mtime=1|size=1|deliverables=|progress=|progress_mtime=0|progress_state=unnamed")"
expect_absent "a machine line naming a log outside this session is not stored" \
  "aelsewhere-2222222222222222" "$(cat "$FG_REPO/$STATE_REL" 2>/dev/null)"

# ============================================================
echo ""
echo "=== Section 8: it never blocks, whatever happens (PostToolUse invariant) ==="
# ============================================================
#
# PostToolUse cannot block — the tool has already run — so every path must exit
# 0. The lock is the one place a naive implementation spins forever: `mkdir`
# fails for reasons no reclaim can fix (an unwritable state directory is
# repo-controlled) and `rm -rf` of an ABSENT path SUCCEEDS.
run_bounded() {  # <secs> <payload> -> sets BOUNDED_ST (137 = killed)
  local secs="$1" payload="$2" waited=0 pid
  printf '%s' "$payload" | bash "$REC" >"$SANDBOX/.bout" 2>"$SANDBOX/.berr" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$secs" ]; do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; BOUNDED_ST=137
  else
    wait "$pid"; BOUNDED_ST=$?
  fi
  return 0
}

IFS='|' read -r LK_REPO LK_TR LK_SUB LK_CFG <<< "$(make_world lock yes)"
plant_agent "$LK_SUB" "awedged-6666666666666666" "wedged"
mkdir -p "$LK_REPO/.bionic/tmp"
run_observation "$LK_CFG" "$LK_REPO" wedged
chmod 500 "$LK_REPO/.bionic/tmp"
run_bounded 12 "$(mk_bash_post "$SID_A" "$LK_TR" "$LK_REPO" \
  "bash ~/.claude/hooks/stop-check.sh wedged" "$OBS_OUT")"
if [ "$BOUNDED_ST" = "137" ]; then
  no "the recorder terminates when the lock cannot be taken" "still running after 12s"
else
  expect_status "the recorder never blocks, even unable to lock" 0 "$BOUNDED_ST"
fi
chmod 700 "$LK_REPO/.bionic/tmp"

# Malformed payloads: this script is fed by the platform, and a shape it does not
# expect must be inert rather than fatal.
for bad_payload in \
  '{}' \
  '{"tool_name":"Bash"}' \
  '{"tool_name":"Bash","tool_response":"error: command failed"}' \
  '{"tool_name":"Agent","tool_response":{}}' \
  'not json at all'
do
  run_rec "$bad_payload"
  expect_status "a malformed payload never blocks: ${bad_payload:0:32}" 0 "$REC_ST"
  expect_eq "a malformed payload says nothing: ${bad_payload:0:32}" "" "$REC_ERR"
done

# ============================================================
echo ""
echo "=== Section 9: six-axis review remediations (S-1 sanitizer parity, S-2 log existence, P roster bound) ==="
# ============================================================
#
# S-1. The writer these values land beside — hooks/dispatch-preflight.sh's
# sanitize() — translates `\n\r\t|` and control characters out of every value,
# because a pipe-delimited one-line record treats either as a field or a row
# boundary. This script checked for `|` ALONE, forty lines from the sibling that
# strips both.
#
# WHAT THE PIPE CHECK ALREADY BUYS, stated so the fix is not sold as more than it
# is: a fully-shaped forged row needs pipes of its own, so it never got past the
# existing guard, and neither value is repo-supplied anyway (§8's adversary never
# reaches them). What a NEWLINE still does is split one record across two physical
# lines — the tail of the real row becoming a second line the readers must
# recognise and skip, one of which begins with the schema token itself. An
# artifact whose line count depends on a platform value is the finding; parity
# with the writer's own pipeline is the fix.

IFS='|' read -r S1_REPO S1_TR S1_SUB S1_CFG <<< "$(make_world sanparity yes)"
seed_roster "$S1_REPO" "$SID_A" "w99-impl" "$TUID"
S1_ROSTER="$S1_REPO/.bionic/tmp/roster-${SID_A}.state"
# No pipe of its own: everything after the newline is supplied by the REAL row's
# own remaining fields, which is what makes the split line schema-shaped.
S1_EVIL="aevil-3333333333333333
roster-state/v1"
run_rec "$(mk_agent_post "$SID_A" "$S1_TR" "$S1_REPO" "w99-impl" "$S1_EVIL" "$TUID")"
expect_status "a newline-bearing agent id never blocks" 0 "$REC_ST"
expect_eq "a newline in the platform's agentId cannot split the row it writes" \
  "2" "$(grep -c '^roster-state/v1|' "$S1_ROSTER" 2>/dev/null)"
expect_contains "…the id is normalized into the row instead, as the writer would" \
  "agent_id=aevil-3333333333333333 roster-state/v1|" "$(cat "$S1_ROSTER" 2>/dev/null)"

IFS='|' read -r S1B_REPO S1B_TR S1B_SUB S1B_CFG <<< "$(make_world sanparityobs yes)"
plant_agent "$S1B_SUB" "aworker-1111111111111111" "worker"
S1B_EVIL="aobserver-5555555555555555
v1"
run_observation "$S1B_CFG" "$S1B_REPO" worker >/dev/null 2>&1
run_rec "$(mk_bash_post "$SID_A" "$S1B_TR" "$S1B_REPO" "bash stop-check.sh worker" "$OBS_OUT" "$S1B_EVIL")"
expect_status "a newline-bearing observer id never blocks" 0 "$REC_ST"
expect_eq "a newline in the payload's agent_id cannot split the record it writes" \
  "1" "$(grep -c '^v1|' "$S1B_REPO/$STATE_REL" 2>/dev/null)"
expect_contains "…the observer is normalized into the record instead" \
  "observer=aobserver-5555555555555555 v1" "$(cat "$S1B_REPO/$STATE_REL" 2>/dev/null)"

# S-2. The recorder's disclosed residual — a command that PRINTS a well-formed
# machine line produces a record — argued that forging one costs the target's
# CURRENT log mtime and size, "which the gate re-checks against the live file".
# The re-check is real, and it has a hole the disclosure did not name: when the
# target's log does not exist, the gate reads mtime 0 / size 0, so a forged line
# carrying mtime=0|size=0 matches it exactly. A record for a log that is not on
# disk can never be honest evidence anyway — the observation just stat'ed that
# file — so it is refused at the door.
IFS='|' read -r S2_REPO S2_TR S2_SUB S2_CFG <<< "$(make_world logexists yes)"
plant_agent "$S2_SUB" "areal-7777777777777777" "real"
run_rec "$(mk_bash_post "$SID_A" "$S2_TR" "$S2_REPO" "echo forged" \
  "stop-check-observation/v1|target=aphantom-8888888888888888|typed=phantom|log=$S2_SUB/agent-aphantom-8888888888888888.jsonl|mtime=0|size=0|deliverables=|progress=|progress_mtime=0|progress_state=unnamed|classification=ours|deliverable_source=none|progress_source=none")"
expect_status "a machine line naming a log that does not exist never blocks" 0 "$REC_ST"
expect_absent "…and is not recorded: the match-by-zero forgery has nothing to match" \
  "aphantom-8888888888888888" "$(cat "$S2_REPO/$STATE_REL" 2>/dev/null)"
# The real path is untouched — the producer stat'ed the file it named, so it is there.
run_observation "$S2_CFG" "$S2_REPO" real >/dev/null 2>&1
run_rec "$(mk_bash_post "$SID_A" "$S2_TR" "$S2_REPO" "bash stop-check.sh real" "$OBS_OUT")"
expect_contains "a real observation of a real log is still recorded" \
  "areal-7777777777777777" "$(cat "$S2_REPO/$STATE_REL" 2>/dev/null)"

# P (performance). `stop-check.state` is capped at MAX_RECORDS because every stop
# walks it; the roster had no cap, no rotation and no compaction — two rows per
# dispatch, appended forever, and THIS arm rescans the whole file on every
# dispatch. Measured on the review's fixture: 669 ms at 200 rows, 3152 ms at
# 1000, against a registered 10 s hook timeout. It degrades to the closed side
# (an unconfirmed row grants nothing) but silently, and the operator's only
# symptom is by-name stops beginning to refuse.
IFS='|' read -r PR_REPO PR_TR PR_SUB PR_CFG <<< "$(make_world rosterbound yes)"
seed_roster "$PR_REPO" "$SID_A" "w99-impl" "$TUID"
PR_ROSTER="$PR_REPO/.bionic/tmp/roster-${SID_A}.state"
{
  _i=0
  while [ "$_i" -lt 300 ]; do
    printf 'roster-state/v1|status=confirmed|session=%s|name=old-%s|agent_id=aold-%s|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_OLD%s\n' \
      "$SID_A" "$_i" "$_i" "$_i"
    _i=$((_i + 1))
  done
} >> "$PR_ROSTER"
run_rec "$(mk_agent_post "$SID_A" "$PR_TR" "$PR_REPO" "w99-impl" "$NEW_AID" "$TUID")"
PR_COUNT=$(grep -c '^roster-state/v1|' "$PR_ROSTER" 2>/dev/null || echo 0)
if [ "$PR_COUNT" -le 200 ]; then
  ok "the roster is bounded like the observation state, not unbounded: $PR_COUNT rows"
else
  no "the roster is bounded like the observation state" "$PR_COUNT rows retained"
fi
expect_contains "the row this event just confirmed survives the bound" \
  "agent_id=$NEW_AID" "$(cat "$PR_ROSTER" 2>/dev/null)"
expect_contains "the schema header survives the fold" \
  "schema roster-state/v1" "$(cat "$PR_ROSTER" 2>/dev/null)"
expect_contains "the NEWEST rows are the ones kept" "name=old-299" "$(cat "$PR_ROSTER" 2>/dev/null)"
expect_absent "…and the oldest are the ones dropped" "name=old-0|" "$(cat "$PR_ROSTER" 2>/dev/null)"
# A roster under the bound is still append-only: nothing is rewritten, and the
# intended row it completes stays exactly where the launch put it.
expect_eq "an under-bound roster keeps its intended row (completion is an append)" \
  "1" "$(grep -c 'status=intended' "$S1_ROSTER" 2>/dev/null)"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "execution-recorder.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
