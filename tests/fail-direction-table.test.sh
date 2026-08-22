#!/bin/bash
# THE §7 FAIL-DIRECTION TABLE, PINNED AS BEHAVIOUR — epic-15 wave-01R, slice 4/6.
#
# Serves AC-10. Governing design: design/orchestrator-subagent-coordination.md §7.
# Known-failure checklist A10: "fail-open/fail-closed direction differs between
# gates on a missing identity field, with nothing pinning that asymmetry itself."
#
# The per-gate suites already drive most of these conditions — each inside the
# suite of the gate it belongs to, where the direction reads as that gate's local
# habit. THE ASYMMETRY IS THE DESIGN CLAIM, and a claim split across two files is
# a claim nobody reads. So this suite is one table: every row of §7, both
# surfaces, driven side by side, with the identical-condition pair
# (`payload missing its session key`) adjacent so that start=open and stop=closed
# are one artefact.
#
# HERMETIC: throwaway git repos under a mktemp'd sandbox, redirected HOME.
#
# Usage: bash tests/fail-direction-table.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

# Overridable so the table can be driven against a MUTATED COPY without the
# shipped file ever being modified — §9's mutation-and-restore proof, repeatable
# by hand: W1R_PARTY_SG=/tmp/mutant.sh bash tests/fail-direction-table.test.sh
START_GATE="${W1R_PARTY_DP:-$BIONIC_HOOKS_DIR/dispatch-preflight.sh}"
STOP_GATE="${W1R_PARTY_SG:-$BIONIC_HOOKS_DIR/stop-guard.sh}"
# The producer and the writer that stand behind the stop gate's positive pair.
OBSERVER="$BIONIC_HOOKS_DIR/stop-check.sh"
RECORDER="${W1R_PARTY_ER:-$BIONIC_HOOKS_DIR/execution-recorder.sh}"
PROBE="${W1R_PARTY_PROBE:-$BIONIC_HOOKS_DIR/preflight-probe.sh}"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/w1r-faildir.XXXXXX")" && pwd -P)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS; do kill -9 "$p" 2>/dev/null; done
  # the probe-refuses fixture below leaves .bionic/tmp chmod 500 (unwritable) —
  # restore write perms first or rm -rf cannot unlink inside it (same technique
  # tests/preflight-probe.test.sh's cleanup() uses for the same reason).
  chmod -R u+rwX "$SANDBOX" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT
export HOME="$SANDBOX/home"
export CLAUDE_CONFIG_DIR="$SANDBOX/home/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "$SANDBOX/plain" "$SANDBOX/stub" "$SANDBOX/nocred/.claude"

# The macOS login keychain is machine-global: a real `security` on this machine
# would satisfy the producer's credential probe and the row-5 case below could
# never fail its blocking probe. Substituting the COMMAND (an environment
# substitution via PATH, not a seam inside the script) is the same technique
# tests/preflight-probe.test.sh uses.
printf '#!/bin/bash\nexit 1\n' > "$SANDBOX/stub/security"
chmod +x "$SANDBOX/stub/security"

# R5 ("attestation never blocks") means every `drive start:*` call below may now
# trigger the wall's auto-probe inline. That probe's credential check must
# succeed DETERMINISTICALLY — not depend on this machine's real login keychain,
# which is exactly the trap the `security` stub above exists to avoid for the
# producer's own suite. The sandboxed-probe-environment technique
# (tests/preflight-probe.test.sh's mk_sandbox) is a credentials-file source: a
# non-empty `.credentials.json` under the shared CLAUDE_CONFIG_DIR satisfies
# credential source 2 before the probe ever reaches `security`, so every world
# below auto-probes successfully unless a fixture deliberately breaks a
# DIFFERENT blocking probe (start:probe-refuses breaks the state-dir probe, per
# w2-s45-wallfacts.md §5 judgment call 9: never an absent credential).
printf '{}' > "$CLAUDE_CONFIG_DIR/.credentials.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="1f4a7c02-3bd9-4e15-8a66-90c1de77b204"

# ---------------------------------------------------------------- fixtures
#
# FIXTURE FIDELITY: the PreToolUse envelope is FAITHFUL to
# .bionic/docs/record/epic-15-kill-interception-experiment.md §2.2 (CLI 2.1.220
# verbatim capture); the `subagents/agent-<id>.{meta.json,jsonl}` layout is
# FAITHFUL to §2.5. Session ids, agent ids, plan text: SYNTHESIZED, declared.

