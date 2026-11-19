# tests/cross-gate-agreement.prelude.sh — THE HALF OF THE CROSS-GATE AGREEMENT SUITE BOTH PARTS SHARE
#
# Sourced by tests/cross-gate-agreement-1.test.sh and -2.test.sh, after tests/lib/resolve-roots.sh,
# plan-fixture.sh and assert.sh. It is not a suite: the runner launches `*.test.sh` only. It sits beside the
# parts rather than under tests/lib/ so the reads index follows it from each part's `source` line, one hop
# (lib/anchors.sh, the prelude hop).
#
# WHY TWO PARTS. One cross-gate-agreement.test.sh of 82 sections ran past half the suite bar on the gate
# and grew with every wave (lib/line.sh LINE_SUITE_BAR, ten minutes of promise; D1). It is cut at a section
# boundary into two suites, every section kept whole and in its order: part 1 holds §A1 through §BP, part 2
# holds §CG through §WIDTH. The cut sits where the two halves cost about the same on the gate.
#
# WHAT IT HOLDS. Everything the old file held above its first section: the sandbox, the pins, the parties, the
# payload builders and fixture drivers; then, marked with the section each came from, each helper or constant
# a section of part 1 defined that a section of part 2 calls. Each of those sections keeps a one-line pointer
# where the definition stood.
#
# WHAT IT NEVER HOLDS. A fixture: a repository one section builds and a later one reads is not a helper, so
# those sections share a part instead. None crosses the cut today.
#
# WHAT THIS SUITE IS FOR, and what it deliberately is not:
#
#   The per-script suites (preflight-probe, dispatch-preflight, stop-check and stop
#   suites) each drive ONE component against its own contract. Every
#   one of them is green while four byte-identical copies of active-wave
#   detection drift apart, because no single-component suite ever asks the other
#   copies the same question. This suite asks all four the SAME question with the
#   SAME fixture and compares the answers. It adds no per-component assertions.
#
# HERMETIC. Throwaway git repos under a mktemp'd sandbox; HOME and
# CLAUDE_CONFIG_DIR redirected into it (the evidence gate appends findings under
# $HOME/.claude/logs — nothing here may touch the real one). No live wave, no
# installed hooks, no network.
#
# THE TWO ROOTS ARE DELIBERATELY DIFFERENT. `$CLAUDE_CONFIG_DIR` is NOT
# `$HOME/.claude` here, because "where Claude Code stores session and project
# metadata" is computed at three sites in this wave and holding the two roots
# equal makes every disagreement between them invisible.
# Every metadata fixture below is
# planted under $CLAUDE_CONFIG_DIR, which is what the platform does when the
# variable is set; §C case 5 plants under $HOME/.claude and proves it is NOT
# seen.
#

# THE DETAIL IS ON, FOR THE WHOLE SUITE (task 13, ruling D-1). Since the migration a
# wall's user stream is ONE line — `bionic: <verb> refused — <fact> (<fix>)` — and every
# FACT this file cross-checks between hooks (a resolved path, a derived step, a roster
# id, a live version constant, a main checkout) travels in `detail`. That is the right
# reading for this suite and not a loosening: what a USER sees is each hook's own suite's
# subject and tests/refuse.test.sh's, while this file is about whether two hooks agree
# about the world. `BIONIC_WALL_VERBOSE=1` is the knob that asks a wall for its facts.
export BIONIC_WALL_VERBOSE=1
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"

REPO_ROOT="${BIONIC_SCRIPTS_DIR}"

# The four parties. Overridable so the suite can be driven against a MUTATED
# COPY of any one of them without the shipped file ever being modified — that
# substitution is how §9's mutation-and-restore proof is taken here, and how a
# reviewer can re-take it by hand:
#   W1R_PARTY_DP=/tmp/mutant.sh bash tests/cross-gate-agreement-1.test.sh   (either part)
PARTY_DP="${W1R_PARTY_DP:-$BIONIC_HOOKS_DIR/dispatch-preflight.sh}"
# The stop gate is hooks/stop.sh, which answers the orchestrator's stop of an agent by its event.
PARTY_SG="${W1R_PARTY_SG:-$BIONIC_HOOKS_DIR/stop.sh}"
PARTY_ER="${W1R_PARTY_ER:-$BIONIC_HOOKS_DIR/execution-recorder.sh}"

