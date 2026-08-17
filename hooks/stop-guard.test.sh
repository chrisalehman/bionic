#!/bin/bash
# Tests for hooks/stop-guard.sh — the STOP GATE, PreToolUse|TaskStop
# (epic-15 wave-01R; recorder arm removed at wave-03 slice 4/4).
#
# The gate: D-1 activity-boundary freshness, D-2 consume-on-stop, and — since
# wave-03 slice 4/6 — D-3 same-actor, D-6 progress staleness, and the
# foreign-stop rule. Serves wave-01R's AC-4/AC-5 and the stop-side rows of
# AC-8/AC-10, plus wave-03's AC-4 (§8), AC-5 (§9) and AC-6 (§10).
#
# WHAT MOVED OUT. This script used to carry a second arm that WROTE the records
# it now only reads. Those rows live in hooks/execution-recorder.test.sh, because
# that is where the writer lives — one writer, one paired suite. The records this
# suite spends are still never hand-written: `observe()` below runs the real
# hooks/stop-check.sh and feeds its real output to the real recorder, so every
# gate row here is discharged through the whole producer→recorder→gate path.
#
# HERMETIC. Every payload is crafted and piped straight into the script under
# test; nothing here invokes the TaskStop tool, touches the live installed hooks,
# or writes outside a mktemp'd sandbox.
#
# Usage: bash hooks/stop-guard.test.sh

set -uo pipefail

. "$(dirname "$0")/../tests/lib/resolve-roots.sh"

HERE="${BIONIC_HOOKS_DIR}"
GUARD="$HERE/stop-guard.sh"
RECORDER="$HERE/execution-recorder.sh"
OBSERVE="$HERE/stop-check.sh"
PASS=0
FAIL=0
TOTAL=0

# `cd … && pwd` normalizes the path: $TMPDIR carries a trailing slash on
# macOS, and a doubled separator would slugify differently from the cwd the
# script under test actually sees.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stop-guard-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------- assertions ----------

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_contains() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_matches()  { if grep -qE -- "$2" <<<"$3"; then ok "$1"; else no "$1" "no match: $2"; fi; }
expect_absent()   { if grep -qF -- "$2" <<<"$3"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }
# ONE line, counted rather than eyeballed: "one informational line" is the whole
# of R3's promise about what a user-ordered stop costs the operator, and a
# refusal-shaped wall of text that happens to exit 0 would satisfy every other
# assertion here.
expect_eq_lines() { local n; n=$(printf '%s\n' "$3" | grep -c .); if [ "$n" = "$2" ]; then ok "$1"; else no "$1" "expected $2 line(s), got $n"; fi; }
expect_file()     { if [ -f "$2" ]; then ok "$1"; else no "$1" "no such file: $2"; fi; }
expect_no_file()  { if [ -f "$2" ]; then no "$1" "file exists but should not: $2"; else ok "$1"; fi; }

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

# THE SAME PAYLOADS, INVOKED BY A SUBAGENT (slice 4/6, D-3). FAITHFUL to
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
run_guard() {  # <payload-json>
  GUARD_OUT=$(printf '%s' "$1" | bash "$GUARD" 2>"$SANDBOX/.err"); GUARD_ST=$?
  GUARD_ERR=$(cat "$SANDBOX/.err")
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
  printf '%s|%s|%s\n' "$repo" "$proj/$SID_A.jsonl" "$proj/$SID_A/subagents"
}

# plant_agent <subagents-dir> <agent-id> <name> [mtime-touch]
plant_agent() {
  local dir="$1" aid="$2" aname="$3" touchts="${4:-}"
  printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0,"model":"opus","taskKind":"in_process_teammate"}\n' \
    "$aname" > "$dir/agent-$aid.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$dir/agent-$aid.jsonl"
  [ -n "$touchts" ] && touch -t "$touchts" "$dir/agent-$aid.jsonl"
  return 0
}

STATE_REL=".bionic/tmp/stop-check.state"

# THE WHOLE PRODUCER→RECORDER PATH, run for real. Since slice 4/4 an observation
# record exists only if hooks/stop-check.sh actually printed its machine line, so
# seeding one by hand would seed a shape the shipped writer can no longer produce.
# The metadata root is reached through CLAUDE_CONFIG_DIR, derived from the same
# transcript path the gate resolves through, so both halves see one fixture world.
# The observation's own session key travels on CLAUDE_CODE_SESSION_ID (slice
# 4/5): it is how the producer finds THIS session's roster, and therefore how a
# contracted progress path reaches the record at all. This suite runs inside a
# real Claude Code session, which exports a real value — unpinned, every call
# below would classify against whatever session happens to be running the suite
# rather than against the fixture, and the suite's HERMETIC claim would be
# quietly false. Pinned to the fixture session here; `observe_nosid` opts out
# explicitly, where the missing key is the fact under test.
observe() {  # <sid> <transcript> <repo> <typed-target> [args…]
  observe_as "" "$@"
}

# <observer> is the agent id of the actor that RAN the observation — empty for
# the orchestrator, which is exactly how the platform renders it (the field is
# absent, and the recorder writes the literal token `orchestrator`).
observe_as() {  # <observer-agent-id|""> <sid> <transcript> <repo> <typed-target> [args…]
  local observer="$1" sid="$2" tr="$3" repo="$4"; shift 4
  local cfg="${tr%/projects/*}" out payload
  out=$( cd "$repo" && CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="$sid" \
         bash "$OBSERVE" "$@" 2>/dev/null )
  if [ -n "$observer" ]; then
    payload=$(mk_bash_post_as "$sid" "$tr" "$repo" \
      "bash ~/.claude/hooks/stop-check.sh $*" "$out" "$observer")
  else
    payload=$(mk_bash_post "$sid" "$tr" "$repo" \
      "bash ~/.claude/hooks/stop-check.sh $*" "$out")
  fi
  printf '%s' "$payload" | bash "$RECORDER" >/dev/null 2>&1
  return 0
}

# An observation run with NO own-session key — the degraded case slice 4/5 named
# (classification `unknown`, roster invisible), driven here because it is the one
# way a contracted progress artifact can go unlooked-at.
observe_nosid() {  # <sid> <transcript> <repo> <typed-target> [args…]
  local sid="$1" tr="$2" repo="$3"; shift 3
  local cfg="${tr%/projects/*}" out
  out=$( cd "$repo" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR="$cfg" \
         bash "$OBSERVE" "$@" 2>/dev/null )
  printf '%s' "$(mk_bash_post "$sid" "$tr" "$repo" \
    "bash ~/.claude/hooks/stop-check.sh $*" "$out")" | bash "$RECORDER" >/dev/null 2>&1
  return 0
}

# THE SESSION ROSTER, planted as the PRECONDITION it is at a real stop. Row shape
# FAITHFUL to the writer, hooks/dispatch-preflight.sh's `ROW=` line (field for
# field, in order); the writer itself is driven by its own suite and the two
# shapes are held together by tests/cross-gate-agreement.test.sh. Since slice 4/9
# a row is no longer what makes a target ours — its directory is — so a world that
# plants none is a perfectly ordinary one. What a row still carries is the
# CONTRACT, and, when `confirmed`, ownership of a target filed elsewhere.
#
# The CONTRACT FIELDS (deliverable, waiver, teammate_id) are optional trailing
# arguments rather than a second helper: epic-16 wave-02 slice S3 made the row's
# contract the thing that discharges a stop, so a suite that could only plant
# contract-less rows could not express the discharging case at all. Every call
# written before that slice passes none of them and gets the identical row it got
# before — an empty `deliverable=` is what the writer emits for a dispatch that
# declared nothing.
roster_row() {  # <repo> <sid> <name> <agent-id> [progress] [status] [deliverable] [waiver] [teammate-id]
  local repo="$1" sid="$2" name="$3" aid="$4" prog="${5:-}" status="${6:-confirmed}"
  local deliv="${7:-}" waiver="${8:-}" tmid="${9:-}"
  local f="$repo/.bionic/tmp/roster-$sid.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=%s|duration=|progress=%s|absent=|waiver=%s|teammate_id=%s|tool_use_id=toolu_01FIXTURE\n' \
    "$status" "$sid" "$name" "$aid" "$deliv" "$prog" "$waiver" "$tmid" >> "$f"
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

# ============================================================
echo ""
echo "=== Section 1: the hot path — relevance before any plan walk (checklist A7) ==="
# ============================================================

IFS='|' read -r W1_REPO W1_TR W1_SUB <<< "$(make_world w1 yes)"
plant_agent "$W1_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"

run_guard "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Read", tool_input:{file_path:"/tmp/x"}}')"
expect_status "an unrelated TOOL passes untouched" 0 "$GUARD_ST"
expect_no_file "an unrelated tool writes no state" "$W1_REPO/$STATE_REL"

# A Bash call is no longer this script's business AT ALL (slice 4/4 moved the
# recorder out). It must pass untouched and, more importantly, write nothing:
# a settings file that still carries the retired PreToolUse|Bash registration
# must produce silence rather than a second writer of the same state.
run_guard "$(mk_bash_payload "$SID_A" "$W1_TR" "$W1_REPO" "ls -la && git status")"
expect_status "an unrelated Bash command passes untouched" 0 "$GUARD_ST"
expect_no_file "an unrelated Bash command writes no state" "$W1_REPO/$STATE_REL"

