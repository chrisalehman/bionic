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
# Usage: bash tests/execution-recorder.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HERE="${BIONIC_HOOKS_DIR}"
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
expect_contains() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_matches()  { if grep -qE -- "$2" <<<"$3"; then ok "$1"; else no "$1" "no match: $2"; fi; }
expect_absent()   { if grep -qF -- "$2" <<<"$3"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
expect_file()     { if [ -f "$2" ]; then ok "$1"; else no "$1" "no such file: $2"; fi; }
expect_no_file()  { if [ -f "$2" ]; then no "$1" "file exists but should not: $2"; else ok "$1"; fi; }

# Portable clock helpers for Section 12 (S6): the delivered predicate the fix
# protects compares a file's mtime against an ISO8601 `launched_at`, and both
# directions of that conversion differ between BSD (macOS) and GNU date/touch.
file_mtime_test() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
iso_to_epoch() {  # <ISO8601Z> -> epoch seconds, or empty
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s' 2>/dev/null || date -u -d "$1" '+%s' 2>/dev/null
}
set_mtime_epoch() {  # <file> <epoch>
  # `touch -t` interprets its timestamp argument in LOCAL time on both BSD and
  # GNU touch, so the calendar string handed to it must be the LOCAL rendering
  # of the epoch (no `-u`) — the earlier `-u` rendering fed a UTC calendar
  # string through a local-time parser and silently offset every mtime by the
  # host's UTC delta, large enough to flip the paired-negative's inequality.
  local ts
  ts=$(date -r "$2" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$2" '+%Y%m%d%H%M.%S' 2>/dev/null)
  [ -n "$ts" ] && touch -t "$ts" "$1" 2>/dev/null
  return 0
}

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
# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2: a
# plain /clear re-keys env, payload and pid file together). Since bionic 1.4.0 the hook
# takes its session id from lib/session.sh, where the env value is primary — so a driver
# that left the runner's own CLAUDE_CODE_SESSION_ID in the environment would be driving a
# DIVERGENCE, not a session, and every roster filename below would be built from the
# wrong key. A payload with no session key exports an empty one, which is what keeps the
# no-session-key arms reaching the fail direction they pin.
run_rec() {  # <payload-json>
  local _sid; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  REC_OUT=$(printf '%s' "$1" | env CLAUDE_CODE_SESSION_ID="$_sid" bash "$REC" 2>"$SANDBOX/.err"); REC_ST=$?
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

run_rec "$(mk_bash_post "$SID_A" "$W1_TR" "$W1_REPO" "ls -la && git status" "README.md")"

# Static order pin: the cheap relevance test must PRECEDE the plan-directory walk
# in the source, not merely produce the same answer (arch-perf F8/F9 — the defect
# was cost, which behaviour alone cannot detect). This script is registered on
# every Bash call in the session, so the walk on the unrelated path is the whole
# cost.
_rel_line=$(grep -n 'MLINES=' "$REC" | head -1 | cut -d: -f1)
_walk_line=$(grep -nE '^[[:space:]]*(PLAN=|for d in "\$DOCS_ROOT)' "$REC" | head -1 | cut -d: -f1)

# Outside an active wave the script is inert, like every other gate in this
# family (spec §Component boundaries: "Inert when no wave is active").
IFS='|' read -r NW_REPO NW_TR NW_SUB NW_CFG <<< "$(make_world nowave no)"
plant_agent "$NW_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
observe "$SID_A" "$NW_CFG" "$NW_REPO" "$NW_TR" quiet-reviewer

# ============================================================
echo ""
echo "=== Section 2: a run that produced evidence is recorded (AC-3, positive) ==="
# ============================================================

observe "$SID_A" "$W1_CFG" "$W1_REPO" "$W1_TR" quiet-reviewer
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
done

# A command that was never dispatched at all fires no PostToolUse event — slice
# 4/1 §5 captured the harness rejecting one and neither hook firing. The
# equivalent here is the absence of any call into this script; asserted as the
# invariant it is, that state on disk is unchanged by an event that never arrives.
rm -f "$C6_REPO/$STATE_REL"

# An observation that resolved for the OPERATOR but names another session's agent
# is not dischargeable evidence here: a session can only stop its own tasks, so a
# record the gate could never match must not be written.
IFS='|' read -r FS_REPO FS_TR FS_SUB FS_CFG <<< "$(make_world foreignsub yes)"
plant_agent "${FS_TR%/*}/$SID_B/subagents" "aforeign-3333333333333333" "foreign"
observe "$SID_A" "$FS_CFG" "$FS_REPO" "$FS_TR" foreign

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
# The async shape carries no addressing id, so the completed row gains no
# `teammate_id` field. The field is teammate-mode's alone (AC-10): a reader that
# finds it knows which namespace the row's id is in without parsing the id.

# THE NAME COMES OFF THE DISPATCH ITSELF (epic-16 wave-03, T4c). `tool_input.name`
# is the one place the harness spells the dispatch name, and this event carries it
# beside the agent id — the single payload that holds both (T4b §3). Recording it
# here makes the confirmed row self-sufficient for the name AND the id, so nothing
# downstream has to recover a name from `agent_type`, which carries the subagent
# TYPE and never the name (t4-probes-report.md §5.1).
IFS='|' read -r RN_REPO RN_TR RN_SUB RN_CFG <<< "$(make_world rostername yes)"
seed_roster "$RN_REPO" "$SID_A" "stale-name" "$TUID"
RN_ROSTER="$RN_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_agent_post "$SID_A" "$RN_TR" "$RN_REPO" "dispatch-name" "$NEW_AID" "$TUID")"
RN_CONFIRMED=$(grep 'status=confirmed' "$RN_ROSTER" 2>/dev/null)
expect_contains "the confirmed row takes its name from tool_input.name" \
  "|name=dispatch-name|" "$RN_CONFIRMED"
expect_contains "…beside the agent id from the same payload" \
  "agent_id=$NEW_AID" "$RN_CONFIRMED"

# An UNNAMED dispatch carries no `tool_input.name` at all, and the launch row's own
# (empty) name must survive rather than being overwritten by an empty read that
# looks the same but is not the same decision.
IFS='|' read -r RU_REPO RU_TR RU_SUB RU_CFG <<< "$(make_world rosterunnamed yes)"
seed_roster "$RU_REPO" "$SID_A" "" "$TUID"
RU_ROSTER="$RU_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(jq -n --arg s "$SID_A" --arg t "$RU_TR" --arg c "$RU_REPO" --arg u "$TUID" \
  --arg a "$NEW_AID" \
  '{session_id:$s, transcript_path:$t, cwd:$c, permission_mode:"bypassPermissions",
    effort:{level:"high"}, hook_event_name:"PostToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                run_in_background:true},
    tool_response:{isAsync:true, status:"async_launched", agentId:$a,
                   description:"a dispatch", resolvedModel:"claude-sonnet-5"},
    tool_use_id:$u, duration_ms:6}')"
expect_contains "…and is confirmed by its id, with the name left empty" \
  "|name=|" "$(grep 'status=confirmed' "$RU_ROSTER" 2>/dev/null)"
expect_contains "…which is the row the landing sweep joins on" \
  "agent_id=$NEW_AID" "$(grep 'status=confirmed' "$RU_ROSTER" 2>/dev/null)"

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

# ---------- the TEAMMATE payload shape (AC-10, epic-16 wave-01 slice 0) ----------
#
# FIXTURE FIDELITY: transcribed field for field from
# .bionic/docs/record/landing-wave-capture-probe.md §3-A — the verbatim
# PostToolUse|Agent payload captured live on CLI 2.1.226 from a pty-driven
# interactive session with CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1. Only the
# session id, transcript, cwd, name and tool_use_id are re-pointed at this
# suite's sandbox; every tool_response key, its spelling and its value form are
# the capture's own. This is the shape EVERY interactive dispatch on this machine
# has produced since 07-12 (payload probe §Task 1(c)), and the shape the
# recorder read straight past: it looked for `agentId` and the payload spells it
# `agent_id`, so the guard at :140 exited before any roster work and no row on
# any live session ever reached `confirmed`.
#
# THE TWO IDS ARE NOT THE SAME VALUE, which is why this is not a one-line
# spelling fix. `tool_response.agent_id` here is the ADDRESSING form
# `probemate@session-3b51bef0`; every later payload for the same teammate —
# SubagentStart, SubagentStop, its own tool calls — carries the TRANSCRIPT form
# `aprobemate-4da9be517e8f90bd` in top-level `agent_id`, and no payload contains
# both (capture probe §3 conclusion 3). Writing the addressing form into
# `agent_id=` would turn every by-id wall's input from EMPTY into WRONG — the
# roster would assert an identity no observation can ever match. So the
# addressing id lands in its own field and `agent_id=` stays empty here; the
# transcript-form id arrives later, from SubagentStart (slice 1's `identified`
# row). A confirmed row never carries a wrong-namespace id.
mk_agent_post_teammate() {  # <sid> <transcript> <cwd> <name> <addressing-id> <tool_use_id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg n "$4" --arg a "$5" --arg u "$6" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Agent",
      tool_input:{description:"Run marker echo command",
                  prompt:"run the bash command echo MARKER_TM_R5 then reply DONE",
                  subagent_type:"general-purpose", run_in_background:true, name:$n},
      tool_response:{status:"teammate_spawned",
                     prompt:"run the bash command echo MARKER_TM_R5 then reply DONE",
                     teammate_id:$a, agent_id:$a, agent_type:"general-purpose",
                     model:"claude-opus-5", name:$n, color:"blue",
                     tmux_session_name:"in-process", tmux_window_name:"in-process",
                     tmux_pane_id:"in-process", team_name:"session-3b51bef0",
                     is_splitpane:false, plan_mode_required:false},
      tool_use_id:$u, duration_ms:9}'
}

IFS='|' read -r RT_REPO RT_TR RT_SUB RT_CFG <<< "$(make_world rosterteam yes)"
seed_roster "$RT_REPO" "$SID_A" "probemate" "$TUID"
RT_ROSTER="$RT_REPO/.bionic/tmp/roster-${SID_A}.state"
TEAM_ID="probemate@session-3b51bef0"

run_rec "$(mk_agent_post_teammate "$SID_A" "$RT_TR" "$RT_REPO" "probemate" "$TEAM_ID" "$TUID")"
RT_CONFIRMED=$(grep 'status=confirmed' "$RT_ROSTER" 2>/dev/null)
expect_contains "the teammate payload completes the row to confirmed" \
  "status=confirmed" "$RT_CONFIRMED"
expect_contains "the addressing id is recorded in its own teammate_id field" \
  "teammate_id=$TEAM_ID" "$RT_CONFIRMED"
# The `@` is why this needs saying: the sanitizer strips `|`, newlines and
# control characters, and an over-eager one would silently truncate the id at
# the separator that makes it addressable.
expect_contains "the addressing form survives the sanitizer intact" \
  "@session-3b51bef0" "$RT_CONFIRMED"
expect_contains "agent_id stays EMPTY — a confirmed row never carries a wrong-namespace id" \
  "|agent_id=|" "$RT_CONFIRMED"
expect_contains "the completed teammate row still names the agent" "name=probemate" "$RT_CONFIRMED"
expect_contains "the completed teammate row keeps the contract state" \
  "deliverable=.bionic/docs/record/w99.txt" "$RT_CONFIRMED"
expect_contains "the completed teammate row keeps the correlation key" \
  "tool_use_id=$TUID" "$RT_CONFIRMED"

# A ROW NEVER CONFIRMED IS LEFT AS IS. That absence is the signal — the live
# exhibit is a dispatch that returned "spawned successfully" and never produced an
# agent (plan §Tasks T7). Nothing is fabricated in its place.
IFS='|' read -r RN_REPO RN_TR RN_SUB RN_CFG <<< "$(make_world rosternone yes)"
seed_roster "$RN_REPO" "$SID_A" "never-born" "$TUID"
RN_ROSTER="$RN_REPO/.bionic/tmp/roster-${SID_A}.state"

run_rec "$(mk_agent_post "$SID_A" "$RN_TR" "$RN_REPO" "other" "$NEW_AID" "toolu_SOMEOTHERCALL")"

# A response carrying no agentId — nothing to fill the row with — writes nothing.
run_rec "$(jq -n --arg s "$SID_A" --arg t "$RN_TR" --arg c "$RN_REPO" --arg u "$TUID" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PostToolUse",
    tool_name:"Agent", tool_input:{description:"d", prompt:"go"},
    tool_response:{status:"error", error:"spawn failed"}, tool_use_id:$u}')"