write_plan() {  # <path> <current-line>
  mkdir -p "$(dirname "$1")"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf 'intent: build\nrigor: audited\nscale: wave\n---\n\n# Fixture plan\n\n'
    printf '## SDLC State\n\nintegration-branch: main\n%s\n\n- Step 4: evidence\n' "$2"
  } > "$1"
}

# make_world <name> <wave:yes|no|nocurrent> -> "repo|transcript|subagents-dir"
make_world() {
  local name="$1" wave="$2"
  local base="$SANDBOX/w/$name" repo="$SANDBOX/w/$name/repo"
  # The session metadata lives under a per-world CLAUDE_CONFIG_DIR rooted at
  # `$base/cfg`, in the layout the platform uses:
  # <config>/projects/<repo-slug>/<session>/subagents. The stop gate reaches it
  # from the payload's transcript path, and the OBSERVATION reaches it by
  # slugifying its cwd — since slice 4/4 the observed rows run the real producer,
  # so a fixture only the gate can reach would prove nothing about the pair.
  # The session directory is named by the SESSION ID, because that is what the
  # platform does and, since slice 4/9, what ownership reads: an agent under
  # <session>/subagents/ was launched by <session>. A world whose directory was
  # named anything else would classify every target foreign, and the rows below
  # would be answering a question about the roster instead of the one they name.
  local cfg="$base/cfg" slug
  slug=$(printf '%s' "$repo" | sed 's/[^a-zA-Z0-9]/-/g')
  mkdir -p "$repo/.bionic" "$cfg/projects/$slug/$SID_A/subagents" \
           "$cfg/projects/$slug/$SID_B/subagents"
  git -C "$repo" init -q 2>/dev/null
  printf '{}\n' > "$cfg/projects/$slug/$SID_A.jsonl"
  printf '{}\n' > "$cfg/projects/$slug/$SID_B.jsonl"
  case "$wave" in
    yes)       write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
               # A LIVE WAVE HAS A LIVE PATROL (epic-17 W5 4/4). The arming wall refuses a
               # dispatch whose session carries no fresh Patrol stamp, and every start-gate
               # row below rides an active world — so an unarmed fixture would rewrite this
               # whole table to one answer. The unarmed direction gets its OWN row
               # (start|patrol-unarmed), driven against a world built without this.
               mkdir -p "$repo/.bionic/tmp"
               for _psid in "$SID_A" "$SID_B"; do
                 printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
                   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_psid" \
                   > "$repo/.bionic/tmp/patrol-$_psid.state"
                 chmod 600 "$repo/.bionic/tmp/patrol-$_psid.state"
               done ;;
    nocurrent) write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: pending" ;;
    no)        mkdir -p "$repo/.bionic/docs" ;;
  esac
  printf '%s|%s|%s' "$repo" "$cfg/projects/$slug/$SID_A.jsonl" "$cfg/projects/$slug/$SID_A/subagents"
}

plant_agent() {  # <subagents-dir> <agent-id> <name>
  printf '{"name":"%s","agentType":"implementor","model":"claude-sonnet-5"}' "$3" \
    > "$1/agent-$2.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$1/agent-$2.jsonl"
}

# The session roster (slice 4/3's writer, row shape field-for-field from
# hooks/dispatch-preflight.sh). Since slice 4/9 the roster no longer decides
# ownership — the session directory does — so a row here carries the CONTRACT and,
# when it is `confirmed`, reaches a target outside this session's own directory.
roster_row() {  # <repo> <sid> <name> <agent-id> [progress] [status]
  local repo="$1" sid="$2" name="$3" aid="$4" prog="${5:-}" status="${6:-confirmed}"
  local f="$repo/.bionic/tmp/roster-$sid.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=%s|absent=|tool_use_id=toolu_01FIXTURE\n' \
    "$status" "$sid" "$name" "$aid" "$prog" >> "$f"
  return 0
}

