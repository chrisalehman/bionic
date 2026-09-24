#!/bin/bash
# Tests for hooks/execution-recorder.sh — ONE script, TWO arms (epic-15 wave-03,
# task 4/4).
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
# whole thesis of this task is that one program's output is the other's input,
# and a synthesized machine line would test the two halves apart.
#
# Usage: bash tests/execution-recorder.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"

HERE="${BIONIC_HOOKS_DIR}"
REC="$HERE/execution-recorder.sh"
OBSERVE="$HERE/stop-check.sh"

# `cd … && pwd` normalizes the path: $TMPDIR carries a trailing slash on macOS,
# and a doubled separator would slugify differently from the cwd the scripts
# under test actually see.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-recorder-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------- assertions ----------
#
# ok/no/expect_status/expect_eq/expect_empty/expect_contains/expect_absent are
# the framework's (tests/lib/assert.sh) — byte-identical semantics, verified by
# a scratch-copy before/after run under the pin (119/119 both ways, zero fails
# either side; S6 report). expect_matches was a pure rename onto expect_regex
# (same ERE-via-herestring semantics, same argument order — S1b/A-17 mapping
# table). expect_file/expect_no_file are not owned names (S1b's report lists
# them explicitly as not-owned) and stay local, unchanged.
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
# PostToolUse payloads captured live on CLI 2.1.222 for this task. Every payload
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

- Step 4: tasks in flight
PLAN
  fi
  printf '%s|%s|%s|%s\n' "$repo" "$proj/$SID_A.jsonl" "$proj/$SID_A/subagents" "$home/.claude"
}

# THE RECORDED ListAgents ANSWER — the live set (wave-roster-lifecycle S6, design ledger
# D1′). The body's shape is the real one, copied from tests/live-agents.test.sh, whose
# bodies are byte-verbatim captures: the separator is U+00B7 and `[8895ce]` is the harness
# ref suffix payload/scripts/lib/agents.sh strips. Accumulated through a `.names` sidecar so
# a second call ADDS a teammate to the one answer rather than replacing it — two agents
# planted in one session directory are two lines of one ListAgents answer, never two answers.
REC_LA_SELF='This session is bionic-fixture [fc3e2d] — the name other sessions use to message it (it is not listed below; a message to it would be a message to yourself).'
rec_live() {  # <transcript> <name>...
  local tr="$1"; shift
  local f="${tr%.jsonl}.names" names=() n body
  mkdir -p "$(dirname "$tr")"
  for n in "$@"; do printf '%s\n' "$n" >> "$f"; done
  while IFS= read -r n; do [ -n "$n" ] && names+=("$n"); done < "$f"
  body="$(live_answer_body ${names[@]+"${names[@]}"})"
  {
    jq -nc --arg ts "2026-09-05T00:50:00.000Z" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
    jq -nc --arg ts "2026-09-05T00:51:00.000Z" \
      '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01FIXTURELISTAGENTS",name:"ListAgents",input:{}}]}}'
    jq -nc --arg ts "2026-09-05T00:52:23.349Z" --arg b "$body" \
      '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01FIXTURELISTAGENTS",content:$b}]}}'
  } > "$tr"
  return 0
}

# THE SESSION ROSTER ROW, field for field from hooks/dispatch-preflight.sh's `ROW=` line,
# in the `identified` state — the state that carries the transcript-form agent id.
rec_roster_row() {  # <repo> <sid> <name> <agent-id>
  local f="$1/.bionic/tmp/roster-$2.state"
  mkdir -p "$1/.bionic/tmp"
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture status=identified session="$2" name="$3" agent_id="$4" \
    launched_at=2026-08-05T00:00:00Z >> "$f"
  return 0
}

# plant_agent <subagents-dir> <agent-id> <name> [repo]
#
# THE THREE THINGS AN OBSERVABLE AGENT NOW IS (wave-roster-lifecycle S6). Until that task
# an agent existed for hooks/stop-check.sh because its `meta.json` was on disk under a
# session's `subagents/` directory, and this helper wrote exactly that. The directory scan
# is gone: resolution reads the newest recorded ListAgents answer in the session's own
# transcript, and the agent id — which the answer does not carry, because the harness lists
# teammates by NAME — comes from a `confirmed`/`identified` roster row. So a plantable agent
# is now three records, not one:
#
#   1. the working log and metadata, at the path the id names (still read, never searched);
#   2. a line in the session's live set, which is what says it EXISTS;
#   3. a roster row carrying its id, which is what says which log is its.
#
# The transcript and the session key are derived from the directory, because that IS the
# layout: `<config>/projects/<slug>/<session>/subagents`. `repo` is passed only where a
# fixture wants the observation to resolve; withholding it plants a live agent this session
# holds no id for, which is its own refusal path.
plant_agent() {
  local dir="$1" aid="$2" aname="$3" repo="${4:-}"
  local sessdir="${dir%/subagents}" sid
  sid="${sessdir##*/}"
  printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0,"model":"opus","taskKind":"in_process_teammate"}\n' \
    "$aname" > "$dir/agent-$aid.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$dir/agent-$aid.jsonl"
  rec_live "${sessdir}.jsonl" "$aname"
  [ -n "$repo" ] && rec_roster_row "$repo" "$sid" "$aname" "$aid"
  return 0
}

STATE_REL=".bionic/tmp/stop-check.state"

# THE REAL PRODUCER, RUN FOR REAL. Its stdout — whatever it is, including nothing
# machine-readable at all — becomes the tool_response the recorder reads.
# CLAUDE_CONFIG_DIR is what hooks/stop-check.sh resolves its metadata root
# through, so the fixture world is reachable without touching $HOME.
OBS_OUT=""; OBS_ST=0
run_observation() {  # <sid> <config-dir> <repo> <args…>
  local sid="$1" cfg="$2" repo="$3"; shift 3
  # CLAUDE_CODE_SESSION_ID IS PINNED TO THE FIXTURE'S OWN SESSION, and pinned it must be:
  # this suite runs inside a real Claude Code session that exports a real key, and an
  # unpinned observation would resolve against whichever session happens to run the suite.
  #
  # It used to be pinned EMPTY, on the reasoning that no fixture here set up a roster and so
  # the answer was always the UNKNOWN classification. Since wave-roster-lifecycle S6 that
  # reasoning is gone with the verdict: the key is how stop-check.sh finds the transcript
  # carrying the live set AND the roster carrying the agent id, so an empty key resolves
  # nothing at all and the producer prints no machine line for the recorder to copy.
  OBS_OUT=$(cd "$repo" && CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="$sid" \
    bash "$OBSERVE" "$@" 2>/dev/null); OBS_ST=$?
  return 0
}

# observe <sid> <cfg> <repo> <transcript> <args…> — producer then recorder, end to end
observe() {
  local sid="$1" cfg="$2" repo="$3" tr="$4"; shift 4
  run_observation "$sid" "$cfg" "$repo" "$@"
  run_rec "$(mk_bash_post "$sid" "$tr" "$repo" "bash ~/.claude/hooks/stop-check.sh $*" "$OBS_OUT")"
}

# ============================================================
section "Section 1: the hot path — relevance before the expensive work (checklist A7)"
# ============================================================

IFS='|' read -r W1_REPO W1_TR W1_SUB W1_CFG <<< "$(make_world w1 yes)"
plant_agent "$W1_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer" "$W1_REPO"

run_rec "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PostToolUse", tool_name:"Read", tool_input:{file_path:"/tmp/x"}, tool_response:{}}')"

run_rec "$(mk_bash_post "$SID_A" "$W1_TR" "$W1_REPO" "ls -la && git status" "README.md")"

# Static order pin: the cheap relevance test must PRECEDE the expensive work in
# the source, not merely produce the same answer (arch-perf F8/F9 — the defect
# was cost, which behaviour alone cannot detect). This script is registered on
# every Bash call in the session, so the resolution on the unrelated path is the
# whole cost.
#
# THE PLAN WALK IS GONE, AND THAT IS WHY THIS PIN CHANGED SHAPE (S11, AC-16).
# The comment here used to name `PLAN=`/`for d in "$DOCS_ROOT` as the expensive
# thing the relevance test had to precede, and derived a `_walk_line` from it —
# a grep that has matched NOTHING in this file since the run predicate was
# removed (`THE RUN PREDICATE IS GONE — ENGAGEMENT SCOPES THIS HOOK`). The line
# number it computed was the empty string, so the comparison the section
# describes could never have been written against it. What this script actually
# spends on an unrelated Bash call today is the git resolution and, below the
# pressure sample, the state-path resolution, the symlink guards and the roster
# read — so those are what the order pin names.
# RE-POINTED AGAIN (epic-23 wave-15, REQ-2). The cheap relevance test WAS the machine-line
# grep over the tool's whole stdout; the observation record is deleted and a Bash payload now
# reaches the pressure sample and leaves. What still has to come before the git resolution is
# the arm dispatch itself — the read that decides which of the two remaining arms, if either,
# this payload belongs to.
_rel_line=$(grep -n '^IS_START=""' "$REC" | head -1 | cut -d: -f1)
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f): the git resolution is `bionic_context`'s
# now, and the literal this line greps for is the call rather than the assignment it
# replaced. The `expect_nonempty` below is what stops the same silent-empty failure this
# section's own comment records — it is the reason the grep literal is re-pointed rather
# than deleted.
_root_line=$(grep -n '^bionic_context' "$REC" | head -1 | cut -d: -f1)
# THE CODE, NOT ITS BANNER (S11). This first read the `THE EARLY EXIT, RESTORED`
# comment, and a planted regression that MOVED the exit block below the state
# paths left the banner where it was and the pin stayed green. A source-order pin
# has to grep the line that runs.
_exit_line=$(grep -nF 'if [ -z "$IS_START" ] && [ "$TOOL_NAME" = "Bash" ]; then' "$REC" | head -1 | cut -d: -f1)
_state_line=$(grep -n 'STATE_DIR="$BIONIC_ROOT/.bionic/tmp"' "$REC" | head -1 | cut -d: -f1)

