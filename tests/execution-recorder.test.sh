#!/bin/bash
# Tests for hooks/execution-recorder.sh — ONE script, TWO arms.
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
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

HERE="${BIONIC_HOOKS_DIR}"
REC="$HERE/execution-recorder.sh"

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
# table).

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design).
#
# Source: .bionic/docs/record/w3-slice1-posttooluse-probe.md §2, the verbatim
# PostToolUse payloads captured live on CLI 2.1.222 for this task. Every payload
# builder below DERIVES from those captures:
#
#   * PostToolUse|Agent — FAITHFUL to capture E (the background dispatch this
#     repo actually uses): tool_input {description, prompt, subagent_type,
#     run_in_background, name} and tool_response {isAsync, status, agentId,
#     description, resolvedModel, prompt, outputFile, canReadOutputFile}, plus
#     tool_use_id. Capture D (synchronous) differs only in the response shape and
#     is exercised by the `status: completed` row below.
#   * transcript_path → session directory — FAITHFUL to §2.5 of
#     record/epic-15-kill-interception-experiment.md, which captures
#     `agent_transcript_path` as "<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl".
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, repo contents,
#     stdout bodies in the forgery rows. None is a platform surface.

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="11111111-2222-3333-4444-555555555555"

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
  printf '%s|%s|%s|%s\n' "$repo" "$proj/$SID_A.jsonl" "$proj/$SID_A/subagents" "$home/.claude"
}

STATE_REL=".bionic/tmp/stop-check.state"

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

# A LAUNCH IS ONE EVENT IN THE RUN'S LOG, and the plan is not written. The session is bound to a plan
# whose row T1 is pending and needs no tree of its own; the intended row carries the row and its brief as the dispatch wall writes
# them. The confirmation appends one `dispatch` beside the brief's record, and the plan's bytes stand.
IFS='|' read -r RD_REPO RD_TR RD_SUB RD_CFG <<< "$(make_world rosterdispatch yes)"
RD_PLAN="$(plan_fixture "$RD_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" wave \
  "| T1 | 4 | build | the build | — | — | — | 30 | REQ-1 | .bionic/docs/record/wave-01-test/T1.md | — | — | pending |")"
printf 'plan=%s\n' "$RD_PLAN" > "$RD_REPO/.bionic/tmp/engaged-$SID_A.state"
RD_BRIEF=.bionic/docs/record/wave-01-test/briefs/w99-T1.md
mkdir -p "$RD_REPO/${RD_BRIEF%/*}"; printf 'the brief\n' > "$RD_REPO/$RD_BRIEF"
{ roster_header; roster_row_fixture status=intended session="$SID_A" name=w99-T1 agent_id= row=T1 \
    brief="$RD_BRIEF" brief_sum=5e1f tool_use_id="$TUID"; } > "$RD_REPO/.bionic/tmp/roster-${SID_A}.state"
RD_SUM="$(shasum < "$RD_PLAN")"
run_rec "$(mk_agent_post "$SID_A" "$RD_TR" "$RD_REPO" "w99-T1" "$NEW_AID" "$TUID")"
RD_LOG="$(grep '^run/v1|ev=dispatch|' "$RD_REPO/.bionic/docs/record/wave-01-test/run.log" 2>/dev/null)"
expect_eq "a launch appends one dispatch event to the run's log" "1" "$(printf '%s' "$RD_LOG" | grep -c .)"
expect_eq "…naming the row, the agent, the brief's path and its sum" "T1 w99-T1 $RD_BRIEF 5e1f" \
  "$(for k in row name brief sum; do printf '%s\n' "$RD_LOG" | tr '|' '\n' | sed -n "s/^$k=//p"; done | tr '\n' ' ' | sed 's/ $//')"
expect_eq "…and the plan is not written" "$RD_SUM" "$(shasum < "$RD_PLAN")"

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
finish