# The roster is per-session (D-5): another session's confirmation never completes
# this session's row, and never writes to this session's file.
run_rec "$(mk_agent_post "$SID_B" "$RN_TR" "$RN_REPO" "never-born" "$NEW_AID" "$TUID")"

# No roster at all — a dispatch the start gate never journalled — writes nothing
# rather than inventing a launch record.
IFS='|' read -r RX_REPO RX_TR RX_SUB RX_CFG <<< "$(make_world rosterabsent yes)"
run_rec "$(mk_agent_post "$SID_A" "$RX_TR" "$RX_REPO" "orphan" "$NEW_AID" "$TUID")"

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

IFS='|' read -r S2_REPO S2_TR S2_SUB S2_CFG <<< "$(make_world sec2 yes)"
plant_agent "$S2_SUB" "avictim-ffffffffffffffff" "victim"
OUTSIDE_DIR="$SANDBOX/sec2-outside-dir"
mkdir -p "$OUTSIDE_DIR" "$S2_REPO/.bionic"
ln -s "$OUTSIDE_DIR" "$S2_REPO/.bionic/tmp"
observe "$SID_A" "$S2_CFG" "$S2_REPO" "$S2_TR" victim

# The roster path gets the same treatment: a symlinked roster is never appended
# through, so a hostile repo cannot turn a dispatch into a write anywhere it likes.
IFS='|' read -r S3_REPO S3_TR S3_SUB S3_CFG <<< "$(make_world sec3 yes)"
mkdir -p "$S3_REPO/.bionic/tmp"
ROSTER_VICTIM="$SANDBOX/sec3-roster-victim.txt"
echo "ROSTER ORIGINAL" > "$ROSTER_VICTIM"
ln -s "$ROSTER_VICTIM" "$S3_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_agent_post "$SID_A" "$S3_TR" "$S3_REPO" "w99-impl" "$NEW_AID" "$TUID")"

# Unpredictable temp names: mktemp with an X-template, and no PID-based name.