# Every line number is asserted non-empty BEFORE it is compared: a grep that
# finds nothing yields the empty string, and `test "" -lt ""` is an error rather
# than a comparison — an order pin over two empty values pins nothing, which is
# exactly what this section had.
expect_nonempty "the cheap relevance test is findable in the recorder's source (the arm dispatch)" "$_rel_line"
expect_nonempty "the git resolution is findable in the recorder's source (bionic_context)" "$_root_line"
expect_nonempty "the restored early exit is findable in the recorder's source" "$_exit_line"
expect_nonempty "the state-path resolution is findable in the recorder's source" "$_state_line"
expect_true "the relevance test PRECEDES the git resolution, not merely in effect" \
  test "$_rel_line" -lt "$_root_line"
expect_true "the early exit PRECEDES the state paths, the symlink guards and the roster read" \
  test "$_exit_line" -lt "$_state_line"

# The plan walk really is absent — asserted, not assumed, and paired with the
# same grep over a script that DOES walk, so "no match" cannot mean "the pattern
# is broken".
_walk_pat='^[[:space:]]*(PLAN=|for d in "\$DOCS_ROOT)'
expect_empty "the recorder walks no plan directory at all (the run predicate is gone)" \
  "$(grep -nE "$_walk_pat" "$REC" | head -1)"
expect_nonempty "…and the same pattern DOES find the walk in a hook that walks (not a broken pattern)" \
  "$(grep -nE "$_walk_pat" "$HERE/dispatch-preflight.sh" | head -1)"

# Outside an active wave the script is inert, like every other gate in this
# family (spec §Component boundaries: "Inert when no wave is active").
#
# THE ROSTER ROW IS PLANTED HERE TOO (S11). Until this task the nowave world
# planted an agent WITHOUT its roster row, so the observation resolved nothing
# and the world would have recorded nothing whether a wave was active or not:
# the inertness this section names was never the reason for the silence. With
# the row planted, the only difference between this world and the paired
# positive below is the active wave.
# THE INERTNESS CLAIM MOVED TO THE ARM THAT STILL WRITES (epic-23 wave-15, REQ-2). It was
# driven here on the Bash channel — an observation outside an active wave recorded nothing —
# and that channel writes nothing at all now, so the assertion would pass just as loudly on a
# recorder that had stopped working entirely. Section 12 carries it: (a) and (b) are the same
# dispatch over the same roster, differing only in the engagement marker, and the scope this
# family shares is engagement rather than the plan.

# ============================================================
setup_section "Sections 2-5: THE OBSERVATION RECORD IS GONE (epic-23 wave-15, REQ-2; ADR-028)"
# ============================================================
#
# Four sections drove the arm this script no longer has: that a run of hooks/stop-check.sh
# produced a record (§2), that a refused or mistyped one produced none (§3), that the record
# named its observer (§4), and that the file was versioned, key-addressed and bounded (§5).
#
# The record existed for one reader, hooks/stop-guard.sh, which spent it to admit a stop. That
# gate takes its own look now — `observe_agent` in payload/scripts/lib/observe.sh, in process,
# at the instant of the stop — because a record is a claim about a PAST look and the wall was
# refusing correct stops on the strength of one nobody had taken (2026-09-15; ADR-028). With
# no reader there is nothing to write, and one writer of a state nobody reads is a state that
# should not exist.
#
# WHAT CARRIES THESE CLAIMS FORWARD. tests/stop-guard.test.sh §5 drives the look itself, over
# the same worlds these sections built; tests/stop-check.test.sh §7 still pins the machine
# line the verb prints for a reader's own eyes. What is NOT carried forward is anything about
# a record's provenance, freshness or ownership — those questions are answered by construction
# once the reader takes its own look.

# ============================================================
section "Section 6: the roster arm — intended → confirmed (AC-1, confirmation half)"
# ============================================================

TUID="toolu_01QhBXwHyZfMQNmS571fqmg8"
NEW_AID="a26bd30bf8616411b"