payload() {  # <tool_name> <sid|-> <transcript|-> <cwd> <task_id-or-command|->
  local tool="$1" sid="$2" tr="$3" cwd="$4" arg="$5"
  local input='{}'
  case "$tool" in
    # The brief carries its labeled contract fields (slice 4/3): the start gate
    # now journals every launch to the session roster and warns on stderr when a
    # brief names none of them. The `start|attested` row below is THE POSITIVE
    # PAIR — an ordinary, well-formed dispatch — and its §7 direction is
    # "pass in silence"; a fieldless brief is a malformed dispatch, whose warning
    # is a different claim, driven in tests/dispatch-preflight.test.sh S10c.
    Agent)    input=$(jq -n --arg d "a dispatch" --arg p 'Expected artifact: .bionic/docs/record/w99.txt
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99.progress' \
                '{description:$d, subagent_type:"implementor", name:"w99-impl", prompt:$p}') ;;
    TaskStop) input=$(jq -n --arg k "$arg" '{task_id:$k}') ;;
    Bash)     input=$(jq -n --arg c "$arg" '{command:$c}') ;;
    *)        input=$(jq -n '{file_path:"/tmp/x"}') ;;
  esac
  jq -n --arg t "$tool" --arg s "$sid" --arg tr "$tr" --arg c "$cwd" --argjson i "$input" \
    '{prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i,
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB", cwd:$c}
     + (if $s == "-" then {} else {session_id:$s} end)
     + (if $tr == "-" then {} else {transcript_path:$tr} end)'
}

# ---------------------------------------------------------------- the worlds

IFS='|' read -r A_REPO A_TR A_SUB <<< "$(make_world active yes)"
plant_agent "$A_SUB" "aworker-1111111111111111" "worker"
plant_agent "$A_SUB" "atwin-2222222222222222" "twin"
plant_agent "$A_SUB" "atwin-3333333333333333" "twin"
roster_row "$A_REPO" "$SID_A" "worker" "aworker-1111111111111111"

IFS='|' read -r I_REPO I_TR I_SUB <<< "$(make_world inert no)"
plant_agent "$I_SUB" "aworker-1111111111111111" "worker"

IFS='|' read -r N_REPO N_TR N_SUB <<< "$(make_world nocurrent nocurrent)"
plant_agent "$N_SUB" "aworker-1111111111111111" "worker"

# An attested active world — the start gate's positive pair. slice 4/2 (D-5): the
# attestation lives at the PER-SESSION filename the gate actually reads; the old shared
# single-slot path is not consulted, so a fixture written there attests to nothing.
IFS='|' read -r T_REPO T_TR T_SUB <<< "$(make_world attested yes)"
mkdir -p "$T_REPO/.bionic/tmp"
printf '# attestation\nversion=1\nkind=preflight-attestation\nsession_id=%s\n' "$SID_A" \
  > "$T_REPO/.bionic/tmp/preflight-$SID_A.state"

# WORLD ISOLATION (w2-s45-wallfacts.md §7 diagnosis): `make_world` gives this world its
# OWN CLAUDE_CONFIG_DIR under $T_REPO/../cfg, but `drive()` runs the gate under the ONE
# shared CLAUDE_CONFIG_DIR exported above — the config dir the auto-probe's D-5 pruning
# actually reads. Under that shared dir session A has no transcript anywhere, so it reads
# as dead: the FIRST auto-probe driven against this world (start|foreign-attestation,
# session B, driven before start|attested below) prunes A's attestation as a dead
# session's stale record, and start|attested then finds nothing and refuses. Planting A's
# transcript under the SHARED config dir — not just the world's own — is what makes A
# read as live wherever the gate actually looks; `session_transcript_exists()` in
# hooks/preflight-probe.sh scans every project directory under CONFIG_DIR, not one keyed
# to a specific repo, so this single file is sufficient regardless of slug.
T_SLUG=$(printf '%s' "$T_REPO" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$T_SLUG"
printf '{}\n' > "$CLAUDE_CONFIG_DIR/projects/$T_SLUG/$SID_A.jsonl"

# `start|attested` (below) is THE POSITIVE PAIR and its §7 direction is literal silence on
# both streams. Until epic-16 wave-02 that claim needed a genuinely LIVE session sweeper
# armed against this world, or the unarmed-sweeper nag fired legitimately and broke it. The
# nag was deleted with the watcher, so silence is now the gate's own answer and this world
# needs no live process standing behind it.

# An observed active world — the stop gate's positive pair. The observation is
# RECORDED BY THE REAL WRITER, never hand-written: the row must be discharged by
# the real producer→recorder→gate path. Since slice 4/4 that writer is
# hooks/execution-recorder.sh on PostToolUse, and it copies the machine line
# hooks/stop-check.sh prints — so the producer is genuinely run here.
IFS='|' read -r O_REPO O_TR O_SUB <<< "$(make_world observed yes)"
plant_agent "$O_SUB" "aworker-1111111111111111" "worker"
roster_row "$O_REPO" "$SID_A" "worker" "aworker-1111111111111111"
# <observer> is the agent id of whoever RAN the observation — empty for the
# orchestrator, which is how the platform renders it (the payload field is simply
# absent). The producer's own session key travels on CLAUDE_CODE_SESSION_ID: it
# is how the observation finds this session's roster, and therefore the only way a
# contracted progress path reaches the record.
observe() {  # <sid> <transcript> <repo> <target> [observer-agent-id]
  local cfg="${2%/projects/*}" out
  out=$( cd "$3" && CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="$1" \
         bash "$OBSERVER" "$4" 2>/dev/null )
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg o "$out" --arg a "${5:-}" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"598cabc5-2776-479c-abcf-52c540a1c60e",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Bash",
      tool_input:{command:"bash ~/.claude/hooks/stop-check.sh", description:"observe"},
      tool_response:{stdout:$o, stderr:"", interrupted:false,
                     isImage:false, noOutputExpected:false},
      tool_use_id:"toolu_01HQV9JAFdKC15TLMDKt2QgF", duration_ms:117}
     + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' \
    | bash "$RECORDER" >/dev/null 2>&1
  return 0
}
observe "$SID_A" "$O_TR" "$O_REPO" "worker"