PROBE="$BIONIC_HOOKS_DIR/preflight-probe.sh"
OBSERVE="$BIONIC_HOOKS_DIR/stop-check.sh"
SWEEPER="$BIONIC_HOOKS_DIR/session-sweeper.sh"
# The landing gate (epic-16 wave-01) is a fifth party and an overridable one for
# the same reason the four above are: §J drives a MUTATED COPY of it to prove the
# verdict/gate battery discriminates, and the shipped file is never touched.
# THE LANDING SWEEP IS A FUNCTION NOW (epic-23 wave-11, T12): `stop_landing_gate` in
# payload/scripts/lib/stop.sh, run by hooks/stop.sh. TWO NAMES, because the sections below
# want two different things and one name would let a section silently read the wrong file:
# $PARTY_LG is the process a fixture DRIVES, $PARTY_LG_SRC is the file a mutation or a
# source extraction READS. A mutation of the sweep is a LIBRARY edit now, so every mutant
# below plants a tree and drives the unmutated hook against its own doctored library.
PARTY_LG="${W1R_PARTY_LG:-$BIONIC_HOOKS_DIR/stop.sh}"
PARTY_LG_SRC="${W1R_PARTY_LG_SRC:-${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh}"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/w1r-agreement.XXXXXX")" && pwd -P)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS; do kill -9 "$p" 2>/dev/null; done
  rm -rf "$SANDBOX"
}
trap cleanup EXIT
export HOME="$SANDBOX/home"
export CLAUDE_CONFIG_DIR="$SANDBOX/cfg"     # NOT $HOME/.claude — see the header
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME/.claude"
# THE SHARE IS FIXTURE DATA TOO (wave-31 T34; A-orch-38, the pin tests/session-poker.prelude.sh keeps as
# SP_CONFIG_DIR). The gate reads the share from ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share and the
# default is 92 since T10, so a suite that planted none read this machine's file or the default, and §ROOM's
# widths (written against 80: "the five-minute load over 6.4 cores" is 8 cores x 0.80) and the CG-ledger
# hold's precondition came out wrong. The fixture's own CLAUDE_CONFIG_DIR above is the pinned dir: it holds
# the share, and every NENV / env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" below carries it along. HOME is not
# pinned to it (the header's two roots stay different); a section that points the variable elsewhere
# (`no-such-config`) reads the default and asks no width of it.
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"
printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
# THE GATE IS FIXTURE DATA (wave-28 T13; D14). The tick and the stop wall size their fill at the
# gate, which reads the machine through the readers' pins and its store at BIONIC_GATE_DIR: 8
# cores, 30% used, a load of 1.0 over the last minute and the last five; every command is promised
# one core (wave-33 T1; Δ10: the cost line below is a duration the gate no longer reads cores from),
# so a width is the fixture's cap, its ready rows or the gate's room, never this host's load.
# §ROOM and CG-budget plant their own.
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
export BIONIC_GATE_DIR="$SANDBOX/gate"
mkdir -p "$BIONIC_GATE_DIR/requests" "$BIONIC_GATE_DIR/cost"
printf '5:0.1:30:1000\n' > "$BIONIC_GATE_DIR/cost/fixture.test.sh"
# Since task 4/5, hooks/stop-check.sh reads CLAUDE_CODE_SESSION_ID; since S6 it reads it to
# find the session TRANSCRIPT the live set is recorded in, which is the whole of resolution.
# This suite runs inside a real Claude Code session, which exports a real one, and an
# unpinned call would read THAT session's live set — the suite's hermetic claim quietly false.
# So it is unset here and pinned per call, to the fixture session, everywhere a party has to
# resolve anything.
unset CLAUDE_CODE_SESSION_ID

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="1f4a7c02-3bd9-4e15-8a66-90c1de77b204"
# The landing gate's active-wave party (§A1/§A2) plants its own one-row roster; a dedicated
# session id keeps it off roster-$SID_A.state, which verdict_er re-seeds on every call.
SID_LG="2ae9d613-4c07-4b8a-9f51-7d02ac86be40"

# ---------------------------------------------------------------- payloads
#
# FIXTURE FIDELITY. PreToolUse envelope FAITHFUL to
# .bionic/docs/record/epic-15-kill-interception-experiment.md §2.2 (CLI 2.1.220
# verbatim capture), field for field; tool_name/tool_input vary per tool as §2.1
# and §2.12 establish. Session ids, agent ids and plan text are SYNTHESIZED and
# declared as such — none is a platform surface.
#
# The Agent tool_input carries a name and a contract-bearing brief (task 4/3):
# tool_input became load-bearing when the start gate began journalling the launch
# to the session roster, and a brief with no labeled contract fields is warned
# about on stderr. This suite's claim is producer/consumer AGREEMENT ON THE
# ATTESTATION — "passes in silence" below means the attestation raised nothing —
# so the fixture is the ordinary dispatch, not a malformed one. The warning
# itself is driven where it belongs, in tests/dispatch-preflight.test.sh S10c.

mk_agent_payload() {  # <sid> <cwd>
  jq -n --arg s "$1" --arg c "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:"implementor", name:"w99-impl",
                  prompt:"Expected artifact: .bionic/docs/record/w99.txt\nExpected duration: ~25 minutes.\nProgress artifact: .bionic/tmp/w99.progress\nSuites: tests/widget.test.sh"},
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

mk_stop_payload() {  # <sid> <transcript> <cwd> <task_id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg k "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"TaskStop",
      tool_input:{task_id:$k}, tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

# The recorder's event. FAITHFUL to .bionic/docs/record/w3-slice1-posttooluse-probe.md
# capture A (orchestrator-invoked PostToolUse|Bash), field for field including the
# tool_response object; capture A carries no top-level agent_id, which is the
# orchestrator case. The stdout carried here is never synthesized in this suite —
# it is whatever the real hooks/stop-check.sh printed.
mk_bash_post() {  # <sid> <transcript> <cwd> <command> <stdout>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg m "$4" --arg o "$5" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"598cabc5-2776-479c-abcf-52c540a1c60e",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Bash",
      tool_input:{command:$m, description:"observe"},
      tool_response:{stdout:$o, stderr:"", interrupted:false,
                     isImage:false, noOutputExpected:false},
      tool_use_id:"toolu_01HQV9JAFdKC15TLMDKt2QgF", duration_ms:117}'
}