# A field-forging value must not be able to manufacture a second record. The
# producer normalizes `|` out of every operator-supplied value; this asserts the
# consumer is not the only thing standing between a crafted name and a forged row.
IFS='|' read -r FG_REPO FG_TR FG_SUB FG_CFG <<< "$(make_world forge yes)"
plant_agent "$FG_SUB" "aworker-1111111111111111" "worker"
run_rec "$(mk_bash_post "$SID_A" "$FG_TR" "$FG_REPO" "bash stop-check.sh x" \
  "stop-check-observation/v1|target=aworker-1111111111111111|typed=x|log=$FG_SUB/agent-aworker-1111111111111111.jsonl|mtime=notanumber|size=1|deliverables=|progress=|progress_mtime=0|progress_state=unnamed")"

# A machine line naming a log OUTSIDE this session's subagents directory is not
# dischargeable evidence and is not stored, however well-formed it is.
run_rec "$(mk_bash_post "$SID_A" "$FG_TR" "$FG_REPO" "bash stop-check.sh x" \
  "stop-check-observation/v1|target=aelsewhere-2222222222222222|typed=x|log=/etc/passwd|mtime=1|size=1|deliverables=|progress=|progress_mtime=0|progress_state=unnamed")"

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
# The real path is untouched — the producer stat'ed the file it named, so it is there.
run_observation "$S2_CFG" "$S2_REPO" real >/dev/null 2>&1
run_rec "$(mk_bash_post "$SID_A" "$S2_TR" "$S2_REPO" "bash stop-check.sh real" "$OBS_OUT")"
expect_contains "a real observation of a real log is still recorded" \
  "areal-7777777777777777" "$(cat "$S2_REPO/$STATE_REL" 2>/dev/null)"

# P (performance). This arm rescans the whole roster on every dispatch, and the
# roster grows two rows per dispatch for the life of the session. The cost was
# real: `line_field` is four processes, the loop ran three of them PER ROW, and a
# single completion measured 696 ms at 200 rows, 3180 ms at 1000 and 9260 ms at
# 3000 — against the 10 s hook timeout the registration declares. Past that
# the completion arm times out, rows silently stop reaching `confirmed`, and the
# operator's only symptom is by-name stops beginning to refuse.
#
# THE FIX IS THE PREFILTER, NOT A CAP, and the difference matters enough to say
# here (Step-6 critic F-1). The first remediation capped the file at MAX_RECORDS
# and evicted by recency — which disarmed the D-6 staleness wall for exactly the
# agents it exists for, because a live agent's roster row is the only copy of its
# contract and eviction cannot tell a running agent from a finished one. That
# whole chain is driven in tests/cross-gate-agreement.test.sh §F; what is pinned
# HERE is the two properties this file owns: the ledger is never truncated, and
# the scan stays cheap enough that it does not have to be.
#
# Haystacks stay ROW-SCOPED below, never the file: `expect_contains` is
# `printf | grep -qF` under `pipefail`, and on a multi-megabyte haystack whose
# match is near the top, grep exits first, printf takes SIGPIPE and the pipeline
# returns 141 — a false FAIL on a string that is present.
IFS='|' read -r PR_REPO PR_TR PR_SUB PR_CFG <<< "$(make_world rosterbound yes)"
seed_roster "$PR_REPO" "$SID_A" "w99-impl" "$TUID"
PR_ROSTER="$PR_REPO/.bionic/tmp/roster-${SID_A}.state"
# A SECOND agent, still running, whose brief declared a progress path. It is the
# OLDEST row in the file after the seed — the first thing eviction-by-recency
# takes, and the row hooks/stop-guard.sh sources its refusal from.
printf 'roster-state/v1|status=intended|session=%s|name=live-one|agent_id=|launched_at=2026-08-05T12:00:00Z|subagent_type=implementor|model=|deliverable=|duration=|progress=.bionic/tmp/live-one.progress|claims=|cadence=~6m.|absent=|tool_use_id=toolu_LIVEONE\n' \
  "$SID_A" >> "$PR_ROSTER"
{
  _i=0
  while [ "$_i" -lt 3000 ]; do
    printf 'roster-state/v1|status=confirmed|session=%s|name=old-%s|agent_id=aold-%s|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_OLD%s\n' \
      "$SID_A" "$_i" "$_i" "$_i"
    _i=$((_i + 1))
  done
} >> "$PR_ROSTER"
PR_BEFORE=$(grep -c '^roster-state/v1|' "$PR_ROSTER" 2>/dev/null || echo 0)

# Seconds, not milliseconds, and deliberately: `date +%s` is the one clock every
# platform this suite runs on has. The budget it has to discriminate is 0.1 s
# against 9.3 s, so whole seconds are ample and nothing here can flake on
# resolution.
PR_T0=$(date -u +%s)
run_rec "$(mk_agent_post "$SID_A" "$PR_TR" "$PR_REPO" "w99-impl" "$NEW_AID" "$TUID")"
PR_ELAPSED=$(( $(date -u +%s) - PR_T0 ))
if [ "$PR_ELAPSED" -lt 5 ]; then
  :
else
  no "one completion against a 3000-row roster stays inside the hook timeout" \
     "took ${PR_ELAPSED}s — the per-row prefilter is not doing its job"
fi

expect_eq "the ledger is NOT truncated: the completion is a pure append" \
  "$((PR_BEFORE + 1))" "$(grep -c '^roster-state/v1|' "$PR_ROSTER" 2>/dev/null || echo 0)"
expect_contains "the row this event confirmed is appended" \
  "agent_id=$NEW_AID" "$(grep 'status=confirmed|.*name=w99-impl|' "$PR_ROSTER" 2>/dev/null)"
PR_LIVE=$(grep 'name=live-one|' "$PR_ROSTER" 2>/dev/null)
# A roster under the bound is still append-only: nothing is rewritten, and the
# intended row it completes stays exactly where the launch put it.

# ============================================================
echo ""
echo "=== Section 10: the identification arm — SubagentStart → identified (AC-2, epic-16 w1 slice 1) ==="
# ============================================================
#
# FIXTURE FIDELITY: mk_subagent_start is transcribed field for field from
# .bionic/docs/record/landing-wave-capture-probe.md §3-C — the verbatim
# SubagentStart payload captured live from a pty-driven interactive session with
# CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1. Six keys, and NO `tool_name` among
# them: that is why this arm cannot sit behind the tool-name gate the other two
# share. Only the session id, transcript, cwd, name and agent id are re-pointed
# at this suite's sandbox; the key set and its spellings are the capture's own.
#
# WHY THE JOIN IS BY AGENT ID, and no longer by name (epic-16 wave-03, T4c). The
# name join read `agent_type` as "the teammate's name". T4b §3 measured that field
# on a live Agent dispatch and it carries the subagent TYPE (`general-purpose`),
# never the dispatch name — so every by-name join missed and this arm was inert
# even when it did receive its event (t4-probes-report.md §5.1). The payload has
# exactly seven keys and only ONE of them can key a row: `agent_id`, the
# transcript-form id, which is byte-identical to the `tool_response.agentId` the
# roster arm already wrote at confirmation and to the `background_tasks[].id` the
# landing sweep reads (T4b §4, measured on one dispatch across all three).
#
# THE COST, stated rather than discovered later: an `intended` row carries an
# EMPTY `agent_id` until the roster arm completes it, so this arm can no longer
# rescue a dispatch whose PostToolUse never fired, and a teammate-mode row — whose
# `agent_id=` is deliberately left empty because the launch response carries only
# the ADDRESSING form — is never identified at all. Both are joins that were
# ALREADY missing (they keyed on a field that does not carry a name); what changes
# is that the miss is now structural and visible instead of silent.
#
# The roster fixture below carries the writer's CURRENT field set — including
# `source=` and `waiver=`, which hooks/dispatch-preflight.sh has emitted since
# the absent-deliverable wall (4b16159) and which this suite's older
# `seed_roster` predates. Every-field-copied-forward is only a meaningful claim
# against the fields the writer actually writes.

