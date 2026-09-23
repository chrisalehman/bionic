#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE (epic-15 wave-01R).
#
# PreToolUse|Agent. Serves AC-2, and the start-side share of AC-9/AC-10.
#
# Governing design: design/orchestrator-subagent-coordination.md §4 "The start
# gate", §3.4 Starting, §7 (fail-direction table).
#
# HERMETIC. Every payload is crafted and piped straight into the script under
# test; nothing here dispatches a real Agent tool call, touches the live
# installed hooks, or depends on a live wave. Repos are throwaway git inits
# under a mktemp'd sandbox; attestations are written directly as fixtures
# (never by invoking the real preflight-probe.sh), except in the S9
# runnability check, which installs a COPY of the real producer into a
# sandboxed HOME specifically to prove its fix command executes.
#
# Usage: bash tests/dispatch-preflight.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"

GATE="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"
PROBE_SRC="${BIONIC_HOOKS_DIR}/preflight-probe.sh"
# The rendered dispatch.md the gate itself reads at refusal time (T2, D3/D11) — the same
# file `dp_scaffold_marked` in hooks/dispatch-preflight.sh resolves via `$HOOK_DIR/..`.
DISPATCH_FILE="${BIONIC_SKILLS_DIR}/canonical-sdlc/dispatch.md"

# scaffold_block <file> -> the fenced scaffold lines, one per line. Defined at the TOP of
# this file, not beside the section that first needed it, because the several-fault wire's
# marked scaffold (T2, D3/D11) is read out of the shipped file by sections throughout —
# every one of them needs the same extractor §scaffold-verbatim drives further down.
scaffold_block() {
  /usr/bin/awk '
    /^### Scaffold/            { inb = 1; next }
    inb && /^```/              { fence++; if (fence == 2) exit; next }
    inb && fence == 1          { print }
  ' "$1"
}

# scaffold_raw_line <file> <label> -> that label's own line, verbatim, out of the shipped
# scaffold — what a marked line looks like before its ` <ADD>` suffix, if any.
scaffold_raw_line() {
  scaffold_block "$1" | /usr/bin/grep -m1 -E "^${2}:"
}

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dispatch-preflight-test.XXXXXX")" && pwd)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS; do kill -9 "$p" 2>/dev/null; done
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

# HELPER-PRESENCE GUARD (spec AC-25). This file runs under `set -uo pipefail` — NO
# `-e` — so a call to an assertion helper that was never defined here is a silent
# "command not found" on stderr: the row asserts nothing and the suite's own
# pass/total never notices (r24e was exactly this defect: `expect_eq` was called at
# :2835 with no definition anywhere in this file, caught by research-code-map §6.2).
# `expect_eq` itself and `require_helpers` now come from tests/lib/assert.sh (S11) —
# every helper this file calls is checked to exist as a function before the first
# test runs, so a future undefined call fails the whole suite loudly instead of
# vanishing.
require_helpers ok no expect_status expect_contains expect_absent expect_empty expect_eq

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design / rule
# fixtures-can-pin-away-the-test).
#
# Source: .bionic/docs/record/epic-15-kill-interception-experiment.md, CLI
# 2.1.220 verbatim captures.
#
#   * PreToolUse payload ENVELOPE — FAITHFUL to §2.2, field for field:
#     session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
#     hook_event_name, tool_name, tool_input, tool_use_id. §2.2 is captured
#     for tool_name:"TaskStop", but §2.1/§2.12 establish this is the SAME
#     builder for every PreToolUse invocation (only tool_name/tool_input
#     differ) — the matcher "Task" matching tool_name "Agent" (§2.12,
#     confirmed live in §2.1) independently corroborates that "Agent" is the
#     real tool_name value for a subagent dispatch.
#   * tool_name:"Agent" value and tool_input SHAPE — FAITHFUL as of task 4/3
#     to .bionic/docs/record/w3-slice1-posttooluse-probe.md capture E (an
#     Agent-tool payload captured live at CLI 2.1.222): tool_input carries
#     description, prompt, subagent_type, run_in_background, and — when the
#     dispatch names one — name. The earlier note here ("SHAPE-ONLY, no
#     verbatim Agent capture exists") described the pre-probe state and is
#     superseded. tool_input became load-bearing in task 4/3: the roster row
#     is lifted from it.
#   * tool_input.model — SHAPE-EXTRAPOLATED and declared: the Agent tool
#     accepts a `model` override, but no captured payload carries one (every
#     probe dispatch inherited). It is fixtured here because the roster
#     records it WHEN PRESENT; its absence is deliberately not an absence
#     finding, and S10c drives the no-model path.
#   * dispatch brief text (BRIEF_FULL / the compact variant) — SYNTHESIZED,
#     but its LABEL GRAMMAR is the shipped one: skills/canonical-sdlc/SKILL.md
#     §Dispatch's seven-field sentence (span-pinned by
#     tests/dispatch-spans.test.sh §5d — that suite was deleted in an earlier
#     purge, commit b959b5e, and nothing replaced the span pin) and the
#     exemplar brief recorded verbatim at .bionic/docs/record/w2-ac3-run.md:25-40.
#   * attestation record — FAITHFUL to hooks/preflight-probe.sh's own
#     schema/comment block: `# comment` + `key=value` lines, read BY KEY
#     (checklist A6), `session_id=` the field this gate keys on (Task 4/1
#     resolution: spelled to match the payload field name).
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, message
#     text. None is a platform surface.

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="1f4a7c02-3bd9-4e15-8a66-90c1de77b204"

# A realistic dispatch brief carrying all seven labeled contract fields in the
# shipped grammar — plus, since S13 (spec AC-20), the eighth: the instrument the
# task declares. `Suites:` is the DECLARED spelling, which is what a sandbox
# repo with no `impact-command:` in its .bionic/config.yaml must use; the DERIVED
# spelling (`Files:` plus a configured command) gets its own fixtures in S27,
# where the config exists. A brief carrying neither refuses at dispatch, so
# leaving the line off here would have put every case in this file on the
# refusal path instead of the one it means to test.
# The DEFAULT for every payload below, because a brief that
# carries its contract fields is the ordinary case — the roster's absence
# warning must not fire on it (that is what keeps the §7 "positive pair: pass in
# silence" row true), and a fixture that omitted them would have made every
# pre-task-4/3 pass case silently exercise the absence path instead
# (.claude memory: fixtures-can-pin-away-the-test). The absence path gets its
# own bare-brief fixture in S10c, and both directions are asserted.
BRIEF_FULL='Canonical-sdlc Step 4, task 4/9 of epic-99 wave-01; build · audited · wave.
Your task: implement the widget behind the existing seam.
Scope constraint: touch only lib/widget.sh and its paired suite.
Expected artifact: .bionic/docs/record/w99-widget.txt
Exit condition: the artifact exists and the paired suite is green.
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-widget.progress
Suites: tests/widget.test.sh'

# ---------- live_agents transcript fixtures (spec AC-6/AC-7/AC-8; task S5) ----------
#
# Entry-shape helpers, copied from tests/live-agents.test.sh — the one file that owns
# the real transcript entry shapes (assistant tool_use / user tool_result / user
# plain-string prompt), per this task's brief ("build transcript fixtures by copying
# the fixture helpers' shapes from tests/live-agents.test.sh").

json_str() { printf '%s' "$1" | jq -Rs .; }

entry_prompt() {  # <ts> <text> -> a user PROMPT entry (.message.content a plain string)
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":%s}}\n' \
    "$1" "$(json_str "$2")"
}

entry_tool_use() {  # <ts> <tool-name> <tool_use_id>
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"%s","input":{}}]}}\n' \
    "$1" "$3" "$2"
}

entry_tool_result() {  # <ts> <tool_use_id> <body>
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":%s}]}}\n' \
    "$1" "$2" "$(json_str "$3")"
}

# THE ANSWER BODY IS BUILT BY tests/lib/live-answer.sh (S17, spec AC-27/AC-28): the self
# line, the block header and every teammate row come out of the committed corpus with only
# this suite's names and statuses substituted in place. With NO names it is the self line
# alone — recognisable, carrying no teammates block at all, which is AC-6's "zero lines"
# case. This suite's private builder was one of the two that truncated the recognition
# anchor to its own spelling; the corpus's is now the only one in the tree.
#
# A bare name is the corpus's own `running`. `name:idle` writes the OTHER status the real
# harness emits: a teammate that finished its turn and was never TaskStop'd stays listed,
# because it stays addressable, and S22c is where that costs a writer slot or does not.
LIVE_ANSWER_TYPE="bionic:implementor"
la_body() {  # <name[:status]>... -> one real-shaped ListAgents answer body
  live_answer_body "$@"
}

# mk_transcript <path> <fresh|stale|none> [name] ... — writes a jsonl transcript at
# <path>. fresh/stale both carry one ListAgents answer naming the given teammates (zero
# or more); stale adds a LATER prompt so the answer no longer postdates the last one;
# none carries no ListAgents call at all. Fixed 2026-09-05 timestamps throughout, same
# idiom the rest of this file's fixtures use — freshness is a comparison between two
# entries in the file, never against wall-clock "now" (only `age=` is, and no assertion
# below pins its value).
_S5_TID=0
mk_transcript() {
  local path="$1" state="$2" tid body
  shift 2
  if [ "$state" = "none" ]; then
    entry_prompt "2026-09-05T00:50:00.000Z" "who is running" > "$path"
    return 0
  fi
  _S5_TID=$((_S5_TID + 1))
  tid="toolu_s5_${_S5_TID}"
  body="$(la_body "$@")"
  {
    entry_prompt      "2026-09-05T00:50:00.000Z" "who is running"
    entry_tool_use    "2026-09-05T00:52:22.000Z" "ListAgents" "$tid"
    entry_tool_result "2026-09-05T00:52:23.349Z" "$tid" "$body"
    [ "$state" = "stale" ] && entry_prompt "2026-09-05T00:55:00.000Z" "anything else?"
  } > "$path"
}

# THE DEFAULT for every dispatch payload below (mk_agent_payload's 6th argument): a
# FRESH answer naming every roster-row name this file's pre-existing S22/S25 fixtures
# use (W-ONE..W-FOUR), so a row that is not otherwise made absent still reads as the
# live agent it always represented — the one adaptation existing budget fixtures need
# now that AC-7 retires the `landing-swept` marker as the closing signal. Tests that
# need a name ABSENT, or a STALE/NONE answer, build and pass their own transcript.
S5_LIVE_TRANSCRIPT="$SANDBOX/.s5-live-default.jsonl"
mk_transcript "$S5_LIVE_TRANSCRIPT" fresh W-ONE W-TWO W-THREE W-FOUR

# mk_agent_payload <sid> <cwd> [prompt] [name] [model] [transcript]
#
# prompt/name/model default to the contract-complete brief; pass "-" for name or
# model to omit the field from tool_input entirely (the absence cases). transcript
# defaults to $S5_LIVE_TRANSCRIPT (fresh, names every W-* fixture row live).
mk_agent_payload() {
  local prompt="${3-$BRIEF_FULL}" name="${4-w99-impl}" model="${5-claude-sonnet-5}" \
        transcript="${6-$S5_LIVE_TRANSCRIPT}" stype="${7-implementor}"
  jq -n --arg s "$1" --arg c "$2" --arg p "$prompt" --arg n "$name" --arg m "$model" \
        --arg t "$transcript" --arg y "$stype" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:({description:"a test dispatch", subagent_type:$y,
                   prompt:$p, run_in_background:true}
                  + (if $n == "-" then {} else {name:$n} end)
                  + (if $m == "-" then {} else {model:$m} end)),
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

mk_bash_payload() {  # <sid> <cwd>  — an irrelevant tool, for the A7 hoist tests
  jq -n --arg s "$1" --arg c "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:"echo hi"}, tool_use_id:"toolu_0irrelevant"}'
}

GATE_OUT=""; GATE_ERR=""; GATE_VERR=""; GATE_ST=0
# THE DENY CHANNEL (wave-12 T17; every brief/state refusal since wave-19 T4). A refusal
# does not exit 2: it prints a PreToolUse deny verdict on STDOUT and exits 0, because
# `permissionDecisionReason` is the one field the E1 measurement proved reaches the MODEL in full (refuse.sh's channel
# table, `model_only=yes`). A driver that read the exit status alone would score that an
# ALLOW. `$GATE_VERDICT` is what a refusal arm asks for now — `deny`, `exit2` or `allow` —
# and `$GATE_REASON` is the model's own wire, parsed out of the JSON rather than grepped.
GATE_DENY=""; GATE_REASON=""; GATE_VERDICT="allow"
# Set to a directory to drive the gate with a sandboxed CLAUDE_CONFIG_DIR — the
# roster prune's liveness lookup reads <config>/projects/*/<session>.jsonl, and
# the operator's REAL config dir would decide which fixtures survive otherwise.
GATE_CONFIG_DIR=""
# Extra `KEY=VALUE` assignments for the gate's own environment, applied unquoted so a
# space-free list can carry several (none of the values below contain spaces). Added for
# the combined preflight (S16): the gate now runs the real preflight-probe.sh inline, and
# the probe reads a credential and a config dir out of the environment — which must be the
# SANDBOX's, never the operator's.
GATE_ENV=""
# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does. Since
# bionic 1.4.0 the wall takes its session id from lib/session.sh, where the ENV value
# is primary and the payload is a witness (design §1, R-1) — so a driver that shipped
# a fixture id in the payload while the runner's own CLAUDE_CODE_SESSION_ID sat in the
# environment would be driving a DIVERGENCE, not a session. The probe that settled
# this measured the two agreeing on a plain /clear (A-probe-2), and every fixture here
# is a session, so the driver mirrors the payload into the environment. A payload with
# no session key exports an empty one, which is what makes the no-session-key arms
# still reach the fail direction they pin.
# THE COLUMN COUNTER, for the AC-E1.3 sweep in the driver below: the em dash is three
# bytes and one column, so a byte count would pass a line that wraps.
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"
GATE_TIME=0
# dp_hires_cs_since <epoch-float> -> whole hundredths of a second elapsed since it.
#
# SUB-SECOND, via python3, for the same reason tests/session-start.test.sh §16 reaches for
# it: a whole-second `date +%s` difference is off by up to a full second either way
# depending on where the two reads straddle a tick. Two arms in this file claim the gate
# "stopped waiting at the bound", and what they have to tell apart is a wait that ended on
# the bound from one that ran 15% past it — at the 20s bound of the time, 20s from 23s, of
# which a whole-second clock can lose one second at each end. That is how a tick-counted
# wait ran 15% long underneath these two arms for a whole wave without either of them
# noticing (wave-14 T34). The margin shrinks with the bound, which is why the slack below
# is stated against `$S29_BOUND` rather than left at a fixed number of seconds.
#
# HUNDREDTHS, AS AN INTEGER, so the comparison stays in bash arithmetic and no arm has to
# fork a second interpreter to decide. A host with no python3 answers 999999, which fails
# both arms loudly rather than passing them blind.
dp_hires_cs_since() {
  python3 -c 'import sys,time; print(int((time.time()-float(sys.argv[1]))*100))' "$1" 2>/dev/null \
    || echo 999999
}

run_gate() {  # <payload-json>
  local _sid _t0; _sid=$(printf '%s' "$1" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  _t0=$(date +%s)
  # OPT-IN, AND ONLY OVER THE FIRST DRIVE. Set `GATE_HIRES=1` before a call to have
  # `$GATE_TIME_CS` measured to the hundredth; every other caller pays nothing, which
  # matters on a driver this file runs a few hundred times. The two python3 forks land
  # outside the timed span on the way in and immediately after `$?` on the way out.
  GATE_TIME_CS=""
  [ -z "${GATE_HIRES:-}" ] || _gate_hires_t0=$(python3 -c 'import time; print(time.time())' 2>/dev/null)
  GATE_ENV="$GATE_ENV CLAUDE_CODE_SESSION_ID=$_sid"
  if [ -n "$GATE_CONFIG_DIR" ]; then
    # shellcheck disable=SC2086
    GATE_OUT=$(printf '%s' "$1" | env $GATE_ENV CLAUDE_CONFIG_DIR="$GATE_CONFIG_DIR" bash "$GATE" 2>"$SANDBOX/.err")
  else
    # shellcheck disable=SC2086
    GATE_OUT=$(printf '%s' "$1" | env $GATE_ENV bash "$GATE" 2>"$SANDBOX/.err")
  fi
  GATE_ST=$?
  [ -z "${GATE_HIRES:-}" ] || GATE_TIME_CS=$(dp_hires_cs_since "${_gate_hires_t0:-0}")
  GATE_TIME=$(( $(date +%s) - _t0 ))
  GATE_ERR=$(cat "$SANDBOX/.err")
  # THE VERDICT, read off both wires. `jq` rather than a grep for the reason: a reason the
  # escaper mangled must come back EMPTY here, not as text that happens to hold the right
  # words — the escaping is refuse.sh's own responsibility and needs a parser to check it.
  GATE_DENY=""; GATE_REASON=""
  case "$GATE_OUT" in
    *'"permissionDecision":"deny"'*)
      GATE_DENY=1
      GATE_REASON=$(printf '%s' "$GATE_OUT" \
        | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null) || GATE_REASON=""
      ;;
  esac
  if [ -n "$GATE_DENY" ]; then
    GATE_VERDICT="deny"
  else
    case "$GATE_ST" in
      0) GATE_VERDICT="allow" ;;
      2) GATE_VERDICT="exit2" ;;
      *) GATE_VERDICT="exit$GATE_ST" ;;
    esac
  fi
  # §no-listagents SWEEP (wave-12 T1; spec D1, AC-4.1). NOT a per-arm assertion: the
  # criterion is "no brief in ANY state", and an arm-by-arm check would only ever cover
  # the states somebody remembered to write. Every payload this suite drives passes
  # through here, allowed and refused alike, and the counter is read once in the
  # §no-listagents section at the end of the file.
  #
  # IT SITS ABOVE THE AC-E1.3 BLOCK ON PURPOSE. That block returns early for a refusal
  # carrying no `bionic: ` line — which was precisely the shape of the live-agents
  # freshness refusal this task retires. A sweep placed after it would have been blind to
  # the one refusal it exists to hunt, and would have read empty for the wrong reason.
  DP_NLA_SWEPT=$(( ${DP_NLA_SWEPT:-0} + 1 ))
  case "$GATE_ERR" in
    *"call ListAgents"*) DP_NLA_HITS="${DP_NLA_HITS:-}[$GATE_ERR] " ;;
  esac
  # AC-E1.3, SWEPT AT THE DRIVER. Every refusal this suite produces is checked for the
  # criterion's shape as it happens, so no site can be migrated without an eval and no
  # arm has to be written twice. The counters are read in the AC-E1.3 section at the end.
  # BOTH BLOCKING CHANNELS. A deny verdict exits 0, so a sweep gated on status 2 alone would
  # stop reading the user line of every refusal T17 moved — the criterion is about the LINE,
  # and the line is on stderr in both modes.
  if [ "$GATE_ST" = "2" ] || [ -n "$GATE_DENY" ]; then
    _dp_line=$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ' || true)
    if [ -z "$_dp_line" ]; then
      # THE ONE REFUSAL SITE THE RULED WORDING TABLE DOES NOT COVER. `live-agents:` at
      # dispatch-preflight.sh (the STALE/NONE roster answer) is a refusal the task-12
      # table has no row for, so task 13 left its text alone rather than inventing
      # wording for it. It is counted here by name so the gap is a fact on the record and
      # a SECOND uncovered site would show up as an unnamed one.
      DP_E1_UNCOVERED=$(( ${DP_E1_UNCOVERED:-0} + 1 ))
      case "$GATE_ERR" in
        *"live-agents: "*) : ;;
        *) DP_E1_UNNAMED="${DP_E1_UNNAMED:-}[$GATE_ERR] " ;;
      esac
      return 0
    fi
    DP_E1_SEEN=$(( ${DP_E1_SEEN:-0} + 1 ))
    printf '%s' "$_dp_line" | /usr/bin/grep -qE '^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$' \
      || DP_E1_BAD_SHAPE="${DP_E1_BAD_SHAPE:-}[$_dp_line] "
    [ "$(printf '%s\n' "$_dp_line" | wc -l | tr -d ' ')" = "1" ] \
      || DP_E1_BAD_LINES="${DP_E1_BAD_LINES:-}[$_dp_line] "
    [ "$(bionic_cols "$_dp_line")" -le 100 ] || DP_E1_BAD_COLS="${DP_E1_BAD_COLS:-}[$_dp_line] "
  fi
  # THE SAME CALL AGAIN, WITH THE KNOB (task 13, ruling D-1). This gate's refusal is
  # now ONE line — `bionic: dispatch refused — <fact> (<fix>)` — and everything this
  # suite reads out of the old frames (the probe output, the budget string, the plan
  # path, the pasteable Fix lines, the candidate list) is `detail`, which reaches a
  # reader only under BIONIC_WALL_VERBOSE=1. `$GATE_ERR` is the LINE; `$GATE_VERR` is
  # the line plus the detail.
  # ONLY WHEN THE FIRST DRIVE REFUSED. An allowed dispatch JOURNALS a roster row, so a
  # second drive of an accepted call would append a second row and every counting arm in
  # this suite would read two where the gate wrote one. Measured, not guessed: an
  # ungated second drive turned "exactly one row was appended" into two.
  # ON A DENY TOO (T17). The gate exits 0 there, and the reason a second drive is gated at
  # all is that an ALLOWED dispatch journals a roster row — a deny journals nothing, because
  # the findings are spent above the journal.
  GATE_VERR=""
  if [ "$GATE_ST" -ne 0 ] || [ -n "$GATE_DENY" ]; then
    if [ -n "$GATE_CONFIG_DIR" ]; then
      # shellcheck disable=SC2086
      GATE_VERR=$(printf '%s' "$1" | env $GATE_ENV BIONIC_WALL_VERBOSE=1 \
        CLAUDE_CONFIG_DIR="$GATE_CONFIG_DIR" bash "$GATE" 2>&1 >/dev/null)
    else
      # shellcheck disable=SC2086
      GATE_VERR=$(printf '%s' "$1" | env $GATE_ENV BIONIC_WALL_VERBOSE=1 bash "$GATE" 2>&1 >/dev/null)
    fi
  fi
  # §no-listagents SWEEP (wave-12 T1; spec D1, AC-4.1). NOT a per-arm assertion: the
  # criterion is "no brief in ANY state", and an arm-by-arm check would only ever cover
  # the states somebody remembered to write. Every payload this suite drives passes
  # through here — allowed and refused alike, line and detail — and the counter is read
  # once in the §no-listagents section at the end of the file.
  case "$GATE_VERR" in
    *"call ListAgents"*) DP_NLA_HITS="${DP_NLA_HITS:-}[detail: $GATE_VERR] " ;;
  esac
  GATE_ENV="${GATE_ENV% CLAUDE_CODE_SESSION_ID=*}"
  return 0
}

# ---------- the combined preflight's environment (epic-16 w2 S5) ----------
#
# As of R5 the gate RUNS hooks/preflight-probe.sh inline whenever this session has no
# attestation on disk, so most cases in this file now reach the real producer. Its
# blocking probes read a credential and its D-5 pruning reads a config directory, and
# both of those are machine-global by default: the operator's login keychain answers the
# credential probe no matter what a sandbox does, and the operator's own `~/.claude`
# decides which fixture rosters look "live". Substituting the ENVIRONMENT (not the
# script) is the same technique preflight-probe.test.sh uses, and it is on for the whole
# file so that no case accidentally depends on the machine it runs on.
#
# The transcript file makes THIS session look live to the probe's own scan; SESSION B
# gets one too, since several cases below turn on a live foreign session being left
# alone rather than pruned.
PROBE_ENV_HOME="$SANDBOX/probehome"
PROBE_ENV_PROJ="$PROBE_ENV_HOME/.claude/projects/-sandbox"
mkdir -p "$PROBE_ENV_PROJ"
: > "$PROBE_ENV_PROJ/$SID_A.jsonl"
: > "$PROBE_ENV_PROJ/$SID_B.jsonl"
probe_env_on() {
  GATE_CONFIG_DIR="$PROBE_ENV_HOME/.claude"
  GATE_ENV="ANTHROPIC_API_KEY=sk-fixture-marker HOME=$PROBE_ENV_HOME"
}
probe_env_on

# ---------- roster readers (task 4/3) ----------
#
# BY KEY, never by position — the same rule the attestation and the observation
# record already follow (checklist A6), so an added field is inert here.
roster_path()  { printf '%s/.bionic/tmp/roster-%s.state' "$1" "$2"; }
roster_rows()  { grep -v '^#' "$1" 2>/dev/null | grep -c . ; }
# NAMED FOR WHAT IT DOES, because `roster_row` is now the production WRITER's name and this
# suite sources it (tests/lib/roster-row.sh, S14). Two functions, one name, one of them
# shadowing the other from line 24 onwards is not a collision a test can survive quietly:
# every fixture built through the writer would have silently been fed to this reader.
roster_nth_row() { grep -v '^#' "$1" 2>/dev/null | sed -n "${2}p"; }   # <file> <n>
roster_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# make_repo <name> <active-wave:yes|no> -> echoes the repo path
make_repo() {
  local name="$1" wave="$2"
  local repo="$SANDBOX/$name/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  if [ "$wave" = "yes" ]; then
    # A live wave has a live Patrol: it is armed at engagement, before the first dispatch
    # (skills/canonical-sdlc/SKILL.md §Dispatch). Every wave-active fixture therefore
    # carries a fresh stamp for the session ids this suite dispatches with, and the S21
    # arms remove or backdate it to drive the arming wall. Without this the wall would be
    # under test in every case in the file rather than in its own section.
    mkdir -p "$repo/.bionic/tmp"
    local _psid
    for _psid in "${SID_A:-}" "${SID_B:-}" "${SID_DEAD:-}" "${SID_LIVE:-}"; do
      [ -n "$_psid" ] || continue
      printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_psid" > "$repo/.bionic/tmp/patrol-$_psid.state"
      chmod 600 "$repo/.bionic/tmp/patrol-$_psid.state"
      # A LIVE WAVE HAS AN ENGAGED SESSION (task-engaged-session). The gate asks
      # `engaged_session` before it asks anything else, so a fixture without this marker is
      # silent for a reason that has nothing to do with the wall under test — every
      # assertion in this file would pass over a hook that exits at its first line. The
      # marker is exactly what hooks/engage.sh writes when canonical-sdlc is invoked.
      : > "$repo/.bionic/tmp/engaged-$_psid.state"
    done
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
  printf '%s' "$repo"
}

# write_attestation <repo> <session_id> [extra kv lines...]
#
# task 4/2 (D-5): writes to the PER-SESSION filename, preflight-<sid>.state — the
# filename is now the primary key, matching hooks/preflight-probe.sh's own scheme.
write_attestation() {
  local repo="$1" sid="$2"; shift 2
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=1\n'
    printf 'kind=preflight-attestation\n'
    printf 'session_id=%s\n' "$sid"
    printf 'written_at=1785790000\n'
    printf 'repo=%s\n' "$repo"
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$repo/.bionic/tmp/preflight-$sid.state"
  chmod 600 "$repo/.bionic/tmp/preflight-$sid.state"
}

# write_legacy_attestation <repo> <session_id> — the OLD, pre-wave-03 single-slot
# filename. Used to prove the gate never consults it (task 4/2).
write_legacy_attestation() {
  local repo="$1" sid="$2"
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=1\n'
    printf 'kind=preflight-attestation\n'
    printf 'session_id=%s\n' "$sid"
    printf 'written_at=1785790000\n'
    printf 'repo=%s\n' "$repo"
  } > "$repo/.bionic/tmp/preflight.state"
  chmod 600 "$repo/.bionic/tmp/preflight.state"
}

section "S1 — relevance hoist (A7): irrelevant tool passes, silent"


REPO=$(make_repo r1 yes)
# no attestation exists at all — if tool_name gating were bypassed, an
# "Agent" payload here would be REFUSED. A "Bash" payload must still pass.
run_gate "$(mk_bash_payload "$SID_A" "$REPO")"
expect_status "irrelevant tool exits 0 even with no attestation in an active wave" "0" "$GATE_ST"
expect_empty "irrelevant tool produces no stdout" "$GATE_OUT"
expect_empty "irrelevant tool produces no stderr" "$GATE_ERR"

# static pin: the relevance check must appear in the source BEFORE the
# active-wave machinery (resolve_docs_root / the plan-directory find) — this
# is the textual half of A7's hoist proof; the behavioral half is above.
TOOL_LINE=$(grep -n '\[ "\$TOOL_NAME" = "Agent" \]' "$GATE" | head -1 | cut -d: -f1)
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f). The first thing this gate pays for is
# no longer its own `session_run` call: `bionic_context` resolves the root, the session id
# and the run verdict in one, and THAT is the line the relevance check must precede. What
# is pinned is unchanged — nothing touches disk before the cheap check.
#
# THE ANCHOR IS THE POINT. Both line numbers are asserted findable BEFORE they are
# compared, because a grep whose literal has left the file yields the empty string and
# `[ "$TOOL_LINE" -lt "" ]` is an error, not a comparison — an order pin over two empty
# values pins nothing, which is exactly the state this one was heading for.
WALK_LINE=$(grep -n '^bionic_context' "$GATE" | head -1 | cut -d: -f1)
expect_nonempty "the relevance check is findable in the gate's source" "$TOOL_LINE"
expect_nonempty "the context call is findable in the gate's source" "$WALK_LINE"
if [ -n "$TOOL_LINE" ] && [ -n "$WALK_LINE" ] && [ "$TOOL_LINE" -lt "$WALK_LINE" ]; then
  ok "relevance check (line $TOOL_LINE) precedes the context resolution (line $WALK_LINE)"
else
  no "relevance check precedes the context resolution" "tool=$TOOL_LINE walk=${WALK_LINE:-none}"
fi

section "S2 — ambiguity: repo unresolvable -> OPEN, silent"

run_gate "$(mk_agent_payload "$SID_A" "")"
expect_status "empty cwd exits 0" "0" "$GATE_ST"
expect_empty "empty cwd produces no stdout" "$GATE_OUT"
expect_empty "empty cwd produces no stderr" "$GATE_ERR"

# A NON-GIT CWD IS NOT THE QUESTION ANY MORE (bionic 1.4.0, spec AC-12, Decision A2).
# It used to be the whole precondition: `git rev-parse --show-toplevel` had to succeed
# or the wall exited silently, which made the wall's coverage a property of the SHELL's
# cwd rather than of the project. A dispatch from a scratch directory that nonetheless
# sat under a real `.bionic` root disarmed arming, containment and rostering at once.
#
# The question now is whether there is a PROJECT: `project_root` walks for the nearest
# real `.bionic` ancestor and `active_run` asks whether its run is open. The two rows
# below are the same non-git cwd on either side of that line, and nothing separates
# them but a `.bionic` directory above.
NONGIT="$SANDBOX/not-a-repo"; mkdir -p "$NONGIT"
run_gate "$(mk_agent_payload "$SID_A" "$NONGIT")"
expect_status "A2 non-git cwd with NO .bionic above it exits 0" "0" "$GATE_ST"
expect_empty "A2 …producing no stdout" "$GATE_OUT"
expect_empty "A2 …and no stderr" "$GATE_ERR"

# The other side: a non-git cwd INSIDE a project with an open run. The wall runs, and
# with no Patrol stamp for this session it refuses at the arming wall — the refusal
# that was unreachable from here before A2.
A2_ROOT=$(make_repo a2root yes)
rm -rf "$A2_ROOT/.git"
rm -f "$A2_ROOT/.bionic/tmp/patrol-$SID_A.state"   # unarmed: the refusal this row drives
A2_SCRATCH="$A2_ROOT/scratch/deep"; mkdir -p "$A2_SCRATCH"
write_attestation "$A2_ROOT" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$A2_SCRATCH")"
expect_eq "A2 non-git cwd WITH a .bionic root above it reaches the wall (exit 2)" "deny" "$GATE_VERDICT"
expect_contains "A2 …refusing at the arming wall, which is what the old precondition hid" \
  "Patrol" "$GATE_ERR"

section "S3 — no active wave -> inert, nothing to decide"

REPO_NOWAVE=$(make_repo r3a no)
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE")"
expect_status "no plan directory at all exits 0" "0" "$GATE_ST"
expect_empty "no plan directory produces no stdout" "$GATE_OUT"
expect_empty "no plan directory produces no stderr" "$GATE_ERR"

REPO_NOWAVE2=$(make_repo r3b yes)
# UNENGAGED, DELIBERATELY (task-engaged-session). make_repo plants the engagement marker
# with the Patrol stamp, and since this wave an ENGAGED session is walled whether or not a
# plan is on disk (AC-23, driven in S24 below). What this block claims is the older, and
# still true, half: a session that never invoked canonical-sdlc sees nothing at all. Removing
# the marker is what keeps the claim about the run predicate rather than about engagement.
rm -f "$REPO_NOWAVE2/.bionic/tmp/engaged-$SID_A.state"
# overwrite with a plan that has no ## SDLC State at all
cat > "$REPO_NOWAVE2/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
---
# A plan with no SDLC State section
PLAN
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE2")"
expect_status "plan with no SDLC State section exits 0" "0" "$GATE_ST"
expect_empty "no SDLC State produces no stdout" "$GATE_OUT"
expect_empty "no SDLC State produces no stderr" "$GATE_ERR"

# even with NO attestation present, no-active-wave still passes an Agent
# dispatch — proving the wave check, not the attestation check, gates entry.
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE")"
expect_status "Agent dispatch with no wave and no attestation still exits 0" "0" "$GATE_ST"

section "S4 — active wave + payload missing session_id -> OPEN, silent (§7 table)"

REPO=$(make_repo r4 yes)
run_gate "$(mk_agent_payload "" "$REPO")"
expect_status "missing session_id in an active wave exits 0" "0" "$GATE_ST"
expect_empty "missing session_id produces no stdout" "$GATE_OUT"
expect_empty "missing session_id produces no stderr" "$GATE_ERR"

section "S5 — active wave + no attestation on disk -> AUTO-PROBE, then pass (AC-2 / AC-4)"
#
# THE DIRECTION REVERSED IN EPIC-16 WAVE-02 (R5). Through wave-01 this refused and named
# a command for the operator to run by hand — and the Synthesis field report measured
# what that cost: five serialized minutes between deciding to dispatch and the agent
# existing, paid again after every /clear, which re-fires the this-session demand
# mid-wave although nothing about the machine has changed.
#
# A missing attestation is not evidence of a broken environment; it is the absence of
# evidence, and re-reading the fact costs a second and cannot go stale. So the gate takes
# the reading itself. The refusal did not disappear — it MOVED, onto the probe's own
# verdict (S16 drives that half, and the arc end to end).

REPO=$(make_repo r5 yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no attestation in an active wave no longer refuses" "0" "$GATE_ST"
expect_empty "the auto-probe path produces no stdout" "$GATE_OUT"
expect_absent "…and no refusal is printed" "BLOCKED" "$GATE_ERR"
expect_status "…the attestation it was missing now exists" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"

# The fix command survives where it still means something — the probe-failure refusal —
# and checklist A1's requirement on it is unchanged: an install-path spelling, runnable
# from any cwd, never this gate itself. Driven here on the one path that still refuses.
REPO=$(make_repo r5b yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_contains "a probe-failure refusal still names the install-path fix command" \
  "bash $PROBE_SRC" "$GATE_VERR"
expect_absent "refusal does not name a repo-relative fix command (checklist A1)" "hooks/preflight-probe.sh\"" "$GATE_ERR"
case "$GATE_ERR" in
  *"hooks/dispatch-preflight.sh"*) no "refusal never names itself as the fix" ;;
  *) ok "refusal never names itself as the fix" ;;
esac

section "S6 — active wave + only a FOREIGN session's attestation exists -> AUTO-PROBE (AC-2)"
#
# task 4/2 (D-5): the foreign attestation is written at ITS OWN per-session filename
# (preflight-<SID_B>.state) — there is no file at all for SID_A, which is exactly what
# "foreign, however fresh, is not an attestation for this session" means once filenames
# are the primary key. That reading is UNCHANGED by R5; what changed is what follows from
# it. A foreign record is still never read as mine — the gate takes my own reading
# instead of refusing, and B's record is left exactly where it was.

REPO=$(make_repo r6 yes)
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "foreign-only attestation auto-probes rather than refusing" "0" "$GATE_ST"
expect_status "…and this session gets a record of its OWN, at its own filename" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
expect_status "…while the LIVE foreign session's record is untouched (D-5)" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_B.state" ] && echo 0 || echo 1)"

section "S6b — active wave + BOTH sessions hold valid attestations concurrently (AC-2)"
#
# The D-5 core case: two sessions on one repo, each with its own per-session file. Both
# dispatches pass — session B's attestation existing is neither necessary nor sufficient
# for session A's gate, and vice versa.

REPO=$(make_repo r6b yes)
write_attestation "$REPO" "$SID_A"
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "session A's dispatch passes with both attestations present" "0" "$GATE_ST"
expect_empty "session A's pass produces no stdout" "$GATE_OUT"
run_gate "$(mk_agent_payload "$SID_B" "$REPO")"
expect_status "session B's dispatch ALSO passes with both attestations present" "0" "$GATE_ST"
expect_empty "session B's pass produces no stdout" "$GATE_OUT"

section "S6c — the legacy single-slot file is NEVER consulted (task 4/2)"
#
# A legacy preflight.state carrying this session's own, perfectly valid-looking
# session_id= must still refuse: only the per-session filename is ever read.

REPO=$(make_repo r6c yes)
write_legacy_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a legacy single-slot attestation is not consulted; the probe runs instead" "0" "$GATE_ST"
expect_status "…and the record that admits the dispatch is at the PER-SESSION filename" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
# The probe prunes the legacy slot on every run — the strongest form of "never consulted"
# is that the file is not there to consult by the time the next dispatch asks.
expect_status "…the legacy slot is gone, not merely ignored" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight.state" ] && echo 1 || echo 0)"

section "S7 — active wave + attestation IS this session -> pass, verdict silent (AC-2)"
#
# "Silent" here is about the VERDICT (no BLOCKED refusal, nothing on stdout ever) — not
# absolute stderr silence, which S10c's absence warning already established is not the
# invariant. Since the unarmed-sweeper nag was deleted with the watcher (epic-16 w2 S1) a
# contract-complete fixture like this one has nothing to say on stderr either, and that is
# asserted directly below rather than left implied.

REPO=$(make_repo r7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "matching attestation exits 0" "0" "$GATE_ST"
expect_empty "matching attestation produces no stdout (never print on the allow path)" "$GATE_OUT"
expect_absent "matching attestation prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_absent "…and says nothing about a sweeper being armed (the nag is deleted)" \
  "sweeper" "$GATE_ERR"

# forward-compatibility (A6): unknown extra fields, reordered, must still
# read the session_id BY KEY, not by position — mirrors
# preflight-probe.test.sh's own reorder case. Written at the PER-SESSION path.
REPO=$(make_repo r7b yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'unknown_future_field=x\nsession_id=%s\nversion=1\nrepo=%s\n' "$SID_A" "$REPO" \
  > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "reordered/extended attestation with a matching key still passes" "0" "$GATE_ST"
expect_empty "reordered/extended pass produces no stdout" "$GATE_OUT"

section "S8 — hostile/malformed attestation shapes -> REFUSE, never followed (AC-8-adjacent)"

# attestation path occupied by a directory
REPO=$(make_repo r8a yes)
mkdir -p "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation path is a directory -> refuse" "2" "$GATE_ST"

# attestation path is a symlink to a file that DOES contain a matching
# session_id= line — proves the gate never follows it, even when doing so
# would happen to "pass": the wall must not be foolable by planted content.
REPO=$(make_repo r8b yes)
mkdir -p "$REPO/.bionic/tmp"
DECOY="$SANDBOX/decoy-attestation"
printf 'session_id=%s\nversion=1\n' "$SID_A" > "$DECOY"
ln -s "$DECOY" "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation path is a symlink -> refuse, not followed" "2" "$GATE_ST"

# S1 (Step-6 security review, task 4/7): the DIRECTORY levels are guarded too.
# Checking only the file leaves the same class open one level up — a repo
# controls its own `.bionic/` contents, so pointing `.bionic/tmp` (or `.bionic`)
# at a directory holding a valid same-session attestation opens the wall with
# content the repo arranges. §8's load-bearing property is that a hostile repo
# can CLOSE or AIM these walls but never OPEN them, and the sibling gate already
# refuses at both levels (hooks/stop-guard.sh's state_paths(); checklist A3
# names this variant, discharged for the WRITE path only).
for _lvl in .bionic/tmp .bionic; do
  _tag=$(printf '%s' "$_lvl" | tr -d './')
  REPO=$(make_repo "r8d-$_tag" yes)
  ELSEWHERE="$SANDBOX/elsewhere-$_tag/.bionic/tmp"
  mkdir -p "$ELSEWHERE"
  printf 'session_id=%s\nversion=1\nkind=preflight-attestation\n' "$SID_A" \
    > "$ELSEWHERE/preflight-$SID_A.state"
  # THE HOSTILE DIRECTORY CARRIES THE ENGAGEMENT MARKER AS WELL (task-engaged-session).
  # The gate asks `engaged_session` first, and its path runs through the very directory
  # this case redirects — so without a marker on the far side the gate would exit at the
  # switch and the S1 claim (the attestation is not read THROUGH a directory symlink)
  # would be proven by an exit that never reached the attestation at all. Planting it is
  # also the honest shape: engagement is the one artifact whose PRESENCE opens a wall, so
  # a repo that can arrange it can only ever ARM these walls against itself.
  : > "$ELSEWHERE/engaged-$SID_A.state"
  if [ "$_lvl" = ".bionic/tmp" ]; then
    mkdir -p "$REPO/.bionic"
    # make_repo plants a real .bionic/tmp (the Patrol stamp lives there); it has to GO,
    # or `ln -s` lands the link INSIDE it and the hostile shape under test never exists.
    rm -rf "$REPO/.bionic/tmp"
    ln -s "$ELSEWHERE" "$REPO/.bionic/tmp"
  else
    # The whole `.bionic` redirected: the active plan has to travel with it, or
    # the case is vacuous (no wave, nothing to decide).
    cp -R "$REPO/.bionic/docs" "$SANDBOX/elsewhere-$_tag/.bionic/docs"
    rm -rf "$REPO/.bionic"
    ln -s "$SANDBOX/elsewhere-$_tag/.bionic" "$REPO/.bionic"
  fi
  run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
  expect_status "a planted DIRECTORY symlink at ${_lvl} -> refuse, not read through (S1)" \
    "2" "$GATE_ST"
done

# attestation file exists but is empty / has no session_id= line at all. Unlike the
# hostile shapes above, this is not an attack — it is an unreadable fact, which R5 treats
# as no fact at all: the probe re-takes it and overwrites the unreadable record. The
# security property is untouched, because the two are distinguished by WHO fixes them —
# a symlink is refused by the probe, a bad record is replaced by it.
REPO=$(make_repo r8c yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'version=1\nkind=preflight-attestation\n' > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation with no session_id= line -> re-taken, not refused" "0" "$GATE_ST"
expect_status "…and the unreadable record is replaced by a keyed one" "0" \
  "$(grep -qx "session_id=$SID_A" "$REPO/.bionic/tmp/preflight-$SID_A.state" && echo 0 || echo 1)"

section "S9 — the fix command is runnable from a NON-REPO cwd (checklist A1)"

# The fix line now lives on the surviving refusal — a probe that FAILED — rather than on
# a missing attestation, which the gate takes for itself (S5). What A1 asks of it is
# unchanged: whatever command the refusal hands an operator has to run from wherever they
# are standing, which a repo-relative spelling does not.
REPO=$(make_repo r9 yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
# THE FIX LINE AS THE GATE ACTUALLY PRINTED IT, never a grep for the spelling we
# hope to find. The old form was `grep -oF "bash $PROBE_SRC"`, which could only ever
# yield the exact absolute command or nothing at all — so the one defect A1 exists to
# catch, a repo-relative spelling, made FIXLINE EMPTY, `bash -c ""` exited 0 with no
# stderr, and all three assertions below passed over a run that never happened. The
# extractor pinned away the property under test (.claude memory:
# fixtures-can-pin-away-the-test); proven vacuous by mutation in epic-18 W3 4/2, where
# rewriting PREFLIGHT_CMD to `bash preflight-probe.sh` flipped nothing.
# Lifting the gate's own text lets a relative spelling reach the execution below.
# THE FIX TEXT IS IN THE DETAIL NOW (task 13, D-1): the user line carries the repair in
# six words and the runnable command travels with `detail`, so the extractor reads the
# verbose stream. That the extracted line still EXECUTES is what the arms below prove.
FIXLINE=$(printf '%s\n' "$GATE_VERR" | sed -n 's/.*re-run by hand: \(.*\))\..*/\1/p' | head -1)
# The extractor's own non-emptiness, positive, on the same fixture — without it the
# three assertions below are again a test of nothing (authoring rule: prove the
# extractor before asserting an absence through it).
expect_contains "a fix line was captured to execute" "preflight-probe.sh" "$FIXLINE"

# A throwaway HOME, so executing the captured fix line cannot touch the real one. Since
# epic-17 W1 S3 the fix line resolves the probe beside the GATE rather than under $HOME, so
# the installed copy below is no longer what makes the line runnable — it stays as the
# hostile case: a stale ~/.claude/hooks/ copy that the fix line must NOT be reaching for.
RUNHOME="$SANDBOX/run9/home"
mkdir -p "$RUNHOME/.claude/hooks"
cp "$PROBE_SRC" "$RUNHOME/.claude/hooks/preflight-probe.sh"
chmod +x "$RUNHOME/.claude/hooks/preflight-probe.sh"

NONREPO_CWD="$SANDBOX/run9/nowhere"
mkdir -p "$NONREPO_CWD"

RUN9_OUT="$SANDBOX/run9.out"; RUN9_ERR="$SANDBOX/run9.err"
( cd "$NONREPO_CWD" && env -i \
    HOME="$RUNHOME" PATH="$PATH" \
    CLAUDE_CONFIG_DIR="$RUNHOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$SID_A" \
    ANTHROPIC_API_KEY="sk-fixture-marker" \
    bash -c "$FIXLINE" ) >"$RUN9_OUT" 2>"$RUN9_ERR"
RUN9_ST=$?

# 127 = command not found, 126 = found but not executable — exactly the
# failure shapes a repo-relative fix command produces from a foreign cwd.
if [ "$RUN9_ST" -eq 127 ] || [ "$RUN9_ST" -eq 126 ]; then
  no "fix command runs from a non-repo cwd" "exit $RUN9_ST (not found/not executable): $(cat "$RUN9_ERR")"
else
  ok "fix command runs from a non-repo cwd"
fi
# `$RUN9_ERR` is the PATH of the capture file; these two used to pass it as the
# HAYSTACK, so they asked whether the string "/tmp/.../run9.err" contains "No such
# file or directory" — which it never can, on any run, however broken. Both were
# vacuous from birth; proven so in epic-18 W3 4/2, where pointing the fix command at
# a file that does not exist (exit 127, that exact message on stderr) flipped neither.
# The arm above already reads the CONTENTS, via `$(cat "$RUN9_ERR")`; these now do too.
RUN9_ERR_TEXT="$(cat "$RUN9_ERR")"
expect_absent "fix-command run produces no 'No such file or directory'" "No such file or directory" "$RUN9_ERR_TEXT"
expect_absent "fix-command run produces no 'command not found'" "command not found" "$RUN9_ERR_TEXT"

section "S10 — the roster row is written on the pass path (AC-1, launch half)"
#
# Governing design: spec §Design "Roster" + §Component boundaries. The row is
# appended at launch with status `intended`; the full agent id and `confirmed`
# are task 4/4's, not this one's.

REPO=$(make_repo r10 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
R10=$(roster_path "$REPO" "$SID_A")

expect_status "a contract-complete dispatch still passes (verdict unchanged)" "0" "$GATE_ST"
expect_empty "a contract-complete dispatch still prints nothing on stdout" "$GATE_OUT"
# The invariant this row protects is "no BLOCKED refusal", asserted directly. Since the
# unarmed-sweeper nag was deleted with the watcher there is nothing else on this stream for
# a contract-complete dispatch either.
expect_absent "a contract-complete dispatch prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_absent "…and nothing about an unarmed sweeper" "sweeper" "$GATE_ERR"
expect_status "the roster file exists at the per-session path" "0" "$([ -f "$R10" ] && echo 0 || echo 1)"
expect_contains "the roster carries a versioned schema header" "roster-state/v1" "$(head -1 "$R10" 2>/dev/null)"
expect_status "exactly one row was appended" "1" "$(roster_rows "$R10")"

ROW=$(roster_nth_row "$R10" 1)
expect_contains "the row's leading field is the schema version" "roster-state/v1" "$(printf '%s' "$ROW" | cut -d'|' -f1)"
expect_status "row status is 'intended'" "intended" "$(roster_field "$ROW" status)"
expect_status "row carries this session's id" "$SID_A" "$(roster_field "$ROW" session)"
expect_status "row carries the agent name from tool_input" "w99-impl" "$(roster_field "$ROW" name)"
expect_status "row carries subagent_type from tool_input" "implementor" "$(roster_field "$ROW" subagent_type)"
expect_status "row carries the model from tool_input" "claude-sonnet-5" "$(roster_field "$ROW" model)"
expect_status "row carries the tool_use_id (the recorder's correlation key)" \
  "toolu_018jyjgop7KMxP6yKtoAWWtB" "$(roster_field "$ROW" tool_use_id)"
expect_status "row's agent_id is empty at launch (task 4/4 fills it)" "" "$(roster_field "$ROW" agent_id)"

LAUNCHED=$(roster_field "$ROW" launched_at)
if printf '%s' "$LAUNCHED" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "row carries a UTC ISO launch timestamp"
else
  no "row carries a UTC ISO launch timestamp" "got '$LAUNCHED'"
fi

# contract state, lifted from the brief's labeled fields
expect_status "row lifts the deliverable path from 'Expected artifact:'" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_contains "row lifts the expected duration" "25" "$(roster_field "$ROW" duration)"
expect_status "row lifts the progress path from 'Progress artifact:'" \
  ".bionic/tmp/w99-widget.progress" "$(roster_field "$ROW" progress)"
expect_status "no contract field is recorded absent for a complete brief" "" "$(roster_field "$ROW" absent)"

section "S10b — the compact one-line label grammar is lifted too (AC-1)"
#
# Real briefs put two labels on one line ("Expected duration: ~35 minutes.
# Progress: append to <path> per stage") — see the exemplar at
# .bionic/docs/record/w2-ac3-run.md. A line-scoped extractor would swallow the
# second label into the first's value; the span must end at the NEXT LABEL, not
# at the newline.

BRIEF_COMPACT='Task 4/4 of epic-99 wave-01; build · audited · wave.
Deliverables: (1) one commit `feat(x): thing (epic-99 w1 task 4/4)`; (2) record/w99-two.txt, verbatim.
Expected duration: ~35 minutes. Progress: append to .bionic/tmp/w99-two.progress per stage.
Exit: both deliverables exist.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_COMPACT" "w99-two")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "compact grammar: the dispatch passes" "0" "$GATE_ST"
expect_contains "compact grammar: deliverable lifted from 'Deliverables:'" \
  "record/w99-two.txt" "$(roster_field "$ROW" deliverable)"
expect_contains "compact grammar: duration lifted, not swallowed by the next label" \
  "35" "$(roster_field "$ROW" duration)"
expect_absent "compact grammar: the duration value stops at the next label" \
  "Progress" "$(roster_field "$ROW" duration)"
expect_status "compact grammar: progress path lifted from a mid-line 'Progress:'" \
  ".bionic/tmp/w99-two.progress" "$(roster_field "$ROW" progress)"
# "4/4" inside the commit subject is slash-bearing but not a path; a lifted
# deliverable list containing it would mean the extractor is matching fractions.

section "S10c — a missing NON-deliverable field is RECORDED + WARNED, never blocked (AC-1)"
#
# Spec §Component boundaries: "Extraction failure warns and records absence —
# starts fail open (TDD §7)." The verdict is the load-bearing assertion here: a
# brief missing everything BUT its deliverable is a warning, not a refusal.
#
# The deliverable is the one field that escaped this rule (S10W): a dispatch
# that names none is refused outright. So this fixture carries a deliverable and
# nothing else — which is also what keeps the two directions honest, since a
# brief carrying no fields at all now never reaches the roster to be warned about.

REPO=$(make_repo r10c yes)
write_attestation "$REPO" "$SID_A"
# The label sits on its OWN line (R8: final-audit A-1 pinned the deliverable-kind
# labels to line start) — a trailing mid-line occurrence would no longer register
# as a hit at all, and this fixture is meant to test the near-fieldless-brief
# warning path, not the line-start rule.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" \
  "Go and do the thing, please.
Expected artifact: .bionic/docs/record/w99-min.txt
Suites: tests/widget.test.sh" "-" "-")"
R10C=$(roster_path "$REPO" "$SID_A")
ROW=$(roster_nth_row "$R10C" 1)

expect_status "a brief with only its deliverable still PASSES the gate" "0" "$GATE_ST"
expect_empty "the absence warning never goes to stdout" "$GATE_OUT"
expect_contains "the absence is warned on stderr" "WARN" "$GATE_ERR"
expect_contains "the warning names the duration field" "duration" "$GATE_ERR"
expect_contains "the warning names the progress field" "progress" "$GATE_ERR"
expect_absent "the warning is not phrased as a refusal" "BLOCKED" "$GATE_ERR"
expect_status "the row is still appended for a near-fieldless brief" "1" "$(roster_rows "$R10C")"
ABSENT=$(roster_field "$ROW" absent)
expect_contains "the row records the duration absence" "duration" "$ABSENT"
expect_contains "the row records the progress absence" "progress" "$ABSENT"
expect_contains "the row records the missing agent name" "name" "$ABSENT"
expect_absent "the deliverable it DID name is not recorded absent" "deliverable" "$ABSENT"
expect_status "the absent contract field is empty in the row, not fabricated" "" "$(roster_field "$ROW" duration)"
# An OMITTED model is not an absence finding — the Agent tool inherits the
# orchestrator's model when none is given, so a warning here would fire on the
# ordinary case and train the operator to read past the real ones.
expect_absent "an omitted model is NOT recorded as an absence" "model" "$ABSENT"

section "S10W — a brief naming NO deliverable is REFUSED; the in-brief waiver is the only way through"
#
# USER-DIRECTED (epic-15 post-w4): "A wall. It should be a wall." The absence
# warning above was the whole enforcement for the one contract field the rest of
# the machinery cannot work without — the sweeper's landing verdict has nothing to
# stat, and a dispatch that dies quietly leaves nothing behind. So this single
# field escalates from warn to REFUSAL, and every escape from the refusal is a
# line in the brief, which means it lands on the roster.
#
# Everything else stays exactly where it was: progress absence warns, duration
# absence warns. This is one wall, not a policy.

BRIEF_NO_DELIVERABLE='Your task: go and do the thing, please.
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-nodeliv.progress
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_DELIVERABLE" "w99-nodeliv")"

expect_eq "a dispatch whose brief names no deliverable is REFUSED" "deny" "$GATE_VERDICT"
expect_eq "the refusal's stdout is ONE deny verdict and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_contains "the refusal is phrased as a refusal, in the renderer's one line" \
  "bionic: dispatch refused — " "$GATE_ERR"
expect_contains "the refusal names the field that is missing" "names no deliverable" "$GATE_ERR"
expect_contains "the refusal shows a label that lifts one" "Expected artifact:" "$GATE_ERR"
expect_contains "the refusal names the waiver escape verbatim" "Deliverable-waiver:" "$GATE_VERR"
# The wrong fix would be the environment attestation's — this refusal is a
# different one and must not send the operator to re-run the probe.
expect_absent "the refusal does not name the attestation fix command" "preflight-probe.sh" "$GATE_ERR$GATE_REASON"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- deliverable PRESENT: wholly unaffected ----
REPO=$(make_repo r10w2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-hasdeliv")"
expect_status "a brief that names a deliverable is not touched by the wall" "0" "$GATE_ST"
expect_absent "…and prints no refusal" "BLOCKED" "$GATE_ERR"
expect_status "…and is journalled as before" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- progress absence stays WARN-ONLY: only the deliverable escalated ----
BRIEF_NO_PROGRESS='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-noprog.txt
Expected duration: ~25 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_PROGRESS" "w99-noprog")"
expect_status "an absent PROGRESS path still passes — only the deliverable escalated" "0" "$GATE_ST"
expect_contains "…and is still warned" "progress" "$GATE_ERR"
expect_absent "…and is never phrased as a refusal" "BLOCKED" "$GATE_ERR"

# ---- the waiver: refusal becomes a warning that echoes the reason ----
BRIEF_WAIVED='Your task: answer one question from the tree; nothing durable is produced.
Deliverable-waiver: read-only reconnaissance, the answer is the report itself
Expected duration: ~10 minutes.
Progress artifact: .bionic/tmp/w99-waived.progress
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_WAIVED" "w99-waived")"
R10W4=$(roster_path "$REPO" "$SID_A")
ROW=$(roster_nth_row "$R10W4" 1)

expect_status "an in-brief waiver converts the refusal into a pass" "0" "$GATE_ST"
expect_absent "a waived dispatch prints no refusal" "BLOCKED" "$GATE_ERR"
expect_contains "the waiver is echoed on stderr, so it is never silent" \
  "read-only reconnaissance, the answer is the report itself" "$GATE_ERR"
expect_contains "the echo is a warning, not a verdict" "WARN" "$GATE_ERR"
expect_status "the waived dispatch is journalled" "1" "$(roster_rows "$R10W4")"
expect_status "the row LEDGERS the waiver reason — every waiver is on the record" \
  "read-only reconnaissance, the answer is the report itself" "$(roster_field "$ROW" waiver)"
# The waiver excuses the refusal; it does not make the fact untrue.
expect_contains "the row still records the deliverable as absent" \
  "deliverable" "$(roster_field "$ROW" absent)"
expect_status "…and fabricates no deliverable path" "" "$(roster_field "$ROW" deliverable)"
# The waiver value must stop where the next labelled field starts.
expect_absent "the waiver reason does not swallow the field after it" \
  "10 minutes" "$(roster_field "$ROW" waiver)"

# ---- a waiver with no reason is not a waiver ----
BRIEF_EMPTY_WAIVER='Your task: do the thing.
Deliverable-waiver:
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_EMPTY_WAIVER" "w99-emptywaiver")"
expect_eq "a reasonless waiver does not open the wall" "deny" "$GATE_VERDICT"
expect_contains "…and the refusal still names the escape" "Deliverable-waiver:" "$GATE_VERR"

# ---- the ordinary brief records no waiver ----
REPO=$(make_repo r10w6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-nowaiver")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief that waives nothing carries an empty waiver field" \
  "" "$(roster_field "$ROW" waiver)"
expect_absent "…and no waiver is echoed for it" "waived" "$GATE_ERR"

section "S10L — the LIVENESS fields are lifted: cadence + the subprocess claim (6-axis A-1)"
#
# The ratified liveness contract shipped into skills/canonical-sdlc/SKILL.md
# §Dispatch in task 4/7 — "The progress-artifact path carries a `cadence`
# alongside it" and "A subprocess claim — a process pattern plus its output file
# — is conditional-required". The Step-6 six-axis review found the procedure
# layer instructing authors to declare two fields this writer had no extraction
# site for, with hooks/stop-check.sh:389 already READING `claims=` off the row
# (axis-3 FAIL: a shipped reader with no producer). These cases are the writer
# half of that closure; tests/stop-check.test.sh §8(g) drives the reader half
# over a row THIS gate really wrote.
#
# GRAMMAR, stated because it is the one place this extractor reads a value that
# is not a path and not free text: `cadence` may be introduced by a colon OR by
# whitespace alone, because the ratified sentence puts it "alongside" the
# progress path inside one sentence rather than on a labeled line of its own.
# The subprocess claim's PATTERN is the backticked/quoted run when the author
# marks one, else the text up to the first comma or arrow; the output file half
# is the path the same span carries.

BRIEF_LIVENESS='Canonical-sdlc Step 4, task 4/10 of epic-99 wave-01; build · audited · wave.
Your task: the widget, behind the existing seam.
Expected artifact: .bionic/docs/record/w99-live.txt
Expected duration: ~50 minutes. Progress: .bionic/tmp/w99-live.progress, cadence ~6m.
Subprocess claim: `bash tests/run.sh` → .bionic/tmp/w99-suite.log
Exit condition: the artifact exists and the suite is green.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LIVENESS" "w99-live")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)

expect_status "liveness brief: the dispatch passes" "0" "$GATE_ST"
expect_status "the row lifts the cadence declared beside the progress path" \
  "~6m." "$(roster_field "$ROW" cadence)"
expect_status "the row lifts the subprocess claim's PATTERN, backticks stripped" \
  "bash tests/run.sh" "$(roster_field "$ROW" claims)"
expect_status "the progress path still stops at the cadence that follows it" \
  ".bionic/tmp/w99-live.progress" "$(roster_field "$ROW" progress)"
# THE REWRITTEN ASSERTION (Step-6 critic N-2). The line here used to read
#   expect_absent "the cadence value stops at the next label" "Subprocess" …
# which certified a property that was never under threat — the span was ALWAYS
# bounded by the next label — while the real defect (a value running ON past its
# own duration token, on its own line, before any label) went undriven and the
# green masked it. The property that matters is that cadence carries the token
# and NOTHING after it; the run-on case below drives the shape the production
# writer actually emits, and this pins the no-run-on baseline exactly.
expect_status "cadence carries the duration token and no run-on (real property, N-2)" \
  "~6m." "$(roster_field "$ROW" cadence)"
expect_status "the duration is unharmed by the new labels" \
  "~50 minutes." "$(roster_field "$ROW" duration)"

# ---- THE RUN-ON case (Step-6 critic N-2, C-1/F-3 root): cadence followed by
# run-on NON-label prose on the SAME line must still lift a bounded token. This
# is the shape the production writer emitted onto the live roster
# (w2-t3-victim2: `cadence=2m) claims=…`) — the field-merge that flipped a
# visibly-alive agent to UNMET by feeding parse_seconds a value it refuses. The
# defect is NOT rescued by a following label: the run-on sits BEFORE the label,
# already inside the value. Bounded extraction stops at the first clause
# boundary (comma / closing bracket / newline), the same restraint claimpat()
# already applies to the subprocess pattern.
BRIEF_CADENCE_RUNON='Canonical-sdlc Step 4, task 4/12 of epic-99 wave-01; build · audited · wave.
Your task: the widget behind the seam.
Expected artifact: .bionic/docs/record/w99-runon.txt
Expected duration: ~50 minutes.
Progress: .bionic/tmp/w99-runon.progress, cadence 2m) claims=w99-marker,/var/tmp/f3 and keep going
Exit condition: the artifact exists.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10Lrunon yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CADENCE_RUNON" "w99-runon")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "run-on cadence: the dispatch passes" "0" "$GATE_ST"
expect_status "run-on cadence: the value is the bounded token, not the swallowed line" \
  "2m" "$(roster_field "$ROW" cadence)"
expect_absent "run-on cadence: the swallowed 'claims=' text never enters the cadence field" \
  "claims=" "$(roster_field "$ROW" cadence)"
expect_absent "run-on cadence: nor does the swallowed path" \
  "/var/tmp/f3" "$(roster_field "$ROW" cadence)"
# The same bounded discipline protects duration from a run-on sentence (A-2:
# an unreadable duration silently exempts a row from overdue notification forever).
BRIEF_DURATION_RUNON='Your task: build it.
Expected artifact: .bionic/docs/record/w99-durrunon.txt
Expected duration: ~15 minutes. Every verbatim output you quote is its own evidence, laid out.
Progress: .bionic/tmp/w99-durrunon.progress
Suites: tests/widget.test.sh'
REPO=$(make_repo r10Ldur yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_DURATION_RUNON" "w99-durrunon")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "run-on duration: the value stops at the end of its own sentence" \
  "~15 minutes." "$(roster_field "$ROW" duration)"
expect_absent "run-on duration: the following sentence never enters the field" \
  "verbatim" "$(roster_field "$ROW" duration)"

# The colon form and the unquoted comma form — the two other shapes the ratified
# sentence permits an author to write.
#
# The claim line reads `Subprocess claim:` rather than the bare `Claims:` this
# fixture used until the Step-6 critic (F-2). That bare label was withdrawn from
# the grammar because it also matched "verify every claim the report claims:" in
# an ordinary review brief and invented a subprocess from it. The two properties
# this case exists for are untouched by the respelling — a cadence introduced by
# a colon on its own line, and an unquoted pattern that stops at the comma before
# its output file — and the vocabulary it now uses is the contract's own.
BRIEF_LIVENESS2='Task 4/11 of epic-99 wave-01.
Deliverables: record/w99-b.txt
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99-b.progress
Cadence: every 5 minutes
Subprocess claim: pgrep-me-w99, output .bionic/tmp/w99-b.log
Exit: the deliverable exists.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LIVENESS2" "w99-live2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the colon form of cadence lifts too" \
  "every 5 minutes" "$(roster_field "$ROW" cadence)"
expect_status "an unquoted claim pattern stops at the comma before its output file" \
  "pgrep-me-w99" "$(roster_field "$ROW" claims)"

# CONDITIONAL-REQUIRED, both directions: a brief that declares neither field
# leaves both EMPTY rather than fabricating one, and — because the subprocess
# claim is declared only when the task backgrounds a long command — its absence
# is never an absence FINDING. The whole point of the contract is that shape
# emerges from which fields are present.
REPO=$(make_repo r10L3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-noclaim")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief with no subprocess claim leaves claims= empty, not fabricated" \
  "" "$(roster_field "$ROW" claims)"
expect_status "a brief with no cadence leaves cadence= empty" "" "$(roster_field "$ROW" cadence)"
expect_absent "an undeclared subprocess claim is NOT an absence finding" \
  "claims" "$(roster_field "$ROW" absent)"

# THE NEGATIVE DIRECTION, which is the one that was missing (Step-6 critic F-2).
# Every case above declares a liveness contract and checks it is read correctly.
# None checked the far more common brief that declares NONE and merely uses one
# of the words in prose — and both labels fabricated a declaration from it.
#
# Fabrication is not neutral noise here. Under the ratified contract
# (skills/canonical-sdlc/SKILL.md) field PRESENCE is the shape key — "shape
# emerges from which are present… adding a subprocess claim is a delegated
# command" — and a claims= value opens a `-- claimed process (P2) --` section
# whose pgrep finds nothing and prints `live: no`, the ALARM direction. So a
# brief that says "keep a steady cadence" was classified long-shape and armed a
# quiescence watcher, and one that says "verify every claim" grew a phantom
# subprocess. Both briefs below are verbatim from the critic's repro
# (.bionic/docs/record/w3-critic-repro-lift.sh, briefs C and D).
BRIEF_PROSE_CADENCE='Your task: write the report.
Deliverables: .bionic/docs/record/w99.md
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99.progress, a line per section.
Scope constraint: keep a steady cadence and do not batch the sections.
Exit: report written.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CADENCE" "w99-prose1")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the word 'cadence' in ordinary prose declares no cadence" \
  "" "$(roster_field "$ROW" cadence)"
# …and the fix is not a blunt one: the fields this brief DOES declare still lift.
expect_status "…while the progress path the same brief declares still lifts" \
  ".bionic/tmp/w99.progress" "$(roster_field "$ROW" progress)"
expect_status "…and its duration" "~40 minutes." "$(roster_field "$ROW" duration)"

BRIEF_PROSE_CLAIMS='Your task: audit the report.
Deliverables: .bionic/docs/record/audit.md
Expected duration: ~20 minutes.
Progress: .bionic/tmp/audit.progress, a line per claim checked.
Scope constraint: verify every claim the report claims: proof or the label unverified.
Exit: audit written.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CLAIMS" "w99-prose2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief that REVIEWS claims declares no subprocess claim" \
  "" "$(roster_field "$ROW" claims)"
expect_status "…and grows no cadence either" "" "$(roster_field "$ROW" cadence)"
expect_status "…while its own progress path is still read" \
  ".bionic/tmp/audit.progress" "$(roster_field "$ROW" progress)"

# The cadence rule stated as the rule it is: the word only declares a cadence
# where the contract puts it — beside the progress path — so the SAME word in the
# SAME brief lifts or does not lift depending on where it falls.
BRIEF_CADENCE_PLACE='Your task: build it.
Deliverables: .bionic/docs/record/w99.md
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99.progress, cadence ~9m.
Scope constraint: keep a steady cadence throughout.
Exit: built.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CADENCE_PLACE" "w99-place")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the cadence beside the progress path is the one that counts" \
  "~9m." "$(roster_field "$ROW" cadence)"

section "S10d — rows APPEND; the roster is a ledger, not a slot"

REPO=$(make_repo r10d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "first-agent")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "second-agent")"
R10D=$(roster_path "$REPO" "$SID_A")
expect_status "two dispatches leave two rows" "2" "$(roster_rows "$R10D")"
expect_status "the first row survives the second dispatch" "first-agent" "$(roster_field "$(roster_nth_row "$R10D" 1)" name)"
expect_status "the second row is the second dispatch" "second-agent" "$(roster_field "$(roster_nth_row "$R10D" 2)" name)"
expect_status "the schema header is written once, not per row" "1" \
  "$(grep -c '^# bionic session roster' "$R10D")"

section "S10e — the roster is per-session from birth (D-5)"

REPO=$(make_repo r10e yes)
write_attestation "$REPO" "$SID_A"
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "agent-of-A")"
run_gate "$(mk_agent_payload "$SID_B" "$REPO" "$BRIEF_FULL" "agent-of-B")"
RA=$(roster_path "$REPO" "$SID_A"); RB=$(roster_path "$REPO" "$SID_B")
expect_status "session A has its own roster file" "0" "$([ -f "$RA" ] && echo 0 || echo 1)"
expect_status "session B has its own roster file" "0" "$([ -f "$RB" ] && echo 0 || echo 1)"
expect_status "session A's roster holds only A's launch" "1" "$(roster_rows "$RA")"
expect_status "session B's roster holds only B's launch" "1" "$(roster_rows "$RB")"
expect_status "A's row is A's agent" "agent-of-A" "$(roster_field "$(roster_nth_row "$RA" 1)" name)"
expect_status "B's row is B's agent" "agent-of-B" "$(roster_field "$(roster_nth_row "$RB" 1)" name)"
expect_status "no shared single-slot roster.state was created" "1" \
  "$([ -f "$REPO/.bionic/tmp/roster.state" ] && echo 0 || echo 1)"

section "S10f — dead-session rosters are pruned, LIVE foreign ones are not (D-5)"
#
# Same liveness rule task 4/2 established for the attestation
# (hooks/preflight-probe.sh: a session is live iff its transcript still exists
# somewhere under CLAUDE_CONFIG_DIR/projects). A live foreign session's roster
# surviving another session's dispatch IS the concurrency D-5 exists for.

SID_DEAD="deadfeed-0000-4000-8000-000000000001"
SID_LIVE="1ivefeed-0000-4000-8000-000000000002"
CFG="$SANDBOX/cfg10f/.claude"
mkdir -p "$CFG/projects/-some-project"
: > "$CFG/projects/-some-project/$SID_LIVE.jsonl"
: > "$CFG/projects/-some-project/$SID_A.jsonl"
# SID_DEAD deliberately has NO transcript anywhere.

REPO=$(make_repo r10f yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic/tmp"
# THE PRUNE READS THE PREFIX, so the fixture is a prefix (tests/lib/roster-row.sh's
# `roster_row_prefix_only`, S14): what decides here is whether the FILE survives, and the
# row exists only to make the file a roster the reader recognises.
{ roster_header; roster_row_prefix_only status=intended "session=$SID_DEAD" name=ghost; } \
  > "$(roster_path "$REPO" "$SID_DEAD")"
{ roster_header; roster_row_prefix_only status=intended "session=$SID_LIVE" name=neighbour; } \
  > "$(roster_path "$REPO" "$SID_LIVE")"

GATE_CONFIG_DIR="$CFG"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
probe_env_on   # restore the file-wide sandbox, never the operator's own config dir

expect_status "the dispatch still passes while pruning" "0" "$GATE_ST"
expect_status "a DEAD session's roster is pruned" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_DEAD")" ] && echo 0 || echo 1)"
expect_status "a LIVE foreign session's roster is left untouched" "0" \
  "$([ -f "$(roster_path "$REPO" "$SID_LIVE")" ] && echo 0 || echo 1)"
expect_contains "the live foreign roster's content is unmodified" "neighbour" \
  "$(cat "$(roster_path "$REPO" "$SID_LIVE")" 2>/dev/null)"
expect_status "our own roster was written" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# The prune must not reach across artifacts: the attestation files share the
# same directory and the same per-session scheme.
expect_status "the prune leaves attestations alone" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"

section "S10g — a roster WRITE FAILURE warns and leaves the verdict alone"
#
# TDD §7: starts fail open. The roster is a ledger, not a wall — a gate that
# refused a dispatch because it could not journal it would be a new failure
# mode, not a safety property.

REPO=$(make_repo r10g yes)
write_attestation "$REPO" "$SID_A"
chmod 555 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 755 "$REPO/.bionic/tmp"
expect_status "an unwritable state dir does not change the PASS verdict" "0" "$GATE_ST"
expect_empty "a write failure prints nothing on stdout" "$GATE_OUT"
expect_contains "a write failure is warned on stderr" "WARN" "$GATE_ERR"
expect_status "no roster file was left behind" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

section "S10h — a symlinked roster path is never written through (§8)"
#
# A hostile repo controls its own .bionic/ contents. It may make this gate fail
# to journal; it must not gain an arbitrary-file append. (The DIRECTORY-level
# variants are already refused upstream by the attestation check — S8 drives
# them — so the file level is the only one reachable here.)

REPO=$(make_repo r10h yes)
write_attestation "$REPO" "$SID_A"
DECOY_ROSTER="$SANDBOX/decoy-roster.txt"
printf 'untouched\n' > "$DECOY_ROSTER"
ln -s "$DECOY_ROSTER" "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a symlinked roster path does not change the PASS verdict" "0" "$GATE_ST"
expect_contains "a symlinked roster path is warned" "WARN" "$GATE_ERR"
expect_status "the symlink target is not appended to" "untouched" "$(cat "$DECOY_ROSTER")"

section "S10i — no row on any path that is not a launch"

# refused dispatch (active wave, the environment probe refuses): the launch never
# happens. The driver moved with the wall itself in epic-16 wave-02 — a missing
# attestation is now taken rather than refused, so the refusal this case needs is the one
# that survived: a blocking probe failure, here an unwritable state directory.
REPO=$(make_repo r10i yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_status "a REFUSED dispatch still exits 2" "2" "$GATE_ST"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# no active wave: this gate has nothing to decide and nothing to ledger.
REPO=$(make_repo r10i2 no)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a dispatch outside an active wave exits 0" "0" "$GATE_ST"
expect_empty "a dispatch outside an active wave stays silent" "$GATE_ERR"
expect_status "a dispatch outside an active wave writes no roster" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# a non-Agent tool is not a launch.
REPO=$(make_repo r10i3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_bash_payload "$SID_A" "$REPO")"
expect_status "a Bash call in an attested active wave writes no roster" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

section "S11 — the unarmed-sweeper nag is GONE (epic-16 w2 task S1)"
#
# A warn-only nag stood here: it asked the sibling sweeper whether a watcher was live for
# this session and, when none was, named the command to arm one. Both the watcher and its
# `status` verb are deleted, so the nag went with them — supervision reads facts off disk at
# the moment a decision needs them rather than depending on a process staying up.
#
# Pinned as an ABSENCE, in the section that used to drive its presence, for two reasons. A
# nag that names a verb the CLI no longer answers to is worse than no nag: it sends an
# operator to a refusal. And this gate has a standing invariant that the allow path prints
# nothing but ratified advisories — a stale one would be invisible to every other assertion
# here, all of which only ask about BLOCKED.

# ---- no ledger at all: the dispatch passes in SILENCE, where it used to warn ----
REPO=$(make_repo r11a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no-ledger dispatch passes" "0" "$GATE_ST"
# expect_absent, not expect_empty (wave-session-bound-run S5): an unbound engaged
# session now gets ONE unrelated advisory line here too (the newest-plan fallback
# notice, S25) — this fixture's own claim was always about the sweeper, never
# about the channel being empty outright.
expect_absent "…in silence: there is no sweeper state left to nag about" "sweeper" "$GATE_ERR"

# ---- a ledger present but naming no live anything: still silent ----
#
# The ledger survives as ack's journal, so this fixture is the shape a real session leaves
# behind. The gate must not read it, or resurrect an opinion about it.
REPO=$(make_repo r11b yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic/tmp"
{
  printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n'
  printf 'sweeper-ledger/v1|event=ack|at=2026-08-06T00:00:00Z|epoch=1780000000|pid=999999|session=%s|name=some-row\n' \
    "$SID_A"
} > "$REPO/.bionic/tmp/sweeper-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a dispatch over an ack-only ledger passes" "0" "$GATE_ST"
# expect_absent, not expect_empty — see r11a's note just above (S5).
expect_absent "…and still says nothing about it" "sweeper" "$GATE_ERR"

# ---- the gate never names the deleted verbs, and never invokes the sweeper at all ----
GATE_SRC="$(cat "$GATE")"
expect_absent "the gate source names no arm command" "session-sweeper.sh arm" "$GATE_SRC"
expect_absent "…and carries no SWEEPER_ARM_CMD constant" "SWEEPER_ARM_CMD" "$GATE_SRC"
# The stronger claim, and the one that keeps a future nag from growing back through some
# other verb: this gate runs the sweeper on NO path. It writes the roster the verdict later
# reads; it never asks the verdict anything.
expect_status "the gate executes the sweeper on no path at all" "0" \
  "$(printf '%s' "$GATE_SRC" | grep -cE 'bash [^\n]*session-sweeper\.sh')"

# ---- a REFUSED dispatch is unchanged: still exits 2, still says nothing about a sweeper ----
REPO=$(make_repo r11d yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_status "a refused dispatch (the probe refused) still exits 2" "2" "$GATE_ST"
expect_absent "a refused dispatch prints no sweeper nag" "session-sweeper.sh" "$GATE_ERR"

section "S12 — inference WITHDRAWN: an unlabeled path never satisfies the wall (R1, AC-3)"
#
# THE REVERSAL (Step-6 decision, plan assumption 48). Wave-02 R4 let an unlabeled
# `record/`-prefixed path satisfy the deliverable wall by INFERENCE — walking the
# whole brief for a path-shaped token. The Step-6 critic (N-1) found the machine
# then enforced that GUESS with a declared fact's full weight: the landing gate
# ordered the agent to write a path the wall picked out of prose. Chris's ruling:
# the wall NEVER guesses a deliverable from prose. A deliverable comes ONLY from a
# canonical label; a brief that declares none REFUSES at dispatch, naming what to
# add. These cases pin the withdrawal: every prose path that used to infer now
# refuses, and only a labeled declaration passes.

# ---- an unlabeled .bionic/docs/record/ mention no longer infers -> REFUSE ----
BRIEF_BARE_RECORD='Your task: read the tree and note what you find.
It belongs in .bionic/docs/record/w99-bare.md when finished.
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r12a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_RECORD" "w99-bare")"
expect_eq "an unlabeled .bionic/docs/record/ mention is REFUSED (no inference)" "deny" "$GATE_VERDICT"
expect_contains "…with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "…and no prose path is lifted onto a roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- a bare record/ prefix in prose is refused the same way ----
BRIEF_BARE_RECORD2='Your task: capture findings as you go.
Write to record/w99-bare2.md at the end.
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r12a2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_RECORD2" "w99-bare2")"
expect_eq "a bare record/ prefix in prose is also REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- the same, but DECLARED: adding a canonical label is the whole fix ----
#
# The friction R1 accepts is that a brief must DECLARE its deliverable. The same
# work, with `Expected artifact:` in front of the path, passes and is `declared`.
BRIEF_BARE_DECLARED='Your task: read the tree and note what you find.
Expected artifact: .bionic/docs/record/w99-bare.md
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r12a3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_DECLARED" "w99-baredecl")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "declaring the same path with a canonical label passes" "0" "$GATE_ST"
expect_status "…and the row carries the declared path" \
  ".bionic/docs/record/w99-bare.md" "$(roster_field "$ROW" deliverable)"
expect_status "…marked declared" "declared" "$(roster_field "$ROW" source)"

# ---- a non-record path in a 'Read first:' is still refused (unchanged) ----
BRIEF_ONLY_READFIRST='Read first: skills/canonical-sdlc/SKILL.md
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r12b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_READFIRST" "w99-readfirst")"
expect_eq "a brief whose only path is a non-record 'Read first:' mention is refused" \
  "deny" "$GATE_VERDICT"
expect_contains "…with the deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- an unlabeled .bionic/tmp/ path is refused (a scratch path was never durable) ----
BRIEF_ONLY_TMP='Your task: write scratch notes to .bionic/tmp/w99-scratch.md as you go.
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r12c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_TMP" "w99-tmp")"
expect_eq "a brief whose only unlabeled path is under .bionic/tmp/ is refused" "deny" "$GATE_VERDICT"
expect_contains "…with the deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- a labeled brief records source=declared; behavior otherwise unchanged ----
REPO=$(make_repo r12d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-declared")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a labeled deliverable passes the wall (unchanged)" "0" "$GATE_ST"
expect_status "the row's deliverable is exactly the labeled path" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "the row marks the source as declared" "declared" "$(roster_field "$ROW" source)"
expect_status "duration is unaffected" \
  "~25 minutes." "$(roster_field "$ROW" duration)"
expect_status "progress is unaffected" \
  ".bionic/tmp/w99-widget.progress" "$(roster_field "$ROW" progress)"

# ---- a LABELED .bionic/tmp/ deliverable keeps today's behavior (label is explicit design) ----
BRIEF_LABELED_TMP='Your task: report interim status to a scratch file.
Expected artifact: .bionic/tmp/w99-labeledtmp.txt
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r12e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LABELED_TMP" "w99-labeledtmp")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a LABELED .bionic/tmp/ deliverable still passes the wall (unchanged)" "0" "$GATE_ST"
expect_status "…and is recorded exactly as labeled" \
  ".bionic/tmp/w99-labeledtmp.txt" "$(roster_field "$ROW" deliverable)"
expect_status "…marked declared (the label is explicit designation)" \
  "declared" "$(roster_field "$ROW" source)"

# ---- the refusal text names the declared-only rule, not an inference rule ----
REPO=$(make_repo r12f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_READFIRST" "w99-refusaltext")"
expect_contains "the refusal names a canonical label to add" "Expected artifact:" "$GATE_ERR"
expect_contains "the refusal says the wall never guesses" "never guesses" "$GATE_VERR"
expect_absent "…and no longer promises to infer an unlabeled record/ mention" \
  "inferred automatically" "$GATE_ERR"

# ---- SHADOWED LABEL: an earlier pathless deliverable-kind hit no longer hides a
# later real labeled line — the declared extractor iterates every deliverable hit ----
#
# The live specimen (a real brief false-blocked): a brief quoting landing-verdict
# prose — "…per deliverable:" — ahead of its real "Expected artifact:" line. The
# bare `deliverable` label hits FIRST by position, and its span ("missing=<x> |
# empty=<y>") carries no path. Under R1 the extractor does not stop at the first
# hit; it walks EVERY deliverable-kind hit in order and returns the first that
# yields a path — so the real, later, labeled line is recovered, and recorded
# `declared` because it came from a label, not from a prose scan.
BRIEF_SHADOW_LABEL='UNMET detail lists every failing conjunct, per deliverable:
missing=<x> | empty=<y>

Expected artifact: .bionic/docs/record/w1-specimen.md
Suites: tests/widget.test.sh'

REPO=$(make_repo r12g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_SHADOW_LABEL" "w1-specimen")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "an earlier pathless 'per deliverable:' hit no longer shadows the real labeled line" \
  "0" "$GATE_ST"
expect_absent "…and prints no refusal" "BLOCKED" "$GATE_ERR"
expect_status "the roster records the real declared deliverable, recovered by iterating hits" \
  ".bionic/docs/record/w1-specimen.md" "$(roster_field "$ROW" deliverable)"
expect_status "the recovered value is DECLARED — it came from a label, not a prose scan" \
  "declared" "$(roster_field "$ROW" source)"

section "S13 — Step-6 review remediation A + R1: C-1/C-2/F-RD, S-1, S-2, S-4"
#
# Holes found by the independent Step-6 reviewers (w1-review-corr-sec.md and, for
# this wave, w2-review-cs.md C-2 + w2-review-rd.md F-RD). Each case below was
# written and run against the PRE-FIX gate first and observed to fail.

# ---------- C-1/F-RD (blocking) — a path the brief tells the agent to READ, or
# merely names in prose, must never become the deliverable. Under R1 the property
# is enforced structurally, not by a label whitelist: the deliverable comes ONLY
# from a canonical label, so an input path (labeled or bare prose) is refused, not
# guessed. This ends the whitelist arms race the critic named — F-RD walked past
# the wave-01 `Read first:`/`scope constraint:` whitelist through a `Context:`
# heading the guard did not know.

BRIEF_READFIRST_RECORD='Please review the design.

Read first: .bionic/docs/record/w1-walk.md and the spec.

Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_READFIRST_RECORD" "readerbot")"
expect_eq "C-1: a record/ path inside a Read-first span is never the deliverable — the dispatch is refused" \
  "deny" "$GATE_VERDICT"
expect_contains "C-1: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "C-1: …and no roster row claims the input as a deliverable" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# The other input-designating label, refused the same way.
BRIEF_SCOPE_RECORD='Your task: tidy the tree.
Scope constraint: do not touch .bionic/docs/record/context.md.
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_SCOPE_RECORD" "scopebot")"
expect_eq "C-1: a record/ path inside a Scope-constraint span is never the deliverable either" \
  "deny" "$GATE_VERDICT"

# F-RD, EXACT re-materialization: the review's own brief named its inputs under a
# `Context:` heading the wave-01 whitelist did not recognise, and the wall inferred
# the AUDITOR's report as the reviewer's deliverable — the landing gate then ordered
# the reviewer to overwrite an independent audit. Under R1 there is no inference:
# `Context:` is not a canonical deliverable label, so the path is never lifted and
# the dispatch REFUSES, naming what to declare.
BRIEF_CONTEXT_PATH='Your task: an independent read-and-duplication review.
Context: read the auditor report record/w2-auditor-report.md and the spec first.
Report: your findings belong in record/w2-review-rd.md.
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13frd yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CONTEXT_PATH" "w2-rev-rd")"
expect_eq "F-RD: a 'Context:' record/ path is NOT lifted as the deliverable — the dispatch is refused" \
  "deny" "$GATE_VERDICT"
expect_contains "F-RD: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "F-RD: …and no roster row contracts the reviewer to the auditor's report" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# C-2 (w2-review-cs.md) — the LABELLED span used to take up to four path tokens and
# run on into whatever prose followed, so files the brief named as INPUTS ("while
# you are there, read …"; "do not touch …") were recorded `source=declared` and the
# landing gate demanded all four. R1 answered by taking the FIRST path in the label's
# first sentence; the R6 critic showed that is a guess with a declaration's weight
# (R6-1), so R7 refuses instead: a span yielding more than one path names candidates
# and asks the author which one is theirs. The input paths are still never contracted —
# now because nothing is contracted until the brief is unambiguous.
BRIEF_LABEL_RUNON='Your task: write the report.
Expected artifact: record/w99-report.md — and while you are there, read record/legacy-notes.md
and do not touch tests/run.sh or .bionic/docs/plans/epic-99-test/wave-01-test.plan.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r13c2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LABEL_RUNON" "runonbot")"
# T26 (critic Issue 3): this brief declares Suites:, so ambiguity is its only fault (the
# absent-deliverable arm now recognises the candidate list as ANOTHER arm's product and
# stays quiet rather than repeating it) — the ordinary single-arm wire, which keeps the
# ambiguity arm's own verbatim detail (since wave-19 T4 one fault is a deny verdict too, its own detail on the reason). "which four paths did the wall see" is proven
# the same way as before: submitted ALONE, the declared artifact (record/w99-report.md) is
# accepted by "C-2 paired positive" right below, so it was never rejected as a bad path,
# only as one candidate among several this labelled span never disambiguated.
expect_eq "C-2: a run-on labelled span naming four paths is REFUSED as ambiguous (R7)" \
  "deny" "$GATE_VERDICT"
expect_status "C-2: …and no roster row demands any of the four" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# THE PAIRED POSITIVE: the exactly-one rule must not become "declaring is off" — a
# properly DECLARED path outside any input mention still lifts, and this is the
# resubmission the refusal above asks for: the same brief with the input clauses moved
# to their own labeled lines.
BRIEF_LABEL_CLEAN='Your task: write the report.
Expected artifact: record/w99-report.md
Read first: record/legacy-notes.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r13c3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LABEL_CLEAN" "cleanbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "C-2 paired positive: a cleanly declared deliverable still passes" "0" "$GATE_ST"
expect_status "C-2 paired positive: …recorded as the declared path" \
  "record/w99-report.md" "$(roster_field "$ROW" deliverable)"
expect_status "C-2 paired positive: …marked declared" "declared" "$(roster_field "$ROW" source)"

# ---------- S-1 (High) — the waiver label lifts only at LINE START, and a
# placeholder-shaped reason is not a reason. One quoted line of documentation
# must not silence the landing contract.

# (a) the reviewer's revsec002 quoter: a real deliverable, and the wall's own
# message quoted mid-sentence. The row must carry NO waiver.
BRIEF_QUOTER='Expected artifact: .bionic/docs/record/quoter-out.md
Expected duration: 20 minutes

Check that the wall message still reads: "Or waive it — Deliverable-waiver: <why this dispatch produces nothing durable>".
Report whether the wording drifted.
Suites: tests/widget.test.sh'

REPO=$(make_repo r13d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTER" "quoter")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S-1: a mid-sentence quoted waiver label lifts NO waiver" \
  "" "$(roster_field "$ROW" waiver)"
expect_absent "S-1: …and nothing is echoed as waived" "waived" "$GATE_ERR"
expect_status "S-1: …the real labeled deliverable is unaffected" \
  ".bionic/docs/record/quoter-out.md" "$(roster_field "$ROW" deliverable)"

# (b) the same quoting with NO deliverable — this is the fail-open the review
# named: one quoted line and the wall opens. The reason quoted here is a REAL
# one, so only the line-start rule can refuse it.
BRIEF_QUOTED_WAIVER='Your task: check the wall text.
Confirm the message still reads: "Or waive it — Deliverable-waiver: read-only reconnaissance".
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTED_WAIVER" "quoter2")"
expect_eq "S-1: a quoted mid-sentence waiver does not open the absent-deliverable wall" \
  "deny" "$GATE_VERDICT"
expect_contains "S-1: …the refusal still names the escape" "Deliverable-waiver:" "$GATE_VERR"

# (c) a line-start waiver whose reason is the literal placeholder from the wall
# text is not a reason.
BRIEF_PLACEHOLDER_WAIVER='Your task: do the thing.
Deliverable-waiver: <why this dispatch produces nothing durable>
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PLACEHOLDER_WAIVER" "placeholder")"
expect_eq "S-1: a placeholder-shaped waiver reason does not open the wall" "deny" "$GATE_VERDICT"

# CONTROL: a real line-start waiver still lifts, indented or not.
BRIEF_INDENTED_WAIVER='Your task: answer one question from the tree.
    Deliverable-waiver: read-only reconnaissance, the answer is the report itself
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_INDENTED_WAIVER" "waived2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S-1 control: an indented line-start waiver with a real reason still lifts" \
  "0" "$GATE_ST"
expect_status "S-1 control: …and is ledgered" \
  "read-only reconnaissance, the answer is the report itself" "$(roster_field "$ROW" waiver)"

# ---------- S-2 (Medium) — a deliverable that resolves outside the repo root is
# refused at dispatch, where it is still fixable. Otherwise the verdict stats
# arbitrary paths and reports their mtime back to the stopping agent.

BRIEF_ESCAPE_REL='Your task: do the thing.
Expected artifact: ../../../../../../etc/hosts
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13h yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ESCAPE_REL" "escaper")"
expect_eq "S-2: a ..-escaping deliverable is refused at the dispatch wall" "deny" "$GATE_VERDICT"
expect_contains "S-2: …the refusal is phrased as a refusal, in the renderer's one line" \
  "bionic: dispatch refused — " "$GATE_ERR"
expect_contains "S-2: …and names the offending path" "../../../../../../etc/hosts" "$GATE_VERR"
expect_status "S-2: …and no roster row is written for it" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

BRIEF_ESCAPE_ABS='Your task: do the thing.
Expected artifact: /usr/share
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r13i yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ESCAPE_ABS" "escaper2")"
expect_eq "S-2: an absolute out-of-repo deliverable is refused too" "deny" "$GATE_VERDICT"
expect_contains "S-2: …and names it" "/usr/share" "$GATE_VERR"

# CONTROL: an in-repo ABSOLUTE path is a perfectly good deliverable and must
# still pass — the check is containment, not a ban on absolute paths.
REPO=$(make_repo r13j yes)
write_attestation "$REPO" "$SID_A"
BRIEF_ABS_INREPO="Your task: do the thing.
Expected artifact: $REPO/.bionic/docs/record/w99-abs.md
Expected duration: 20 minutes
Suites: tests/widget.test.sh"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ABS_INREPO" "absbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S-2 control: an in-repo absolute deliverable still passes" "0" "$GATE_ST"
expect_status "S-2 control: …and is recorded verbatim" \
  "$REPO/.bionic/docs/record/w99-abs.md" "$(roster_field "$ROW" deliverable)"

# ---------- S-4 (Low, defence-in-depth) — the payload session_id is shape-checked
# before it is interpolated into any state path.
#
# The escape is only OBSERVABLE if the intermediate directories exist, so the
# fixture creates them; the vulnerability is the unchecked interpolation, not the
# directories. With sid `a/../../rogue`, both the attestation path and the roster
# path resolve to $REPO/.bionic/rogue.state — one level ABOVE the state dir the
# symlink guards protect.
SID_EVIL="a/../../rogue"
REPO=$(make_repo r13k yes)
mkdir -p "$REPO/.bionic/tmp/preflight-a" "$REPO/.bionic/tmp/roster-a"
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\n'
  printf 'kind=preflight-attestation\n'
  printf 'session_id=%s\n' "$SID_EVIL"
  printf 'written_at=1785790000\n'
  printf 'repo=%s\n' "$REPO"
} > "$REPO/.bionic/rogue.state"
run_gate "$(mk_agent_payload "$SID_EVIL" "$REPO" "$BRIEF_FULL" "evilsid")"
expect_status "S-4: a shape-invalid session_id degrades to a silent pass" "0" "$GATE_ST"
expect_status "S-4: …and NO roster row is written outside the state directory" "0" \
  "$(grep -c '^roster-state/' "$REPO/.bionic/rogue.state" 2>/dev/null)"
expect_absent "S-4: …and the escaped path is never named on stderr" "rogue.state" "$GATE_ERR"

section "S14 — a templated deliverable is not a declaration: it REFUSES (R1)"
#
# The `<slot>` shape has a long lineage. Wave-01 remediation A-b made `ispath()`
# reject any token carrying an unfilled `<…>` slot, so a brief quoting the wall's
# own help text — `Expected artifact: .bionic/docs/record/<name>.md` — could not
# lift a contract nothing would satisfy. Wave-02 R4 then FILLED the slot from the
# agent name and recorded `source=inferred`. R1 withdraws that fill: filling a slot
# from the agent's name is guessing a deliverable, which is exactly what the wall
# must never do. A slot is still not a path (ispath rejects it), so a brief whose
# ONLY deliverable is a template names no concrete path and REFUSES — the author is
# told at dispatch to name it exactly. A real declared line alongside the template
# is still recovered (the extractor iterates every deliverable hit).

BRIEF_QUOTES_HELP='Your task: check that the wall message still reads right.
It currently says: Fix: name a durable artifact path in the brief —
    Expected artifact: .bionic/docs/record/<name>.md
Report whether the wording drifted.
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r14a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTES_HELP" "helpquoter")"
expect_eq "a brief whose only deliverable is the help-text template is REFUSED (no fill)" \
  "deny" "$GATE_VERDICT"
expect_contains "…with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "…and no roster row is written at all" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# A quoted template ahead of a REAL labeled line: the real one is recovered (the
# extractor walks every deliverable hit), and the slot never reaches the row.
BRIEF_HELP_THEN_REAL='Your task: verify the wall text, then write up what you find.
The message reads: Expected artifact: .bionic/docs/record/<name>.md
Expected artifact: .bionic/docs/record/w99-shape2.md
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r14b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_HELP_THEN_REAL" "helpquoter2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a quoted template ahead of a real line does not shadow it" "0" "$GATE_ST"
expect_status "…the row carries the REAL artifact, never the slot" \
  ".bionic/docs/record/w99-shape2.md" "$(roster_field "$ROW" deliverable)"
expect_status "…recorded declared (it came from a label)" "declared" "$(roster_field "$ROW" source)"
expect_absent "…and the slot appears nowhere on the row" "<name>" "$ROW"

# An ordinary labeled deliverable is untouched by any of this.
REPO=$(make_repo r14c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-stillworks")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "control: an ordinary labeled deliverable is unaffected" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "…and is still marked declared" "declared" "$(roster_field "$ROW" source)"

# A templated PROGRESS path is also not filled — progress is advisory (absent
# warns), so a template that names no concrete path leaves it EMPTY and WARNED,
# exactly as a missing one is. The real deliverable is unaffected.
BRIEF_PLACEHOLDER_PROGRESS='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-progplaceholder.md
Progress artifact: .bionic/tmp/<name>.progress
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r14d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PLACEHOLDER_PROGRESS" "progplaceholder")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a templated PROGRESS path is not filled — the field is left empty" \
  "" "$(roster_field "$ROW" progress)"
expect_absent "…so no slot reaches the field the liveness check stats" "<" \
  "$(roster_field "$ROW" progress)"
expect_contains "…and the absent progress path is warned" "progress" "$GATE_ERR"
expect_status "…while the real deliverable still passes the wall" "0" "$GATE_ST"

section "S15 — the ship-day corners now pass BY DECLARING, not by guessing (R1, AC-3)"
#
# The two 2026-08-08 false blocks were GRAMMAR corners
# (`plans/epic-16-landing-contract/continuation.md` §charter-seed, decision 3: "Both of
# the day's false blocks were grammar corners (mid-string `<slot>` vs `^<`, and the
# quoted-help-text deliverable lift)"). R4 answered them by GUESSING a deliverable from
# prose and filling slots from the agent name. The Step-6 critic (N-1) showed the guess
# is then enforced with a declared fact's full weight, so Chris withdrew inference: the
# friction the wave wanted to remove was the requirement to DECLARE, and the reframe is
# that declaring is cheap and robustly parsed while guessing is off-thesis. So each
# corner now takes the same shape — as-written it REFUSES (there is no concrete declared
# path), and adding one canonical label makes it pass as `declared`.
#
# FIXTURE FIDELITY — declared, narrower than "verbatim": no ship-day brief text survives
# on disk (searched: `grep -rn "names no deliverable\|false-block" .bionic/docs/record/`);
# what survives is a DESCRIPTION of each corner in the charter seed, commit 121d277's
# message, and `record/w1-remediation-A2-report.md`. These briefs are RECONSTRUCTED to
# those descriptions. What IS verbatim is the thing that made the corner:
# BRIEF_QUOTES_HELP quotes this gate's own help text, where every ship-day `<name>.md`
# came from. Each corner is driven BOTH ways — refused as-written, accepted once declared.

# ---- corner 1: the MID-STRING slot in prose. As-written -> REFUSE ----
BRIEF_CORNER1='Canonical-sdlc Step 4, task S4 of epic-99 wave-02; build · audited · wave.
Your task: reconcile the label grammar with the declared parse.
Write your findings to .bionic/docs/record/w2-<task>-notes.md when the suite is green.
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r15a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CORNER1" "corner1")"
expect_eq "AC-3 corner 1 (mid-string slot in prose): REFUSED, no path is guessed" "deny" "$GATE_VERDICT"
expect_contains "AC-3 corner 1: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "AC-3 corner 1: …and no roster row is written" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# corner 1, DECLARED: adding a canonical label with a concrete name is the whole fix.
BRIEF_CORNER1_FIXED='Canonical-sdlc Step 4, task S4 of epic-99 wave-02; build · audited · wave.
Your task: reconcile the label grammar with the declared parse.
Expected artifact: .bionic/docs/record/w2-s4-notes.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r15a2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CORNER1_FIXED" "corner1")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "AC-3 corner 1 fixed: declaring a concrete path passes" "0" "$GATE_ST"
expect_status "AC-3 corner 1 fixed: …the row carries the declared path" \
  ".bionic/docs/record/w2-s4-notes.md" "$(roster_field "$ROW" deliverable)"
expect_status "AC-3 corner 1 fixed: …marked declared" "declared" "$(roster_field "$ROW" source)"
expect_absent "AC-3 corner 1 fixed: …no slot survives onto the roster" "<" "$ROW"

# ---- corner 2: the QUOTED-HELP-TEXT template. As-written it REFUSES (S14 r14a); the
# fix is BRIEF_HELP_THEN_REAL — the same quote plus a real declared line (S14 r14b).
# Both are pinned in S14; here we assert the FRAMING: the corner's resolution is to
# declare, and the declared line is what carries the contract.
REPO=$(make_repo r15b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_HELP_THEN_REAL" "helpquoter")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "AC-3 corner 2 (quoted help text + a real declaration): passes" "0" "$GATE_ST"
expect_status "AC-3 corner 2: …the declared line carries the contract, not the quoted slot" \
  ".bionic/docs/record/w99-shape2.md" "$(roster_field "$ROW" deliverable)"
expect_status "AC-3 corner 2: …recorded declared" "declared" "$(roster_field "$ROW" source)"

# ---- THE PLANTED FAILURE (AC-3): a brief naming no concrete path STILL refuses ----
#
# The wall did not become advisory. A brief that names no concrete declared path — no
# label, no record/ mention, no template — has given the machinery nothing to stat.
BRIEF_NOTHING='Your task: read the wall message through and tell me whether the wording drifted.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r15c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NOTHING" "saysnothing")"
expect_eq "AC-3 planted failure: a brief naming no plausible deliverable is STILL refused" \
  "deny" "$GATE_VERDICT"
expect_contains "AC-3 planted failure: …with the absent-deliverable refusal" \
  "names no deliverable" "$GATE_ERR"

# ---- an unnamed dispatch whose only deliverable is a template is refused (no fill,
# no ancestor fallback) — the withdrawal is total, not "fill when a name exists" ----
REPO=$(make_repo r15f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTES_HELP" "-")"
expect_eq "AC-3: an unnamed dispatch with only a templated path is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "AC-3: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- a real declared path always wins over a quoted template, wherever it sits, and
# is recorded DECLARED — the extractor walks every deliverable hit and takes the first
# that yields a concrete path ----
REPO=$(make_repo r15h yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_HELP_THEN_REAL" "helpquoter2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "AC-3: a quoted template ahead of a real line still loses to it" \
  ".bionic/docs/record/w99-shape2.md" "$(roster_field "$ROW" deliverable)"
expect_status "AC-3: …recorded declared, because a label yielded it" \
  "declared" "$(roster_field "$ROW" source)"

section "S16 — the combined preflight: a missing attestation AUTO-RUNS the probe (epic-16 w2 S5, AC-4)"
#
# Synthesis §3, the five serialized minutes between order and spawn: the operator was
# refused, ran the probe by hand, retried, and only then dispatched. R5 makes the
# attestation a FACT the gate takes for itself — the probe is run inline, once, and the
# dispatch proceeds. Blocking survives in exactly one place on this path: the probe
# REFUSING, which means the environment is genuinely broken and the fleet would die.
#
# The probe invoked here is the REAL `hooks/preflight-probe.sh` sitting beside the gate —
# no stub, no seam. Its environment is substituted instead (a sandboxed config dir and a
# fixture credential), which is the same technique preflight-probe.test.sh uses.

# ---- ONE invocation, order to spawn: no attestation in, dispatch out ----
REPO=$(make_repo r16a yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "AC-4: a dispatch with NO attestation is no longer refused" "0" "$GATE_ST"
expect_status "AC-4: …the probe ran inline and left this session's attestation on disk" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
expect_status "AC-4: …keyed to THIS session, not whatever the shell was" "0" \
  "$(grep -qx "session_id=$SID_A" "$REPO/.bionic/tmp/preflight-$SID_A.state" && echo 0 || echo 1)"
expect_contains "AC-4: …and the auto-run is announced, not silent" "attestation" "$GATE_ERR"
expect_absent "AC-4: …with no refusal anywhere in it" "BLOCKED" "$GATE_ERR"
expect_status "AC-4: …the dispatch is journalled exactly once (one invocation, one row)" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# The probe roots from the PINNED root, so the record it writes describes the repo the
# gate is guarding — the Synthesis field case (attestation redone because the root came
# from the shell's working directory) read the other way round.
# Compared PHYSICALLY on both sides. The sandbox lives under the platform temp dir,
# which is reached through a symlink on macOS (/var -> /private/var), so a string compare
# against the test's own spelling of the path would fail on a correct answer.
ATT_REPO=$(grep -m1 '^repo=' "$REPO/.bionic/tmp/preflight-$SID_A.state" | cut -d= -f2-)
expect_status "AC-4: …and the attestation names the pinned repo root" \
  "$(cd "$REPO" && pwd -P)" "$(cd "$ATT_REPO" 2>/dev/null && pwd -P)"

# ---- a FOREIGN-only attestation is the same fact: absent for me ----
REPO=$(make_repo r16b yes)
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "AC-4: a foreign-only attestation auto-probes rather than refusing" "0" "$GATE_ST"
expect_status "AC-4: …and session B's record is left strictly alone" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_B.state" ] && echo 0 || echo 1)"

# ---- probe FAILURE fails CLOSED: the one surviving attestation refusal ----
#
# Driven by an unwritable state directory rather than an absent credential: the
# credential's third source is the machine keychain, which no sandbox can take away, so
# an absent-credential fixture would pass on this operator's machine and fail on a build
# box. An unwritable directory is the same blocking-probe class and is deterministic.
REPO=$(make_repo r16c yes)
mkdir -p "$REPO/.bionic/tmp"
chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_status "AC-4: a probe that FAILS blocks the dispatch (the environment is broken)" \
  "2" "$GATE_ST"
expect_contains "AC-4: …the refusal is phrased as a refusal, in the renderer's one line" \
  "bionic: dispatch refused — " "$GATE_ERR"
expect_contains "AC-4: …and hands over the probe's own reason, not a paraphrase" \
  "state dir" "$GATE_VERR"
expect_status "AC-4: …and a blocked dispatch is journalled nowhere (AC-12)" "0" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 1 || echo 0)"

section "S17 — ledger hygiene: a refusal leaves NO row; a same-path claim WARNS (epic-16 w2 S4, AC-12)"
#
# The F-4 phantom-intended-rows class, closed by inventory rather than by inspection: the
# roster is compared BYTE FOR BYTE across a refused dispatch, so a row added anywhere on
# any refusal path fails this regardless of what it says. Each absence assertion carries
# its accepted-dispatch twin, because "no row was written" is trivially true of a gate
# that writes no rows at all.

# ---- the paired positive first: an accepted dispatch writes exactly one row ----
REPO=$(make_repo r17a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "AC-12 paired positive: an ACCEPTED dispatch creates exactly one row" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- and each refusal path leaves the inventory untouched ----
#
# The roster is pre-seeded with a real accepted dispatch so the comparison is against a
# NON-EMPTY ledger: "identical" then means the refusal added nothing, not that the file
# never existed.
for _case in nodeliverable outofrepo; do
  REPO=$(make_repo "r17-$_case" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "seed-row")"
  RP="$(roster_path "$REPO" "$SID_A")"
  BEFORE="$(cat "$RP" 2>/dev/null)"
  BEFORE_N="$(roster_rows "$RP")"
  case "$_case" in
    nodeliverable) _brief="$BRIEF_NOTHING" ;;
    outofrepo)     _brief='Your task: build it.
Expected artifact: ../../../../../../etc/hosts
Expected duration: ~15 minutes.' ;;
  esac
  # ONE WIRE WHATEVER THE FAULT COUNT (wave-19 T4, REQ-7, D8). These two cases used to sit
  # either side of a channel split — the deliverable-less brief's ONE fault on exit2, the
  # out-of-repo brief's two (it declares no instrument either) on deny. Both are a deny
  # verdict now. Refused is refused; the roster arms below are what this section is
  # actually about and neither is touched.
  _want=deny
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$_brief" "ghost-$_case")"
  expect_eq "AC-12 ($_case): the dispatch is refused" "$_want" "$GATE_VERDICT"
  expect_status "AC-12 ($_case): the roster is byte-identical across the refusal" \
    "$BEFORE" "$(cat "$RP" 2>/dev/null)"
  expect_status "AC-12 ($_case): …and still holds only the accepted dispatch's row" \
    "$BEFORE_N" "$(roster_rows "$RP")"
  expect_absent "AC-12 ($_case): the refused agent's name appears on no row" \
    "ghost-$_case" "$(cat "$RP" 2>/dev/null)"
done

# ---- a second dispatch claiming a path an open row already owns: WARN, never block ----
REPO=$(make_repo r17b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "first-owner")"
expect_status "AC-12: the first claim on a path passes silently" "0" "$GATE_ST"
expect_absent "AC-12: …with no contention warning, since nothing else owns it" \
  "already" "$GATE_ERR"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "second-owner")"
expect_status "AC-12: a second dispatch claiming the same deliverable is NOT blocked" "0" "$GATE_ST"
expect_contains "AC-12: …it draws a warning" "already" "$GATE_ERR"
expect_contains "AC-12: …that names the OWNING row" "first-owner" "$GATE_ERR"
expect_contains "AC-12: …and the contested path" ".bionic/docs/record/w99-widget.txt" "$GATE_ERR"
expect_status "AC-12: …and the second row is journalled all the same" "2" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# a DIFFERENT path in the same session is not contention
REPO=$(make_repo r17c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "owner-a")"
BRIEF_OTHER_PATH='Your task: build the other widget.
Expected artifact: .bionic/docs/record/w99-other.txt
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-other.progress
Suites: tests/widget.test.sh'
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_OTHER_PATH" "owner-b")"
expect_status "AC-12 paired negative: a distinct deliverable draws no contention warning" "0" "$GATE_ST"
expect_absent "AC-12 paired negative: …and says nothing about an owner" "already" "$GATE_ERR"

section "S18 — EXACTLY ONE path under the deliverable label (R7: R6 critic R6-1/R6-2/R6-3/R6-4)"
#
# R1 withdrew prose inference but kept a guess inside the label: it read the FIRST
# SENTENCE of the label span and took the FIRST path-shaped token in it. The R6 critic
# showed that is F-RD wearing a declaration's clothes — "same shape as A, written to B"
# contracted A, recorded `source=declared`, and the landing gate then ordered the agent
# to write A (an existing report it was told to READ). Worse than pre-R1, where the
# over-broad span at least CONTAINED the real deliverable.
#
# THE RULE (plan assumption 71, faithful completion of 48s never guess — declare or
# refuse): the deliverable labels span must yield EXACTLY ONE path. Zero refuses (name
# one); more than one REFUSES, naming every candidate, because choosing among them is
# the guess. No position heuristic, no reading-verb whitelist, no first-wins.
#
# Because ambiguity is now fatal rather than resolved, the search window WIDENS back to
# the whole span — which retires the false-block R1s first-sentence bound introduced
# (a path in the labels second sentence was invisible, and the refusal told the author
# to name a path they had already named).

# ---- R6-1 CASE 9: two paths in one deliverable sentence -> REFUSE, both named ----
BRIEF_TWO_PATHS_SHAPE='You are reviewing the wave.

Expected artifact: same shape as .bionic/docs/record/w2-critic-report.md, written to .bionic/docs/record/w2-probe-frd.md
Expected duration: 30 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_PATHS_SHAPE" "shapebot")"
# T26 (critic Issue 3): this brief used to trip TWO brief-shape arms — the ambiguity arm
# and the absent-deliverable arm, since C_DELIVERABLE stays empty either way — which
# printed "this brief names no deliverable" beside "the deliverable label names several
# paths", a straight contradiction (the several-fault deny wire). The absent-deliverable
# arm now recognises a non-empty candidate list as ANOTHER arm's product and stays quiet
# (`not checked: deliverable`) rather than repeating a false "nothing was declared". A
# `Suites:`-carrying brief with candidates is therefore back to exactly ONE fault, which
# keeps its own arm's verbatim detail — the shape wave-13 gave every lone fault. Since
# wave-19 T4 (REQ-7, D8) that detail rides the same deny wire the pooled list rides.
expect_eq "R6-1 CASE 9: a deliverable span naming two paths is REFUSED, never resolved" \
  "deny" "$GATE_VERDICT"
expect_contains "R6-1 CASE 9: …and asks for exactly one" "exactly one" "$GATE_ERR"
expect_status "R6-1 CASE 9: …and no roster row contracts the agent to either" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- R6-1 CASE 10: the read-then-produce ordering, the F-RD harm verbatim ----
BRIEF_TWO_PATHS_READ='Your task: an independent read-and-duplication review.
Deliverable: read .bionic/docs/record/w2-auditor-report.md first, then produce .bionic/docs/record/w2-probe-frd2.md
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r18b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_PATHS_READ" "readproducebot")"
# T26 (critic Issue 3): as CASE 9 above — one fault, not two, once the absent-deliverable
# arm stops repeating the ambiguity arm's own refusal — so this is the single-fault shape,
# not a pooled list (since wave-19 T4 one fault is a deny verdict too, its own detail on the reason).
expect_eq "R6-1 CASE 10: read-X-then-produce-Y is REFUSED, not contracted to X" \
  "deny" "$GATE_VERDICT"
expect_status "R6-1 CASE 10: …and no row is written for either" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- the refusal DIAGNOSES ambiguity, and is not the absent-deliverable message ----
expect_absent "the ambiguity refusal is not misfiled as an absent deliverable" \
  "names no deliverable" "$GATE_ERR$GATE_REASON"

# ---- THE RESUBMISSION: CASE 9 with one path in the label and the reference moved out ----
BRIEF_TWO_PATHS_FIXED='You are reviewing the wave.

Read first: .bionic/docs/record/w2-critic-report.md — match its shape.
Expected artifact: .bionic/docs/record/w2-probe-frd.md
Expected duration: 30 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_PATHS_FIXED" "shapebot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the resubmission — one path in the label, the reference outside it — passes" \
  "0" "$GATE_ST"
expect_status "…contracted to the artifact the brief actually asked for" \
  ".bionic/docs/record/w2-probe-frd.md" "$(roster_field "$ROW" deliverable)"
expect_status "…marked declared" "declared" "$(roster_field "$ROW" source)"

# ---- R6-4 CASE 5: a path in the labels SECOND sentence is declared, not absent ----
#
# R1 bounded the search at the end of the first sentence, so this brief — which names a
# concrete path under a canonical label — was refused for naming none, and the message
# told the author to do what they had already done. With ambiguity fatal, the window can
# safely be the whole span.
BRIEF_LATE_PATH='Your task: assess the wave.
Expected artifact: a written report. Put it at .bionic/docs/record/w2-probe-late.md when done.
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r18d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LATE_PATH" "latepathbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "R6-4 CASE 5: a path in the labels second sentence PASSES (no first-sentence bound)" \
  "0" "$GATE_ST"
expect_status "R6-4 CASE 5: …and is the contract" \
  ".bionic/docs/record/w2-probe-late.md" "$(roster_field "$ROW" deliverable)"
expect_status "R6-4 CASE 5: …recorded declared, because a label yielded it" \
  "declared" "$(roster_field "$ROW" source)"

# ---- paired positive: one path plus surrounding prose in the span still passes ----
BRIEF_ONE_PATH_PROSE='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-prose.md — the behavior table, the evidence,
and the judgment calls, written as prose rather than a log. Keep it short.
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_PATH_PROSE" "prosebot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "paired positive: a one-path span wrapped in prose passes" "0" "$GATE_ST"
expect_status "paired positive: …with that path as the contract" \
  ".bionic/docs/record/w99-prose.md" "$(roster_field "$ROW" deliverable)"

# ---- the same path named twice is ONE path, not an ambiguity ----
BRIEF_SAME_TWICE='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-twice.md — append to .bionic/docs/record/w99-twice.md as you go.
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_SAME_TWICE" "twicebot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "one path named twice is not an ambiguity" "0" "$GATE_ST"
expect_status "…and lifts once" \
  ".bionic/docs/record/w99-twice.md" "$(roster_field "$ROW" deliverable)"

# ---- a WAIVER does not excuse an ambiguous declaration (R7 judgment call) ----
#
# The waiver excuses declaring NOTHING durable. A brief that declares a label naming two
# artifacts has not waived anything — it has written a contract the machine cannot read,
# and the author is the only one who can say which path is theirs.
BRIEF_AMBIG_WAIVED='Your task: review the wave.
Deliverable-waiver: this dispatch returns its findings in the final message.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r18g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_AMBIG_WAIVED" "waivedambig")"
expect_eq "a waiver does not excuse an ambiguous deliverable label" "deny" "$GATE_VERDICT"
expect_contains "…and the refusal still names both candidates" "a-notes.md" "$GATE_VERR"

# ---- S18b: the deliverable span ends at the next LABELLED LINE, not at the next
# registered label (wave-bionic-1.3.2, found at dispatch) ----
#
# A span used to run on until the next label THIS WALL KNOWS or a blank line, so a brief
# that put `Evidence log: <path>` on the line after `Expected artifact: <path>` had two
# paths in one deliverable span and was refused as ambiguous — for a brief whose author had
# named exactly one deliverable and one input, each on its own labelled line. `Evidence
# log:` is not in the label table and does not need to be: any line that OPENS with a short
# `<Word>:` head is a new field, and a field ends where the next one begins. Two paths on
# the deliverable label OWN line are still the ambiguity the wall exists to refuse.
BRIEF_EVIDENCE_LOG='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-evlog.md
Evidence log: .bionic/docs/record/w99-evlog.log
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18evlog yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_EVIDENCE_LOG" "evlogbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S18b Evidence log: on the NEXT line does not make the deliverable ambiguous" \
  "0" "$GATE_ST"
expect_status "S18b …and the deliverable is the one on the label own line" \
  ".bionic/docs/record/w99-evlog.md" "$(roster_field "$ROW" deliverable)"

# The same brief with the two paths on ONE line is still refused: the fix bounds the span,
# it does not stop the wall counting.
BRIEF_TWO_ON_ONE_LINE='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-two.md .bionic/docs/record/w99-two.log
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18twoline yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_ON_ONE_LINE" "twolinebot")"
# T26 (critic Issue 3): as C-2/R6-1 above — one fault; a deny verdict since wave-19 T4.
expect_eq "S18b two paths on the deliverable label OWN line are still REFUSED" \
  "deny" "$GATE_VERDICT"

# A prose continuation line (no label head) still belongs to the span — the R6-4 window
# stays open, so a path named in a later sentence is still found.
BRIEF_PROSE_CONT='Your task: assess the wave.
Expected artifact: a written report.
Put it at .bionic/docs/record/w99-cont.md when you are done.
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r18prosecont yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CONT" "contbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S18b a prose continuation line is still inside the span" "0" "$GATE_ST"
expect_status "S18b …and its path is the contract" \
  ".bionic/docs/record/w99-cont.md" "$(roster_field "$ROW" deliverable)"

# ---- R6-2: every refusal message recommends a brief the walls ACCEPT ----
#
# The containment refusal handed the author `Expected artifact: .bionic/docs/record/<name>.md`
# — the literal string tests/cross-gate-agreement.test.sh §N.4 pins as REFUSED, and which
# the SIBLING refusal (the absent-deliverable wall) explicitly calls out as not a name.
# Two refusal messages in one file in direct contradiction, green the whole time because
# no test read a Fix: line. This pin reads each walls own recommendation back out of its
# stderr and DRIVES IT: an author who follows the Fix: line verbatim must not be refused.
# It never hardcodes the example, so it holds when the wording is next edited.
#
# TWO SHAPES, since T2 (D3, D11). A single-fault refusal (containment, absent, ambiguous) still
# carries the OLD indented Fix: block, unchanged — on the deny reason since wave-19 T4. A several-fault refusal (`deny`: ambiguous,
# combined) now carries the MARKED SCAFFOLD instead — its own `Expected artifact:` line is a
# placeholder with an embedded `e.g. …` example, not a recommendation typed for this brief, so
# the nested `<wave>`/`<name>` placeholders are filled the same way §scaffold-verbatim's own
# `scaffold_fill()` fills them, and any trailing ` <ADD>` this brief earned is stripped.
fix_example() {  # <stderr-or-reason> -> the artifact path the wall's own text recommends
  local line ex
  line=$(printf '%s\n' "$1" | grep -m1 -E '^[[:space:]]+Expected artifact: ')
  if [ -n "$line" ]; then
    printf '%s\n' "$line" | sed -e 's/^[[:space:]]*Expected artifact: //' -e 's/[[:space:]]*$//'
    return
  fi
  line=$(printf '%s\n' "$1" | grep -m1 -E '^Expected artifact: ')
  [ -n "$line" ] || return 0
  ex=$(printf '%s\n' "$line" \
    | sed -e 's/^Expected artifact: .*e\.g\. //' -e 's/>[[:space:]]*<ADD>[[:space:]]*$//' -e 's/>[[:space:]]*$//')
  ex="${ex//<wave>/w99}"
  ex="${ex//<name>/scaffold-note}"
  printf '%s\n' "$ex"
}

BRIEF_OUT_OF_REPO='Your task: build it.
Expected artifact: ../../../../../../etc/hosts
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh'

# THE THREE-FAULT BRIEF (wave-12 T2, spec D3, AC-1.1/AC-1.2). One brief that trips three
# brief-shape arms at once: the deliverable label offers two candidates (A11), which leaves
# `deliverable=` empty with no waiver behind it (A13), and no instrument is declared at all
# (A14). It is the shape Chris met on 2026-09-13 — six dispatches to spawn one researcher,
# because the gate exited at the first fault every time — and the §combined section below
# reads the whole refusal. It is defined HERE because the self-consistency loop below is the
# first thing that drives it.
BRIEF_THREE_FAULTS='Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes'

for _wall in containment absent ambiguous combined; do
  # EVERY BRIEF REFUSES WITH A DENY VERDICT (wave-19 T4, REQ-7, D8; before it, wave-12 T17
  # sent a ONE-fault brief to exit2). What still differs by fault count is the reason's
  # SHAPE: one fault carries its arm's own detail and indented Fix: block, several carry
  # the fault lines and the marked scaffold — and `fix_example` reads either. "ambiguous" is one fault now (T26, critic
  # Issue 3): its candidates leave `deliverable=` empty, and the absent-deliverable arm
  # recognises that as the ambiguity arm's own product rather than repeating the fault —
  # `BRIEF_THREE_FAULTS` still carries the extra "no Files:/no Suites:" fault beside it.
  case "$_wall" in
    containment) _b="$BRIEF_OUT_OF_REPO";    _want=deny ;;
    absent)      _b="$BRIEF_NOTHING";        _want=deny ;;
    ambiguous)   _b="$BRIEF_TWO_PATHS_SHAPE"; _want=deny ;;
    combined)    _b="$BRIEF_THREE_FAULTS";    _want=deny ;;
  esac
  REPO=$(make_repo "r18h-$_wall" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$_b" "fixline-$_wall")"
  # AND EACH WALL IS READ WHERE ITS REFUSAL ACTUALLY LANDS: `permissionDecisionReason`, the
  # model's own wire, with no knob set (the exit2 arm of this case is kept for a wall that
  # ever leaves on the environment wire). An author, or a model, only ever gets to follow a Fix: line it can see.
  case "$_want" in
    deny) _src="$GATE_REASON" ;;
    *)    _src="$GATE_VERR" ;;
  esac
  expect_eq "self-consistency ($_wall): the wall refuses" "$_want" "$GATE_VERDICT"
  _ex=$(fix_example "$_src")
  expect_status "self-consistency ($_wall): its Fix: block recommends a labeled example" "0" \
    "$([ -n "$_ex" ] && echo 0 || echo 1)"
  expect_absent "self-consistency ($_wall): …carrying no slot the walls themselves refuse" \
    "<" "$_ex"
  REPO=$(make_repo "r18i-$_wall" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: do the work.
Expected artifact: $_ex
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "followed-$_wall")"
  expect_status "self-consistency ($_wall): a brief following that Fix: line verbatim PASSES" \
    "0" "$GATE_ST"
  expect_status "self-consistency ($_wall): …and the recommended path is what lands on the row" \
    "$_ex" "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"
done

# ---- R6-3: a parenthetical duration lifts readable, not truncated mid-phrase ----
#
# bound_field ended a value at `)` but not `(`, so a balanced parenthetical truncated with
# a dangling open bracket — `~45 minutes (phase 1 only` — which the poker's parse_seconds
# refuses (two numbers, one matched unit pair). An unreadable duration silently exempts the
# row from overdue notification, which is A-2 read from the writer side.
BRIEF_PAREN_DURATION='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-paren.md
Expected duration: ~45 minutes (phase 1 only), phase 2 is a separate dispatch.
Suites: tests/widget.test.sh'

REPO=$(make_repo r18j yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PAREN_DURATION" "parenbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "R6-3: a parenthetical duration lifts the clause before the bracket" \
  "~45 minutes" "$(roster_field "$ROW" duration)"
expect_absent "R6-3: …with no dangling open bracket for parse_seconds to choke on" \
  "(" "$(roster_field "$ROW" duration)"
expect_absent "R6-3: …and none of the parentheticals own numbers" \
  "phase" "$(roster_field "$ROW" duration)"

# ---- S18c: Files: then Suites: on ADJACENT LINES, no blank between — both read (T3,
# REQ-7 AC-7.2) ----
#
# B4's static analysis (research R2 step1-research-R2-refusal-detail.md) found the span
# rule already correct at HEAD: `spanend()`'s first bound is the next REGISTERED label's
# start (`:1579`), and `Suites:`/`Files:` are both registered with `bol=1` — so a `Files:`
# span has always stopped at the following `Suites:` line, with or without a blank line
# between them. What was missing was a PIN saying so, against the real hook, now that the
# scaffold and dispatch.md no longer teach "own paragraph"/"to the next blank line" (T9).
BRIEF_ADJACENT_LABELS='Your task: build the widget.
Expected artifact: .bionic/docs/record/w18c.md
Files: payload/scripts/lib/widget.sh
Suites: tests/widget.test.sh'

REPO=$(make_repo r18adj yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ADJACENT_LABELS" "adjacentbot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S18c a Files: line directly followed by a Suites: line is ADMITTED" \
  "0" "$GATE_ST"
expect_status "S18c …Files: reads only its own line" \
  "payload/scripts/lib/widget.sh" "$(roster_field "$ROW" files)"
expect_status "S18c …and Suites: reads its own line too, carried onto suites_allowed=" \
  "widget.test.sh" "$(roster_field "$ROW" suites_allowed)"

section "S19 — deliverable-kind labels are LINE-START ONLY (R8: final-audit A-1)"
#
# record/w2-r7-audit.md A-1: R7's ambiguity wall refuses when a deliverable SPAN
# holds two paths, but each of its three refusal messages quotes the same
# concrete, liftable example — "Expected artifact: .bionic/docs/record/
# my-task-notes.md" — and briefs in this repo quote wall text constantly. A
# brief that quotes that line in PROSE ahead of its real, later "Expected
# artifact:" line puts each label in its OWN span (one path apiece), so the
# ambiguity wall never sees two paths in one span; decl_deliverable() then
# takes the FIRST hit that yields any path and silently contracts the agent to
# a file it will never write, recorded source=declared as though a human named
# it — the one shape that routes around the ambiguity wall entirely.
#
# THE FIX: the same mechanism `deliverable-waiver` already uses (S-1) — a
# deliverable-kind label counts only at LINE START. A mid-line occurrence is
# prose, not a declaration, and must not even register as a hit.

# ---- the audit's own P2 specimen, verbatim ----
BRIEF_P2_BAIT='Your task: build the widget.
The wall told me to write: Expected artifact: .bionic/docs/record/my-task-notes.md
Expected artifact: .bionic/docs/record/w2-probe-real.md
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r19a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_P2_BAIT" "p2bot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "A-1: a quoted wall-message bait ahead of the real label passes" \
  "0" "$GATE_ST"
expect_status "A-1: …contracted to the REAL line-start label's path" \
  ".bionic/docs/record/w2-probe-real.md" "$(roster_field "$ROW" deliverable)"
expect_absent "A-1: …never to the mid-line quoted bait" \
  "my-task-notes.md" "$(roster_field "$ROW" deliverable)"
expect_status "A-1: …still recorded declared" "declared" "$(roster_field "$ROW" source)"

# ---- CONTROL: the bare `deliverable` label, same shape — proves the pin
# generalizes across the canonical variants, not just `expected artifact` ----
BRIEF_P2_BARE='Your task: review the wave.
It said: Deliverable: .bionic/docs/record/bait-bare.md is the example.
Deliverable: .bionic/docs/record/w2-real-bare.md
Expected duration: 20 minutes
Suites: tests/widget.test.sh'

REPO=$(make_repo r19b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_P2_BARE" "p2barebot")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "A-1 control (bare label): passes" "0" "$GATE_ST"
expect_status "A-1 control (bare label): contracted to the real line-start path" \
  ".bionic/docs/record/w2-real-bare.md" "$(roster_field "$ROW" deliverable)"
expect_absent "A-1 control (bare label): never to the mid-line bait" \
  "bait-bare.md" "$(roster_field "$ROW" deliverable)"

section "S20 — the agent-context channel: walls travel, the LEDGER does not (T6, D1)"
#
# hooks/agent-context-guard.sh registers this gate a second time, through
# settings.json, so a dispatch made from INSIDE a teammate or subagent context meets
# the same walls a main-thread one does — the skill channel is dead there
# (.bionic/docs/record/session-20260815-landing-supervision/t1-probe-report.md §3).
# What must not travel with the walls is the journal: the roster is the depth-one
# ledger of what the ORCHESTRATOR launched, and rows for a teammate's own subagents
# are contracts nobody confirms, lands or checks.
#
# The guard is the only writer of BIONIC_HOOK_CHANNEL and this is its only reader;
# tests/cross-gate-agreement.test.sh §L.6 pins the pair across the two files.
#
# BOTH DIRECTIONS, because a suppression that suppressed the WALL as well would look
# identical from the roster's side — and would be the R2 hole reopening in the act of
# closing it.
REPO=$(make_repo r20 yes)
write_attestation "$REPO" "$SID_A"
S20_SAVED_ENV="$GATE_ENV"
GATE_ENV="$GATE_ENV BIONIC_HOOK_CHANNEL=agent-context"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a contract-complete dispatch in an agent context passes" "0" "$GATE_ST"
expect_status "…and writes NO roster row (the ledger stays at depth one)" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# The wall itself is untouched by the channel — a deliverable-less brief is refused
# at depth, which is the entire point of the second registration.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Canonical-sdlc Step 4. Do the thing.
Exit condition: the suite is green.')"
# T17: this brief trips SEVERAL brief-shape arms, so its one refusal is a deny verdict
# on stdout with exit 0, not exit 2. The refusal itself — and every assertion below — is
# unchanged; only the channel the wall blocks on is.
expect_eq "a deliverable-less dispatch in an agent context is still REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…by the absent-deliverable wall, in its own words" \
  "bionic: dispatch refused — this brief names no deliverable" "$GATE_ERR"
GATE_ENV="$S20_SAVED_ENV"

# The paired positive: the same dispatch with no channel marker — the main thread, as
# the skill channel delivers it — still journals its row.
REPO=$(make_repo r20b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "the same dispatch on the main thread passes" "0" "$GATE_ST"
expect_status "…and DOES journal exactly one row" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# An unrelated value in the variable is not the channel: only the guard's exact
# spelling suppresses, so a stray export cannot silently stop the ledger.
S20_SAVED_ENV="$GATE_ENV"
GATE_ENV="$GATE_ENV BIONIC_HOOK_CHANNEL=something-else"
REPO=$(make_repo r20c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "an unrecognised channel value journals normally" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
GATE_ENV="$S20_SAVED_ENV"


section "S21: the arming wall — a dispatch needs a live Patrol (epic-17 W5 4/4, AC-6)"
#
# WHAT THIS WALL IS FOR. Every other wall on this path asks whether the dispatch is
# well-formed or the environment is sound. This one asks whether anything is WATCHING the
# fleet the dispatch is about to join. The Patrol is the run's one clock; when it is not
# armed, or was armed and has silently stopped firing, a launched agent can die quiet and
# nothing notices until a human wanders back. The stamp
# (.bionic/tmp/patrol-<sid>.state, written by hooks/session-poker.sh's `arm` and by every
# `tick` before it decides) is the liveness signal, and its AGE is the whole test:
# absent = never armed, older than 2x the poker-interval = armed-but-dead.
#
# SCOPE IS THE HOOK'S EXISTING ACTIVE-RUN PREDICATE, deliberately — no second definition of
# "active" (design ledger D-C mechanic 4). Outside a wave this gate has already exited long
# before reaching here, which the no-wave arm below drives directly.
#
# THE INTERVAL IS THE POKER'S OWN, read by invoking the sibling `interval` verb rather than
# by re-implementing the config knob. An interval this gate cannot read is an AMBIGUITY, not
# a finding, and takes §7's start-side direction: warn and pass.

s21_stamp_path() { printf '%s/.bionic/tmp/patrol-%s.state' "$1" "$2"; }

s21_backdate() {  # <file> <seconds ago>
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

# ---------- the transcript the staleness half reads (REQ-1, AC-1.1/1.2) ----------
#
# THE STALENESS HALF IS AN IDLE-TIME PREDICATE NOW (ADR-028). A session cron fires only
# while the session is idle, so a stamp past the fire window is a DEATH only when an idle
# gap at least that long has passed since it with no tick in it; a stamp that went stale
# under a long busy turn is an advisory and the dispatch proceeds. Every armed-but-dead
# fixture below therefore carries a transcript with a real gap, and the busy fixture carries
# one without. The suite's default transcript (`S5_LIVE_TRANSCRIPT`, fixed 2026-09-05
# timestamps) predates every stamp this section backdates, so it reads as BUSY and is the
# right default for every fixture here that is not about the staleness half at all.
#
# RELATIVE TO NOW, REBUILT AT EACH CALL: the gap has to fall after the stamp, and the stamp
# is backdated by between 50 and 4000 seconds. Nothing here sleeps.
s21_iso() {  # <seconds ago>
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

s21_idle_tr() {  # -> path of a transcript whose last turn opened after a long idle gap
  { printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
      "$(s21_iso 10000)"
    printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"carry on"}}\n' \
      "$(s21_iso 1)"
  } > "$SANDBOX/.s21-idle.jsonl"
  printf '%s' "$SANDBOX/.s21-idle.jsonl"
}

s21_busy_tr() {  # -> path of a transcript holding one continuous 2500s turn
  { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"a long piece of work"}}\n' \
      "$(s21_iso 2500)"
    for _s21_s in 2400 2100 1800 1500 1200 900 600 300 120 30 5; do
      printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
        "$(s21_iso "$_s21_s")"
    done
  } > "$SANDBOX/.s21-busy.jsonl"
  printf '%s' "$SANDBOX/.s21-busy.jsonl"
}

s21_stale_payload() {  # <sid> <repo> -> a dispatch payload carrying the idle transcript
  mk_agent_payload "$1" "$2" "$BRIEF_FULL" w99-impl claude-sonnet-5 "$(s21_idle_tr)"
}

# ---------- absent stamp: never armed ----------
REPO=$(make_repo r21a yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "an ABSENT Patrol stamp refuses the dispatch" "deny" "$GATE_VERDICT"
expect_contains "…in the checkpoint house style, not an alarm word" \
  "bionic: dispatch refused — no Patrol stamp exists for this session" "$GATE_ERR"
expect_contains "…naming the state it found" "never armed" "$GATE_VERR"
# REWORKED, NOT WEAKENED (wave-12 T2, spec D4). This arm used to demand the refusal name
# `session-poker.sh arm` as the second step of a two-step re-arm. hooks/engage.sh runs that
# command itself now, at engagement (T4) — so the refusal that still ordered it would be
# instructing the model to do the machine's work. What the never-armed arm must name is the
# half the model DOES own, and where the other half comes from; §a3-text drives both
# directions, and the STALE arm below still names the hand command it still needs.
expect_contains "…and naming engagement as what writes the stamp" "engage" "$GATE_VERR"
expect_contains "…and the CronCreate half, so the stamp is not re-armed into a dead clock" \
  "CronCreate" "$GATE_VERR"
expect_contains "…and says what to do after" "retry the dispatch" "$GATE_VERR"
expect_status "…and journals nothing: a refused dispatch is not a launch" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---------- stale stamp: armed, then died ----------
REPO=$(make_repo r21b yes)
write_attestation "$REPO" "$SID_A"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000   # past the 1320s fire window
run_gate "$(s21_stale_payload "$SID_A" "$REPO")"
expect_eq "a STALE Patrol stamp refuses the dispatch" "deny" "$GATE_VERDICT"
expect_contains "…and names the armed-but-dead state, not the never-armed one" \
  "stopped firing" "$GATE_ERR"
expect_absent "…so the two arms cannot be confused in a transcript" "never armed" "$GATE_ERR$GATE_REASON"

# ---------- stale stamp, busy session: an advisory, and the dispatch proceeds ----------
#
# AC-1.1, at the wall that blocks mid-turn by construction. The SAME 4000s stamp as r21b,
# and the only thing that differs is the transcript: one continuous turn with no idle gap
# in it, so the cron had no opportunity to fire and its silence proves nothing. This is the
# 2026-09-15 field case — a dispatch refused because the orchestrator was working.
REPO=$(make_repo r21b2 yes)
write_attestation "$REPO" "$SID_A"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" w99-impl claude-sonnet-5 "$(s21_busy_tr)")"
expect_status "a stale stamp under a BUSY session lets the dispatch through" "0" "$GATE_ST"
expect_absent "…and does not claim the Patrol stopped firing" "stopped firing" "$GATE_ERR"
expect_contains "…but says the stamp is stale and why that is not a verdict" \
  "busy" "$GATE_ERR"

# ---------- stale stamp, unreadable idle time: an advisory naming the reason ----------
#
# AC-1.3 at this wall. The transcript path in the payload names a file that is not there;
# a wall that cannot observe the thing it refuses on does not refuse.
REPO=$(make_repo r21b3 yes)
write_attestation "$REPO" "$SID_A"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" w99-impl claude-sonnet-5 "$SANDBOX/.s21-absent.jsonl")"
expect_status "a stale stamp whose idle time cannot be read lets the dispatch through" \
  "0" "$GATE_ST"
expect_contains "…naming the reason it could not measure" "no readable transcript" "$GATE_ERR"

# ---------- fresh stamp: passes, silently ----------
REPO=$(make_repo r21c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a FRESH Patrol stamp lets the dispatch through" "0" "$GATE_ST"
expect_absent "…and the wall says nothing on the pass path" "patrol checkpoint" "$GATE_ERR"
expect_status "…and the launch is journalled as usual" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---------- a stamp for ANOTHER session is not this session's liveness ----------
REPO=$(make_repo r21d yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "a stamp keyed to a DIFFERENT session does not arm this one" "deny" "$GATE_VERDICT"
expect_contains "…and reads as never-armed here" "never armed" "$GATE_VERR"

# ---------- the wall rides the active-run predicate and nothing else ----------
REPO=$(make_repo r21e no)
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "with NO wave active an unarmed Patrol is not this gate's business" "0" "$GATE_ST"
expect_empty "…and the gate is silent, as it is for every other check outside a wave" "$GATE_ERR"

# ---------- the threshold is ONE FIRE WINDOW, and follows the config knob ----------
#
# AMENDED at REQ-1 (T1). The threshold was 2x the poker-interval (120s for this fixture's
# 1m); it is the FIRE WINDOW now — the interval plus the scheduler's jitter, a tenth of the
# period, so 66s — and the two fixtures move with it. The assertion is the same one either
# side of the boundary: inside it the stamp is not stale at all, past it the transcript
# decides.
REPO=$(make_repo r21f yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 1m\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 50      # inside the 66s fire window
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a stamp inside the CONFIGURED fire window passes (50s of 66s)" "0" "$GATE_ST"

REPO=$(make_repo r21g yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 1m\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 200     # past the 66s fire window
run_gate "$(s21_stale_payload "$SID_A" "$REPO")"
expect_eq "…and one past it refuses, on the same fixture the default would have passed" \
  "deny" "$GATE_VERDICT"
expect_contains "…naming the fire window it measured against" "66s fire window" "$GATE_VERR"

# ---------- a symlinked stamp is refused, never followed ----------
REPO=$(make_repo r21h yes)
write_attestation "$REPO" "$SID_A"
printf 'patrol-stamp/v1|at=2099-01-01T00:00:00Z|session=%s|verb=arm\n' "$SID_A" \
  > "$SANDBOX/planted-stamp"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
ln -s "$SANDBOX/planted-stamp" "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "a SYMLINKED stamp cannot open this wall" "deny" "$GATE_VERDICT"

# ---------- an unreadable interval falls back to the poker's own default ----------
#
# CRITIC C-2 (W5). This used to skip BOTH arms of the wall and pass. `poker-interval:` is
# machine-local and agent-writable, so one line in a config file disabled an entire wall —
# in a file whose own §8 says a hostile repo may CLOSE a wall and must never be able to
# OPEN one. And the line that reaches it is the likeliest typo there is: a BARE NUMBER
# (`poker-interval: 30`) makes the poker refuse, where `30m` and `30 minutes` both parse.
#
# The interval is a THRESHOLD, not a precondition, and only one of the two arms needs it.
# So: the stamp-existence arm runs unconditionally (an absent stamp is absent at every
# interval), and the staleness arm falls back to the poker's own POKER_INTERVAL_DEFAULT —
# read from the poker, never retyped here, via its read-only `interval-default` verb. The
# dispatch still passes, because the operator's config really is unreadable and that is an
# ambiguity; what it no longer does is pass with nothing checked.
REPO=$(make_repo r21i yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: whenever\n' > "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "an interval the poker refuses to read does not refuse the dispatch" "0" "$GATE_ST"
expect_contains "…but says so, rather than passing a wall off as satisfied" \
  "Patrol interval" "$GATE_ERR"
expect_contains "…and says the wall RAN, at the default, rather than that it did not run" \
  "wall ran at default" "$GATE_ERR"

# r21j — THE MISSING COMBINATION, and the one that made C-2 a hole rather than a wording
# problem: the same unreadable interval with NO stamp at all. r21i above drives a FRESH
# stamp, so it can only ever show pass-stays-pass.
REPO=$(make_repo r21j yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 30\n' > "$REPO/.bionic/config.yaml"   # the bare-number typo: rc=2
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "an unreadable interval does NOT open the wall for an unarmed session" "deny" "$GATE_VERDICT"
expect_contains "…the never-armed arm still fires" "never armed" "$GATE_VERR"

# r21k — and the staleness arm runs too, measured against the fallback default.
REPO=$(make_repo r21k yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 30\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000   # past the 1320s default window
run_gate "$(s21_stale_payload "$SID_A" "$REPO")"
expect_eq "a stale stamp under an unreadable interval refuses at the DEFAULT threshold" \
  "deny" "$GATE_VERDICT"
expect_contains "…naming the armed-but-dead state" "stopped firing" "$GATE_ERR"

# r21l — the fallback is the POKER'S constant, not a number retyped in the gate. Proven
# by MUTATION: change POKER_INTERVAL_DEFAULT on a doctored copy of the poker tree and the
# threshold the gate measures against has to move with it. A gate carrying its own 1200
# would pass this fixture unchanged.
# A COPIED HOOK NEEDS THE LIBRARY BESIDE IT — the shape the plugin ships, `hooks/`
# beside `scripts/lib` (bionic 1.4.0). Both the gate and the poker load through the
# shared loader idiom, whose first candidate is `$(dirname "$0")/../scripts/lib`; a copy
# dropped into a bare temp directory finds none, fails open, and every arm below would be
# measuring the step-aside rather than the threshold. The library is LINKED rather than
# copied, so the tree under test reads exactly the functions the shipped scripts read —
# and linking the whole directory means a hook that later wants one more basename does not
# silently fall off the end of a hand-listed set.
s21_plant() {  # <tree root> -> plants hooks/ + scripts/lib and echoes the hooks dir
  local root="$1"
  mkdir -p "$root/hooks" "$root/scripts"
  ln -s "$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)" "$root/scripts/lib" 2>/dev/null \
    || ln -s "$(cd "${BIONIC_HOOKS_DIR}/../scripts/lib" && pwd -P)" "$root/scripts/lib" 2>/dev/null || true
  printf '%s' "$root/hooks"
}
S21_TREE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/s21-poker-tree.XXXXXX")
S21_TREE_HOOKS=$(s21_plant "$S21_TREE_ROOT")
S21_TREE="$S21_TREE_HOOKS"   # POKER's spelling; both names address one directory
cp "$GATE" "$S21_TREE_HOOKS/dispatch-preflight.sh"
sed 's/^POKER_INTERVAL_DEFAULT="20m"$/POKER_INTERVAL_DEFAULT="10s"/' \
  "${BIONIC_HOOKS_DIR}/session-poker.sh" > "$S21_TREE_HOOKS/session-poker.sh"
if grep -qF 'POKER_INTERVAL_DEFAULT="10s"' "$S21_TREE_HOOKS/session-poker.sh"; then
  ok "r21l meta: the doctored poker default landed (the sed anchor still matches)"
else
  no "r21l meta: the doctored poker default did NOT land — the arm below proves nothing"
fi
REPO=$(make_repo r21l yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 30\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 100   # fresh at 1200s, ancient at 10s
S21_SAVED_GATE="$GATE"; GATE="$S21_TREE_HOOKS/dispatch-preflight.sh"
run_gate "$(s21_stale_payload "$SID_A" "$REPO")"
expect_eq "r21l the fallback threshold moves with the POKER's constant, not the gate's" \
  "deny" "$GATE_VERDICT"
# AMENDED at REQ-1 (T1): the threshold is the fire window, so the doctored 10s default is
# measured against as 11s rather than as 2x10s. The fact under test is unchanged — the
# number moves with the POKER's constant and not with one typed in the gate.
expect_contains "…and measures against the doctored default's own fire window" \
  "11s fire window" "$GATE_VERR"
GATE="$S21_SAVED_GATE"

# r21m — THE POKER ITSELF UNREACHABLE. `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/` is the
# gate's second lane for its siblings, and after the Step-9 legacy teardown that directory
# no longer holds hooks on any machine — so on a plugin-only install the only lane that
# resolves is the sibling one. If BOTH miss, there is no interval and no default to be had,
# and the honest degradation is per-arm: the existence half needs no threshold and still
# refuses, and the staleness half says out loud that it did not run. What must never happen
# is the whole wall going quiet, which is what a teardown would otherwise have bought.
S21_LONE=$(mktemp -d "${TMPDIR:-/tmp}/s21-lone-gate.XXXXXX")
S21_LONE_HOOKS=$(s21_plant "$S21_LONE")
cp "$GATE" "$S21_LONE_HOOKS/dispatch-preflight.sh"
S21_EMPTY_CONFIG=$(mktemp -d "${TMPDIR:-/tmp}/s21-empty-config.XXXXXX")
REPO=$(make_repo r21m yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
S21_SAVED_GATE="$GATE"; S21_SAVED_CONFIG="$GATE_CONFIG_DIR"
GATE="$S21_LONE_HOOKS/dispatch-preflight.sh"; GATE_CONFIG_DIR="$S21_EMPTY_CONFIG"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r21m with NO poker on either lane, the unarmed session is still refused" \
  "deny" "$GATE_VERDICT"
expect_contains "…by the existence arm, which never needed the interval" "never armed" "$GATE_VERR"

# …and the staleness half, which genuinely cannot run, says so instead of passing quietly.
REPO=$(make_repo r21n yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r21n …and a stamped session passes, the staleness half unmeasured" "0" "$GATE_ST"
expect_contains "…saying which half did not run, and why" \
  "staleness half" "$GATE_ERR"
GATE="$S21_SAVED_GATE"; GATE_CONFIG_DIR="$S21_SAVED_CONFIG"

# ================================================== S22: THE PARALLEL-BUDGET ARM
# (spec AC-26; plan task WALLS; assumptions WALLS/2, WALLS/3, WALLS/4.)
#
# The active plan's frontmatter may carry ONE budget string —
# `parallel-budget: writers=N suites=N worktrees=N test_jobs=N source=…` — written at
# Step 0 from the resources probe and byte-identical to the attestation's `budget=`
# value (L-RESOURCES/2). With that line present the gate refuses a dispatch that would
# push any of the three counted resources past its ceiling; WITHOUT it the gate is
# inert, which is what keeps every plan written before this wave dispatching normally.
#
# The three counts and where each comes from:
#   writers   — OPEN roster rows for this session (a `status=intended` row whose name
#               carries no `landing-swept/v1` marker). Same predicate lib/patrol.sh's
#               patrol_roster_state uses for its own `open=`, and r22g pins the two
#               against each other on one fixture so the wall and the Patrol can never
#               disagree about how many writers are out.
#   suites    — those same open rows carrying a non-empty `claims=` (the subprocess
#               claim a suite-running brief declares).
#   worktrees — live linked trees under `<project root>/.worktrees` — a directory whose
#               `.git` is a FILE, which is exactly how scripts/lib/worktree.sh tells a
#               linked worktree from the main checkout.
# Each arm adds 1 for the dispatch about to happen, per the plan's literal text.

# s22_set_budget <repo> <budget value> — insert `parallel-budget:` into the plan's
# leading frontmatter block (the plan fixture's first line is the opening `---`).
s22_set_budget() {
  local plan="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" val="$2"
  awk -v v="$val" 'NR == 1 && $0 == "---" { print; print "parallel-budget: " v; next } { print }' \
    "$plan" > "$plan.tmp" && mv "$plan.tmp" "$plan"
}

# s22_roster_row <repo> <sid> <name> [claims] — one launch row in the shipped schema.
s22_roster_row() {
  local f; f="$(roster_path "$1" "$2")"
  mkdir -p "$(dirname "$f")"
  # No `plan=`: these rows are counted by the budget arm, which reads `status=` and
  # `claims=` and nothing else, and `roster_row_no_plan` is the shape this fixture has
  # always had (tests/lib/roster-row.sh, S14).
  roster_row_no_plan status=intended "session=$2" "name=$3" agent_id= \
    launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
    "deliverable=/tmp/d-$3" source=declared "duration=~10 minutes" progress= \
    "claims=${4:-}" cadence= absent= waiver= "tool_use_id=t-$3" >> "$f"
}

# s22_sweep <repo> <sid> <name> — the landing marker that closes a row.
# THROUGH THE ONE WRITER (S17, spec AC-26): `swept_marker_write` is
# hooks/landing-gate.sh's own function, extracted by tests/lib/swept-marker.sh and called
# for real. The printf that used to sit here wrote a marker the originator would not
# recognise — no `session=`, no `agent_id=` — and stayed green because every reader of the
# marker is by key.
s22_sweep() {
  swept_marker_write "$(roster_path "$1" "$2")" 2026-09-02T00:00:00Z "$2" "$3" "" MET
}

# s22_ack <repo> <sid> <name> [at] — one `event=ack` line on the sweeper's OWN ledger,
# `.bionic/tmp/sweeper-<sid>.state`, which is where `session-sweeper.sh ack` journals the
# orchestrator's judgement that a row is closed (that verb's write, :1020). The SCHEMA is
# read out of the writer rather than transcribed here — §S15b's idiom for `SWEPT_SCHEMA`,
# and for the same reason: a prefix that drifted would leave this fixture writing lines no
# reader believes, silently and greenly. `at` defaults to a moment AFTER the launch stamp
# `s22_roster_row` writes (2026-09-02T00:00:00Z), because an ack only closes a row it
# postdates.
S22_LEDGER_SCHEMA="$(/usr/bin/grep -m1 '^LEDGER_SCHEMA=' "${BIONIC_HOOKS_DIR}/session-sweeper.sh" | cut -d'"' -f2)"
s22_ack() {
  local f="$1/.bionic/tmp/sweeper-$2.state"
  mkdir -p "$(dirname "$f")"
  printf '%s|event=ack|at=%s|epoch=1756771200|pid=%s|session=%s|name=%s|by=human\n' \
    "$S22_LEDGER_SCHEMA" "${4:-2026-09-03T00:00:00Z}" "$$" "$2" "$3" >> "$f"
}

# s22_fake_tree <repo> <dir> — a linked worktree's on-disk signature: a `.git` FILE.
s22_fake_tree() {
  mkdir -p "$1/.worktrees/$2"
  printf 'gitdir: %s/.git/worktrees/%s\n' "$1" "$2" > "$1/.worktrees/$2/.git"
}

section "S22: the parallel-budget arm"

# --- writers: at the ceiling, refuse; one under it, pass.
REPO=$(make_repo r22a yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22a two open rows against writers=2 → the third dispatch is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the budget line verbatim" \
  "writers=2 suites=9 worktrees=9 test_jobs=4 source=probe" "$GATE_VERR"
expect_contains "…and the count that broke it" "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_contains "…naming the plan the budget came from" "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" "$GATE_ERR"

REPO=$(make_repo r22b yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22b one open row against writers=2 → the second dispatch passes" "0" "$GATE_ST"
expect_absent "…and says nothing about a budget on the pass path" "parallel budget" "$GATE_ERR"

# --- unmeasured without the line, and SAID (epic-23 wave-20 T2, REQ-10 AC-10.2, D10;
#     ADR-035). The same roster that refused above still dispatches when the plan declares
#     no budget — the ceilings cannot be measured, so nothing is refused on them — but a
#     LIVE plan (past Step 3) without the key is a plan that slipped past the governing-skill
#     hook's Write wall, and this wall names the key rather than passing it in silence. Until
#     this wave it was silent here: "inert without the line" was the rule of a budget a run
#     OPTED INTO, and ADR-035 made the budget a measurement every plan carries.
REPO=$(make_repo r22c yes)
write_attestation "$REPO" "$SID_A"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
s22_roster_row "$REPO" "$SID_A" "W-THREE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22c no parallel-budget: in a live plan → no ceiling refuses, three rows notwithstanding" "0" "$GATE_ST"
expect_absent "…and no ceiling count is printed" "writers: budget=" "$GATE_ERR"
expect_contains "r22c2 …but the missing key is NAMED on the pass path (AC-10.2)" \
  "no parallel-budget: line with a writers= field" "$GATE_ERR"
expect_contains "r22c2 …citing the decision that makes the budget a measurement" "ADR-035" "$GATE_ERR"
expect_contains "r22c2 …and naming the plan it read" \
  "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" "$GATE_ERR"

# r22c3 — A KEY SPELLED ANY OTHER WAY IS NO KEY. A leading space before `parallel-budget:`
# is the spelling the stop wall used to read as 3 and the tick, preflight and the hook read
# as nothing; one strict reader now answers "no line" for all four, so it gets the same
# named backstop as an absent key.
REPO=$(make_repo r22c3 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
sed -i '' 's/^parallel-budget: /  parallel-budget: /' "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
expect_contains "r22c3 meta: the plan carries the indented key" "  parallel-budget: writers=1" \
  "$(cat "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22c3 an indented key reads as no key: nothing is refused on writers=1" "0" "$GATE_ST"
expect_contains "r22c3 …and the key is named as missing" "no parallel-budget: line with a writers= field" "$GATE_ERR"

# r22c4 — BELOW STEP 4 NOTHING IS OWED. A plan at `current: 3` is still being written, so a
# missing key there is not a live run's gap and nothing is said (the stop wall's backstop
# takes the same boundary: fill_ledger_live, past Step 3).
REPO=$(make_repo r22c4 yes)
write_attestation "$REPO" "$SID_A"
sed -i '' 's/^current: 4$/current: 3/' "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22c4 a keyless plan at current: 3 dispatches" "0" "$GATE_ST"
expect_absent "r22c4 …and nothing is said about the key" "no parallel-budget: line" "$GATE_ERR"

# r22c5 — THE PAIRED CONTROL: a keyed plan at current: 4 says nothing about a missing key.
# Without it r22c2 is green on a wall that prints the line on every dispatch.
REPO=$(make_repo r22c5 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22c5 a keyed live plan dispatches" "0" "$GATE_ST"
expect_absent "r22c5 …and names no missing key" "no parallel-budget: line" "$GATE_ERR"

# r22c6 — max_writers IS NOT writers. The field is read whole: `max_writers=9 writers=1`
# carries a ceiling of ONE, so one open row refuses the second dispatch (the 9-vs-3 defect,
# triage-D, at this wall's own numbers).
REPO=$(make_repo r22c6 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "max_writers=9 writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22c6 max_writers=9 writers=1 with one open row → REFUSED on writers=1" "deny" "$GATE_VERDICT"
expect_contains "…naming the whole-field reading" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# --- a row absent from the fresh live set is not an open one (AC-7; the
#     anti-vacuity control: the same fixture refuses while the row is live).
#     `landing-swept` is no longer consulted at all — the row's own PRESENCE in
#     THIS TURN's ListAgents answer is the only thing that opens or closes it.
REPO=$(make_repo r22d yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22d one LIVE row against writers=1 → refused (the control)" "deny" "$GATE_VERDICT"
R22D_ABSENT="$SANDBOX/.r22d-absent.jsonl"
mk_transcript "$R22D_ABSENT" fresh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22D_ABSENT")"
expect_status "…and the same row, absent from a fresh answer, no longer counts → passes" \
  "0" "$GATE_ST"

# --- suites: an open row carrying a subprocess claim.
REPO=$(make_repo r22e yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=1 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE" "bash tests/run.sh"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22e one claimed suite against suites=1 → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the suite count" "suites: budget=1 claimed=1 with-this-dispatch=2" "$GATE_VERR"

REPO=$(make_repo r22f yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=1 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22f the same row with NO claim does not spend a suite → passes" "0" "$GATE_ST"

# --- worktrees: live linked trees on disk.
REPO=$(make_repo r22h yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=1 test_jobs=4 source=probe"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22h worktrees=1 with no tree standing → passes (the control)" "0" "$GATE_ST"
# A DISTINCT NAME, because the control above was ALLOWED and journalled `w99-impl` on this
# repo's roster (wave-14 REQ-8). Re-using it would put the name-in-flight arm's fault beside
# the worktree ceiling's, and since the arms pool now that is one refusal naming two
# things — a true answer to a question this section is not asking.
s22_fake_tree "$REPO" "one"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl-b")"
expect_eq "…one live tree against worktrees=1 → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the tree count" "worktrees: budget=1 live=1 with-this-dispatch=2" "$GATE_VERR"
# A plain directory under .worktrees is not a leased tree — only a linked one is.
REPO=$(make_repo r22i yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=1 test_jobs=4 source=probe"
mkdir -p "$REPO/.worktrees/not-a-tree"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r22i a bare directory under .worktrees is not a lease → passes" "0" "$GATE_ST"

# --- r22g: the wall and the Patrol count the same open rows on THIS fixture. AC-7
#     retires `landing-swept` as the wall's own signal — W-FOUR is left off the fresh
#     transcript instead — but lib/patrol.sh's `patrol_roster_state` is untouched by
#     this task and still reads the swept marker, so both are kept: one closes
#     W-FOUR for the Patrol's own count, the other closes it for the wall's.
REPO=$(make_repo r22g yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=3 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
s22_roster_row "$REPO" "$SID_A" "W-THREE"
s22_roster_row "$REPO" "$SID_A" "W-FOUR"
s22_sweep "$REPO" "$SID_A" "W-FOUR"
R22G_TRANSCRIPT="$SANDBOX/.r22g-live.jsonl"
mk_transcript "$R22G_TRANSCRIPT" fresh W-ONE W-TWO W-THREE
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22G_TRANSCRIPT")"
expect_eq "r22g three live rows and one absent, against writers=3 → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…the wall counts three open" "writers: budget=3 open=3 with-this-dispatch=4" "$GATE_VERR"
# shellcheck source=/dev/null
( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/patrol.sh" 2>/dev/null \
  && patrol_roster_state "$REPO" "$SID_A" ) > "$SANDBOX/.r22g" 2>/dev/null
expect_contains "…and so does lib/patrol.sh's patrol_roster_state, on the same file" \
  "open=3" "$(cat "$SANDBOX/.r22g")"

# ================================== S22b: LIVE-AGENTS FRESHNESS GATES THE COUNT
# (spec AC-7, AC-8; task S5.)
#
# The predicate itself, isolated from every other S22 arm: one `status=intended` row,
# writers budget tight enough that whether it counts open decides pass vs refuse.

section "S22b: the budget count is read off the fresh live set"

# (a) the row's agent is ABSENT from a FRESH answer -> open=0, and the dispatch that
# would have been the SECOND writer (budget=1, one row not counted) is allowed.
REPO=$(make_repo r22ja yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
R22JA_T="$SANDBOX/.r22ja.jsonl"
mk_transcript "$R22JA_T" fresh W-OTHER
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22JA_T")"
expect_status "r22ja r1 absent from a fresh answer -> open=0, dispatch allowed at budget=1" \
  "0" "$GATE_ST"
expect_absent "…and no budget refusal, live-agents or otherwise" "BLOCKED" "$GATE_ERR"
expect_absent "…specifically no writers count printed" "writers:" "$GATE_ERR"

# (b) the SAME roster, repo and budget; only the answer changes to name r1 itself ->
# open=1, and the same dispatch is now the second writer against a budget of one.
REPO=$(make_repo r22jb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
R22JB_T="$SANDBOX/.r22jb.jsonl"
mk_transcript "$R22JB_T" fresh r1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22JB_T")"
expect_eq "r22jb r1 present in the fresh answer -> open=1, REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the count" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# ======================== S22b-nla: A LISTAGENTS ANSWER IS NOT A PRECONDITION
# (wave-12 T1; spec D1 and principle P-A; Chris 2026-09-13 "What the hell. I don't want
# this to happen to begin with!" — AC-4.1, AC-4.2.)
#
# WHAT MOVED. Until 1.7.0 a transcript carrying no fresh ListAgents answer refused the
# WHOLE dispatch and told the orchestrator to go call the tool first. That is a chore on
# the normal path, and it asks for a fact the machine already holds: the roster. N deduped
# `status=intended` rows ARE N open writers until some reading says otherwise, so the
# count falls back to the roster and the dispatch is JUDGED rather than deferred.
#
# THE DISCRIMINATOR IS THE CEILING, NOT THE EXIT CODE. Each pair below holds the repo, the
# roster and the transcript fixed and moves ONLY the writers ceiling across N+1. A rule
# that counted 0 would pass both halves; a rule that still refused on freshness would fail
# both; only a rule that counts exactly N passes one and refuses the other.

section "S22b-nla: with no ListAgents answer the count is the open roster rows"

# (a) N=2 rows, NO answer in the transcript at all, ceiling 3 -> 2+1 = 3 fits: ALLOWED.
REPO=$(make_repo r22nla yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=3 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
R22NLA_NONE="$SANDBOX/.r22nla-none.jsonl"
mk_transcript "$R22NLA_NONE" none
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLA_NONE")"
expect_status "r22nla 2 open rows, no answer, ceiling 3 -> judged against 2, ALLOWED" \
  "0" "$GATE_ST"
expect_absent "…and nothing is said about a missing live-agents answer" \
  "live-agents:" "$GATE_ERR"
expect_absent "…and no tool call is demanded of the dispatcher" \
  "call ListAgents" "$GATE_ERR"

# (b) THE SAME two rows and the same empty transcript; only the ceiling moves to 2 ->
# 2+1 = 3 passes it: REFUSED, and the count it names is the roster's own N.
REPO=$(make_repo r22nlb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLA_NONE")"
expect_eq "r22nlb the same two rows against a ceiling of 2 -> REFUSED on the BUDGET" \
  "deny" "$GATE_VERDICT"
# THE LINE, NOT ONLY THE DETAIL. A freshness refusal carries no `bionic: ` line at all, so
# this row is what says the budget arm is the one that spoke — and, because run_gate only
# re-drives for the detail when a `bionic: ` line was printed, it is also what keeps the
# rows below from reading a GATE_VERR left over from an earlier arm.
expect_contains "…and it is the budget arm that speaks, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…naming the roster count as the live-agent count" \
  "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_absent "…and never asking for a ListAgents call first" \
  "call ListAgents" "$GATE_VERR"
expect_absent "…nor refusing for want of a fresh answer" "live-agents: none" "$GATE_VERR"

# (c) N IS READ, NOT ASSUMED. Three rows, same empty transcript, ceiling 3 -> open=3.
# Without this arm a hard-coded 2 would pass (a) and (b) both.
REPO=$(make_repo r22nlc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=3 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
s22_roster_row "$REPO" "$SID_A" "n3"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLA_NONE")"
expect_eq "r22nlc three open rows against a ceiling of 3 -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…on the budget, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…counting three, because three is what the roster holds" \
  "writers: budget=3 open=3 with-this-dispatch=4" "$GATE_VERR"

# (d) A STALE ANSWER READS THE SAME WAY. Freshness is a property of the transcript, so a
# stale answer tells this wall nothing about any row — and telling the operator to go
# refresh it is the very chore D1 struck. Same two rows, same ceiling of 2 as (b).
REPO=$(make_repo r22nld yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
R22NLD_STALE="$SANDBOX/.r22nld-stale.jsonl"
mk_transcript "$R22NLD_STALE" stale n1 n2
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLD_STALE")"
expect_eq "r22nld a STALE answer is judged against the roster too -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…on the budget, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…on the budget, with the same count" \
  "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_absent "…not on the staleness" "call ListAgents" "$GATE_VERR"

# (e) THE FALLBACK IS A FALLBACK, not a new rule. When the answer IS fresh it still
# decides: the same two rows, a fresh answer naming neither of them, and a ceiling of 1 —
# open=0 and the dispatch is allowed. A rule that had simply started counting every row
# would refuse here.
REPO=$(make_repo r22nle yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
R22NLE_FRESH="$SANDBOX/.r22nle-fresh.jsonl"
mk_transcript "$R22NLE_FRESH" fresh W-OTHER
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLE_FRESH")"
expect_status "r22nle a FRESH answer naming neither row still closes both -> ALLOWED" \
  "0" "$GATE_ST"
expect_absent "…so no writers count is printed at all" "writers:" "$GATE_ERR"

# The paired negative: an EMPTY roster (no `status=intended` rows at all) needs no live
# reading at all, so a STALE transcript never even reaches the reader — the loop that
# would call it has nothing to iterate. The row below is what keeps the fallback in
# §S22b-nla from being read as "a stale answer makes the wall say something": with no
# rows there is nothing to count and nothing to say.
REPO=$(make_repo r22jd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
R22JD_STALE="$SANDBOX/.r22jd-stale.jsonl"
mk_transcript "$R22JD_STALE" stale r1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22JD_STALE")"
expect_status "r22jd an empty roster needs no live reading -> the same STALE transcript passes" \
  "0" "$GATE_ST"
expect_absent "…and says nothing about live-agents" "live-agents:" "$GATE_ERR"

# (e) THE CLOSING MARKER IS UNREACHABLE WHILE THE PANEL IS FRESH (wave-14 AC-3.4,
# narrowing wave-12 AC-7).
#
# WHAT THE OLD PIN SAID. AC-7 retired `landing-swept` as this wall's closing signal
# outright and pinned the retirement on the function's own body at the TOKEN level, so the
# marker could not quietly come back as a second, competing signal on some future edit.
# r22ja/r22jb pin the BEHAVIOUR — presence in the fresh live set is what opens or closes a
# row — and this arm pinned the implementation beside them.
#
# WHAT WAVE-14 NARROWS, AND WHY (D7, REQ-3). The retirement is kept whole for the case it
# was written for: WHILE THE PANEL IS FRESH THE PANEL IS THE TRUTH AND NO MARKER IS
# CONSULTED. It is lifted on the one path wave-12 left counting every `status=intended` row
# open forever — a STALE or ABSENT panel, where there is no reading to prefer and nine
# landed rows held nine writer slots for the rest of the session (§budget-markers below).
# The precedent is in this same file: the name-in-flight arm has read the same marker off
# the same roster to answer the same question since T26.
#
# SO THE PIN MOVES from "the token is absent from the body" to "the token is UNREACHABLE on
# the fresh path", and it is held by a delimited span: everything the count does when the
# panel HAS spoken for a row sits between `BEGIN fresh-panel branch` and `END fresh-panel
# branch`, and no closing reading may appear inside it. The mutation arm plants one there.
BUDGET_FN_BODY="$(sed -n '/^  budget_roster_counts() {/,/^  }$/p' "$GATE")"
expect_eq "…and the extracted span is non-empty (the pin is not vacuously true)" "1" \
  "$(printf '%s\n' "$BUDGET_FN_BODY" | /usr/bin/grep -c 'budget_roster_counts() {' || true)"
# THE NARROWING IS REAL IN BOTH DIRECTIONS. The count DOES consult the closing reading —
# once, through the one owner both roster walls share — so a body that had simply dropped
# the marker again (and taken §budget-markers red) fails here too.
expect_eq "budget_roster_counts consults the closing reading exactly once, through its one owner" "1" \
  "$(printf '%s\n' "$BUDGET_FN_BODY" | /usr/bin/grep -c 'roster_open_names' || true)"
BUDGET_FRESH_SPAN="$(printf '%s\n' "$BUDGET_FN_BODY" \
  | /usr/bin/awk '/BEGIN fresh-panel branch/, /END fresh-panel branch/')"
expect_nonempty "…and the fresh-panel branch is delimited (the span pin is not vacuous)" \
  "$BUDGET_FRESH_SPAN"
expect_eq "the fresh-panel branch consults no landing marker at all (never while FRESH)" "0" \
  "$(printf '%s\n' "$BUDGET_FRESH_SPAN" | /usr/bin/grep -cE 'landing-swept|roster_open_names' || true)"

# THE ANTI-VACUITY ARM: a doctored copy that reads a marker INSIDE the fresh-panel branch
# must fail the pin above. The doctor inserts one inert statement right after the span's own
# opening delimiter — not a comment change to the function signature, which would move the
# extractor's anchor and prove nothing.
GATE_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-preflight-swept-mut.XXXXXX")"
GATE_MUT="$GATE_MUT_ROOT/dispatch-preflight.sh"
awk '
  { print }
  /---- BEGIN fresh-panel branch/ { print "        : \"$(roster_open_names \"$f\")\" # landing-swept read on the FRESH path (test-only)" }
' "$GATE" > "$GATE_MUT"
expect_eq "swept-mut meta: the doctor's re-added line landed (the anchor still matches)" "1" \
  "$(/usr/bin/grep -c 'landing-swept read on the FRESH path' "$GATE_MUT")"
BUDGET_FN_BODY_MUT="$(sed -n '/^  budget_roster_counts() {/,/^  }$/p' "$GATE_MUT")"
BUDGET_FRESH_SPAN_MUT="$(printf '%s\n' "$BUDGET_FN_BODY_MUT" \
  | /usr/bin/awk '/BEGIN fresh-panel branch/, /END fresh-panel branch/')"
expect_contains "…and the doctored fresh branch now DOES read a marker (the pin above discriminates)" \
  "roster_open_names" "$BUDGET_FRESH_SPAN_MUT"
rm -rf "$GATE_MUT_ROOT"

# ================= §budget-markers: A LANDED ROW HOLDS NO WRITER SLOT ON A DARK PANEL
# (wave-14 REQ-3, design D7; seed C18; A-orch-23.)
#
# WHAT S22b-nla LEFT. The fallback above judges a dark panel against the roster's own
# `status=intended` rows — every one of them, because nothing there asks whether a row
# FINISHED. On a wave of nine tasks that is nine writers for the rest of the session: the
# panel goes stale for one turn and the next dispatch is refused on a budget that eight
# landed rows are still holding. The roster already carries the closing fact — the
# `landing-swept/v1|…|state=MET` marker the name-in-flight arm has read since T26 — and the
# sweeper's ledger carries the other, for a row the sweep cannot verdict (a row that
# declared nothing durable stats MET vacuously).
#
# THE RULE (D7, narrowed by epic-23 wave-20 T2, D10; ADR-034 d1). A row is open iff
# `status=intended` and, WHEN THE PANEL IS STALE OR ABSENT, no ack taken after its latest
# launch closes it — `roster_open_names` (payload/scripts/lib/roster.sh), the one close
# predicate every reader calls. A landing marker closes NOTHING any more: wave-14 counted it as
# a second closing truth here, and that was one of the four readings of "is this name closed"
# that disagreed (triage-C claim 4). The ack is the one terminal state; the Patrol writes it
# once a fresh panel shows the agent gone. A FRESH panel is still the whole truth and no
# closing reading is consulted at all — that is (c).
#
# EACH ARM MOVES ONE THING. (a) and (b) share the roster, the ceiling and the stale panel and
# differ only in whether the markers are there; (b) and (c) share the markers and differ only
# in the panel's freshness; (d) and (e) share the acks and differ only in WHEN they were taken.

section "§budget-markers: a landed row holds no writer slot on a dark panel"

S22MK_NAMES="m1 m2 m3 m4 m5 m6 m7 m8 m9"
S22MK_LANDED="m1 m2 m3 m4 m5 m6 m7"

expect_nonempty "§budget-markers meta: the ack fixture read a ledger schema out of the writer" \
  "$S22_LEDGER_SCHEMA"

# (a) REVERSED BY epic-23 wave-20 T2 (REQ-10 AC-10.1, D10). Wave-14 AC-3.1 drove this arm the
# other way: nine intended rows, seven carrying a landing marker, a STALE panel and a ceiling
# of eight read open=2 and ALLOWED the dispatch. A marker without an ack is now OPEN to every
# reader alike — the sweeper and the stop wall already counted it open, so the Patrol filled
# against a slot this wall had handed out — and the same fixture is REFUSED at open=9. The
# marker-free close is (d): the same seven rows ACKED.
REPO=$(make_repo r22mka yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
R22MK_STALE="$SANDBOX/.r22mk-stale.jsonl"
# shellcheck disable=SC2086
mk_transcript "$R22MK_STALE" stale $S22MK_NAMES
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mka nine rows, seven MET-marked and NONE acked, STALE panel, writers=8 -> REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open: a marker closes nothing" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"
expect_absent "…and nothing is said about the panel's staleness" "live-agents:" "$GATE_ERR"

# (b) AC-3.2 — THE CONTROL: the same nine rows, the same stale panel and the same ceiling,
# with NO markers written. open=9 and the dispatch is refused, naming the budget — the same
# answer (a) now gives, which is the point: the markers changed nothing.
REPO=$(make_repo r22mkb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mkb the same nine rows UNMARKED on the same stale panel -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…on the budget, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…naming the count the roster holds" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (c) AC-3.3 — THE PANEL WINS WHEN IT IS FRESH. The same nine rows and the same seven
# markers as (a); only the panel changes, to a FRESH answer naming all nine as live. The
# markers say landed, the panel says working, and the panel is the truth: open=9, REFUSED.
REPO=$(make_repo r22mkc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
R22MK_FRESH="$SANDBOX/.r22mk-fresh.jsonl"
# shellcheck disable=SC2086
mk_transcript "$R22MK_FRESH" fresh $S22MK_NAMES
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_FRESH")"
expect_eq "r22mkc a FRESH panel naming all nine live is not overridden by seven markers -> REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open, because the panel said so" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (d) THE ACK IS THE SECOND CLOSING TRUTH (REQ-3: "a landing marker or an ack"). The same
# nine rows and the same stale panel as (b), no markers at all — seven rows acked on the
# sweeper's own ledger instead. open=2, ALLOWED.
REPO=$(make_repo r22mkd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_ack "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_status "r22mkd seven rows ACKED on a stale panel, writers=8 -> ALLOWED" "0" "$GATE_ST"
expect_absent "…so no writers count is printed at all" "writers:" "$GATE_ERR"

# (e) AN ACK CLOSES THE ROW IT POSTDATES, NOT THE NAME FOREVER. Byte-for-byte (d)'s
# fixture with the acks dated BEFORE the rows were launched — the shape a name re-dispatched
# after its ack leaves behind. The ledger holds no ordering against the roster, so the
# comparison is by time, and an ack that predates the launch closes nothing: open=9, REFUSED.
REPO=$(make_repo r22mke yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_ack "$REPO" "$SID_A" "$_n" 2026-09-01T00:00:00Z; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mke acks dated BEFORE the rows were launched close nothing -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (f) A MARKER IS NOT A LATCH (the C1/S2 defect, in this wall's own terms). (a)'s fixture
# with every landed name DISPATCHED AGAIN below its marker: a fresh `status=intended` row
# retires the marker above it, so all nine are open once more and the ceiling of eight
# refuses. This is what makes the reading above a LATEST-CONTRACT reading and not a set.
REPO=$(make_repo r22mkf yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mkf a name re-dispatched below its own marker is open again -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (g) THE CLAIM GOES BACK WITH THE SLOT. A closed row's subprocess claim is not spent
# either: nine rows each claiming a suite, seven ACKED (the one close, D10), a stale panel and
# a ceiling of two suites — claimed=2, so this dispatch is the third and the SUITE arm allows
# it. Without the claim half of the subtraction the same fixture refuses on `suites:`.
REPO=$(make_repo r22mkg yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=3 worktrees=9 test_jobs=4 source=probe"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n" "bash tests/widget.test.sh"; done
for _n in $S22MK_LANDED; do s22_ack "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_status "r22mkg seven acked rows give their suite claims back too -> ALLOWED at suites=3" \
  "0" "$GATE_ST"
expect_absent "…and no suite count is printed" "suites:" "$GATE_ERR"

# (i) REQ-9 AC-9.3 AT ITS OWN NUMBERS, SUPERSEDED IN ITS CLOSING FACT by epic-23 wave-20 T2
# (REQ-10 AC-10.1, D10). EIGHT rows, a ceiling of eight writers. AC-9.3 closed six of them
# with a landing marker and ALLOWED the ninth; a marker is no close now, so six marked-but-
# unacked rows still hold their slots and the ninth is REFUSED at open=8. (i.3) below is the
# criterion's surviving half — six rows ACKED, open=2, ALLOWED — and is the close this wall
# honours.
#
# fails-when (AC-10.1): six rows MET-marked and never acked stop counting.
S22MK9_NAMES="n1 n2 n3 n4 n5 n6 n7 n8"
S22MK9_LANDED="n1 n2 n3 n4 n5 n6"
R22MK9_STALE="$SANDBOX/.r22mk9-stale.jsonl"
# shellcheck disable=SC2086
mk_transcript "$R22MK9_STALE" stale $S22MK9_NAMES

REPO=$(make_repo r22mki yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=8 worktrees=8 test_jobs=4 source=probe"
for _n in $S22MK9_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK9_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK9_STALE")"
expect_eq "r22mki eight rows, six MET-marked and none acked, writers=8 -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "r22mki …counting all eight open" "writers: budget=8 open=8 with-this-dispatch=9" "$GATE_VERR"

# (i.2) THE CONTROL. The same eight rows and the same ceiling with no markers: open=8, the
# ninth is over — the same answer (i) gives, because the markers change nothing.
REPO=$(make_repo r22mki2 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=8 worktrees=8 test_jobs=4 source=probe"
for _n in $S22MK9_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK9_STALE")"
expect_eq "r22mki2 the same eight rows UNMARKED at the same ceiling -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "r22mki2 …naming the count the roster holds" \
  "writers: budget=8 open=8 with-this-dispatch=9" "$GATE_VERR"

# (i.3) THE ACK IS THE SECOND CLOSING TRUTH AT THESE NUMBERS TOO (AC-9.3 names both). Six of
# the eight acked on the sweeper's own ledger instead of marked: open=2, ALLOWED.
REPO=$(make_repo r22mki3 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=8 worktrees=8 test_jobs=4 source=probe"
for _n in $S22MK9_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK9_LANDED; do s22_ack "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK9_STALE")"
expect_status "r22mki3 six rows ACKED at ceiling 8 -> ALLOWED" "0" "$GATE_ST"
expect_absent "r22mki3 …and no writers count is printed" "writers:" "$GATE_ERR"

# (h) THE CLOSED-SET LOOKUP DOES NOT LOSE A ROW TO ITS OWN PIPE (correctness review F8,
# wave-14 T26; memory grep-q-sigpipe-under-pipefail). `budget_roster_counts`'s dark-rows
# settlement asked `printf '%s\n' "$closed" | grep -qxF -- "$nm"` under this file's own
# `set -uo pipefail` (:67). `grep -q` exits at its first match; when `$closed` is large
# enough that the match leaves more queued than the pipe buffer holds, `printf` takes
# SIGPIPE, `pipefail` promotes that 141 over grep's own 0, and `|| continue` reads a name
# that WAS found as though it were not — a landed row keeps holding its writer slot.
#
# THE FIXTURE NEEDS THE FAILURE MODE, NOT A ROUND NUMBER. F8's own measurement put the
# threshold at roughly 4,000-6,000 short lines on this machine; six thousand rows, every
# one closed, is the margin this pin uses — and the first-inserted name is checked first
# against a list that also starts with it, which is the worst case (the biggest possible
# queued tail behind an early match). Built through the real roster writer
# (`roster_row_no_plan`) and the ack line `s22_ack` writes in the sweeper's own shape — ONE
# real row and ONE real ack captured with a placeholder name, then mechanically substituted
# six thousand times each, so the suite pays one writer call per shape rather than twelve
# thousand subprocess spawns for an equivalent loop. THE CLOSE IS AN ACK since epic-23
# wave-20 T2 (D10): a landing marker closes nothing, so the fixture that used to close six
# thousand rows with markers closes them the one way every reader honours.
section "§budget-markers-pipe: a closed name past the pipe buffer is still recognised"

R22MKH_N=6000
REPO=$(make_repo r22mkh yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"

R22MKH_F="$(roster_path "$REPO" "$SID_A")"
mkdir -p "$(dirname "$R22MKH_F")"

R22MKH_ROW_TMPL="$(roster_row_no_plan status=intended "session=$SID_A" "name=%%NM%%" \
  agent_id= launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  "deliverable=/tmp/d-%%NM%%" source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= "tool_use_id=t-%%NM%%")"
R22MKH_ACK_REPO="$SANDBOX/.r22mkh-ack-one"
s22_ack "$R22MKH_ACK_REPO" "$SID_A" "%%NM%%"
R22MKH_MARK_TMPL="$(cat "$R22MKH_ACK_REPO/.bionic/tmp/sweeper-$SID_A.state" 2>/dev/null)"
R22MKH_LEDGER="$REPO/.bionic/tmp/sweeper-$SID_A.state"

expect_nonempty "§budget-markers-pipe meta: the row template came from the real writer" \
  "$R22MKH_ROW_TMPL"
expect_nonempty "§budget-markers-pipe meta: the ack template came from the ledger's shape" \
  "$R22MKH_MARK_TMPL"

/usr/bin/awk -v tmpl="$R22MKH_ROW_TMPL" -v n="$R22MKH_N" '
  BEGIN {
    for (i = 0; i < n; i++) {
      nm = sprintf("f%05d", i)
      row = tmpl
      gsub(/%%NM%%/, nm, row)
      print row
    }
  }
' >> "$R22MKH_F"
/usr/bin/awk -v tmpl="$R22MKH_MARK_TMPL" -v n="$R22MKH_N" '
  BEGIN {
    for (i = 0; i < n; i++) {
      nm = sprintf("f%05d", i)
      row = tmpl
      gsub(/%%NM%%/, nm, row)
      print row
    }
  }
' >> "$R22MKH_LEDGER"

expect_eq "§budget-markers-pipe meta: the fixture really wrote six thousand roster rows" \
  "$R22MKH_N" "$(/usr/bin/grep -c "^roster-state/${ROSTER_SCHEMA_VERSION}|status=intended|" "$R22MKH_F" 2>/dev/null || echo 0)"
expect_eq "§budget-markers-pipe meta: …and six thousand acks" \
  "$R22MKH_N" "$(/usr/bin/grep -c "^${S22_LEDGER_SCHEMA}|event=ack|" "$R22MKH_LEDGER" 2>/dev/null || echo 0)"

R22MKH_STALE="$SANDBOX/.r22mkh-stale.jsonl"
mk_transcript "$R22MKH_STALE" stale f00000
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MKH_STALE")"
expect_status "r22mkh six thousand acked rows on a stale panel, writers=1 -> ALLOWED" \
  "0" "$GATE_ST"
expect_absent "…so no writers count is printed at all" "writers:" "$GATE_ERR"

# ============================== S22c: A FINISHED-BUT-UNSTOPPED AGENT IS NOT A WRITER
# (spec R2, AC-27; task S16, closing the Step-5 auditor's F-1.)
#
# R2 names two departure modes — "delivered and stopped, or finished and never stopped".
# S22b counts a row open on PRESENCE, which discharges the first and misses the second:
# the harness keeps listing a teammate that finished its turn and was never TaskStop'd,
# with status `idle`, because it stays addressable (a SendMessage would resume it). Under
# presence-counting that finished agent holds a writer slot until somebody stops it —
# B-1's stuck-slot defect wearing a new coat.
#
# THE RULE. A roster row counts OPEN only when its name is present in the fresh answer
# with status `running`. Presence is still what the STOP GUARD resolves on (an idle agent
# is exactly the one you stop), and both consumers read the one parse — the budget
# through `live_agents_status`, the guard through `live_agents_has` — so they cannot
# disagree about who is listed, only about what the status means. AMBIGUITY (a name
# listed twice, exit 2) still counts OPEN: the reader could not resolve it, and spending
# a slot beats handing one out on a reading nobody could make.
#
# Every arm below holds the roster, the repo and the budget fixed and moves ONLY the
# status in the answer, so nothing but the status can explain the verdict.

section "S22c: an idle (finished, unstopped) teammate does not count open"

# (a) THE HEADLINE. Byte-for-byte r22jb's fixture — one row `r1`, writers=1, r1 named in
# a fresh answer — with `running` changed to `idle`. r22jb REFUSES. This must pass.
REPO=$(make_repo r22ka yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KA_T="$SANDBOX/.r22ka.jsonl"
mk_transcript "$R22KA_T" fresh "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KA_T")"
expect_status "r22ka an idle (finished, unstopped) teammate does NOT count open" "0" "$GATE_ST"
expect_absent "…so no writers refusal is printed at all" "writers:" "$GATE_ERR"
expect_absent "…and the dispatch is not blocked" "BLOCKED" "$GATE_ERR"

# The meta-row: the fixture really did say idle. Without it, a builder that silently
# dropped the status and wrote nothing would make (a) pass for the wrong reason.
expect_contains "r22ka meta: the answer body names r1 idle, not running" \
  "r1 [8895ce]  ·  bionic:implementor  ·  idle" "$(cat "$R22KA_T")"

# (b) THE DISCRIMINATING PAIR, on one answer. Two rows, one idle and one running,
# against writers=1: the count is 1, not 2 and not 0. A rule that ignored status would
# say 2; a rule that stopped counting altogether would say 0 and let this through.
REPO=$(make_repo r22kb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
s22_roster_row "$REPO" "$SID_A" "r2"
R22KB_T="$SANDBOX/.r22kb.jsonl"
mk_transcript "$R22KB_T" fresh "r1:idle" "r2:running"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KB_T")"
expect_eq "r22kb one idle row and one running row against writers=1 -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…counting the running one ONLY: open=1, not open=2" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (c) AMBIGUITY IS STILL OPEN, and it is the arm that keeps (a) from being read as
# "anything the reader cannot call running is free". The same name twice — two sessions
# in one root launching same-named agents — is unresolvable, so the slot is spent.
REPO=$(make_repo r22kc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KC_T="$SANDBOX/.r22kc.jsonl"
mk_transcript "$R22KC_T" fresh "r1:idle" "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KC_T")"
expect_eq "r22kc the same name listed TWICE is unresolvable -> still counted open" \
  "deny" "$GATE_VERDICT"
expect_contains "…open=1 on the safe direction, even though neither copy reads running" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (d) A STALE `idle` IS NOT AN `idle` (wave-12 T1, D1). The status arms above all read a
# FRESH answer. On a stale one the word says nothing about now, so the row is not closed
# by it — it falls back to the roster and counts OPEN, and the BUDGET is what refuses.
# Before D1 this arm refused on the staleness itself and never reached a count; the
# outcome is the same exit, for a reason the operator can act on without a tool call.
REPO=$(make_repo r22kd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KD_T="$SANDBOX/.r22kd.jsonl"
mk_transcript "$R22KD_T" stale "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KD_T")"
expect_eq "r22kd a STALE idle does not close the row -> REFUSED on the budget" "deny" "$GATE_VERDICT"
expect_contains "…by the budget arm, not by the staleness" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…counting the row the stale answer could not speak for" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (e) THE REAL ANSWER, byte-verbatim. Everything above is synthesised from the harness's
# shape; this arm drives the shipped hook against a body captured from this project's own
# orchestrator session at 2026-09-05T03:07:41.801Z — `s6-stop-resolution` idle beside
# `s5-dispatch-budget` running, the moment S6 had delivered its report and had not yet
# been stopped (the stop is recorded at 03:07:46.215Z, five seconds later). Both names
# are on the roster and the budget is two: presence-counting fills it and refuses; the
# rule under test counts the one running writer and lets the dispatch through.
REPO=$(make_repo r22ke yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "s6-stop-resolution"
s22_roster_row "$REPO" "$SID_A" "s5-dispatch-budget"
# THE BODY IS THE CORPUS'S OWN LINE, not a copy of it (S17). This section is about ONE
# REAL ANSWER — the 03:07:41.801Z one, an idle writer beside a running one — and that
# answer is committed at tests/fixtures/claude/listagents-answers.jsonl as the line
# `LIVE_ANSWER_MIXED_LINE` names. Read back rather than re-typed, so the two names below
# and the two names on the roster rows above cannot drift apart from it.
R22KE_BODY="$(live_answer_content "$LIVE_ANSWER_MIXED_LINE")"
R22KE_T="$SANDBOX/.r22ke.jsonl"
{
  entry_prompt      "2026-09-05T03:07:30.000Z" "land S6"
  entry_tool_use    "2026-09-05T03:07:40.000Z" "ListAgents" "toolu_01Amv2QjVrsFDp5uVfKEowty"
  entry_tool_result "2026-09-05T03:07:41.801Z" "toolu_01Amv2QjVrsFDp5uVfKEowty" "$R22KE_BODY"
} > "$R22KE_T"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KE_T")"
expect_status "r22ke the real 03:07:41.801Z answer: one finished writer, one working -> allowed at writers=2" \
  "0" "$GATE_ST"
expect_absent "…no writers refusal, because open=1 and not 2" "writers:" "$GATE_ERR"

# The paired direction on the SAME real body: at writers=1 the one genuinely running
# writer fills the budget, and the refusal names open=1. This is what keeps (e) from
# passing against a gate that had simply stopped counting.
REPO=$(make_repo r22kf yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "s6-stop-resolution"
s22_roster_row "$REPO" "$SID_A" "s5-dispatch-budget"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KE_T")"
expect_eq "r22kf …and at writers=1 the still-running one alone fills it -> REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…open=1, the finished agent uncounted" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (f) THE CLAIMED (suites) COUNT RIDES THE SAME PREDICATE. A `claims=` row whose agent
# has finished must not hold a suite allowance either — otherwise the two ceilings would
# disagree about the same departed agent.
REPO=$(make_repo r22kg yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=1 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1" "live-agents"
R22KG_T="$SANDBOX/.r22kg.jsonl"
mk_transcript "$R22KG_T" fresh "r1:running"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KG_T")"
expect_eq "r22kg meta: a RUNNING claimant fills suites=1 (the control)" "deny" "$GATE_VERDICT"
expect_contains "…naming the claimed count" "suites: budget=1 claimed=1 with-this-dispatch=2" "$GATE_VERR"
mk_transcript "$R22KG_T" fresh "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KG_T")"
expect_status "r22kg the SAME claimant, now idle, releases its suite allowance" "0" "$GATE_ST"
expect_absent "…no suites refusal" "suites:" "$GATE_ERR"

# (g) FAIL-CLOSED ON AN UNKNOWN STATUS WORD (S19, Step-5 auditor F-13). S16 counted a row
# open only on the exact word `running`, which made every OTHER word — a renamed status, a
# third one the harness starts printing — read as CLOSED and hand out a writer slot. That is
# fail-OPEN, and it sat inside the same function whose ambiguity arm (c) is deliberately
# fail-CLOSED. The rule is now `open unless the harness said idle`, owned by
# `live_row_open` in payload/scripts/lib/agents.sh, and these two arms are the inversion.
#
# `starting` is deliberately a word the measured corpus does NOT contain: 26 captured
# answers, 44 teammate rows, two words only — 33 `running`, 11 `idle`. The predicate must
# not depend on that staying true.
REPO=$(make_repo r22kh yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KH_T="$SANDBOX/.r22kh.jsonl"
mk_transcript "$R22KH_T" fresh "r1:starting"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KH_T")"
expect_eq "r22kh an UNKNOWN third status word still counts OPEN -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…open=1, the slot kept on a reading nobody has seen before" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"
expect_contains "r22kh meta: the answer body really says starting, not running" \
  "r1 [8895ce]  ·  bionic:implementor  ·  starting" "$(cat "$R22KH_T")"

# THE DISCRIMINATING PAIR for (g), on one roster and one budget: the SAME row read `idle`
# is let through. Without it, r22kh would pass against a gate that had gone back to
# counting presence — and presence is exactly what S16 removed.
mk_transcript "$R22KH_T" fresh "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KH_T")"
expect_status "…while the SAME row read idle is still not open -> allowed" "0" "$GATE_ST"
expect_absent "…and prints no writers refusal" "writers:" "$GATE_ERR"

# (h) THE SUITE ALLOWANCE RIDES THE SAME PREDICATE, on the unknown word too. r22kg proved
# `claims=` follows the running/idle split; this proves it follows the ONE predicate rather
# than a second copy of the word `running` living in the claim arm.
REPO=$(make_repo r22ki yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=1 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "r1" "live-agents"
R22KI_T="$SANDBOX/.r22ki.jsonl"
mk_transcript "$R22KI_T" fresh "r1:starting"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KI_T")"
expect_eq "r22ki an unknown-status claimant still HOLDS its suite allowance" "deny" "$GATE_VERDICT"
expect_contains "…naming the claimed count" "suites: budget=1 claimed=1 with-this-dispatch=2" "$GATE_VERR"
mk_transcript "$R22KI_T" fresh "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KI_T")"
expect_status "…and the SAME claimant read idle releases it" "0" "$GATE_ST"
expect_absent "…no suites refusal" "suites:" "$GATE_ERR"

# (i) THE PREDICATE HAS ONE OWNER, and this gate is not a second copy of it. The inline
# `status = running` test S16 wrote lived here; S19 deleted it. A grep is the honest
# observable for "the rule is not spelled twice", and the anti-vacuity arm below proves the
# grep can see the string it is looking for.
expect_eq "the hook carries no inline status-word predicate of its own" "0" \
  "$(/usr/bin/grep -c '"\$la_st" = "running"' "$GATE")"
expect_eq "…and asks the library's one predicate by name instead" "1" \
  "$( [ "$(/usr/bin/grep -c 'live_row_open' "$GATE")" -ge 1 ] && echo 1 || echo 0 )"
S22K_MUT="$SANDBOX/.s22k-inline-mut.sh"
{ printf '# doctored: %s\n' '[ "$la_st" = "running" ] && row_open=yes'; cat "$GATE"; } > "$S22K_MUT"
expect_eq "…and the grep really can see that string when it is there (not vacuous)" "1" \
  "$(/usr/bin/grep -c '"\$la_st" = "running"' "$S22K_MUT")"

# ============================================ S23: THE ORCHESTRATOR-IN-WORKTREE ARM
# (spec AC-14; handoff 2.5.)
#
# A worktree is LEASED to the writer it was spawned for. A main-thread dispatch made
# from inside one is an orchestrator that has moved into a writer's tree — the roster
# it appends to hangs off the MAIN checkout (project_root maps the worktree back), so
# the dispatch is journalled in one address space while its author works in another,
# and the tree's own lease has no row that accounts for the orchestrator. The refusal
# names the main checkout, which is where dispatch authority sits.
#
# AN AGENT CONTEXT IS ALLOWED, and that is the whole point of the arm: a writer
# dispatched INTO a tree works there by construction, and refusing it would refuse the
# arrangement the wave is built on. Two spellings mark an agent context — the guard's
# BIONIC_HOOK_CHANNEL on the settings channel, and the payload's own `agent_type`,
# which the harness sets for a dispatched agent — and either one is enough.

section "S23: a main-thread dispatch from inside a linked worktree"

REPO=$(make_repo r23a yes)
write_attestation "$REPO" "$SID_A"
git -C "$REPO" worktree add -q -b wt/one "$REPO/.worktrees/one" >/dev/null 2>&1
S23_TREE="$REPO/.worktrees/one"
# PHYSICAL, because every root this gate prints is: project_root resolves with `pwd -P`
# and the sandbox sits under macOS's /var -> /private/var link. Comparing the refusal's
# main-checkout line against the LOGICAL fixture path would fail on the link alone,
# which is the same trap tests/canonical-sdlc-governing-skill.test.sh's make_project
# documents.
S23_MAIN=$( cd "$REPO" && pwd -P )

run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r23a a dispatch from the MAIN checkout passes (the control)" "0" "$GATE_ST"

# A DISTINCT NAME from r23a's, for the reason r23c states below and this arm now needs too:
# r23a was ALLOWED and journalled `w99-impl`, and with the arms pooled (wave-14 REQ-8) a
# re-used name would add the name-in-flight fault to the lease fault and refuse for both at
# once. The lease wall is what this arm is about.
run_gate "$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-b")"
expect_eq "r23b the same dispatch from inside the linked worktree is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the main checkout" "main checkout: $S23_MAIN" "$GATE_VERR"
expect_contains "…and the tree it was made from" "$S23_TREE" "$GATE_VERR"

# The settings-channel spelling of an agent context.
# A DISTINCT NAME per dispatch from here (T22): r23a's ALLOWED dispatch journalled a
# `w99-impl` row on this repo's roster, and a name with an open row cannot be handed out
# twice — which is the arm under test in §T22-name-in-flight, not this section's subject.
GATE_ENV="$GATE_ENV BIONIC_HOOK_CHANNEL=agent-context"
run_gate "$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-c")"
GATE_ENV="${GATE_ENV% BIONIC_HOOK_CHANNEL=agent-context}"
expect_status "r23c the same dispatch in an agent context (BIONIC_HOOK_CHANNEL) is allowed" "0" "$GATE_ST"

# The payload spelling.
S23_AGENT_PAYLOAD=$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-d" | jq '. + {agent_type:"senior-implementor"}')
run_gate "$S23_AGENT_PAYLOAD"
expect_status "r23d …and so is one whose payload carries agent_type" "0" "$GATE_ST"

section "S24 — THE ENGAGEMENT SWITCH (AC-5, AC-13, AC-14, AC-23)"
#
# The switch this wave adds, driven in both directions on ONE fixture so neither half can
# be true by accident. Every silence below sits beside the positive it is the negation of:
# the same repo, the same payload, the marker the only difference.

S24_REPO=$(make_repo r24 yes)
# An attestation up front (AC-25 / r24e): without one, r24a's dispatch auto-probes and
# WRITES it as a side effect, adding a one-time "environment check was run
# automatically" advisory line that r24e's later re-dispatch — now that the
# attestation already exists — does not repeat. That made the two refusals differ
# for a reason that had nothing to do with engagement, the thing r24e is testing;
# writing it up front, as every other fixture in this file does, removes the
# confound so "byte-identical" tests only the engagement switch.
write_attestation "$S24_REPO" "$SID_A"
S24_MARK="$S24_REPO/.bionic/tmp/engaged-$SID_A.state"

# (a) ENGAGED — the positive. A dispatch whose brief carries no deliverable is refused
# exactly as it was before this wave existed.
S24_BARE='Go and do the thing. No contract fields at all.'
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
# T17: this brief trips SEVERAL brief-shape arms, so its one refusal is a deny verdict
# on stdout with exit 0, not exit 2. The refusal itself — and every assertion below — is
# unchanged; only the channel the wall blocks on is.
expect_eq "r24a engaged: a dispatch with no deliverable is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…at the absent-deliverable wall" "Expected artifact" "$GATE_ERR"
S24_REFUSAL="$GATE_ERR"

# (b) THE SAME payload, the SAME repo, the marker removed -> nothing at all (AC-5).
rm -f "$S24_MARK"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_status "r24b unengaged: the same dispatch exits 0" "0" "$GATE_ST"
expect_empty "r24b …with no stdout" "$GATE_OUT"
expect_empty "r24b …and no stderr" "$GATE_ERR"

# (c) A SYMLINK at the marker path reads as ABSENT, never followed (AC-4's direction, at
# this gate). The link points at a real regular file, so only the -L refusal in
# `engaged_session` can produce this silence.
S24_DECOY="$SANDBOX/r24-decoy-marker"
printf 'plan=none\n' > "$S24_DECOY"
ln -s "$S24_DECOY" "$S24_MARK"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_status "r24c a SYMLINK at the marker path exits 0" "0" "$GATE_ST"
expect_empty "r24c …with no stdout" "$GATE_OUT"
expect_empty "r24c …and no stderr" "$GATE_ERR"
rm -f "$S24_MARK"

# (d) A FOREIGN session's marker is not this session's (AC-4).
: > "$S24_REPO/.bionic/tmp/engaged-$SID_B.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_status "r24d another session's marker exits 0" "0" "$GATE_ST"
expect_empty "r24d …and says nothing" "$GATE_ERR"
rm -f "$S24_REPO/.bionic/tmp/engaged-$SID_B.state"

# (e) THE REFUSAL TEXT IS BYTE-UNCHANGED for an engaged session (AC-13, AC-14). Restoring
# the marker must reproduce (a) exactly — not merely refuse, but refuse in the same words.
: > "$S24_MARK"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_eq "r24e re-engaged: the refusal is byte-identical to r24a" "$S24_REFUSAL" "$GATE_ERR"

# META (spec AC-25): r24e must not be vacuous the way it was before this task — a
# DOCTORED refusal (one byte changed) has to make it FAIL. Run in a subshell so the
# probe's own local ok/no/PASS/FAIL shadow the real ones and never touch this suite's
# actual counts; only the verdict below is a real assertion.
(
  PASS=0; FAIL=0; TOTAL=0
  ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); }
  no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); }
  expect_eq "probe" "$S24_REFUSAL" "${S24_REFUSAL}Z"
  exit "$FAIL"
)
if [ $? -ne 0 ]; then
  ok "r24e meta: a doctored refusal (one byte changed) makes expect_eq report a failure"
else
  no "r24e meta: a doctored refusal did NOT make expect_eq fail — the assertion is vacuous"
fi

# ---------- ENGAGED WITH NO PLAN ON DISK (AC-23) ----------
#
# The half of the ruling that is not "silence": engagement decides WHETHER a hook acts,
# the plan decides WHAT. A run's Step 0 precedes its own plan, and the walls that need no
# plan are owed from the first dispatch.
S24_NOPLAN=$(make_repo r24np yes)
rm -rf "$S24_NOPLAN/.bionic/docs"

# the Patrol checkpoint is plan-free: no stamp, no dispatch.
rm -f "$S24_NOPLAN/.bionic/tmp/patrol-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_NOPLAN")"
expect_eq "r24f engaged, no plan, no stamp -> REFUSED at the Patrol checkpoint" "deny" "$GATE_VERDICT"
expect_contains "…naming the Patrol" "Patrol" "$GATE_ERR"

# the deliverable wall is plan-free too: stamp back, brief stripped.
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID_A" > "$S24_NOPLAN/.bionic/tmp/patrol-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_NOPLAN" "$S24_BARE")"
# T17: this brief trips SEVERAL brief-shape arms, so its one refusal is a deny verdict
# on stdout with exit 0, not exit 2. The refusal itself — and every assertion below — is
# unchanged; only the channel the wall blocks on is.
expect_eq "r24g engaged, no plan, no deliverable -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…at the absent-deliverable wall" "Expected artifact" "$GATE_ERR"

# the BUDGET wall is plan-bound: it measures against a ceiling only a plan can declare,
# so with no plan it says nothing. Driven with a contract-complete brief so the walls
# above have nothing to say, and the silence is the budget wall's own.
run_gate "$(mk_agent_payload "$SID_A" "$S24_NOPLAN")"
expect_status "r24h engaged, no plan, a complete brief -> passes" "0" "$GATE_ST"
expect_absent "r24h …and the budget wall stays silent" "parallel-budget" "$GATE_ERR"

# THE PAIRED POSITIVE, so r24h is not silence-by-vacuity: the same dispatch against a plan
# whose ceiling is already full IS refused by that wall.
S24_BUDGET=$(make_repo r24bw yes)
S24_PLAN="$S24_BUDGET/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
awk 'NR==2 { print "parallel-budget: writers=0 suites=4 worktrees=32 test_jobs=8 source=probe" } { print }' \
  "$S24_PLAN" > "$S24_PLAN.tmp" && mv "$S24_PLAN.tmp" "$S24_PLAN"
run_gate "$(mk_agent_payload "$SID_A" "$S24_BUDGET")"
expect_eq "r24i the same brief against a FULL budget is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…by the budget wall" "writers" "$GATE_VERR"

# and the same full budget with NO plan-free failure and NO marker is silent.
rm -f "$S24_BUDGET/.bionic/tmp/engaged-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_BUDGET")"
expect_status "r24j …and unengaged, that same full budget decides nothing" "0" "$GATE_ST"
expect_empty "r24j …silently" "$GATE_ERR"

setup_section "S25 — active_run -> session_run (wave-session-bound-run S5)"
#
# THE CONTRACT UNDER TEST (design ledger AC-1/AC-3/AC-6). `PLAN` used to come from
# `active_run "$REPO"` — the newest open plan in the root, with no session input at
# all. It now comes from `session_run "$REPO" "$PAYLOAD_SID"`: a session BOUND to a
# plan (`.bionic/tmp/engaged-<sid>.state` carrying `plan=<path>`) is gated on that
# plan and that plan alone, whatever else is open in the root; an UNBOUND session
# (the marker empty, as make_repo's own engaged-* fixtures are) resolves by
# newest-plan exactly as before, and says so on stderr; a session bound to a plan
# that has since closed is treated as having no open run at all, and says that too.
#
# s25_bind <repo> <sid> <plan-abs-path> — overwrites the marker make_repo already
# planted (empty = unbound) with a real binding, under the same two-line shape
# hooks/engage.sh writes (spec §Session binding), via the real `bind_plan` (S11,
# tests/lib/bound-marker.sh).
s25_bind() {
  bound_marker "$1" "$2" "$3"
}

# s25_repo <name> <budget-a> <budget-b> -> sets the globals S25_REPO / S25_PLAN_A
# / S25_PLAN_B (a plain call, never `$(...)` — a command substitution runs in a
# subshell, and every assignment here would be lost the instant it returned). A
# and B are the ONLY open plans in the root — make_repo's own default plan is
# removed — and A is older by mtime, so an UNBOUND session's fallback is
# decisively B.
s25_repo() {
  local name="$1" budget_a="$2" budget_b="$3"
  local repo; repo=$(make_repo "$name" yes)
  rm -f "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  S25_REPO="$repo"
  S25_PLAN_A="$repo/.bionic/docs/plans/epic-99-test/plan-a.plan.md"
  S25_PLAN_B="$repo/.bionic/docs/plans/epic-99-test/plan-b.plan.md"
  cat > "$S25_PLAN_A" <<PLANA
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
parallel-budget: $budget_a
---

## SDLC State

current: 4

- Step 4: plan A in flight
PLANA
  cat > "$S25_PLAN_B" <<PLANB
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
parallel-budget: $budget_b
---

## SDLC State

current: 4

- Step 4: plan B in flight
PLANB
  touch -t 202601010000 "$S25_PLAN_A"
  touch -t 202602010000 "$S25_PLAN_B"
}

# s25_deliver <plan-abs-path> — closes a plan (Step 9, delivered).
s25_deliver() {
  cat > "$1" <<'PLANDONE'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
---

## SDLC State

current: 9

- Step 9: report record/x.md, delivered: 2026-09-04
PLANDONE
}

section "S25a: bound-open — the caller's OWN plan is the ceiling"

# A's budget is tight (writers=1, already at the ceiling with one open row); B's is
# loose (writers=99). Bound to A, the dispatch is refused by A's ceiling — proof
# that a second open plan in the same root (B, newer, looser) is never consulted.
s25_repo r25a "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe" \
              "writers=99 suites=9 worktrees=9 test_jobs=4 source=probe"
write_attestation "$S25_REPO" "$SID_A"
s25_bind "$S25_REPO" "$SID_A" "$S25_PLAN_A"
s22_roster_row "$S25_REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO")"
expect_eq "25a1: bound to A (tight budget), the dispatch is REFUSED by A's ceiling" "deny" "$GATE_VERDICT"
expect_contains "25a2: …naming A as the plan the budget came from" "$S25_PLAN_A" "$GATE_VERR"
expect_absent "25a3: …and B's path is never named" "$S25_PLAN_B" "$GATE_ERR$GATE_REASON"
expect_absent "25a4: bound: no fallback line is printed" \
  "run resolved by newest-plan fallback" "$GATE_ERR$GATE_REASON"

section "S25b: fallback — unbound resolves to the newest plan, and says so"

# The SAME shape, a fresh repo, budgets swapped so B (the newest, and now the
# fallback target) is the tight one. Left UNBOUND (make_repo's own empty marker,
# untouched), the dispatch is refused by B's ceiling, not A's — and the gate
# prints the fallback advisory naming B. The positive (line present, B used) sits
# beside its negative (line absent once bound) on the same fixture.
s25_repo r25b "writers=99 suites=9 worktrees=9 test_jobs=4 source=probe" \
              "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
S25_REPO2="$S25_REPO"
# PHYSICAL, because the fallback path comes off active_plan's own resolution —
# `project_root` calls `pwd -P` internally (payload/scripts/lib/root.sh) — while
# $S25_PLAN_B is built from the SANDBOX's logical path (plain `pwd`, no `-P`, in
# this file's own SANDBOX= line). The two differ under macOS's /var -> /private/var
# link, and unlike a bare path-substring check (25b2/25b3, which match anywhere
# in GATE_ERR), this assertion pins an exact adjacency — "— " immediately
# followed by the path — so it needs the SAME physical form the hook itself
# prints. Mirrors tests/dispatch-preflight.test.sh S23's own S23_MAIN idiom.
S25_PLAN_B_PHYS="$(cd "$S25_REPO2" && pwd -P)/.bionic/docs/plans/epic-99-test/plan-b.plan.md"
write_attestation "$S25_REPO2" "$SID_A"
s22_roster_row "$S25_REPO2" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO2")"
expect_eq "25b1: unbound, the dispatch is REFUSED by B's (newest) ceiling" "deny" "$GATE_VERDICT"
expect_contains "25b2: …naming B as the plan the budget came from" "$S25_PLAN_B" "$GATE_ERR"
expect_absent "25b3: …and A's path is never named" "$S25_PLAN_A" "$GATE_ERR$GATE_REASON"
expect_contains "25b4: …and the fallback advisory names B, verbatim" \
  "dispatch-preflight: run resolved by newest-plan fallback (session unbound) — $S25_PLAN_B_PHYS" \
  "$GATE_ERR"

# THE NEGATIVE, same repo, same payload, only the binding added: once bound to A
# the fallback line disappears (A's loose budget also lets the dispatch through).
s25_bind "$S25_REPO2" "$SID_A" "$S25_PLAN_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO2")"
expect_status "25b5: the SAME repo, now bound to A (loose budget), passes" "0" "$GATE_ST"
expect_absent "25b6: …and the fallback advisory is gone" \
  "run resolved by newest-plan fallback" "$GATE_ERR"

section "S25c: bound-closed — a plan that closed is no open run at all"

# A is delivered (closed); B stays open, with a ceiling of zero — so if B were
# consulted at all, ANY dispatch would refuse. Bound to closed A, the dispatch
# passes (the budget wall is inert, as it is for any engaged-with-no-plan
# session) and the closed-plan advisory names A; B's path is nowhere in the
# output, proving B was never the fallback here.
s25_repo r25c "suites=9 worktrees=9 test_jobs=4 source=probe" \
              "writers=0 suites=9 worktrees=9 test_jobs=4 source=probe"
S25_REPO3="$S25_REPO"
s25_deliver "$S25_PLAN_A"
write_attestation "$S25_REPO3" "$SID_A"
s25_bind "$S25_REPO3" "$SID_A" "$S25_PLAN_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO3")"
expect_status "25c1: bound to a CLOSED plan (A), the dispatch passes — the budget wall is inert" \
  "0" "$GATE_ST"
expect_contains "25c2: …and the closed-plan advisory names A, verbatim" \
  "dispatch-preflight: bound plan closed — $S25_PLAN_A; this session has no open run" \
  "$GATE_ERR"
expect_absent "25c3: …B's path (the still-open plan) appears nowhere" "$S25_PLAN_B" "$GATE_ERR"
expect_absent "25c4: …nor does the writers=0 budget line B carries" "writers=0" "$GATE_ERR"

section "S25d: the roster row's plan= field (AC-2, §Roster attribution)"

# Roster attribution is the BINDING, not the resolved run: a session bound to A
# gets plan=A on its row even though the budget/fallback logic above resolves
# differently case by case. An unbound session's row carries the literal "none".
s25_repo r25d "suites=9 worktrees=9 test_jobs=4 source=probe" \
              "suites=9 worktrees=9 test_jobs=4 source=probe"
S25_REPO4="$S25_REPO"
# PHYSICAL, same reason as S25_PLAN_B_PHYS above: s25_bind (S11) writes through the real
# bind_plan, which stores the CANONICAL directory (`pwd -P`), not the sandbox's logical one.
S25_PLAN_A_PHYS="$(cd "$S25_REPO4" && pwd -P)/.bionic/docs/plans/epic-99-test/plan-a.plan.md"
write_attestation "$S25_REPO4" "$SID_A"
s25_bind "$S25_REPO4" "$SID_A" "$S25_PLAN_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO4")"
expect_status "25d1: bound dispatch passes" "0" "$GATE_ST"
S25_ROW=$(roster_nth_row "$(roster_path "$S25_REPO4" "$SID_A")" 1)
expect_status "25d2: the row's plan= field is A's path, verbatim" "$S25_PLAN_A_PHYS" \
  "$(roster_field "$S25_ROW" plan)"

s25_repo r25e "suites=9 worktrees=9 test_jobs=4 source=probe" \
              "suites=9 worktrees=9 test_jobs=4 source=probe"
S25_REPO5="$S25_REPO"
write_attestation "$S25_REPO5" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO5")"
expect_status "25d3: unbound dispatch passes" "0" "$GATE_ST"
S25_ROW2=$(roster_nth_row "$(roster_path "$S25_REPO5" "$SID_A")" 1)
expect_status "25d4: the row's plan= field is the literal 'none'" "none" \
  "$(roster_field "$S25_ROW2" plan)"

# --- S25d5: a plan path carrying a `|` cannot forge a row (S10a, review SEC F3) ---
#
# THE ROW IS PIPE-DELIMITED ON ONE LINE, which is why `sanitize()` exists and why every
# other interpolated value on it goes through that filter first. `plan=` is the field this
# wave added and was the one field that skipped it, while the parallel writer in
# `session-poker.sh adopt` filtered the same value through `clean()` — so the two writers
# disagreed about whether the field was trusted.
#
# THE FIXTURE IS A REAL FILE. A plan named `wave-99|status=landed|name=ghost.plan.md` is a
# legal filename on every filesystem bionic runs on, so no part of this is hypothetical.
#
# WHAT IS ASSERTED IS THE ROW'S SHAPE, not just the field's text: a forged `status=landed`
# would lose to the real one at `line_field`'s `head -1` today, which makes a value-only
# assertion pass for a reason that could evaporate under any reader change. The field COUNT
# is what says no segment was injected.
s25_repo r25f "suites=9 worktrees=9 test_jobs=4 source=probe" \
              "suites=9 worktrees=9 test_jobs=4 source=probe"
S25_REPO6="$S25_REPO"
write_attestation "$S25_REPO6" "$SID_A"
S25_EVIL="$S25_REPO6/.bionic/docs/plans/epic-99-test/wave-99|status=landed|name=ghost.plan.md"
cp "$S25_PLAN_A" "$S25_EVIL"
# PHYSICAL, same reason as S25_PLAN_B_PHYS above: s25_bind (S11) now writes through the
# real bind_plan, which resolves the marker's DIRECTORY with `pwd -P` and leaves the leaf
# (the pipe-bearing filename) untouched — so the roster row's plan= field carries this
# physical directory spelling, not the logical $S25_EVIL one.
S25_EVIL_PHYS="$(cd "$(dirname "$S25_EVIL")" && pwd -P)/$(basename "$S25_EVIL")"
expect_status "25d5a: the pipe-bearing plan file really exists (non-vacuity)" "yes" \
  "$([ -f "$S25_EVIL" ] && echo yes || echo no)"
s25_bind "$S25_REPO6" "$SID_A" "$S25_EVIL"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO6")"
expect_status "25d5b: the dispatch still passes" "0" "$GATE_ST"
S25_ROW3=$(roster_nth_row "$(roster_path "$S25_REPO6" "$SID_A")" 1)
S25_ROW_CLEAN=$(roster_nth_row "$(roster_path "$S25_REPO4" "$SID_A")" 1)
expect_status "25d5c: the row has exactly as many pipe-delimited fields as a clean row" \
  "$(printf '%s' "$S25_ROW_CLEAN" | tr -cd '|' | wc -c | tr -d ' ')" \
  "$(printf '%s' "$S25_ROW3" | tr -cd '|' | wc -c | tr -d ' ')"
expect_status "25d5d: status is still the writer's own value, not the injected one" "intended" \
  "$(roster_field "$S25_ROW3" status)"
expect_status "25d5e: name is still the dispatched agent's, not the injected one" \
  "$(roster_field "$S25_ROW_CLEAN" name)" "$(roster_field "$S25_ROW3" name)"
expect_status "25d5f: and plan= holds the path with its pipes neutralised" \
  "$(printf '%s' "$S25_EVIL_PHYS" | tr '|' ' ')" "$(roster_field "$S25_ROW3" plan)"

# ================================================== S26: ONE TRANSCRIPT PARSE PER GATE
#
# Step-6 review P-1. The budget loop asks `live_row_open` once per unique `status=intended`
# name, and each ask used to run two whole-file `jq` passes over the transcript. Twelve
# rows against a 4.1 MB transcript measured 1.22 s — over the ~1 s budget for a hook that
# fronts every dispatch — and the row count grows for the life of a session while the
# transcript grows too. `live_agents` now memoizes its parse per process, and the loop
# primes that cache once in the shell the loop runs in, because the per-row call is a
# command substitution and a subshell's cache write dies with it.
#
# THE COUNT IS THE PIN, not the timing. A `jq` shim on PATH records one line per
# invocation whose argv names the transcript; the answer must be 2 (one `_la_scan`, one
# `_la_body`) no matter how many rows the roster carries.
section "S26: the budget parses the transcript once, not once per row"

S26_SHIM="$SANDBOX/s26shim"
mkdir -p "$S26_SHIM"
S26_REAL_JQ="$(command -v jq)"
S26_COUNT="$SANDBOX/.s26-jq-calls"
cat > "$S26_SHIM/jq" <<S26EOF
#!/bin/bash
for _a in "\$@"; do
  case "\$_a" in *"\$LA_COUNT_TRANSCRIPT") printf '%s\n' "\$_a" >> "\$LA_COUNT_FILE" ;; esac
done
exec "$S26_REAL_JQ" "\$@"
S26EOF
chmod +x "$S26_SHIM/jq"

REPO=$(make_repo r26 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=99 suites=9 worktrees=9 test_jobs=4 source=probe"
S26_N=1
while [ "$S26_N" -le 12 ]; do
  s22_roster_row "$REPO" "$SID_A" "r26-$S26_N"
  S26_N=$((S26_N + 1))
done
S26_T="$SANDBOX/.r26.jsonl"
mk_transcript "$S26_T" fresh W-OTHER

: > "$S26_COUNT"
S26_SAVED_ENV="$GATE_ENV"
GATE_ENV="$GATE_ENV PATH=$S26_SHIM:$PATH LA_COUNT_FILE=$S26_COUNT LA_COUNT_TRANSCRIPT=$S26_T"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w26-impl" "claude-sonnet-5" "$S26_T")"
GATE_ENV="$S26_SAVED_ENV"

expect_status "26a twelve intended rows and the gate still passes at writers=99" "0" "$GATE_ST"
expect_status "26b …and the transcript was parsed exactly twice — once per jq pass, not once per row" \
  "2" "$(grep -c . "$S26_COUNT" | tr -d ' ')"

# ============================================================================
section "S27: the suite-allowance wall (AC-20, AC-24)"
# ============================================================================
#
# THE INCIDENT THIS SECTION IS ABOUT. Two dispatched writers finished their own work
# green at ~45 minutes and then spent 40 more re-running the whole tree, one suite at a
# time, in parallel, on an 8 GB machine. Their briefs said "run impacted suites only;
# never tests/run.sh". Prose in a brief is a wish; the roster row is what the writer-side
# guard can read. So the brief declares INTENT (`Files:`) or the closed set (`Suites:`),
# the wall records the budget, and a brief that declares neither is refused here.
#
# THE IMPACT COMMAND IS FIXTURED, NOT REAL. What this section proves is that the wall
# RUNS the configured command over the declared paths and records what comes back — so the
# command is a two-line stub whose answer is unmistakably its own, and doctoring it must
# move the row. Driving the real `tests/lib/impact.sh` through this contract is
# tests/cross-gate-agreement.test.sh's job (one owner per shared truth): a fixture that
# reproduced its output would pin this file to a derivation it does not own.

# s27_impact <repo> <suite>... — writes an impact command into <repo> that answers with
# exactly the named suites, in the `suite<TAB>reason:file` shape S12 published, and points
# .bionic/config.yaml at it. The stub ECHOES ITS ARGUMENTS into a side file, so the test
# can prove the declared paths reached it rather than assuming they did.
s27_impact() {
  local repo="$1"; shift
  mkdir -p "$repo/.bionic"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$@" > "$(dirname "$0")/impact-args.txt"\n'
    local _s
    for _s in "$@"; do printf 'printf "%%s\\tpath-ref:fixture\\n" %s\n' "$_s"; done
  } > "$repo/.bionic/impact-stub.sh"
  chmod +x "$repo/.bionic/impact-stub.sh"
  printf 'impact-command: bash %s/.bionic/impact-stub.sh\n' "$repo" > "$repo/.bionic/config.yaml"
}

BRIEF_FILES='Canonical-sdlc Step 4, task 4/13 of epic-99 wave-01; build · audited · wave.
Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-files.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh, hooks/widget-guard.sh'

# --- S27a: Files: + a configured impact command -> the DERIVED row ---
REPO=$(make_repo r27a yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" beta.test.sh alpha.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-files")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27a a brief declaring Files: with an impact command PASSES" "0" "$GATE_ST"
expect_status "27a …and the row records the declared paths verbatim" \
  "payload/scripts/lib/widget.sh,hooks/widget-guard.sh" "$(roster_field "$ROW" files)"
expect_status "27a …the derived set is the impact command's answer, sorted and deduplicated" \
  "alpha.test.sh beta.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "27a …and the row says the set was DERIVED, not declared" \
  "derived" "$(roster_field "$ROW" suites_source)"
# NON-VACUITY, both directions. The stub really ran, and it really received the paths the
# brief declared — a wall that ignored the command and wrote a constant would pass every
# assertion above.
expect_status "27a …the impact command was really run" "0" \
  "$([ -f "$REPO/.bionic/impact-args.txt" ] && echo 0 || echo 1)"
expect_eq "27a …over the declared paths, one argument each" \
  "payload/scripts/lib/widget.sh
hooks/widget-guard.sh" "$(cat "$REPO/.bionic/impact-args.txt")"

# --- S27a2: MUTATION — doctor the command, and the row must move ---
# The row is the command's answer, not the wall's opinion of it.
REPO=$(make_repo r27a2 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" gamma.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-files2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27a2 a DIFFERENT impact command answer lands a different budget" \
  "gamma.test.sh" "$(roster_field "$ROW" suites_allowed)"

# --- S27a3: a derivation that answers NOTHING leaves the budget empty, and warns ---
REPO=$(make_repo r27a3 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-files3")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27a3 an impact command that derives nothing still PASSES the dispatch" "0" "$GATE_ST"
expect_status "27a3 …with an empty budget on the row" "" "$(roster_field "$ROW" suites_allowed)"
expect_status "27a3 …still marked derived, so no reader mistakes it for a declaration" \
  "derived" "$(roster_field "$ROW" suites_source)"
expect_contains "27a3 …and the operator is told at dispatch" "derived no suites" "$GATE_ERR"

# --- S27b: Suites: -> the DECLARED row, normalised to basenames ---
REPO=$(make_repo r27b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27b.md
Suites: tests/one.test.sh, tests/two.test.sh' "w27-decl")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27b a declared Suites: line PASSES with no impact command configured" "0" "$GATE_ST"
expect_status "27b …recorded as BASENAMES, the same alphabet the derivation prints" \
  "one.test.sh two.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "27b …and the row says the set was DECLARED" \
  "declared" "$(roster_field "$ROW" suites_source)"
expect_status "27b …with no files= value, because the brief declared none" \
  "" "$(roster_field "$ROW" files)"

# --- S27c: NEITHER label -> refused, naming all three fixes ---
REPO=$(make_repo r27c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27c.md
Expected duration: ~15 minutes.' "w27-neither")"
expect_eq "27c a brief declaring neither Files: nor Suites: is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27c …naming the Files: fix" "Files: path/one.sh" "$GATE_VERR"
expect_contains "27c …naming the Suites: fix" "Suites: tests/one.test.sh" "$GATE_VERR"
expect_contains "27c …and the waiver" "Suites: none" "$GATE_VERR"
# THE SPELLING RULE, IN THE ONE MESSAGE AN AUTHOR READS WHEN THE LABELS ARE MISSING. Both
# labels are read out of the brief TEXT before any shell expands anything, and the
# writer-side guard reads its command the same way (review-c C-5/C-6): a name that is still
# a variable when a hook sees it can be neither derived from nor checked against anything.
expect_contains "27c …and the spelling rule the two labels share" \
  "one path per token, no shell variables" "$GATE_VERR"
expect_eq "27c …with ONE deny verdict on stdout and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_status "27c …and no row journalled for a refused dispatch" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- S27d: `Suites: none` is the waiver, and it lands on the row ---
REPO=$(make_repo r27d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: read the tree and report.
Expected artifact: .bionic/docs/record/w27d.md
Suites: none' "w27-waived")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27d a Suites: none brief PASSES" "0" "$GATE_ST"
expect_status "27d …and the waiver is on the row, where the writer-side guard reads it" \
  "none" "$(roster_field "$ROW" suites_allowed)"
expect_status "27d …recorded as a declaration, because a human declared it" \
  "declared" "$(roster_field "$ROW" suites_source)"

# --- S27e: Files: with NO impact command -> refused, naming the two fixes ---
#
# `Files:` states an intent that only a derivation can turn into a budget. bionic runs in
# repositories that configure none, and there the author is the only one who can name the
# set — so this refuses rather than passing with an empty budget, at the one moment the
# author is still holding the brief.
REPO=$(make_repo r27e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-nocmd")"
expect_eq "27e Files: with no impact-command configured is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27e …naming the declared-set fix" "Suites: tests/one.test.sh" "$GATE_VERR"
expect_contains "27e …and the config key that would derive it" "impact-command:" "$GATE_VERR"

# --- S27f: a brief carrying BOTH — the declaration wins ---
#
# `Suites: none` is a waiver, and a waiver a derivation could overrule is not a waiver.
REPO=$(make_repo r27f yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" derived-only.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27f.md
Files: payload/scripts/lib/widget.sh
Suites: tests/declared-only.test.sh' "w27-both")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27f a brief with both labels takes the DECLARED set" \
  "declared-only.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "27f …and says so" "declared" "$(roster_field "$ROW" suites_source)"
expect_status "27f …while still recording the files the brief declared" \
  "payload/scripts/lib/widget.sh" "$(roster_field "$ROW" files)"
# NON-VACUITY: the impact command that would have answered differently really was configured.
expect_status "27f …non-vacuity: an impact command WAS configured for this repo" "0" \
  "$([ -f "$REPO/.bionic/config.yaml" ] && echo 0 || echo 1)"

# --- §declared-new-suite (T8, AC-5.1) — a declared suite ABSENT ON DISK lands verbatim ---
#
# T7's repro (record/wave-14-tune-181/T7-req5-repro.md §3, RUN 2) drove this exact shape —
# Files: + a Suites: paragraph naming a suite the task itself is about to create, path-
# prefixed, own paragraph — against the REAL hook and found it already passing: lift
# (`lift_contract_fields`/`suite_names()`, :1388-1406) performs no on-disk existence check,
# and selection (`:2192-2194`) takes the declared set whole. This is that RUN, kept as a
# PIN beside 27f rather than a new implementation — 27f's own "declared wins whole"
# assertion is unchanged by it. Per the T8 brief: if this never goes red against the
# parent, it is reported as a pin, not as RED→GREEN.
REPO=$(make_repo r27new yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" archive.test.sh run.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Canonical-sdlc Step 4, task 4/4 of epic-23 wave-13; build · audited · wave.
Your task: the close-out script (D5, D6).
Expected artifact: .bionic/docs/record/wave-13-fixit-180/T4-close-out.md
Expected duration: ~120 minutes.
Files: payload/scripts/close-out.sh, payload/scripts/lib/archive.sh, tests/close-out.test.sh, tests/archive.test.sh, payload/scripts/lib/run.sh

Suites: tests/close-out.test.sh, tests/run-predicate.test.sh' "w27-newsuite")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "declared-new-suite a Files:+Suites: brief naming a suite absent on disk PASSES" \
  "0" "$GATE_ST"
expect_status "declared-new-suite …the row carries BOTH declared tokens, verbatim" \
  "close-out.test.sh run-predicate.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "declared-new-suite …suites_source= is declared, not derived" \
  "declared" "$(roster_field "$ROW" suites_source)"
# NON-VACUITY: the file really is absent from this fixture repo, and the impact command
# really was configured (so a wall that fell through to derivation would answer
# "archive.test.sh run.sh" instead, not this pair).
expect_status "declared-new-suite …non-vacuity: tests/close-out.test.sh is absent on disk" \
  "1" "$([ -f "$REPO/tests/close-out.test.sh" ] && echo 0 || echo 1)"
expect_status "declared-new-suite …non-vacuity: an impact command WAS configured for this repo" \
  "0" "$([ -f "$REPO/.bionic/config.yaml" ] && echo 0 || echo 1)"

# --- S27g: the row's instrument fields never disturb the ones already on it ---
#
# RE-AUTHORED FOR THE FOURTH FIELD (epic-23 wave-16, REQ-1/REQ-7 AC-7.3). `re_executes=` is
# the runner-agnostic half of the instrument declaration and joins the group as its LAST
# member, so the contiguity claim below is now over four keys rather than three. The claim
# itself is unchanged and is the one that matters: the group sits between `waiver=` and
# `tool_use_id=`, it does not interleave with anything, and `plan=` is still last on the row.
# A field appended anywhere else would pass a key-by-key read and still move bytes the
# captured row in tests/fixtures/roster-row.captured pins (cross-gate §RA.2).
REPO=$(make_repo r27g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w27-shape")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27g the deliverable is unmoved by the instrument fields" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "27g …and plan= is still the LAST field on the row" "0" \
  "$(printf '%s' "$ROW" | grep -qE '\|plan=[^|]*$' && echo 0 || echo 1)"
expect_status "27g the four instrument fields sit between waiver= and tool_use_id=" "0" \
  "$(printf '%s' "$ROW" | grep -qE '\|waiver=[^|]*\|files=[^|]*\|suites_allowed=[^|]*\|suites_source=[^|]*\|re_executes=[^|]*\|tool_use_id=' && echo 0 || echo 1)"

# --- S27h: SELF-CONSISTENCY — a brief following this wall's own Fix lines passes ---
#
# The same pin R6-2 applies to the deliverable walls, read back off THIS wall's stderr:
# an author who copies the recommended `Suites:` line verbatim must not be refused by the
# wall that recommended it.
S27_FIX=$(printf '%s\n' "$GATE_ERR" | grep -m1 -E '^[[:space:]]+Suites: ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
REPO=$(make_repo r27c2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27c2.md' "w27-neither2")"
S27_FIX=$(printf '%s\n' "$GATE_VERR" | grep -m1 -E '^[[:space:]]+Suites: tests' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
expect_status "27h the refusal really recommended a Suites: line" "0" \
  "$([ -n "$S27_FIX" ] && echo 0 || echo 1)"
REPO=$(make_repo r27h yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27h.md
$S27_FIX" "w27-followed")"
expect_status "27h a brief following that Fix: line verbatim PASSES" "0" "$GATE_ST"

# --- S27i: A WIDE DECLARED BUDGET SURVIVES WHOLE ON THE ROW (T18, REQ-9/D7 write side) ---
#
# T9 exempted `suites_allowed=`/`files=` from `clean()`'s 400-char cut on the READER side
# (`hooks/session-poker.sh`'s `adopt_write_row`). This is the same defect's WRITE side: the
# two `sanitize()` calls that build `C_FILES`/`C_SUITES` from a brief's own `Files:`/
# `Suites:` line still capped at 900 (the widest cap this file had, per the comment they
# used to carry — "truncating a list silently narrows a budget"). `SUITES_MAX`/`FILES_MAX`
# (60, `lift_contract_fields`'s own token-count bound, a SEPARATE and deliberate limit — see
# A-T18.2) cap the item COUNT the extraction stage lifts at all, so this fixture stays at
# exactly that many items and makes each one long enough that 60 of them still overflow the
# 900-char cap this task removes — a real budget this wide is not a hypothetical (A-orch-16).
S27I_SUITES=""; S27I_EXPECT=""
for _s27i in $(seq -w 1 60); do
  _s27i_name="very-long-suite-basename-for-the-budget-cut-test-number-${_s27i}.test.sh"
  S27I_SUITES="${S27I_SUITES}tests/${_s27i_name}, "
  S27I_EXPECT="${S27I_EXPECT:+$S27I_EXPECT }${_s27i_name}"
done
S27I_SUITES="${S27I_SUITES%, }"
expect_status "27i fixture non-vacuity: the declared line really overflows 900 chars" \
  "0" "$([ "${#S27I_SUITES}" -gt 900 ] && echo 0 || echo 1)"
REPO=$(make_repo r27i yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27i.md
Suites: ${S27I_SUITES}" "w27-wide-declared")"
expect_status "27i a brief declaring a 60-suite, >900-char budget PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27I_ROW_SUITES=$(roster_field "$ROW" suites_allowed)
expect_eq "27i …and the row's suites_allowed= carries the WHOLE set, byte for byte" \
  "$S27I_EXPECT" "$S27I_ROW_SUITES"
expect_status "27i …the LAST one specifically — the one 900 chars would have cut" \
  "0" "$(printf '%s\n' "$S27I_ROW_SUITES" | tr ' ' '\n' | grep -qxF 'very-long-suite-basename-for-the-budget-cut-test-number-60.test.sh' && echo 0 || echo 1)"
expect_status "27i …every one of the 60, none dropped" \
  "60" "$(printf '%s\n' "$S27I_ROW_SUITES" | tr ' ' '\n' | grep -c 'very-long-suite-basename')"

# --- S27j: A WIDE DECLARED Files: LIST SURVIVES WHOLE TOO (same fix, `files=`) ---
S27J_FILES=""; S27J_EXPECT=""
for _s27j in $(seq -w 1 60); do
  _s27j_path="payload/scripts/lib/a-fairly-long-widget-module-name-number-${_s27j}.sh"
  S27J_FILES="${S27J_FILES}${_s27j_path}, "
  S27J_EXPECT="${S27J_EXPECT:+$S27J_EXPECT,}${_s27j_path}"
done
S27J_FILES="${S27J_FILES%, }"
expect_status "27j fixture non-vacuity: the declared line really overflows 900 chars" \
  "0" "$([ "${#S27J_FILES}" -gt 900 ] && echo 0 || echo 1)"
REPO=$(make_repo r27j yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" alpha.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27j.md
Files: ${S27J_FILES}" "w27-wide-files")"
expect_status "27j a brief declaring 60 long files PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27J_ROW_FILES=$(roster_field "$ROW" files)
expect_eq "27j …and files= carries the WHOLE declared list, byte for byte (no cut at all)" \
  "$S27J_EXPECT" "$S27J_ROW_FILES"

# --- S27k: CONTROL — an ORDINARY field still cuts, unaffected by the fix above ---
#
# `deliverable=` keeps its own pre-existing 300-char cap: the fix is scoped to the two
# LIST-valued fields, exactly as `clean()`'s exemption was on the reader side.
S27K_LONG=$(printf 'x%.0s' $(seq 1 500))
REPO=$(make_repo r27k yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27k-${S27K_LONG}.md
Suites: tests/one.test.sh" "w27-control-cut")"
expect_status "27k a 500-char deliverable still PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27K_ROW_DELIV=$(roster_field "$ROW" deliverable)
expect_eq "27k …but its deliverable= is cut at exactly its own 300-char cap" \
  "300" "${#S27K_ROW_DELIV}"

# --- S27l: A 70-SUITE BUDGET LANDS WHOLE — the item-COUNT cap, raised (T19, A-orch-19.1) ---
#
# S27i/j proved the CHAR cut is gone (T18). This is the separate, third layer the walk
# found: `suite_names()`'s own token-COUNT bound, `SUITES_MAX` — the exact "your own suite
# is off your budget" shape that bit T9 at 70 declared suites. 70 is chosen to match that
# incident directly; the cap this task raises (200) holds it with room to spare.
S27L_SUITES=""; S27L_EXPECT=""
for _s27l in $(seq -w 1 70); do
  _s27l_name="count-cap-suite-${_s27l}.test.sh"
  S27L_SUITES="${S27L_SUITES}tests/${_s27l_name}, "
  S27L_EXPECT="${S27L_EXPECT:+$S27L_EXPECT }${_s27l_name}"
done
S27L_SUITES="${S27L_SUITES%, }"
REPO=$(make_repo r27l yes)
write_attestation "$REPO" "$SID_A"
# A BUDGETED PLAN, as every live plan is (ADR-035): since epic-23 wave-20 T2 a keyless live
# plan earns preflight's named-backstop WARN, and this row's "no WARN" is about the suite cap.
s22_set_budget "$REPO" "writers=99 suites=99 worktrees=99 test_jobs=4 source=probe"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27l.md
Expected duration: 5 minutes
Progress: .bionic/docs/record/w27-progress.md, cadence 5 minutes
Suites: ${S27L_SUITES}" "w27-count-70")"
expect_status "27l a brief declaring 70 real suites PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27L_ROW_SUITES=$(roster_field "$ROW" suites_allowed)
expect_eq "27l …and suites_allowed= carries all 70, none dropped" \
  "$S27L_EXPECT" "$S27L_ROW_SUITES"
expect_status "27l …the 70th specifically" "0" \
  "$(printf '%s\n' "$S27L_ROW_SUITES" | tr ' ' '\n' | grep -qxF 'count-cap-suite-70.test.sh' && echo 0 || echo 1)"
expect_absent "27l …no WARN, because 70 is under the raised cap" "WARN" "$GATE_ERR"

# --- S27m: OVER THE RAISED CAP IS LOUD — a WARN naming the cap and what it dropped ---
#
# 201 tokens (SUITES_MAX + 1) so the cap this task sets (200) is exercised at its own
# boundary. The prior behaviour here was a SILENT exit 0 (A-orch-19.1) — the same class of
# bug T9 fixed on the char cut and T18 fixed on the preflight-sanitize char cut, now fixed
# on the count cap. `expect_absent` on the OLD (silent) shape would pass vacuously if the
# WARN plumbing were simply missing, so this checks both the cap enforcement (200 kept, the
# 201st absent from the row) AND the WARN naming that exact 201st token.
S27M_SUITES=""
for _s27m in $(seq -w 1 201); do
  S27M_SUITES="${S27M_SUITES}tests/count-cap-over-${_s27m}.test.sh, "
done
S27M_SUITES="${S27M_SUITES%, }"
REPO=$(make_repo r27m yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27m.md
Expected duration: 5 minutes
Progress: .bionic/docs/record/w27-progress.md, cadence 5 minutes
Suites: ${S27M_SUITES}" "w27-count-201")"
expect_status "27m a 201-suite brief still PASSES (the cap warns, it does not refuse)" \
  "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27M_ROW_SUITES=$(roster_field "$ROW" suites_allowed)
expect_status "27m …suites_allowed= holds exactly the cap, 200" "200" \
  "$(printf '%s\n' "$S27M_ROW_SUITES" | tr ' ' '\n' | grep -c 'count-cap-over-')"
expect_absent "27m …the 201st is NOT on the row" "count-cap-over-201.test.sh" "$S27M_ROW_SUITES"
expect_contains "27m …and dispatch WARNs, naming the cap" "WARN" "$GATE_ERR"
expect_contains "27m …by number" "200" "$GATE_ERR"
expect_contains "27m …naming the dropped 201st token specifically" \
  "count-cap-over-201.test.sh" "$GATE_ERR"
expect_status "27m …never a SILENT exit 0 — stderr is non-empty" "0" \
  "$([ -n "$GATE_ERR" ] && echo 0 || echo 1)"

# ============================================================================
section "S27n: a dropped Suites: token is a refusal, not a silent no-instrument arm (T3, REQ-8, AC-8.1)"
# ============================================================================
#
# `suite_names()`'s filter (`:1748`) has always kept only a `*.test.sh` basename or a
# path-qualified `run.sh`; everything else fell off in total silence — a jest spec name,
# a pytest module — and the brief then met the UNRELATED "no Files: and no Suites:" arm,
# for having named something real. This puts the drop on the same channel the unexpanded-
# variable arm already uses (`:1746`, `suites_bad=`), named, before that arm is reached
# (research R3 §C1.4, option 3 — no existence check, D11-compliant).

REPO=$(make_repo r27n yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w27n-audit.md
Expected duration: ~30 minutes.
Suites: image-id.spec.ts" "w27n-aud-spec" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "27n an auditor brief naming a dropped token is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27n …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_contains "27n …the new verdict" \
  "Suites: names a file the shell runner cannot run" "$GATE_ERR"
expect_contains "27n …the fix points at Re-executes:" "Re-executes:" "$GATE_VERR"
expect_absent "27n …never the unrelated no-instrument text" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"
expect_status "27n …no roster row for the refused dispatch" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

REPO=$(make_repo r27n2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27n-writer.md
Expected duration: ~30 minutes.
Suites: image-id.spec.ts" "w27n-writer-spec")"
expect_eq "27n2 a writer brief naming the same dropped token is REFUSED likewise" \
  "deny" "$GATE_VERDICT"
expect_contains "27n2 …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_absent "27n2 …never the unrelated no-instrument text" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"

# ============================================================================
section "S27p: a trailing # comment is not a dropped Suites: token (T23, review R1)"
# ============================================================================
#
# THE SHIPPED SCAFFOLD CARRIES ONE. `agents-src/blocks/brief-scaffold.md` renders
# `Suites: none    # *.test.sh names or a path-qualified run.sh; other runners:
# Re-executes:` into all eight surfaces, and an author who fills the scaffold in keeps
# the comment. The drop refusal above read EVERY whitespace-separated token on the span,
# so `other`, `runners:` and the rest each scored as a file the shell runner cannot run,
# and a brief was refused for carrying this repo's own teaching text — with a message
# that names
# `Re-executes:` and never mentions the comment, so the repair was not discoverable from
# it (Step-6 review R1, HIGH; the base at 72e07ec admitted the same brief). `suite_names()`
# now stops reading the span at the first token beginning with `#`.
#
# fails-when: a commented span refuses; a word of the comment reaches the roster row; the
# comment changes the budget the bare span would have produced; or stopping at `#` also
# stopped the drop arm from seeing a real dropped token.

R27P_BRIEF='Your task: build it.
Expected artifact: .bionic/docs/record/w27p.md
Suites: tests/a.test.sh  # the impacted suite'
R27P_BARE='Your task: build it.
Expected artifact: .bionic/docs/record/w27p.md
Suites: tests/a.test.sh'

REPO=$(make_repo r27p yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$R27P_BRIEF" "w27p-comment")"
expect_status "27p a filled brief whose Suites: line ends in a comment is ADMITTED" \
  "0" "$GATE_ST"
expect_status "27p …on the deny channel as well as the exit one" "allow" "$GATE_VERDICT"
ROW_COMMENTED=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27p …the budget is the declared suite alone" "a.test.sh" \
  "$(roster_field "$ROW_COMMENTED" suites_allowed)"
expect_status "27p …declared, because a human declared it" "declared" \
  "$(roster_field "$ROW_COMMENTED" suites_source)"
expect_absent "27p …no word of the comment reaches the row" "impacted" "$ROW_COMMENTED"
expect_absent "27p …and the suite-drop refusal never fires" \
  "Suites: names a file the shell runner cannot run" "$GATE_ERR"

# THE CONTROL: the same brief with the comment deleted. The row is compared WHOLE, field
# for field, `launched_at=` excepted — that cell is one `date -u` per drive and the two
# drives can straddle a second boundary.
REPO=$(make_repo r27p2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$R27P_BARE" "w27p-comment")"
expect_status "27p2 the same brief without the comment is ADMITTED too" "0" "$GATE_ST"
ROW_BARE=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27p2 …and its row is the commented brief's row, field for field" \
  "$(printf '%s' "$ROW_COMMENTED" | sed 's/launched_at=[^|]*/launched_at=/')" \
  "$(printf '%s' "$ROW_BARE"      | sed 's/launched_at=[^|]*/launched_at=/')"
expect_contains "27p2 …non-vacuity: the compared row really carries the budget" \
  "suites_allowed=a.test.sh" "$ROW_BARE"

# THE WAIVER, COMMENTED — the scaffold line as it ships, filled in and left commented.
REPO=$(make_repo r27p3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: read the tree and report.
Expected artifact: .bionic/docs/record/w27p3.md
Suites: none    # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:' \
  "w27p-waiver")"
expect_status "27p3 a commented Suites: none is the waiver it always was" "0" "$GATE_ST"
# ...and on the OTHER channel too: a several-fault refusal exits 0 and denies on stdout, so
# the exit status alone would score this ADMITTED whatever the gate decided (wave-12 T17).
expect_status "27p3 …no refusal verdict on either channel" "allow" "$GATE_VERDICT"
expect_status "27p3 …the waiver on the row, where the writer-side guard reads it" "none" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# THE SAME LINE ON THE ROLE WHOSE OWN FILE SHIPS IT. `agents/auditor.md` carries the
# scaffold, and an auditor that waives every suite must declare runs instead (16lb1/16lb2) —
# so this is that admitted shape with the comment left on, and the control below is the same
# brief without the runs, which must still meet the AUDITOR arm and not the drop arm.
REPO=$(make_repo r27p3b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w27p3b-audit.md
Expected duration: ~30 minutes.
Suites: none    # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:
Re-executes: `pytest tests/unit`' "w27p-aud-waiver" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" \
  "bionic:auditor")"
expect_status "27p3b an auditor waiving suites in a comment-carrying line, declaring runs, is ADMITTED" \
  "0" "$GATE_ST"
expect_status "27p3b …the waiver on the row" "none" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

REPO=$(make_repo r27p3c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w27p3c-audit.md
Expected duration: ~30 minutes.
Suites: none    # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:' \
  "w27p-aud-bare" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "27p3c …and the same line without runs still meets the AUDITOR arm" "deny" "$GATE_VERDICT"
expect_contains "27p3c …named as an auditor that re-executes nothing" \
  "an auditor names no suites" "$GATE_ERR"
expect_absent "27p3c …never the suite-drop refusal" \
  "Suites: names a file the shell runner cannot run" "$GATE_ERR$GATE_REASON"

# THE DISCRIMINATOR: a genuinely dropped token AHEAD of a comment still refuses, naming the
# token and no word of the comment. §27n/§27n2 pin the whole-span case; this pins that
# stopping at `#` did not stop the arm.
REPO=$(make_repo r27p4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27p4.md
Suites: image-id.spec.ts  # the impacted suite' "w27p-drop")"
expect_eq "27p4 a dropped token ahead of a comment is still REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27p4 …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_absent "27p4 …and never a word of the comment" "impacted" "$GATE_VERR"

# ============================================================================
section "S27q: a # comment ends its LINE, not the whole span (critic C8/C9)"
# ============================================================================
#
# A `Suites:` SPAN IS NOT A LINE. `spanof()` runs to the next LABELLED line or the next
# blank line, so a roster wrapped across several lines is one span — and this wave's own
# dispatches carry 19-suite rosters. §27p above stopped the scan at the first `#` token
# anywhere in that span, so a comment on the FIRST line silently discarded every suite
# declared on the continuation lines: no refusal, no `suites_dropped=`, nothing on the
# roster row to show it happened, and the writer met the run-time budget wall instead
# (critic C8 — the loud drop §27n installed turned back into a quiet budget cut).
#
# THE RULE IS NOW LINE-SCOPED: a `#` token ends the tokens of ITS OWN line, and the scan
# resumes at the next line of the span. §27p's whole promise is kept — no word of a
# comment reaches the row or the drop refusal — and a comment that opens a CONTINUATION
# line ends that line only, contributing nothing from it.
#
# AND A SPAN THAT IS ALL COMMENT NOW SAYS SO (critic C9). `Suites: # read-only` lifts
# nothing, so all four guards of the no-instrument arm read empty and the brief is refused
# for "declaring no Files: and no Suites:" — of a brief that declares `Suites:` in as many
# words, the self-refuting shape C3 was fixed for. The verdict and the fix stay as they
# are (there genuinely is no budget for the row to carry); the DETAIL now opens by naming
# what happened and the one-word repair, first so it survives refuse.sh's twelve-line fold.
#
# fails-when: a suite declared on a continuation line is dropped behind a comment; a word
# of a comment reaches the row or a refusal; a dropped token on a continuation line goes
# silent; or an all-comment span is still refused as a brief that declared nothing.

S27Q_WRAP='Your task: build it.
Expected artifact: .bionic/docs/record/w27q.md
Suites: tests/a.test.sh   # the impact set
  tests/b.test.sh tests/c.test.sh'
S27Q_WRAP_BARE='Your task: build it.
Expected artifact: .bionic/docs/record/w27q.md
Suites: tests/a.test.sh
  tests/b.test.sh tests/c.test.sh'

REPO=$(make_repo r27q yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S27Q_WRAP" "w27q-wrap")"
expect_status "27q a wrapped Suites: span whose first line ends in a comment is ADMITTED" \
  "0" "$GATE_ST"
ROW_WRAP=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27q …and the budget is every suite the SPAN names, not the first line's alone" \
  "a.test.sh b.test.sh c.test.sh" "$(roster_field "$ROW_WRAP" suites_allowed)"
expect_absent "27q …no word of the comment reaches the row" "impact" "$ROW_WRAP"

# THE CONTROL: the same wrapped span with the comment deleted. Row compared WHOLE, field
# for field, `launched_at=` excepted — one `date -u` per drive, two drives can straddle a
# second boundary (§27p2's rule).
REPO=$(make_repo r27q2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S27Q_WRAP_BARE" "w27q-wrap")"
expect_status "27q2 the same wrapped span without the comment is ADMITTED too" "0" "$GATE_ST"
ROW_WRAP_BARE=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27q2 …and its row is the commented span's row, field for field" \
  "$(printf '%s' "$ROW_WRAP"      | sed 's/launched_at=[^|]*/launched_at=/')" \
  "$(printf '%s' "$ROW_WRAP_BARE" | sed 's/launched_at=[^|]*/launched_at=/')"
expect_contains "27q2 …non-vacuity: the compared row really carries all three suites" \
  "suites_allowed=a.test.sh b.test.sh c.test.sh" "$ROW_WRAP_BARE"

# THE COMMENT'S OWN WORDS ARE STILL NOT TOKENS — the hazard `break` was chosen for
# (A-T23.1). A suite NAMED INSIDE the comment is prose, not a declaration, on the comment's
# own line and glued to the `#` alike.
REPO=$(make_repo r27q3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q3.md
Suites: tests/a.test.sh  # and tests/b.test.sh' "w27q-prose")"
expect_status "27q3 a suite named inside the comment is not declared" "0" "$GATE_ST"
expect_status "27q3 …the budget is the declared suite alone" "a.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

REPO=$(make_repo r27q4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q4.md
Suites: tests/a.test.sh #tests/b.test.sh' "w27q-glued")"
expect_status "27q4 …and a comment glued to its own marker reads the same" "0" "$GATE_ST"
expect_status "27q4 …the budget is the declared suite alone" "a.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# A CONTINUATION LINE THAT IS ITSELF ALL COMMENT contributes nothing, and does not end the
# span's reading either — the line scope cuts both ways.
REPO=$(make_repo r27q5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q5.md
Suites: tests/a.test.sh
  # tests/b.test.sh is out of scope
  tests/c.test.sh' "w27q-contcomment")"
expect_status "27q5 an all-comment continuation line is ADMITTED" "0" "$GATE_ST"
expect_status "27q5 …contributes nothing, and does not stop the line after it" \
  "a.test.sh c.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# THE DISCRIMINATOR FOR C8: a genuinely dropped token on a CONTINUATION line, behind a
# comment on the first. §27p4 pins the same token ahead of a comment; this is the shape
# `break` silenced.
REPO=$(make_repo r27q6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q6.md
Suites: tests/a.test.sh  # the impact set
  image-id.spec.ts' "w27q-contdrop")"
expect_eq "27q6 a dropped token on a continuation line behind a comment is REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "27q6 …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_absent "27q6 …and never a word of the comment" "impact set" "$GATE_VERR"

# --- C9: a span that is ALL comment is refused for what it is ---------------------
REPO=$(make_repo r27q7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q7.md
Suites: # none needed, this is read-only' "w27q-allcomment")"
expect_eq "27q7 a Suites: span that is entirely a comment is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27q7 …the verdict is the no-instrument one, unchanged" \
  "declares no Files: and no Suites:" "$GATE_ERR"
expect_contains "27q7 …and the detail names what actually happened" \
  "its span is a comment" "$GATE_REASON"
expect_contains "27q7 …with the one-word repair beside it" \
  "write \`none\` to waive" "$GATE_REASON"
expect_absent "27q7 …no word of the comment is read as a suite" \
  "read-only" "$GATE_VERR"

# NON-VACUITY, BOTH WAYS. (i) An ordinary no-instrument brief — no `Suites:` label at all —
# keeps the detail it has always had and never gains the clause. (ii) An all-comment
# `Suites:` beside a `Files:` declaration is not refused at all: the clause is a sentence
# in one arm's detail, never a new refusal.
REPO=$(make_repo r27q8 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q8.md' "w27q-noinstrument")"
expect_eq "27q8 a brief with no Suites: label at all is refused as before" "deny" "$GATE_VERDICT"
expect_contains "27q8 …same verdict" "declares no Files: and no Suites:" "$GATE_ERR"
expect_absent "27q8 …and never the comment clause" "its span is a comment" "$GATE_ERR$GATE_REASON"

REPO=$(make_repo r27q9 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q9.md
Suites: # the marked runs below are the whole budget
Re-executes: `pytest tests/unit`' "w27q-runsplus")"
expect_status "27q9 an all-comment Suites: beside a declared run is ADMITTED" \
  "0" "$GATE_ST"
S27Q9_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "27q9 …non-vacuity: the declared run really is the row's budget" \
  "re_executes=\`pytest tests/unit\`" "$S27Q9_ROW"
expect_absent "27q9 …and no word of the comment reaches the row" "whole budget" \
  "$S27Q9_ROW"

# ============================================================================
section "S28: one regression per run (AC-24)"
# ============================================================================
#
# The full tree is proved once per run, by one dispatched runner, at integration close.
# A second full-tree dispatch is not forbidden — it is the shape a re-proof legitimately
# takes after a merge — it is made to COST A WRITTEN REASON on the plan, where the next
# reader finds it beside the run it explains.
#
# NEWER IS COUNTED, NOT TIMED (A-S13-4). The plan file is rewritten after every task, so
# its mtime is newer than everything within minutes and a timestamp comparison would be
# vacuous by lunchtime. The Nth full-tree dispatch of a run needs the (N-1)th
# `regression-cause:` line — monotone, hermetic, and one new sentence per extra run.

BRIEF_REGRESSION='Your task: run the tests floor.
Expected artifact: .bionic/docs/record/w28-floor.log
Expected duration: ~40 minutes.
Suites: tests/run.sh'

s28_add_cause() {  # <repo> <reason>
  local plan="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  printf 'regression-cause: %s\n' "$2" >> "$plan"
}

REPO=$(make_repo r28 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_REGRESSION" "w28-runner-one")"
expect_status "28a the FIRST full-tree dispatch of a run passes" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "28a …and its row carries run.sh, which is what makes it countable" \
  "run.sh" "$(roster_field "$ROW" suites_allowed)"

run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_REGRESSION" "w28-runner-two")"
expect_eq "28b a SECOND full-tree dispatch in the same run is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "28b …counting what it found" "Full-tree runs on this roster: 1" "$GATE_VERR"
# READ OUT OF THE FIX BLOCK, not merely "somewhere on stderr" — the unbound-session
# advisory this gate prints on every run also names the plan path, so a plain contains
# passes over a wall that never fired.
# Compared from the fixture root rightwards, because the gate resolves symlinks on the
# path it prints (/var -> /private/var on macOS) while $REPO does not.
S28_FIXLINE=$(printf '%s\n' "$GATE_VERR" | grep -A1 -F 'under `## SDLC State` in' | tail -1 | sed 's/^[[:space:]]*//')
expect_status "28b …naming the plan the cause belongs on, inside its own Fix block" \
  "/repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" "${S28_FIXLINE##*/r28}"
expect_contains "28b …and the line to write" "regression-cause:" "$GATE_VERR"
expect_status "28b …and the refused dispatch journalled no second row" \
  "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

s28_add_cause "$REPO" "the merge changed the loader; the tree must be re-proved"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_REGRESSION" "w28-runner-three")"
expect_status "28c a recorded regression-cause: releases the second run" "0" "$GATE_ST"
expect_status "28c …and it is journalled" \
  "2" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_REGRESSION" "w28-runner-four")"
expect_eq "28d …but the cause is spent: a THIRD run needs a second one" "deny" "$GATE_VERDICT"
expect_contains "28d …and the count says so" "Full-tree runs on this roster: 2" "$GATE_VERR"

# A NARROWER BRIEF NEEDS NO CAUSE — the rule is about the full tree, not about dispatching.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: fix the widget.
Expected artifact: .bionic/docs/record/w28-narrow.md
Suites: tests/widget.test.sh' "w28-narrow")"
expect_status "28e a narrow brief in the same run is unaffected" "0" "$GATE_ST"

# CONTROL: the cause line only counts under `## SDLC State`. A cause written into the
# prose above it is not a ledger entry, and the wall must not read one.
REPO=$(make_repo r28f yes)
write_attestation "$REPO" "$SID_A"
S28F_PLAN="$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
S28F_BODY=$(cat "$S28F_PLAN")
printf '%s\n' "${S28F_BODY/# Test wave plan/# Test wave plan
regression-cause: written outside the ledger}" > "$S28F_PLAN"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_REGRESSION" "w28f-one")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_REGRESSION" "w28f-two")"
expect_eq "28f a regression-cause above ## SDLC State does not count" "deny" "$GATE_VERDICT"
expect_contains "28f …and the wall still reports zero causes" "Recorded causes on the plan: 0" "$GATE_VERR"

section "SECTION 29 — the derivation is BOUNDED, and the overrun is a refusal (review-c C-16)"
# THE DEFECT. The impact command is the whole of this gate's cost — ~0.3 s without it,
# ~2.9-3.1 s with it on an idle tree, 5.06-6.51 s measured while this wave's own writers
# were running. hooks/hooks.json registers the hook at a timeout of its own and the call
# had no bound of its own. A PreToolUse hook killed on the CLI's timeout does NOT exit 2: the
# dispatch proceeds, NO ROSTER ROW IS WRITTEN, and the writer runs with no budget at all —
# the wall defeated by the cost of the wall. So the bound is built here, and it refuses.
#
# NO SEAM. The bound is the shipped constant, not a value this suite hands the hook; the
# stub below simply outruns it. A test that shortened the bound would prove a constant it
# had itself supplied and leave the production path unverified.
#
# AND THE CONSTANT IS READ, NOT TRANSCRIBED (wave-14 REQ-7, D4). It moved from a literal in
# the hook to `payload/scripts/lib/bounds.sh`, which both this wall and the landing sweep
# source; a number typed here would go stale the first time the library's does, and the
# assertions below would then be pinning this file's memory of the bound rather than the
# bound. `s29_impact`'s sleep is derived from it for the same reason.
S29_BOUND="$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/bounds.sh" 2>/dev/null)"
expect_nonempty "29 the shipped bound is readable from lib/bounds.sh" "$S29_BOUND"

# s29_impact <repo> <sleep seconds> — an impact command that answers correctly, but late.
s29_impact() {
  local repo="$1" secs="$2"
  mkdir -p "$repo/.bionic"
  {
    printf '#!/bin/bash\n'
    printf 'sleep %s\n' "$secs"
    printf 'printf "alpha.test.sh\\tpath-ref:fixture\\n"\n'
  } > "$repo/.bionic/impact-stub.sh"
  chmod +x "$repo/.bionic/impact-stub.sh"
  printf 'impact-command: bash %s/.bionic/impact-stub.sh\n' "$repo" > "$repo/.bionic/config.yaml"
}

# --- 29a: a derivation that outruns the bound REFUSES, and refuses in time ---
REPO=$(make_repo r29a yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" $(( S29_BOUND + 10 ))
S29_T0=$(date +%s)
GATE_HIRES=1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w29-slow")"
GATE_HIRES=""
# THE WALL'S OWN COST, not the suite's: `run_gate` drives the call a second time with
# BIONIC_WALL_VERBOSE=1 to read `detail`, and that second bounded derivation would double
# the number measured here. `$GATE_TIME` is the first drive alone.
S29_ELAPSED="$GATE_TIME_CS"
expect_eq "29a a derivation that outruns the bound REFUSES the dispatch" "deny" "$GATE_VERDICT"
expect_contains "29a …naming the bound it outran" "bound:   ${S29_BOUND}s" "$GATE_VERR"
expect_contains "29a …naming the command that was slow" "impact-stub.sh" "$GATE_VERR"
expect_contains "29a …naming the paths it was asked about" "payload/scripts/lib/widget.sh" "$GATE_VERR"
expect_contains "29a …and saying why an unbounded one would be worse" "no roster row" "$GATE_VERR"
# THE POINT OF THE BOUND IS THE CLOCK: the wait ends when the bound says so and not when
# the command finishes. The stub sleeps ten seconds longer than the bound, so a gate that
# waited for it would be caught here.
#
# THIS ASSERTION USED TO READ `< 10`, THE HOOK'S OWN REGISTRATION IN hooks/hooks.json, and
# it is re-pinned to the bound instead (wave-14 T6, A-T6.5) — NOT because the registration
# stopped mattering. THE GAP A-T6.5 NAMED IS CLOSED (wave-14 T35, D1 by Chris): the bound
# was 20 under a registration of 10, so on the machine the CLI killed this hook before its
# own bound could fire, and a hook killed on the CLI timeout does not exit 2 — the exact
# failure the bound exists to prevent, invisible here because a suite has no CLI timeout.
# Both numbers moved: the registration to 15, the bound to 10, five seconds clear. What
# this file discharges is AC-7.2, that the wait ends when the bound says so; that the bound
# sits strictly UNDER its registration is a two-file claim neither file can make alone, and
# tests/cross-gate-agreement.test.sh §L.4c is where it is pinned.
# EIGHT SECONDS OF SLACK WAS ENOUGH TO HIDE THE DEFECT IT WAS WATCHING (wave-14 T34). This
# read `< S29_BOUND + 8` over a whole-second clock. The gate's wait was denominated in
# `sleep 0.1` polls costing 115 ms each, so a stated 20s bound waited 23.0-23.2s — comfortably
# inside `+8`, and therefore green, for as long as the drift stayed under eight seconds,
# which is to say for as long as nobody was under enough load to care. Measured: 22s here
# and 22s at §hanging-impact on the tick-counted wait, against 20s and 21s on the clock.
#
# THE SLACK IS ONE SECOND NOW, AND THE CLOCK CAN SEE IT. `$GATE_TIME_CS` is the first
# drive in hundredths (`GATE_HIRES` above), so what is left to absorb is the gate's own
# non-waiting work rather than a second of rounding at each end. A wait denominated in
# anything that stretches under load misses by seconds and fails here.
if [ "$S29_ELAPSED" -le $(( (S29_BOUND + 1) * 100 )) ]; then
  ok "29a …and it stopped waiting at the bound, not at the sleep ($(( S29_ELAPSED / 100 )).$(printf '%02d' $(( S29_ELAPSED % 100 )))s)"
else
  no "29a …and it stopped waiting at the bound, not at the sleep" \
    "took $(( S29_ELAPSED / 100 )).$(printf '%02d' $(( S29_ELAPSED % 100 )))s against a ${S29_BOUND}s bound"
fi
# FAIL-CLOSED MEANS NO ROW. A refused dispatch journals nothing, so there is no row a
# writer-side guard could read as "no budget was stated" and stand aside on.
expect_status "29a …and journalled no row at all" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- 29b: CONTROL — the same brief, the same stub, fast, still derives and passes ---
REPO=$(make_repo r29b yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 0
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w29-fast")"
expect_status "29b control: the same stub, prompt, PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "29b …and the derived budget is the stub's answer" \
  "alpha.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "29b …recorded as derived" "derived" "$(roster_field "$ROW" suites_source)"

# --- 29c: a derivation that answers NOTHING is unchanged: empty budget, a warning ---
# The overrun is a refusal because the alternative is an unwritten row; a command that
# fails or answers nothing has still answered, and the third state (`suites_allowed=` empty)
# already has readers. This is the boundary between the two, asserted so a later edit
# cannot quietly turn one into the other.
REPO=$(make_repo r29c yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic"
printf '#!/bin/bash\nexit 3\n' > "$REPO/.bionic/impact-stub.sh"
chmod +x "$REPO/.bionic/impact-stub.sh"
printf 'impact-command: bash %s/.bionic/impact-stub.sh\n' "$REPO" > "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w29-empty")"
expect_status "29c a derivation that answers nothing still PASSES" "0" "$GATE_ST"
expect_contains "29c …with the operator warned at the moment the config is fixable" \
  "derived no suites" "$GATE_ERR"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "29c …and the row records the empty third state" "" "$(roster_field "$ROW" suites_allowed)"

# --- 29d/29e: the overrun refusal keeps whatever brief-shape faults were already
# collected (review-c19c16e F3, wave-12 T23, AC-1.1's fails-when). A15 sat between the
# five collecting arms and dp_refuse_findings and refused on the spot, discarding
# DP_FINDINGS — an ambiguous-label brief with a slow impact command was told about the
# label alone on attempt 1, and the impact overrun alone (with no memory of the label) on
# attempt 2. That is the exact one-fault-per-attempt loop T2 built dp_finding to end.

BRIEF_T23_COMBINED_IMPACT='Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes
Files: payload/scripts/lib/widget.sh'

# --- 29d: the ambiguous-label brief + an overrunning impact command -> ONE refusal, BOTH faults ---
REPO=$(make_repo r29d yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 30
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_T23_COMBINED_IMPACT" "w29d-slow")"
expect_eq "29d an ambiguous label + an overrunning impact command is refused ONCE" "deny" "$GATE_VERDICT"
expect_eq "29d …exactly one refusal line reaches the user" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_contains "29d …naming the multi-path fault (A11)" "several paths" "$GATE_VERR"
# T2 (D3, D11) NARROWS WHAT THIS CAN STILL PROVE. The several-fault wire no longer carries
# ANY per-finding rationale — not just the brief-shape kind C-2/R6-1/S18b above lost, but
# A15's config-shaped fact and Fix: too, since neither is one of the five scaffold labels
# and there is nowhere left on the wire to put it.
# T26 (critic Issue 3) NARROWS IT FURTHER STILL: the Expected artifact: line is no longer
# marked <ADD> even here, because `dp_scaffold_marked` now treats a non-empty candidate
# list as a label that WAS populated, just ambiguously — the same reasoning that keeps the
# absent-deliverable arm quiet on this brief (see A11 above; the second fault here is A15,
# not the absent-deliverable arm). The discriminator that A15 specifically fired — not just
# A11 — is what 29a already covers on its own single-fault path; this
# pair no longer distinguishes it from a combined-brief-fault-only refusal on the WIRE,
# which is a real narrowing this task surfaces rather than papers over (A-T2, assumptions.md).
expect_absent "29d …the Expected artifact: line is NOT marked <ADD> (a populated, ambiguous label)" \
  "$(scaffold_raw_line "$DISPATCH_FILE" "Expected artifact") <ADD>" "$GATE_VERR"
expect_status "29d …and journalled no roster row at all" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- 29e: CONTROL — the same brief, a fast impact command -> the multi-path fault named,
# the impact fault absent: nothing overran, so there is nothing to append.
REPO=$(make_repo r29e yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 0
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_T23_COMBINED_IMPACT" "w29e-fast")"
# T26 (critic Issue 3): nothing overran, and A11 is now this brief's ONLY fault (Files:
# is declared, so the no-Files/no-Suites arm does not fire either) — the single-fault
# shape, not a pooled list (since wave-19 T4 one fault is a deny verdict too, its own detail on the reason).
expect_eq "29e control: the same brief, a fast impact command, is still refused" \
  "deny" "$GATE_VERDICT"
expect_contains "29e …naming the multi-path fault (A11)" "several paths" "$GATE_ERR"


# ===========================================================================
section "S30: the approval checkpoint — a writer needs an approved plan (epic-22 K2, AC-K2.4)"
# ===========================================================================
#
# WHY THE WRITER AND NOT ONLY THE COMMIT. The evidence gate refuses a commit made at
# `current: 4` while the plan carries no `approved-by:`. That is the right wall, and it is
# the LATE one: by the time it fires, eight writers have already read the brief, taken
# worktrees and written code against a plan nobody ratified. This arm is the early half —
# it refuses the writer, which is the first act of a plan that closing a file cannot undo.
#
# THE ROLE SET IS THE WHOLE DISCRIMINATION. Researchers, test-runners, auditors and critics
# are dispatched BEFORE approval as a matter of course: the research that informs the plan
# is exactly such a dispatch, and refusing it would refuse the work that produces the
# approval. So the arm names two roles and only two, matched whole.
#
# HERMETIC, like everything else here: `make_repo` writes a plan at `current: 4` with no
# `approved-by:` line, which is precisely the refused state; the pass cases add the line.

# k2_plan_line <repo> <line...> — rewrite the fixture plan's `## SDLC State` body.
k2_write_plan() {  # <repo> <current> <approved-by line, or "">
  local repo="$1" cur="$2" approved="$3"
  local dir="$repo/.bionic/docs/plans/epic-99-test"
  mkdir -p "$dir"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf -- 'intent: build\nrigor: audited\nscale: wave\n---\n\n'
    printf -- '# Test wave plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: %s\n' "$cur"
    [ -n "$approved" ] && printf -- '%s\n' "$approved"
    printf -- '\n- Step %s: tasks in flight\n' "$cur"
  } > "$dir/wave-01-test.plan.md"
}

K2_APPROVED_LINE='approved-by: dana 2026-09-07T19:05Z "Ok, amazing! Approved."'

# --- 30a/30b: the two writer roles are refused while the line is absent ---
for _role in bionic:implementor bionic:senior-implementor; do
  _tag="30a"; [ "$_role" = "bionic:senior-implementor" ] && _tag="30b"
  REPO=$(make_repo "r${_tag}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_plan "$REPO" 4 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w${_tag}" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_eq "${_tag} a ${_role} dispatch at current: 4 with no approved-by is refused" "deny" "$GATE_VERDICT"
  expect_contains "${_tag} …and the refusal names the missing line" "approved-by" "$GATE_VERR"
  # NOT merely the plan path: an unbound session's own resolution announcement carries that
  # already, so a path assertion here would be green with no refusal printed at all.
  expect_contains "${_tag} …and says what a writer needs" "writers run against an APPROVED plan" "$GATE_VERR"
done

# --- 30c: THE CONTROL — the same dispatch with the line present passes ---
REPO=$(make_repo r30c yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30c" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "30c control: the same writer dispatch with approved-by present passes" "0" "$GATE_ST"
expect_absent "30c …with no refusal printed" "BLOCKED" "$GATE_ERR"

# --- 30d: an approved-by whose value is empty records no approval ---
REPO=$(make_repo r30d yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 "approved-by:"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30d" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "30d an empty approved-by: value is not an approval" "deny" "$GATE_VERDICT"

# --- 30e: the reading roles pass through the same refused plan ---
for _role in bionic:researcher bionic:test-runner bionic:auditor bionic:critic; do
  REPO=$(make_repo "r30e-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_plan "$REPO" 4 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30e" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_status "30e a ${_role} dispatch against the SAME unapproved plan passes" "0" "$GATE_ST"
done

# --- 30f: below Step 4 the arm is inert — the plan is still being authored ---
REPO=$(make_repo r30f yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 3 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30f" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "30f current: 3 with no approved-by — the arm is inert" "0" "$GATE_ST"

# --- 30g: the durable half — the approval still binds after Step 4 ---
REPO=$(make_repo r30g yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 6 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30g" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "30g current: 6 with no approved-by — still refused" "deny" "$GATE_VERDICT"

# --- 30h: no plan on disk at all — a plan-bound arm with nothing to measure ---
REPO=$(make_repo r30h no)
mkdir -p "$REPO/.bionic/tmp"
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID_A" > "$REPO/.bionic/tmp/patrol-$SID_A.state"
: > "$REPO/.bionic/tmp/engaged-$SID_A.state"
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30h" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "30h an engaged session with no plan on disk — the arm is inert" "0" "$GATE_ST"


# ===========================================================================
section "S31: the approval checkpoint binds at task scale too (epic-22 K2.5)"
# ===========================================================================
#
# K2.5 (Chris 2026-09-07 "Option 2"): a task-scale plan's `current: T<n>` reads as
# past Step 3 the same way the evidence gate's `k2_step_num` reads it — there is
# no "still being authored" state at task scale, so this arm binds on ANY
# `current: T<n>` (n >= 1), not only on numbered `current: 4`+. Mirrors S30
# exactly, on a `scale: task` plan instead of `scale: wave`.

# k2_write_task_plan <repo> <current T<n>> <approved-by line, or "">
k2_write_task_plan() {
  local repo="$1" cur="$2" approved="$3"
  local dir="$repo/.bionic/docs/plans/epic-99-test"
  mkdir -p "$dir"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf -- 'intent: build\nrigor: tested\nscale: task\n---\n\n'
    printf -- '# Test task-scale plan\n\n## Tasks\n\n'
    printf -- '| id | intent | rigor | description | status |\n|---|---|---|---|---|\n'
    printf -- '| %s | build | tested | wire the K2.5 arms | active |\n\n' "$cur"
    printf -- '## SDLC State\n\nscale: task\ncurrent: %s\n' "$cur"
    [ -n "$approved" ] && printf -- '%s\n' "$approved"
    printf -- '\n- %s: bash tests/dispatch-preflight.test.sh green\n' "$cur"
  } > "$dir/task-99-test.plan.md"
}

# --- 31a/31b: the two writer roles are refused while the line is absent ---
for _role in bionic:implementor bionic:senior-implementor; do
  _tag="31a"; [ "$_role" = "bionic:senior-implementor" ] && _tag="31b"
  REPO=$(make_repo "r${_tag}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_task_plan "$REPO" T1 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w${_tag}" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_eq "${_tag} a ${_role} dispatch at task-scale current: T1 with no approved-by is refused" "deny" "$GATE_VERDICT"
  expect_contains "${_tag} …and the refusal names the missing line" "approved-by" "$GATE_VERR"
done

# --- 31c: THE CONTROL — the same dispatch with the line present passes ---
REPO=$(make_repo r31c yes)
write_attestation "$REPO" "$SID_A"
k2_write_task_plan "$REPO" T1 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31c" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "31c control: the same task-scale writer dispatch with approved-by present passes" "0" "$GATE_ST"
expect_absent "31c …with no refusal printed" "BLOCKED" "$GATE_ERR"

# --- 31d: an approved-by whose value is empty records no approval, at task scale ---
REPO=$(make_repo r31d yes)
write_attestation "$REPO" "$SID_A"
k2_write_task_plan "$REPO" T1 "approved-by:"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31d" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "31d an empty approved-by: value is not an approval, at task scale" "deny" "$GATE_VERDICT"

# --- 31e: the reading roles pass through the same refused task-scale plan ---
for _role in bionic:researcher bionic:test-runner bionic:auditor bionic:critic; do
  REPO=$(make_repo "r31e-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_task_plan "$REPO" T1 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31e" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_status "31e a ${_role} dispatch against the SAME unapproved task-scale plan passes" "0" "$GATE_ST"
done

# --- 31f: any n >= 1 binds, not only T1 ---
REPO=$(make_repo r31f yes)
write_attestation "$REPO" "$SID_A"
k2_write_task_plan "$REPO" T3 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31f" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "31f task-scale current: T3 with no approved-by is refused (any n >= 1, not just T1)" "deny" "$GATE_VERDICT"


# ============================================================================
section "§combined — one refusal, every brief-shape fault (wave-12 T2, D3, AC-1.1/AC-1.2)"
# ============================================================================
#
# THE INCIDENT THIS SECTION IS BUILT FROM. On 2026-09-13 six dispatch attempts were spent
# spawning one researcher: the gate exited at the FIRST failing brief-shape arm, so each
# attempt taught the author exactly one fault and the next attempt found the next one. The
# faults were all in the brief — the one artifact the author was holding — and all readable
# in a single pass.
#
# WHAT CHANGED (spec D3, principle P-A). The five BRIEF-SHAPE arms — A11 several paths,
# A12 outside the repo, A13 no deliverable, A14 no Files:/Suites:, A16 Files: with no
# impact command — no longer refuse where they stand. Each appends its finding (fact, fix
# and its own verbatim `Fix:` block) to a list, and ONE `refuse exit2` after the last of
# them emits the list in file order and exits 2 once. The STATE arms are untouched: a
# missing attestation, an unarmed Patrol, an unapproved plan, a worktree cwd, a full
# budget and a second full-tree dispatch each still exit where they stand, because none of
# them is a defect in the brief and none is fixed by reading the next one.
#
# fails-when: a three-fault brief is refused for fewer than three faults, or refused more
# than once, or the second attempt — written from the first refusal's own `Fix:` examples —
# is refused for a fault the first refusal never named.

REPO=$(make_repo rcomb yes)
# A BUDGETED PLAN (ADR-035). Since epic-23 wave-20 T2 a keyless live plan adds its own
# `not checked: budget` line to the wire, and this arm's line cap counts the scaffold's walls,
# not the budget's; a real plan carries the key, so the fixture does too.
s22_set_budget "$REPO" "writers=99 suites=99 worktrees=99 test_jobs=4 source=probe"
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "combobot")"

# THE CHANNEL IS THE VERDICT, NOT THE STATUS (wave-12 T17). A combined refusal exits 0 and
# blocks with a PreToolUse deny verdict, so this arm reads `$GATE_VERDICT` — the driver's
# reading of both wires — where it used to read exit 2. §combined-deny below is where that
# channel is pinned in full; here it only has to be a REFUSAL for the counts to mean anything.
expect_eq "§combined a brief with three shape faults is REFUSED" "deny" "$GATE_VERDICT"

# ONE REFUSAL, NOT THREE. `refuse` exits, so a second refusal object cannot be emitted by
# the same process — but a wall that printed its findings as it went would show three
# `bionic: ` lines, and a wall that kept exiting at the first arm would show one line and
# one finding. The count of refusal lines and the count of findings are therefore both
# read, and they are different numbers on purpose.
expect_eq "§combined …exactly once: one refusal line reaches the user" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_eq "§combined …and the detail carries one refusal, not three stacked" "1" \
  "$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -c '^bionic: dispatch refused' || true)"

# THE USER LINE IS THE FIRST ARM'S OWN, and the detail says how many there are. AC-E1.3
# gives the line one fact and one six-word fix, and the widest arm here already spends 99
# of its 100 columns — so a line that also carried a count would be refused by the
# renderer as malformed. The count lives one line into the detail instead, where there is
# room for it and for every fault behind it.
expect_eq "§combined …the user line stays the first arm's own sentence" \
  "bionic: dispatch refused — the deliverable label names several paths (name exactly one deliverable)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
# THE MARKED SCAFFOLD REPLACES THE OLD RATIONALE (T2, D3/D11). No fault-count header
# sentence, no per-fault `── N.` heading, no `Fix:` block — the several-fault wire is the
# scaffold read live out of the shipped dispatch.md, each label the brief left empty
# suffixed ` <ADD>`, closed by one pointer line. Every string compared against below is
# read out of $DISPATCH_FILE at run time, never transcribed, so this stays true when the
# scaffold's own wording next changes.
expect_absent "§combined …no fault-count header sentence" "SHAPE FAULTS" "$GATE_VERR"
expect_absent "§combined …no per-fault '── N.' heading" "── " "$GATE_VERR"
expect_absent "§combined …no Fix: block" "Fix: " "$GATE_VERR"
# RAISED 8 -> 10 (T17, R6 finding 3): the scaffold gained two lines (`Progress artifact:`,
# `Cadence:`), and dp_scaffold_marked reproduces every scaffold line verbatim — marked or
# not — so the wire grows by exactly as many lines as the scaffold does. Not a widened
# tolerance; the cap tracks the scaffold's own line count by construction.
#
# RAISED 10 -> 13 (wave-14 T6, REQ-8/AC-8.3, A-T6.2), and by a formula rather than a
# feeling. Ten is still the fixed part — one refusal line, a blank, seven scaffold lines, a
# blank, the pointer. On top of it this brief buys three lines and no more, though WHICH
# three moved at T26 (critic Issue 3): the ambiguity fault IS the refusal line and costs
# nothing; "this brief declares no Files: and no Suites:" is the second fault and costs one
# line; and two `not checked:` lines now ride the wire instead of one — `deliverable, needs
# one path` (the absent-deliverable arm recognising the ambiguity arm's own candidates,
# rather than repeating the fault) and `one-regression, needs a suite set` (unchanged). The
# general form is still 10 + (faults - 1) + not-checked lines, and the total is unchanged
# at 13 because a line only moved from the fault column to the not-checked column.
# §three-arms holds the criterion's own case — three faults, nothing unchecked, twelve —
# where this arm holds the canonical brief. Widening either without moving a fault count is
# the mistake to catch.
#
# RAISED 13 -> 14 (wave-15 T5, REQ-5, A-T5.2), and by the same formula. The floor-once wall
# is a SECOND arm keyed on `run.sh` in the derived suite set, so a brief that produces no
# set leaves two walls unable to answer rather than one, and AC-8.2's rule is that each of
# them says so. The fault count did not move — the third `not checked:` line is a new wall
# declaring itself, which is the growth this cap is meant to permit.
#
# RAISED 14 -> 15 (epic-23 wave-16, REQ-1 AC-1.8, A-T2.7), by the cap's oldest clause: it
# "tracks the scaffold's own line count by construction", and the scaffold gained the
# `Re-executes:` line. The FIXED part is now eleven — one refusal line, a blank, EIGHT
# scaffold lines, a blank, the pointer — and the variable part is unmoved at one extra
# fault plus three not-checked lines. No fault and no wall was added by that change.
expect_status "§combined …the wire is at most 15 lines (11 + 1 extra fault + 3 not-checked)" "0" \
  "$([ "$(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ')" -le 15 ] && echo 0 || echo 1)"
# AND THE THIRD LINE IS THE NEW WALL'S, NAMED — a cap raised without saying which line
# filled it is a widened tolerance, which is the mistake the comment above warns about.
expect_contains "§combined …and the line that filled it is the floor-once wall's" \
  "not checked: floor-once, needs a suite set" "$GATE_REASON"

# EACH LABEL, MARKED BY WHETHER THIS BRIEF CARRIES IT — not by which wall fired. The
# absent Files: and the absent Deliverable-waiver: lines earn ` <ADD>`; the present
# Expected duration: line is left exactly as shipped. The ambiguous Expected artifact:
# line does NOT earn one (T26, critic Issue 3) — the label was read and rejected as
# ambiguous, which is not the same fault as an empty label, and the wire's own
# `not checked: deliverable, needs one path` line (below) says so instead.
COMB_ART_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Expected artifact")"
COMB_FILES_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Files")"
COMB_DURATION_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Expected duration")"
COMB_WAIVER_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Deliverable-waiver")"
expect_absent "§combined …the still-ambiguous Expected artifact: line is NOT marked <ADD>" \
  "${COMB_ART_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …and its not-checked line names the deliverable arm instead" \
  "not checked: deliverable, needs one path" "$GATE_VERR"
expect_contains "§combined …the absent Files: line is marked <ADD>" \
  "${COMB_FILES_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …the absent Deliverable-waiver: line is marked <ADD>" \
  "${COMB_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …the present Expected duration: line is left exactly as shipped" \
  "$COMB_DURATION_LINE" "$GATE_VERR"
expect_absent "§combined …and carries no <ADD> of its own" \
  "${COMB_DURATION_LINE} <ADD>" "$GATE_VERR"
expect_contains "§combined …and closes with the pointer line" \
  "See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required." "$GATE_VERR"

# AND NOTHING WAS LAUNCHED. A refused dispatch is not a launch, however many faults it had.
expect_status "§combined …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- the second attempt, written from the first refusal's own examples ----
#
# THE WHOLE POINT, AND THE ONLY ARM THAT CAN CARRY IT. Three facts in one message are worth
# nothing if acting on all three still leaves a fault the message never mentioned. The
# examples are read back OUT of the stderr rather than typed here, so this stays true when
# the wording is next edited.
COMB_ART=$(fix_example "$GATE_VERR")
COMB_SUITES=$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -m1 -E '^Suites:' \
  | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*<ADD>[[:space:]]*$//' -e 's/[[:space:]]*$//')
expect_status "§combined the refusal really recommended an artifact path" "0" \
  "$([ -n "$COMB_ART" ] && echo 0 || echo 1)"
expect_status "§combined …and a Suites: line" "0" \
  "$([ -n "$COMB_SUITES" ] && echo 0 || echo 1)"
expect_absent "§combined …neither carrying a slot the walls themselves refuse" "<" "$COMB_ART"

REPO=$(make_repo rcomb2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: $COMB_ART
Expected duration: 20 minutes
$COMB_SUITES" "combobot2")"
expect_status "§combined attempt 2, following every scaffold-line example, PASSES" "0" "$GATE_ST"
expect_status "§combined …with the recommended path as the contract" \
  "$COMB_ART" "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"

# ---- the discriminator: declaring one field discharges that field's PAIR, and nothing else ----
#
# Without this arm a wall that printed the scaffold with every line marked unconditionally
# would pass every assertion above.
#
# RENARROWED BY WAVE-14 T26 (critic Issue 3). This arm used to declare `Suites:` against
# $BRIEF_THREE_FAULTS and check that the Files:/Suites: pair lost its <ADD> while the
# Expected artifact:/Deliverable-waiver: pair — still unresolved by an AMBIGUOUS label —
# kept theirs, on a deny wire the ambiguity finding and a separately-firing "this brief
# names no deliverable" finding kept alive together. That second finding is exactly critic
# Issue 3's contradiction (fixed above: an ambiguous label is one fault, not two), so
# $BRIEF_THREE_FAULTS with `Suites:` added now carries the ambiguity fault ALONE — the
# single-fault shape, with no scaffold on it at all (§combined a two-fault
# brief... below reads that exact fixture). What this arm can still discriminate is
# narrower and cleaner: a GENUINELY absent (non-ambiguous) deliverable is a real,
# independent fault from "no Files: and no Suites:" — declaring `Suites:` discharges only
# the second and leaves the first exactly where it was.
REPO=$(make_repo rcomb3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected duration: 20 minutes
Suites: tests/widget.test.sh" "combobot3")"
expect_eq "§combined declaring Suites: discharges the Files:/Suites: fault, leaving the other" \
  "deny" "$GATE_VERDICT"
expect_contains "§combined …the surviving fault is the genuinely absent deliverable" \
  "this brief names no deliverable" "$GATE_ERR"
expect_absent "§combined …and the Files:/Suites: fault is really gone, not merely unmarked" \
  "Files:" "$GATE_ERR$GATE_REASON"

# ---- and a ONE-fault brief is refused in its arm's own words, as it always was ----
#
# AC-1.3 from the other side: collecting must not re-word the single-fault refusal every
# other section in this file reads. One finding renders as one finding — the arm's own fact,
# its own fix, its own detail — and the user line is the one the E1.3 table pins.
REPO=$(make_repo rcomb4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "combobot4")"
expect_eq "§combined a single-fault brief keeps the arm's own line, unchanged" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_eq "§combined …and renders exactly one Fix: block" "1" \
  "$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -c '^Fix: ' || true)"

# ============================================================================
section "§scaffold-marks — the scaffold marks what the brief LACKS, not what it omits (wave-14 REQ-6, D8)"
# ============================================================================
#
# WHAT A MARK MEANS. `dp_scaffold_marked` reproduces the shipped scaffold and suffixes
# ` <ADD>` to the lines this brief still needs. Until wave-14 it asked only "did this brief
# spell this label", which is A-T2.1's literal-presence rule — and three of the scaffold's
# labels are not standalone requirements at all. The scaffold says so itself: `Files:` is
# "writers; omit for a read-only brief", `Deliverable-waiver:` is "only for a report returned
# by message". So a read-only brief that had correctly declared `Suites:` was told to add
# files it will not touch, and a brief that had declared its artifact was told to waive it —
# an instruction that, followed, would make the dispatch worse. Two of the three items on
# wave-13's walk.
#
# THE RULE (D8). `Files:` is marked only when `C_FILES` and `C_SUITES` are BOTH empty — the
# suite-allowance wall's own condition, so the mark appears exactly when that wall fires.
# `Expected artifact:` and `Deliverable-waiver:` are each marked only when `C_DELIVERABLE`
# and `C_WAIVER` are both empty — the absent-deliverable wall's own condition, and the pair
# is symmetric because either one satisfies the contract.
#
# KEYED ON THE LIFTED FIELDS, NEVER ON LITERAL LINE PRESENCE (R2 Q7). `BRIEF_THREE_FAULTS`
# below carries an `Expected artifact:` line whose span names two paths: the extractor emits
# candidates and leaves `C_DELIVERABLE` empty, so the brief HAS the label and still needs it.
# A rule keyed on the label's presence would unmark it and take (c) — and §combined's own
# pin — red.
#
# EVERY EXPECTED STRING IS READ OUT OF THE SHIPPED dispatch.md at run time, never
# transcribed, exactly as §combined does it.

SM_ART_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Expected artifact")"
SM_FILES_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Files")"
SM_SUITES_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Suites")"
SM_WAIVER_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Deliverable-waiver")"
expect_nonempty "§scaffold-marks meta: the four scaffold lines were read out of dispatch.md" \
  "${SM_ART_LINE}${SM_FILES_LINE}${SM_SUITES_LINE}${SM_WAIVER_LINE}"

# (a) AC-6.1 — A READ-ONLY BRIEF DECLARES ITS INSTRUMENT THE OTHER WAY. `Suites: none` is
# the read-only waiver, so `Files:`/`Suites:` are satisfied and must not be marked.
#
# RENARROWED BY WAVE-14 T26 (critic Issue 3). This fixture used to pair an ambiguous
# deliverable label with an empty one for a two-fault deny — the exact duplicate-counting
# bug Issue 3 names (see the §combined rewrite above for the full reasoning). With that
# collapsed to one fault, and `Suites: none` discharging the OTHER pooled arm this file has
# (no independent third arm can fire alongside a satisfied Files:/Suites: pair and a
# deliverable-field fault — every other brief-shape arm reads the same field), this brief
# is down to its single-fault shape, where `dp_scaffold_marked` never renders
# at all. What still discriminates: the refusal names ONLY the deliverable fault, and
# never so much as mentions Files:/Suites:/impact-command — proving the pair was read as
# satisfied rather than merely unmarked on a wire this fixture can no longer reach.
REPO=$(make_repo rsm-readonly yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected duration: 20 minutes
Suites: none" "smbot1")"
expect_eq "§scaffold-marks (a) the read-only brief refuses on its own single-arm wire" \
  "deny" "$GATE_VERDICT"
expect_contains "§scaffold-marks (a) …naming the absent deliverable" \
  "this brief names no deliverable" "$GATE_ERR"
expect_absent "§scaffold-marks (a) …and never mentioning Files: — Suites: none satisfied it" \
  "Files:" "$GATE_ERR$GATE_REASON"
expect_absent "§scaffold-marks (a) …nor Suites: — it was declared, not missing" \
  "no impact command" "$GATE_ERR$GATE_REASON"

# (b) AC-6.2 — A DECLARED ARTIFACT SATISFIES THE WAIVER'S HALF OF THE PAIR. The deliverable
# resolves outside the repo and the brief declares no instrument: two faults, and a
# `C_DELIVERABLE` that is non-empty. Nothing here needs a waiver.
REPO=$(make_repo rsm-artifact yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: ../../../../../../etc/hosts
Expected duration: ~15 minutes." "smbot2")"
expect_status "§scaffold-marks (b) the artifact-bearing brief refuses on the several-fault wire" "0" \
  "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_absent "§scaffold-marks (b) …and the Deliverable-waiver: line is NOT marked beside a declared artifact" \
  "${SM_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (b) …the Deliverable-waiver: line is still rendered, as shipped" \
  "$SM_WAIVER_LINE" "$GATE_VERR"
expect_absent "§scaffold-marks (b) …nor is the declared Expected artifact: line marked" \
  "${SM_ART_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (b) …while the absent Files: line IS marked (no instrument either way)" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"

# (c) AC-6.2, THE OTHER DIRECTION. A declared waiver satisfies the artifact's half of the
# same pair: the brief reports by message, so `Expected artifact:` is not something it
# lacks. Its two faults are the ambiguous label and the missing instrument — the
# absent-deliverable wall is waived, which is what the waiver is for.
REPO=$(make_repo rsm-waiver yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Deliverable-waiver: nothing durable — this dispatch reports by message
Expected duration: 20 minutes" "smbot3")"
expect_status "§scaffold-marks (c) the waived brief refuses on the several-fault wire" "0" \
  "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_absent "§scaffold-marks (c) …and the Expected artifact: line is NOT marked beside a declared waiver" \
  "${SM_ART_LINE} <ADD>" "$GATE_VERR"
expect_absent "§scaffold-marks (c) …nor is the declared Deliverable-waiver: line marked" \
  "${SM_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (c) …while the absent Files: line IS marked" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"

# (d) AC-6.3 — NEITHER INSTRUMENT DECLARED, BOTH THOSE LINES MARKED. `BRIEF_THREE_FAULTS`
# is §combined's own fixture: `Files:`/`Suites:` are both absent (marked), and
# `Deliverable-waiver:` is absent too (marked). `Expected artifact:` is NOT marked (T26,
# critic Issue 3) — the label was read and rejected as ambiguous, which `dp_scaffold_marked`
# now treats as a populated-but-unresolved label rather than an empty one; the wire's
# `not checked: deliverable, needs one path` line (§combined above) is where that reads.
REPO=$(make_repo rsm-both yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "smbot4")"
expect_status "§scaffold-marks (d) the three-fault brief refuses on the several-fault wire" "0" \
  "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_absent "§scaffold-marks (d) the still-ambiguous Expected artifact: line is NOT marked" \
  "${SM_ART_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (d) both absent -> the Deliverable-waiver: line is marked" \
  "${SM_WAIVER_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (d) neither instrument -> the Files: line is marked" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"
expect_contains "§scaffold-marks (d) neither instrument -> the Suites: line is marked" \
  "${SM_SUITES_LINE} <ADD>" "$GATE_VERR"
# ============================================================================
section "§combined-deny — the combined refusal reaches the MODEL (wave-12 T17, AC-1.1)"
# ============================================================================
#
# WHAT T2 LEFT OPEN (its finding A-T2.2; ruling A-orch-10, 2026-09-13). The five brief-shape
# arms already collect into ONE refusal — and it went out on `exit2`, where refuse.sh's
# channel table ships `detail_to_user=no` under ruling D-1 AND there is only one wire: what
# the user stream carries is what the model's synthetic tool_result carries. So the author
# read one sentence and THE MODEL READ THE SAME ONE SENTENCE. The findings list existed and
# no dispatching model ever saw it, which is the six-attempt loop of 2026-09-13 still
# running behind a better-built wall.
#
# WHAT THIS PINS. The combined refusal goes out on `deny`: a PreToolUse verdict on STDOUT
# whose `permissionDecisionReason` the same measurement proved reaches the model verbatim
# (`model_only=yes`), with exit 0 because the JSON is the block rather than the status. D-1
# is NOT reversed — the human still gets exactly one line on stderr — and the knob is not
# involved anywhere below: these arms run with BIONIC_WALL_VERBOSE unset, which is the state
# a real dispatch runs in.
#
# THE ARM THAT CARRIES THE CLAIM is the last one: attempt two is written from the examples
# read back out of the MODEL'S OWN WIRE, `permissionDecisionReason`, and must dispatch. Three
# facts on a channel the model reads are worth nothing if acting on all three still leaves a
# fault the message never named.
#
# fails-when: the three-fault brief exits 2; or its stdout is not one parseable deny verdict;
# or the reason names fewer than three facts or carries fewer than three `Fix:` blocks; or
# the human's one line grows a detail behind it; or the single-fault brief leaves on a
# different wire (wave-19 T4, REQ-7, D8 — until then this clause read the other way).

expect_empty "§combined-deny the verbose knob is UNSET for every arm here" "${BIONIC_WALL_VERBOSE:-}"

REPO=$(make_repo rcombdeny yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "denybot")"

expect_status "§combined-deny a three-fault brief exits 0 — the verdict is the block" \
  "0" "$GATE_ST"
expect_eq "§combined-deny …and the verdict is a deny, not an allow" "deny" "$GATE_VERDICT"
expect_eq "§combined-deny …stdout is ONE object and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_eq "§combined-deny …naming the PreToolUse event it answers" "PreToolUse" \
  "$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null || echo PARSE-FAILED)"
expect_eq "§combined-deny …with permissionDecision=deny" "deny" \
  "$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || echo PARSE-FAILED)"

# THE REASON IS THE MODEL'S WIRE. Every assertion below reads `$GATE_REASON`, which the
# driver parsed out of the JSON with `jq` — so an escaper that broke on the findings list's
# newlines reads EMPTY here rather than passing on a grep of the raw bytes.
expect_eq "§combined-deny the reason opens with the refusal's one line" \
  "bionic: dispatch refused — the deliverable label names several paths (name exactly one deliverable)" \
  "$(printf '%s\n' "$GATE_REASON" | sed -n '1p')"
# NO RATIONALE ON THE MODEL'S WIRE EITHER (T2, D3/D11) — the marked scaffold replaces it,
# read live out of $DISPATCH_FILE, the same way §combined checks GATE_VERR.
expect_absent "§combined-deny …no fault-count header sentence" "SHAPE FAULTS" "$GATE_REASON"
expect_absent "§combined-deny …no per-fault '── N.' heading" "── " "$GATE_REASON"
expect_absent "§combined-deny …no Fix: block" "Fix: " "$GATE_REASON"
expect_absent "§combined-deny …the still-ambiguous Expected artifact: line is NOT marked <ADD>" \
  "${COMB_ART_LINE} <ADD>" "$GATE_REASON"
expect_contains "§combined-deny …and its not-checked line names the deliverable arm instead" \
  "not checked: deliverable, needs one path" "$GATE_REASON"
expect_contains "§combined-deny …the absent Files: line is marked <ADD>" \
  "${COMB_FILES_LINE} <ADD>" "$GATE_REASON"
expect_contains "§combined-deny …the present Expected duration: line is left exactly as shipped" \
  "$COMB_DURATION_LINE" "$GATE_REASON"
expect_contains "§combined-deny …and closes with the pointer line" \
  "See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required." "$GATE_REASON"

# AND THE HUMAN IS STILL INTERRUPTED BY ONE SENTENCE (ruling D-1). The split is the whole
# reason this channel was chosen over flipping `detail_to_user`: the model reads everything,
# the reader reads one line, and neither is a setting.
expect_eq "§combined-deny the user stream carries exactly one refusal line" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_eq "§combined-deny …the first arm's own sentence, unchanged" \
  "bionic: dispatch refused — the deliverable label names several paths (name exactly one deliverable)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_absent "§combined-deny …with no findings list behind it" "Fix: " "$GATE_ERR"
expect_absent "§combined-deny …and no count header either" "SHAPE FAULTS" "$GATE_ERR"

# NOTHING WAS LAUNCHED. A deny exits 0, which is the one status a wall must never let mean
# "allowed" by accident: the roster is where that would show.
expect_status "§combined-deny …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- the discriminator, INVERTED: a ONE-fault brief takes the same deny wire ----
#
# CHANGED, WITH ATTRIBUTION (wave-19 T4, REQ-7, D8). This arm used to pin the opposite: that
# a single fault stayed on exit2 with an empty stdout, so a change moving every refusal to
# `deny` would red here. Two statuses for one kind of refusal was the defect REQ-7 names —
# a fixture's status depended on how many faults its ENVIRONMENT added (A-T4.8). What the
# arm still protects is the single fault's own SHAPE: its arm's line, unchanged, on the
# user stream, and its arm's own detail — not the pooled list — on the model's wire.
REPO=$(make_repo rcombdeny2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "denybot2")"
expect_eq "§combined-deny a single-fault brief refuses on the same deny wire" "deny" "$GATE_VERDICT"
expect_status "§combined-deny …exiting 0, the verdict being the block" "0" "$GATE_ST"
expect_eq "§combined-deny …stdout is ONE verdict and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_absent "§combined-deny …carrying its arm's own detail, not the pooled scaffold" \
  "See skills/canonical-sdlc/dispatch.md §Dispatch" "$GATE_REASON"
expect_eq "§combined-deny …with its arm's own line, unchanged" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"

# ---- and a LONE refusal is not on the JSON channel either, whatever arm it came from ----
#
# CHANGED, WITH ATTRIBUTION (wave-14 T6, REQ-8/D3, A-T6.4). This arm used to drive
# `BRIEF_THREE_FAULTS` with the Patrol unarmed and assert exit2, on wave-12's reading that
# the channel tracks "a list of BRIEF faults" and a state fault is a different kind of
# thing. REQ-8 overturns that reading: the arming wall now pools with the rest, so that
# fixture carries FOUR faults and the several-fault wire is where all four belong — the
# whole point being that the model reads them in one pass. What the arm was really
# protecting is that a LONE fault keeps its arm's own sentence, its own `exit2` and an empty
# stdout, and that claim is stronger when the lone fault is a STATE one, so that is what it
# drives now: a clean brief whose only defect is the unarmed Patrol. Since wave-19 T4
# (REQ-7, D8) that lone fault's WIRE is the deny verdict too; its sentence is still its own.
REPO=$(make_repo rcombdeny3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "denybot3")"
expect_eq "§combined-deny a LONE state fault (the unarmed Patrol) takes the deny wire too" \
  "deny" "$GATE_VERDICT"
expect_eq "§combined-deny …and prints ONE verdict on stdout" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_contains "§combined-deny …refusing for the state, in the arming wall's own words" \
  "Patrol" "$GATE_ERR$GATE_VERR"

# THE PAIRED CONTROL, and it is the half REQ-8 added: the SAME unarmed Patrol beside brief
# faults is one refusal on the model's wire, naming both kinds. Without this row the arm
# above reads as "state refusals never reach the deny channel", which is what stopped being
# true.
REPO=$(make_repo rcombdeny3b yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "denybot3b")"
expect_eq "§combined-deny the same state fault BESIDE brief faults refuses once, on deny" \
  "deny" "$GATE_VERDICT"
expect_eq "§combined-deny …with exactly one refusal line on the user stream" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_contains "§combined-deny …the model's wire naming the state fault" \
  "no Patrol stamp exists for this session" "$GATE_REASON"
expect_contains "§combined-deny …and a brief fault beside it" \
  "this brief declares no Files: and no Suites:" "$GATE_REASON"

# ---- the claim: attempt two, written from the MODEL'S wire, dispatches ----
REPO=$(make_repo rcombdeny4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_THREE_FAULTS" "denybot4")"
DENY_ART=$(fix_example "$GATE_REASON")
DENY_SUITES=$(printf '%s\n' "$GATE_REASON" | /usr/bin/grep -m1 -E '^Suites:' \
  | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*<ADD>[[:space:]]*$//' -e 's/[[:space:]]*$//')
expect_status "§combined-deny the reason really recommended an artifact path" "0" \
  "$([ -n "$DENY_ART" ] && echo 0 || echo 1)"
expect_status "§combined-deny …and a Suites: line" "0" \
  "$([ -n "$DENY_SUITES" ] && echo 0 || echo 1)"
expect_absent "§combined-deny …neither carrying a slot the walls themselves refuse" "<" "$DENY_ART"

REPO=$(make_repo rcombdeny5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: $DENY_ART
Expected duration: 20 minutes
$DENY_SUITES" "denybot5")"
expect_eq "§combined-deny attempt 2, from the reason alone, is ALLOWED" "allow" "$GATE_VERDICT"
expect_status "§combined-deny …and the recommended path is the contract on the row" \
  "$DENY_ART" "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"


# ============================================================================
section "§scaffold-verbatim — the shipped brief scaffold dispatches as written (AC-2.2)"
# ============================================================================
#
# WHAT THIS PINS. `agents-src/blocks/brief-scaffold.md` renders into seven surfaces, one of
# which is skills/canonical-sdlc/dispatch.md; an orchestrator writes its brief by filling
# that block in. A scaffold whose filled form the gate refuses teaches the wrong grammar to
# every dispatch in the tree, and nothing but a drive can tell you which it is.
#
# THE BLOCK IS READ OUT OF THE SHIPPED FILE, never transcribed here: a copy in this suite
# would go on passing after the source drifted, which is the exact failure this pins against.
# Only two things are done to it — the trailing `  # …` annotations are stripped (they are
# guidance to the author, not brief text) and each `<placeholder>` span is replaced with a
# real value, keeping the label spelling and the surrounding text the file wrote.
#
# fails-when: the rendered scaffold, filled in, is refused by the gate it is written for.

SCAFFOLD_FILE="$DISPATCH_FILE"

# scaffold_block is defined earlier in this file (beside fix_example, ~line 2440), shared
# with §combined/§combined-deny — not redefined here. Both it and scaffold_fill below read
# the file named by $SCAFFOLD_FILE, reassigned for the SKILL.md second pass further down.

scaffold_fill() {  # <suites|files> -> the scaffold as a brief, placeholders filled
  local mode="$1" line label value
  printf 'Your task: build the widget.\n'
  while IFS= read -r line; do
    line="${line%%  #*}"
    line="$(printf '%s' "$line" | sed 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    label="${line%%:*}"
    case "$label" in
      "Deliverable-waiver") continue ;;
      "Files")  [ "$mode" = "files" ]  || continue ;;
      "Suites") [ "$mode" = "suites" ] || continue ;;
    esac
    case "$label" in
      "Expected duration") value="20" ;;
      "Expected artifact") value=".bionic/docs/record/w99-scaffold.md" ;;
      "Progress artifact") value=".bionic/docs/record/w99-scaffold.progress" ;;
      "Cadence")           value="15" ;;
      "Files")             value="payload/scripts/lib/widget.sh" ;;
      "Suites")            value="none" ;;
      *)                   value="" ;;
    esac
    case "$line" in
      *"<"*">"*) line="${line%%<*}${value}${line##*>}" ;;
    esac
    printf '%s\n' "$line"
  done < <(scaffold_block "$SCAFFOLD_FILE")
}

# ANTI-VACUITY FIRST: a block that could not be found would make every drive below a drive
# of the two lines this helper prepends, and they would pass.
SCAFFOLD_RAW="$(scaffold_block "$SCAFFOLD_FILE")"
expect_status "§scaffold the shipped dispatch.md really carries a fenced scaffold" "0" \
  "$([ "$(printf '%s\n' "$SCAFFOLD_RAW" | /usr/bin/grep -c .)" -ge 3 ] && echo 0 || echo 1)"
expect_contains "§scaffold …carrying the deliverable label the gate reads" \
  "Expected artifact:" "$SCAFFOLD_RAW"

SCAFFOLD_SUITES="$(scaffold_fill suites)"
SCAFFOLD_FILES="$(scaffold_fill files)"
expect_absent "§scaffold the filled brief leaves no placeholder behind" "<" "$SCAFFOLD_SUITES"
expect_absent "§scaffold …in either variant" "<" "$SCAFFOLD_FILES"
expect_contains "§scaffold …and still spells the labels the way the file does" \
  "Expected artifact: .bionic/docs/record/" "$SCAFFOLD_SUITES"

# ---- variant 1: the waiver form of the instrument line ----
REPO=$(make_repo rscaff1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_SUITES" "scaffoldbot1")"
expect_status "§scaffold the rendered scaffold, filled in, DISPATCHES" "0" "$GATE_ST"
expect_status "§scaffold …with the named artifact as the contract" \
  ".bionic/docs/record/w99-scaffold.md" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"

# T17 (R6 finding 3, A-orch-36 walk item 2): a brief built strictly from the scaffold used to
# warn "absent brief field(s): … progress" by construction, because the shipped block had no
# `Progress artifact:`/`Cadence:` line to fill in. The scaffold now carries both, so the
# filled brief leaves nothing absent and the roster row records both fields.
expect_absent "§scaffold …and prints no absent-field warning naming progress (T17)" \
  "absent brief field(s)" "$GATE_ERR"
expect_status "§scaffold …the roster row's progress artifact is filled (T17)" \
  ".bionic/docs/record/w99-scaffold.progress" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" progress)"
expect_status "§scaffold …and its cadence is filled alongside it (T17)" \
  "15 min" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" cadence)"

# ---- variant 2: the `Files:` form, where a derivation exists to consume it ----
REPO=$(make_repo rscaff2 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_FILES" "scaffoldbot2")"
expect_status "§scaffold the Files: variant DISPATCHES where a derivation is configured" \
  "0" "$GATE_ST"
expect_status "§scaffold …and the budget is the derived one" "widget.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# ---- the discriminator: the scaffold UNFILLED is refused ----
#
# So "it dispatches" is a fact about the filling, not about a gate that waves anything
# carrying the right labels through.
REPO=$(make_repo rscaff3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build the widget.
$SCAFFOLD_RAW" "scaffoldbot3")"
# T23 (review R1): the scaffold's own `Suites: none   # read-only brief; …` comment is no
# longer read as a span of dropped suites, so the unfilled scaffold is once again refused
# for its REAL fault — its deliverable is an unfilled `<…>` slot, which is one fault, which
# is the exit-2 channel (task 12/T17's rule: one fault exits 2, several deny). T6 had
# weakened this to `expect_ne allow` when the comment added a second fault; the channel is
# pinned again, because a channel nobody pins is a channel that drifts.
expect_eq "§scaffold the scaffold with its placeholders still in it is REFUSED" \
  "deny" "$GATE_VERDICT"

# ---- the SECOND home: SKILL.md carries the same scaffold, injected (T2, AC-2.2/AC-2.3) ----
#
# `SKILL.md.tmpl` gained its own `<!-- INJECT: brief-scaffold -->` beside the
# dispatch-pointer sentence, so an orchestrator who never opens dispatch.md still meets a
# fillable scaffold on the page it reads every Step-4 dispatch from. Same drives, same
# extractor, a different file — proof the second copy is byte-identical in shape, not just
# present (docs-pins.test.sh's 131/131b pin presence; this pins that it DISPATCHES).
SCAFFOLD_FILE="${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"

SCAFFOLD_RAW="$(scaffold_block "$SCAFFOLD_FILE")"
expect_status "§scaffold …and SKILL.md's own copy really carries a fenced scaffold" "0" \
  "$([ "$(printf '%s\n' "$SCAFFOLD_RAW" | /usr/bin/grep -c .)" -ge 3 ] && echo 0 || echo 1)"

SCAFFOLD_SUITES="$(scaffold_fill suites)"

REPO=$(make_repo rscaff4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$SCAFFOLD_SUITES" "scaffoldbot4")"
expect_status "§scaffold …SKILL.md's rendered scaffold, filled in, DISPATCHES" "0" "$GATE_ST"
expect_status "§scaffold …with the named artifact as the contract" \
  ".bionic/docs/record/w99-scaffold.md" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"

REPO=$(make_repo rscaff5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build the widget.
$SCAFFOLD_RAW" "scaffoldbot5")"
# T23 (review R1): as the dispatch.md variant above — the comment is no longer a drop, the
# one remaining fault is the unfilled deliverable slot, and the exit-2 channel is pinned.
expect_eq "§scaffold …SKILL.md's scaffold, unfilled, is REFUSED the same way" \
  "deny" "$GATE_VERDICT"

# ============================================================================
section "§a3-text — the Patrol stamp is armed at engagement, not by hand (D4, REQ-3)"
# ============================================================================
#
# WHY THE TEXT MOVED. Until this wave the A3 refusal handed the model a two-step re-arm and
# step 2 was `session-poker.sh arm` — a command the operator was expected to type after
# engaging. hooks/engage.sh now runs it itself, with the session id and the project root it
# already holds, right after writing the engagement marker (T4, spec D4). A refusal that
# still ordered the hand step would be instructing the model to do the machine's work, which
# is principle P-A read at its own wall.
#
# THE ARM ITSELF IS UNCHANGED — an absent stamp still refuses, in the same words, and still
# names the CronCreate half, which IS the model's step: engagement writes the stamp, nothing
# but the model can create the recurring job that keeps writing it.
#
# fails-when: the never-armed refusal still names `session-poker.sh arm` as a step to run,
# or stops naming engagement as what writes the stamp.

REPO=$(make_repo ra3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§a3 an absent stamp still refuses the dispatch" "deny" "$GATE_VERDICT"
expect_contains "§a3 …in the same words as before" \
  "bionic: dispatch refused — no Patrol stamp exists for this session" "$GATE_ERR"
expect_contains "§a3 …and the fix names engagement as what writes the stamp" \
  "engage" "$GATE_VERR"
expect_absent "§a3 …and no longer orders the hand-run arm" \
  "session-poker.sh arm" "$GATE_VERR"
expect_contains "§a3 …while still naming the one half the model owns" "CronCreate" "$GATE_VERR"

# THE PAIRED ARM, and the anti-vacuity one. A4 (armed, then stopped firing) is a different
# finding with a different remedy — the clock died, the stamp did not — and it keeps both
# halves. It also proves the absence above is a fact about A3's text rather than about a
# string this suite can no longer produce at all.
REPO=$(make_repo ra3b yes)
write_attestation "$REPO" "$SID_A"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000
run_gate "$(s21_stale_payload "$SID_A" "$REPO")"
expect_eq "§a3 the STALE arm is untouched by the A3 rewording" "deny" "$GATE_VERDICT"
expect_contains "§a3 …still naming the armed-but-dead state" "stopped firing" "$GATE_ERR"
expect_contains "§a3 …and still offering the hand re-arm, which is A4's remedy" \
  "session-poker.sh arm" "$GATE_VERR"

# ======================== §T22-name-in-flight: A NAME IN FLIGHT IS REFUSED AT DISPATCH
# (T22, A-orch-33; AC-4.4's prevention half.)
#
# THE ROSTER IS THE IDENTITY REGISTER. Two agents of one name in one session is the
# condition every downstream ambiguity was built to survive: the stop gate carried a whole
# arm for it ("several live agents answer to that name"), and a message addressed to a name
# that resolves to two agents reaches the wrong one. The cure is at the door — a name with
# an OPEN row on THIS session's roster is not available, and the FILL line already names a
# free one.
#
# OPEN IS A ROSTER-AND-LEDGER READING (P-A; wave-19 T4, D1, ADR-034; epic-23 wave-20 T2,
# D10). `intended`, `confirmed` and `identified` are open; a name is free again only when a
# sweeper-ledger ack LATER than its last launch closes it — `roster_open_names`, the one
# close predicate every reader calls. A `landing-swept/v1|…|state=MET` marker closes nothing
# (it did here until wave-20, and nowhere else agreed). No transcript, no live set, no tool call: every fixture below leaves the transcript
# in the `none` state deliberately, so a gate that reached for an answer would refuse the
# control rows too.

section "§T22-name-in-flight: a dispatch cannot reuse a name that is still open"

T22NF_NONE="$SANDBOX/.t22nf-none.jsonl"
mk_transcript "$T22NF_NONE" none

# (a) THE REFUSAL. One open `intended` row named `T5`; a dispatch that names `T5` again.
REPO=$(make_repo t22nfa yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfa a name with an open intended row is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the fix points at the FILL line" "use the FILL line's name" "$GATE_ERR"
expect_contains "…and the detail names the name and its status" "T5" "$GATE_VERR"

# (b) A CONFIRMED ROW IS OPEN TOO. The three live statuses are one class here.
REPO=$(make_repo t22nfb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
roster_row_no_plan status=confirmed "session=$SID_A" name=T6 agent_id=aT6-1111111111111111 \
  launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T6 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T6 >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T6" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfb a name with an open confirmed row is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the same fact" "that name is in flight" "$GATE_ERR"

# (c) AN IDENTIFIED ROW IS OPEN TOO.
REPO=$(make_repo t22nfc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
roster_row_no_plan status=identified "session=$SID_A" name=T7 agent_id=aT7-2222222222222222 \
  launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T7 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T7 >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T7" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfc a name with an open identified row is REFUSED" "deny" "$GATE_VERDICT"

# (d) THE CONTROL THAT MAKES IT A RULE AND NOT A BAN. The SAME roster, the SAME transcript,
# a DIFFERENT name: allowed. A gate that refused every dispatch once a roster existed would
# pass (a)-(c) and fail here.
REPO=$(make_repo t22nfd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5-r2" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfd the name the FILL line would derive instead is ALLOWED" "0" "$GATE_ST"
expect_absent "…and nothing is said about a name in flight" "in flight" "$GATE_ERR"

# (e) A MET MARKER DOES NOT FREE A NAME (epic-23 wave-20 T2, REQ-10 AC-10.1, D10). Until this
# wave the marker alone freed it here, while the sweeper and the stop wall still counted the
# row open — the MET-not-acked half of triage-C claim 4. The marker records that a landing was
# seen; the agent behind it may still be on the panel. REFUSED.
REPO=$(make_repo t22nfe yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T8"
s22_sweep "$REPO" "$SID_A" "T8"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T8" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfe a name with a MET marker and no ack is still in flight: REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
# (e2) …and the ack, once written, frees it: the same roster, one ack's difference.
s22_ack "$REPO" "$SID_A" "T8"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T8" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfe2 the same name, acked after its launch, is free to dispatch again" "0" "$GATE_ST"
expect_absent "…and no in-flight refusal" "in flight" "$GATE_ERR"

# (f) ANOTHER SESSION'S ROSTER IS NOT THIS ONE'S REGISTER. The row is planted under SID_B;
# SID_A dispatches the same name and is allowed. Names are unique per SESSION, which is the
# scope every other roster reader in the fleet already uses.
REPO=$(make_repo t22nff yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_B" "T9"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T9" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nff a predecessor session's row does not reserve the name here" "0" "$GATE_ST"

# (g) AN UNNAMED DISPATCH IS NOT JUDGED BY THIS ARM AT ALL — there is no name to be in
# flight, and an arm that refused one would break every unnamed async dispatch in the fleet.
REPO=$(make_repo t22nfg yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "-" "claude-sonnet-5" "$T22NF_NONE")"
expect_absent "t22nfg an unnamed dispatch is never refused for a name in flight" \
  "in flight" "$GATE_ERR"

# (h) THE LANDED-THEN-RELAUNCHED NAME — the case the arm was built for and missed
# (delta review C1/S2). `T5` runs, lands, and its MET marker frees the name; the SAME name
# is then dispatched again (which (e) proves is allowed) and that second lineage reaches
# `identified`. A THIRD dispatch under `T5` while that lineage is live must be refused.
#
# WHY IT NEEDS ITS OWN CASE. `met` was a file-global flag set by ANY marker for the name,
# so one landing turned the arm off for that name for the rest of the session — and (e)'s
# fixture, which stops at the marker, cannot tell a position-blind reading from a
# position-aware one. The rule is that the LATEST contract decides: a marker older than the
# newest intended/confirmed/identified row of that name does not close it.
REPO=$(make_repo t22nfh yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T5"
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-1111111111111111 \
  launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T5 >> "$(roster_path "$REPO" "$SID_A")"
s22_sweep "$REPO" "$SID_A" "T5"
# …the relaunch: a fresh contract for the same name, AFTER the marker.
s22_roster_row "$REPO" "$SID_A" "T5"
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-2222222222222222 \
  launched_at=2026-09-02T01:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T5b >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfh a name RELAUNCHED after its MET marker is in flight again: REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the status it names is the LATEST row's, not the first lineage's" \
  "identified" "$GATE_VERR"

# (i) THE PAIRED CONTROL — the same shape, with the relaunch closed by an ack taken AFTER
# it launched (2026-09-02T02:00Z). The latest contract is closed, so the name is free again.
# An arm that never freed a name once it had been open would pass (h) and fail here. (Until
# epic-23 wave-20 T2 the close here was the relaunch's own MET marker; a marker closes
# nothing now, D10, and the marker is kept to show it.)
REPO=$(make_repo t22nfi yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T5"
s22_sweep "$REPO" "$SID_A" "T5"
s22_roster_row "$REPO" "$SID_A" "T5"
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-3333333333333333 \
  launched_at=2026-09-02T01:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T5c >> "$(roster_path "$REPO" "$SID_A")"
s22_sweep "$REPO" "$SID_A" "T5"
s22_ack "$REPO" "$SID_A" "T5" 2026-09-02T02:00:00Z
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfi a relaunch closed by an ack after it launched frees the name again" "0" "$GATE_ST"
expect_absent "…and no in-flight refusal" "in flight" "$GATE_ERR"

# (j) ADOPTION RE-OPENS A NAME THIS SESSION HAD LANDED — deliberate, and nothing drove it
# (delta review S1; A-T26.2). `contract_note` retires a MET marker on ANY live row of the name
# that follows it, whatever `session=` that row carries — symmetrical with how the marker is
# set, and the reading (h) needs. Its consequence is the case below: `session-poker.sh`'s
# `adopt_write_row` journals a PREDECESSOR session's agent onto THIS session's roster as
# `status=identified` with `adopted_from=`, so a session that ran and landed a `T5` of its own
# and then adopts a predecessor's `T5` has a live `T5` row again, and the next dispatch under
# that name is refused. The refusal is true on its own terms — this register does carry an
# open row of the name — and (j2) is the way out.
REPO=$(make_repo t22nfj yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T5"
s22_sweep "$REPO" "$SID_A" "T5"
# The ADOPT-SHAPED row, and the one field that separates it from (h)'s ordinary relaunch:
# `adopted_from=` naming the session that launched the agent this one took over.
roster_row_no_plan status=identified "session=$SID_A" name=T5 agent_id=aT5-4444444444444444 \
  launched_at=2026-09-02T01:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T5 source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= "adopted_from=$SID_B" tool_use_id=t-T5d \
  >> "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfj an ADOPTED live row re-opens a name this session had landed: REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…naming the same fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the status it names is the adopted row's" "identified" "$GATE_VERR"

# (j2) THE PAIRED CONTROL, and the recovery — the ACK, the one close since epic-23 wave-20 T2
# (D10; it was the landing marker until then). Acking the adopted row after its launch frees
# the name, exactly as (e2) and (i) free an ordinary one — and without this row (j) is green
# on a wall that refuses the name forever.
s22_ack "$REPO" "$SID_A" "T5" 2026-09-02T02:00:00Z
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T5" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfj2 acking the adopted row frees the name again" "0" "$GATE_ST"
expect_absent "…and no in-flight refusal is left" "in flight" "$GATE_ERR"

# (k) A POST-LAUNCH ACK FREES THE NAME (wave-19 T4, REQ-1 AC-1.4, D1; ADR-034).
#
# CHANGED, WITH ATTRIBUTION. Wave-14 T16 drove the opposite here: this arm passed no ack
# ledger to `dp_roster_contracts`, on the premise that an ack was the orchestrator's
# judgement about a DELIVERABLE and could precede the agent leaving. ADR-034 retires that
# premise — the ack is the ONE terminal state of a name, the Patrol writes it only when a
# fresh panel confirms the agent gone, and `stop-orders.sh stopped` writes it beside the
# stop — so this arm now reads the same ledger the budget wall reads (r22mkd), and one
# question has one answer. `ack_closes`'s time test is kept: the ack must be LATER than the
# name's last launch.
#
# fails-when: a dispatch under a name acked after its last launch is refused, or one acked
# before its last launch is admitted (AC-1.4) — (k) is the first half, (l) the second.
REPO=$(make_repo t22nfk yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T16-k"
s22_ack "$REPO" "$SID_A" "T16-k"
# META, and the anti-vacuity arm: the ack really is on the ledger, under the schema its WRITER
# declares (s22_ack reads `LEDGER_SCHEMA` out of hooks/session-sweeper.sh), and it postdates the
# launch stamp `s22_roster_row` wrote — so (k) below is green because the arm READ it, never
# because the fixture wrote a row no reader counts as open (the refusal (l) proves it is).
expect_contains "t22nfk meta: the ack is on the sweeper's ledger, for this name" \
  "name=T16-k" "$(cat "$REPO/.bionic/tmp/sweeper-$SID_A.state")"
expect_contains "t22nfk meta: …and it postdates the row's launched_at" \
  "at=2026-09-03T00:00:00Z" "$(cat "$REPO/.bionic/tmp/sweeper-$SID_A.state")"
expect_contains "t22nfk meta: …and that launch is 2026-09-02" \
  "launched_at=2026-09-02T00:00:00Z" "$(cat "$(roster_path "$REPO" "$SID_A")")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T16-k" "claude-sonnet-5" "$T22NF_NONE")"
expect_status "t22nfk a name acked AFTER its last launch is free: ADMITTED" "0" "$GATE_ST"
expect_eq "t22nfk …on no deny verdict either" "allow" "$GATE_VERDICT"
expect_absent "…and no in-flight refusal" "in flight" "$GATE_ERR$GATE_REASON"

# (l) THE PAIRED CONTROL — AN ACK OLDER THAN THE LAST LAUNCH FREES NOTHING. The same name
# was acked (2026-09-03), then RELAUNCHED (2026-09-04) and that lineage is live. The ack
# predates the live launch, so `ack_closes` declines it and the name is in flight — without
# this row, (k) is green on an arm that frees a name on ANY ack, including the stale one a
# relaunched agent sits behind.
REPO=$(make_repo t22nfl yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "T16-l"
s22_ack "$REPO" "$SID_A" "T16-l"
roster_row_no_plan status=identified "session=$SID_A" name=T16-l agent_id=aT16l-111111111111 \
  launched_at=2026-09-04T00:00:00Z subagent_type=implementor model= \
  deliverable=/tmp/d-T16-l source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= tool_use_id=t-T16-l2 >> "$(roster_path "$REPO" "$SID_A")"
expect_contains "t22nfl meta: the ack is on the ledger at 2026-09-03" \
  "at=2026-09-03T00:00:00Z" "$(cat "$REPO/.bionic/tmp/sweeper-$SID_A.state")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "T16-l" "claude-sonnet-5" "$T22NF_NONE")"
expect_eq "t22nfl a name acked BEFORE its last launch is still REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the fact" "that name is in flight" "$GATE_ERR"
expect_contains "…and the status it names is the relaunch's" "identified" "$GATE_VERR"

section "§one-wire — one exit status for every brief/state refusal, whatever the fault count (wave-19 T4, REQ-7, D8)"
# ============================================================================
#
# THE DEFECT (ideas row 4; A-T4.8; research R3 Q1). `dp_refuse_findings` sent ONE finding out
# on `refuse exit2` (status 2) and SEVERAL on `refuse deny` (status 0 with a deny verdict), so
# a refusal's exit status depended on its fault count — and a fixture's fault count depends
# on its ENVIRONMENT as well as its brief: with no `impact-command:` in .bionic/config.yaml a
# `Files:` brief picks up a second fault silently (dispatch-preflight.sh, the no-impact arm).
# Both rows below therefore pin the config, so each carries exactly the faults it names.
#
# fails-when (AC-7.1): the two-fault brief exits 2 or names one fault, or its one-fault
# control leaves on a different wire. (AC-7.2): this two-fault row is absent.
#
# THE TWO-FAULT ROW: no deliverable, and no Files:/Suites: at all.
REPO=$(make_repo r1wire2 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" "tests/widget.test.sh"
expect_contains "1wire2 meta: the impact command is configured" "impact-command:" \
  "$(cat "$REPO/.bionic/config.yaml")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes." "w1wire2")"
expect_status "1wire2 a TWO-fault brief exits 0 — the verdict is the block" "0" "$GATE_ST"
expect_eq "1wire2 …with a deny verdict" "deny" "$GATE_VERDICT"
expect_contains "1wire2 …whose reason names the first fault" \
  "this brief names no deliverable" "$GATE_REASON"
expect_contains "1wire2 …and the second" \
  "this brief declares no Files: and no Suites:" "$GATE_REASON"
expect_status "1wire2 …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# THE ONE-FAULT CONTROL: the SAME brief plus a `Files:` line the configured impact command
# answers for, so the deliverable fault is the ONLY one. Same status, same verdict.
REPO=$(make_repo r1wire1 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" "tests/widget.test.sh"
expect_contains "1wire1 meta: the impact command is configured" "impact-command:" \
  "$(cat "$REPO/.bionic/config.yaml")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Files: payload/scripts/lib/widget.sh" "w1wire1")"
expect_status "1wire1 a ONE-fault brief exits 0 too — the same wire" "0" "$GATE_ST"
expect_eq "1wire1 …with a deny verdict" "deny" "$GATE_VERDICT"
expect_contains "1wire1 …naming its one fault" "this brief names no deliverable" "$GATE_REASON"
expect_absent "1wire1 …and only that one: the Files: line satisfied the instrument arm" \
  "no Files: and no Suites:" "$GATE_REASON"
expect_absent "1wire1 …nor did a missing impact command add one" \
  "no impact command is configured" "$GATE_REASON"
expect_eq "1wire1 …the user stream is still ONE sentence" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_status "1wire1 …and journals no roster row" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

section "§three-arms — one refusal names every fault, across arms (wave-14 REQ-8, D3, AC-8.1/AC-8.3)"
# ============================================================================
#
# THE INCIDENT, ONE WAVE ON. Wave-12 T2 pooled the five BRIEF-SHAPE arms and left every
# STATE arm exiting where it stood, on the argument that a broken environment and a typo
# do not belong in one list. The 2026-09-13 loop is the measurement that overturned it:
# the six refusals Chris counted were the arming wall, then the budget, then the suite
# allowance — three DIFFERENT arms, one per attempt, each holding a fact the gate had
# already read. D3 keeps arm 6 (attestation) first and alone, because a repo that cannot
# be written makes every later disk read meaningless, and pools everything else.
#
# fails-when: the refusal names fewer than three faults, or fixing the first alone
# produces a refusal naming a fault the first refusal could have named.

# ONE SHAPE FAULT, not three: BRIEF_THREE_FAULTS would put five faults on the wire and the
# arm below could not tell "the pool works" from "the shape pool works". This is the
# §combined-deny single-fault brief — a declared Suites: and no artifact — so the only
# brief-shape arm that fires is A13.
BRIEF_ONE_SHAPE_FAULT='Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r3arms yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"                      # fault 1: arm 7a, the Patrol
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"                          # fault 2: arm 10, the budget
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_SHAPE_FAULT" "w3arms")"

expect_eq "§three-arms a brief faulting in three arms is REFUSED" "deny" "$GATE_VERDICT"
expect_eq "§three-arms …exactly once: one refusal line reaches the user" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
# THE USER LINE IS THE FIRST ARM'S OWN, unchanged — the Patrol runs first in file order,
# and AC-E1.3 leaves no room on that line for a count or a second fault.
expect_eq "§three-arms …the user line stays the first arm's own sentence" \
  "bionic: dispatch refused — no Patrol stamp exists for this session (CronCreate the Patrol job)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
# ALL THREE ON THE MODEL'S OWN WIRE. `$GATE_REASON` is parsed out of the deny verdict, so
# what is asserted here is what the model actually reads.
expect_contains "§three-arms …the model's wire names the Patrol fault" \
  "no Patrol stamp exists for this session" "$GATE_REASON"
expect_contains "§three-arms …and the budget fault" \
  "this passes the run's writer budget" "$GATE_REASON"
expect_contains "§three-arms …and the brief-shape fault" \
  "this brief names no deliverable" "$GATE_REASON"

# AC-8.3 — THE LINE BUDGET IS A FORMULA NOW, not a tolerance. Wave-13's cap was ten lines
# (one refusal line, a blank, the seven scaffold lines, a blank, the pointer) and it tracks
# the scaffold's own length by construction; epic-23 wave-16's `Re-executes:` line makes the
# scaffold eight lines and the fixed part eleven (REQ-1 AC-1.8, A-T2.7). REQ-8 adds ONE line
# per ADDITIONAL fault: the first fault is already the user line and costs nothing, faults
# 2..N cost a line each, and so does every `not checked:` line. Three faults, no not-checked
# line: eleven plus two.
expect_status "§three-arms …and the wire is at most 13 lines (11 + one per additional fault)" "0" \
  "$([ "$(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ')" -le 13 ] && echo 0 || echo 1)"
# NOT VACUOUS: a wire that named nothing extra would also be under twelve. It has to have
# GROWN by exactly the two lines the two extra faults bought.
expect_status "§three-arms …and it really grew: more than the ten-line single-arm wire" "0" \
  "$([ "$(printf '%s' "$GATE_REASON" | wc -l | tr -d ' ')" -ge 11 ] && echo 0 || echo 1)"
# THE SHAPE BANS OF WAVE-13 STAND: no per-fault heading, no fault-count sentence, no
# stacked `Fix:` paragraphs. One line per fault is a LINE, not a section.
expect_absent "§three-arms …no fault-count header sentence" "SHAPE FAULTS" "$GATE_REASON"
expect_absent "§three-arms …no per-fault '── N.' heading" "── " "$GATE_REASON"
expect_absent "§three-arms …and no stacked Fix: blocks" "Fix: " "$GATE_REASON"
# THE FIXTURE'S OWN ROW STANDS AND NOTHING WAS ADDED TO IT. A refused dispatch is not a
# launch, however many arms it faulted in — and the budget fixture above wrote exactly one.
expect_status "§three-arms …and appends no row for the refused dispatch" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- THE CLAIM: fixing the first fault surfaces NOTHING the first refusal withheld ----
#
# This is the arm that makes the section mean something. Arm the Patrol and dispatch the
# same brief into the same repo: the refusal must name the remaining two and must not
# name a THIRD that was readable all along.
write_attestation "$REPO" "$SID_A"
printf 'armed\n' > "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_SHAPE_FAULT" "w3arms2")"
expect_eq "§three-arms attempt 2, the Patrol armed, is still refused" "deny" "$GATE_VERDICT"
expect_absent "§three-arms …and the Patrol fault is gone" \
  "no Patrol stamp exists for this session" "$GATE_REASON"
expect_contains "§three-arms …naming the budget fault the first refusal already named" \
  "this passes the run's writer budget" "$GATE_REASON"
expect_contains "§three-arms …and the brief-shape fault it already named too" \
  "this brief names no deliverable" "$GATE_REASON"

# ---- AND ONE FAULT IS STILL ONE SENTENCE, on the one wire ----
#
# The discriminator wave-12 T17 installed kept a LONE state refusal off the JSON wire;
# wave-19 T4 (REQ-7, D8) retired that half, so every brief or state fault leaves as a deny
# verdict. What stays pinned is the sentence: a clean brief with nothing wrong but the
# Patrol refuses in the arming wall's own words, one verdict on stdout.
REPO=$(make_repo r3arms3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w3arms3")"
expect_eq "§three-arms a LONE state fault refuses on the deny wire" "deny" "$GATE_VERDICT"
expect_eq "§three-arms …printing ONE verdict on stdout" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_eq "§three-arms …in the arming wall's own words, unchanged" \
  "bionic: dispatch refused — no Patrol stamp exists for this session (CronCreate the Patrol job)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"

section "§not-checked — a dependent arm says so, rather than going quiet (wave-14 REQ-8, AC-8.2)"
# ============================================================================
#
# SOME ARMS GENUINELY CANNOT ANSWER until an earlier one has produced something. The
# one-regression wall reads `SUITES_ALLOWED` for `run.sh`; a brief that declares neither
# `Files:` nor `Suites:` produces no set at all, so the wall has nothing to read. Silence
# there is the thing AC-8.2 forbids: the author fixes the pooled faults, dispatches again,
# and meets a refusal the gate could have TOLD them was coming. The shape is the one the
# budget wall's per-field reading already uses — name the arm, name what it needs.
#
# fails-when: a dependent arm is silently skipped.

BRIEF_NO_SET='Your task: review the wave.
Expected duration: 20 minutes.'

REPO=$(make_repo rnotchk yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_SET" "wnotchk")"
expect_eq "§not-checked a brief with no Files: and no Suites: is refused" "deny" "$GATE_VERDICT"
expect_contains "§not-checked …naming the suite-allowance fault" \
  "this brief declares no Files: and no Suites:" "$GATE_REASON"
expect_contains "§not-checked …and saying the one-regression wall was not checked, and why" \
  "not checked: one-regression, needs a suite set" "$GATE_REASON"
# THE CONTROL, and it is what stops this from pinning a constant string. It has to be a
# refusal on the SAME wire — two faults, so the several-fault wire is what is read — over a
# brief that DOES declare a suite set, which leaves the one-regression wall checkable. An
# unarmed Patrol supplies the second fault without touching the brief.
REPO=$(make_repo rnotchk2 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_SHAPE_FAULT" "wnotchk2")"
expect_eq "§not-checked control: a two-fault brief that DECLARES Suites: is refused too" \
  "deny" "$GATE_VERDICT"
expect_absent "§not-checked …with no not-checked line for a wall that COULD be checked" \
  "not checked: one-regression" "$GATE_REASON"

section "§slow-impact — a slow derivation is admitted, and derives the same set (wave-14 REQ-7, AC-7.1)"
# ============================================================================
#
# THE STANDING WORKAROUND THIS RETIRES. `IMPACT_BOUND_S` was six seconds and
# tests/lib/impact.sh cost 4.2 s at quiet load, so an ordinary dispatch under load 8-12
# took 5.6 s and was refused for the cost of asking its own question (A-orch-46). The
# operator's answer was to declare `Suites:` by hand on every dispatch during a floor.
# The bound is a HANG GUARD now (lib/bounds.sh), the cost is gone to T9's cache, and a
# derivation that merely takes 5.6 s is admitted.
#
# THE SLEEP IS THE LOAD. AC-7.1 states the cost in seconds; a load generator would prove
# the same thing with a fixture nobody can run twice the same way. What matters is that
# the gate waits for a derivation of that length and records its answer.
#
# fails-when: the loaded case is refused with the bound line, or the two derived sets differ.
REPO=$(make_repo rslowimp yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 5.6
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-slow-imp")"
expect_status "§slow-impact a 5.6s derivation is ADMITTED" "0" "$GATE_ST"
expect_absent "§slow-impact …with no bound line anywhere on the wire" "bound:" "$GATE_ERR"
SLOW_SET="$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"
expect_eq "§slow-impact …and the row carries the derivation's own answer" "alpha.test.sh" "$SLOW_SET"

# ---- THE PAIRED ARM (T29, AC-7.1 discrimination) ----
#
# WHY THE ARM ABOVE PROVES NOTHING ALONE. §slow-impact's claim is that the SHIPPED bound
# (10s since T35's D1 move, 20s as T9/D4 first set it) is what admits a 5.6s derivation —
# not that any bound would. At the
# superseded 6s bound the same 5.6s sleep cleared by only 0.4s, so this section passed
# there too (T6-one-refusal.md §3; auditor finding AC-7.1, UNVERIFIABLE at d3930dd): the
# observation is identical with the bound move absent. The missing control is the SAME
# 5.6s derivation, on the SAME fixture, forced under a bound BELOW the sleep — it must
# refuse, and its refusal must name the forced number, or the override never reached the
# arm and any refusal it produced would be refusing for some unrelated reason.
#
# HOW THE BOUND IS FORCED. dispatch-preflight.sh sources lib/bounds.sh only when
# IMPACT_BOUND_S is unset (`[ -z "${IMPACT_BOUND_S:-}" ]`, :2509) — an env value already
# set on entry wins and the library is never read. GATE_ENV is the driver's own channel
# for exactly this (see probe_env_on above, which does the same thing for
# ANTHROPIC_API_KEY and HOME); saved and restored around the one call so no later arm in
# this file inherits a forced bound.
#
# WHY 5 AGAINST 5.6 IS A REAL MARGIN NOW, AND WAS NOT (wave-14 T34). As written this arm
# was a coin flip, green at T29's head and red at 89f6944's on the same machine at lower
# load. Nothing about the override was at fault — instrumentation caught the arm reading
# `bound=5` exactly as intended — but the gate spent that bound as fifty `sleep 0.1` polls
# costing 115 ms each, so the "5 second" wait ran 5.77 s against a 5.6 s derivation and the
# fixture won about half the time. The wait is a wall-clock one now and ends in
# [4 s, 5 s], which is 0.6 s clear of the sleep and, being a clock, does not narrow under
# load. The 0.4 s the arm was written with was never the margin it looked like; measure
# before shortening it further.
#
# fails-when: the forced-5s call is ADMITTED, or its refusal does not name the forced
# number (`bound:   5s`, the arm's own wire spacing — a wire naming a different number
# would mean the override never reached the arm at all).
_S29_GATE_ENV_SAVE="$GATE_ENV"
GATE_ENV="$GATE_ENV IMPACT_BOUND_S=5"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-slow-imp-forced5")"
GATE_ENV="$_S29_GATE_ENV_SAVE"
expect_eq "§slow-impact …the SAME 5.6s derivation, forced to a 5s bound, is REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "§slow-impact …naming the FORCED bound, proving the override reached the arm" \
  "bound:   5s" "$GATE_VERR"
# THE ROSTER IS THE CONTROL: still exactly the one row the ADMITTED call above wrote —
# not two, which would mean the forced-bound call was admitted after all and only the
# assertion above was wrong.
expect_status "§slow-impact …and journalled no row for the refused dispatch" \
  "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# THE SAME DISPATCH AT QUIET LOAD, same set. This is AC-7.1's second half: the derived set
# is a property of the tree and the brief, never of how long the machine took to say it.
REPO=$(make_repo rslowimp2 yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 0
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-quiet-imp")"
expect_status "§slow-impact control: the same brief with no sleep is admitted too" "0" "$GATE_ST"
expect_eq "§slow-impact …and derives the SAME set" "$SLOW_SET" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

section "§hanging-impact — a hang is still bounded, and the bound is named (wave-14 REQ-7, AC-7.2)"
# ============================================================================
#
# WHAT IS LEFT FOR A BOUND TO DO once the cost is cached: an impact command that never
# returns. A hook killed on the CLI's own timeout does NOT exit 2 — the dispatch proceeds
# with no roster row and therefore no budget at all — so the wait has to end on OUR terms,
# strictly inside the registration hooks/hooks.json gives this hook (§L.4c in
# cross-gate-agreement pins the pair; both numbers are read from their own files).
#
# NO SEAM. The bound is the shipped constant, read from lib/bounds.sh; the fixture simply
# outruns it. A test that shortened the bound would prove a value it had itself supplied.
#
# fails-when: the preflight waits past the stated bound, or the refusal does not name it.
BOUND_S="$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/bounds.sh" 2>/dev/null)"
expect_nonempty "§hanging-impact the shipped bound is readable from lib/bounds.sh" "$BOUND_S"

REPO=$(make_repo rhangimp yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 60
GATE_HIRES=1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w-hang-imp")"
GATE_HIRES=""
HANG_ELAPSED="$GATE_TIME_CS"
expect_eq "§hanging-impact a 60s derivation is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "§hanging-impact …naming the bound it outran, as the library defines it" \
  "${BOUND_S}s" "$GATE_VERR"
# THE CLOCK IS THE CLAIM. `$GATE_TIME_CS` is the first drive alone (run_gate drives a
# second time under the verbose knob, which would double any number read across both).
# ONE SECOND OF SLACK, NOT EIGHT, AND READ IN HUNDREDTHS — the same re-pinning as 29a, for
# the same reason and against the same defect (wave-14 T34): the tick-counted wait ran
# 23.0-23.2s here too, and a whole-second clock with eight seconds of slack called it fine.
if [ "$HANG_ELAPSED" -le $(( (BOUND_S + 1) * 100 )) ]; then
  ok "§hanging-impact …and it stopped waiting at the bound, not at the sleep ($(( HANG_ELAPSED / 100 )).$(printf '%02d' $(( HANG_ELAPSED % 100 )))s)"
else
  no "§hanging-impact …and it stopped waiting at the bound, not at the sleep" \
    "took $(( HANG_ELAPSED / 100 )).$(printf '%02d' $(( HANG_ELAPSED % 100 )))s against a ${BOUND_S}s bound"
fi
expect_status "§hanging-impact …and journalled no row at all" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

section "§bound-one-owner — the derivation bound is defined once, fleet-wide (wave-14 REQ-7, AC-7.4)"
# ============================================================================
#
# T9's own suite pins the LIBRARY's half (tests/stop.test.sh §6). This is the other half,
# and the one AC-7.4 names: the preflight carried its own `IMPACT_BOUND_S=6` under its own
# header, so the two legs of the fleet meant different things by "bounded" while each
# message quoted its own number.
#
# THE REAL PATHS, NOT `payload/`. `payload/hooks` is a symlink to `../hooks`, and grep -r
# does not descend through a symlinked directory met during recursion — AC-7.4's own
# spelling over `payload/` cannot see this file's definition at all and would report one
# while two existed (T9 report §6).
#
# A DEFINITION IS A LITERAL NUMBER. A line that READS the constant — the wait's own
# `[ "$SECONDS" -ge "$IMPACT_BOUND_S" ]` — is not counted; that distinction is the whole of
# what "defined in two places" means.
#
# TWO BOUNDS, ONE OWNER EACH (re-spelled by wave-14 T16 against T15). This arm counted every
# definition matching `[A-Z_]*IMPACT_BOUND_S=`, which was one until T15 landed
# `LG_IMPACT_BOUND_S=6` — the LANDING GATE's bound, a different number that moves for a
# different reason (lib/bounds.sh states both, and tests/stop.test.sh §6 owns that one). The
# loose prefix read T15's ratified second constant as a second definition of THIS one. So the
# count below is of the exact name, and the arm under it keeps the intent the prefix was there
# for: no hook re-spells a derivation bound under its own header, whatever it calls it — every
# `*IMPACT_BOUND_S=` definition in the fleet lives in lib/bounds.sh, and there are exactly two.
DP_BOUND_DEFS="$(/usr/bin/grep -rnE '^[[:space:]]*IMPACT_BOUND_S=[0-9]' \
  "${BIONIC_SCRIPTS_DIR}/hooks" "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null)"
expect_eq "§bound-one-owner exactly one numeric definition across hooks/ and payload/scripts/" \
  "1" "$(printf '%s\n' "$DP_BOUND_DEFS" | /usr/bin/grep -c . )"
expect_contains "§bound-one-owner …and it is the one in lib/bounds.sh" "lib/bounds.sh" "$DP_BOUND_DEFS"
DP_BOUND_ANY="$(/usr/bin/grep -rnE '^[[:space:]]*[A-Z_]*IMPACT_BOUND_S=[0-9]' \
  "${BIONIC_SCRIPTS_DIR}/hooks" "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null)"
expect_eq "§bound-one-owner …and NO other file defines a bound under any prefix" "0" \
  "$(printf '%s\n' "$DP_BOUND_ANY" | /usr/bin/grep -v '/lib/bounds\.sh:' | /usr/bin/grep -c . )"
expect_eq "§bound-one-owner …lib/bounds.sh owning exactly the two the fleet has (T15's is the second)" \
  "2" "$(printf '%s\n' "$DP_BOUND_ANY" | /usr/bin/grep -c '/lib/bounds\.sh:')"
# THE WAIT MOVED WITH THE DERIVATION (wave-20 T6; REQ-4, Δ10). The dispatch wall's derivation
# is `brief_validate_fields` in payload/scripts/lib/brief.sh now, the contract grammar `amend`
# and `task-add` call too, so the READ of the bound and the source of lib/bounds.sh are that
# file's. These rows follow them there; what they assert about the bound is unchanged.
DP_GRAMMAR="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh"
# NOT VACUOUS: the sweep reaches the grammar, whose READ it declines to count.
expect_nonempty "§bound-one-owner the sweep reaches lib/brief.sh, whose READ is uncounted" \
  "$(/usr/bin/grep -rn 'IMPACT_BOUND_S' "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null \
     | /usr/bin/grep 'lib/brief.sh')"
DP_GATE_SRC="$(cat "$DP_GRAMMAR")"
expect_nonempty "§bound-one-owner the dispatch wall's grammar sources lib/bounds.sh" \
  "$(/usr/bin/grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$DP_GRAMMAR")"
# RE-SPELLED ONTO THE CLOCK (wave-14 T34). This pair used to read the hook's tick budget,
# `IMPACT_BOUND_TICKS=$(( IMPACT_BOUND_S * 10 ))`, and assert it was DERIVED from the
# constant rather than typed as a second literal. The budget is gone: a count of `sleep
# 0.1` polls cost 115 ms a poll, so spending it waited ~1.15x the bound the refusal quoted
# (T34 §2-3), and the wait now ends on `SECONDS` against the constant itself. The intent
# survives intact and gets stronger — the strongest form of "not a second number" is no
# second number at all — so the positive arm reads the stop condition and the negative one
# stands guard over the mechanism that was removed.
expect_regex "§bound-one-owner …and its wait ends on the constant itself, not on a derived second number" \
  '\[[[:space:]]*"\$SECONDS"[[:space:]]*-ge[[:space:]]*"\$IMPACT_BOUND_S"[[:space:]]*\]' "$DP_GATE_SRC"
expect_no_regex "§bound-one-owner …leaving no tick budget behind to drift against it" \
  '^[[:space:]]*IMPACT_BOUND_TICKS=' "$DP_GATE_SRC"

# ============================================================================
section "S32: the floor-once wall — a second full floor waits for Step 4 (REQ-5, D7)"
# ============================================================================
#
# THE RULE MADE MECHANICAL. `skills/canonical-sdlc/dispatch.md:12` has said for three
# releases that the full tree belongs on one row per run, the Step-5 runner's. Nothing
# enforced the half that matters most: a floor run WHILE Step-4 rows are still open
# proves a tree that no longer exists by the time those rows land, and wave-14 paid for
# it six times (seed row 5, Chris DevX item 1).
#
# THE SIBLING WALL IS NOT THIS ONE. S28 above counts full-tree rows on the ROSTER and
# asks for one written cause per extra run; it says nothing about whether the work being
# proved is finished. This wall reads the PLAN's `## Tasks` ledger and asks whether any
# step-4 or fold-in row is still `pending` or `active`. Both can fire on one dispatch and
# they pool into one refusal like every other pair of arms in this file.
#
# THE LEDGER IS READ THROUGH `units_rows`, THE ONE TASKS PARSER (AC-5.5). The static pins
# at the end of this section are what hold that; a second table split in this hook is the
# defect REQ-1e existed to remove and it would land back here first.
#
# fails-when: a run.sh brief is admitted with an open step-4 row and no recorded cause;
# an all-landed ledger is refused; a recorded cause does not release the dispatch; a
# non-floor brief, an unbound session or a plan with no `## Tasks` is touched by this arm.

# s32_row <id> <step> <status> [task text] -> one `## Tasks` data row
s32_row() {
  printf '| %s | %s | build | %s | implementor | — | 30 | REQ-1 | payload/scripts/lib/widget.sh | — | %s |' \
    "$1" "$2" "${4:-does the thing}" "$3"
}

# s32_plan <repo> <regression-cause text, or empty> <row>... — rewrite the fixture plan
#
# WRITTEN WHOLE, NOT APPENDED. `## Tasks` is a section heading, so it CLOSES
# `## SDLC State`: a cause line appended to the end of a plan that carries a Tasks table
# is outside the ledger and neither this wall nor S28's counts it (S28f pins that reading
# from the other side). The cause therefore has to be placed inside the state section
# when the file is built, which is what this helper is for.
s32_plan() {
  local repo="$1" cause="$2"; shift 2
  local plan="$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  local row
  {
    printf -- '---\n'
    printf 'governing-skill: canonical-sdlc\n'
    printf 'canonical_sdlc_version: 14\n'
    printf 'intent: build\n'
    printf 'rigor: audited\n'
    printf 'scale: wave\n'
    printf -- '---\n\n'
    printf '# Test wave plan\n\n'
    printf '## SDLC State\n\n'
    printf 'integration-branch: main\n'
    printf 'current: 4\n\n'
    printf -- '- Step 4: tasks in flight\n'
    [ -z "$cause" ] || printf 'regression-cause: %s\n' "$cause"
    printf '\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |\n'
    printf -- '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$plan"
}

S32_FLOOR_BRIEF='Your task: run the tests floor.
Expected artifact: .bionic/docs/record/w32-floor.log
Expected duration: ~40 minutes.
Suites: tests/run.sh'

S32_NARROW_BRIEF='Your task: fix the widget.
Expected artifact: .bionic/docs/record/w32-widget.md
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh'

# ---- AC-5.1: an open step-4 row refuses the floor, and the refusal names it ----
REPO=$(make_repo r32a yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T3 4 pending)" \
  "$(s32_row T12 5 pending 'Step-5 floor at the integration head')"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-one")"
expect_eq "32a a full-tree brief is REFUSED while a step-4 row is pending" "deny" "$GATE_VERDICT"
expect_contains "32a …and the one line names the open row by id" \
  "T3" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_contains "32a …saying what is open" "Step-4 rows open" "$GATE_ERR"
expect_contains "32a …the detail gives the row its step and status" "step 4, pending" "$GATE_VERR"
expect_contains "32a …and names the plan the cause would go on" \
  "wave-01-test.plan.md" "$GATE_VERR"
expect_contains "32a …and the line to write" "regression-cause:" "$GATE_VERR"
# THE STEP-5 ROW IS NOT THE FLOOR'S BUSINESS. T12 is `pending` at step 5 — the runner row
# this very dispatch would fill — and a wall that counted it would refuse every floor
# forever, which is the failure mode this arm is one assertion away from.
expect_absent "32a …and the step-5 runner row is NOT counted against the floor" \
  "T12" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_status "32a …and the refused dispatch journalled no row" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- AC-5.1: an ACTIVE row counts too, and several are all named ----
REPO=$(make_repo r32b yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T2 4 active)" \
  "$(s32_row T3 4 pending)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-two")"
expect_eq "32b an ACTIVE step-4 row refuses the floor as well as a pending one" "deny" "$GATE_VERDICT"
S32B_LINE=$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')
expect_contains "32b …and BOTH open rows are named on the one line" "T2" "$S32B_LINE"
expect_contains "32b …the second one too" "T3" "$S32B_LINE"
expect_absent "32b …and the landed row is not" "T1" "$S32B_LINE"

# ---- AC-5.1: a FOLD-IN row at a later step counts (the plan's own vocabulary) ----
#
# A fold-in is work that lands AFTER the step it is folded into — wave-14 carried eleven
# of them at steps 5 and 6, and every one of them changed the tree the floor had proved.
# The predicate is the plan's own word (A-T5.1): a row whose `step` cell is 4, or whose
# task text names a fold-in.
REPO=$(make_repo r32c yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T20 6 pending 'Step-6 fold-in (review F1): re-spell the pin')"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-foldin")"
expect_eq "32c an open FOLD-IN row at step 6 refuses the floor" "deny" "$GATE_VERDICT"
expect_contains "32c …naming it" "T20" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
# THE CONTROL that keeps the row above from passing on the step cell: an ordinary step-6
# row with the same status and no fold-in in its text is NOT counted.
REPO=$(make_repo r32c2 yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T20 6 pending 'Step-6 six-axis review at the audited head')"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-plain6")"
expect_status "32c control: an ordinary open step-6 row does NOT refuse the floor" "0" "$GATE_ST"

# ---- AC-5.2: every step-4 row landed or dropped, and the floor is admitted ----
REPO=$(make_repo r32d yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T2 4 dropped)" \
  "$(s32_row T3 4 landed)" \
  "$(s32_row T12 5 pending 'Step-5 floor at the integration head')"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-clear")"
expect_status "32d the floor is ADMITTED once every step-4 row is landed or dropped" "0" "$GATE_ST"
expect_absent "32d …with nothing from this arm on the wire" "Step-4 rows open" "$GATE_ERR"
expect_status "32d …and it is journalled" \
  "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- AC-5.3: a recorded cause releases the floor with rows still open ----
#
# WRITTEN AS A PAIR (A-T5.5). The positive half alone is vacuous at a parent that has no
# wall: exit 0 is what an absent arm gives too. Its discriminator is the second half —
# the SAME ledger without the cause line, on a fresh repo, must refuse — so the block goes
# red at a parent where the wall is missing and green only where the override is read.
REPO=$(make_repo r32e yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "the merge changed the loader; the tree must be re-proved" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T3 4 pending)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-caused")"
expect_status "32e a recorded regression-cause: admits the floor with T3 still pending" "0" "$GATE_ST"
expect_absent "32e …with nothing from this arm on the wire" "Step-4 rows open" "$GATE_ERR"
REPO=$(make_repo r32e2 yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T3 4 pending)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-uncaused")"
expect_eq "32e discriminator: the SAME ledger without the cause line is refused" "deny" "$GATE_VERDICT"
# AND THE CAUSE IS READ WHERE S28 READS ITS OWN: under `## SDLC State`, nowhere else.
REPO=$(make_repo r32e3 yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T3 4 pending)"
printf 'regression-cause: written after the table, outside the ledger\n' \
  >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-floor-outside")"
expect_eq "32e …a cause written below the Tasks table is outside ## SDLC State and does not count" \
  "deny" "$GATE_VERDICT"

# ---- AC-5.4: the arm is silent on everything that is not a floor ----
REPO=$(make_repo r32f yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" \
  "$(s32_row T1 4 landed)" \
  "$(s32_row T3 4 pending)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_NARROW_BRIEF" "w32-narrow")"
expect_status "32f a brief that does not name tests/run.sh is untouched by this arm" "0" "$GATE_ST"
expect_absent "32f …silently" "Step-4 rows open" "$GATE_ERR"

# A PLAN WITH NO `## Tasks` TABLE is open and silent — which is every fixture above this
# section, and the reason none of them changed when this wall landed.
REPO=$(make_repo r32g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-no-table")"
expect_status "32g a bound plan with no ## Tasks table admits the floor" "0" "$GATE_ST"
expect_absent "32g …silently" "Step-4 rows open" "$GATE_ERR"

# NO BOUND PLAN AT ALL: nowhere to read a ledger and nowhere to write a cause.
REPO=$(make_repo r32h yes)
write_attestation "$REPO" "$SID_A"
rm -rf "$REPO/.bionic/docs/plans"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S32_FLOOR_BRIEF" "w32-unbound")"
expect_status "32h an unbound session admits the floor" "0" "$GATE_ST"
expect_absent "32h …silently" "Step-4 rows open" "$GATE_ERR"

# ---- AC-5.4: and the arm says so when it cannot answer (wave-14 AC-8.2's shape) ----
REPO=$(make_repo r32i yes)
write_attestation "$REPO" "$SID_A"
s32_plan "$REPO" "" "$(s32_row T3 4 pending)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: review the wave.
Expected duration: 20 minutes.' "w32-no-set")"
expect_contains "32i a brief with no suite set leaves this arm unable to answer, and it says so" \
  "not checked: floor-once, needs a suite set" "$GATE_REASON"

# ---- AC-5.5: one Tasks parser, and it is the library's ----
S32_HOOK="$GATE"
expect_status "32j the hook reads the ledger through units_rows" "yes" \
  "$([ "$(/usr/bin/grep -c 'units_rows' "$S32_HOOK")" -ge 1 ] && echo yes || echo no)"
expect_status "32j …and declares units.sh in its own BIONIC_LIB_WANT" "yes" \
  "$(sed -n 's/^BIONIC_LIB_WANT="\(.*\)"$/\1/p' "$S32_HOOK" | head -1 \
     | tr ' ' '\n' | /usr/bin/grep -qx 'units.sh' && echo yes || echo no)"
# NO SECOND TABLE PARSER. The matrix spelled this pin as "`split(` on `|` is zero", which
# was written against a `grep -r payload/` that returns nothing at all (payload/hooks is a
# SYMLINK and `grep -r` does not follow one — A-T5.4). The hook has carried exactly one
# split-on-pipe since epic-16: a roster-state LINE reader (`dp_roster_contracts` until
# epic-23 wave-20 T2; since D10 the name-in-flight arm's status label, the close itself being
# the library's `roster_open_names`), which is not a markdown table. So the pin is re-spelled (A-T5.3): the count stays at one, that one
# is the roster reader, and nothing in this hook scans for a `## Tasks` heading.
expect_eq "32j …and carries exactly one awk split on a pipe, the roster-line reader" \
  "1" "$(/usr/bin/grep -cE 'split\([^)]*\|' "$S32_HOOK")"
expect_contains "32j …which splits a roster LINE, not a markdown table" \
  "split(line, parts" "$(/usr/bin/grep -hE 'split\([^)]*\|' "$S32_HOOK")"
expect_eq "32j …and no arm of this hook scans for a ## Tasks heading of its own" \
  "0" "$(/usr/bin/grep -cE '/\^#+ *Tasks/' "$S32_HOOK")"

# ============================================================================
section "S33: an auditor brief may not waive Suites: (REQ-4 AC-4.3/AC-4.4, D6)"
# ============================================================================
#
# THE INCIDENT THIS ARM PREVENTS. `Suites: none` is a legitimate waiver for a role
# that never runs a suite at all — a researcher reads, a test-runner reports — and
# both pass through this wall unchanged. An auditor's Step-5 job is to FALSIFY the
# matrix's evidence, which for a hermetic-tier row means RE-RUNNING the suite the
# row names; an auditor brief that waives every suite has nothing to re-run.
#
# ROLE MATCHED WHOLE, ON subagent_type — never on the brief's prose (handoff rule).
# Both spellings this repo's briefs actually carry are covered: the fully-qualified
# `bionic:auditor` and the bare `auditor`.
#
# fails-when: an auditor brief with Suites: none is admitted; a researcher or
# test-runner brief with Suites: none is refused by THIS arm; an auditor brief that
# names real suites is refused by this arm.

S33_WAIVED_BRIEF='Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w33-audit.md
Expected duration: ~30 minutes.
Suites: none'

S33_DECLARED_BRIEF='Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w33-audit2.md
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh, tests/gadget.test.sh'

# ---- AC-4.3: bionic:auditor + Suites: none is refused, fix names the suites ----
REPO=$(make_repo r33a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w33-auditor" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "33a a bionic:auditor brief with Suites: none is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "33a …the one line names the fault" \
  "auditor" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_contains "33a …and the fix names what to declare" \
  "name the suites" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_status "33a …and no roster row was journalled for the refused dispatch" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- AC-4.3: the bare role word ("auditor", no bionic: prefix) is caught too ----
REPO=$(make_repo r33b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w33-auditor-bare" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "auditor")"
expect_eq "33b a bare 'auditor' subagent_type with Suites: none is REFUSED too" \
  "deny" "$GATE_VERDICT"

# ---- AC-4.3: the CONTROL — an auditor brief that names real suites passes ----
REPO=$(make_repo r33c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_DECLARED_BRIEF" "w33-auditor-ok" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "33c control: an auditor brief that DECLARES suites PASSES" "0" "$GATE_ST"
expect_absent "33c …with no refusal printed" "BLOCKED" "$GATE_ERR"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "33c …and the row carries the declared set" \
  "widget.test.sh gadget.test.sh" "$(roster_field "$ROW" suites_allowed)"

# ---- AC-4.4: the two other reading roles are UNCHANGED by this arm ----
for _role in bionic:researcher bionic:test-runner; do
  REPO=$(make_repo "r33d-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w33-reader" \
                               "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_status "33d a ${_role} brief with Suites: none is UNCHANGED — still admitted" \
    "0" "$GATE_ST"
done

# ---- AC-4.1 end-to-end (T4): a not-yet-existing tests/*.test.sh under Files: gets
# its self edge on the roster row, driven through the REAL tests/lib/impact.sh (the
# tool T4 changed) rather than the S27 stub — this row proves the two tasks meet.
# BIONIC_IMPACT_CACHE_DIR is forced empty so the real tree's own impact-cache under
# .bionic/tmp is never written to by this fixture run (impact.sh's own contract for
# turning the cache off).
s33_real_impact() {  # <repo> — point .bionic/config.yaml at the real impact.sh
  mkdir -p "$1/.bionic"
  printf 'impact-command: env BIONIC_IMPACT_CACHE_DIR= bash %s/tests/lib/impact.sh\n' \
    "${BIONIC_SCRIPTS_DIR}" > "$1/.bionic/config.yaml"
}

S33_NEWSUITE_BRIEF='Your task: add a brand-new suite.
Expected artifact: .bionic/docs/record/w33-newsuite.md
Expected duration: ~20 minutes.
Files: tests/brand-new.test.sh'

REPO=$(make_repo r33e yes)
write_attestation "$REPO" "$SID_A"
s33_real_impact "$REPO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_NEWSUITE_BRIEF" "w33-newsuite")"
expect_status "33e a Files: tests/brand-new.test.sh (absent) brief is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "33e …and the roster row's suites_allowed carries the new suite's self edge" \
  "brand-new.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "33e …the derived set is exactly the real tree's answer (self + 3 dir-refs)" \
  "brand-new.test.sh cross-gate-agreement.test.sh docs-pins.test.sh seam-resolution.test.sh" \
  "$(roster_field "$ROW" suites_allowed)"
expect_status "33e …and the row says the set was DERIVED, not declared" \
  "derived" "$(roster_field "$ROW" suites_source)"

section "§runs-lift — a brief declares what it will RUN, in any runner (REQ-1, D1, D3, ADR-029)"
# ============================================================================
#
# WHAT THIS SECTION IS FOR. Until 1.8.3 "suite" meant "shell suite" at five independent
# sites (research R1 §9.1), so an agent working in a jest, pytest or go project could
# declare nothing true: the auditor arm refused it and the writer budget held nothing.
# `Re-executes:` is the one runner-agnostic label — lifted from the brief TEXT exactly as
# `Suites:` is, for every role, recorded on the roster row as its own field, and held by
# the writer-side budget arm (that half is T2's).
#
# THE GRAMMAR IS AUTHOR-MARKED (D3). A run is a backtick-delimited command on the span, in
# position order, at most three of them; text outside the marks is not a run; a run carrying
# an UNQUOTED pipe, a newline or an unexpanded shell variable is refused at the lift with the
# token named (a pipe inside quotes is an ordinary argument — 18T4a/18T4b below). The marks are KEPT on the roster field, which is what makes "the exact marked run"
# a thing the budget arm can compare against.
#
# fails-when: the field is absent from the row; an auditor brief declaring runs and waiving
# suites is refused; a brief carrying only this label is refused for declaring no
# instrument; an unexpanded name is admitted under either spelling; a fourth run reaches the
# row; unmarked text on the span is lifted as a run.

# THE MARK, HELD IN A VARIABLE. A backtick inside a double-quoted string here would be a
# command substitution, and a backtick pair inside a double-quoted ASSERTION NAME is the
# fault cross-gate §B pins against tree-wide. Every run below is built from this.
RL_BT='`'
RL_JEST="${RL_BT}npx jest --testPathPatterns 'x'${RL_BT}"
RL_PYTEST="${RL_BT}pytest tests/unit${RL_BT}"
RL_GO="${RL_BT}go test ./...${RL_BT}"
RL_NPM="${RL_BT}npm test${RL_BT}"

# ---- AC-1.1: the field is lifted and lands on the roster row ----
REPO=$(make_repo r16la yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w16-audit.md
Expected duration: ~30 minutes.
Suites: none
Re-executes: ${RL_JEST}" "w16-auditor" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "16la an auditor brief declaring a marked run and waiving suites is ADMITTED" \
  "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16la …and the roster row carries the run, marks and all" \
  "$RL_JEST" "$(roster_field "$ROW" re_executes)"
expect_status "16la …with the waiver still recorded as the declared suite set" \
  "none" "$(roster_field "$ROW" suites_allowed)"

# ---- AC-8.1 (T5, REQ-8, D12): a span WITHIN the cap reads back every run it declared ----
# THE CONTROL FOR AC-8.2 BELOW. Two runs is under `RUNS_MAX` (3), so neither the cap-hit
# refusal nor its own drop field should ever fire here — the lift reads back exactly what
# was declared, space-joined, marks and all, and the dispatch is ADMITTED. Without this row
# a broken lift that dropped every second run, or one that refused ANY multi-run span, could
# pass 16le/16lf below green for the wrong reason.
REPO=$(make_repo r18t5a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w18-t5a.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST}" "w18-t5a")"
expect_status "18T5a a two-run span, under the cap, is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "18T5a …and the lift reads BOTH runs back, in order" \
  "$RL_JEST $RL_PYTEST" "$(roster_field "$ROW" re_executes)"

# ---- AC-1.2: the auditor arm reads BOTH spellings, and its Fix text shows both ----
# Row 1 of the seed's §7 table: a named suite list is admitted (33c drives this too; it is
# repeated here as this section's own control, at the same fixture shape as rows 2 and 3).
REPO=$(make_repo r16lb1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w16-audit.md
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh" "w16-aud-suites" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "16lb1 an auditor naming a suite list is ADMITTED" "0" "$GATE_ST"

# Row 2: the waiver plus declared runs is admitted — the arm's predicate is "no suites AND
# no declared runs", not "no suites".
REPO=$(make_repo r16lb2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w16-audit.md
Expected duration: ~30 minutes.
Suites: none
Re-executes: ${RL_PYTEST}" "w16-aud-runs" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_status "16lb2 an auditor waiving suites but declaring runs is ADMITTED" "0" "$GATE_ST"

# Row 3: the waiver alone is still refused, and the Fix text now names both spellings — an
# auditor in a jest repo must be able to read its way out of this refusal.
REPO=$(make_repo r16lb3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S33_WAIVED_BRIEF" "w16-aud-bare" \
                             "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "16lb3 an auditor waiving suites with no declared runs is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16lb3 …and the Fix text shows the suite spelling" \
  "Suites: tests/one.test.sh" "$GATE_VERR"
expect_contains "16lb3 …and the runner spelling beside it" \
  "Re-executes:" "$GATE_VERR"

# ---- AC-1.3: the field is a budget declaration — it satisfies the Files-or-Suites arm ----
REPO=$(make_repo r16lc yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests and report.
Expected artifact: .bionic/docs/record/w16-runs.md
Expected duration: ~20 minutes.
Re-executes: ${RL_GO}" "w16-runsonly")"
expect_status "16lc a brief carrying only the runs label is ADMITTED" "0" "$GATE_ST"
expect_absent "16lc …the no-instrument arm did not fire" \
  "declares no Files: and no Suites:" "$GATE_ERR"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lc …and the declared run is the budget on the row" \
  "$RL_GO" "$(roster_field "$ROW" re_executes)"

# ---- AC-1.4: an unexpanded shell variable is refused at the lift, under BOTH spellings ----
# EACH FIXTURE CARRIES A VALID `Files:` LINE so the bad declaration is the brief's ONLY
# fault and the refusal is the single-fault shape, whose detail (and so the named token)
# is readable under the verbose knob (since wave-19 T4 one fault is a deny verdict too, its own detail on the reason).
REPO=$(make_repo r16ld1 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool: the impact command is not under test in this
# section, and the real one over the real tree runs 11-17 s against a 10 s bound under
# wave-scale machine load (measured 2026-09-19), which would make these rows report the
# derivation bound instead of the fault they exist for.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-var.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}\$JEST x${RL_BT}" "w16-var-run")"
expect_eq "16ld1 a marked run holding an unexpanded name is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld1 …naming the token it saw" "\$JEST x" "$GATE_VERR"

REPO=$(make_repo r16ld2 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool: the impact command is not under test in this
# section, and the real one over the real tree runs 11-17 s against a 10 s bound under
# wave-scale machine load (measured 2026-09-19), which would make these rows report the
# derivation bound instead of the fault they exist for.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: run the suite.
Expected artifact: .bionic/docs/record/w16-var2.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Suites: \$SUITE" "w16-var-suite")"
expect_eq "16ld2 a Suites: token that is still a variable is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld2 …naming the token it saw" "\$SUITE" "$GATE_VERR"

# ---- AC-1.4 (cont.): a bracket that is not a WHOLE slot is a fault, named ----
#
# THE SILENT DROP THIS CLOSES (wave-16 T25, walk §W7). `istemplate()` carries two arms for
# trimtok RESIDUE — an opening bracket whose closer trimtok ate, and the mirror — and they
# are right where they were written, on `Files:` and `Suites:`, whose readers call trimtok
# first. `marked_runs()` never calls trimtok, so at THAT call site the same two arms fired
# on shell redirections: `> out`, `2>&1`, `<in`. The run was `continue`d with no
# `re_executes_bad` and no capwarn, the dispatch was ADMITTED with an empty or truncated
# `re_executes=` field, and the writer-side budget arm refused the agent's own command 40
# minutes later as undeclared. A pipe in the same position is refused loudly one line
# earlier and an unexpanded `$name` is refused with the token named (16ld1); this was the
# one shape that failed quietly.
#
# REFUSAL, NOT PASSTHROUGH (Chris, D14 option 3). An author who means a redirection is told
# which token and why, rather than having the wall silently agree to a budget entry nothing
# will ever equal.
#
# fails-when: a redirection run is admitted, its token is absent from the detail, or a
# roster row is written for the refused dispatch.
REPO=$(make_repo r16ld3 yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-redir.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}bash tests/x.test.sh > out 2>&1${RL_BT}" "w16-redir-run")"
expect_eq "16ld3 a marked run carrying a shell redirection is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ld3 …naming the whole token it saw, redirection and all" \
  "bash tests/x.test.sh > out 2>&1" "$GATE_VERR"
# AND NOTHING REACHED THE ROSTER. Under the old lift the row was written with the
# redirection tokens silently gone; this reads the absence of the row itself, and its
# failure message prints whatever row was written instead. Paired with the two positive
# rows above over the same fixture.
expect_empty "16ld3 …and no roster row was written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# THE PAIRED POSITIVE, one fixture, both halves: a WHOLE `<...>` slot is still read as
# guidance — no fault, nothing lifted — and an ordinary run beside it still lifts with its
# marks intact. Without this row 16ld3 could pass on a lift that refused every run.
REPO=$(make_repo r16ld4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-redir-ok.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_BT}<cmd>${RL_BT}" "w16-redir-ok")"
expect_status "16ld4 a whole <cmd> slot beside an ordinary run is still ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16ld4 …the slot lifted nothing and the ordinary run kept its marks" \
  "$RL_JEST" "$(roster_field "$ROW" re_executes)"

# ---- AC-7.1 / AC-7.2 (epic-23 wave-18, T4; REQ-7, D4): a QUOTED pipe is not a pipe ----
#
# WHAT WAS WRONG. The lift's pipe test was a whole-token scan — `index(tok, "|") > 0` — so
# a pipe inside single quotes, double quotes, a bracket expression or a regex alternation
# was refused identically to shell plumbing. A jest repository cannot declare its own runs
# without one: `--testPathPattern='(a|b)...'` is the ordinary spelling, and the refusal it
# drew told the author to "leave the shell plumbing off the span" about a character that
# was never plumbing. Research R2 §2 measured that the branch had NEVER been executed by a
# test in either direction, which is how the reading survived two waves.
#
# WHY BOTH HALVES ARE HERE. Making the scan quote-aware is necessary and not sufficient:
# the roster row is pipe-delimited, and the writer folded `|` to a space in every field —
# so an admitted run reached the row as a command no agent could ever type back, and the
# writer-side budget arm would refuse at run time the run this wall had just admitted (the
# wave-16 T25 failure through a different door). The row now percent-encodes the pipe in
# `re_executes=` and every reader decodes it, so the ADMIT row below asserts the encoded
# field, not just the exit status.
#
# fails-when: the quoted-pipe brief is refused; the unquoted one is admitted; the row
# carries a folded space where the pipe was; or the refusal still promises that any pipe
# is plumbing.
RL_QP_CMD="npx jest --testPathPattern='(a|b)\\.spec\\.ts'"
RL_QP_ENC="npx jest --testPathPattern='(a%7Cb)\\.spec\\.ts'"

# THE BRIEF CARRIES A VALID `Files:` LINE so the quoted pipe is its ONLY candidate fault.
# Without one the no-instrument arm fires beside it and the refusal leaves on the
# SEVERAL-fault wire, which is a `deny` verdict at exit 0 — a status this row would then
# read as admission, and the whole assertion would be green against the broken lift.
REPO=$(make_repo r18t4a yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w18-qpipe.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}${RL_QP_CMD}${RL_BT}" "w18-qpipe")"
expect_status "18T4a a quoted pipe is not a pipe — the run is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "18T4a2 …and the row carries the run with its pipe percent-encoded" \
  "${RL_BT}${RL_QP_ENC}${RL_BT}" "$(roster_field "$ROW" re_executes)"
# THE SEGMENT COUNT IS THE PROPERTY (S25d5's reasoning). A field that still held the raw
# pipe would read as one more segment to every by-key reader in the fleet.
expect_status "18T4a3 …and the run forged no segment of its own" "1" \
  "$(printf '%s' "$ROW" | tr '|' '\n' | grep -c '^re_executes=' | tr -d ' ')"

# THE OTHER DIRECTION, over the same shape. An UNQUOTED pipe is still shell plumbing and
# is still refused with the token named — the half that keeps 18T4a from being a hole.
REPO=$(make_repo r18t4b yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool — same reason as 16ld1 above.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w18-upipe.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}bash tests/x.test.sh | tee out${RL_BT}" "w18-upipe")"
expect_eq "18T4b an unquoted pipe IS a pipe — the run is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "18T4b2 …naming the fault as a pipe" "a pipe" "$GATE_VERR"
expect_empty "18T4b3 …and no roster row was written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# THE PROSE IS THE THIRD READER (AC-7.1). A wall whose sentence is false for the shape it
# now admits sends the author to fix a command that was never wrong; the detail must say
# UNQUOTED, and must no longer promise that any pipe at all is shell plumbing.
expect_contains "18T4c the detail names the unquoted pipe" "an unquoted pipe" "$GATE_VERR"
expect_absent "18T4c2 …and no longer calls every pipe plumbing" \
  "carrying a pipe" "$GATE_VERR"
# THE EVIDENCE MUST SHOW THE CHARACTER IT NAMES (T5, T4 carry-over). `C_RUNS_BAD` used to
# be sanitized with no field name, so `sanitize` folded this token's `|` to a space — the
# detail said "a pipe" beside a token that, as printed, no longer carried one. Passing the
# `re_executes` field name (the same case that keeps `re_executes=` itself pipe-intact)
# keeps the character in the evidence the classification names.
expect_contains "18T4c3 …and the shown token still carries the pipe it names" \
  "tests/x.test.sh | tee out" "$GATE_VERR"

# ---- AC-8.2 (T5, REQ-8, D12), supersedes AC-1.6: an over-cap span is REFUSED, naming the
# dropped run; unmarked text is not a run ----
# WHAT WAS WRONG. A four-run span used to be ADMITTED with three of the four on the row and
# a `warn()` line nobody in particular reads; the fourth run was left for the writer-side
# budget arm to refuse 40 minutes later, as undeclared, for a fact the author was never told
# at dispatch — the same shape T3 (REQ-8) closed for a dropped `Suites:` token. `RUNS_MAX`
# (3) is unchanged; only the fourth-and-up runs fate is.
REPO=$(make_repo r16le yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "w16-cap")"
# FLIPPED BY DESIGN (wave-20 T4; Δ3, Δ9). The cap of three is the AUDITOR's — its source is
# the auditor mandate's "<=3 re-executions" — and this brief is an implementor's (the
# driver's default role), so four runs is a declaration within SUITES_MAX and is admitted
# with every run on the row. The auditor twin that keeps the refusal is 16le-aud below.
expect_eq "16le a four-run span from an implementor is ADMITTED (the cap of three is the auditor's)" \
  "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "16le …and the row carries the fourth run" "npm test" "$(roster_field "$ROW" re_executes)"

# ---- AC-7.2 (wave-20 T4; REQ-7, Δ3, Δ9): three for auditors, SUITES_MAX for every other role ----
#
# fails-when: a test-runner brief with four runs is refused, an auditor brief with four is
# admitted, or a test-runner brief with 201 is admitted.
REPO=$(make_repo r16le-tr yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap-tr.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "w16-cap-tr" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:test-runner)"
expect_eq "16le-tr a test-runner brief with four runs is ADMITTED" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "16le-tr …and its row carries all four runs" \
  "${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "$(roster_field "$ROW" re_executes)"

REPO=$(make_repo r16le-aud yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap-aud.md
Expected duration: ~20 minutes.
Re-executes: ${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_NPM}" "w16-cap-aud" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:auditor)"
expect_eq "16le-aud an auditor brief with four runs is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16le-aud …naming the fourth (dropped) run" "npm test" "$GATE_VERR"
expect_contains "16le-aud …and the fact names the auditor's 3-run cap" \
  "exceeds the 3-run cap" "$GATE_ERR"
expect_empty "16le-aud …with no roster row written for the refused dispatch" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# 201 RUNS, SUITES_MAX + 1: the count that bounds `Suites:` bounds every other role's runs.
T4_RUNS=""
for _i in $(seq 1 201); do T4_RUNS="$T4_RUNS ${RL_BT}pytest tests/unit/t${_i}.py${RL_BT}"; done
REPO=$(make_repo r16le-201 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-cap-201.md
Expected duration: ~20 minutes.
Re-executes:${T4_RUNS}" "w16-cap-201" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:test-runner)"
expect_eq "16le-201 a test-runner brief with 201 runs is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16le-201 …naming the 201st run" "pytest tests/unit/t201.py" "$GATE_VERR"
expect_contains "16le-201 …against the 200-run cap" "exceeds the 200-run cap" "$GATE_ERR"
expect_empty "16le-201 …with no roster row written" \
  "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"

# THE TEXTS ARE ROLE-AWARE. A not-literal run is refused for every role; only the auditor's
# fix says "at most three". `Files:` and the stub derivation are there so this fault is the
# brief's ONLY one — with a second fault the refusal lists facts and no detail, and the
# absence row below would pass on a detail that was never printed. The positive row
# (`GATE_VERR` carries the not-literal token) proves the detail is on the wire.
REPO=$(make_repo r16le-txt-tr yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-txt-tr.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}pytest \$T${RL_BT}" "w16-txt-tr" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:test-runner)"
expect_eq "16le-txt a test-runner's variable run is refused" "deny" "$GATE_VERDICT"
expect_contains "16le-txt …and its detail is on the wire (non-vacuity)" "pytest \$T" "$GATE_VERR"
expect_absent "16le-txt …and its fix never tells a test-runner three" "at most three" "$GATE_VERR"
REPO=$(make_repo r16le-txt-aud yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-txt-aud.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${RL_BT}pytest \$T${RL_BT}" "w16-txt-aud" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:auditor)"
expect_eq "16le-txt an auditor's variable run is refused" "deny" "$GATE_VERDICT"
expect_contains "16le-txt …and its fix tells the auditor three" "at most three" "$GATE_VERR"

REPO=$(make_repo r16lf yes)
write_attestation "$REPO" "$SID_A"
# THE STUB DERIVATION, not the real tool: the impact command is not under test in this
# section, and the real one over the real tree runs 11-17 s against a 10 s bound under
# wave-scale machine load (measured 2026-09-19), which would make these rows report the
# derivation bound instead of the fault they exist for.
s27_impact "$REPO" widget.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/w16-unmarked.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: npx jest --testPathPatterns 'x' and then pytest tests/unit" "w16-unmarked")"
expect_status "16lf a span with no marks at all is ADMITTED on its Files: line" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lf …and nothing unmarked was lifted as a run" \
  "" "$(roster_field "$ROW" re_executes)"

# ---- AC-1.7: the read-only roles are UNCHANGED — driven at :6531 (33d), unchanged here ----
# A researcher and a test-runner brief with `Suites: none` and no `Re-executes:` are still
# admitted; that is S33's own row 33d, and it is the pin this criterion is discharged by.

# ---- AC-1.8 — the scaffold's OWN placeholder lifts NOTHING (wave-16 T20; walk finding 1) ----
#
# `agents-src/blocks/brief-scaffold.md` carries `` Re-executes: `<cmd>` `` as guidance —
# rendered into dispatch.md verbatim. That is a TEMPLATE, exactly the shape `istemplate()`
# already rejects on the `Files:` and `Suites:` readers (`paths()`/`ispath()` and
# `suite_names()` both call it). `marked_runs()` did not, so a brief that pasted the scaffold
# without filling it in satisfied the suite-allowance wall on a budget entry
# (`` `<cmd>` ``) no real command could ever equal, and `dp_scaffold_marked` — which marks a
# label only when NONE of the three instrument fields is set — read the placeholder as a
# real declaration and left `Files:`/`Suites:`/`Re-executes:` all unmarked.
#
# THE LINE IS READ OUT OF THE SHIPPED FILE, never transcribed, exactly as the rest of this
# section's fixtures are.
RL_RE_EXECUTES_RAW_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Re-executes")"
expect_eq "16lg meta: the scaffold's own Re-executes line, unfilled, out of dispatch.md" \
  'Re-executes: `<cmd>`' "$RL_RE_EXECUTES_RAW_LINE"

# (a) the rendered scaffold placeholder, lifted as written, yields an EMPTY re_executes=
# field — `Suites: none` carries the instrument, so this brief still dispatches, and the
# placeholder must contribute nothing to the row.
REPO=$(make_repo r16lg1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build the widget.
Expected artifact: .bionic/docs/record/w16-scaffold-run.md
Expected duration: ~20 minutes.
Suites: none
${RL_RE_EXECUTES_RAW_LINE}" "w16-scaffold-run")"
expect_status "16lg1 a brief satisfying the instrument via Suites: none still dispatches" \
  "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lg1 …and the scaffold's own placeholder lifts NOTHING onto the row" \
  "" "$(roster_field "$ROW" re_executes)"

# (b) with NO other instrument declared, an unfilled placeholder refuses exactly as an
# absent `Re-executes:` line would, and the several-fault scaffold marks ALL THREE
# instrument labels — reusing `$SM_FILES_LINE`/`$SM_SUITES_LINE` from §scaffold-marks
# above, plus the placeholder line itself as the (unsatisfied) `Re-executes:` line. The
# ambiguous-deliverable line is what keeps this on the several-fault deny wire (two
# faults: ambiguity + no instrument) rather than the single-fault shape, which never
# renders the scaffold at all (see §scaffold-marks (a)).
REPO=$(make_repo r16lg2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes.
${RL_RE_EXECUTES_RAW_LINE}" "w16-scaffold-only")"
expect_status "16lg2 an unfilled placeholder beside another fault reaches the deny wire" \
  "0" "$([ -n "$GATE_DENY" ] && echo 0 || echo 1)"
expect_contains "16lg2 …the Files: line IS marked (the placeholder satisfied nothing)" \
  "${SM_FILES_LINE} <ADD>" "$GATE_VERR"
expect_contains "16lg2 …the Suites: line IS marked" \
  "${SM_SUITES_LINE} <ADD>" "$GATE_VERR"
expect_contains "16lg2 …and the Re-executes: line ITSELF is marked, not read as satisfied" \
  "${RL_RE_EXECUTES_RAW_LINE} <ADD>" "$GATE_VERR"

# (c) a real marked run BESIDE the scaffold's placeholder lifts exactly the real run — the
# placeholder neither shadows it nor occupies one of the three cap slots.
RL_PLACEHOLDER="${RL_BT}<cmd>${RL_BT}"
REPO=$(make_repo r16lg3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: re-run the unit tests.
Expected artifact: .bionic/docs/record/w16-scaffold-run3.md
Expected duration: ~20 minutes.
Re-executes: ${RL_PYTEST} ${RL_PLACEHOLDER}" "w16-mixed-run")"
expect_status "16lg3 a real run beside the scaffold's placeholder is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16lg3 …and only the real run reaches the row; the placeholder lifts nothing" \
  "$RL_PYTEST" "$(roster_field "$ROW" re_executes)"

# ============================================================================
section "§two-deliverables — two deliverable labels, two paths, one refusal (REQ-12 AC-12.1)"
# ============================================================================
#
# THE CARRY-OVER THIS CLOSES (row 14; research R3 row 35). `decl_deliverable` walked the
# deliverable-kind label hits in position order and returned the paths of the FIRST that
# yielded any — so a brief carrying `Expected artifact: a.md` and, lower down, a real
# `Deliverable: b.md` line was contracted to whichever came first, recorded `source=declared`
# as though a human had named one, with the other path silently discarded. The rule was
# POSITION, never label rank, and the ambiguity wall never saw two paths because each hit
# owned its own span.
#
# THE FIX IS THE WALL THIS FILE ALREADY HAS. The walk now unions the distinct paths of every
# deliverable-kind hit, so two labels naming two paths reach `deliverable_ambiguous=` exactly
# as one label naming two paths always has — one refusal, both candidates handed back, no
# guess. The same path under both labels is one path and is admitted: an author who repeated
# themselves has not created an ambiguity.
#
# fails-when: the two-path brief is admitted with one of the paths on the row, or the
# one-path brief is refused.

REPO=$(make_repo r16ma yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: write the report.
Expected artifact: .bionic/docs/record/w16-a.md
Deliverable: .bionic/docs/record/w16-b.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh" "w16-two-deliv")"
expect_eq "16ma two deliverable labels naming two paths is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "16ma …on the ambiguity arm, not on a guess" \
  "the deliverable label names several paths" "$GATE_ERR"
expect_contains "16ma …handing back the first candidate" \
  ".bionic/docs/record/w16-a.md" "$GATE_VERR"
expect_contains "16ma …and the second" \
  ".bionic/docs/record/w16-b.md" "$GATE_VERR"
expect_status "16ma …and no roster row was journalled" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

REPO=$(make_repo r16mb yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: write the report.
Expected artifact: .bionic/docs/record/w16-a.md
Deliverable: .bionic/docs/record/w16-a.md
Expected duration: ~20 minutes.
Suites: tests/widget.test.sh" "w16-one-deliv")"
expect_status "16mb the same path under both labels is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "16mb …and that one path is the contract on the row" \
  ".bionic/docs/record/w16-a.md" "$(roster_field "$ROW" deliverable)"

# ============================================================================
section "§no-listagents — no brief, in any session state, is told to call ListAgents"

# READ OF THE DRIVER SWEEP INSTALLED IN run_gate. Every payload this file drives — every
# brief shape, every roster, every transcript state, allowed and refused, line and
# detail — has passed through that case statement by the time this runs. AC-4.1 is "any
# brief in any state", and this is the only assertion in the suite that can carry it.
expect_eq "no dispatch this suite drove asked for a ListAgents call" "" "${DP_NLA_HITS:-}"

# THE TWO ANTI-VACUITY ARMS. An empty counter proves nothing unless the sweep both RAN
# and DISCRIMINATES. The first says it ran over real traffic — a run_gate that never
# reached the case statement would leave this at zero. The second says the predicate
# still catches the retired string, so the row above is empty because no dispatch
# printed it, not because the test stopped looking.
expect_eq "…having swept every payload this suite drove (the sweep is not dead code)" \
  "yes" "$([ "${DP_NLA_SWEPT:-0}" -gt 100 ] && echo yes || echo "no: ${DP_NLA_SWEPT:-0}")"
DP_NLA_PROBE=""
case "bionic: dispatch refused — call ListAgents, then dispatch" in
  *"call ListAgents"*) DP_NLA_PROBE="caught" ;;
esac
expect_eq "…and the sweep's own predicate still catches that string when it is present" \
  "caught" "$DP_NLA_PROBE"

section "AC-E1.3/E1.5 — every refusal this gate makes is one line, in the shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`.
#
# WHY A WRAPPER AND NOT ONE ROW PER SITE. This gate has sixteen refusal sites behind
# three frames, and every one of them is already driven somewhere above. `run_gate` is
# wrapped here so that EVERY refusal the rest of this suite produced was checked as it
# happened — shape, line count and column budget — and the counter proves the sweep saw
# real refusals rather than counting over air.


expect_eq "E1.3 the gate refused at least ten times in this run (not counting over air)" "yes" \
  "$([ "${DP_E1_SEEN:-0}" -ge 10 ] && echo yes || echo no)"
expect_eq "E1.3 every refusal matched the criterion's shape" "" "${DP_E1_BAD_SHAPE:-}"
expect_eq "E1.3 every refusal was exactly one line" "" "${DP_E1_BAD_LINES:-}"
expect_eq "E1.3 every refusal fitted the 100-column budget" "" "${DP_E1_BAD_COLS:-}"
# THE UNCOVERED SITE, named rather than silently tolerated: `live-agents:` has no row in
# the task-12 wording table, so it still speaks in its own voice. Any OTHER refusal that
# renders no line fails here.
expect_eq "E1.3 the only refusals with no rendered line are the uncovered live-agents site" \
  "" "${DP_E1_UNNAMED:-}"

# THE TABLE'S EXACT WORDING at three sites, one per frame: the environment frame, the
# Patrol frame, and a direct arm.
REPO=$(make_repo re13b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "w-e13b")"
expect_eq "E1.3 row 48 (no deliverable) is the table's line" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"

# AC-E1.5, the pair: the user stream LEADS with the verdict line, and the knob carries the
# frame's Fix block.
#
# RE-AUTHORED FROM A LINE COUNT TO THE LINE (REQ-2, D2/ADR-030; A-orch-13/A-orch-14). This
# assertion used to read "the Fix block is NOT on the user stream", which was the 1.8.2
# reading of AC-E1.5: an `exit2` refusal rendered its one line and nothing else, so the
# absence of any detail text WAS the criterion. D2 reverses that by Chris's own call — an
# `exit2` refusal now prints its bounded violation detail under the verdict — and an absence
# pin would red at the wave head for the change it was never about. What AC-E1.5 has always
# been about is that the READER GETS THE VERDICT: one line, in the table's words, first.
# That claim holds on both sides of the flip, and it is what is pinned here.
# THE FIRST `bionic: ` LINE, not the first line and not the only line. The user stream can
# carry an advisory above the verdict — this very fixture draws `dispatch-preflight: run
# resolved by newest-plan fallback` — and under D2 it carries bounded detail below it, so
# both edges of the refusal are lines this assertion must not count.
expect_eq "E1.5 the verdict reaches the USER stream, in the table's words" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | awk '/^bionic: / { print; exit }')"
expect_contains "E1.5 …and BIONIC_WALL_VERBOSE=1 puts it back" \
  "Then retry the dispatch" "$GATE_VERR"
expect_contains "E1.5 …with the one line still in it" \
  "bionic: dispatch refused — this brief names no deliverable" "$GATE_VERR"

# ============================================================
section "§brief-lib — the contract grammar is one library (wave-20 T6; REQ-4, D4, Δ10)"
# ============================================================
#
# A VALID CONTRACT IS DEFINED ONCE (Δ10). The lift, its caps, and every check the lifted
# Files:/Suites:/Re-executes: fields feed live in payload/scripts/lib/brief.sh, so `amend` (T9)
# and `task-add` hold an amended or added contract to exactly a fresh dispatch's standard.
# Every row above this section drives the hook and is the refactor's proof that nothing moved
# in behaviour; the rows here drive the library ALONE, with no hook around it, which is how
# its other two callers will meet it. tests/cross-gate-agreement.test.sh §S13c asks the two
# doors for one verdict on the same fields.
BRIEF_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh"
BRIEF_NOCONF="$SANDBOX/brief-noconf"; mkdir -p "$BRIEF_NOCONF"
BRIEF_CONF="$SANDBOX/brief-conf"; mkdir -p "$BRIEF_CONF/.bionic"
printf 'impact-command: bash stub-impact.sh\n' > "$BRIEF_CONF/.bionic/config.yaml"
BT='`'
# brief_verdict <role> <root> <brief text> -> one `finding: <fact>` or `warn: <line>` per sink
# call, then `rc=`, `suites=` and `source=`. The library is sourced by nothing but this
# shell, so a dependency it forgets to bring in is a failure here and not a pass on a
# neighbour's load.
brief_verdict() {
  bash -c '
    . "$1" || exit 9
    sink() { case "$1" in finding) printf "finding: %s\n" "$2" ;; warn) printf "warn: %s\n" "$2" ;; esac; }
    rc=0
    brief_validate_fields "$(lift_contract_fields "$4" "$2")" "$2" "$3" sink || rc=$?
    printf "rc=%s\nsuites=%s\nsource=%s\n" "$rc" "${BRIEF_SUITES_ALLOWED-}" "${BRIEF_SUITES_SOURCE-}"
  ' _ "$BRIEF_LIB" "$1" "$2" "$3" 2>&1
}

expect_eq "brief-lib the library sources alone and carries the grammar, its caps and the checker" \
  "ok 200 3" "$(bash -c '. "$1" || exit 9
    for f in sanitize lift_contract_fields dp_runs_cap dp_runs_cap_words brief_field brief_validate_fields; do
      declare -F "$f" >/dev/null || { echo "missing $f"; exit 0; }
    done
    echo "ok $DP_SUITES_MAX $DP_AUDITOR_RUNS_MAX"' _ "$BRIEF_LIB" 2>&1)"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Suites: tests/one.test.sh, tests/two.test.sh")
expect_contains "brief-lib a declared set passes clean (rc=0)" "rc=0" "$BV"
expect_absent   "brief-lib …with no finding" "finding:" "$BV"
expect_contains "brief-lib …and IS the suite set, recorded as declared" "source=declared" "$BV"
expect_contains "brief-lib …holding the declared basenames" "one.test.sh" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" 'Suites: tests/$X.test.sh')
expect_contains "brief-lib an unexpanded suite name is refused" "finding: a declared suite is not a literal name" "$BV"
expect_contains "brief-lib …and a finding answers rc=1" "rc=1" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Suites: tests/unit/foo.spec.ts")
expect_contains "brief-lib a suite the shell runner cannot run is refused" \
  "finding: Suites: names a file the shell runner cannot run" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Re-executes: ${BT}npx jest x | tee log${BT}")
expect_contains "brief-lib a run with an unquoted pipe is refused" "finding: a declared run is not a literal command" "$BV"

BV_FOUR="Re-executes: ${BT}go test ./a${BT}, ${BT}go test ./b${BT}, ${BT}go test ./c${BT}, ${BT}go test ./d${BT}"
BV=$(brief_verdict bionic:auditor "$BRIEF_NOCONF" "$BV_FOUR")
expect_contains "brief-lib an auditor's fourth run passes the auditor's cap of three" \
  "finding: Re-executes: line exceeds the 3-run cap" "$BV"
BV=$(brief_verdict implementor "$BRIEF_NOCONF" "$BV_FOUR")
expect_contains "brief-lib …while the same four runs pass clean for a writer" "rc=0" "$BV"

BV=$(brief_verdict bionic:auditor "$BRIEF_NOCONF" "Suites: none")
expect_contains "brief-lib an auditor that waives every suite is refused" "finding: an auditor names no suites" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Expected duration: ~5 minutes.")
expect_contains "brief-lib a brief with no instrument is refused" \
  "finding: this brief declares no Files: and no Suites:" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib Files: where no impact command is configured is refused" \
  "finding: no impact command is configured here" "$BV"

printf '#!/bin/bash\nprintf "beta.test.sh\\tpath-ref\\nalpha.test.sh\\tself\\nalpha.test.sh\\tpath-ref\\n"\n' > "$BRIEF_CONF/stub-impact.sh"
BV=$(brief_verdict implementor "$BRIEF_CONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib Files: under an impact command derives the suite set" "suites=alpha.test.sh beta.test.sh" "$BV"
expect_contains "brief-lib …recorded as derived" "source=derived" "$BV"
expect_contains "brief-lib …and passes clean" "rc=0" "$BV"

printf '#!/bin/bash\nexit 0\n' > "$BRIEF_CONF/stub-impact.sh"
BV=$(brief_verdict implementor "$BRIEF_CONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib a derivation that answers nothing is a warning through the sink, not a finding" \
  "warn: the impact command derived no suites from the declared files" "$BV"
expect_absent "brief-lib …never a finding" "finding:" "$BV"

printf '#!/bin/bash\nsleep 8\n' > "$BRIEF_CONF/stub-impact.sh"
BV=$(IMPACT_BOUND_S=1 brief_verdict implementor "$BRIEF_CONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib a derivation past its bound is a finding" "finding: the impact command did not answer" "$BV"
expect_contains "brief-lib …answered rc=2, so the door knows the suite set was never built" "rc=2" "$BV"

expect_eq "brief-lib brief_field hands back the Files: set as the row stores it" \
  "payload/a.sh,payload/b.sh" \
  "$(bash -c '. "$1" || exit 9; brief_field "$(lift_contract_fields "Files: payload/a.sh, payload/b.sh")" files' _ "$BRIEF_LIB" 2>&1)"

finish