# FAITHFUL to the same record's capture E (background dispatch, the mode this
# repo uses): tool_response carries `agentId`, tool_input carries `name`.
mk_agent_post() {  # <sid> <transcript> <cwd> <tool_use_id> [name] [agentId]
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg u "$4" \
    --arg n "${5:-battery}" --arg a "${6:-a26bd30bf8616411b}" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"33f36a9c-ad3b-4bb4-afbd-325a18e62a9e",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                  run_in_background:true, name:$n},
      tool_response:{isAsync:true, status:"async_launched", agentId:$a,
                     description:"a dispatch", resolvedModel:"claude-sonnet-5",
                     prompt:"go", outputFile:("/tmp/tasks/" + $a + ".output"),
                     canReadOutputFile:true},
      tool_use_id:$u, duration_ms:6}'
}

# The LANDING SWEEP's event (epic-16 wave-03, T4c). FAITHFUL to
# .bionic/docs/record/session-20260814-wave-detector-terminal-state/t4b-probe-report.md
# §2.1 (the eleven-key Stop envelope) and §2.2 (the `background_tasks[]` row shape,
# `{id, type, status, description, agent_type}`). The ids passed here are the LIVE set —
# every roster row whose agent_id is absent from it has landed and is judged.
mk_stopsweep_payload() {  # <cwd> <sid> <stop_hook_active true|false> [live-agent-id...]
  local c="$1" s="$2" h="$3"; shift 3
  local live
  live=$(printf '%s\n' "$@" | jq -R 'select(length > 0)' | jq -s \
    'map({id:., type:"subagent", status:"running", description:"a live dispatch",
          agent_type:"general-purpose"})')
  jq -n --arg c "$c" --arg s "$s" --argjson h "$h" --argjson bg "$live" \
    '{session_id:$s, transcript_path:("/tmp/transcripts/" + $s + ".jsonl"), cwd:$c,
      prompt_id:"e30e6fb0-3868-467c-b092-ca03e55b4cd5",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"Stop", stop_hook_active:$h,
      last_assistant_message:"The background probe agent completed and returned PONG.",
      background_tasks:$bg, session_crons:[]}'
}

# THE SESSION ROSTER, in the shape its writer writes it — field for field from
# hooks/dispatch-preflight.sh's `ROW=` line. Both the producer (classification,
# contract state) and the stop gate (the foreign-stop rule) read this file, which
# is precisely why it is planted from ONE helper here: a fixture written twice is
# two shapes, and this suite exists to catch exactly that.
cg_roster_row() {  # <repo> <sid> <name> <agent-id> [progress] [status]
  local repo="$1" sid="$2" name="$3" aid="$4" prog="${5:-}" status="${6:-confirmed}"
  local f="$repo/.bionic/tmp/roster-$sid.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture \
    status="$status" session="$sid" name="$name" agent_id="$aid" \
    launched_at=2026-08-05T00:00:00Z progress="$prog" >> "$f"
  return 0
}

# THE RECORDED ListAgents ANSWER — the live set (S6, D1′). Since this task both stop
# scripts resolve a target against the newest recorded ListAgents answer in a session's
# transcript, so a fixture transcript is no longer an empty file. The body's shape is the
# real one, copied from tests/live-agents.test.sh, whose bodies are byte-verbatim captures:
# the separator is U+00B7 and `[8895ce]` is the harness ref suffix the reader strips.
# Accumulated in a sidecar so a second call ADDS a teammate rather than replacing the answer.
# THE RECORDER UPDATES A ROW, IT DOES NOT APPEND ONE. `intended → confirmed → identified` is
# one row moving through three states carrying one contract (§K), so a fixture that appended a
# second row of the same name would leave the CONTRACT on the first and the AGENT ID on the
# second — a shape no writer produces, and one that would make the readers below look broken
# for a reason nothing in production can reach.
roster_identify() {  # <repo> <sid> <name> <agent-id>
  local f="$1/.bionic/tmp/roster-$2.state" prev
  prev=$(grep -F "|name=$3|" "$f" 2>/dev/null | tail -1) || prev=""
  if [ -n "$prev" ]; then
    # FORWARD-COPIED, not rewritten: the identification arm carries the whole row forward with
    # its contract intact (§K), and the earlier state's row stays on the file exactly as the
    # real writers leave it — which is what lets a later section still find an `intended` row
    # to complete. Only the two fields the identification owns are replaced.
    printf '%s\n' "$prev" \
      | sed -e 's/|status=[^|]*|/|status=identified|/' -e "s/|agent_id=[^|]*|/|agent_id=$4|/" >> "$f"
    return 0
  fi
  cg_roster_row "$1" "$2" "$3" "$4" "" "identified"
}