mk_subagent_start() {  # <sid> <transcript> <cwd> <agent-type> <agent-id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg n "$4" --arg a "$5" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      agent_id:$a, agent_type:$n, hook_event_name:"SubagentStart"}'
}

seed_roster_full() {  # <repo> <sid> <name> <tool_use_id> [status] [agent-id] [teammate-id]
  local repo="$1" sid="$2" name="$3" tuid="$4"
  local status="${5:-intended}" aid="${6:-}" tid="${7:-}"
  local f="$repo/.bionic/tmp/roster-${sid}.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=2026-08-08T09:00:00Z|subagent_type=implementor|model=claude-opus-5|deliverable=.bionic/docs/record/w1-slice1-report.md|source=declared|duration=~25 minutes.|progress=.bionic/tmp/w1-s1-progress.md|claims=|cadence=~8m.|absent=|waiver=|tool_use_id=%s' \
    "$status" "$sid" "$name" "$aid" "$tuid" >> "$f"
  if [ -n "$tid" ]; then printf '|teammate_id=%s' "$tid" >> "$f"; fi
  printf '\n' >> "$f"
  return 0
}

START_ID="aprobemate-4da9be517e8f90bd"

# ---------- the join over a confirmed row ----------
IFS='|' read -r I1_REPO I1_TR I1_SUB I1_CFG <<< "$(make_world identintended yes)"
seed_roster_full "$I1_REPO" "$SID_A" "probemate" "toolu_01IDENTA" confirmed "$START_ID"
I1_ROSTER="$I1_REPO/.bionic/tmp/roster-${SID_A}.state"

run_rec "$(mk_subagent_start "$SID_A" "$I1_TR" "$I1_REPO" "general-purpose" "$START_ID")"
I1_ROW=$(grep 'status=identified' "$I1_ROSTER" 2>/dev/null)
expect_contains "the start appends an identified row" "status=identified" "$I1_ROW"
expect_contains "…carrying the TRANSCRIPT-form id the by-id walls can match" \
  "agent_id=$START_ID" "$I1_ROW"
# THE §5.1 FIX, asserted directly: the payload's `agent_type` is `general-purpose`
# — the subagent TYPE — and the row still answers to the dispatch name the brief
# gave it. A join that read agent_type as a name would have written `probemate`
# nowhere and matched nothing.
expect_contains "…still named for the DISPATCH, never for the payload's agent_type" \
  "name=probemate" "$I1_ROW"
# Slice 2's verdict verb folds the roster to the LATEST row per name and reads
# the contract off that row alone (plan Assumptions 8). Every field carried
# forward is what makes that fold sound.
expect_contains "…and the deliverable the brief contracted" \
  "deliverable=.bionic/docs/record/w1-slice1-report.md" "$I1_ROW"
expect_contains "…the launch clock the delivered predicate dates from" \
  "launched_at=2026-08-08T09:00:00Z" "$I1_ROW"
expect_contains "…the progress artifact and its cadence" \
  "progress=.bionic/tmp/w1-s1-progress.md" "$I1_ROW"
expect_contains "…the cadence beside it" "cadence=~8m." "$I1_ROW"
expect_contains "…the deliverable's source designation" "source=declared" "$I1_ROW"
expect_contains "…the waiver field the absent-deliverable wall writes" "waiver=" "$I1_ROW"
expect_contains "…and the correlation key" "tool_use_id=toolu_01IDENTA" "$I1_ROW"
expect_eq "exactly one identified row is appended" \
  "1" "$(grep -c 'status=identified' "$I1_ROSTER")"

# ---------- the full chain: intended → confirmed → identified ----------
#
# The async dispatch lifecycle, which is the one the id join can span end to end:
# `tool_response.agentId` at confirmation is the SAME string this event carries,
# so the confirmed row is the join target and every contract field on it rides
# forward.
IFS='|' read -r I2_REPO I2_TR I2_SUB I2_CFG <<< "$(make_world identchain yes)"
I2_TUID="toolu_01IDENTCHAIN"
seed_roster_full "$I2_REPO" "$SID_A" "probemate" "$I2_TUID"
I2_ROSTER="$I2_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_agent_post "$SID_A" "$I2_TR" "$I2_REPO" "probemate" "$START_ID" "$I2_TUID")"
run_rec "$(mk_subagent_start "$SID_A" "$I2_TR" "$I2_REPO" "general-purpose" "$START_ID")"
I2_ROW=$(grep 'status=identified' "$I2_ROSTER" 2>/dev/null)
expect_contains "the start joins the CONFIRMED row, whose agent_id it matches" \
  "status=identified" "$I2_ROW"
expect_contains "…carrying the same transcript-form id the confirmation recorded" \
  "agent_id=$START_ID" "$I2_ROW"
expect_contains "…and the deliverable the brief contracted rides forward" \
  "deliverable=.bionic/docs/record/w1-slice1-report.md" "$I2_ROW"
expect_eq "the chain is three rows, none rewritten" \
  "3" "$(grep -c '^roster-state/v1|' "$I2_ROSTER")"

# A TEAMMATE confirmation leaves `agent_id=` empty on purpose (the launch response
# carries only the ADDRESSING form), so there is no id to join on — and until
# session-20260815 T2 that meant a teammate row was never identified at all, which
# is what left every teammate outside the landing contract.
#
# THE NAME JOIN RETURNS, SCOPED (design D2, tactical default 2). `agent_type` is
# not one field with one meaning: t1-probe-report.md §2.1 measured it carrying the
# subagent TYPE (`general-purpose`) for an async dispatch and the dispatch NAME
# (`t1mate`) for a teammate, on one live session. Wave-03 read the first half and
# removed the join for cause; the second half is the only identifying field a
# teammate payload has. So the join comes back keyed on the row's `teammate_id=`
# being non-empty — the writer's own statement of which dispatch mode the row is,
# never a sniff at the id's shape — and an async row is untouched by it.
IFS='|' read -r I2B_REPO I2B_TR I2B_SUB I2B_CFG <<< "$(make_world identteammate yes)"
I2B_TUID="toolu_01IDENTTEAM"
seed_roster_full "$I2B_REPO" "$SID_A" "probemate" "$I2B_TUID"
I2B_ROSTER="$I2B_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_agent_post_teammate "$SID_A" "$I2B_TR" "$I2B_REPO" "probemate" \
  "probemate@session-3b51bef0" "$I2B_TUID")"
run_rec "$(mk_subagent_start "$SID_A" "$I2B_TR" "$I2B_REPO" "probemate" "$START_ID")"
I2B_ROW=$(grep 'status=identified' "$I2B_ROSTER" 2>/dev/null)
expect_contains "…and the teammate row IS identified, by name" "status=identified" "$I2B_ROW"
expect_contains "…carrying the TRANSCRIPT-form id the landing verdict joins on" \
  "agent_id=$START_ID" "$I2B_ROW"