# Stale: observed, then the target writes again (D-1's activity boundary).
IFS='|' read -r S_REPO S_TR S_SUB <<< "$(make_world stale yes)"
plant_agent "$S_SUB" "aworker-1111111111111111" "worker"
roster_row "$S_REPO" "$SID_A" "worker" "aworker-1111111111111111"
observe "$SID_A" "$S_TR" "$S_REPO" "worker"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"more work"}]}}\n' \
  >> "$S_SUB/agent-aworker-1111111111111111.jsonl"

# Foreign: the only observation belongs to another session.
IFS='|' read -r F_REPO F_TR F_SUB <<< "$(make_world foreign yes)"
plant_agent "$F_SUB" "aworker-1111111111111111" "worker"
roster_row "$F_REPO" "$SID_A" "worker" "aworker-1111111111111111"
observe "$SID_B" "$F_TR" "$F_REPO" "worker"

# Not ours at all (slice 4/6, AC-6; re-keyed in slice 4/9): an agent filed under
# ANOTHER session's directory, which this session's roster nonetheless names on an
# unconfirmed row — the corpse collision that fired in live operation. By NAME it
# is refused; by FULL AGENT ID it is the documented zombie-predecessor cleanup and
# passes on its own fresh observation.
IFS='|' read -r X_REPO X_TR X_SUB <<< "$(make_world foreignowned yes)"
X_TR_B="${X_TR%/*}/$SID_B.jsonl"
plant_agent "${X_TR_B%.jsonl}/subagents" "abb20f616-7777777777777" "worker"
roster_row "$X_REPO" "$SID_A" "worker" "" "" intended
observe "$SID_A" "$X_TR_B" "$X_REPO" "worker"

# A look taken by somebody else (slice 4/6, D-3): the record is fresh, this
# session's, and about the right target — and it is not the stopper's own.
IFS='|' read -r B_REPO B_TR B_SUB <<< "$(make_world borrowedlook yes)"
plant_agent "$B_SUB" "aworker-1111111111111111" "worker"
roster_row "$B_REPO" "$SID_A" "worker" "aworker-1111111111111111"
observe "$SID_A" "$B_TR" "$B_REPO" "worker" "asubagent-2020202020202020"

# The contracted progress artifact written after the look (slice 4/6, D-6): the
# working log is untouched, so this is the channel D-1 alone could not see.
IFS='|' read -r G_REPO G_TR G_SUB <<< "$(make_world progressstale yes)"
plant_agent "$G_SUB" "aworker-1111111111111111" "worker"
roster_row "$G_REPO" "$SID_A" "worker" "aworker-1111111111111111" ".bionic/tmp/w99.progress"
printf 'stage 1\n' > "$G_REPO/.bionic/tmp/w99.progress"
observe "$SID_A" "$G_TR" "$G_REPO" "worker"
sleep 1
printf 'stage 2\n' >> "$G_REPO/.bionic/tmp/w99.progress"