run_guard "$(mk_bash_payload "$SID_A" "$W1_TR" "$W1_REPO" "bash ~/.claude/hooks/stop-check.sh quiet-reviewer")"
expect_status "a REAL observation command is no longer this gate's business" 0 "$GUARD_ST"
expect_no_file "the stop gate writes no observation record, ever (one writer)" "$W1_REPO/$STATE_REL"
expect_absent "the gate source no longer greps command lines for the observation" \
  "grep -qF 'stop-check.sh'" "$(cat "$GUARD")"

run_guard "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent", tool_input:{prompt:"go"}}')"
expect_status "the Agent tool is not this gate's business" 0 "$GUARD_ST"

# Static order pin: the cheap relevance test must precede the plan-directory
# walk in the source, not merely produce the same answer (arch-perf F8/F9 — the
# defect was cost, which behavior alone cannot detect). The relevance test is now
# the tool-name check itself.
_rel_line=$(grep -n 'TOOL_NAME" = "TaskStop" \] || exit 0' "$GUARD" | head -1 | cut -d: -f1)
_walk_line=$(grep -nE '^[[:space:]]*(PLAN=|find )' "$GUARD" | head -1 | cut -d: -f1)
if [ -n "$_rel_line" ] && [ -n "$_walk_line" ] && [ "$_rel_line" -lt "$_walk_line" ]; then
  ok "relevance check precedes the plan walk in source order"
else
  no "relevance check precedes the plan walk in source order" "relevance@${_rel_line:-none} walk@${_walk_line:-none}"
fi

# ============================================================
echo ""
echo "=== Section 2: WRITING moved out — see hooks/execution-recorder.test.sh ==="
# ============================================================
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
ok "the recording rows live with the writer (hooks/execution-recorder.test.sh)"

# ============================================================
echo ""
echo "=== Section 3: the observation record is VERSIONED and key-addressed (checklist A6) ==="
# ============================================================

IFS='|' read -r W3_REPO W3_TR W3_SUB <<< "$(make_world w3 yes)"
plant_agent "$W3_SUB" "atarget-3333333333333333" "target"
roster_row "$W3_REPO" "$SID_A" "target" "atarget-3333333333333333"
observe "$SID_A" "$W3_TR" "$W3_REPO" "target"
STATE=$(cat "$W3_REPO/$STATE_REL")
expect_matches "the record leads with a schema version token" '(^|\|)v1(\||$)' "$STATE"
expect_matches "fields are key=value, not positional" 'target=' "$STATE"

# Forward compatibility: one MORE field must not break the reader (A6 — the
# defect was a fixed-field-order parser breaking undiagnosably on a new field).
sed -i.bak 's/$/|futurefield=whatever/' "$W3_REPO/$STATE_REL"
rm -f "$W3_REPO/$STATE_REL.bak"
run_guard "$(mk_stop_payload "$SID_A" "$W3_TR" "$W3_REPO" "target")"
expect_status "an unknown EXTRA field does not break the reader" 0 "$GUARD_ST"

# An unknown schema VERSION is not guessed at — it is refused.
observe "$SID_A" "$W3_TR" "$W3_REPO" "target"
sed -i.bak 's/^v1|/v9|/' "$W3_REPO/$STATE_REL"; rm -f "$W3_REPO/$STATE_REL.bak"
run_guard "$(mk_stop_payload "$SID_A" "$W3_TR" "$W3_REPO" "target")"
expect_status "an unknown schema VERSION refuses the stop" 2 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 4: fail directions at the stop gate (AC-10, TDD §7) ==="
# ============================================================

# --- before the active-wave verdict: OPEN and SILENT ---
IFS='|' read -r N_REPO N_TR N_SUB <<< "$(make_world nowave no)"
plant_agent "$N_SUB" "aidle-4444444444444444" "idle"
run_guard "$(mk_stop_payload "$SID_A" "$N_TR" "$N_REPO" "idle")"
expect_status "no active wave: the stop passes" 0 "$GUARD_ST"
expect_empty "no active wave: the gate is silent" "$GUARD_ERR"

run_guard "$(jq -n --arg c "$N_REPO" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"TaskStop", tool_input:{task_id:"idle"}}')"
expect_status "no active wave + no session key: still open (pre-verdict)" 0 "$GUARD_ST"
expect_empty "no active wave + no session key: still silent" "$GUARD_ERR"

# A plan that exists but names no step is not a run in progress. This is the
# rung BELOW "no plan at all", and it needs its own case: a gate that treated
# any plan file as an active wave would wall every repo that has ever held one.
IFS='|' read -r P_REPO P_TR P_SUB <<< "$(make_world plannostep yes)"
plant_agent "$P_SUB" "aidle-4444444444444444" "idle"
sed -i.bak 's/^current: 4$/current: pending/' "$P_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
rm -f "$P_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md.bak"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_status "a plan with no valid current step is not an active wave: open" 0 "$GUARD_ST"
expect_empty "a plan with no valid current step: silent" "$GUARD_ERR"

# --- after the verdict: CLOSED and LOUD ---
IFS='|' read -r W4_REPO W4_TR W4_SUB <<< "$(make_world w4 yes)"
plant_agent "$W4_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
roster_row "$W4_REPO" "$SID_A" "quiet-reviewer" "aquiet-reviewer-deadbeefdeadbeef"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer")"
expect_status "active wave + no observation: REFUSED" 2 "$GUARD_ST"
expect_contains "the refusal names the observation command" "stop-check.sh" "$GUARD_ERR"
# A1 asks for a command an operator can run from wherever they are standing. The gate used
# to buy that with an installed-path literal; since epic-17 W1 S3 it buys it by resolving
# hooks/stop-check.sh beside itself from "$0", which is absolute for the same reason and
# stays correct in a plugin payload where ~/.claude/hooks/ no longer holds anything.
expect_contains "the fix command uses the resolved INSTALL path, not a repo-relative one (A1)" \
  "$HERE/stop-check.sh" "$GUARD_ERR"
expect_absent "the fix command is not repo-relative" "bash hooks/stop-check.sh" "$GUARD_ERR"
expect_contains "the refusal names the target as typed" "quiet-reviewer" "$GUARD_ERR"

run_guard "$(jq -n --arg c "$W4_REPO" --arg t "$W4_TR" \
  '{transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:"TaskStop", tool_input:{task_id:"quiet-reviewer"}}')"
expect_status "active wave + payload missing its session key: REFUSED (closed)" 2 "$GUARD_ST"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "")"
expect_status "active wave + empty task_id: REFUSED" 2 "$GUARD_ST"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "no-such-agent")"
expect_status "active wave + unresolvable name (not address-shaped): PASSES THROUGH (T4)" 0 "$GUARD_ST"
expect_matches "…and the passthrough is logged, never silent" 'PASSTHROUGH' "$GUARD_ERR"

# Ambiguity: two live agents answering to the same name in one session.
plant_agent "$W4_SUB" "adouble-5555555555555555" "twin"
plant_agent "$W4_SUB" "adouble-6666666666666666" "twin"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "twin")"
expect_status "active wave + ambiguous name: REFUSED" 2 "$GUARD_ST"
expect_contains "an ambiguous name says so" "ambiguous" "$GUARD_ERR"

# A plan with CR-only line endings is still a plan. `tr -d` on those separators
# collapses the file to one line, the run-state marker goes unseen, and the gate
# quietly reports "no wave" on a repo mid-wave — the fail-dangerous shape that
# bypassed the evidence gate for a whole wave (.claude/rules/hook-authoring.md).
IFS='|' read -r CR_REPO CR_TR CR_SUB <<< "$(make_world crplan yes)"
plant_agent "$CR_SUB" "acrlf-0123456789abcdef" "crlf"
roster_row "$CR_REPO" "$SID_A" "crlf" "acrlf-0123456789abcdef"
CR_PLAN="$CR_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
tr '\n' '\r' < "$CR_PLAN" > "$CR_PLAN.cr" && mv "$CR_PLAN.cr" "$CR_PLAN"
run_guard "$(mk_stop_payload "$SID_A" "$CR_TR" "$CR_REPO" "crlf")"
expect_status "a CR-only plan is still read: the wave is still detected" 2 "$GUARD_ST"

# The positive pair — a wall that refuses everything is equally broken (§9).
observe "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer")"
expect_status "active wave + fresh observation: PERMITTED" 0 "$GUARD_ST"
expect_empty "a permitted stop is silent" "$GUARD_ERR"

# A foreign session's observation is not mine.
IFS='|' read -r W5_REPO W5_TR W5_SUB <<< "$(make_world w5 yes)"
plant_agent "$W5_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
roster_row "$W5_REPO" "$SID_A" "quiet-reviewer" "aquiet-reviewer-deadbeefdeadbeef"
observe "$SID_B" "$W5_TR" "$W5_REPO" "quiet-reviewer"
run_guard "$(mk_stop_payload "$SID_A" "$W5_TR" "$W5_REPO" "quiet-reviewer")"
expect_status "another session's observation does not discharge my stop" 2 "$GUARD_ST"
expect_contains "the foreign-session refusal says whose it was" "session" "$GUARD_ERR"

# ============================================================
echo ""
echo "=== Section 4a: unsupervised-target passthrough (T4, AC-6) ==="
# ============================================================
#
# scan_subagent_dirs only ever iterates agent-*.meta.json — the Agent tool's own
# bookkeeping. A background bash task id never gets one (A-D4), so MATCH_COUNT
# was unconditionally 0 for it, forever, with no code path back to
# order_current() — the escape hatch this gate's own header advertises
# (step2-research-a1-a3.md §A3). The ratified carve (session.plan.md ## Design
# ¶T4): refuse only a target wearing an AGENT-ADDRESS shape (`@session-`, or
# transcript-form `a<hex>` / `a<name>-<16hex>`); everything else passes through,
# logged once, never silent.