expect_contains "…while the addressing id rides forward untouched" \
  "teammate_id=probemate@session-3b51bef0" "$I2B_ROW"
expect_contains "…and so does the contract the brief declared" \
  "deliverable=.bionic/docs/record/w1-slice1-report.md" "$I2B_ROW"
expect_eq "…exactly one identified row is appended" \
  "1" "$(grep -c 'status=identified' "$I2B_ROSTER")"

# ---------- THE BADGE AT THE DOOR (session-20260815-landing-cleanup, T1) ----------
#
# The block above identifies a teammate only AFTER its PostToolUse has landed —
# that is what puts a non-empty `teammate_id=` on the row for the name join to
# scope itself to. But `teammate_id=` is written by ARM 2, and ARM 2 runs at
# PostToolUse|Agent: at the FIRST SubagentStart the row is still `intended`, with
# an empty `agent_id=` AND an empty `teammate_id=`, so the id join has no key and
# the name join has no scope. Identification could not fire at the door, only at a
# resume — which is exactly what left the predecessor wave's teammates uncontracted
# on their own live roster (step2-research-a1-a3.md §A1(3): three confirmed
# teammate rows, all `agent_id=` empty, zero sweep markers).
#
# The join therefore widens: `agent_type` against `name=` on this session's own
# rows, exact and non-empty, no `teammate_id=` precondition. The misjoin guard is
# the field's own two meanings — a teammate start carries the dispatch NAME, an
# async start carries the subagent TYPE, and a type is not a name (the paired
# negative below drives exactly that).
#
# FIXTURE FIDELITY: the teammate shapes here are the live capture's own, not
# invented — `agent_type` = the dispatch name and `agent_id` =
# `at1mate-fdaa80c4b3cb703f` for teammate `t1mate`, against `agent_type` =
# `general-purpose` and `agent_id` = `af3d9128ea3b393af` for the unnamed async
# subagent, both transcribed from the side-by-side payload table in
# .bionic/docs/record/session-20260815-landing-cleanup/step2-research-a1-a3.md
# §A1(3), which quotes the live dual-channel capture in
# record/session-20260815-landing-supervision/t1-probe-report.md:100-121.
TM_START_ID="at1mate-fdaa80c4b3cb703f"
ASYNC_START_ID="af3d9128ea3b393af"

IFS='|' read -r I2E_REPO I2E_TR I2E_SUB I2E_CFG <<< "$(make_world identdoor yes)"
seed_roster_full "$I2E_REPO" "$SID_A" "t1mate" "toolu_01DOOR"
I2E_ROSTER="$I2E_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I2E_TR" "$I2E_REPO" "t1mate" "$TM_START_ID")"
I2E_ROW=$(grep 'status=identified' "$I2E_ROSTER" 2>/dev/null)
expect_contains "the first start identifies the INTENDED row, before any PostToolUse" \
  "status=identified" "$I2E_ROW"
expect_contains "…filling the transcript-form id the by-id walls match on" \
  "agent_id=$TM_START_ID" "$I2E_ROW"
expect_contains "…on the row the dispatch named" "name=t1mate" "$I2E_ROW"
expect_contains "…with the contract the brief declared riding forward" \
  "deliverable=.bionic/docs/record/w1-slice1-report.md" "$I2E_ROW"
expect_contains "…and the correlation key the launch wrote" \
  "tool_use_id=toolu_01DOOR" "$I2E_ROW"
expect_eq "…exactly one identified row is appended" \
  "1" "$(grep -c 'status=identified' "$I2E_ROSTER")"

# THE PAIRED NEGATIVE, and the whole of the misjoin guard: an ASYNC-shaped start
# — `agent_type` carrying the subagent TYPE, `agent_id` the collapsed transcript
# form — against a NAMED intended row identifies nothing. A type is not a name,
# so the exact match simply misses; nothing on the roster is advanced by an event
# that names no row of ours.
IFS='|' read -r I2F_REPO I2F_TR I2F_SUB I2F_CFG <<< "$(make_world identasyncshape yes)"
seed_roster_full "$I2F_REPO" "$SID_A" "probemate" "toolu_01ASYNCSHAPE"
I2F_ROSTER="$I2F_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I2F_TR" "$I2F_REPO" "general-purpose" "$ASYNC_START_ID")"

# THE RESIDUAL THE WIDENING BUYS, pinned rather than left to be discovered
# (plan Assumptions A-D1). Dropping the `teammate_id=` scope means the join can no
# longer tell a teammate named `general-purpose` from an async dispatch of TYPE
# `general-purpose` — one dispatch literally named after a subagent type collides,
# and the roster's own vocabulary is the only thing that could separate them. This
# is not a new, differently-scoped join resembling a prior defect: it is the SAME
# join `47e8961` wrote and `27a8e4c` deleted, with the same predicates (name=
# equality, intended|confirmed, session-scoped) — deleted on the belief that
# `agent_type` never carries a dispatch name, a belief this wave's research
# falsified (t1-probe-report.md §2.1; see hooks/execution-recorder.sh's ARM 3
# name-join comment). It costs exactly this row, restored along with the join.
# Flipping this assertion back is a design change, not a fix.
IFS='|' read -r I2C_REPO I2C_TR I2C_SUB I2C_CFG <<< "$(make_world identasyncname yes)"
seed_roster_full "$I2C_REPO" "$SID_A" "general-purpose" "toolu_01ASYNCNAME"
I2C_ROSTER="$I2C_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I2C_TR" "$I2C_REPO" "general-purpose" "$START_ID")"
expect_contains "…and DOES identify it — the accepted A-D1 collision, name against name" \
  "status=identified" "$(cat "$I2C_ROSTER")"

# A PHANTOM start — the harness's own internal agents carry an EMPTY agent_type
# (t1 §4.6) — must not join the row whose name is empty either, and there is
# nothing else it could key on.
IFS='|' read -r I2D_REPO I2D_TR I2D_SUB I2D_CFG <<< "$(make_world identphantom yes)"
seed_roster_full "$I2D_REPO" "$SID_A" "" "toolu_01PHANTOM" confirmed "" "probe@session-3b51bef0"
I2D_ROSTER="$I2D_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I2D_TR" "$I2D_REPO" "" "a12b83613c5edc596")"

# The LATEST row wins, not the first: an id can appear on several rows of one
# session (intended → confirmed, or a resume), and the contract that belongs to
# the agent now starting is the later one.
IFS='|' read -r I3_REPO I3_TR I3_SUB I3_CFG <<< "$(make_world identlatest yes)"
seed_roster_full "$I3_REPO" "$SID_A" "twice" "toolu_01FIRST" confirmed "$START_ID"
seed_roster_full "$I3_REPO" "$SID_A" "twice" "toolu_01SECOND" confirmed "$START_ID"
I3_ROSTER="$I3_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I3_TR" "$I3_REPO" "general-purpose" "$START_ID")"
expect_contains "the join takes the LATEST row for the id" \
  "tool_use_id=toolu_01SECOND" "$(grep 'status=identified' "$I3_ROSTER")"