# Unknown schema version: a record this gate will not guess at (checklist A6).
IFS='|' read -r V_REPO V_TR V_SUB <<< "$(make_world badversion yes)"
plant_agent "$V_SUB" "aworker-1111111111111111" "worker"
roster_row "$V_REPO" "$SID_A" "worker" "aworker-1111111111111111"
mkdir -p "$V_REPO/.bionic/tmp"
printf 'v9|session=%s|target=%s|typed=worker|log=%s|mtime=1|size=1\n' \
  "$SID_A" "aworker-1111111111111111" "$V_SUB/agent-aworker-1111111111111111.jsonl" \
  > "$V_REPO/.bionic/tmp/stop-check.state"

# A symlinked state path — a hostile repo may CLOSE the wall, never open it (§8).
IFS='|' read -r L_REPO L_TR L_SUB <<< "$(make_world symlinked yes)"
plant_agent "$L_SUB" "aworker-1111111111111111" "worker"
mkdir -p "$L_REPO/.bionic/tmp"
ln -s "$SANDBOX/elsewhere.state" "$L_REPO/.bionic/tmp/stop-check.state"

# AN ATTESTED ACTIVE WORLD WHOSE PATROL WAS NEVER ARMED (epic-17 W5 4/4, spec AC-6). The
# environment is sound and the brief is well-formed; what is missing is the clock that would
# notice the dispatched agent dying. Its direction is REFUSE, LOUD — the second surviving
# refusal on this path, and the only one that is not about the environment.
IFS='|' read -r Q_REPO Q_TR Q_SUB <<< "$(make_world patrol-unarmed yes)"
mkdir -p "$Q_REPO/.bionic/tmp"
printf '# attestation\nversion=1\nkind=preflight-attestation\nsession_id=%s\n' "$SID_A" \
  > "$Q_REPO/.bionic/tmp/preflight-$SID_A.state"