# (a) A bash-background-task-shaped id (A-D4 probe evidence: t5triyxvo) carries
# no agent metadata and wears no address shape: PASSES THROUGH.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "t5triyxvo")"
expect_status "a bash-task-shaped target with no metadata: PASSES THROUGH" 0 "$GUARD_ST"
expect_matches "…and the passthrough is logged, never silent" 'PASSTHROUGH' "$GUARD_ERR"
expect_eq_lines "…in exactly one line" 1 "$GUARD_ERR"

# (b) An addressing-form target (`name@session-xxxx`) with no metadata IS
# address-shaped: stays REFUSED, the verbatim unresolved-target message unchanged.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "ghost@session-deadbeef")"
expect_status "an addressing-form target with no metadata: still REFUSED" 2 "$GUARD_ST"
expect_contains "…the verbatim unresolved-target message" "is unresolved" "$GUARD_ERR"

# (c) Transcript-form targets (`a`+hex, and `a<name>-<16hex>`) with no metadata
# ARE address-shaped: stay REFUSED.
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "af3d9128ea3b393af")"
expect_status "a hex transcript-form target with no metadata: still REFUSED" 2 "$GUARD_ST"
expect_contains "…the verbatim unresolved-target message" "is unresolved" "$GUARD_ERR"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "aghost-0123456789abcdef")"
expect_status "a named transcript-form target with no metadata: still REFUSED" 2 "$GUARD_ST"
expect_contains "…the verbatim unresolved-target message" "is unresolved" "$GUARD_ERR"

# (d) A supervised named target (metadata present) still engages the FULL guard
# path, untouched — the passthrough branch is reached only at MATCH_COUNT=0, and
# a target that resolves to a real agent of this session never gets there.
# DRIVEN (Step-6 review flag 2-C: a bare `ok` here asserted nothing and could not
# fail). Quiet-reviewer's own REFUSED/PERMITTED pair above already proves the
# full path for that name; this plants a SECOND, never-observed teammate in the
# same active-wave world so the assertion here carries its own evidence rather
# than pointing at rows planted for a different purpose.
plant_agent "$W4_SUB" "ahushed-reviewer-7777777777777777" "hushed-reviewer"
roster_row "$W4_REPO" "$SID_A" "hushed-reviewer" "ahushed-reviewer-7777777777777777"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "hushed-reviewer")"
expect_status "a supervised named target still engages the full guard path: REFUSED for want of an observation" 2 "$GUARD_ST"
expect_contains "…the full no-observation refusal names the observation command" "stop-check.sh" "$GUARD_ERR"
expect_absent "…and this is NOT the passthrough branch" "PASSTHROUGH" "$GUARD_ERR"

# ============================================================
echo ""
echo "=== Section 5: D-1 — freshness by ACTIVITY BOUNDARY, no clocks (AC-4) ==="
# ============================================================

IFS='|' read -r D1_REPO D1_TR D1_SUB <<< "$(make_world d1 yes)"
plant_agent "$D1_SUB" "aworker-7777777777777777" "worker"
roster_row "$D1_REPO" "$SID_A" "worker" "aworker-7777777777777777"

# STALE: the target wrote AFTER the observation. This is the founding incident
# (UC-5) and the flaw the v1 exchange-keyed design provably re-permitted.
observe "$SID_A" "$D1_TR" "$D1_REPO" "worker"
sleep 1
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"committed my work"}]}}\n' \
  >> "$D1_SUB/agent-aworker-7777777777777777.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$D1_TR" "$D1_REPO" "worker")"
expect_status "target wrote after the observation: REFUSED as stale" 2 "$GUARD_ST"
expect_contains "the staleness refusal names activity, not elapsed time" "since" "$GUARD_ERR"
expect_absent "the staleness refusal quotes no clock window" "seconds ago" "$GUARD_ERR"

# SUB-SECOND: a write inside the same mtime second still counts as activity.
IFS='|' read -r D1B_REPO D1B_TR D1B_SUB <<< "$(make_world d1b yes)"
plant_agent "$D1B_SUB" "aworker-8888888888888888" "worker"
roster_row "$D1B_REPO" "$SID_A" "worker" "aworker-8888888888888888"
observe "$SID_A" "$D1B_TR" "$D1B_REPO" "worker"
LOG="$D1B_SUB/agent-aworker-8888888888888888.jsonl"
MT=$(date -r "$LOG" +%Y%m%d%H%M.%S 2>/dev/null)
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}\n' >> "$LOG"
touch -t "$MT" "$LOG"   # restored to the SAME mtime second; only the size grew
run_guard "$(mk_stop_payload "$SID_A" "$D1B_TR" "$D1B_REPO" "worker")"
expect_status "a write within the same mtime second is still activity: REFUSED" 2 "$GUARD_ST"

# DORMANT, HOWEVER OLD: no clock may expire an honest observation.
IFS='|' read -r D2_REPO D2_TR D2_SUB <<< "$(make_world d1old yes)"
plant_agent "$D2_SUB" "asleeper-9999999999999999" "sleeper" "202601010000"
roster_row "$D2_REPO" "$SID_A" "sleeper" "asleeper-9999999999999999"
observe "$SID_A" "$D2_TR" "$D2_REPO" "sleeper"
touch -t 202601010000 "$D2_SUB/agent-asleeper-9999999999999999.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$D2_TR" "$D2_REPO" "sleeper")"
expect_status "dormant since the observation, however old: PERMITTED" 0 "$GUARD_ST"

# LONG-EXCHANGE, MULTI-AGENT (§9 — the configuration v1 never tested). One
# session, three agents, interleaved observations and stops, with one agent
# waking up mid-sequence.
IFS='|' read -r LX_REPO LX_TR LX_SUB <<< "$(make_world longx yes)"
plant_agent "$LX_SUB" "aalpha-aaaaaaaaaaaaaaaa" "alpha"
plant_agent "$LX_SUB" "abeta-bbbbbbbbbbbbbbbb"  "beta"
plant_agent "$LX_SUB" "agamma-cccccccccccccccc" "gamma"
roster_row "$LX_REPO" "$SID_A" "alpha" "aalpha-aaaaaaaaaaaaaaaa"
roster_row "$LX_REPO" "$SID_A" "beta" "abeta-bbbbbbbbbbbbbbbb"
roster_row "$LX_REPO" "$SID_A" "gamma" "agamma-cccccccccccccccc"
observe "$SID_A" "$LX_TR" "$LX_REPO" "alpha"
observe "$SID_A" "$LX_TR" "$LX_REPO" "beta"
observe "$SID_A" "$LX_TR" "$LX_REPO" "gamma"
sleep 1
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"still here"}]}}\n' \
  >> "$LX_SUB/agent-abeta-bbbbbbbbbbbbbbbb.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$LX_TR" "$LX_REPO" "alpha")"
expect_status "long exchange: dormant alpha still stoppable" 0 "$GUARD_ST"
run_guard "$(mk_stop_payload "$SID_A" "$LX_TR" "$LX_REPO" "beta")"
expect_status "long exchange: beta woke up — its earlier observation is stale" 2 "$GUARD_ST"
run_guard "$(mk_stop_payload "$SID_A" "$LX_TR" "$LX_REPO" "gamma")"
expect_status "long exchange: gamma's own observation survives the others" 0 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 6: D-2 — one observation, one stop (AC-5) ==="
# ============================================================

IFS='|' read -r D2R_REPO D2R_TR D2R_SUB <<< "$(make_world d2 yes)"
plant_agent "$D2R_SUB" "arunner-dddddddddddddddd" "runner"
roster_row "$D2R_REPO" "$SID_A" "runner" "arunner-dddddddddddddddd"
observe "$SID_A" "$D2R_TR" "$D2R_REPO" "runner"
run_guard "$(mk_stop_payload "$SID_A" "$D2R_TR" "$D2R_REPO" "runner")"
expect_status "the first stop is permitted" 0 "$GUARD_ST"
expect_absent "a permitted stop CONSUMES its observation" \
  "arunner-dddddddddddddddd" "$(cat "$D2R_REPO/$STATE_REL" 2>/dev/null)"

run_guard "$(mk_stop_payload "$SID_A" "$D2R_TR" "$D2R_REPO" "runner")"
expect_status "a second stop without a fresh observation: REFUSED" 2 "$GUARD_ST"

observe "$SID_A" "$D2R_TR" "$D2R_REPO" "runner"
run_guard "$(mk_stop_payload "$SID_A" "$D2R_TR" "$D2R_REPO" "runner")"
expect_status "re-observing re-arms the stop" 0 "$GUARD_ST"

# A REFUSED stop consumes nothing — nothing was stopped.
IFS='|' read -r D2B_REPO D2B_TR D2B_SUB <<< "$(make_world d2b yes)"
plant_agent "$D2B_SUB" "abusy-eeeeeeeeeeeeeeee" "busy"
roster_row "$D2B_REPO" "$SID_A" "busy" "abusy-eeeeeeeeeeeeeeee"
observe "$SID_A" "$D2B_TR" "$D2B_REPO" "busy"
sleep 1
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"awake"}]}}\n' \
  >> "$D2B_SUB/agent-abusy-eeeeeeeeeeeeeeee.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$D2B_TR" "$D2B_REPO" "busy")"