# THE ANSWER BODY IS BUILT BY tests/lib/live-answer.sh (S17, spec AC-27/AC-28). The self
# line, the `Teammates (N):` header and every teammate row come out of the committed corpus
# with only this suite's names, statuses and type substituted in place — so the recognition
# anchor these sections lean on is the one the harness actually writes, not this file's own
# spelling of it, and the bash-3.2 `case`-inside-`$( … )` hazard the old private row builder
# had to be hoisted out of (Step-6 review C-2) is gone with the builder.
#
# `LIVE_ANSWER_TYPE` is the type every composed row carries: §LA.5 and §LA.6 assert on it.
# A bare name is the corpus's own `running`; `name:idle` writes the harness's other status —
# the teammate that finished its turn and was never stopped, which LA.5 turns into the
# discriminator between the two questions the one parse now answers.
LIVE_ANSWER_TYPE="bionic:implementor"

cg_live() {  # <transcript> <name[:status]>...
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

# ============================================================
# THE SHARED QUESTION
# ============================================================
#
# All three parties compute the same thing from a repo: resolve the docs root
# (honouring .bionic/config.yaml's `docs-root:`), select the newest plan two
# levels deep under plans/ and incidents/, read the fence-aware `## SDLC State`
# section through the CR-translating normalizer, and take its `current:` value.
#
# They then USE it differently, so the comparable observable is the predicate
# each can answer:
#
#     "does this repo present a plan whose `current:` names a valid step?"
#
#   dispatch-preflight  refuse (exit 2, no attestation planted)  <=> yes
#   stop gate           refuse (exit 2, target unresolvable)     <=> yes
#
# The evidence gate is no party: it reads a run's step from its log, and a plan at 14
# is a document to it, so no party reads these plans' state sections as a run.
#
# Deliberately out of the battery, and why:
#   * `current: T<n>` — not a step at any scale since wave-31 (one ledger shape, D2):
#     the one party that reads `current:` refuses it. Section A3 pins that at either
#     scale, rather than mixing a refused value into the agreement rows.
#   * The evidence gate's misplaced-plan sweep (`*.plan.md` carrying
#     canonical_sdlc_version outside the docs root) — a gate-specific rule with
#     no counterpart in the other two. Fixture plans are therefore named
#     `*.md`, not `*.plan.md`: every party's plan SELECTION matches `*.md`, so
#     nothing under test is weakened, and the sweep never fires to confound the
#     observable.

verdict_dp() {  # <repo> -> yes|no|other:<detail>
  local out st
  out=$(mk_agent_payload "$SID_A" "$1" | bash "$PARTY_DP" 2>&1); st=$?
  case "$st" in
    0) if [ -z "$out" ]; then echo no; else echo "other:pass-with-output"; fi ;;
    2) echo yes ;;
    *) echo "other:exit-$st" ;;
  esac
}

verdict_sg() {  # <repo> -> yes|no|other:<detail>
  local out st
  out=$(mk_stop_payload "$SID_A" "$SANDBOX/t.jsonl" "$1" "no-such-agent" \
        | bash "$PARTY_SG" 2>&1); st=$?
  case "$st" in
    0) if [ -z "$out" ]; then echo no; else echo "other:pass-with-output"; fi ;;
    2) echo yes ;;
    *) echo "other:exit-$st" ;;
  esac
}

# The recorder holds the FOURTH copy of active-wave detection (task 4/4), and a
# duplicated wall nothing drives is a wall that diverges. Its observable is the
# roster: with a wave active it completes an `intended` row on execution
# confirmation, and outside one it is inert. The row is re-seeded on every call so
# the answer describes this run and not a previous one.
verdict_er() {  # <repo> -> yes|no|other:<detail>
  # TWO STATEMENTS, NOT ONE — the trap this file records at `j_mutant` and `mk_root`.
  # `local repo="$1" roster="$repo/…"` expands every word before it assigns any, so
  # `$roster` was built from whatever `repo` happened to be in a CALLER's scope; inside the
  # battery loop that was the right value by accident, and from anywhere else it is an
  # unbound-variable abort under `set -u`.
  local repo="$1" out st roster
  roster="$repo/.bionic/tmp/roster-$SID_A.state"
  mkdir -p "$repo/.bionic/tmp"
  {
    roster_header
    roster_row_fixture status=intended session="$SID_A" name=battery agent_id= \
      launched_at=2026-08-05T00:00:00Z model= tool_use_id=toolu_BATTERY
  } > "$roster"
  out=$(mk_agent_post "$SID_A" "$SANDBOX/t.jsonl" "$repo" "toolu_BATTERY" | bash "$PARTY_ER" 2>&1); st=$?
  if [ "$st" -ne 0 ]; then echo "other:exit-$st"; return; fi
  if [ -n "$out" ]; then echo "other:output"; return; fi
  if grep -q 'status=confirmed' "$roster" 2>/dev/null; then echo yes; else echo no; fi
}

