# tests/dispatch-preflight.prelude.sh — sourced by the four dispatch-preflight shards.
#
# NOT A SUITE. It matches no `tests/*.test.sh`, so the runner never launches it, and it
# sits beside the shards rather than under tests/lib/, so an edit here reaches these four
# suites and not the whole roster (wave-30 design ledger D8). A shard sources the framework
# and the shared libraries first, then this file.
#
# THE FIRST PART is the unsplit suite's own prelude, unchanged: the paths of the code under
# test, the scaffold readers, the sandbox and its cleanup trap, the payload builders, run_gate,
# the fixture-loss guard and its DEBUG trap, and the attestation writers.
#
# THE MAP FOLLOWS THIS FILE. tests/lib/impact.sh takes a `tests/*.prelude.sh` a suite sources
# as a transitive hop, like a tests/lib helper (wave-30 T1, ruling A-orch-23), so every path
# named here reaches each shard. An edit to this file reaches the four shards and no more.
#
# THE SECOND PART holds what a section defined and a section in another shard reads:
# helpers and constant strings, each block moved whole from the section named above it,
# with a pointer left where it was.

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
# .claude/rules/test-harness.md, "Fixture fidelity").
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
# (.claude/rules/test-harness.md, "Fixture fidelity"). The absence path gets its
# own bare-brief fixture in S10c, and both directions are asserted.
BRIEF_FULL='Canonical-sdlc Step 4, task 4/9 of epic-99 wave-01; build · double · wave.
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
  # T57: no wall runs on a fixture that was never made (fixture_drive_ok, beside make_repo).
  if ! fixture_drive_ok "$(printf '%s' "$1" | jq -r '.cwd // ""' 2>/dev/null)"; then
    GATE_OUT=""; GATE_ERR="fixture lost: $FIXTURE_LOST"; GATE_VERR=""; GATE_REASON=""; GATE_DENY=""
    GATE_ST=97; GATE_VERDICT="fixture-lost"; return 0
  fi
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
    # refuse.sh REFUSING ITS OWN CALL fits the shape, but the author never sees the real fault
    # (wave-22 T13; critic-3598752 I1).
    case "$_dp_line" in "bionic: refuse-call refused"*) DP_E1_BAD_SHAPE="${DP_E1_BAD_SHAPE:-}[$_dp_line] " ;; esac
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

# ONE STAGED SEED, COPIED (wave-28 T20). Every fixture repository starts as the same four steps
# — init, two config lines, README.md staged — and this file builds a few hundred of them, so
# the four are run once here into $MAKE_REPO_SEED and each make_repo copies the result. The
# commit stays per repository, so each one's HEAD is made when its fixture is, as before. A
# name already holding a repository, or a seed that was not made, takes the four steps itself.
MAKE_REPO_SEED="$SANDBOX/.make-repo-seed"
make_repo_seed() {
  mkdir -p "$MAKE_REPO_SEED" \
    && git -C "$MAKE_REPO_SEED" init -q 2>/dev/null \
    && git -C "$MAKE_REPO_SEED" config user.email t@example.com \
    && git -C "$MAKE_REPO_SEED" config user.name "T" \
    && echo seed > "$MAKE_REPO_SEED/README.md" \
    && git -C "$MAKE_REPO_SEED" add README.md \
    || rm -rf "$MAKE_REPO_SEED"
}
make_repo_seed