# The intended row EXACTLY as hooks/dispatch-preflight.sh writes it (task 4/3,
# schema roster-state/v1 — the field order and header are that script's).
seed_roster() {  # <repo> <sid> <name> <tool_use_id>
  local repo="$1" sid="$2" name="$3" tuid="$4"
  mkdir -p "$repo/.bionic/tmp"
  {
    roster_header
    roster_row_fixture status=intended session="$sid" name="$name" agent_id= \
      launched_at=2026-08-05T12:00:00Z model= deliverable=.bionic/docs/record/w99.txt \
      duration='~25 minutes.' progress=.bionic/tmp/w99.progress tool_use_id="$tuid"
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

# ---------- the TEAMMATE payload shape (AC-10, epic-16 wave-01 task 0) ----------
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
# transcript-form id arrives later, from SubagentStart (task 1's `identified`
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
section "Section 7: hostile repo (AC-8, TDD §8, checklist A2/A3)"
# ============================================================

# Predictable temp names + symlink-following writes were a PROVEN arbitrary-file
# overwrite in the discarded run (corr-sec S1/S2). Every level is replanted.
# THE CONTROL WORLD FIRST (S11, AC-16). Every assertion in this section is an
# ABSENCE — a file outside the repo that still holds its original bytes, a
# directory outside the repo that stayed empty — and an absence over a drive that
# resolved nothing is not a guard, it is silence. This world is the hostile ones
# with the hostile part left out: same builder, same agent, same observation, a
# real `.bionic/tmp`. It has to record, or none of the refusals below mean
# anything.
#
# THE HOSTILE WORLDS THAT GUARDED THE OBSERVATION RECORD ARE GONE WITH IT (epic-23 wave-15,
# REQ-2). Three of them stood here — a control that recorded, a symlinked state FILE and a
# symlinked state DIRECTORY, each asserting that a repo cannot redirect this script's write
# outside itself. The write they guarded does not happen any more. What this script still
# writes is the ROSTER row, and the two levels of that path — the state directory and the
# roster file itself — are what the worlds below drive.
#
# THE DIRECTORY LEVEL, on the arm that still writes. A repo that points `.bionic/tmp` at a
# directory outside itself must not have this script append a confirmation row there.
IFS='|' read -r S2_REPO S2_TR S2_SUB S2_CFG <<< "$(make_world sec2 yes)"
OUTSIDE_DIR="$SANDBOX/sec2-outside-dir"
mkdir -p "$OUTSIDE_DIR"
seed_roster "$SANDBOX/sec2-seed" "$SID_A" "w99-impl" "$TUID"
cp "$SANDBOX/sec2-seed/.bionic/tmp/roster-${SID_A}.state" "$OUTSIDE_DIR/roster-${SID_A}.state"
: > "$OUTSIDE_DIR/engaged-$SID_A.state"
OUTSIDE_BEFORE="$(cat "$OUTSIDE_DIR/roster-${SID_A}.state")"
rm -rf "$S2_REPO/.bionic/tmp"
ln -s "$OUTSIDE_DIR" "$S2_REPO/.bionic/tmp"
run_rec "$(mk_agent_post "$SID_A" "$S2_TR" "$S2_REPO" "w99-impl" "$NEW_AID" "$TUID")"
expect_eq "a symlinked state DIRECTORY is not written through — the roster outside keeps its bytes" \
  "$OUTSIDE_BEFORE" "$(cat "$OUTSIDE_DIR/roster-${SID_A}.state" 2>/dev/null)"
expect_status "…and the arm still exits 0 rather than failing loudly" "0" "$REC_ST"

# The roster path gets the same treatment: a symlinked roster is never appended# The roster path gets the same treatment: a symlinked roster is never appended
# through, so a hostile repo cannot turn a dispatch into a write anywhere it likes.
# THE FILE OUTSIDE IS A PLAUSIBLE ROSTER, not a line of prose (S11). It used to
# hold `ROSTER ORIGINAL`, which carries no row this dispatch could complete — so
# the fold found nothing to write and the assertion below would have held with
# every symlink guard in this script removed. A hostile repo pointing its roster
# at a file outside the repo points it at something that looks like a roster; the
# victim is seeded with the very `intended` row this payload confirms, so
# "not appended through" is a claim about the guard and not about the join.
IFS='|' read -r S3_REPO S3_TR S3_SUB S3_CFG <<< "$(make_world sec3 yes)"
mkdir -p "$S3_REPO/.bionic/tmp" "$SANDBOX/sec3-victim-seed"
seed_roster "$SANDBOX/sec3-victim-seed" "$SID_A" "w99-impl" "$TUID"
ROSTER_VICTIM="$SANDBOX/sec3-victim-seed/.bionic/tmp/roster-${SID_A}.state"
ROSTER_VICTIM_BEFORE="$(cat "$ROSTER_VICTIM")"
ln -s "$ROSTER_VICTIM" "$S3_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_agent_post "$SID_A" "$S3_TR" "$S3_REPO" "w99-impl" "$NEW_AID" "$TUID")"
expect_eq "a symlinked ROSTER is not appended through — the file outside keeps its bytes" \
  "$ROSTER_VICTIM_BEFORE" "$(cat "$ROSTER_VICTIM" 2>/dev/null)"
expect_absent "…so no confirmation row reaches it" "status=confirmed" "$(cat "$ROSTER_VICTIM" 2>/dev/null)"
expect_status "…and the roster arm still exits 0 rather than failing loudly" "0" "$REC_ST"

# The control for that absence: the SAME dispatch payload against a repo whose
# roster is a real file writes the row. Without this the assertion above passes
# on any recorder that has stopped writing rosters entirely.
IFS='|' read -r S3OK_REPO S3OK_TR S3OK_SUB S3OK_CFG <<< "$(make_world sec3ok yes)"
seed_roster "$S3OK_REPO" "$SID_A" "w99-impl" "$TUID"
run_rec "$(mk_agent_post "$SID_A" "$S3OK_TR" "$S3OK_REPO" "w99-impl" "$NEW_AID" "$TUID")"
expect_contains "the control: a REAL roster does get the confirmation row appended" \
  "status=confirmed" "$(cat "$S3OK_REPO/.bionic/tmp/roster-${SID_A}.state" 2>/dev/null)"

# THE FORGED-MACHINE-LINE WORLD IS GONE WITH THE ARM THAT READ ONE (epic-23 wave-15, REQ-2).
# Four cases stood here: a well-formed line was stored, a non-numeric mtime was not, a log
# outside this session's subagents directory was not, and neither was the id that came with
# it. All four were about a record this script no longer writes, and the residual they
# managed — stdout is not a trusted channel — is closed at its root rather than narrowed,
# because nothing reads stdout any more.

# ============================================================
section "Section 8: it never blocks, whatever happens (PostToolUse invariant)"
# ============================================================
#
# PostToolUse cannot block — the tool has already run — so every path must exit
# 0. The lock is the one place a naive implementation spins forever: `mkdir`
# fails for reasons no reclaim can fix (an unwritable state directory is
# repo-controlled) and `rm -rf` of an ABSENT path SUCCEEDS.
run_bounded() {  # <secs> <payload> -> sets BOUNDED_ST (137 = killed)
  local secs="$1" payload="$2" waited=0 pid _sid
  # THE ENVIRONMENT AGREES WITH THE PAYLOAD, for run_rec's reason and with its
  # spelling (S11). Without the pin this driver left the RUNNER's own
  # CLAUDE_CODE_SESSION_ID in the environment, the hook took that key as primary,
  # and the engagement marker this world plants for the fixture session did not
  # match it — so every bounded drive exited at the engagement switch and the
  # lock below it was never reached by this section at all.
  _sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  printf '%s' "$payload" | env CLAUDE_CODE_SESSION_ID="$_sid" bash "$REC" \
    >"$SANDBOX/.bout" 2>"$SANDBOX/.berr" &
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

# THE LOCK IS GONE WITH THE RECORD IT SERIALIZED (epic-23 wave-15, REQ-2). This world drove
# the one place a naive implementation spins forever — `mkdir` fails for reasons no reclaim
# can fix, and `rm -rf` of an absent path succeeds — and the read-modify-write it protected
# was the observation record's. The roster arm has never taken a lock (a single O_APPEND
# write of well under a pipe buffer), so there is no wait left in this script to bound. The
# bounded driver above stays: the malformed-payload rows below still use it, and it is what
# proves this hook terminates on a payload shape nobody planned for.

# Malformed payloads: this script is fed by the platform, and a shape it does not
# expect must be inert rather than fatal. Each one is asserted: PostToolUse cannot
# block, so the exit status IS the invariant, and five drives that nobody looked
# at were five chances for this script to start exiting non-zero unnoticed.
for bad_payload in \
  '{}' \
  '{"tool_name":"Bash"}' \
  '{"tool_name":"Bash","tool_response":"error: command failed"}' \
  '{"tool_name":"Agent","tool_response":{}}' \
  'not json at all'
do
  run_rec "$bad_payload"
  expect_status "a malformed payload is inert, not fatal: $bad_payload" "0" "$REC_ST"
  expect_empty "…and it blocks nothing on stdout either: $bad_payload" "$REC_OUT"
done

# ============================================================
section "Section 9: six-axis review remediations (S-1 sanitizer parity, S-2 log existence, P roster bound)"
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
${ROSTER_ROW_SCHEMA}"
run_rec "$(mk_agent_post "$SID_A" "$S1_TR" "$S1_REPO" "w99-impl" "$S1_EVIL" "$TUID")"
expect_eq "a newline in the platform's agentId cannot split the row it writes" \
  "2" "$(grep -c "^${ROSTER_ROW_SCHEMA}|" "$S1_ROSTER" 2>/dev/null)"
expect_contains "…the id is normalized into the row instead, as the writer would" \
  "agent_id=aevil-3333333333333333 ${ROSTER_ROW_SCHEMA}|" "$(cat "$S1_ROSTER" 2>/dev/null)"

# S-1's OBSERVATION HALF AND S-2 ARE GONE WITH THE RECORD (epic-23 wave-15, REQ-2). The
# sanitizer parity above was asserted twice, once per artifact this script wrote: the roster
# row (immediately above, and still driven) and the observation record. S-2 was the
# log-existence guard that closed the match-by-zero forgery — a line carrying `mtime=0|size=0`
# matched a gate reading a log that was not on disk. Neither artifact exists; the gate stats
# the log itself now, so there is no line to forge and no zero to match.

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
roster_row_fixture status=intended session="$SID_A" name=live-one agent_id= \
  launched_at=2026-08-05T12:00:00Z model= progress=.bionic/tmp/live-one.progress \
  cadence='~6m.' tool_use_id=toolu_LIVEONE >> "$PR_ROSTER"
{
  _i=0
  while [ "$_i" -lt 3000 ]; do
    roster_row_fixture status=confirmed session="$SID_A" name="old-$_i" \
      agent_id="aold-$_i" launched_at=2026-08-05T00:00:00Z tool_use_id="toolu_OLD$_i"
    _i=$((_i + 1))
  done
} >> "$PR_ROSTER"
PR_BEFORE=$(grep -c "^${ROSTER_ROW_SCHEMA}|" "$PR_ROSTER" 2>/dev/null || echo 0)

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
  "$((PR_BEFORE + 1))" "$(grep -c "^${ROSTER_ROW_SCHEMA}|" "$PR_ROSTER" 2>/dev/null || echo 0)"
expect_contains "the row this event confirmed is appended" \
  "agent_id=$NEW_AID" "$(grep 'status=confirmed|.*name=w99-impl|' "$PR_ROSTER" 2>/dev/null)"
PR_LIVE=$(grep 'name=live-one|' "$PR_ROSTER" 2>/dev/null)
# A roster under the bound is still append-only: nothing is rewritten, and the
# intended row it completes stays exactly where the launch put it.

# ============================================================
section "Section 10: the identification arm — SubagentStart → identified (AC-2, epic-16 w1 task 1)"
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
  # THE LAUNCH STAMP, overridable by `SEED_LAUNCHED_AT` for the one case that needs a relaunch
  # dated after an ack (T22-dup, re-authored at epic-23 wave-20 T20): the close predicate
  # compares the two stamps, so a relaunch carrying the first launch's stamp would read closed.
  local la="${SEED_LAUNCHED_AT:-2026-08-08T09:00:00Z}"
  local f="$repo/.bionic/tmp/roster-${sid}.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || roster_header > "$f"
  # `teammate_id=` is PRESENT-IF-PASSED, which is the writer's own rule and the reason the
  # optional field can be added by naming it rather than by appending a segment by hand.
  if [ -n "$tid" ]; then
    roster_row_fixture status="$status" session="$sid" name="$name" agent_id="$aid" \
      launched_at="$la" model=claude-opus-5 \
      deliverable=.bionic/docs/record/w1-slice1-report.md duration='~25 minutes.' \
      progress=.bionic/tmp/w1-s1-progress.md cadence='~8m.' teammate_id="$tid" \
      tool_use_id="$tuid" >> "$f"
  else
    roster_row_fixture status="$status" session="$sid" name="$name" agent_id="$aid" \
      launched_at="$la" model=claude-opus-5 \
      deliverable=.bionic/docs/record/w1-slice1-report.md duration='~25 minutes.' \
      progress=.bionic/tmp/w1-s1-progress.md cadence='~8m.' tool_use_id="$tuid" >> "$f"
  fi
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
# Task 2's verdict verb folds the roster to the LATEST row per name and reads
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

# ---------- T22: A SECOND START FOR ONE ID IS RECORDED, NOT REFUSED ----------
#
# (T22, A-orch-33.) One agent id that starts twice in one session is a RESUMED COPY: the
# harness loses the agent table across a `/clear` but keeps the teammate table, so a
# SendMessage or a resume aimed at a transcript id brings up a second process against a
# contract the first is still working. The roster is the identity register, and this is the
# register noticing.
#
# WHY IT IS A RECORD AND NOT A WALL, measured rather than assumed. The installed CLI's own
# hook-event contract for this event reads, verbatim:
#     SubagentStart … Exit code 0 - JSON additionalContext shown to subagent
#                     Exit code 2 - show stderr to user only
#                     Other exit codes - show stderr to user only
# and the binary's hookSpecificOutput switch consumes only `additionalContext` for
# SubagentStart — there is no `permissionDecision` branch for it, as there is for
# PreToolUse. A SubagentStart hook cannot block. So the second start is journalled
# `status=duplicate-start` and the Patrol tick is what names it; the door that CAN close
# is the dispatch wall's name-in-flight arm, one event earlier.
#
# IT IS ADDITIVE. Before this, a second start for an already-`identified` id joined nothing
# at all — the id loop accepts `intended|confirmed` only — and exited silently. The silence
# is what is replaced.

IFS='|' read -r ID_REPO ID_TR ID_SUB ID_CFG <<< "$(make_world identdup yes)"
seed_roster_full "$ID_REPO" "$SID_A" "probemate" "toolu_01IDENTDUP" confirmed "$START_ID"
ID_ROSTER="$ID_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$ID_TR" "$ID_REPO" "general-purpose" "$START_ID")"
expect_eq "T22-dup: the FIRST start identifies, exactly once" \
  "1" "$(grep -c 'status=identified' "$ID_ROSTER")"
expect_eq "…and records no duplicate" \
  "0" "$(grep -c 'status=duplicate-start' "$ID_ROSTER")"

run_rec "$(mk_subagent_start "$SID_A" "$ID_TR" "$ID_REPO" "general-purpose" "$START_ID")"
ID_DUP=$(grep 'status=duplicate-start' "$ID_ROSTER" 2>/dev/null)
expect_contains "T22-dup: a SECOND start for the same id is journalled as a duplicate" \
  "status=duplicate-start" "$ID_DUP"
expect_contains "…carrying the id that started twice" "agent_id=$START_ID" "$ID_DUP"
expect_contains "…and the name the contract was dispatched under" "name=probemate" "$ID_DUP"
expect_eq "…and it does not identify a second time" \
  "1" "$(grep -c 'status=identified' "$ID_ROSTER")"

# THE EXIT IS STILL ZERO. This hook cannot block and must not pretend to: a non-zero exit
# here would put stderr in front of the human for a condition only the tick can act on.
expect_eq "T22-dup: the recorder still exits 0 — a start hook cannot block" "0" "$REC_ST"

# THE CONTROL — RE-AUTHORED (epic-23 wave-20 T20, REQ-10, D10; found by T17, approved by
# Chris). It read "a row CLOSED by a MET marker is a finished lineage, and a start against
# it records no duplicate". The recorder was the last roster reader but one that closed a
# name on a `landing-swept/v1|state=MET` marker alone; it now asks the one close predicate,
# `roster_open_names` (payload/scripts/lib/roster.sh): a name is closed by an ack stamped
# after its latest launch, and by nothing else (ADR-034 d1). A MET marker records that a
# landing was SEEN, not that the agent left, so a second start behind one is a resumed copy
# against a contract nobody has closed. The claim the control came for is unchanged — a
# start against a FINISHED lineage is a name being reused and is not journalled — and the
# finish is now the ack. Both halves are pinned: the marker alone journals (the reading that
# changed), and an ack after launch does not (the control, kept).
ack_write() {  # <repo> <sid> <at> <name> — the sweeper ledger's ack line, in its writer's shape
  local le="$1/.bionic/tmp/sweeper-$2.state"
  [ -f "$le" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$le"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
    "$3" "$2" "$4" >> "$le"
}
IFS='|' read -r IDM_REPO IDM_TR IDM_SUB IDM_CFG <<< "$(make_world identdupmet yes)"
seed_roster_full "$IDM_REPO" "$SID_A" "probemate" "toolu_01IDENTDUPM" confirmed "$START_ID"
IDM_ROSTER="$IDM_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$IDM_TR" "$IDM_REPO" "general-purpose" "$START_ID")"
swept_marker_write "$IDM_ROSTER" 2026-08-08T09:30:00Z "$SID_A" probemate "$START_ID" MET
run_rec "$(mk_subagent_start "$SID_A" "$IDM_TR" "$IDM_REPO" "general-purpose" "$START_ID")"
expect_eq "T20: a start behind a MET marker with no ack IS journalled — the marker closes nothing" \
  "1" "$(grep -c 'status=duplicate-start' "$IDM_ROSTER")"

IFS='|' read -r IDC_REPO IDC_TR IDC_SUB IDC_CFG <<< "$(make_world identdupclosed yes)"
seed_roster_full "$IDC_REPO" "$SID_A" "probemate" "toolu_01IDENTDUPC" confirmed "$START_ID"
IDC_ROSTER="$IDC_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$IDC_TR" "$IDC_REPO" "general-purpose" "$START_ID")"
swept_marker_write "$IDC_ROSTER" 2026-08-08T09:30:00Z "$SID_A" probemate "$START_ID" MET
ack_write "$IDC_REPO" "$SID_A" 2026-08-08T09:31:00Z probemate
run_rec "$(mk_subagent_start "$SID_A" "$IDC_TR" "$IDC_REPO" "general-purpose" "$START_ID")"
expect_eq "T22-dup: a start against a lineage acked after its launch records no duplicate (T20: the ack closes, not the marker)" \
  "0" "$(grep -c 'status=duplicate-start' "$IDC_ROSTER")"

# ---------- T20b: A RESTART AFTER AN ACK GETS A FRESH LAUNCH STAMP (review R5) ----------
#
# The control above proves the restart is not journalled a duplicate — a name closed by an
# ack is a finished lineage, and a start against it is a reused name, identified afresh. Until
# this fix the fresh identification still carried the ORIGINAL launch forward:
# `prior_launch_for_agent` finds the FIRST row on the roster for this id, which is the very
# lineage the ack just closed, and substitutes ITS `launched_at` into the new row. So the
# "fresh" row read exactly as old as the one the ack had already discharged, and
# `roster_open_names` kept reading the name closed — the restarted agent held no slot at all
# (walk §9b/9c; review R5). The fix stamps this one case — a start whose DUP_PRIOR reading
# was reset because the name was found CLOSED, not a start that was never a duplicate reading
# to begin with — with the event's OWN time, so the reused lineage reads open again.
open_names_of() {  # <roster> <ledger> <sid> -> roster_open_names, sourced in a private subshell
  bash -c '. "$1"; shift; roster_open_names "$@"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh" "$@"
}
IDC_LEDGER="$IDC_REPO/.bionic/tmp/sweeper-${SID_A}.state"
expect_eq "T20b: the restart identifies a second time" \
  "2" "$(grep -c 'status=identified' "$IDC_ROSTER")"
IDC_LA2=$(grep 'status=identified' "$IDC_ROSTER" | tail -1 | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)
expect_regex "T20b: …and its launch stamp is well-formed" \
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$IDC_LA2"
# RE-AUTHORED (epic-23 wave-20 T20c, critic C2-2). T20b put the fresh stamp in `launched_at`,
# and `launched_at` is ALSO the clock the sweeper dates the deliverable against: a contract met
# before the ack then read UNMET for good, and `stopped` closed a landed row `abandoned`.
# Occupancy and the contract are two questions, so they are two fields now. `launched_at` stays
# the contract's launch, carried forward as it was before T20b; the restart's own time rides
# `restarted_at=`, which `roster_open_names` reads for occupancy and no contract reader reads.
expect_eq "T20c: the restart row keeps the contract's launch (T20c: was \"T20b: …and it is NOT the original launch carried forward\", expect_ne on launched_at)" \
  "2026-08-08T09:00:00Z" "$IDC_LA2"
IDC_RA2=$(grep 'status=identified' "$IDC_ROSTER" | tail -1 | tr '|' '\n' | grep '^restarted_at=' | cut -d= -f2-)
expect_regex "T20c: …and carries the restart's own time as a well-formed restarted_at" \
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$IDC_RA2"
if [[ "$IDC_RA2" > "2026-08-08T09:31:00Z" ]]; then IDC_RA2_FRESH=yes; else IDC_RA2_FRESH=no; fi
expect_eq "T20c: …strictly later than the ack that had closed the name (T20c: was \"T20b: …and it is strictly later than the ack that had closed the name\", on launched_at)" \
  "yes" "$IDC_RA2_FRESH"
expect_eq "T20c: …exactly one restarted_at on the row (a by-key reader takes the first)" \
  "1" "$(grep 'status=identified' "$IDC_ROSTER" | tail -1 | tr '|' '\n' | grep -c '^restarted_at=')"
expect_contains "T20b: …so roster_open_names counts the restarted agent again" \
  "probemate" "$(open_names_of "$IDC_ROSTER" "$IDC_LEDGER" "$SID_A")"
# THE PAIRED NEGATIVE: the FIRST identification of the same id is no restart and carries no
# restarted_at, so the field marks exactly the case the ack had closed.
expect_eq "T20c: the first identification of the id carries no restarted_at" \
  "0" "$(grep 'status=identified' "$IDC_ROSTER" | head -1 | tr '|' '\n' | grep -c '^restarted_at=')"

# ---------- T20d: A RESTART AFTER AN EXTEND CARRIES THE EXTENDED LAUNCH (critic C3-1) ----------
#
# `hooks/session-poker.sh`'s `extend` verb re-opens a MET row by appending a FRESH row for
# the SAME id, "launched now, so the old deliverable reads stale" (session-poker.sh, the
# `extend` verb's own comment). Until this fix `prior_launch_for_agent` — which restart used
# unconditionally — answers the id's EARLIEST launched_at, so a restart after that EXTENDED
# contract's own ack rolled `launched_at` back past the extend, to the ORIGINAL dispatch:
# a contract the extend had revoked (its stale deliverable predates the bumped launch) read
# met again by that same stale deliverable, with acked=no — a tree `stopped` had left
# standing for salvage becomes landable again. The world: the confirmed seed row is the
# first dispatch (09:00Z); the extend is a fresh `identified` row for the SAME id, the shape
# `session-poker.sh extend` writes (row_copy_args carries `status=identified` forward
# unchanged); the ack is taken after the extend's own launch, not the first dispatch's.
IFS='|' read -r IDX_REPO IDX_TR IDX_SUB IDX_CFG <<< "$(make_world identextend yes)"
seed_roster_full "$IDX_REPO" "$SID_A" "probemate" "toolu_01IDENTEXT" confirmed "$START_ID"
IDX_ROSTER="$IDX_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$IDX_TR" "$IDX_REPO" "general-purpose" "$START_ID")"
# THE EXTEND, in `session-poker.sh`'s own row shape: a fresh `identified` row for the SAME
# id, launched later, with its `extended=<iso> <reason>` audit key.
roster_row_fixture status=identified session="$SID_A" name=probemate agent_id="$START_ID" \
  launched_at=2026-08-08T09:15:00Z subagent_type=implementor model=opus deliverable= \
  source=declared duration= progress= claims= cadence= absent= waiver= \
  tool_use_id=toolu_01IDENTEXT plan=none "extended=2026-08-08T09:15:00Z retry" \
  >> "$IDX_ROSTER"