# The landing gate holds a FIFTH byte-identical copy of active-wave detection
# (hooks/landing-gate.sh, the block deliberately duplicated from dispatch-preflight's) and
# until this party existed it sat OUTSIDE the very battery meant to catch that copy drifting
# — §J drives the gate's verdict/gate agreement, not its wave detection (Step-6 critic D-1).
# Its observable is a Stop over a roster carrying ONE unmet contract that has LANDED (its
# agent_id is absent from the payload's background_tasks): with a wave active the gate
# reaches the verdict, reads UNMET and refuses (exit 2); with no wave it exits 0 before ever
# taking a verdict. So exit-2-with-the-refusal <=> yes and exit-0 <=> no, the same predicate
# the other four answer. The gate resolves the sweeper as its own sibling, so a MUTATED copy
# of it (§A2) must sit beside a sweeper — $MUTDIR carries one. The roster is re-seeded per
# call under $SID_LG, off verdict_er's $SID_A file — which also clears the sweep's own
# idempotency marker, so every call is this row's first verdict.
verdict_lg() {  # <repo> -> yes|no|other:<detail>
  # TWO STATEMENTS, NOT ONE — the trap this file records at `j_mutant` and `mk_root`.
  # `local repo="$1" roster="$repo/…"` expands every word before it assigns any, so
  # `$roster` was built from whatever `repo` happened to be in a CALLER's scope; inside the
  # battery loop that was the right value by accident, and from anywhere else it is an
  # unbound-variable abort under `set -u`.
  local repo="$1" out st roster
  roster="$repo/.bionic/tmp/roster-$SID_LG.state"
  mkdir -p "$repo/.bionic/tmp"
  {
    roster_header
    roster_row_fixture status=confirmed session="$SID_LG" name=lg-probe \
      agent_id=alg-probe-0001 launched_at=2026-08-05T00:00:00Z \
      deliverable=.bionic/docs/record/never-lg.md tool_use_id=toolu_LGPROBE
  } > "$roster"
  out=$(mk_stopsweep_payload "$repo" "$SID_LG" false | bash "$PARTY_LG" 2>&1); st=$?
  case "$st" in
    0) echo no ;;
    2) if printf '%s' "$out" | grep -qF "bionic: stop refused — a dispatched agent's contract is unmet"; then echo yes; else echo "other:block-no-detail"; fi ;;
    *) echo "other:exit-$st" ;;
  esac
}

# ---------------------------------------------------------------- fixtures

# THE FIXTURE PLAN IS AN APPROVED ONE (wave-20 T7, AC-9.1). Since 1.8.7 the dispatch wall
# refuses every non-read-only type — this suite's bare `implementor` included — against a plan
# with no `approved-by:`, at any step. A live wave at `current: 4` has been approved, so the
# fixture says so; a body that states its own `approved-by:` keeps it.
write_plan() {  # <path> <state-body>
  mkdir -p "$(dirname "$1")"
  {
    printf -- '---\n'
    printf 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf 'intent: build\nrigor: double\nscale: wave\n'
    printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\nintegration-branch: main\n'
    printf '%s\n' "$2"
    case "$2" in *approved-by:*) ;; *) printf 'approved-by: dana 2026-09-07T19:05Z "approved"\n' ;; esac
    printf '\n- Step 3: prior evidence\n'
  } > "$1" || return
  seal_fixture "$1"
}

# A LIVE WAVE HAS A LIVE PATROL (epic-17 W5 4/4). hooks/dispatch-preflight.sh refuses a
# dispatch whose session carries no fresh Patrol stamp, so a repo fixture without one answers
# "refused" to every question this suite asks about roster rows, identity chains and progress
# paths — the arming wall would be under test in every section instead of in its own (§P,
# which removes the stamp deliberately). This is the fixture equivalent of an engagement
# arming the Patrol before the first dispatch. Written under the MAIN repository always: the
# stamp shares the roster's pinned root, which §N.3 depends on and would break by planting
# a phantom `.bionic` in a worktree.
arm_patrol() {  # <repo> <session-id>...
  local repo="$1"; shift
  mkdir -p "$repo/.bionic/tmp"
  local sid
  for sid in "$@"; do
    printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" > "$repo/.bionic/tmp/patrol-$sid.state"
    chmod 600 "$repo/.bionic/tmp/patrol-$sid.state"
    # …AND A WATCH THAT RESTED ON PURPOSE, which the dispatch wall admits as it admits a live one.
    printf 'state=resting\nwhy=person\nat=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$repo/.bionic/tmp/watch-$sid.state"
    # …AND AN ENGAGED SESSION (task-engaged-session). Since this wave every gate this suite
    # drives asks `engaged_session` before it asks anything else, so a fixture without the
    # marker answers every question in this file the same way — silence — and the whole
    # suite would be green over nothing. The marker travels with the stamp for the same
    # reason the stamp travels with the plan: SKILL.md arms the Patrol AT engagement, so a
    # world that has one has both. A marker already there is KEPT: a binding written before
    # the Patrol was armed is the session's, and re-arming must not unbind it
    # (wave-23-fixit-1810 T1 — an unbound session's fallback plan is never acted on).
    [ -f "$repo/.bionic/tmp/engaged-$sid.state" ] || : > "$repo/.bionic/tmp/engaged-$sid.state"
  done
}