expect_status "the stale stop is refused" 2 "$GUARD_ST"
expect_contains "a REFUSED stop consumes nothing" \
  "abusy-eeeeeeeeeeeeeeee" "$(cat "$D2B_REPO/$STATE_REL" 2>/dev/null)"

# ============================================================
echo ""
echo "=== Section 6a: the refusal's Fix line is runnable AS PRINTED (R2) ==="
# ============================================================
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
roster_row "$R2_REPO" "$SID_A" "blocked" "ablocked-aaaaaaaaaaaaaaaa"
run_guard "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "blocked")"
expect_status "the stop with no observation is refused (setup for R2)" 2 "$GUARD_ST"
FIXLINE=$(printf '%s\n' "$GUARD_ERR" | grep '^Fix: ' | sed 's/^Fix: //')
expect_contains "a fix line was captured to execute" "stop-check.sh" "$FIXLINE"
expect_absent "the fix line carries no bracketed placeholder (R2)" "[" "$FIXLINE"

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
  ok "the captured fix line executes from a non-repo cwd (exit $R2_ST)"
fi
expect_absent "running the fix line as printed reports no fabricated deliverable" \
  "— ABSENT" "$R2_OUT"
expect_absent "running the fix line as printed produces no usage error" "Usage:" "$R2_OUT"

# ============================================================
echo ""
echo "=== Section 6b: the lock and the consume — the failure paths (C3, S2) ==="
# ============================================================
#
# This region shipped with no callsite at all (Step-6 architecture review A4),
# and both a fail-OPEN consume (C3) and an unbounded spin (S2) lived in it.

# --- C3: a consume that cannot complete must REFUSE the stop ---
#
# The rename is the one consume failure a fixture cannot provoke directly (the
# other two — lock held, no writable temp — deny already and are driven below).
# Proven the way §9 names as durable: mutate a COPY so the rename targets an
# unwritable path, drive it, then re-checksum the shipped file.
GUARD_SUM_BEFORE=$(shasum "$GUARD" | awk '{print $1}')
MUTANT="$SANDBOX/stop-guard.consume-fails.sh"
sed 's|mv -f "$TMP" "$STATE_FILE" 2>/dev/null|mv -f "$TMP" "/nonexistent-dir-0xdead/x" 2>/dev/null|' \
  "$GUARD" > "$MUTANT"
if grep -qF '/nonexistent-dir-0xdead/x' "$MUTANT"; then
  ok "the consume-failure mutation applied (a mutation matching nothing must FAIL, not skip)"
else
  no "the consume-failure mutation applied (a mutation matching nothing must FAIL, not skip)"
fi

IFS='|' read -r C3_REPO C3_TR C3_SUB <<< "$(make_world c3 yes)"
plant_agent "$C3_SUB" "aunconsumable-5555555555555555" "unconsumable"
roster_row "$C3_REPO" "$SID_A" "unconsumable" "aunconsumable-5555555555555555"
observe "$SID_A" "$C3_TR" "$C3_REPO" "unconsumable"
C3_PAYLOAD=$(mk_stop_payload "$SID_A" "$C3_TR" "$C3_REPO" "unconsumable")
C3_ERR=$(printf '%s' "$C3_PAYLOAD" | bash "$MUTANT" 2>&1 >/dev/null)
C3_ST=$?
expect_status "a consume that cannot complete REFUSES the stop (C3)" 2 "$C3_ST"
expect_contains "the refusal says the record could not be consumed (C3)" \
  "could not be consumed" "$C3_ERR"
expect_contains "the record survives an unconsumed stop, so D-2 still holds it" \
  "aunconsumable-5555555555555555" "$(cat "$C3_REPO/$STATE_REL" 2>/dev/null)"
if [ -d "$C3_REPO/.bionic/tmp/.stop-check.lock" ]; then
  no "a refused consume RELEASES the lock" "the lock survived, wedging every later stop"
else
  ok "a refused consume RELEASES the lock"
fi
expect_status "the shipped script was never modified by the mutation proof" 0 \
  "$([ "$GUARD_SUM_BEFORE" = "$(shasum "$GUARD" | awk '{print $1}')" ]; echo $?)"

# --- S2: the gate may not spin forever when the lock cannot be taken ---
#
# `mkdir` fails for reasons a stale-lock reclaim cannot fix — an unwritable state
# directory is repo-controlled — and `rm -rf` of an ABSENT path SUCCEEDS, so a
# reclaim-and-retry loop with no hard bound never terminates. A PreToolUse hook
# that never returns renders no verdict at all, which §7's table has no row for.
# The writer's half of this row is in hooks/execution-recorder.test.sh §8.
run_bounded() {  # <label> <secs> <payload> -> sets BOUNDED_ST (137 = killed)
  local secs="$2" payload="$3" waited=0 pid
  printf '%s' "$payload" | bash "$GUARD" >"$SANDBOX/.bout" 2>"$SANDBOX/.berr" &
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

IFS='|' read -r S2_REPO S2_TR S2_SUB <<< "$(make_world s2 yes)"
plant_agent "$S2_SUB" "awedged-6666666666666666" "wedged"
roster_row "$S2_REPO" "$SID_A" "wedged" "awedged-6666666666666666"
observe "$SID_A" "$S2_TR" "$S2_REPO" "wedged"        # a valid record, so the gate reaches the consume
mkdir -p "$S2_REPO/.bionic/tmp"
chmod 500 "$S2_REPO/.bionic/tmp"

run_bounded "gate" 12 "$(mk_stop_payload "$SID_A" "$S2_TR" "$S2_REPO" "wedged")"
if [ "$BOUNDED_ST" = "137" ]; then
  no "the GATE arm terminates when the lock cannot be taken (S2)" "still running after 12s"
else
  expect_status "the GATE arm REFUSES rather than spinning (S2, §7 stop=closed)" 2 "$BOUNDED_ST"
  expect_contains "the lock refusal says why and names the state directory" \
    "could not be consumed" "$(cat "$SANDBOX/.berr")"
fi
chmod 700 "$S2_REPO/.bionic/tmp"

# ============================================================
echo ""
echo "=== Section 7: hostile repo (AC-8, TDD §8, checklist A2/A3) ==="
# ============================================================

# Predictable temp names + symlink-following writes were a PROVEN arbitrary-file
# overwrite in the discarded run (corr-sec S1/S2). Both levels are replanted.
IFS='|' read -r S_REPO S_TR S_SUB <<< "$(make_world sec yes)"
plant_agent "$S_SUB" "avictim-ffffffffffffffff" "victim"
mkdir -p "$S_REPO/.bionic/tmp"
VICTIM_FILE="$SANDBOX/sec-outside-file.txt"
echo "ORIGINAL CONTENT" > "$VICTIM_FILE"
ln -s "$VICTIM_FILE" "$S_REPO/$STATE_REL"
observe "$SID_A" "$S_TR" "$S_REPO" "victim"
expect_contains "a planted state symlink is not written through (file level)" \
  "ORIGINAL CONTENT" "$(cat "$VICTIM_FILE")"

# The gate refuses to READ through a planted symlink — the direction that is
# uniquely its own. A repo that can choose which file this gate reads its evidence
# out of can OPEN the wall, which §8 forbids; the write side of the same planted
# path is the writer's row, in hooks/execution-recorder.test.sh §7.
run_guard "$(mk_stop_payload "$SID_A" "$S_TR" "$S_REPO" "victim")"
expect_status "a symlinked state path refuses the stop" 2 "$GUARD_ST"
expect_contains "the symlink refusal says what it found" "symlink" "$GUARD_ERR"

IFS='|' read -r S2_REPO S2_TR S2_SUB <<< "$(make_world sec2 yes)"
plant_agent "$S2_SUB" "avictim-ffffffffffffffff" "victim"
OUTSIDE_DIR="$SANDBOX/sec2-outside-dir"
mkdir -p "$OUTSIDE_DIR" "$S2_REPO/.bionic"
ln -s "$OUTSIDE_DIR" "$S2_REPO/.bionic/tmp"
observe "$SID_A" "$S2_TR" "$S2_REPO" "victim"
if [ -z "$(ls -A "$OUTSIDE_DIR")" ]; then
  ok "a planted directory symlink is not written through (directory level)"
else
  no "a planted directory symlink is not written through (directory level)" "$(ls -A "$OUTSIDE_DIR")"
fi
run_guard "$(mk_stop_payload "$SID_A" "$S2_TR" "$S2_REPO" "victim")"
expect_status "a symlinked state DIRECTORY refuses the stop too" 2 "$GUARD_ST"

# The ROSTER is repo-controlled state too, so a symlink at its own level would let
# a repo choose which file answers a question the gate asks — the OPEN direction §8
# forbids a repo from reaching. Since slice 4/9 the roster answers ownership for
# exactly one case, a `confirmed` row keyed on AGENT ID reaching a target outside
# this session's own directory, and that is the case driven here: a planted roster
# claiming a foreign-filed agent as ours. Refusing to read through the link leaves
# the claim unmade, which is the closed side. (A same-directory target needs no
# roster at all now, so a repo has nothing to gain by pointing this file anywhere.)
IFS='|' read -r SR_REPO SR_TR SR_SUB <<< "$(make_world secroster yes)"
SR_TR_B="${SR_TR%/*}/$SID_B.jsonl"
plant_agent "${SR_TR_B%.jsonl}/subagents" "avictim-1818181818181818" "victim"
roster_row "$SANDBOX/plantedroster" "$SID_A" "victim" "avictim-1818181818181818"
mkdir -p "$SR_REPO/.bionic/tmp"
ln -s "$SANDBOX/plantedroster/.bionic/tmp/roster-$SID_A.state" \
  "$SR_REPO/.bionic/tmp/roster-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$SR_TR_B" "$SR_REPO" "victim")"