ack_write "$IDX_REPO" "$SID_A" 2026-08-08T09:31:00Z probemate
run_rec "$(mk_subagent_start "$SID_A" "$IDX_TR" "$IDX_REPO" "general-purpose" "$START_ID")"
IDX_LA3=$(grep 'status=identified' "$IDX_ROSTER" | tail -1 | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)
expect_eq "T20d: a restart after an extend's ack carries the EXTENDED launch, not the first dispatch's (critic C3-1)" \
  "2026-08-08T09:15:00Z" "$IDX_LA3"
IDX_RA3=$(grep 'status=identified' "$IDX_ROSTER" | tail -1 | tr '|' '\n' | grep '^restarted_at=' | cut -d= -f2-)
expect_regex "T20d: …and the restart still carries its own restarted_at, occupancy unaffected by the fix" \
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$IDX_RA3"
# THE PAIRED CONTROL: an extend with NO ack afterward is not a restart at all — the name is
# still open, so DUP_PRIOR is never reset and the fix's `if RESTART_AFTER_ACK` never fires. A
# further start against it is an ordinary live duplicate, journalled verbatim (no new
# `identified` row, no PRIOR_LAUNCH of any kind computed) — proving the fix reaches the
# RESTART_AFTER_ACK path only, not every id with more than one row.
IFS='|' read -r IDX2_REPO IDX2_TR IDX2_SUB IDX2_CFG <<< "$(make_world identextendnoack yes)"
seed_roster_full "$IDX2_REPO" "$SID_A" "probemate" "toolu_01IDENTEXT2" confirmed "$START_ID"
IDX2_ROSTER="$IDX2_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$IDX2_TR" "$IDX2_REPO" "general-purpose" "$START_ID")"
roster_row_fixture status=identified session="$SID_A" name=probemate agent_id="$START_ID" \
  launched_at=2026-08-08T09:15:00Z subagent_type=implementor model=opus deliverable= \
  source=declared duration= progress= claims= cadence= absent= waiver= \
  tool_use_id=toolu_01IDENTEXT2 plan=none "extended=2026-08-08T09:15:00Z retry" \
  >> "$IDX2_ROSTER"