# make_repo <name> <active-wave:yes|no> -> echoes the repo path
make_repo() {
  local name="$1" wave="$2"
  local repo="$SANDBOX/$name/repo"
  mkdir -p "$repo"
  if [ ! -e "$repo/.git" ] && [ -f "$MAKE_REPO_SEED/.git/index" ] \
     && cp -R "$MAKE_REPO_SEED/." "$repo/" 2>/dev/null; then
    :
  else
    git -C "$repo" init -q 2>/dev/null
    git -C "$repo" config user.email t@example.com
    git -C "$repo" config user.name "T"
    echo seed > "$repo/README.md"
    git -C "$repo" add README.md
  fi
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
rigor: double
scale: wave
---

# Test wave plan

## SDLC State

integration-branch: main
current: 4
approved-by: dana 2026-09-07T19:05Z "approved"

- Step 4: tasks in flight
PLAN
    # A LIVE WAVE'S SESSIONS ARE BOUND TO IT (wave-23-fixit-1810, REQ-1, D1). An empty marker
    # beside an open plan is the UNBOUND state, whose `fallback` plan is announced and never
    # acted on — so a fixture that meant "this session is running this wave" and left the
    # marker empty would now test the unbound arm in every case of the file. The binding is
    # written through the real `bind_plan` (tests/lib/bound-marker.sh), which stores the
    # canonical path. Sections that drive the unbound state unbind explicitly (S25).
    local _pplan
    _pplan="$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
    for _psid in "${SID_A:-}" "${SID_B:-}" "${SID_DEAD:-}" "${SID_LIVE:-}"; do
      [ -n "$_psid" ] || continue
      bound_marker "$repo" "$_psid" "$_pplan"
    done
  fi
  # A repository with no commit is not the fixture asked for: answer nothing, and fail (T57).
  git -C "$repo" rev-parse -q --verify HEAD >/dev/null 2>&1 || return 1
  printf '%s' "$repo"
}