expect_status "a symlinked roster refuses the stop" 2 "$GUARD_ST"
expect_contains "…because it was not read through: the ownership claim is never made" \
  "was not launched by this session" "$GUARD_ERR"

# Unpredictable temp names: mktemp with an X-template, and no PID-based name.
expect_matches "temp files use an mktemp X-template" 'mktemp.*XXXXXX' "$(cat "$GUARD")"
expect_absent "no PID-based temp filename" '.tmp.$$' "$(cat "$GUARD")"

# The gate reads the working log; it must never quote it. (§8 keeps that
# disclosure in the observation, whose whole purpose is to show it to a reader.)
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"CANARY_LOG_BODY"}]}}\n' \
  >> "$S_SUB/agent-avictim-ffffffffffffffff.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$S_TR" "$S_REPO" "victim")"
expect_absent "the refusal prints no working-log contents" "CANARY_LOG_BODY" "$GUARD_ERR"

# ============================================================
echo ""
echo "=== Section 8: D-3 — a stop is discharged only by the STOPPER'S OWN look (AC-4) ==="
# ============================================================
#
# The borrowed look. D-1 makes an observation perishable, but nothing made it
# ATTRIBUTABLE: any record for the target discharged any actor's stop, so a
# subagent's look could pay for the orchestrator's stop and neither one had seen
# what the other saw. Slice 4/1 resolved assumption (A) FULL — a subagent-invoked
# payload carries top-level `agent_id`, the orchestrator's does not — so the
# comparison is one payload field against the `observer=` field the recorder
# wrote out of ITS payload. Same key, both ends.

IFS='|' read -r SA_REPO SA_TR SA_SUB <<< "$(make_world sameactor yes)"
plant_agent "$SA_SUB" "aworker-1010101010101010" "worker"
roster_row "$SA_REPO" "$SID_A" "worker" "aworker-1010101010101010"
SUBAGENT="asubagent-2020202020202020"

observe_as "$SUBAGENT" "$SID_A" "$SA_TR" "$SA_REPO" "worker"
expect_contains "the record carries the actor who looked" \
  "observer=$SUBAGENT" "$(cat "$SA_REPO/$STATE_REL" 2>/dev/null)"

run_guard "$(mk_stop_payload "$SID_A" "$SA_TR" "$SA_REPO" "worker")"
expect_status "a subagent's look does not discharge the ORCHESTRATOR's stop" 2 "$GUARD_ST"
expect_contains "the refusal names the actor who looked" "$SUBAGENT" "$GUARD_ERR"
expect_contains "the refusal names the actor who is stopping" "orchestrator" "$GUARD_ERR"
expect_contains "the same-actor refusal names the fix" "stop-check.sh" "$GUARD_ERR"
expect_contains "a refused same-actor stop consumes nothing" \
  "aworker-1010101010101010" "$(cat "$SA_REPO/$STATE_REL" 2>/dev/null)"

# The positive pair: the actor that looked may spend its own look.
run_guard "$(mk_stop_payload_as "$SID_A" "$SA_TR" "$SA_REPO" "worker" "$SUBAGENT")"
expect_status "the actor who looked spends its own observation" 0 "$GUARD_ST"
expect_empty "and does so in silence" "$GUARD_ERR"

# The mirror image: the orchestrator looked, a subagent tries to spend it.
IFS='|' read -r SB_REPO SB_TR SB_SUB <<< "$(make_world sameactor2 yes)"
plant_agent "$SB_SUB" "aworker-3030303030303030" "worker"
roster_row "$SB_REPO" "$SID_A" "worker" "aworker-3030303030303030"
observe "$SID_A" "$SB_TR" "$SB_REPO" "worker"
expect_contains "an orchestrator look records the orchestrator as observer" \
  "observer=orchestrator" "$(cat "$SB_REPO/$STATE_REL" 2>/dev/null)"
run_guard "$(mk_stop_payload_as "$SID_A" "$SB_TR" "$SB_REPO" "worker" "$SUBAGENT")"
expect_status "the orchestrator's look does not discharge a SUBAGENT's stop" 2 "$GUARD_ST"
expect_contains "the refusal names the subagent doing the stopping" "$SUBAGENT" "$GUARD_ERR"
run_guard "$(mk_stop_payload "$SID_A" "$SB_TR" "$SB_REPO" "worker")"
expect_status "…and the orchestrator can still spend its own" 0 "$GUARD_ST"

# A record with no observer at all cannot prove same-actor, so it does not
# discharge anything. Fail-closed: this is the §7 stop cell, and the cost of the
# refusal is one re-observation.
IFS='|' read -r SC_REPO SC_TR SC_SUB <<< "$(make_world sameactor3 yes)"
plant_agent "$SC_SUB" "aworker-4040404040404040" "worker"
roster_row "$SC_REPO" "$SID_A" "worker" "aworker-4040404040404040"
observe "$SID_A" "$SC_TR" "$SC_REPO" "worker"
sed -i.bak 's/|observer=[^|]*//' "$SC_REPO/$STATE_REL"; rm -f "$SC_REPO/$STATE_REL.bak"
expect_absent "the observer field was genuinely stripped for this case" \
  "observer=" "$(cat "$SC_REPO/$STATE_REL" 2>/dev/null)"
run_guard "$(mk_stop_payload "$SID_A" "$SC_TR" "$SC_REPO" "worker")"
expect_status "a record carrying no observer discharges nothing" 2 "$GUARD_ST"
expect_contains "…and says the look cannot be attributed" "observer" "$GUARD_ERR"

# ============================================================
echo ""
echo "=== Section 9: D-6 — the contracted progress artifact is a second activity channel (AC-5) ==="
# ============================================================
#
# D-1 watched ONE channel: the working log. An agent that spends 40 minutes
# inside a single tool call writes nothing to it, so "dormant since your look"
# was true of a wedged agent and a working one alike — and the work contract's
# own progress artifact, the thing that separates them, counted for nothing at
# the gate. Since slice 4/5 the observation records the progress state it saw;
# this gate compares that snapshot against the artifact as it is NOW, by exactly
# the rule the working log already follows: any activity after the look stales
# the look.

PROG_REL=".bionic/tmp/prog.txt"

IFS='|' read -r PG_REPO PG_TR PG_SUB <<< "$(make_world progress yes)"
plant_agent "$PG_SUB" "arunner-1212121212121212" "runner"
roster_row "$PG_REPO" "$SID_A" "runner" "arunner-1212121212121212" "$PROG_REL"
mkdir -p "$PG_REPO/.bionic/tmp"
printf 'stage 1\n' > "$PG_REPO/$PROG_REL"

observe "$SID_A" "$PG_TR" "$PG_REPO" "runner"
PG_STATE=$(cat "$PG_REPO/$STATE_REL" 2>/dev/null)
expect_contains "the contract reached the record from the ROSTER, not the command line" \
  "progress_source=roster" "$PG_STATE"
expect_contains "the record carries the progress state the look saw" \
  "progress_state=present" "$PG_STATE"

# A stop taken with nothing having moved is permitted — the check must not refuse
# on the mere existence of a progress contract.
run_guard "$(mk_stop_payload "$SID_A" "$PG_TR" "$PG_REPO" "runner")"
expect_status "progress unchanged since the look: PERMITTED" 0 "$GUARD_ST"

observe "$SID_A" "$PG_TR" "$PG_REPO" "runner"
sleep 1
printf 'stage 2\n' >> "$PG_REPO/$PROG_REL"
run_guard "$(mk_stop_payload "$SID_A" "$PG_TR" "$PG_REPO" "runner")"
expect_status "progress written AFTER the look: REFUSED as stale" 2 "$GUARD_ST"
expect_contains "the refusal names the progress artifact it compared" "$PROG_REL" "$GUARD_ERR"
expect_contains "the refusal says the observation went stale" "stale" "$GUARD_ERR"
expect_contains "the progress refusal names the fix" "stop-check.sh" "$GUARD_ERR"
expect_absent "the progress refusal quotes no clock window" "seconds ago" "$GUARD_ERR"
expect_absent "the progress refusal prints no progress CONTENTS" "stage 2" "$GUARD_ERR"
expect_contains "a stop refused on progress staleness consumes nothing" \
  "arunner-1212121212121212" "$(cat "$PG_REPO/$STATE_REL" 2>/dev/null)"

# A fresh look over the NEW state re-arms it — the loop the refusal names has an exit.
observe "$SID_A" "$PG_TR" "$PG_REPO" "runner"
run_guard "$(mk_stop_payload "$SID_A" "$PG_TR" "$PG_REPO" "runner")"
expect_status "a fresh look over the new progress state re-arms the stop" 0 "$GUARD_ST"

# The artifact APPEARING is activity too: "absent" and "present" are different
# states, and a first write may land inside the same mtime second as the look.
IFS='|' read -r PA_REPO PA_TR PA_SUB <<< "$(make_world progressappear yes)"
plant_agent "$PA_SUB" "arunner-1313131313131313" "runner"
roster_row "$PA_REPO" "$SID_A" "runner" "arunner-1313131313131313" "$PROG_REL"
mkdir -p "$PA_REPO/.bionic/tmp"
observe "$SID_A" "$PA_TR" "$PA_REPO" "runner"
expect_contains "the look recorded the contracted artifact as ABSENT" \
  "progress_state=absent" "$(cat "$PA_REPO/$STATE_REL" 2>/dev/null)"