# ---------- the starts that are not ours to record ----------
#
# A start whose id is on no row of this session's roster is a foreign or phantom
# agent. Nothing is invented in its place — the same rule the roster arm already
# keeps for a dispatch the start gate never journalled.
IFS='|' read -r I4_REPO I4_TR I4_SUB I4_CFG <<< "$(make_world identnomatch yes)"
seed_roster_full "$I4_REPO" "$SID_A" "ours" "toolu_01OURS" confirmed "$START_ID"
I4_ROSTER="$I4_REPO/.bionic/tmp/roster-${SID_A}.state"

run_rec "$(mk_subagent_start "$SID_A" "$I4_TR" "$I4_REPO" "general-purpose" "astranger-000")"

# AN UNJOINABLE ROW IS NOT A WILDCARD. `agent_id=` is empty on every `intended`
# row, and an empty id must never match one: matching would identify a dispatch
# that has not been confirmed to exist.
IFS='|' read -r I4B_REPO I4B_TR I4B_SUB I4B_CFG <<< "$(make_world identemptyid yes)"
seed_roster_full "$I4B_REPO" "$SID_A" "ours" "toolu_01EMPTYID"
I4B_ROSTER="$I4B_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I4B_TR" "$I4B_REPO" "general-purpose" "$START_ID")"

# The PHANTOM class, verbatim from capture probe §4: these events fire with an
# EMPTY `agent_type`, and that field is no longer read at all — the id is what
# decides, so a phantom carrying an id we never dispatched joins nothing.
run_rec "$(mk_subagent_start "$SID_A" "$I4_TR" "$I4_REPO" "" "$START_ID")"
expect_contains "…and agent_type is not consulted: the id still joins its row" \
  "status=identified" "$(cat "$I4_ROSTER")"

# Nothing to identify WITH is the whole point of the row this arm writes.
run_rec "$(mk_subagent_start "$SID_A" "$I4_TR" "$I4_REPO" "general-purpose" "")"
expect_eq "…and records nothing without an id to record" \
  "1" "$(grep -c 'status=identified' "$I4_ROSTER")"

# The roster is per-session (D-5): another session's start never writes here, and
# never conjures a roster of its own.
run_rec "$(mk_subagent_start "$SID_B" "$I4_TR" "$I4_REPO" "general-purpose" "$START_ID")"
expect_eq "a foreign session's start identifies nothing of ours" \
  "1" "$(grep -c 'status=identified' "$I4_ROSTER")"

# No roster at all, and no active wave: inert on both counts, like every other
# arm of this script.
IFS='|' read -r I5_REPO I5_TR I5_SUB I5_CFG <<< "$(make_world identnoroster yes)"
run_rec "$(mk_subagent_start "$SID_A" "$I5_TR" "$I5_REPO" "orphan" "$START_ID")"

IFS='|' read -r I6_REPO I6_TR I6_SUB I6_CFG <<< "$(make_world identnowave no)"
seed_roster_full "$I6_REPO" "$SID_A" "probemate" "toolu_01NOWAVE" confirmed "$START_ID"
run_rec "$(mk_subagent_start "$SID_A" "$I6_TR" "$I6_REPO" "general-purpose" "$START_ID")"

# An `identified` row is not itself a join target: the states advance, and the
# contract a second start needs still lives on the confirmed row it came from.
run_rec "$(mk_subagent_start "$SID_A" "$I1_TR" "$I1_REPO" "general-purpose" "$START_ID")"
expect_eq "a repeated start joins the intended/confirmed row again, never an identified one" \
  "toolu_01IDENTA" \
  "$(grep 'status=identified' "$I1_ROSTER" | tail -1 | tr '|' '\n' | grep '^tool_use_id=' | cut -d= -f2-)"

# The sanitizer is the writer's, byte for byte (S-1): a platform id carrying a
# `|` would otherwise forge a field on the row this arm appends. The id is
# sanitized BEFORE it is compared, so the value matched against the roster is the
# value that was written there.
IFS='|' read -r I7_REPO I7_TR I7_SUB I7_CFG <<< "$(make_world identsanitize yes)"
seed_roster_full "$I7_REPO" "$SID_A" "probemate" "toolu_01SAN" confirmed \
  "aevil-1111 status=confirmed name=someone-else"
I7_ROSTER="$I7_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$I7_TR" "$I7_REPO" "general-purpose" \
  "aevil-1111|status=confirmed|name=someone-else")"
I7_ROW=$(grep 'status=identified' "$I7_ROSTER" 2>/dev/null)
# The pipes become spaces, so the hostile text survives INSIDE the id value and
# forges nothing: what the assertion has to test is the FIELD, not the substring.
# Every reader here splits on `|` and takes the first match for a key, so a row
# whose `name=` still reads `probemate` is a row the injection did not reach.
expect_contains "…the row still answers to the name it was joined on" \
  "|name=probemate|" "$I7_ROW"
expect_contains "…and the hostile text is confined to the id value" \
  "agent_id=aevil-1111 status=confirmed name=someone-else" "$I7_ROW"
expect_eq "…and the appended row is still one line" \
  "1" "$(grep -c 'status=identified' "$I7_ROSTER")"

# ============================================================
echo ""
echo "=== Section 11: the session key is shape-checked before it becomes a path (Step-6 S-4) ==="
# ============================================================
#
# `roster-${SID}.state` interpolates the payload's `.session_id` straight into a write path.
# The symlink guards cover `.bionic`, the state directory and the exact filenames — so a key
# carrying path separators does not trip a guard, it leaves the guarded directory. Session
# ids are harness-minted UUIDs today and nothing reaches this; but every other payload value
# on this path is sanitized, this one was not, and this script's own threat model says the
# repo is hostile. The check is the dispatch wall's, spelling for spelling.
IFS='|' read -r I8_REPO I8_TR I8_SUB I8_CFG <<< "$(make_world identtraversal yes)"
mkdir -p "$I8_REPO/.bionic/tmp/roster-x" "$I8_REPO/planted"
SID_TRAVERSAL='x/../../../planted/evil'
I8_PLANTED="$I8_REPO/planted/evil.state"
seed_roster_full "$I8_REPO" "$SID_TRAVERSAL" "probemate" "toolu_01TRAVERSE" confirmed "$START_ID"
run_rec "$(mk_subagent_start "$SID_TRAVERSAL" "$I8_TR" "$I8_REPO" "general-purpose" "$START_ID")"

# ============================================================
echo ""
echo "=== Section 12: launch-reference immutability across resume (AC-5, R6, epic-16 w2 S6) ==="
# ============================================================
#
# FIXTURE FIDELITY: this section replays the documented field sequence from
# record/w1-rc-verify-floor.md §Amendment-2 verbatim in shape — dispatch,
# a takeover authors the deliverable while the writer is presumed stalled, a
# stand-down message resumes the SAME agent id, and the resumed row's launch
# reference must still predate the takeover-authored artifact. Timestamps
# below mirror that record's own clock (dispatched ~18:30Z, amendment written
# ~18:45Z): T0 is the original dispatch, T_DELIVER is the takeover's write,
# T_RESUME is the fresh stamp a resume's own intended/confirmed cycle carries.
#
# seed_roster_at parametrizes seed_roster_full's field set (source/waiver/
# claims/cadence — the writer's CURRENT shape) by an explicit launched_at and
# tool_use_id, so the two dispatch cycles in one roster (original + resume)
# can carry different clocks under the same name and agent id.
seed_roster_at() {  # <repo> <sid> <name> <tool_use_id> <launched_at> [status] [agent-id]
  local repo="$1" sid="$2" name="$3" tuid="$4" lat="$5"
  local status="${6:-intended}" aid="${7:-}"
  local f="$repo/.bionic/tmp/roster-${sid}.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=%s|subagent_type=implementor|model=claude-sonnet-5|deliverable=.bionic/docs/record/w1-rc-verify.md|source=declared|duration=~25 minutes.|progress=.bionic/tmp/w1-rc.progress|claims=|cadence=~8m.|absent=|waiver=|tool_use_id=%s\n' \
    "$status" "$sid" "$name" "$aid" "$lat" "$tuid" >> "$f"
  return 0
}