# ENGAGEMENT (task-engaged-session, 2026-09-03). Every party in this battery asks whether
# the session invoked the canonical-sdlc skill before it asks whether a run is open, so a
# fixture built to make the five parties agree about the RUN has to clear that question
# first — for each session key any party is driven under. Without it every party would
# answer "no run" for a reason that has nothing to do with the plan on disk, and the whole
# battery would agree vacuously.
engage_sids() {  # <repo> <sid>...
  local r="$1"; shift
  mkdir -p "$r/.bionic/tmp"
  local s
  # Engaged and unbound: a binding record left beside the seal would be believed over the empty marker.
  for s in "$@"; do { ! declare -F bound_marker_unrecord >/dev/null || bound_marker_unrecord "$r" "$s"; }; : > "$r/.bionic/tmp/engaged-$s.state"; done
}

# write_live_plan <plan path> <step> — the page a run at 15 holds at <step>, approved
# (tests/lib/plan-fixture.sh), then BIND the repo's three fixture
# sessions to that plan (wave-23-fixit-1810, REQ-1, D1). new_repo engages them with an EMPTY
# marker — engaged and unbound — and an unbound session's newest-plan fallback is announced
# and never acted on: the dispatch wall refuses its writers with the bind instruction. A
# section whose subject is a wave in flight (a writer journalled, a chain advanced) means a
# session running that wave, so it writes its plan through here. The repo is the path up to
# its `.bionic/`.
write_live_plan() {
  plan_fixture --current "$2" "$1" wave >/dev/null
  local _r="${1%%/.bionic/*}" _s
  for _s in "$SID_A" "$SID_B" "$SID_LG"; do bound_marker "$_r" "$_s" "$1"; done
}

new_repo() {  # <name> -> path
  local r="$SANDBOX/fx/$1/repo"
  mkdir -p "$r/.bionic/tmp"
  git -C "$r" init -q 2>/dev/null
  arm_patrol "$r" "$SID_A" "$SID_B" "$SID_LG"
  engage_sids "$r" "$SID_A" "$SID_B" "$SID_LG"
  printf '%s' "$r"
}

# name|expected-answer|expected-current
FIXTURES='
baseline-active|yes|4
no-plan-dir|no|-
no-sdlc-state|no|-
docs-root-double-quoted|yes|4
docs-root-single-quoted|yes|4
docs-root-absolute|yes|4
docs-root-duplicate-lines|yes|4
docs-root-indented|yes|4
docs-root-trailing-space|yes|4
plan-crlf|yes|4
plan-cr-only|yes|4
current-indented|yes|4
current-duplicate-lines|yes|4
current-fenced-only|no|-
newest-plan-wins|yes|8b
marker-less-newest-loses|yes|open-at-14
fenced-only-newest-loses|yes|open-at-14
only-marker-less-files|no|-
nested-two-deep|yes|4
nested-three-deep|no|-
incidents-dir|yes|4
current-8b|yes|8b
current-placeholder|no|-
'