printf 'first write\n' > "$PA_REPO/$PROG_REL"
run_guard "$(mk_stop_payload "$SID_A" "$PA_TR" "$PA_REPO" "runner")"
expect_status "the contracted artifact appearing after the look: REFUSED" 2 "$GUARD_ST"

# NO progress contract: the whole check is inert, and the world behaves exactly
# as it did before this slice. A wall that fires where nothing was contracted
# would refuse every ordinary stop.
IFS='|' read -r PN_REPO PN_TR PN_SUB <<< "$(make_world progressnone yes)"
plant_agent "$PN_SUB" "arunner-1414141414141414" "runner"
roster_row "$PN_REPO" "$SID_A" "runner" "arunner-1414141414141414"
mkdir -p "$PN_REPO/.bionic/tmp"
observe "$SID_A" "$PN_TR" "$PN_REPO" "runner"
expect_contains "with no contracted path the look records progress_state=unnamed" \
  "progress_state=unnamed" "$(cat "$PN_REPO/$STATE_REL" 2>/dev/null)"
sleep 1
printf 'unrelated\n' > "$PN_REPO/$PROG_REL"
run_guard "$(mk_stop_payload "$SID_A" "$PN_TR" "$PN_REPO" "runner")"
expect_status "no progress contract: an unrelated file's write changes nothing" 0 "$GUARD_ST"

# A CONTRACTED channel the look never opened. The observation ran without its own
# session key (slice 4/5's `unknown` case), so it never saw the roster and never
# looked at the progress artifact — and an artifact nobody looked at can never go
# stale, which would make the check above unreachable by simply looking wrong.
IFS='|' read -r PU_REPO PU_TR PU_SUB <<< "$(make_world progressunseen yes)"
plant_agent "$PU_SUB" "arunner-1515151515151515" "runner"
roster_row "$PU_REPO" "$SID_A" "runner" "arunner-1515151515151515" "$PROG_REL"
mkdir -p "$PU_REPO/.bionic/tmp"
printf 'stage 1\n' > "$PU_REPO/$PROG_REL"
observe_nosid "$SID_A" "$PU_TR" "$PU_REPO" "runner"
expect_contains "the blind look recorded no progress channel at all" \
  "progress_state=unnamed" "$(cat "$PU_REPO/$STATE_REL" 2>/dev/null)"
run_guard "$(mk_stop_payload "$SID_A" "$PU_TR" "$PU_REPO" "runner")"
expect_status "a look that skipped the contracted channel discharges nothing" 2 "$GUARD_ST"
expect_contains "…and names the contracted path it should have looked at" "$PROG_REL" "$GUARD_ERR"
PU_FIX=$(printf '%s\n' "$GUARD_ERR" | grep '^Fix: ' | sed 's/^Fix: //')
expect_contains "…and the fix command carries the progress flag, runnable as printed" \
  "--progress $PROG_REL" "$PU_FIX"
# Following the fix as printed clears the refusal — the loop has a stated exit.
observe_nosid "$SID_A" "$PU_TR" "$PU_REPO" "runner" "--progress" "$PROG_REL"
run_guard "$(mk_stop_payload "$SID_A" "$PU_TR" "$PU_REPO" "runner")"
expect_status "observing the contracted channel as instructed re-arms the stop" 0 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 10: AC-6 — what this session did not launch, it does not stop BY NAME ==="
# ============================================================
#
# THE bb20f616 EXHIBIT. A previous epic's dead fleet left agent metadata on disk
# answering to names a live session was still using; a stop by name resolved to
# whichever one the scan found first. A name is not an identity. The escape hatch
# is the full agent id, which is unambiguous by construction and is how the
# documented zombie-predecessor cleanup is done; it buys no relief from the
# observation requirements.
#
# WHAT IDENTITY IS, corrected in slice 4/9 after live operation: the metadata's
# own filing. An agent under <session>/subagents/ was launched by <session>. Slice
# 4/6 keyed this on ROSTER MEMBERSHIP instead and both arms failed live —
# unconfirmed rows (the standing state until a session restarts) matched by NAME
# and handed ownership to another session's corpse, while every agent dispatched
# before the roster hook shipped had no row and was refused as foreign. The roster
# is still read for the CONTRACT, and a `confirmed` row still establishes
# ownership BY AGENT ID; it is never a name-oracle again.
#
# Agent id shape SYNTHESIZED after the exhibit named in continuation.md; the
# session ids and names are fixtures, as everywhere else in this suite.

# The corpse collision AT THE GATE: an UNCONFIRMED row of ours (agent_id empty)
# naming `reviewer`, and a `reviewer` filed under ANOTHER session's directory.
# Reaching it needs a stop whose transcript path and session key disagree, which
# is the only way a target outside this session's own directory ever resolves
# here — and it is exactly the disagreement the owning-directory key detects.
IFS='|' read -r FG_REPO FG_TR FG_SUB <<< "$(make_world foreignstop yes)"
FG_TR_B="${FG_TR%/*}/$SID_B.jsonl"
FG_SUB_B="${FG_TR_B%.jsonl}/subagents"
plant_agent "$FG_SUB_B" "abb20f616-7777777777777" "reviewer"
roster_row "$FG_REPO" "$SID_A" "reviewer" "" "" "intended"

# A fresh, well-formed observation first, so that what is asserted below is the
# OWNERSHIP refusal and not the ordinary missing-observation one — without it every
# assertion here would pass on a fixture that never reached the rule under test.
# Before slice 4/9 this pair PERMITTED the stop: the name matched an unconfirmed
# row, so the corpse was treated as ours and its record spent.
observe "$SID_A" "$FG_TR_B" "$FG_REPO" "abb20f616-7777777777777"
run_guard "$(mk_stop_payload "$SID_A" "$FG_TR_B" "$FG_REPO" "reviewer")"
expect_status "a target filed under ANOTHER session, matched only by an unconfirmed row's NAME: REFUSED" \
  2 "$GUARD_ST"
expect_absent "…and it is not the missing-observation refusal — a fresh record exists" \
  "No observation" "$GUARD_ERR"
expect_contains "the refusal names the directory it keyed on" "filed under session" "$GUARD_ERR"
expect_contains "the refusal names the classification" "FOREIGN" "$GUARD_ERR"
expect_absent "…and never the retired label that claimed the agent was live" \
  "FOREIGN-LIVE" "$GUARD_ERR"
expect_contains "the refusal names the full-id escape hatch" \
  "abb20f616-7777777777777" "$GUARD_ERR"

# THE OTHER DIRECTION, and the one that broke live operation: an agent this
# session really launched, with NO roster row at all — the standing state for
# everything dispatched before the roster hook shipped. Slice 4/6 refused these.
IFS='|' read -r UO_REPO UO_TR UO_SUB <<< "$(make_world unrosteredours yes)"
plant_agent "$UO_SUB" "asibling-1818181818181818" "sibling"
run_guard "$(mk_stop_payload "$SID_A" "$UO_TR" "$UO_REPO" "sibling")"
expect_status "an unrostered agent under THIS session's own directory is not refused as foreign" \
  2 "$GUARD_ST"
expect_absent "…the refusal is the ordinary missing-observation one, not a foreign one" \
  "FOREIGN" "$GUARD_ERR"
observe "$SID_A" "$UO_TR" "$UO_REPO" "sibling"
run_guard "$(mk_stop_payload "$SID_A" "$UO_TR" "$UO_REPO" "sibling")"
expect_status "…and its fresh observation discharges the stop BY NAME" 0 "$GUARD_ST"
expect_empty "…permitted in silence" "$GUARD_ERR"

# `name@team` is still a name (P5: the platform hands the gate the string as typed).
run_guard "$(mk_stop_payload "$SID_A" "$FG_TR_B" "$FG_REPO" "reviewer@team")"
expect_status "name@team is a name: REFUSED" 2 "$GUARD_ST"

# The escape hatch, spending the very record the by-name attempts left behind.
run_guard "$(mk_stop_payload "$SID_A" "$FG_TR_B" "$FG_REPO" "abb20f616-7777777777777")"
expect_status "the same target addressed by FULL AGENT ID: PERMITTED" 0 "$GUARD_ST"
expect_empty "…and permitted in silence" "$GUARD_ERR"

# The hatch is not a bypass: by-id still needs a fresh look of its own (D-2 spent
# the record above).
run_guard "$(mk_stop_payload "$SID_A" "$FG_TR_B" "$FG_REPO" "abb20f616-7777777777777")"
expect_status "by full id with no observation left: still REFUSED" 2 "$GUARD_ST"
expect_contains "…refused for the ordinary reason, not the foreign one" \
  "No observation" "$GUARD_ERR"

# THE `identified` STATE (epic-16 wave-01 slice 1). The by-id clause above keyed
# on `confirmed` alone, and in teammate mode a confirmed row can never carry a
# matchable id: the launch half only ever learns the ADDRESSING form, so
# `agent_id=` is written EMPTY there by design (capture probe §3 conclusion 3,
# recorder ARM 2). The transcript-form id arrives one state later, on
# SubagentStart, as an `identified` row — so under the old accepted set the
# ownership rule was unreachable for every teammate this repo dispatches, and
# widening it to `confirmed|identified` is what makes it reachable at all.
#
# Reaching the rule at all needs a target whose OWNING directory disagrees with
# the stopping session — the same construction the corpse-collision case above
# uses, and the only path on which ROSTER_ID_MATCH is consulted.
IFS='|' read -r ID_REPO ID_TR ID_SUB <<< "$(make_world identifiedrow yes)"
ID_TR_B="${ID_TR%/*}/$SID_B.jsonl"
ID_SUB_B="${ID_TR_B%.jsonl}/subagents"
plant_agent "$ID_SUB_B" "aroamer-5555555555555555" "roamer"
roster_row "$ID_REPO" "$SID_A" "roamer" "aroamer-5555555555555555" "" "identified"
observe "$SID_A" "$ID_TR_B" "$ID_REPO" "roamer"
run_guard "$(mk_stop_payload "$SID_A" "$ID_TR_B" "$ID_REPO" "roamer")"
expect_status "an IDENTIFIED row's id establishes ownership just as a confirmed one does" \
  0 "$GUARD_ST"