run_rec "$(mk_subagent_start "$SID_A" "$IDX2_TR" "$IDX2_REPO" "general-purpose" "$START_ID")"
expect_eq "T20d: …the control — an extend with NO ack is not a restart: a live duplicate is journalled, not a new identification" \
  "1" "$(grep -c 'status=duplicate-start' "$IDX2_ROSTER")"
expect_eq "T20d: …still exactly two identified rows (the seed's and the extend's, neither touched)" \
  "2" "$(grep -c 'status=identified' "$IDX2_ROSTER")"
expect_contains "T20d: …and the duplicate-start row carries the extend's own launch, untouched by any PRIOR_LAUNCH read" \
  "|launched_at=2026-08-08T09:15:00Z|" "$(grep 'status=duplicate-start' "$IDX2_ROSTER" | tail -1)"

# THE LANDED-THEN-RELAUNCHED LINEAGE (delta review C1; RE-AUTHORED at epic-23 wave-20 T20).
# The control above proves an ack frees the name; this proves the ack does NOT free it
# forever. `probemate` runs under one id, lands, is acked, and is dispatched again under the
# SAME name and a NEW id — which the dispatch wall allows, because the ack closed the first
# contract. A second start under the SECOND id is a live duplicate and must be journalled.
# Until T20 the first lineage was closed here by a MET marker; the close is the ack now
# (`roster_open_names`), and the marker stays in the fixture because a landing writes one.
#
# WHY IT NEEDS ITS OWN CASE. `met[]` was filled from ANY marker for the name, anywhere in
# the file, so one landing silenced the duplicate arm for that name for the rest of the
# session; the predicate that replaced it compares the ack against the LATEST launch, and an
# ack older than a relaunch closes nothing. The rule is still that the LATEST contract
# decides — by its launch stamp now, which is why the relaunch is dated after the ack.
START_ID_R2="aprobemate-8c17f42b0d6e5591"
IFS='|' read -r IDR_REPO IDR_TR IDR_SUB IDR_CFG <<< "$(make_world identduprelaunch yes)"
seed_roster_full "$IDR_REPO" "$SID_A" "probemate" "toolu_01IDENTDUPR1" confirmed "$START_ID"
IDR_ROSTER="$IDR_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$IDR_TR" "$IDR_REPO" "general-purpose" "$START_ID")"
swept_marker_write "$IDR_ROSTER" 2026-08-08T09:30:00Z "$SID_A" probemate "$START_ID" MET
ack_write "$IDR_REPO" "$SID_A" 2026-08-08T09:31:00Z probemate
# …the relaunch: a fresh contract for the same NAME under a new id, launched after the ack.
SEED_LAUNCHED_AT=2026-08-08T10:00:00Z \
  seed_roster_full "$IDR_REPO" "$SID_A" "probemate" "toolu_01IDENTDUPR2" confirmed "$START_ID_R2"
run_rec "$(mk_subagent_start "$SID_A" "$IDR_TR" "$IDR_REPO" "general-purpose" "$START_ID_R2")"
expect_eq "T22-dup: the relaunched lineage identifies once and records no duplicate yet" \
  "0" "$(grep -c 'status=duplicate-start' "$IDR_ROSTER")"
run_rec "$(mk_subagent_start "$SID_A" "$IDR_TR" "$IDR_REPO" "general-purpose" "$START_ID_R2")"
IDR_DUP=$(grep 'status=duplicate-start' "$IDR_ROSTER" 2>/dev/null)
expect_contains "T22-dup: a second start against the RELAUNCHED lineage is journalled" \
  "status=duplicate-start" "$IDR_DUP"
expect_contains "…carrying the relaunch's id, not the landed one" \
  "agent_id=$START_ID_R2" "$IDR_DUP"
expect_eq "…exactly once" "1" "$(grep -c 'status=duplicate-start' "$IDR_ROSTER")"
# A RELAUNCH UNDER A NEW ID is a fresh dispatch cycle, not a restart: its own launch stamp
# already postdates the ack, so it carries no restarted_at (T20c).
expect_eq "T20c: a relaunch under a new id carries no restarted_at (only a restart of an acked id does)" \
  "0" "$(grep 'status=identified' "$IDR_ROSTER" | grep -c '|restarted_at=')"

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
  "3" "$(grep -c "^${ROSTER_ROW_SCHEMA}|" "$I2_ROSTER")"

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
section "Section 11: the session key is shape-checked before it becomes a path (Step-6 S-4)"
# ============================================================
#
# `roster-${SID}.state` interpolates the payload's `.session_id` straight into a write path.
# The symlink guards cover `.bionic`, the state directory and the exact filenames — so a key
# carrying path separators does not trip a guard, it leaves the guarded directory. Session
# ids are harness-minted UUIDs today and nothing reaches this; but every other payload value
# on this path is sanitized, this one was not, and this script's own threat model says the
# repo is hostile. The check is the dispatch wall's, spelling for spelling.
IFS='|' read -r I8_REPO I8_TR I8_SUB I8_CFG <<< "$(make_world identtraversal yes)"
# BOTH INTERPOLATION SITES GET THEIR DIRECTORY (S11). The key is interpolated
# into `roster-<sid>.state` AND into the engagement marker `engaged-<sid>.state`,
# and a traversal only resolves if the leading segment exists as a directory. With
# `engaged-x` missing, the engagement switch — not the shape check — was what
# refused this world, and removing the shape check from a scratch copy of the hook
# left the section green: the guard the section names was never the reason. Both
# paths resolve to the SAME file, `<repo>/planted/evil.state`, which the seed
# below writes, so the engagement marker the switch looks for is a regular file
# and the drive reaches the write this section is about.
mkdir -p "$I8_REPO/.bionic/tmp/roster-x" "$I8_REPO/.bionic/tmp/engaged-x" "$I8_REPO/planted"
SID_TRAVERSAL='x/../../../planted/evil'
I8_PLANTED="$I8_REPO/planted/evil.state"
seed_roster_full "$I8_REPO" "$SID_TRAVERSAL" "probemate" "toolu_01TRAVERSE" confirmed "$START_ID"