build_fixture() {  # <name> -> repo path
  local name="$1" repo
  repo=$(new_repo "$name")
  case "$name" in
    baseline-active)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4" ;;
    no-plan-dir)
      mkdir -p "$repo/.bionic/docs" ;;
    no-sdlc-state)
      mkdir -p "$repo/.bionic/docs/plans/epic-99"
      printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# Notes\n\ncurrent: 4\n' \
        > "$repo/.bionic/docs/plans/epic-99/wave-01.md" ;;

    # --- A9's undiscriminated parser edges, each built so a mis-parse FLIPS ---
    # the answer: the override points at the only directory holding a plan, and
    # the default root holds none.
    docs-root-double-quoted)
      printf 'docs-root: "custom-docs"\n' > "$repo/.bionic/config.yaml"
      write_plan "$repo/custom-docs/plans/epic-99/wave-01.md" "current: 4" ;;
    docs-root-single-quoted)
      printf "docs-root: 'other-docs'\n" > "$repo/.bionic/config.yaml"
      write_plan "$repo/other-docs/plans/epic-99/wave-01.md" "current: 4" ;;
    docs-root-absolute)
      # An ABSOLUTE override is used as-is; treating it as repo-relative yields
      # "$repo/$abs", which does not exist, and the answer flips to no.
      mkdir -p "$SANDBOX/fx/$name/elsewhere"
      printf 'docs-root: %s\n' "$SANDBOX/fx/$name/elsewhere" > "$repo/.bionic/config.yaml"
      write_plan "$SANDBOX/fx/$name/elsewhere/plans/epic-99/wave-01.md" "current: 4" ;;
    docs-root-duplicate-lines)
      # FIRST directive wins (head -1). The second names a real but planless
      # directory, so last-wins flips the answer.
      { printf 'docs-root: live-docs\n'; printf 'docs-root: dead-docs\n'; } \
        > "$repo/.bionic/config.yaml"
      mkdir -p "$repo/dead-docs/plans"
      write_plan "$repo/live-docs/plans/epic-99/wave-01.md" "current: 4" ;;
    docs-root-indented)
      printf '  docs-root: indented-docs\n' > "$repo/.bionic/config.yaml"
      write_plan "$repo/indented-docs/plans/epic-99/wave-01.md" "current: 4" ;;
    docs-root-trailing-space)
      printf 'docs-root: trail-docs   \n' > "$repo/.bionic/config.yaml"
      write_plan "$repo/trail-docs/plans/epic-99/wave-01.md" "current: 4" ;;

    # --- line endings: CRLF is common, CR-only is the fail-dangerous one ---
    plan-crlf)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
      awk '{ printf "%s\r\n", $0 }' "$repo/.bionic/docs/plans/epic-99/wave-01.md" \
        > "$repo/.bionic/docs/plans/epic-99/wave-01.md.x"
      mv "$repo/.bionic/docs/plans/epic-99/wave-01.md.x" \
         "$repo/.bionic/docs/plans/epic-99/wave-01.md" ;;
    plan-cr-only)
      # `tr -d '\r'` collapses this to ONE line and every line-anchored match
      # misses — the silently-inert-wall shape from .claude/rules/hook-authoring.md.
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
      tr '\n' '\r' < "$repo/.bionic/docs/plans/epic-99/wave-01.md" \
        > "$repo/.bionic/docs/plans/epic-99/wave-01.md.x"
      mv "$repo/.bionic/docs/plans/epic-99/wave-01.md.x" \
         "$repo/.bionic/docs/plans/epic-99/wave-01.md" ;;

    # --- the `current:` directive's own edges ---
    current-indented)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "   current :  4" ;;
    current-duplicate-lines)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" \
        "$(printf 'current: 4\ncurrent: notastep')" ;;
    current-fenced-only)
      # The ONLY `## SDLC State` in the file is inside a fenced example. A
      # fence-blind parser reads it and reports an active wave on a plan that
      # documents the schema rather than running it.
      mkdir -p "$repo/.bionic/docs/plans/epic-99"
      {
        printf -- '---\ncanonical_sdlc_version: 14\nscale: wave\n---\n\n# Schema doc\n\n'
        printf 'The section looks like this:\n\n```\n## SDLC State\n\ncurrent: 4\n```\n'
      } > "$repo/.bionic/docs/plans/epic-99/wave-01.md" ;;
    newest-plan-wins)
      # NEWEST among CANDIDATE PLANS wins. Both files are real plans here, so the
      # predicate cannot discriminate and the DERIVED VALUE is what does: an
      # oldest-wins selection reports 4 instead of 8b. This fixture used to make
      # the newer file a marker-less note and expect `no` — which pinned the
      # off-switch (record/session-20260815-landing-supervision/t8-forensic-read.md)
      # as intended behaviour. That shape is now its own fixture, expecting the
      # opposite; the newest-wins claim survives here, on two plans.
      write_plan "$repo/.bionic/docs/plans/epic-99/a-older.md" "current: 4"
      touch -t 202001010000 "$repo/.bionic/docs/plans/epic-99/a-older.md"
      write_plan "$repo/.bionic/docs/plans/epic-99/b-newer.md" "current: 8b"
      touch -t 203001010000 "$repo/.bionic/docs/plans/epic-99/b-newer.md" ;;
    marker-less-newest-loses)
      # AC-10, THE OFF-SWITCH. A stray marker-less *.md — a continuation note, a
      # probe scrap, a Step-9 artifact — is newest under plans/ while a real plan
      # with a live `current:` sits beside it. Selecting the stray reads `current:`
      # empty and every wall in this battery passes silently with a wave running.
      # That is not hypothetical: it disarmed this repo for ~15 minutes on
      # 2026-08-15, twice, by two agents, neither trying. The real plan must win.
      write_plan "$repo/.bionic/docs/plans/epic-99/session.plan.md" "current: 4"
      touch -t 202001010000 "$repo/.bionic/docs/plans/epic-99/session.plan.md"
      printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# Continuation\n\ncurrent: 4\n' \
        > "$repo/.bionic/docs/plans/epic-99/continuation.md"
      touch -t 203001010000 "$repo/.bionic/docs/plans/epic-99/continuation.md" ;;
    fenced-only-newest-loses)
      # The same shape one turn subtler: the newest file DOES contain the string
      # `## SDLC State`, inside a fenced example. A fence-blind candidate filter
      # accepts it, `current:` parses empty through the fence-aware read, and the
      # off-switch is back — so the candidate filter is fence-aware exactly like
      # the read it feeds. (The fenced file alone still passes silently:
      # `current-fenced-only` holds that direction.)
      write_plan "$repo/.bionic/docs/plans/epic-99/session.plan.md" "current: 4"
      touch -t 202001010000 "$repo/.bionic/docs/plans/epic-99/session.plan.md"
      {
        printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# Schema notes\n\n'
        printf 'The section looks like this:\n\n```\n## SDLC State\n\ncurrent: 4\n```\n'
      } > "$repo/.bionic/docs/plans/epic-99/schema-notes.md"
      touch -t 203001010000 "$repo/.bionic/docs/plans/epic-99/schema-notes.md" ;;
    only-marker-less-files)
      # THE PRESERVED AMBIGUITY. A plans tree holding no valid plan at all still
      # reads as "no wave" and passes SILENTLY — the ratified fail direction, and
      # the reason the fix is a candidate filter rather than a refusal: skipping
      # every candidate must land in the same place as finding none.
      mkdir -p "$repo/.bionic/docs/plans/epic-99"
      printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# Continuation\n' \
        > "$repo/.bionic/docs/plans/epic-99/continuation.md"
      printf '# Scratch\n\ncurrent: 4\n' \
        > "$repo/.bionic/docs/plans/epic-99/scratch.md" ;;
    nested-two-deep)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4" ;;
    nested-three-deep)
      # DEPTH 3 IS OUT OF THE BOUND, and this fixture is where that is decided for the whole
      # fleet. Two depths were live during bionic 1.4.0 — the hand-copies and the evidence
      # gate walked 2, which is the bionic layout's own depth (plans/<epic>/<wave>.plan.md),
      # and L-RUN shipped 3 — and §S.3d pinned the disagreement rather than papering over it.
      # POKER/2's unification (ratified 2026-09-03) resolves it AT 2: the descend-2 read is
      # the one §S holds body-for-body, anything deeper under plans/ is notes rather than a
      # plan, and a bound nobody can state from the layout is a bound that drifts again. All
      # five parties read the library, so all five must agree it is not a run.
      write_plan "$repo/.bionic/docs/plans/epic-99/sub/wave-01.md" "current: 4" ;;
    incidents-dir)
      write_plan "$repo/.bionic/docs/incidents/inc-01/incident.md" "current: 4" ;;
    current-8b)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 8b" ;;
    current-placeholder)
      # A plan that exists but names no step is not a run in progress.
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: pending" ;;
    *) echo "UNKNOWN FIXTURE $name" >&2; exit 9 ;;
  esac
  printf '%s' "$repo"
}