rm -f "$Q_REPO"/.bionic/tmp/patrol-*.state
Q_SLUG=$(printf '%s' "$Q_REPO" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$Q_SLUG"
printf '{}\n' > "$CLAUDE_CONFIG_DIR/projects/$Q_SLUG/$SID_A.jsonl"

# An unattested world whose STATE DIRECTORY is unwritable — the environment probe's
# own state-dir blocking check genuinely fails (w2-s45-wallfacts.md §5 judgment call 9:
# never an absent credential, since the third credential source is the machine login
# keychain and no sandbox can take that away). This is the row that carries the
# surviving REFUSE direction under R5: unlike start|unattested/foreign-attestation
# above, the auto-probe here has a real, deterministic reason to refuse. Same
# chmod-500 technique tests/preflight-probe.test.sh uses for its own state-dir case.
IFS='|' read -r U_REPO U_TR U_SUB <<< "$(make_world probeblocked yes)"
plant_agent "$U_SUB" "aworker-1111111111111111" "worker"
mkdir -p "$U_REPO/.bionic/tmp"
chmod 500 "$U_REPO/.bionic/tmp"

# ---------------------------------------------------------------- the driver

DRV_ST=0; DRV_OUT=""; DRV_ERR=""
drive() {  # <condition>
  local p
  case "$1" in
    # --- start gate ---------------------------------------------------------
    start:irrelevant-tool)  p=$(payload Bash "$SID_A" "$A_TR" "$A_REPO" "echo hi") ;;
    start:empty-cwd)        p=$(payload Agent "$SID_A" "$A_TR" "" -) ;;
    start:non-git-cwd)      p=$(payload Agent "$SID_A" "$A_TR" "$SANDBOX/plain" -) ;;
    start:no-plan)          p=$(payload Agent "$SID_A" "$I_TR" "$I_REPO" -) ;;
    start:plan-names-no-step) p=$(payload Agent "$SID_A" "$N_TR" "$N_REPO" -) ;;
    start:no-session-key)   p=$(payload Agent - "$A_TR" "$A_REPO" -) ;;
    start:unattested)       p=$(payload Agent "$SID_A" "$A_TR" "$A_REPO" -) ;;
    start:foreign-attestation) p=$(payload Agent "$SID_B" "$T_TR" "$T_REPO" -) ;;
    start:attested)         p=$(payload Agent "$SID_A" "$T_TR" "$T_REPO" -) ;;
    start:probe-refuses)    p=$(payload Agent "$SID_A" "$U_TR" "$U_REPO" -) ;;
    start:patrol-unarmed)   p=$(payload Agent "$SID_A" "$Q_TR" "$Q_REPO" -) ;;
    # --- stop gate ----------------------------------------------------------
    stop:irrelevant-tool)   p=$(payload Read "$SID_A" "$A_TR" "$A_REPO" -) ;;
    stop:empty-cwd)         p=$(payload TaskStop "$SID_A" "$A_TR" "" worker) ;;
    stop:non-git-cwd)       p=$(payload TaskStop "$SID_A" "$A_TR" "$SANDBOX/plain" worker) ;;
    stop:no-plan)           p=$(payload TaskStop "$SID_A" "$I_TR" "$I_REPO" worker) ;;
    stop:plan-names-no-step) p=$(payload TaskStop "$SID_A" "$N_TR" "$N_REPO" worker) ;;
    stop:no-session-key-inert) p=$(payload TaskStop - "$I_TR" "$I_REPO" worker) ;;
    stop:no-session-key)    p=$(payload TaskStop - "$A_TR" "$A_REPO" worker) ;;
    stop:empty-target)      p=$(payload TaskStop "$SID_A" "$A_TR" "$A_REPO" "") ;;
    stop:no-transcript)     p=$(payload TaskStop "$SID_A" - "$A_REPO" worker) ;;
    stop:unresolvable)      p=$(payload TaskStop "$SID_A" "$A_TR" "$A_REPO" ghost) ;;
    stop:unresolvable-addressed) p=$(payload TaskStop "$SID_A" "$A_TR" "$A_REPO" "ghost@session-deadbeef") ;;
    stop:ambiguous)         p=$(payload TaskStop "$SID_A" "$A_TR" "$A_REPO" twin) ;;
    stop:no-observation)    p=$(payload TaskStop "$SID_A" "$A_TR" "$A_REPO" worker) ;;
    stop:foreign-observation) p=$(payload TaskStop "$SID_A" "$F_TR" "$F_REPO" worker) ;;
    stop:unknown-schema)    p=$(payload TaskStop "$SID_A" "$V_TR" "$V_REPO" worker) ;;
    stop:stale-observation) p=$(payload TaskStop "$SID_A" "$S_TR" "$S_REPO" worker) ;;
    stop:symlinked-state)   p=$(payload TaskStop "$SID_A" "$L_TR" "$L_REPO" worker) ;;
    stop:foreign-by-name)   p=$(payload TaskStop "$SID_A" "$X_TR_B" "$X_REPO" worker) ;;
    stop:borrowed-look)     p=$(payload TaskStop "$SID_A" "$B_TR" "$B_REPO" worker) ;;
    stop:progress-stale)    p=$(payload TaskStop "$SID_A" "$G_TR" "$G_REPO" worker) ;;
    stop:observed)          p=$(payload TaskStop "$SID_A" "$O_TR" "$O_REPO" worker) ;;
    stop:foreign-by-full-id) p=$(payload TaskStop "$SID_A" "$X_TR_B" "$X_REPO" abb20f616-7777777777777) ;;
    *) echo "unknown condition $1" >&2; return 9 ;;
  esac
  case "$1" in
    start:*) DRV_OUT=$(printf '%s' "$p" | bash "$START_GATE" 2>"$SANDBOX/.err") ;;
    stop:*)  DRV_OUT=$(printf '%s' "$p" | bash "$STOP_GATE"  2>"$SANDBOX/.err") ;;
  esac
  DRV_ST=$?
  DRV_ERR=$(cat "$SANDBOX/.err")
  return 0
}