# THE SEED ITSELF WROTE THROUGH THE TRAVERSAL, so the planted file EXISTS before
# the hook runs — `roster-x/../../../planted/evil.state` under the state
# directory resolves to `<repo>/planted/evil.state`. The question this section
# asks is therefore not whether the file is there; it is whether THE HOOK wrote
# to it. The seeded bytes are the baseline (S11, AC-16).
I8_BEFORE="$(cat "$I8_PLANTED" 2>/dev/null)"
expect_contains "the fixture really did place a file outside the state directory (the target exists)" \
  "status=confirmed" "$I8_BEFORE"

run_rec "$(mk_subagent_start "$SID_TRAVERSAL" "$I8_TR" "$I8_REPO" "general-purpose" "$START_ID")"

I8_AFTER="$(cat "$I8_PLANTED" 2>/dev/null)"
expect_eq "a session key carrying path separators writes NOTHING outside the state directory" \
  "$I8_BEFORE" "$I8_AFTER"
expect_absent "…so no identified row is appended through the traversal" \
  "status=identified" "$I8_AFTER"
expect_status "…and the hook is silent about it rather than failing" "0" "$REC_ST"

# THE PAIRED POSITIVE, same section, same drive, same roster shape: a WELL-FORMED
# session key does get its identified row. Without it, all three rows above pass
# on a hook that stopped writing rosters entirely.
IFS='|' read -r I8OK_REPO I8OK_TR I8OK_SUB I8OK_CFG <<< "$(make_world identtraversalok yes)"
seed_roster_full "$I8OK_REPO" "$SID_A" "probemate" "toolu_01TRAVERSE" confirmed "$START_ID"
run_rec "$(mk_subagent_start "$SID_A" "$I8OK_TR" "$I8OK_REPO" "general-purpose" "$START_ID")"
expect_contains "the control: a harness-shaped session key DOES get its identified row" \
  "status=identified" "$(cat "$I8OK_REPO/.bionic/tmp/roster-${SID_A}.state" 2>/dev/null)"

# ============================================================
section "Section 12: launch-reference immutability across resume (AC-5, R6, epic-16 w2 S6)"
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
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture status="$status" session="$sid" name="$name" agent_id="$aid" \
    launched_at="$lat" model=claude-sonnet-5 \
    deliverable=.bionic/docs/record/w1-rc-verify.md duration='~25 minutes.' \
    progress=.bionic/tmp/w1-rc.progress cadence='~8m.' tool_use_id="$tuid" >> "$f"
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
section "Section 12: THE ENGAGEMENT SWITCH (AC-6)"
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
section "Section 13: THE PRESSURE SAMPLE (wave-roster-lifecycle S9, spec AC-15)"
# ============================================================
#
# One `pressure_sample` call after the engagement check, on every engaged Bash
# PostToolUse payload — not tied to whether that payload carries a stop-check
# machine line, and not fired on the Agent or SubagentStart arms. Isolated with
# its own ring (BIONIC_PRESSURE_RING) and clock (BIONIC_NOW_EPOCH) so this suite
# never touches the real machine-scoped ring.

P_RING="$SANDBOX/pressure/p13.ring"
P_NOW=1700000000
run_rec_pressure() {  # <payload-json> — like run_rec, with the pressure fixture pinned
  local _sid; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  REC_OUT=$(printf '%s' "$1" | env CLAUDE_CODE_SESSION_ID="$_sid" \
    BIONIC_PRESSURE_RING="$P_RING" BIONIC_NOW_EPOCH="$P_NOW" \
    BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=69 BIONIC_PROBE_LOAD_1M=1.6 \
    bash "$REC" 2>"$SANDBOX/.err"); REC_ST=$?
  REC_ERR=$(cat "$SANDBOX/.err")
  return 0
}

IFS='|' read -r P_REPO P_TR P_SUB P_CFG <<< "$(make_world pressure yes)"

# (a) an engaged Bash call carrying NO stop-check machine line still samples.
# A plain, unremarkable command — the overwhelming majority of Bash calls in a
# session — is exactly the case the old early exit on empty MLINES used to skip
# before it ever reached the engagement check or this sample.
rm -f "$P_RING"
run_rec_pressure "$(mk_bash_post "$SID_A" "$P_TR" "$P_REPO" "echo hi" "hi")"
expect_status "13a an ordinary Bash call still exits 0" "0" "$REC_ST"
expect_file   "13a …and one ring line was appended" "$P_RING"
expect_eq     "13a …exactly one" "1" "$(wc -l < "$P_RING" | tr -d ' ')"

# (b) a second engaged Bash call samples again — the ring grows, it is not
# replaced (pressure_sample's own append-then-prune, not this hook's business).
run_rec_pressure "$(mk_bash_post "$SID_A" "$P_TR" "$P_REPO" "echo two" "two")"
expect_eq "13b a second engaged call appends a second line" "2" "$(wc -l < "$P_RING" | tr -d ' ')"

# (c) UNENGAGED: the marker removed, the same shape of call samples nothing.
rm -f "$P_REPO/.bionic/tmp/engaged-$SID_A.state"
run_rec_pressure "$(mk_bash_post "$SID_A" "$P_TR" "$P_REPO" "echo three" "three")"
expect_status "13c unengaged: still exits 0" "0" "$REC_ST"
expect_eq     "13c …and the ring is untouched" "2" "$(wc -l < "$P_RING" | tr -d ' ')"
: > "$P_REPO/.bionic/tmp/engaged-$SID_A.state"

# (d) the Agent arm (a dispatch confirming) does not sample — only Bash does.
P_ROSTER="$P_REPO/.bionic/tmp/roster-${SID_A}.state"
seed_roster "$P_REPO" "$SID_A" "w99-pressure" "toolu_01PRESSUREAGENT"
run_rec_pressure "$(mk_agent_post "$SID_A" "$P_TR" "$P_REPO" "w99-pressure" "apressure-2222222222222222" "toolu_01PRESSUREAGENT")"
expect_contains "13d the Agent call still confirms its roster row" "status=confirmed" "$(cat "$P_ROSTER")"
expect_eq       "13d …but appends nothing to the ring" "2" "$(wc -l < "$P_RING" | tr -d ' ')"

# (e) FAILURE-TOLERANT: an unwritable ring path does not crash the hook or block
# the rest of its work — pressure_sample's own failure (return 2, a stderr line)
# is swallowed, not propagated.
P_BLOCKER="$SANDBOX/pressure/blocker-file"
mkdir -p "$(dirname "$P_BLOCKER")"; : > "$P_BLOCKER"
run_rec_pressure_blocked() {
  local _sid; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  REC_OUT=$(printf '%s' "$1" | env CLAUDE_CODE_SESSION_ID="$_sid" \
    BIONIC_PRESSURE_RING="$P_BLOCKER/pressure.ring" BIONIC_NOW_EPOCH="$P_NOW" \
    bash "$REC" 2>"$SANDBOX/.err"); REC_ST=$?
  REC_ERR=$(cat "$SANDBOX/.err")
  return 0
}
seed_roster "$P_REPO" "$SID_A" "w99-pressure2" "toolu_01PRESSUREBLOCKED"
run_rec_pressure_blocked "$(mk_agent_post "$SID_A" "$P_TR" "$P_REPO" "w99-pressure2" "apressure-3333333333333333" "toolu_01PRESSUREBLOCKED")"
expect_status   "13e an unwritable ring path still exits 0" "0" "$REC_ST"
expect_contains "13e …and the rest of the hook's work still happens" "status=confirmed" "$(cat "$P_ROSTER")"

# (f) THE EARLY EXIT, RESTORED (Step-6 review P-2). This hook is PostToolUse on EVERY
# Bash call, and the overwhelming majority carry no machine line. S9 deleted the early
# exit that used to fire on an empty MLINES, because the pressure sample above sits below
# the loader and the engagement switch and had to be reachable. The exit is back,
# immediately after the sample: nothing below it has any work to do for an empty MLINES,
# and ARM 1's `<<<"$MLINES"` loop already wrote nothing there.
#
# THE OBSERVABLE IS THE SPAWN COUNT, because the empty-MLINES path writes no file either
# way — the difference is work not done. A `jq` shim counts every invocation the hook
# makes: four with the exit, six without (the two the transcript/subagents resolution
# below it costs). Timing measured on one synthetic payload: 0.10 s -> 0.09 s wall, of
# which ~0.03 s is `project_root`'s git resolution and ~0.04 s is the sample itself —
# both above the exit by necessity, and both named in s20-report.md.
P_SHIM="$SANDBOX/pressure/shim"
mkdir -p "$P_SHIM"
P_REAL_JQ="$(command -v jq)"
P_JQC="$SANDBOX/pressure/.jq-calls"
cat > "$P_SHIM/jq" <<PSHIMEOF
#!/bin/bash
printf 'x' >> "\$REC_JQ_COUNT"
exec "$P_REAL_JQ" "\$@"
PSHIMEOF
chmod +x "$P_SHIM/jq"