RC_T0="2026-08-08T18:30:00Z"
RC_T_DELIVER="2026-08-08T18:40:00Z"
RC_T_RESUME="2026-08-08T19:00:00Z"
RC_NAME="w1-rc-verify"
RC_AID="aw1rcverify9c1c1c1c1c1c1c1"

# ---------- the RED replay: launch → deliver → resume ----------
IFS='|' read -r RC_REPO RC_TR RC_SUB RC_CFG <<< "$(make_world rcresume yes)"
RC_ROSTER="$RC_REPO/.bionic/tmp/roster-${SID_A}.state"

# 1. Launch — the original dispatch, at T0.
seed_roster_at "$RC_REPO" "$SID_A" "$RC_NAME" "toolu_01RCORIG" "$RC_T0"
run_rec "$(mk_agent_post "$SID_A" "$RC_TR" "$RC_REPO" "$RC_NAME" "$RC_AID" "toolu_01RCORIG")"
run_rec "$(mk_subagent_start "$SID_A" "$RC_TR" "$RC_REPO" "$RC_NAME" "$RC_AID")"
RC_FIRST_IDENT=$(grep 'status=identified' "$RC_ROSTER" 2>/dev/null | tail -1)
expect_contains "the original dispatch identifies with its own launch clock" \
  "launched_at=$RC_T0" "$RC_FIRST_IDENT"

# 2. Deliver — a takeover authors the deliverable BEFORE the resume, exactly as
# record/w1-rc-verify-floor.md §Amendment describes ("the results above are
# now doubly confirmed" — written by the orchestrator, not the resumed agent).
mkdir -p "$RC_REPO/.bionic/docs/record"
printf 'takeover-authored report\n' > "$RC_REPO/.bionic/docs/record/w1-rc-verify.md"
set_mtime_epoch "$RC_REPO/.bionic/docs/record/w1-rc-verify.md" "$(iso_to_epoch "$RC_T_DELIVER")"
RC_DELIVER_MTIME=$(file_mtime_test "$RC_REPO/.bionic/docs/record/w1-rc-verify.md")

# 3. Resume — the stand-down message wakes the SAME agent id; the field case
# shows this reaching the roster as a fresh intended/confirmed cycle stamped
# at resume time, then a fresh SubagentStart for that same id (the mechanism
# named in the S6 brief: "SubagentStart firing again for an agent id the
# roster already carries"). Nothing here is a new dispatch — same name, same
# transcript-form agent id — which is exactly what distinguishes a resume from
# the paired-negative case below.
seed_roster_at "$RC_REPO" "$SID_A" "$RC_NAME" "toolu_01RCRESUME" "$RC_T_RESUME"
run_rec "$(mk_agent_post "$SID_A" "$RC_TR" "$RC_REPO" "$RC_NAME" "$RC_AID" "toolu_01RCRESUME")"
run_rec "$(mk_subagent_start "$SID_A" "$RC_TR" "$RC_REPO" "$RC_NAME" "$RC_AID")"

RC_LAST_IDENT=$(grep 'status=identified' "$RC_ROSTER" 2>/dev/null | tail -1)
RC_LAST_CONFIRMED=$(grep 'status=confirmed' "$RC_ROSTER" 2>/dev/null | tail -1)
expect_contains "THE FIX: the resumed row still carries the ORIGINAL launch reference" \
  "launched_at=$RC_T0" "$RC_LAST_IDENT"
expect_contains "…and the confirmed row underneath it is pinned the same way" \
  "launched_at=$RC_T0" "$RC_LAST_CONFIRMED"
expect_eq "…still keyed to the SAME transcript-form agent id" \
  "1" "$(printf '%s' "$RC_LAST_IDENT" | grep -c "agent_id=$RC_AID")"
expect_eq "…and the resume's own row is still an APPEND, not a rewrite" \
  "2" "$(grep -c 'status=identified' "$RC_ROSTER" 2>/dev/null)"

# The delivered predicate itself (mtime > launched_at), computed inline rather
# than through hooks/session-sweeper.sh — that verb belongs to another file —
# but this is the exact conjunct AC-5 asks the fix to preserve: an artifact
# authored before the resume must still date after the reference the resumed
# row now carries.
RC_LAST_LAUNCHED=$(printf '%s' "$RC_LAST_IDENT" | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)
RC_LAUNCHED_EPOCH=$(iso_to_epoch "$RC_LAST_LAUNCHED")
if [ -n "$RC_DELIVER_MTIME" ] && [ -n "$RC_LAUNCHED_EPOCH" ] && [ "$RC_DELIVER_MTIME" -gt "$RC_LAUNCHED_EPOCH" ]; then
  ok "the delivered predicate holds: takeover-authored artifact postdates the resumed row's launch reference"
else
  no "the delivered predicate holds: takeover-authored artifact postdates the resumed row's launch reference" \
     "artifact mtime=$RC_DELIVER_MTIME vs launched_at epoch=$RC_LAUNCHED_EPOCH (from '$RC_LAST_LAUNCHED')"
fi

# ---------- the paired negative: a genuinely NEW agent id is not sticky ----------
#
# Immutability is keyed by AGENT ID, never by name (S6 brief) — a name
# dispatched under a DIFFERENT agent id is a different agent entirely (the
# two-stage-identity class ARM 3's own "twice" fixture in Section 10 already
# covers), and it must get its own fresh launch reference, not the first
# agent's. An artifact that predates THIS launch must still read as
# undelivered under it, however delivered it reads under the other agent's row.
IFS='|' read -r RCN_REPO RCN_TR RCN_SUB RCN_CFG <<< "$(make_world rcresumeneg yes)"
RCN_ROSTER="$RCN_REPO/.bionic/tmp/roster-${SID_A}.state"
RCN_NAME="second-worker"
RCN_AID="asecondworker9c1c1c1c1c1c1c"
RCN_T_NEW="2026-08-08T20:00:00Z"

# An artifact that already exists — old news to a BRAND NEW agent, since it
# predates a launch reference that has nothing to do with it.
mkdir -p "$RCN_REPO/.bionic/docs/record"
printf 'unrelated pre-existing artifact\n' > "$RCN_REPO/.bionic/docs/record/w1-rc-verify.md"
set_mtime_epoch "$RCN_REPO/.bionic/docs/record/w1-rc-verify.md" "$(iso_to_epoch "$RC_T_DELIVER")"
RCN_ARTIFACT_MTIME=$(file_mtime_test "$RCN_REPO/.bionic/docs/record/w1-rc-verify.md")

seed_roster_at "$RCN_REPO" "$SID_A" "$RCN_NAME" "toolu_01RCNEW" "$RCN_T_NEW"
run_rec "$(mk_agent_post "$SID_A" "$RCN_TR" "$RCN_REPO" "$RCN_NAME" "$RCN_AID" "toolu_01RCNEW")"
run_rec "$(mk_subagent_start "$SID_A" "$RCN_TR" "$RCN_REPO" "$RCN_NAME" "$RCN_AID")"