# ============================================================
# THE TABLE. One row per driven condition; the `direction` column is the §7 cell
# it discharges. OPEN = exit 0; CLOSED = exit 2 (the code that blocks the tool
# call). SILENT = nothing on either stream; LOUD = a refusal on stderr;
# SILENT-WITH-ANNOUNCE = exit 0, stdout empty, but ONE operator-facing line on
# stderr reporting that the wall took an action on the operator's behalf (R5:
# the auto-probe ran and passed) — distinct from LOUD, which reports a refusal.
# PASSTHROUGH = exit 0, stdout empty, and the specific PASSTHROUGH-labeled line
# on stderr naming the target that was let through unrefused (T4, AC-6,
# session-20260815-landing-cleanup: a TaskStop target that resolves to no agent
# AND wears no agent-address shape is not this gate's business) — distinct from
# SILENT-WITH-ANNOUNCE, whose announce line is the auto-probe's, not this one's.
# ============================================================
TABLE='
start|irrelevant-tool|0|silent|Start gate — any ambiguity, anywhere: OPEN, silent
start|empty-cwd|0|silent|Start gate — any ambiguity, anywhere: OPEN, silent
start|non-git-cwd|0|silent|Start gate — any ambiguity, anywhere: OPEN, silent
start|no-plan|0|silent|Start gate — any ambiguity, anywhere: OPEN, silent
start|plan-names-no-step|0|silent|Start gate — any ambiguity, anywhere: OPEN, silent
start|no-session-key|0|silent|Payload missing its session key — start: OPEN
start|unattested|0|silent-with-announce|Start gate — R5 attestation never blocks: the wall auto-runs the probe, the probe succeeds, and the dispatch proceeds with one announce line
start|foreign-attestation|0|silent-with-announce|Start gate — R5 attestation never blocks: a foreign-only attestation does not belong to this session, so the wall auto-probes exactly as unattested does and proceeds
start|attested|0|silent|Start gate — the positive pair: pass in silence
start|probe-refuses|2|loud|Start gate — one of two surviving refusals under R5: the auto-probe itself genuinely fails (unwritable state dir), so the dispatch is REFUSED quoting the reason the probe gives
start|patrol-unarmed|2|loud|Start gate — the arming wall: environment sound, brief well-formed, but no Patrol has stamped this session, so nothing would notice the dispatched agent dying — REFUSED with both re-arm commands named
stop|irrelevant-tool|0|silent|Stop gate — before the active-wave verdict: OPEN, silent
stop|empty-cwd|0|silent|Stop gate — before the active-wave verdict: OPEN, silent
stop|non-git-cwd|0|silent|Stop gate — before the active-wave verdict: OPEN, silent
stop|no-plan|0|silent|Stop gate — before the active-wave verdict: OPEN, silent
stop|plan-names-no-step|0|silent|Stop gate — before the active-wave verdict: OPEN, silent
stop|no-session-key-inert|0|silent|Stop gate — before the active-wave verdict: OPEN, silent
stop|no-session-key|2|loud|Payload missing its session key — stop: CLOSED
stop|empty-target|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|no-transcript|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|unresolvable|0|passthrough|Stop gate — T4 carve: an unresolved target wearing no agent-address shape passes through, OPEN
stop|unresolvable-addressed|2|loud|Stop gate — T4 carve: an unresolved target that DOES wear an agent-address shape still refuses, CLOSED
stop|ambiguous|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|no-observation|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|foreign-observation|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|unknown-schema|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|stale-observation|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|symlinked-state|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|foreign-by-name|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|borrowed-look|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|progress-stale|2|loud|Stop gate — after the verdict: CLOSED, loud
stop|observed|0|silent|Stop gate — the positive pair: a fresh observation permits
stop|foreign-by-full-id|0|silent|Stop gate — the positive pair: a fresh observation permits
'

echo "=== §7 rows driven as behaviour (AC-10) ==="
while IFS='|' read -r surface cond want_exit want_loud row; do
  [ -n "$surface" ] || continue
  drive "$surface:$cond"
  if [ "$DRV_ST" = "$want_exit" ]; then
    ok "$surface/$cond exits $want_exit — $row"
  else
    no "$surface/$cond exits $want_exit — $row" "got exit $DRV_ST; stderr: $(printf '%s' "$DRV_ERR" | head -1)"
  fi
  if [ "$want_loud" = "silent" ]; then
    if [ -z "$DRV_OUT" ] && [ -z "$DRV_ERR" ]; then
      ok "$surface/$cond is SILENT on both streams"
    else
      no "$surface/$cond is SILENT on both streams" "stdout='$DRV_OUT' stderr='$DRV_ERR'"
    fi
  elif [ "$want_loud" = "silent-with-announce" ]; then
    if [ -z "$DRV_OUT" ] && [ -n "$DRV_ERR" ]; then
      ok "$surface/$cond is SILENT-WITH-ANNOUNCE — stdout empty, one operator-facing line on stderr"
    else
      no "$surface/$cond is SILENT-WITH-ANNOUNCE — stdout empty, one operator-facing line on stderr" \
         "stdout='$DRV_OUT' stderr='$DRV_ERR'"
    fi
  elif [ "$want_loud" = "passthrough" ]; then
    if [ -z "$DRV_OUT" ] && printf '%s' "$DRV_ERR" | grep -qF 'PASSTHROUGH'; then
      ok "$surface/$cond is PASSTHROUGH — stdout empty, PASSTHROUGH line present on stderr"
    else
      no "$surface/$cond is PASSTHROUGH — stdout empty, PASSTHROUGH line present on stderr" \
         "stdout='$DRV_OUT' stderr='$DRV_ERR'"
    fi
  else
    if [ -n "$DRV_ERR" ]; then
      ok "$surface/$cond is LOUD — it says why on stderr"
    else
      no "$surface/$cond is LOUD — it says why on stderr" "stderr was empty"
    fi
  fi