echo "building fixture repos..."
while IFS='|' read -r name want cur; do
  [ -n "$name" ] || continue
  build_fixture "$name" >/dev/null
done <<EOF
$(printf '%s' "$FIXTURES")
EOF

# A MUTANT NEEDS THE LIBRARY BESIDE IT (bionic 1.4.0). Every hook loads root.sh, run.sh
# and session.sh through the shared loader idiom, whose first candidate is
# `$(dirname "$0")/../scripts/lib`. A copy alone in a temp directory does not find it
# there — and the loader's HEALING candidates then reach the plugin installed on this
# machine, whose library predates this wave and does not carry the wanted basenames — so
# the copy fails OPEN and every mutation arm below would be measuring the step-aside
# instead of the mutation. `plant_hook_tree` builds the shipped shape around a mutant:
# hooks/ beside scripts/lib/, holding this checkout's library.
plant_hook_tree() {  # <tree root> -> echoes <tree root>/hooks
  local root="$1" src="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
  [ -d "$src" ] || src="$BIONIC_HOOKS_DIR/../scripts/lib"
  mkdir -p "$root/hooks" "$root/scripts/lib"
  cp "$src"/*.sh "$root/scripts/lib/" 2>/dev/null || true
  printf '%s' "$root/hooks"
}

# run_battery assert — one assertion per fixture: the four engagement-scoped parties answer
# the same on every plan shape, since none of them reads the plan.
run_battery() {
  local name want cur repo a b d e
  while IFS='|' read -r name want cur; do
    [ -n "$name" ] || continue
    repo="$SANDBOX/fx/$name/repo"
    a=$(verdict_dp "$repo"); b=$(verdict_sg "$repo"); d=$(verdict_er "$repo"); e=$(verdict_lg "$repo")
    # Every fixture is engaged (see `arm_patrol`), so each party answers yes on all of them;
    # a party that still had a plan opinion of its own would break that constancy.
    if [ "$a|$b|$d|$e" = "yes|yes|yes|yes" ]; then
      ok "the four engagement-scoped parties agree on '$name'"
    else
      no "the four engagement-scoped parties agree on '$name'" \
         "dispatch-preflight=$a stop=$b execution-recorder=$d landing-gate=$e"
    fi
  done <<EOF
$(printf '%s' "$FIXTURES")
EOF
  return 0
}


# ============================================================
# HOISTED: defined in a section of part 1, called by a section of part 2.
# ============================================================

# ---- from §A2: RUN_LIB, FILL_LIB ----
RUN_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/run.sh"
[ -r "$RUN_LIB" ] || RUN_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/run.sh"
# fill.sh's `current:` reader, which the poker's `_sched_plan_current_field` delegates to since
# wave-19 (REQ-6, D7): §CG sources it beside the extraction, as the shipped poker does.
FILL_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/fill.sh"
[ -r "$FILL_LIB" ] || FILL_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/fill.sh"

# ---- from §Section P (the Patrol stamp): PARTY_PK ----
PARTY_PK="${W1R_PARTY_PK:-$BIONIC_HOOKS_DIR/session-poker.sh}"