RCN_IDENT=$(grep 'status=identified' "$RCN_ROSTER" 2>/dev/null | tail -1)
expect_contains "a genuinely NEW agent id still gets its OWN fresh launch reference" \
  "launched_at=$RCN_T_NEW" "$RCN_IDENT"

RCN_LAUNCHED=$(printf '%s' "$RCN_IDENT" | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)
RCN_LAUNCHED_EPOCH=$(iso_to_epoch "$RCN_LAUNCHED")
if [ -n "$RCN_ARTIFACT_MTIME" ] && [ -n "$RCN_LAUNCHED_EPOCH" ] && [ "$RCN_ARTIFACT_MTIME" -lt "$RCN_LAUNCHED_EPOCH" ]; then
  ok "the paired negative: a pre-existing artifact reads UNMET/stale under a brand new agent's launch reference"
else
  no "the paired negative: a pre-existing artifact reads UNMET/stale under a brand new agent's launch reference" \
     "artifact mtime=$RCN_ARTIFACT_MTIME vs launched_at epoch=$RCN_LAUNCHED_EPOCH (from '$RCN_LAUNCHED')"
fi

# ---------- the confirmation-only half, isolated (ARM 2's own pin) ----------
#
# The fix lands in both arms (ARM 2's completion and ARM 3's identification):
# this isolates ARM 2 alone, confirming a resume's fresh Agent-tool completion
# is pinned even before any SubagentStart ever joins it.
IFS='|' read -r RC2_REPO RC2_TR RC2_SUB RC2_CFG <<< "$(make_world rcresumearm2 yes)"
RC2_ROSTER="$RC2_REPO/.bionic/tmp/roster-${SID_A}.state"
seed_roster_at "$RC2_REPO" "$SID_A" "$RC_NAME" "toolu_01RC2ORIG" "$RC_T0"
run_rec "$(mk_agent_post "$SID_A" "$RC2_TR" "$RC2_REPO" "$RC_NAME" "$RC_AID" "toolu_01RC2ORIG")"
seed_roster_at "$RC2_REPO" "$SID_A" "$RC_NAME" "toolu_01RC2RESUME" "$RC_T_RESUME"
run_rec "$(mk_agent_post "$SID_A" "$RC2_TR" "$RC2_REPO" "$RC_NAME" "$RC_AID" "toolu_01RC2RESUME")"
RC2_LAST_CONFIRMED=$(grep 'status=confirmed' "$RC2_ROSTER" 2>/dev/null | tail -1)
expect_contains "ARM 2 alone pins the resume's completion to the original launch reference" \
  "launched_at=$RC_T0" "$RC2_LAST_CONFIRMED"

# ============================================================
echo ""
echo "=== Section 12: THE ENGAGEMENT SWITCH (AC-6) ==="
# ============================================================
#
# Since task-engaged-session this recorder asks `engaged_session` before it asks anything
# else, and it asks NOTHING about the plan: roster journalling is what the dispatch wall's
# `intended` row is waiting for, and that fact is true before a run has a plan and still
# true after the run closes. Every silence below is paired with the write the same fixture
# produces once the marker is back, so neither half can be true by accident.

E_TUID="toolu_01ENGAGEMENTSWITCH00000"
E_AID="aengage-1111111111111111"
IFS='|' read -r E_REPO E_TR E_SUB E_CFG <<< "$(make_world engage yes)"
E_ROSTER="$E_REPO/.bionic/tmp/roster-${SID_A}.state"

# (a) ENGAGED — the positive: the intended row is completed.
seed_roster "$E_REPO" "$SID_A" "w99-engage" "$E_TUID"
run_rec "$(mk_agent_post "$SID_A" "$E_TR" "$E_REPO" "w99-engage" "$E_AID" "$E_TUID")"
expect_status "12a engaged: the dispatch is confirmed" "0" "$REC_ST"
expect_contains "12a …with a confirmed row on the roster" "status=confirmed" "$(cat "$E_ROSTER")"

# (b) THE SAME payload, the SAME roster, the marker removed -> nothing is written.
seed_roster "$E_REPO" "$SID_A" "w99-engage" "$E_TUID"
rm -f "$E_REPO/.bionic/tmp/engaged-$SID_A.state"
run_rec "$(mk_agent_post "$SID_A" "$E_TR" "$E_REPO" "w99-engage" "$E_AID" "$E_TUID")"
expect_status "12b unengaged: the same dispatch exits 0" "0" "$REC_ST"
expect_empty "12b …with no stdout" "$REC_OUT"
expect_empty "12b …and no stderr" "$REC_ERR"
expect_absent "12b …and the roster is untouched" "status=confirmed" "$(cat "$E_ROSTER")"

# (c) a SYMLINK at the marker path reads as ABSENT, never followed.
E_DECOY="$SANDBOX/engage-decoy-marker"; printf 'plan=none\n' > "$E_DECOY"
ln -s "$E_DECOY" "$E_REPO/.bionic/tmp/engaged-$SID_A.state"
run_rec "$(mk_agent_post "$SID_A" "$E_TR" "$E_REPO" "w99-engage" "$E_AID" "$E_TUID")"
expect_absent "12c a symlink at the marker path is not an engagement" "status=confirmed" "$(cat "$E_ROSTER")"
rm -f "$E_REPO/.bionic/tmp/engaged-$SID_A.state"

# (d) ANOTHER session's marker is not this session's.
: > "$E_REPO/.bionic/tmp/engaged-$SID_B.state"
run_rec "$(mk_agent_post "$SID_A" "$E_TR" "$E_REPO" "w99-engage" "$E_AID" "$E_TUID")"
expect_absent "12d another session's marker is not this session's engagement" "status=confirmed" "$(cat "$E_ROSTER")"
rm -f "$E_REPO/.bionic/tmp/engaged-$SID_B.state"

# (e) restored, the write happens exactly as in (a).
: > "$E_REPO/.bionic/tmp/engaged-$SID_A.state"
run_rec "$(mk_agent_post "$SID_A" "$E_TR" "$E_REPO" "w99-engage" "$E_AID" "$E_TUID")"
expect_contains "12e re-engaged: the row is confirmed again" "status=confirmed" "$(cat "$E_ROSTER")"

# (f) NO PLAN ON DISK, marker present: roster journalling is plan-free (AC-23). A run's
# Step 0 dispatches before it writes its plan, and a recorder that waited for one would
# leave the dispatch wall writing `intended` rows nothing ever confirms.
IFS='|' read -r E2_REPO E2_TR E2_SUB E2_CFG <<< "$(make_world engage-noplan yes)"
rm -rf "$E2_REPO/.bionic/docs"
seed_roster "$E2_REPO" "$SID_A" "w99-noplan" "$E_TUID"
: > "$E2_REPO/.bionic/tmp/engaged-$SID_A.state"
run_rec "$(mk_agent_post "$SID_A" "$E2_TR" "$E2_REPO" "w99-noplan" "$E_AID" "$E_TUID")"
expect_contains "12f engaged with no plan on disk: the row is still confirmed" \
  "status=confirmed" "$(cat "$E2_REPO/.bionic/tmp/roster-${SID_A}.state")"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "execution-recorder.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