run_rec_counted() {  # <payload-json> — run_rec_pressure with a counting jq on PATH
  local _sid; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  REC_OUT=$(printf '%s' "$1" | env PATH="$P_SHIM:$PATH" REC_JQ_COUNT="$P_JQC" \
    CLAUDE_CODE_SESSION_ID="$_sid" \
    BIONIC_PRESSURE_RING="$P_RING" BIONIC_NOW_EPOCH="$P_NOW" \
    BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=69 BIONIC_PROBE_LOAD_1M=1.6 \
    bash "$REC" 2>"$SANDBOX/.err"); REC_ST=$?
  REC_ERR=$(cat "$SANDBOX/.err")
  return 0
}

: > "$P_JQC"
run_rec_counted "$(mk_bash_post "$SID_A" "$P_TR" "$P_REPO" "echo four" "four")"
expect_status "13f an ordinary Bash call still exits 0" "0" "$REC_ST"
expect_eq "13f …and the sample still landed on it" "3" "$(wc -l < "$P_RING" | tr -d ' ')"
# THE CONSTANT HAS MOVED TWICE, and each move made the hot path cheaper rather than changing
# what this row is for. 4 -> 3 at epic-23 wave-12-fixit-171 T11: `bionic_context` stopped
# spending two `jq` processes on the payload and spends one on the whole field roster
# (lib/context.sh, `_bionic_jq_fill`). 3 -> 2 at epic-23 wave-15 (REQ-2): the read this arm
# spent pulling the tool's whole stdout out of the payload, so it could be grepped for a
# machine line, is gone with the observation record — nothing reads a tool's output here now.
# Two reads is the floor: the tool name, and the context fill.
P_JQ_WITH_EXIT=2
expect_eq "13f …and the hook stopped right after the sample: two payload reads, not four" \
  "$P_JQ_WITH_EXIT" "$(wc -c < "$P_JQC" | tr -d ' ')"

# THE OTHER DIRECTION IS GONE, AND ITS ABSENCE IS THE CLAIM (epic-23 wave-15, REQ-2). A Bash
# call that carried a machine line used to skip the exit and run the arms below it, at a
# strictly higher payload-read count — the measurement this section made. Nothing reads a
# tool's stdout any more, so the two calls are INDISTINGUISHABLE to this hook, and that is
# what the pair below asserts: the same count either way, which is the observation arm being
# gone rather than merely quiet.
P_MLINE="stop-check-observation/v1|agent=w99-none|log=$SANDBOX/pressure/nolog|mtime=1|size=1"
: > "$P_JQC"
run_rec_counted "$(mk_bash_post "$SID_A" "$P_TR" "$P_REPO" "bash stop-check.sh" "$P_MLINE")"
expect_status "13f a Bash call whose output LOOKS like a machine line still exits 0" "0" "$REC_ST"
expect_eq "13f …and costs exactly the same payload reads: nothing reads stdout" \
  "$P_JQ_WITH_EXIT" "$(wc -c < "$P_JQC" | tr -d ' ')"
expect_no_file "13f …and writes no record for it" "$P_REPO/$STATE_REL"

# ============================================================
section "Section 14: the BUDGET FIELDS survive both rebuilds, byte for byte (review-b B-4)"
# ============================================================
#
# THE LINK NOTHING TESTED. `hooks/background-suite-guard.sh`'s budget arm reads
# `suites_allowed=` off the LAST roster row carrying this agent's id — and the launch row
# hooks/dispatch-preflight.sh writes carries `agent_id=` EMPTY, so it can never be that row.
# The field is filled only here, by ARM 2 (confirmation) and ARM 3 (identification), both of
# which rebuild the row FIELD-WISE with `RS = "|"`. Every test of the budget arm plants its
# row directly with `roster_row_fixture`; no test drove dispatch → recorder → guard, so a
# rebuild that dropped or renamed the three fields would turn the AC-21 named-suite refusal
# inert in production with every suite still green — the wall going quiet, which is the
# failure direction this wave exists to close.
#
# BYTE FOR BYTE, not "present": the budget is compared as a string by the guard
# (`case " $SUITES_ALLOWED " in *" $_target "*`), so a value that survived with its spacing
# or ordering changed is a different budget.

S14_TUID="toolu_01BUDGETCARRY0001"
S14_AID="a91be40cf7712533c"
S14_FILES="payload/scripts/lib/widget.sh,hooks/widget-guard.sh"
S14_SUITES="alpha.test.sh beta.test.sh gamma.test.sh"

seed_roster_budget() {  # <repo> <sid> <name> <tool_use_id> <status> <agent-id>
  local repo="$1" sid="$2" name="$3" tuid="$4" status="$5" aid="$6"
  local f="$repo/.bionic/tmp/roster-${sid}.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture status="$status" session="$sid" name="$name" agent_id="$aid" \
    launched_at=2026-08-08T09:00:00Z model=claude-opus-5 \
    deliverable=.bionic/docs/record/w14-budget.md duration='~25 minutes.' \
    progress=.bionic/tmp/w14.progress tool_use_id="$tuid" \
    files="$S14_FILES" suites_allowed="$S14_SUITES" suites_source=derived >> "$f"
  return 0
}

# --- 14a: ARM 2, the confirmation rebuild ---
IFS='|' read -r B1_REPO B1_TR B1_SUB B1_CFG <<< "$(make_world budgetconfirm yes)"
seed_roster_budget "$B1_REPO" "$SID_A" "w14-impl" "$S14_TUID" intended ""
B1_ROSTER="$B1_REPO/.bionic/tmp/roster-${SID_A}.state"
# NON-VACUITY, the precondition: the launch row really carries the three fields, and really
# carries an EMPTY agent_id — the two facts that make this the row the guard cannot use yet.
B1_LAUNCH=$(grep 'status=intended' "$B1_ROSTER" 2>/dev/null)
expect_contains "14a the launch row carries the derived budget" "|suites_allowed=$S14_SUITES|" "$B1_LAUNCH"
expect_contains "14a …and an empty agent_id, so the guard can never match it" \
  "|agent_id=|" "$B1_LAUNCH"

run_rec "$(mk_agent_post "$SID_A" "$B1_TR" "$B1_REPO" "w14-impl" "$S14_AID" "$S14_TUID")"
B1_ROW=$(grep 'status=confirmed' "$B1_ROSTER" 2>/dev/null)
expect_contains "14a the confirmed row is the one the guard reads" "agent_id=$S14_AID" "$B1_ROW"
expect_contains "14a …carrying files= forward byte for byte" "|files=$S14_FILES|" "$B1_ROW"
expect_contains "14a …carrying suites_allowed= forward byte for byte" \
  "|suites_allowed=$S14_SUITES|" "$B1_ROW"
expect_contains "14a …carrying suites_source= forward byte for byte" \
  "|suites_source=derived|" "$B1_ROW"
# ONE OF EACH. Every reader takes the FIRST match for a key, so a rebuild that appended
# rather than substituted would answer with whichever copy it happened to put first.
for _k in files suites_allowed suites_source; do
  expect_eq "14a …exactly one $_k= field on the rebuilt row" "1" \
    "$(printf '%s' "$B1_ROW" | tr '|' '\n' | /usr/bin/grep -c "^$_k=" | tr -d ' ')"
done

# --- 14b: ARM 3, the identification rebuild ---
IFS='|' read -r B2_REPO B2_TR B2_SUB B2_CFG <<< "$(make_world budgetident yes)"
seed_roster_budget "$B2_REPO" "$SID_A" "w14-mate" "toolu_01BUDGETCARRY0002" confirmed "$START_ID"
B2_ROSTER="$B2_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$B2_TR" "$B2_REPO" "general-purpose" "$START_ID")"
B2_ROW=$(grep 'status=identified' "$B2_ROSTER" 2>/dev/null)
expect_contains "14b the identified row keys to the same agent" "agent_id=$START_ID" "$B2_ROW"
expect_contains "14b …carrying files= forward byte for byte" "|files=$S14_FILES|" "$B2_ROW"
expect_contains "14b …carrying suites_allowed= forward byte for byte" \
  "|suites_allowed=$S14_SUITES|" "$B2_ROW"
expect_contains "14b …carrying suites_source= forward byte for byte" \
  "|suites_source=derived|" "$B2_ROW"
for _k in files suites_allowed suites_source; do
  expect_eq "14b …exactly one $_k= field on the rebuilt row" "1" \
    "$(printf '%s' "$B2_ROW" | tr '|' '\n' | /usr/bin/grep -c "^$_k=" | tr -d ' ')"
done

# --- 14c: THE LAST ROW WINS, and it is the one that carries the budget. The guard reads the
# newest row for an id; after both rebuilds that row must still state the same set.
B2_LAST=$(grep -v '^#' "$B2_ROSTER" | tail -1)
expect_contains "14c the LAST row carrying the id is the one the guard would read" \
  "agent_id=$START_ID" "$B2_LAST"
expect_contains "14c …and it states the budget the dispatch derived" \
  "|suites_allowed=$S14_SUITES|" "$B2_LAST"