# A FIXTURE WHOSE REPOSITORY WAS NOT MADE FAILS ITS ROWS BY NAME (wave-27 T57; review pass 35 N6).
# Under fork pressure `REPO=$(make_repo …)` came back empty: the fixture then wrote toward `/`, the
# wall ran inert and answered allow, and a row expecting allow passed having tested nothing. Three
# parts, each in one place:
#   - the take: the guard is on the VALUE. A DEBUG trap notes each `<var>=$(make_repo …)` and,
#     before the next command at that subshell level ($BASH_SUBSHELL: the suite runs under
#     /bin/bash 3.2, which has no BASHPID), reads <var>: empty, whatever make_repo exited
#     with (a dying subshell, make_repo's own check above, or nothing printed at all), it points
#     <var> at a path under "$SANDBOX/.lost/" before any word is expanded, so no path is ever
#     built from an empty value and every write the fixture goes on to make lands in the sandbox;
#   - the drive: run_gate refuses to run the wall on a payload whose cwd is under .lost, empty
#     (unless the row sets GATE_CWD_FREE=1) or outside the sandbox, and names the fixture;
#   - the rows: while a fixture is lost, `ok` fails each row by its own name (the framework's row
#     guard, below), so no row passes on a wall that never ran. The next drive on a made fixture
#     clears it.
FIXTURE_LOST=""; FIXTURE_LOST_N=0
SANDBOX_P="$(cd "$SANDBOX" && pwd -P)"
FIXTURE_TAKE=""; FIXTURE_TAKE_LEVEL=""; FIXTURE_TAKE_CMD=""
fixture_take_guard() {
  if [ -n "$FIXTURE_TAKE" ] && [ "$FIXTURE_TAKE_LEVEL" = "$BASH_SUBSHELL" ]; then
    local v="$FIXTURE_TAKE"; FIXTURE_TAKE=""
    if [ -z "${!v}" ]; then
      FIXTURE_LOST_N=$((FIXTURE_LOST_N + 1))
      printf -v "$v" '%s' "$SANDBOX/.lost/$v-$FIXTURE_LOST_N"
      FIXTURE_LOST="$FIXTURE_TAKE_CMD"
    fi
  fi
  case "$BASH_COMMAND" in
    *'=$(make_repo '*)
      case "${BASH_COMMAND%%=*}" in ''|*[!A-Za-z0-9_]*) return 0 ;; esac
      FIXTURE_TAKE="${BASH_COMMAND%%=*}"; FIXTURE_TAKE_LEVEL="$BASH_SUBSHELL"; FIXTURE_TAKE_CMD="$BASH_COMMAND" ;;
  esac
}
set -o functrace
trap fixture_take_guard DEBUG
fixture_drive_ok() {  # <payload cwd> -> 0 when the wall may run on it; else FIXTURE_LOST is named
  case "$1" in
    "$SANDBOX"/.lost/*) FIXTURE_LOST="${FIXTURE_LOST:-$1}" ;;
    '') [ -n "${GATE_CWD_FREE:-}" ] && FIXTURE_LOST="" || FIXTURE_LOST="${FIXTURE_LOST:-a payload with no cwd}" ;;
    "$SANDBOX"/*|"$SANDBOX_P"/*) FIXTURE_LOST="" ;;
    *) FIXTURE_LOST="${FIXTURE_LOST:-$1, outside the sandbox}" ;;
  esac
  [ -z "$FIXTURE_LOST" ]
}
# The rows' part is the framework's row guard (tests/lib/assert.sh, THE ROW GUARD; T80): ok()
# asks this function first and records a named fail while it prints a reason.
fixture_row_guard() {
  [ -z "$FIXTURE_LOST" ] || printf 'fixture lost: %s made no repository, so this row tested nothing' "$FIXTURE_LOST"
}
TF_ROW_GUARD=fixture_row_guard

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

# ======================================================================================
# HOISTED FROM THE SECTIONS (wave-30 T1). Read by sections in more than one shard.
# ======================================================================================

# ---- from S18: fix_example ----
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

# ---- from S18: BRIEF_THREE_FAULTS ----
# THE THREE-FAULT BRIEF (wave-12 T2, spec D3, AC-1.1/AC-1.2). One brief that trips three
# brief-shape arms at once: the deliverable label offers two candidates (A11), which leaves
# `deliverable=` empty with no waiver behind it (A13), and no instrument is declared at all
# (A14). It is the shape Chris met on 2026-09-13 — six dispatches to spawn one researcher,
# because the gate exited at the first fault every time — and the §combined section below
# reads the whole refusal. It is defined in S18 because the self-consistency loop there is the
# first thing that drives it.
BRIEF_THREE_FAULTS='Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes'

# ---- from S21: s21_stamp_path, s21_backdate, s21_iso, s21_idle_tr, s21_busy_tr, s21_stale_payload ----
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

# ---- from S21: s21_plant ----
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

# ---- from S21: s22_set_budget, s22_roster_row, s22_sweep, S22_LEDGER_SCHEMA, s22_ack, s22_fake_tree ----
# s22_set_budget <repo> <budget value> — insert `parallel-budget:` into the plan's
# leading frontmatter block (the plan fixture's first line is the opening `---`).
s22_set_budget() {
  local plan="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" val="$2"
  awk -v v="$val" 'NR == 1 && $0 == "---" { print; print "parallel-budget: " v; next } { print }' \
    "$plan" > "$plan.tmp" && mv "$plan.tmp" "$plan"
}

# s22_roster_row <repo> <sid> <name> [claims] [subagent_type] — one launch row in the shipped
# schema; the type defaults to `implementor`, the writer every earlier section planted.
s22_roster_row() {
  local f; f="$(roster_path "$1" "$2")"
  mkdir -p "$(dirname "$f")"
  # No `plan=`: these rows are counted by the budget arm, which reads `status=` and
  # `claims=` and nothing else, and `roster_row_no_plan` is the shape this fixture has
  # always had (tests/lib/roster-row.sh, S14).
  roster_row_no_plan status=intended "session=$2" "name=$3" agent_id= \
    launched_at=2026-09-02T00:00:00Z "subagent_type=${5:-implementor}" model= \
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

# ---- from S27: s27_impact, BRIEF_FILES ----
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

BRIEF_FILES='Canonical-sdlc Step 4, task 4/13 of epic-99 wave-01; build · double · wave.
Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-files.md
Expected duration: ~20 minutes.
Files: payload/scripts/lib/widget.sh, hooks/widget-guard.sh'

# ---- from S28: PF_LIB_DIR, PF_FULL_BRIEF, pf_repo, pf_commit, pf_plan_path, pf_row, PF_FRONT_EXTRA, PF_STATE_EXTRA, pf_plan, pf_state, pf_line ----
PF_LIB_DIR="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
[ -r "$PF_LIB_DIR/proof.sh" ] || PF_LIB_DIR="${BIONIC_HOOKS_DIR}/../scripts/lib"

# The floor row lands no code, so its brief names no landing suite (wave-28 T7, ruling A-orch-73: a
# writer brief that binds a row, as `w99-T12` binds T12, carries a Lands-on: line).
PF_FULL_BRIEF='Your task: run the full suite on the working head.
Expected artifact: .bionic/docs/record/w28-floor.log
Expected duration: ~40 minutes.
Lands-on: none the floor row proves the head with the full suite and lands no code
Suites: tests/run.sh'

# pf_repo <name> -> a wave fixture checked out on `wave/99-test`, five suites. It names no
# impact command: the map is gone (wave-31 T2), and nothing the full-run wall reads is in config.
pf_repo() {
  local repo s
  repo=$(make_repo "$1" yes)
  git -C "$repo" checkout -q -b wave/99-test 2>/dev/null
  mkdir -p "$repo/tests" "$repo/lib"
  for s in a b c d e; do printf '#!/bin/bash\n' > "$repo/tests/$s.test.sh"; done
  printf 'one\n' > "$repo/lib/one.sh"
  printf 'every\n' > "$repo/lib/every.sh"
  git -C "$repo" add tests lib
  git -C "$repo" commit -qm base 2>/dev/null
  printf '%s' "$repo"
}
# pf_commit <repo> <path> <content> -> one commit on whatever the checkout holds.
pf_commit() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "change $2" 2>/dev/null
}
pf_plan_path() { printf '%s/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md' "$1"; }
# pf_row <id> <step> <status> <Files> [<kind> [<deps>]] -> one `## Tasks` data row (a build row
# with no deps unless told otherwise).
pf_row() {
  printf '| %s | %s | %s | does the thing | implementor | %s | 30 | REQ-1 | %s | — | %s |' \
    "$1" "$2" "${5:-build}" "${6:-—}" "$4" "$3"
}
# pf_plan <repo> <floor head, or empty> [<row>...] — the plan, written whole: a `## Tasks`
# heading closes `## SDLC State`, so a proof or cause line appended after it would be outside
# the section. PF_STATE_EXTRA, when set, is one more line inside `## SDLC State`; PF_FRONT_EXTRA,
# when set, is one more frontmatter line (the plan's `regression:` key, wave-31 T26).
PF_STATE_EXTRA=""
PF_FRONT_EXTRA=""
pf_plan() {
  local repo="$1" head="$2" row; shift 2
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf 'intent: build\nrigor: double\nscale: wave\n'
    [ -z "$PF_FRONT_EXTRA" ] || printf '%s\n' "$PF_FRONT_EXTRA"
    printf -- '---\n\n# Test wave plan\n\n'
    printf '## SDLC State\n\n'
    printf 'integration-branch: main\nworking-branch: wave/99-test\ncurrent: 5\n'
    printf 'approved-by: dana 2026-09-07T19:05Z "approved"\n\n'
    printf -- '- Step 5: verify\n'
    [ -z "$head" ] || \
      printf 'proved: kind=floor head=%s at=2026-10-04T00:00:00Z evidence=record/w99-floor.txt\n' "$head"
    [ -z "$PF_STATE_EXTRA" ] || printf '%s\n' "$PF_STATE_EXTRA"
    if [ "$#" -gt 0 ]; then
      printf '\n## Tasks\n\n'
      printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |\n'
      printf -- '|---|---|---|---|---|---|---|---|---|---|---|\n'
      for row in "$@"; do printf '%s\n' "$row"; done
    fi
  } > "$(pf_plan_path "$repo")"
}
# pf_state <repo> -> what proof_state prints for the fixture's plan and tree.
pf_state() {
  ( . "$PF_LIB_DIR/proof.sh" >/dev/null 2>&1; proof_state "$(pf_plan_path "$1")" "$1" ) 2>/dev/null
}
pf_line() { printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: '; }

# ---- from §runs-lift: RL_BT, RL_JEST, RL_PYTEST, RL_GO, RL_NPM ----
# THE MARK, HELD IN A VARIABLE. A backtick inside a double-quoted string here would be a
# command substitution, and a backtick pair inside a double-quoted ASSERTION NAME is the
# fault cross-gate §B pins against tree-wide. Every run below is built from this.
RL_BT='`'
RL_JEST="${RL_BT}npx jest --testPathPatterns 'x'${RL_BT}"
RL_PYTEST="${RL_BT}pytest tests/unit${RL_BT}"
RL_GO="${RL_BT}go test ./...${RL_BT}"
RL_NPM="${RL_BT}npm test${RL_BT}"