expect_empty "…and the stop is permitted in silence" "$GUARD_ERR"

# The tightening slice 4/9 bought is untouched: `intended` is still not an
# ownership claim, because the id on an unconfirmed row is a claim about a launch
# nothing has observed.
IFS='|' read -r II_REPO II_TR II_SUB <<< "$(make_world intendedrow yes)"
II_TR_B="${II_TR%/*}/$SID_B.jsonl"
II_SUB_B="${II_TR_B%.jsonl}/subagents"
plant_agent "$II_SUB_B" "adrifter-6666666666666666" "drifter"
roster_row "$II_REPO" "$SID_A" "drifter" "adrifter-6666666666666666" "" "intended"
observe "$SID_A" "$II_TR_B" "$II_REPO" "drifter"
run_guard "$(mk_stop_payload "$SID_A" "$II_TR_B" "$II_REPO" "drifter")"
expect_status "an INTENDED row's id still establishes nothing: REFUSED" 2 "$GUARD_ST"
expect_contains "…as FOREIGN, by the owning directory" "FOREIGN" "$GUARD_ERR"

# DEAD HISTORY: the same rule, and the refusal says which case it is. The
# distinction is the OWNING session's transcript — the check
# hooks/stop-check.sh and hooks/preflight-probe.sh already make.
IFS='|' read -r DH_REPO DH_TR DH_SUB <<< "$(make_world deadhistory yes)"
DH_TR_B="${DH_TR%/*}/$SID_B.jsonl"
plant_agent "${DH_TR_B%.jsonl}/subagents" "abb20f616-8888888888888" "reviewer"
rm -f "$DH_TR_B"
run_guard "$(mk_stop_payload "$SID_A" "$DH_TR_B" "$DH_REPO" "reviewer")"
expect_status "a dead-history target addressed by name: REFUSED" 2 "$GUARD_ST"
expect_contains "…and the refusal says the owning session's transcript is gone" \
  "DEAD HISTORY" "$GUARD_ERR"

# The `intended` row — written at dispatch, before any agent id exists (slice
# 4/3) — is no longer what makes a target ours; the directory is. What it still
# does is carry the CONTRACT, which is the one thing the record cannot supply.
IFS='|' read -r OI_REPO OI_TR OI_SUB <<< "$(make_world oursintended yes)"
plant_agent "$OI_SUB" "aworker-1616161616161616" "worker"
mkdir -p "$OI_REPO/.bionic/tmp"
roster_row "$OI_REPO" "$SID_A" "worker" "" "$PROG_REL" "intended"
printf 'stage 1\n' > "$OI_REPO/$PROG_REL"
observe "$SID_A" "$OI_TR" "$OI_REPO" "worker"
expect_contains "an intended row still supplies the contracted progress path by NAME" \
  "progress=$PROG_REL" "$(cat "$OI_REPO/$STATE_REL" 2>/dev/null)"
run_guard "$(mk_stop_payload "$SID_A" "$OI_TR" "$OI_REPO" "worker")"
expect_status "…and the stop of an agent in this session's own directory is permitted" 0 "$GUARD_ST"

# A roster belonging to ANOTHER session proves nothing about this one: the file
# is per-session by name (D-5), so this session simply never reads it — and the
# directory it names is not this session's either.
IFS='|' read -r XR_REPO XR_TR XR_SUB <<< "$(make_world foreignroster yes)"
XR_TR_B="${XR_TR%/*}/$SID_B.jsonl"
plant_agent "${XR_TR_B%.jsonl}/subagents" "aworker-1717171717171717" "worker"
roster_row "$XR_REPO" "$SID_B" "worker" "aworker-1717171717171717"
observe "$SID_A" "$XR_TR_B" "$XR_REPO" "worker"
run_guard "$(mk_stop_payload "$SID_A" "$XR_TR_B" "$XR_REPO" "worker")"
expect_status "another session's roster does not make a target ours" 2 "$GUARD_ST"

# C-2 (Step-6 six-axis review). The by-id ownership clause is keyed on a
# CONFIRMED row, not merely on a non-empty `agent_id=`. The comment beside it
# always stated the invariant that way; the code checked only non-emptiness and
# leaned on a property of a DIFFERENT file — hooks/dispatch-preflight.sh emits
# `agent_id=` empty on every `intended` row — to keep that true. An invariant
# enforced somewhere else is the shape slice 4/9 existed to remediate, and here
# it opens the wall: an `intended` row carrying an id is enough to walk the
# corpse past the foreign rule, and with a fresh record of its own the stop is
# PERMITTED.
IFS='|' read -r IR_REPO IR_TR IR_SUB <<< "$(make_world intendedid yes)"
IR_TR_B="${IR_TR%/*}/$SID_B.jsonl"
IR_SUB_B="${IR_TR_B%.jsonl}/subagents"
plant_agent "$IR_SUB_B" "aintended-1919191919191" "stranger"
roster_row "$IR_REPO" "$SID_A" "some-other-name" "aintended-1919191919191" "" "intended"
observe "$SID_A" "$IR_TR_B" "$IR_REPO" "aintended-1919191919191"
run_guard "$(mk_stop_payload "$SID_A" "$IR_TR_B" "$IR_REPO" "stranger")"
expect_status "an INTENDED row's id does not make a foreign target ours: REFUSED" 2 "$GUARD_ST"
expect_contains "…and it is the OWNERSHIP refusal, not the missing-observation one" \
  "filed under session" "$GUARD_ERR"
expect_absent "…which is what a fresh record of its own would otherwise have spent" \
  "No observation" "$GUARD_ERR"

# The other half of the same invariant, unchanged: a CONFIRMED row's id still
# establishes ownership. Slice 4/9 kept that on purpose — an id is unambiguous
# by construction and a confirmed row is this session's own record of its own
# launch — so the tightening above must not take it away.
IFS='|' read -r CR_REPO CR_TR CR_SUB <<< "$(make_world confirmedid yes)"
CR_TR_B="${CR_TR%/*}/$SID_B.jsonl"
CR_SUB_B="${CR_TR_B%.jsonl}/subagents"
plant_agent "$CR_SUB_B" "aconfirmed-2121212121212" "stranger"
roster_row "$CR_REPO" "$SID_A" "some-other-name" "aconfirmed-2121212121212" "" "confirmed"
observe "$SID_A" "$CR_TR_B" "$CR_REPO" "aconfirmed-2121212121212"
run_guard "$(mk_stop_payload "$SID_A" "$CR_TR_B" "$CR_REPO" "stranger")"
expect_status "a CONFIRMED row's id still establishes ownership: PERMITTED" 0 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 11: FACTS DISCHARGE THE STOP (epic-16 w2 S3, AC-1/AC-2, R2) ==="
# ============================================================
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
roster_row "$F_REPO" "$SID_A" "lander" "alander-1111111111111111" "" "confirmed" \
  ".bionic/docs/record/lander.md"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "lander")"
expect_status "MET contract: the stop passes with NO observation ever taken" 0 "$GUARD_ST"
expect_empty "…and the gate says nothing at all — zero ceremony" "$GUARD_ERR"

# --- paired negative: same world, same everything, artifact absent ---
plant_agent "$F_SUB" "aslacker-2222222222222222" "slacker"
roster_row "$F_REPO" "$SID_A" "slacker" "aslacker-2222222222222222" "" "confirmed" \
  ".bionic/docs/record/slacker.md"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "slacker")"
expect_status "UNMET contract: the ceremony survives — REFUSED" 2 "$GUARD_ST"
expect_contains "…with the observation refusal, not a landing one" \
  "No observation has been recorded" "$GUARD_ERR"

# --- WAIVED: an explicit designation discharges as surely as an artifact ---
plant_agent "$F_SUB" "awaived-3333333333333333" "waived-one"
roster_row "$F_REPO" "$SID_A" "waived-one" "awaived-3333333333333333" "" "confirmed" \
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
roster_row "$F_REPO" "$SID_A" "acked-one" "aacked-4444444444444444" "" "confirmed" \
  ".bionic/docs/record/never-written.md"
ack_row "$F_REPO" "$SID_A" "acked-one"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "acked-one")"
expect_status "ACKED row: the stop passes though the contract is UNMET" 0 "$GUARD_ST"
expect_empty "…and silently" "$GUARD_ERR"

# An ack of a DIFFERENT row closes nothing here — whole-name match, never a
# substring, and never the whole roster.
plant_agent "$F_SUB" "aacked-5555555555555555" "acked-one-more"
roster_row "$F_REPO" "$SID_A" "acked-one-more" "aacked-5555555555555555" "" "confirmed" \
  ".bionic/docs/record/never-written-2.md"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "acked-one-more")"
expect_status "a neighbouring ack does not discharge this row: REFUSED" 2 "$GUARD_ST"