# --- 14d: A WIDE budget survives both rebuilds too (T18, REQ-9/D7) ---
#
# A-orch-16 named this file's confirmed→identified copy-forward as one of two writers it
# suspected still capped `suites_allowed=`/`files=` at 400 chars, alongside
# `hooks/dispatch-preflight.sh`'s launch row (fixed at T18, `tests/dispatch-preflight.test.sh`
# §S27i/§S27j). Investigated here directly: both rewrites in THIS file build the row
# FIELD-WISE with `RS = "|"` and substitute only `status=`/`agent_id=`/`name=`/
# `teammate_id=`/`launched_at=` — every other field, `suites_allowed=`/`files=` included,
# passes through as `f = $0` with no length operation anywhere in either awk block. That
# is confirmed here rather than assumed: a budget well past any cap this repo has ever
# used on this field (900, the widest — and past 400, T9's own reader-side number) rebuilds
# whole through BOTH arms. This section was already green before T18 touched anything; it
# is added as the permanent regression guard the investigation justified, not as a fix.
S14D_SUITES=""
for _s14d in $(seq -w 1 70); do
  S14D_SUITES="${S14D_SUITES:+$S14D_SUITES }wide-budget-suite-basename-number-${_s14d}.test.sh"
done
expect_status "14d fixture non-vacuity: the planted budget really exceeds 900 chars" \
  "0" "$([ "${#S14D_SUITES}" -gt 900 ] && echo 0 || echo 1)"

IFS='|' read -r B3_REPO B3_TR B3_SUB B3_CFG <<< "$(make_world budgetwide yes)"
B3_ROSTER="$B3_REPO/.bionic/tmp/roster-${SID_A}.state"
mkdir -p "$B3_REPO/.bionic/tmp"
roster_header > "$B3_ROSTER"
roster_row_fixture status=intended session="$SID_A" name="w14d-impl" agent_id="" \
  launched_at=2026-08-08T09:00:00Z model=claude-opus-5 \
  deliverable=.bionic/docs/record/w14d-budget.md duration='~25 minutes.' \
  progress=.bionic/tmp/w14d.progress tool_use_id="toolu_01BUDGETWIDE01" \
  files="payload/scripts/lib/widget.sh" "suites_allowed=$S14D_SUITES" \
  suites_source=derived >> "$B3_ROSTER"

run_rec "$(mk_agent_post "$SID_A" "$B3_TR" "$B3_REPO" "w14d-impl" "aw14dwidebudget001" "toolu_01BUDGETWIDE01")"
B3_CONFIRMED=$(grep 'status=confirmed' "$B3_ROSTER" 2>/dev/null | tr '|' '\n' | grep '^suites_allowed=' | cut -d= -f2-)
expect_eq "14d ARM 2 (confirmation) carries the WIDE budget forward whole" \
  "$S14D_SUITES" "$B3_CONFIRMED"

run_rec "$(mk_subagent_start "$SID_A" "$B3_TR" "$B3_REPO" "general-purpose" "aw14dwidebudget001")"
B3_IDENTIFIED=$(grep 'status=identified' "$B3_ROSTER" 2>/dev/null | tr '|' '\n' | grep '^suites_allowed=' | cut -d= -f2-)
expect_eq "14d ARM 3 (identification) carries the WIDE budget forward whole too" \
  "$S14D_SUITES" "$B3_IDENTIFIED"

# ============================================================
section "Section 15: dispatch-terms delivery — SubagentStart pushes survival.md to bionic agents (wave-11 1c-b, design D2, probe P2)"
# ============================================================
#
# D2 (spec §2, "Dispatcher ↔ agent"): the SubagentStart hook, already registered, reads
# `agent_type`; for `bionic:*` it prints `payload/context/survival.md` as `additionalContext`.
# Third-party and harness agents receive nothing. Probe P2
# (record/wave-11-lean-spine/step2-probe-premises.md §2) proved the mechanism end to end on a
# live dispatch: the exact stdout shape
# `{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"<text>"}}`
# reaches the child transcript as a `<system-reminder>` and is acted on. This section drives
# that same shape through the real hook, hermetically, over `agent_type` alone — the field
# ARM 3 already reads for identification (its own comments call it unreliable for a NAME, but
# it is the field this script is given for the subagent's TYPE, which is what a `bionic:`
# prefix test is about).
#
# BYTE-FOR-BYTE PIN (item 3): the survival text is shipped in exactly one file —
# `payload/context/survival.md` — and that file is the SSoT; this hook's stdout is its
# rendering surface (spec ownership table, "SurvivalTerms"). Case 15a's equality assertion
# IS the agreement between the two: a future edit that changes one without the other fails
# here first.
#
# PLACEMENT, independent of the roster (deliberate). The print is gated on `agent_type` alone,
# ahead of the `ROSTER_FILE`/`ROW` bookkeeping ARM 3 already does — delivering the dispatch
# terms cannot depend on whether this session's roster happens to carry a matching row, or a
# bionic agent started from a roster-less path would silently lose its survival terms. Case
# 15b drives that independence directly: no roster row is seeded at all, and delivery still
# fires. Case 15e is the paired positive showing the two effects (stdout delivery, roster
# identification) coexist without one gating the other, over the SAME fixture as case 15a.
#
# ENGAGEMENT-SCOPED, like every arm in this file (`engaged_session` is asked before any of
# ARM 1/2/3's own logic) — every fixture below is a `yes`-wave world.

# The SSoT itself, read once. `$HERE` is this suite's own `BIONIC_HOOKS_DIR`
# (tests/lib/resolve-roots.sh), so `dirname "$HERE"` is THIS repo's root regardless of which
# checkout is under test — never the fixture sandbox, because the hook resolves its library
# (and this file) from its OWN path, not from the payload's `cwd`.
SURVIVAL_REAL="$(dirname "$HERE")/payload/context/survival.md"
expect_file "15: the SSoT file this whole section pins against exists" "$SURVIVAL_REAL"
S15_WANT="$(cat "$SURVIVAL_REAL" 2>/dev/null)"
expect_nonempty "15: …and it is not empty (a non-vacuous byte-for-byte pin)" "$S15_WANT"

# --- 15a: bionic:senior-implementor, WITH a matching roster row (reuses 14/10's own
#     fixture idiom) — proves delivery AND that ARM 3's existing identification duty is
#     untouched (item 1e). ---
IFS='|' read -r S15A_REPO S15A_TR S15A_SUB S15A_CFG <<< "$(make_world survivalsenior yes)"
seed_roster_full "$S15A_REPO" "$SID_A" "s15a-senior" "toolu_01SURVIVALA" confirmed "$START_ID"
S15A_ROSTER="$S15A_REPO/.bionic/tmp/roster-${SID_A}.state"
run_rec "$(mk_subagent_start "$SID_A" "$S15A_TR" "$S15A_REPO" "bionic:senior-implementor" "$START_ID")"
expect_eq "15a: stdout is exactly one line" "1" "$(printf '%s\n' "$REC_OUT" | grep -c .)"
S15A_EVENT=$(printf '%s' "$REC_OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
expect_eq "15a: hookSpecificOutput.hookEventName is SubagentStart" "SubagentStart" "$S15A_EVENT"
S15A_CTX=$(printf '%s' "$REC_OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
expect_eq "15a: additionalContext equals the byte content of payload/context/survival.md (SSoT pin, item 3)" \
  "$S15_WANT" "$S15A_CTX"
# --- 15e: the existing recorder duty still fires alongside delivery, over this same fixture ---
S15A_ROW=$(grep 'status=identified' "$S15A_ROSTER" 2>/dev/null)
expect_contains "15e: ARM 3's identification still fires on a bionic type" \
  "status=identified" "$S15A_ROW"
expect_contains "15e: …carrying the same transcript-form id delivery did not disturb" \
  "agent_id=$START_ID" "$S15A_ROW"

# --- 15b: bionic:test-runner, with NO roster row at all — delivery does not depend on the
#     roster arm finding (or even having) anything to join. ---
IFS='|' read -r S15B_REPO S15B_TR S15B_SUB S15B_CFG <<< "$(make_world survivalrunner yes)"
run_rec "$(mk_subagent_start "$SID_A" "$S15B_TR" "$S15B_REPO" "bionic:test-runner" "$START_ID")"
expect_eq "15b: stdout is exactly one line" "1" "$(printf '%s\n' "$REC_OUT" | grep -c .)"
S15B_EVENT=$(printf '%s' "$REC_OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
expect_eq "15b: hookSpecificOutput.hookEventName is SubagentStart" "SubagentStart" "$S15B_EVENT"
S15B_CTX=$(printf '%s' "$REC_OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
expect_eq "15b: additionalContext equals the byte content of payload/context/survival.md" \
  "$S15_WANT" "$S15B_CTX"

# --- 15c: general-purpose (a harness agent) — no dispatch terms; this is not a bionic role. ---
IFS='|' read -r S15C_REPO S15C_TR S15C_SUB S15C_CFG <<< "$(make_world survivalharness yes)"
run_rec "$(mk_subagent_start "$SID_A" "$S15C_TR" "$S15C_REPO" "general-purpose" "$START_ID")"
expect_empty "15c: a harness agent type receives nothing on stdout" "$REC_OUT"

# --- 15d: superpowers:something (a third-party skill's agent) — no dispatch terms either;
#     the prefix test is `bionic:`, not merely "carries a colon". ---
IFS='|' read -r S15D_REPO S15D_TR S15D_SUB S15D_CFG <<< "$(make_world survivalthirdparty yes)"
run_rec "$(mk_subagent_start "$SID_A" "$S15D_TR" "$S15D_REPO" "superpowers:something" "$START_ID")"
expect_empty "15d: a third-party agent type receives nothing on stdout" "$REC_OUT"

finish