done <<EOF
$(printf '%s' "$TABLE")
EOF

# ============================================================
echo ""
echo "=== the asymmetry itself: ONE missing field, TWO directions ==="
# ============================================================
#
# Checklist A10's defect was not a wrong direction — it was that no test asserted
# the two directions were different ON PURPOSE. The same absent `session_id`, the
# same active wave, adjacent:

drive start:no-session-key
S_START=$DRV_ST; S_START_ERR=$DRV_ERR
drive stop:no-session-key
S_STOP=$DRV_ST; S_STOP_ERR=$DRV_ERR

expect_eq "a keyless payload at the START gate passes (open)"   "0" "$S_START"
expect_eq "a keyless payload at the STOP gate is refused (closed)" "2" "$S_STOP"
if [ "$S_START" != "$S_STOP" ]; then
  ok "the directions differ — recorded inconsistency, accepted by §7, not an accident"
else
  no "the directions differ" "both gates answered $S_START"
fi
expect_eq "the open side stays silent about it" "" "$S_START_ERR"

# ============================================================
echo ""
echo "=== the producer's two rows (§7 rows 4 and 5) ==="
# ============================================================

P_REPO="$SANDBOX/w/producer/repo"; mkdir -p "$P_REPO/.bionic/tmp"
git -C "$P_REPO" init -q 2>/dev/null

# slice 4/2 (D-5): both rows are about what a run does to an attestation ALREADY on
# disk, so each fixture must sit at the per-session filename that run actually governs.
# Left at the old shared slot these rows stayed green for the wrong reason — the probe
# now prunes that legacy file unconditionally, so "no attestation is on disk" below was
# satisfied by the prune rather than by the blocking-failure delete it exists to pin.
PRIOR_B="$P_REPO/.bionic/tmp/preflight-$SID_B.state"
printf '# attestation\nversion=1\nsession_id=%s\n' "$SID_B" > "$PRIOR_B"
PRIOR_SUM=$(shasum "$PRIOR_B")

# Row 4 — no session key: REFUSE, and state is LEFT UNTOUCHED. An unkeyed run
# cannot tell whose attestation is on disk, so deleting it would destroy another
# session's valid stamp (slice 4/1 resolution).
OUT=$( cd "$P_REPO" && env -u CLAUDE_CODE_SESSION_ID ANTHROPIC_API_KEY=x \
       HOME="$HOME" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$PROBE" 2>&1 ); ST=$?
expect_eq "environment check with no session key REFUSES (exit 3)" "3" "$ST"
expect_eq "…and leaves existing state byte-identical" "$PRIOR_SUM" "$(shasum "$PRIOR_B")"

# Row 5 — a blocking probe fails: NO ATTESTATION, and the prior one is deleted.
# A stale pass must not outlive the environment it described. The prior stamp is THIS
# session's own, so pruning never touches it — only the blocking-failure path can.
PRIOR_A="$P_REPO/.bionic/tmp/preflight-$SID_A.state"
printf '# attestation\nversion=1\nsession_id=%s\n' "$SID_A" > "$PRIOR_A"
OUT=$( cd "$P_REPO" && env -u ANTHROPIC_API_KEY CLAUDE_CODE_SESSION_ID="$SID_A" \
       HOME="$SANDBOX/nocred" CLAUDE_CONFIG_DIR="$SANDBOX/nocred/.claude" \
       PATH="$SANDBOX/stub:$PATH" bash "$PROBE" 2>&1 ); ST=$?
expect_eq "environment check with a failing blocking probe exits 1" "1" "$ST"
expect_eq "…and no attestation is on disk" "no" "$([ -e "$PRIOR_A" ] && echo yes || echo no)"

echo ""
echo "──────────────────────────────────────────────"
echo "fail-direction-table: ${PASS} passed, ${FAIL} failed, ${TOTAL} total"
[ "$FAIL" -eq 0 ]