# --- the VACUOUS MET keeps its ceremony ---
#
# `verdict` calls a row that declared no artifact MET, correctly — it names
# nothing to hold the agent to. That is not a landing, and treating it as one
# would discharge every contract-less dispatch on a fact nobody produced. AC-1
# says MET means "artifact delivered"; ack is what closes the rest.
plant_agent "$F_SUB" "anothing-6666666666666666" "declares-nothing"
roster_row "$F_REPO" "$SID_A" "declares-nothing" "anothing-6666666666666666"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "declares-nothing")"
expect_status "a row that declared NOTHING is not discharged by its vacuous MET" 2 "$GUARD_ST"

# --- a repo-controlled ledger cannot open this gate ---
#
# The CLOSED half of the pair whose open half is at the landing gate
# (hooks/landing-gate.test.sh §8f). A repo owns its own .bionic/, so a symlinked ledger is
# a set of acks nobody in this session recorded: the sweeper — the ONE reader of that file
# since S9 — refuses to answer over it at all, so no `acked=` reaches this gate, and this
# gate, which is CLOSED and loud after the active-wave verdict, refuses the stop even though
# the artifact is on disk. That last part is the point: the refusal costs a re-run, and the
# alternative was letting a repo choose which acks this session recorded. The same fixture
# passes at the landing gate,
# which is fail-open by design. Opposite directions, one fixture, both deliberate.
plant_agent "$F_SUB" "alinked-8888888888888888" "linked-ledger"
roster_row "$F_REPO" "$SID_A" "linked-ledger" "alinked-8888888888888888" "" "confirmed" \
  ".bionic/docs/record/lander.md"
mkdir -p "$SANDBOX/elsewhere"
printf '# bionic sweeper ledger — schema sweeper-ledger/v1\nsweeper-ledger/v1|event=ack|at=2026-08-11T00:00:00Z|epoch=1|pid=1|session=%s|name=linked-ledger\n' \
  "$SID_A" > "$SANDBOX/elsewhere/ledger.state"
ln -sf "$SANDBOX/elsewhere/ledger.state" "$F_REPO/.bionic/tmp/sweeper-$SID_A.state"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "linked-ledger")"
expect_status "a symlinked ledger discharges nothing: REFUSED though the artifact is there" 2 "$GUARD_ST"
rm -f "$F_REPO/.bionic/tmp/sweeper-$SID_A.state"

# --- no roster row at all: unchanged ---
plant_agent "$F_SUB" "aunrostered-777777777777" "unrostered"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "unrostered")"
expect_status "a target on no roster row is unchanged by any of this" 2 "$GUARD_ST"

# --- an ack for a name NO ROSTER ROW carries closes nothing here (epic-16 w2 S9) ---
#
# The one behavioural delta of S9's `acked=` promotion, pinned rather than left to be
# discovered. This gate used to open the ledger itself and match a bare name in it, so an
# ack recorded for a name the roster never carried discharged the stop. The ack now reaches
# it as a field on the verdict line for a ROW, and there is no row — so the ceremony stands.
#
# That is the ack verb's OWN semantics, which the gate had been the odd one out on: an ack
# for an unknown name is recorded with a warning and is "exempt the moment a row of that
# name appears" (session-sweeper.sh's ack verb, and hooks/session-sweeper.test.sh §4). The
# landing gate has always passed such a stop for an unrelated reason (a name on no row makes
# the verb exit 0 and the gate fail open), and the stand-down never sees one, so this is the
# reading all three now share.
plant_agent "$F_SUB" "aackless-9999999999999999" "acked-but-rowless"
ack_row "$F_REPO" "$SID_A" "acked-but-rowless"
run_guard "$(mk_stop_payload "$SID_A" "$F_TR" "$F_REPO" "acked-but-rowless")"
expect_status "an ack over a name no roster row carries does not discharge the stop" 2 "$GUARD_ST"
# The paired positive is one case up: the SAME ack verb, over a name that HAS a row, passes
# the same gate silently ("ACKED row: the stop passes though the contract is UNMET").

# ============================================================
echo ""
echo "=== Section 12: the USER-ORDERED stop executes, and reports (R3, AC-2) ==="
# ============================================================
#
# A human order is not evidence and it is not a discharge of the contract: it is
# an INSTRUCTION, and the gate's job in front of one is to get out of the way and
# say what is being given up. Never a refusal — a wall that argues with the
# person it exists to serve has mistaken who it works for.

IFS='|' read -r O_REPO O_TR O_SUB <<< "$(make_world orders yes)"
mkdir -p "$O_REPO/.bionic/docs/record"
plant_agent "$O_SUB" "aordered-1111111111111111" "ordered"
roster_row "$O_REPO" "$SID_A" "ordered" "aordered-1111111111111111" "" "confirmed" \
  ".bionic/docs/record/ordered.md"

# Precondition: without the order this is the ordinary live+unmet refusal.
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "ordered")"
expect_status "precondition — unmet and unordered: REFUSED" 2 "$GUARD_ST"

order_stop "$O_REPO" "$SID_A" "ordered"
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "ordered")"
expect_status "a user-ordered stop EXECUTES: permitted, no observation" 0 "$GUARD_ST"
expect_contains "…and names what is being given up" \
  ".bionic/docs/record/ordered.md" "$GUARD_ERR"
expect_absent "…as information, never as a refusal" "BLOCKED" "$GUARD_ERR"
expect_eq_lines "…in exactly one line" 1 "$GUARD_ERR"

# An order names ONE target. A stop of a different agent is not covered by it.
plant_agent "$O_SUB" "aunordered-22222222222" "unordered"
roster_row "$O_REPO" "$SID_A" "unordered" "aunordered-22222222222" "" "confirmed" \
  ".bionic/docs/record/unordered.md"
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "unordered")"
expect_status "an order for another target discharges nothing here: REFUSED" 2 "$GUARD_ST"

# AN ORDER IS A LIVE INSTRUCTION, NOT A STANDING ONE. It is bounded in time on
# purpose — the one place in this gate where a clock is right, because what is
# being bounded is an instruction's currency and not evidence's freshness. An
# expired order leaves the ceremony exactly where it was.
plant_agent "$O_SUB" "astale-333333333333333" "stale-order"
roster_row "$O_REPO" "$SID_A" "stale-order" "astale-333333333333333" "" "confirmed" \
  ".bionic/docs/record/stale-order.md"
order_stop "$O_REPO" "$SID_A" "stale-order" --at $(( $(date -u +%s) - 86400 ))
run_guard "$(mk_stop_payload "$SID_A" "$O_TR" "$O_REPO" "stale-order")"
expect_status "an EXPIRED order does not discharge: REFUSED" 2 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 13: an id form the STOPPER CAN ACTUALLY USE (field data 2026-08-11) ==="
# ============================================================
#
# The by-id escape hatch was unreachable in the field. The gate hands back the
# TRANSCRIPT-form id (`aname-<hex>`), the platform's stop primitive addresses a
# teammate as `name@session-xxxxxxxx`, and nothing bridged the two — so the
# refusal named a way out that the operator could not type. A refusal that cannot
# be cleared is a refusal that costs four calls and an ambiguity round, which is
# what it cost on 2026-08-11.

IFS='|' read -r I_REPO I_TR I_SUB <<< "$(make_world idforms yes)"
I_TR_B="${I_TR%/*}/$SID_B.jsonl"
I_SUB_B="${I_TR_B%.jsonl}/subagents"
plant_agent "$I_SUB_B" "aforeigner-11111111111" "foreigner"
roster_row "$I_REPO" "$SID_A" "foreigner" "" "" "confirmed" "" "" "foreigner@session-${SID_B:0:8}"

# The refusal still fires for a bare NAME — a name is not an identity, unchanged.
observe "$SID_A" "$I_TR_B" "$I_REPO" "aforeigner-11111111111"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR_B" "$I_REPO" "foreigner")"
expect_status "a bare name for a foreign-filed agent: still REFUSED" 2 "$GUARD_ST"
expect_contains "…and the way out is an address the stop primitive accepts" \
  "foreigner@session-${SID_B:0:8}" "$GUARD_ERR"

# …and the addressing form the platform actually hands the operator RESOLVES as
# an identity. It is unambiguous by construction in exactly the way the raw id
# is: it carries the launching session.
observe "$SID_A" "$I_TR_B" "$I_REPO" "aforeigner-11111111111"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR_B" "$I_REPO" "foreigner@session-${SID_B:0:8}")"
expect_status "the name@session form is an IDENTITY, not a name: PERMITTED" 0 "$GUARD_ST"

# The raw transcript id keeps working — this adds a form, it does not swap one.
plant_agent "$I_SUB_B" "aforeigner-22222222222" "foreigner2"
observe "$SID_A" "$I_TR_B" "$I_REPO" "aforeigner-22222222222"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR_B" "$I_REPO" "aforeigner-22222222222")"
expect_status "the transcript-form id still resolves: PERMITTED" 0 "$GUARD_ST"

# A `name@session-` form whose session is NOT the one the agent is filed under is
# a guess that happens to be shaped like an id. It stays a name.
plant_agent "$I_SUB_B" "aforeigner-33333333333" "foreigner3"
observe "$SID_A" "$I_TR_B" "$I_REPO" "aforeigner-33333333333"
run_guard "$(mk_stop_payload "$SID_A" "$I_TR_B" "$I_REPO" "foreigner3@session-deadbeef")"
expect_status "a name@session naming the WRONG session is not an identity: REFUSED" 2 "$GUARD_ST"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "stop-guard.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
