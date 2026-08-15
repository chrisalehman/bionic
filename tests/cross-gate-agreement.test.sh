#!/bin/bash
# CROSS-COMPONENT INSTRUMENT PROOFS — epic-15 wave-01R, slice 4/6.
#
# Serves AC-9 (N-way agreement over every copy of a duplicated concept,
# including the actively-maintained origin; one-copy mutation goes red) and the
# cross-script share of AC-8 (no command text in any written artefact;
# unpredictable temp names across all four scripts).
#
# Governing design: design/orchestrator-subagent-coordination.md §8, §9.
# Known-failure checklist: .bionic/docs/record/epic-15-w1r-known-failure-checklist.md
# A8 (duplicated logic with only a 2-way agreement test — the origin missing
# from the test meant to catch drift) and A9 (green suites hid undiscriminated
# parser edges: quoted values, absolute paths, duplicate directive lines,
# indentation — proven by a one-copy mutation staying green).
#
# WHAT THIS SUITE IS FOR, and what it deliberately is not:
#
#   The per-script suites (hooks/{preflight-probe,dispatch-preflight,stop-check,
#   stop-guard}.test.sh) each drive ONE component against its own contract. Every
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
# equal makes every disagreement between them invisible. That is not
# hypothetical: this file previously pinned the equal case, and behind it the
# observation resolved NOTHING while the recorder wrote a record and the stop
# gate spent it (Step-6 critic, issue 1). Every metadata fixture below is
# planted under $CLAUDE_CONFIG_DIR, which is what the platform does when the
# variable is set; §C case 5 plants under $HOME/.claude and proves it is NOT
# seen.
#
# Usage: bash tests/cross-gate-agreement.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

# The four parties. Overridable so the suite can be driven against a MUTATED
# COPY of any one of them without the shipped file ever being modified — that
# substitution is how §9's mutation-and-restore proof is taken here, and how a
# reviewer can re-take it by hand:
#   W1R_PARTY_DP=/tmp/mutant.sh bash tests/cross-gate-agreement.test.sh
PARTY_DP="${W1R_PARTY_DP:-$REPO_ROOT/hooks/dispatch-preflight.sh}"
PARTY_SG="${W1R_PARTY_SG:-$REPO_ROOT/hooks/stop-guard.sh}"
PARTY_EG="${W1R_PARTY_EG:-$REPO_ROOT/hooks/canonical-sdlc-evidence-gate.sh}"
# The recorder moved out of the stop gate at slice 4/4: observations are written
# post-execution by their own script, from the producer's own printed output.
PARTY_ER="${W1R_PARTY_ER:-$REPO_ROOT/hooks/execution-recorder.sh}"

PROBE="$REPO_ROOT/hooks/preflight-probe.sh"
OBSERVE="$REPO_ROOT/hooks/stop-check.sh"
SWEEPER="$REPO_ROOT/hooks/session-sweeper.sh"
# The landing gate (epic-16 wave-01) is a fifth party and an overridable one for
# the same reason the four above are: §J drives a MUTATED COPY of it to prove the
# verdict/gate battery discriminates, and the shipped file is never touched.
PARTY_LG="${W1R_PARTY_LG:-$REPO_ROOT/hooks/landing-gate.sh}"
# §J also drives a mutated copy of the SWEEPER, to prove the opposite direction:
# a change to the predicate moves both answers rather than splitting them.
PARTY_SW="$SWEEPER"

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
# Since slice 4/5, hooks/stop-check.sh reads CLAUDE_CODE_SESSION_ID to classify a
# target against ITS OWN session's roster. This suite runs inside a real Claude
# Code session, which exports a real one; unpinned, every bare `bash "$OBSERVE"`
# call below would silently classify against WHATEVER session happens to be
# running the suite instead of UNKNOWN, the always-reachable answer none of
# these fixtures set a roster up for. Section E opts back in explicitly, per call,
# exactly where OURS is the fact under test.
unset CLAUDE_CODE_SESSION_ID

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_absent()   { if printf '%s' "$3" | grep -qF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }

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
# The Agent tool_input carries a name and a contract-bearing brief (slice 4/3):
# tool_input became load-bearing when the start gate began journalling the launch
# to the session roster, and a brief with no labeled contract fields is warned
# about on stderr. This suite's claim is producer/consumer AGREEMENT ON THE
# ATTESTATION — "passes in silence" below means the attestation raised nothing —
# so the fixture is the ordinary dispatch, not a malformed one. The warning
# itself is driven where it belongs, in hooks/dispatch-preflight.test.sh S10c.

mk_agent_payload() {  # <sid> <cwd>
  jq -n --arg s "$1" --arg c "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:"implementor", name:"w99-impl",
                  prompt:"Expected artifact: .bionic/docs/record/w99.txt\nExpected duration: ~25 minutes.\nProgress artifact: .bionic/tmp/w99.progress"},
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

mk_bash_payload() {  # <sid> <transcript> <cwd> <command>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg m "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$m}, tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
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

# The TEAMMATE completion (epic-16 wave-01 slice 0). FAITHFUL to
# .bionic/docs/record/landing-wave-capture-probe.md §3-A and the live re-capture
# slice 0 took through the pty harness: `tool_response.status` is
# `teammate_spawned`, and `agent_id`/`teammate_id` both carry the ADDRESSING form
# `<name>@session-<id8>` — never the transcript form, which no PostToolUse
# payload contains. This is the dispatch mode every interactive session on this
# machine really uses; `mk_agent_post` above is the async one.
mk_agent_post_teammate() {  # <sid> <transcript> <cwd> <name> <addressing-id> <tool_use_id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg n "$4" --arg a "$5" --arg u "$6" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PostToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                  run_in_background:true, name:$n},
      tool_response:{status:"teammate_spawned", prompt:"go",
                     teammate_id:$a, agent_id:$a, agent_type:"implementor",
                     model:"claude-opus-5", name:$n, color:"blue",
                     tmux_session_name:"in-process", tmux_window_name:"in-process",
                     tmux_pane_id:"in-process", team_name:"session-6c85684c",
                     is_splitpane:false, plan_mode_required:false},
      tool_use_id:$u, duration_ms:9}'
}

# The SubagentStart event (slice 1). VERBATIM shape from capture probe §3-C: six
# keys and no `tool_name` at all, which is why the recorder's third arm cannot sit
# behind the tool-name gate its other two share. `agent_type` is the teammate's
# NAME here — the platform's own rename — and `agent_id` is the TRANSCRIPT form.
mk_start_payload() {  # <sid> <transcript> <cwd> <name> <transcript-id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg n "$4" --arg a "$5" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      agent_id:$a, agent_type:$n, hook_event_name:"SubagentStart"}'
}

# The SubagentStop event (slice 5). FAITHFUL to capture probe §3-D, a live teammate
# stop: `agent_type` carries the name, `agent_id` the transcript form,
# `background_tasks[]` its task-id key. Only the four fields the gate reads vary.
mk_substop_payload() {  # <cwd> <sid> <agent_type> <stop_hook_active true|false>
  jq -n --arg c "$1" --arg s "$2" --arg a "$3" --argjson h "$4" \
    '{session_id:$s, transcript_path:("/tmp/transcripts/" + $s + ".jsonl"), cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      permission_mode:"bypassPermissions",
      agent_id:"aprobemate-4da9be517e8f90bd", agent_type:$a,
      effort:{level:"high"}, hook_event_name:"SubagentStop", stop_hook_active:$h,
      agent_transcript_path:("/tmp/transcripts/" + $s + "/subagents/agent-aprobemate-4da9be517e8f90bd.jsonl"),
      last_assistant_message:"DONE\n\nRan the slice; report written.",
      background_tasks:[{id:"tooha5cgi", type:"teammate", status:"running",
                         description:"run the slice and report"}],
      session_crons:[]}'
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

# THE PRODUCER→RECORDER PAIR, DRIVEN END TO END. Since slice 4/4 the recorder
# reads no command line: it copies the machine line the observation printed. So
# the only honest way to ask "what did the recorder write for this command" is to
# RUN the observation and hand its real stdout to the real recorder — which is
# also what makes the two halves one fact rather than two parsers (F-1).
run_pair() {  # <repo> <transcript> <sid> <args…> -> recorder's exit status; sets PAIR_OUT
  local repo="$1" tr="$2" sid="$3"; shift 3
  PAIR_OUT=$( cd "$repo" && bash "$OBSERVE" "$@" 2>/dev/null )
  mk_bash_post "$sid" "$tr" "$repo" "bash ~/.claude/hooks/stop-check.sh $*" "$PAIR_OUT" \
    | bash "$PARTY_ER" >/dev/null 2>&1
}

# THE SESSION ROSTER, in the shape its writer writes it — field for field from
# hooks/dispatch-preflight.sh's `ROW=` line. Both the producer (classification,
# contract state) and the stop gate (the foreign-stop rule) read this file, which
# is precisely why it is planted from ONE helper here: a fixture written twice is
# two shapes, and this suite exists to catch exactly that.
roster_row() {  # <repo> <sid> <name> <agent-id> [progress] [status]
  local repo="$1" sid="$2" name="$3" aid="$4" prog="${5:-}" status="${6:-confirmed}"
  local f="$repo/.bionic/tmp/roster-$sid.state"
  mkdir -p "$repo/.bionic/tmp"
  [ -f "$f" ] || printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=%s|absent=|tool_use_id=toolu_01FIXTURE\n' \
    "$status" "$sid" "$name" "$aid" "$prog" >> "$f"
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
#   stop-guard          refuse (exit 2, target unresolvable)     <=> yes
#   evidence-gate       "has no 'Step N:' line" (exit 2)         <=> yes, and N
#                       is the derived value itself — the only party that
#                       reports it, which is why the fixtures below are built so
#                       that a MIS-PARSE FLIPS THE PREDICATE rather than merely
#                       changing a value. A fixture whose mis-parse is invisible
#                       to two of three parties proves nothing about them (A9).
#
# Deliberately out of the battery, and why:
#   * `current: T<n>` — the two gates accept a task token unconditionally; the
#     evidence gate accepts it only on a `scale: task` plan and then exits 0 on a
#     valid ledger, so its answer to the predicate is unobservable there. Both
#     behaviours are conservative and deliberate; the asymmetry is pinned as a
#     KNOWN DIVERGENCE in section A3 rather than mixed into the agreement rows.
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

# The recorder holds the FOURTH copy of active-wave detection (slice 4/4), and a
# duplicated wall nothing drives is a wall that diverges. Its observable is the
# roster: with a wave active it completes an `intended` row on execution
# confirmation, and outside one it is inert. The row is re-seeded on every call so
# the answer describes this run and not a previous one.
verdict_er() {  # <repo> -> yes|no|other:<detail>
  local repo="$1" out st roster="$repo/.bionic/tmp/roster-$SID_A.state"
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
    printf 'roster-state/v1|status=intended|session=%s|name=battery|agent_id=|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=|deliverable=|duration=|progress=|absent=|tool_use_id=toolu_BATTERY\n' \
      "$SID_A"
  } > "$roster"
  out=$(mk_agent_post "$SID_A" "$SANDBOX/t.jsonl" "$repo" "toolu_BATTERY" | bash "$PARTY_ER" 2>&1); st=$?
  if [ "$st" -ne 0 ]; then echo "other:exit-$st"; return; fi
  if [ -n "$out" ]; then echo "other:output"; return; fi
  if grep -q 'status=confirmed' "$roster" 2>/dev/null; then echo yes; else echo no; fi
}

# The evidence gate is the only party that reports the DERIVED VALUE, so its
# answer is `yes:<value>` where the others answer `yes`. Callers split on `:`.
verdict_eg() {  # <repo> -> yes:<current>|no|other:<detail>
  local out st
  out=$(mk_bash_payload "$SID_A" "$SANDBOX/t.jsonl" "$1" "git commit -m x" \
        | env -u CLAUDE_PROJECT_DIR bash "$PARTY_EG" 2>&1); st=$?
  if [ "$st" -eq 0 ]; then echo no; return; fi
  case "$out" in
    *"has no 'Step "*)
      printf 'yes:%s\n' \
        "$(printf '%s' "$out" | sed -n "s/.*has no 'Step \([^']*\):' line.*/\1/p" | head -1)" ;;
    *"missing a valid 'current: N' line"*) echo no ;;
    *"empty '## SDLC State' section"*)     echo "other:empty-section" ;;
    *) echo "other:$(printf '%s' "$out" | head -1 | cut -c1-60)" ;;
  esac
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
  local repo="$1" out st roster="$repo/.bionic/tmp/roster-$SID_LG.state"
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
    printf 'roster-state/v1|status=confirmed|session=%s|name=lg-probe|agent_id=alg-probe-0001|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=.bionic/docs/record/never-lg.md|source=declared|duration=|progress=|claims=|cadence=|absent=|waiver=|tool_use_id=toolu_LGPROBE\n' \
      "$SID_LG"
  } > "$roster"
  out=$(mk_stopsweep_payload "$repo" "$SID_LG" false | bash "$PARTY_LG" 2>&1); st=$?
  case "$st" in
    0) echo no ;;
    2) if printf '%s' "$out" | grep -qF 'LANDING CONTRACT UNMET'; then echo yes; else echo "other:block-no-detail"; fi ;;
    *) echo "other:exit-$st" ;;
  esac
}

# ---------------------------------------------------------------- fixtures

write_plan() {  # <path> <state-body>
  mkdir -p "$(dirname "$1")"
  {
    printf -- '---\n'
    printf 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 13\n'
    printf 'intent: build\nrigor: audited\nscale: wave\n'
    printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\nintegration-branch: main\n'
    printf '%s\n' "$2"
    printf '\n- Step 3: prior evidence\n'
  } > "$1"
}

new_repo() {  # <name> -> path
  local r="$SANDBOX/fx/$1/repo"
  mkdir -p "$r/.bionic"
  git -C "$r" init -q 2>/dev/null
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
marker-less-newest-loses|yes|4
fenced-only-newest-loses|yes|4
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
      printf -- '---\ncanonical_sdlc_version: 13\n---\n\n# Notes\n\ncurrent: 4\n' \
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
        printf -- '---\ncanonical_sdlc_version: 13\nscale: wave\n---\n\n# Schema doc\n\n'
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
      printf -- '---\ncanonical_sdlc_version: 13\n---\n\n# Continuation\n\ncurrent: 4\n' \
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
        printf -- '---\ncanonical_sdlc_version: 13\n---\n\n# Schema notes\n\n'
        printf 'The section looks like this:\n\n```\n## SDLC State\n\ncurrent: 4\n```\n'
      } > "$repo/.bionic/docs/plans/epic-99/schema-notes.md"
      touch -t 203001010000 "$repo/.bionic/docs/plans/epic-99/schema-notes.md" ;;
    only-marker-less-files)
      # THE PRESERVED AMBIGUITY. A plans tree holding no valid plan at all still
      # reads as "no wave" and passes SILENTLY — the ratified fail direction, and
      # the reason the fix is a candidate filter rather than a refusal: skipping
      # every candidate must land in the same place as finding none.
      mkdir -p "$repo/.bionic/docs/plans/epic-99"
      printf -- '---\ncanonical_sdlc_version: 13\n---\n\n# Continuation\n' \
        > "$repo/.bionic/docs/plans/epic-99/continuation.md"
      printf '# Scratch\n\ncurrent: 4\n' \
        > "$repo/.bionic/docs/plans/epic-99/scratch.md" ;;
    nested-two-deep)
      write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4" ;;
    nested-three-deep)
      # maxdepth 2 under plans/: this one is at depth 3 and is not found.
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

# run_battery <mode>  — mode=assert emits one assertion per fixture;
#                       mode=detect returns 1 at the FIRST disagreement.
run_battery() {
  local mode="$1" name want cur repo a b c d e cnorm cval
  while IFS='|' read -r name want cur; do
    [ -n "$name" ] || continue
    repo="$SANDBOX/fx/$name/repo"
    a=$(verdict_dp "$repo"); b=$(verdict_sg "$repo"); c=$(verdict_eg "$repo")
    d=$(verdict_er "$repo"); e=$(verdict_lg "$repo")
    cnorm="${c%%:*}"; cval=""
    [ "$cnorm" = "yes" ] && cval="${c#*:}"
    if [ "$mode" = "assert" ]; then
      if [ "$a" = "$want" ] && [ "$b" = "$want" ] && [ "$cnorm" = "$want" ] && [ "$d" = "$want" ] && [ "$e" = "$want" ]; then
        ok "all five parties agree on '$name': $want"
      else
        no "all five parties agree on '$name': $want" \
           "dispatch-preflight=$a stop-guard=$b evidence-gate=$c execution-recorder=$d landing-gate=$e"
      fi
      if [ "$want" = "yes" ]; then
        expect_eq "  and the evidence gate derived current='$cur' for '$name'" "$cur" "$cval"
      fi
    else
      # Detect mode also compares the DERIVED VALUE, so a mutation that selects a
      # different plan without flipping the predicate is caught too.
      if [ "$a" != "$want" ] || [ "$b" != "$want" ] || [ "$cnorm" != "$want" ] || [ "$d" != "$want" ] || [ "$e" != "$want" ] \
         || { [ "$want" = "yes" ] && [ "$cval" != "$cur" ]; }; then
        printf 'disagreement on %s: want=%s/%s dp=%s sg=%s eg=%s er=%s lg=%s\n' "$name" "$want" "$cur" "$a" "$b" "$c" "$d" "$e"
        return 1
      fi
    fi
  done <<EOF
$(printf '%s' "$FIXTURES")
EOF
  return 0
}

# ============================================================
echo ""
echo "=== A1 — N-way agreement on active-wave detection (AC-9, checklist A8/A9) ==="
# ============================================================
echo "parties: $(basename "$PARTY_DP") · $(basename "$PARTY_SG") · $(basename "$PARTY_EG") · $(basename "$PARTY_ER") · $(basename "$PARTY_LG")"

run_battery assert

# The origin is IN the test, not merely cited by it. Checklist A8's defect was
# exactly this: three byte-identical copies, a 2-way agreement test, and the
# actively-maintained origin absent from the test meant to catch drift.
expect_contains "the actively-maintained origin is one of the driven parties" \
  "canonical-sdlc-evidence-gate.sh" "$PARTY_EG"
# The landing gate carries a copy too (Step-6 critic D-1) — it is now a driven party, and
# the copy it holds is really the active-wave detection block, not something else.
expect_contains "the landing gate's active-wave copy is a driven party" \
  "landing-gate.sh" "$PARTY_LG"
expect_contains "…and the copy under test is genuinely the active-wave block" \
  "active-wave detection" "$(cat "$PARTY_LG")"

# ============================================================
echo ""
echo "=== A2 — one-copy mutation goes RED (checklist A9, TDD §9) ==="
# ============================================================
#
# A9's proof that the discarded run's ~450 assertions did not discriminate was a
# one-copy mutation that stayed GREEN. Each mutation below is applied to a COPY
# of ONE party — the shipped files are never modified, and their checksums are
# re-verified at the end — and the whole battery must then find a disagreement.
#
# Every mutation is a plausible drift, not damage: a maintainer editing one copy
# and not the other two.

CKSUM_BEFORE=$(shasum "$PARTY_DP" "$PARTY_SG" "$PARTY_EG" "$PARTY_ER" "$PARTY_LG" 2>/dev/null)
MUTDIR="$SANDBOX/mutants"; mkdir -p "$MUTDIR"
# A MUTATED landing gate still resolves its sweeper as a SIBLING, so one lives here for the
# LG party below to find. The shipped sweeper is never touched — this is a copy.
cp "$PARTY_SW" "$MUTDIR/session-sweeper.sh"

# mutate <src> <dst> <kind>  — rc 1 if the mutation matched nothing
mutate() {
  local src="$1" dst="$2" kind="$3"
  case "$kind" in
    docs-root-last-wins)   # head -1 -> tail -1, first occurrence (resolve_docs_root)
      awk 'BEGIN{d=0} !d && $0=="      | head -1 \\" {print "      | tail -1 \\"; d=1; next} {print}' \
        "$src" > "$dst" ;;
    keep-quotes)           # drop the quote-stripping sed in resolve_docs_root
      # `;s/[` is the second half of `s/^['"]//;s/['"]$//` and appears first, in
      # every party, on exactly that line.
      awk 'BEGIN{d=0} !d && index($0,";s/[") {print "      | cat \\"; d=1; next} {print}' \
        "$src" > "$dst" ;;
    delete-cr)             # translate-CR -> delete-CR (the fail-dangerous shape)
      awk '{ i=index($0,"gsub(/\\r/, \"\\n\"); ");
             while (i>0) { $0=substr($0,1,i-1) substr($0,i+20); i=index($0,"gsub(/\\r/, \"\\n\"); ") }
             print }' "$src" > "$dst" ;;
    depth-1)               # plan search one level shallower
      awk '{ i=index($0,"-maxdepth 2 -type f -name '"'"'*.md'"'"'");
             if (i>0) { $0=substr($0,1,i-1) "-maxdepth 1 -type f -name '"'"'*.md'"'"'" substr($0,i+33) }
             print }' "$src" > "$dst" ;;
    fence-blind)           # stop skipping fenced content
      awk '{ t=$0; sub(/^[ \t]+/,"",t); sub(/[ \t]+$/,"",t); if (t=="fence { next }") next; print }' \
        "$src" > "$dst" ;;
    no-marker-skip)        # accept marker-less candidates again (revert the AC-10 skip)
      awk '{ t=$0; sub(/^[ \t]+/,"",t); sub(/[ \t]+$/,"",t);
             if (t=="has_sdlc_state \"$f\" || continue") next; print }' "$src" > "$dst" ;;
    anchor-current)        # lose the leading-whitespace tolerance on `current:`
      awk '{ i=index($0,"'"'"'^[[:space:]]*current[[:space:]]*:'"'"'");
             if (i>0) { $0=substr($0,1,i-1) "'"'"'^current:'"'"'" substr($0,i+38) }
             print }' "$src" > "$dst" ;;
    *) echo "unknown mutation $kind" >&2; return 1 ;;
  esac
  cmp -s "$src" "$dst" && return 1
  return 0
}

MUTATIONS="docs-root-last-wins keep-quotes delete-cr depth-1 fence-blind anchor-current no-marker-skip"

# LG is the landing gate's active-wave copy (Step-6 critic D-1): every mutation below is an
# active-wave-detection drift, and the gate holds a byte-identical copy of that block, so the
# same six drifts must move its answer too or its copy is uncovered. ER is
# execution-recorder's copy (t6-review.md F-1's sibling finding, F-4): §A1 drives all five
# parties over the fixture matrix, but until now this loop asserted only DP/SG/EG/LG — ER's
# copy was held by shared-fixture agreement alone, never by a demonstration that drifting it
# turns the battery red the way it does for the other four.
for party in DP SG EG ER LG; do
  case "$party" in
    DP) src="$PARTY_DP" ;;
    SG) src="$PARTY_SG" ;;
    EG) src="$PARTY_EG" ;;
    ER) src="$PARTY_ER" ;;
    LG) src="$PARTY_LG" ;;
  esac
  for m in $MUTATIONS; do
    dst="$MUTDIR/$party-$m.sh"
    if ! mutate "$src" "$dst" "$m"; then
      # A mutation that matches nothing is not a passing test — it means the
      # code moved and this proof has gone vacuous (fixtures-can-pin-away-the-test).
      no "mutation '$m' applies to $(basename "$src")" "the awk target matched nothing — the code moved"
      continue
    fi
    saved_dp="$PARTY_DP"; saved_sg="$PARTY_SG"; saved_eg="$PARTY_EG"; saved_er="$PARTY_ER"; saved_lg="$PARTY_LG"
    case "$party" in
      DP) PARTY_DP="$dst" ;;
      SG) PARTY_SG="$dst" ;;
      EG) PARTY_EG="$dst" ;;
      ER) PARTY_ER="$dst" ;;
      LG) PARTY_LG="$dst" ;;
    esac
    if detail=$(run_battery detect); then
      no "one-copy mutation '$m' in $party makes the battery RED" \
         "the battery stayed green with one copy mutated — it does not discriminate"
    else
      ok "one-copy mutation '$m' in $party makes the battery RED"
    fi
    PARTY_DP="$saved_dp"; PARTY_SG="$saved_sg"; PARTY_EG="$saved_eg"; PARTY_ER="$saved_er"; PARTY_LG="$saved_lg"
  done
done

expect_eq "the five shipped parties are byte-identical to before the mutations" \
  "$CKSUM_BEFORE" "$(shasum "$PARTY_DP" "$PARTY_SG" "$PARTY_EG" "$PARTY_ER" "$PARTY_LG" 2>/dev/null)"

# ============================================================
echo ""
echo "=== A3 — the one KNOWN divergence, pinned so it cannot drift silently ==="
# ============================================================
#
# `current: T<n>` on a plan that is not `scale: task`: the two gates read the
# task token as an active wave (conservative — a task run IS a run); the
# evidence gate rejects the plan as invalid, because a T-token is legal only at
# task scale (conservative in the other direction — it blocks the commit). Both
# refuse; neither passes. Nothing here is a defect, and the reason this is
# pinned rather than left implicit is checklist A10: an unpinned asymmetry
# between gates is exactly what shipped last time.

TREPO=$(new_repo "known-divergence")
write_plan "$TREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: T4"
expect_eq "T-token, wave scale: the start gate reads an active wave"  "yes" "$(verdict_dp "$TREPO")"
expect_eq "T-token, wave scale: the stop gate reads an active wave"   "yes" "$(verdict_sg "$TREPO")"
expect_eq "T-token, wave scale: the evidence gate rejects the plan instead" \
  "no" "$(verdict_eg "$TREPO")"

# ============================================================
echo ""
echo "=== B — the session-identity key: producer and BOTH consumers agree ==="
# ============================================================
#
# Ownership table (spec §Design): preflight-probe WRITES the session identity;
# dispatch-preflight and stop-guard READ it. The per-component suites each hold
# their own half — the producer's suite reads back what it wrote, the start
# gate's suite writes attestations as fixtures. Neither proves the two halves
# spell or compare the key the same way. Here ONE value produced by the REAL
# producer flows through both consumers.

IREPO=$(new_repo "identity")
# The metadata lives where the PLATFORM puts it — under the configured metadata
# root, in this project's slug directory, in this session's own directory. The
# earlier version of this fixture invented a transcript path outside any
# projects root, which let the record and the gate-pass below stand behind an
# observation that resolved nothing (Step-6 critic, issue 1). A fixture that
# cannot be reached by BOTH parties proves nothing about their agreement.
ISLUG=$(printf '%s' "$IREPO" | sed 's/[^a-zA-Z0-9]/-/g')
IPROJ="$CLAUDE_CONFIG_DIR/projects/$ISLUG"
ISUB="$IPROJ/$SID_A/subagents"
mkdir -p "$ISUB"
ITR="$IPROJ/$SID_A.jsonl"
printf '{}\n' > "$ITR"
printf '{"name":"worker","agentType":"implementor"}' > "$ISUB/agent-aworker-1111111111111111.meta.json"
printf '{}\n' > "$ISUB/agent-aworker-1111111111111111.jsonl"
write_plan "$IREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"

# The producer, run for real, with the session key on the channel it actually
# reads (CLAUDE_CODE_SESSION_ID — slice 4/1's resolution) and a credential
# present so the blocking probes pass.
( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" ANTHROPIC_API_KEY="sk-fixture-not-a-real-key" \
    HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
    bash "$PROBE" >"$SANDBOX/probe.out" 2>"$SANDBOX/probe.err" )
PROBE_ST=$?
expect_eq "the producer wrote an attestation (exit 0)" "0" "$PROBE_ST"
# slice 4/2 (D-5): the session identity is now carried in TWO places that must agree —
# the FILENAME and the session_id= line inside it. A producer and a consumer that
# disagreed on the filename scheme would refuse every dispatch, so the path is asserted
# here as part of the same agreement the key is.
ATT="$IREPO/.bionic/tmp/preflight-$SID_A.state"
expect_eq "the attestation exists where both consumers look" "yes" "$([ -f "$ATT" ] && echo yes || echo no)"
expect_eq "and nothing was left in the legacy single-slot both parties abandoned" "no" \
  "$([ -e "$IREPO/.bionic/tmp/preflight.state" ] && echo yes || echo no)"

# The producer's spelling and the consumer's spelling are the same key.
expect_contains "the producer spells the identity key 'session_id='" "session_id=$SID_A" "$(cat "$ATT")"
expect_contains "the start gate reads that same key by name" "'^session_id='" "$(cat "$PARTY_DP")"

# Consumer 1 — the start gate: the produced value passes; one character off refuses.
# "Passes in silence" used to need a genuinely LIVE session sweeper armed for this
# session/repo, or the unarmed-sweeper nag fired legitimately and broke the claim. Both the
# nag and the watcher it asked about were deleted in epic-16 wave-02, so silence is the
# gate's own unaided answer here.
OUT=$(mk_agent_payload "$SID_A" "$IREPO" | bash "$PARTY_DP" 2>&1); ST=$?
expect_eq "start gate: the producer's own session passes" "0" "$ST"
expect_eq "start gate: and passes in silence" "" "$OUT"
OUT=$(mk_agent_payload "${SID_A%?}0" "$IREPO" | bash "$PARTY_DP" 2>&1); ST=$?
expect_eq "start gate: a one-character-different session is refused (exact compare)" "2" "$ST"
OUT=$(mk_agent_payload "$SID_B" "$IREPO" | bash "$PARTY_DP" 2>&1); ST=$?
expect_eq "start gate: a foreign session is refused" "2" "$ST"

# Consumer 2 — the stop gate: the recorder writes the key, the gate compares it.
# Same literal value, produced by the same session, carried by the payload.
#
# The record attests to an EXAMINATION, so what the examination itself showed is
# asserted first. Without this line the three assertions beneath it are green on
# a fixture where the operator's own command printed "unresolved" and exited 1 —
# which is exactly what they were green on before (Step-6 critic, issue 1).
expect_contains "the observation the record attests to actually resolved the target" \
  "Resolved:      aworker-1111111111111111" "$( cd "$IREPO" && bash "$OBSERVE" worker 2>&1 )"
# Both sessions get a row so that the roster is not what differs between the two
# stops below: the ONLY thing that differs is the session value carried by the
# record and the payload, which is what this section is about.
roster_row "$IREPO" "$SID_A" "worker" "aworker-1111111111111111"
roster_row "$IREPO" "${SID_A%?}0" "worker" "aworker-1111111111111111"
run_pair "$IREPO" "$ITR" "$SID_A" worker
SGSTATE="$IREPO/.bionic/tmp/stop-check.state"
expect_eq "the recorder wrote an observation record" "yes" "$([ -f "$SGSTATE" ] && echo yes || echo no)"
expect_contains "the recorder keys the record with the same session value" \
  "session=$SID_A" "$(cat "$SGSTATE")"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "worker" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "stop gate: the same session's observation discharges the stop" "0" "$ST"

# Re-observe (the first record was consumed by the permitted stop, D-2), then
# prove a one-character-different session cannot spend it.
run_pair "$IREPO" "$ITR" "$SID_A" worker
OUT=$(mk_stop_payload "${SID_A%?}0" "$ITR" "$IREPO" "worker" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "stop gate: a one-character-different session is refused (exact compare)" "2" "$ST"
expect_contains "stop gate: and says the record was another session's" "different session" "$OUT"

# The two consumers key on the SAME payload field, which is the same value the
# producer took from the environment. If either side ever renamed its field,
# one of the three assertions above would fail — this one states the agreement
# itself, so the reason is legible when it does.
expect_contains "the stop gate reads the payload's session_id field" ".session_id" "$(cat "$PARTY_SG")"
expect_contains "the start gate reads the payload's session_id field" ".session_id" "$(cat "$PARTY_DP")"

# ============================================================
echo ""
echo "=== C — target resolution: the observation and BOTH stop-guard arms agree ==="
# ============================================================
#
# `scan_subagent_dirs` and the portable file facts are duplicated between
# hooks/stop-check.sh and hooks/stop-guard.sh, and both copies carried a comment
# claiming this battery held them together while no such battery existed
# (Step-6 duplication review D1). Byte-identity of the FUNCTION was never the
# claim worth testing anyway: the two callers fed it different directory sets,
# and that divergence is what let an observation print "ambiguous — decide
# nothing" while the recorder wrote a dischargeable record (correctness C1).
#
# So the question this battery asks is the CALLERS' question, over one fixture
# world, with the two halves reaching the directories by their own means: the
# observation by slugifying its cwd (it has no payload), the recorder and the
# gate from the payload's transcript path. Agreement means all three answer the
# same way about the same typed name — or, where they deliberately differ, that
# the difference is pinned and fail-closed.

# The metadata root is the CONFIGURED one. `$CLAUDE_CONFIG_DIR` and
# `$HOME/.claude` are different directories in this suite (header), so every
# case below asks its question with the only variable that separates the two
# callers actually varying. Stated as an assertion rather than a comment,
# because a future edit that collapses the roots would silently make this whole
# battery blind again.
expect_eq "the two metadata roots are genuinely different directories here" "different" \
  "$([ "$CLAUDE_CONFIG_DIR" != "$HOME/.claude" ] && echo different || echo same)"

RSLUG=$(printf '%s' "$SANDBOX/fx/resolver/repo" | sed 's/[^a-zA-Z0-9]/-/g')
RPROJ="$CLAUDE_CONFIG_DIR/projects/$RSLUG"
RREPO=$(new_repo "resolver")
write_plan "$RREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
mkdir -p "$RPROJ/$SID_A/subagents" "$RPROJ/$SID_B/subagents"
printf '{}\n' > "$RPROJ/$SID_A.jsonl"
printf '{}\n' > "$RPROJ/$SID_B.jsonl"
RTR="$RPROJ/$SID_A.jsonl"

plant() {  # <subagents-dir> <agent-id> <name>
  printf '{"name":"%s","agentType":"implementor","description":"fixture","model":"opus"}' "$3" \
    > "$1/agent-$2.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$1/agent-$2.jsonl"
}

# The three questions, each asked of the REAL party.
q_observation() {  # <typed> -> resolved|ambiguous|unresolved
  local out
  out=$( cd "$RREPO" && bash "$OBSERVE" "$1" 2>&1 )
  case "$out" in
    *"Resolved:      ambiguous"*)  echo ambiguous ;;
    *"Resolved:      unresolved"*) echo unresolved ;;
    *"Resolved:      a"*)          echo resolved ;;
    *) echo "other" ;;
  esac
}
q_recorder() {  # <typed> -> recorded|nothing
  rm -f "$RREPO/.bionic/tmp/stop-check.state"
  run_pair "$RREPO" "$RTR" "$SID_A" "$1"
  if grep -q '^v1|' "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null; then
    echo recorded
  else
    echo nothing
  fi
}
q_gate() {  # <typed> -> permitted|refused   (asked AFTER q_recorder, on its state)
  mk_stop_payload "$SID_A" "$RTR" "$RREPO" "$1" | bash "$PARTY_SG" >/dev/null 2>&1
  [ "$?" -eq 0 ] && echo permitted || echo refused
}

# --- case 1: unique in this session. All three say yes. ---
plant "$RPROJ/$SID_A/subagents" "asolo-1111111111111111" "solo"
# …and this session's roster records it. Since slice 4/9 the row is not what makes
# it ours — it is filed under this session's own directory — but keeping the row
# holds this case fixed on the RESOLUTION question the three parties are answering.
roster_row "$RREPO" "$SID_A" "solo" "asolo-1111111111111111"
expect_eq "C1 observation resolves a uniquely-named agent" "resolved" "$(q_observation solo)"
expect_eq "C1 recorder records the same agent" "recorded" "$(q_recorder solo)"
expect_eq "C1 gate discharges the stop on that record" "permitted" "$(q_gate solo)"

# --- case 2: the same name in two sessions of this project. The operator is
# shown a candidate list and NO evidence tier, so nothing may be dischargeable. ---
plant "$RPROJ/$SID_A/subagents" "adup-2222222222222222" "dup"
plant "$RPROJ/$SID_B/subagents" "adup-3333333333333333" "dup"
expect_eq "C2 observation reports the cross-session name as AMBIGUOUS" \
  "ambiguous" "$(q_observation dup)"
expect_eq "C2 recorder writes nothing for a name the operator could not resolve" \
  "nothing" "$(q_recorder dup)"
expect_eq "C2 gate refuses it" "refused" "$(q_gate dup)"

# --- case 3: resolves only in ANOTHER session of this project. A KNOWN,
# PINNED divergence, not a defect: the observation is project-wide because it has
# no payload to scope it, while a stop is session-scoped because a session can
# only stop its own tasks. The divergence runs fail-closed in every direction —
# the operator can look, nothing records, the stop refuses — and the refusal
# names the scope so the loop has a stated exit (readability R4). ---
plant "$RPROJ/$SID_B/subagents" "aforeign-4444444444444444" "foreign"
expect_eq "C3 observation can still SHOW another session's agent" \
  "resolved" "$(q_observation foreign)"
expect_eq "C3 recorder records nothing for it (only this session's agents)" \
  "nothing" "$(q_recorder foreign)"
expect_eq "C3 gate refuses it" "refused" "$(q_gate foreign)"
OUT=$(mk_stop_payload "$SID_A" "$RTR" "$RREPO" "foreign" | bash "$PARTY_SG" 2>&1)
expect_contains "C3 the refusal NAMES the scope, so the named fix is not an endless loop" \
  "scoped to agents this session launched" "$OUT"

# --- case 4: unknown to both. ---
expect_eq "C4 observation reports an unknown name unresolved" "unresolved" "$(q_observation nobody)"
expect_eq "C4 recorder writes nothing" "nothing" "$(q_recorder nobody)"
expect_eq "C4 gate refuses" "refused" "$(q_gate nobody)"

# --- case 5: the metadata root itself. The recorder and the gate reach the
# directories through the PAYLOAD's transcript path; the observation has no
# payload and must reach the same root by configuration. Where
# `$CLAUDE_CONFIG_DIR` names a root other than `$HOME/.claude` — which is the
# whole reason the variable exists — an observation rooted at `$HOME` looks in a
# directory the platform is not using: it shows the operator nothing, while the
# recorder records and the gate spends the record. That is the wall opening on a
# look that never happened, and it is the direction this case pins.
#
# Cases 1-4 above already run under the divergent roots and prove the AGREEING
# direction. This one plants a decoy under the default root and proves the
# observation does not answer from it. ---
HOMEPROJ="$HOME/.claude/projects/$RSLUG"
mkdir -p "$HOMEPROJ/$SID_A/subagents"
plant "$HOMEPROJ/$SID_A/subagents" "adecoy-6666666666666666" "decoy"
expect_eq "C5 observation ignores metadata under \$HOME/.claude when CLAUDE_CONFIG_DIR names another root" \
  "unresolved" "$(q_observation decoy)"
expect_eq "C5 recorder writes nothing for it" "nothing" "$(q_recorder decoy)"
expect_eq "C5 gate refuses it" "refused" "$(q_gate decoy)"

# --- case 6: the ARGUMENT GRAMMAR itself — RESIDUAL CLOSED at slice 4/4.
#
# Cases 1-5 ask both halves about one typed name; this one asks them about one
# COMMAND LINE, which is the thing they actually share. It used to be the hardest
# row in this file, because there were TWO readers of that line: the observation
# parsed its own `$@`, and a PreToolUse recorder re-parsed the same string with a
# grammar of its own (skip `-*` tokens, take the first non-flag). Nothing held
# them together, and a slice that widened one of them shipped: `--progress <path>
# <agent>` had the operator looking at <agent> while the record named <path> — an
# attestation about an agent nobody examined (Step-6 review F-1). Narrowing the
# producer then CONVERTED two ordinary typos into refused-observation-still-
# recorded, and that residual was pinned here rather than claimed away (critic
# finding A).
#
# There is now ONE reader. The recorder fires PostToolUse and copies the machine
# line hooks/stop-check.sh prints on its success path, so a command the operator
# watched fail printed no line and leaves nothing behind. The rows below are the
# same rows, with the residual expectations replaced by the closure: every
# refused form records NOTHING, and the documented form still records its target.
# ---
plant "$RPROJ/$SID_A/subagents" "aworker-7777777777777777" "worker"
GPROG="$RREPO/.bionic/tmp/w-grammar.progress"
mkdir -p "$RREPO/.bionic/tmp"; printf 'step 1\n' > "$GPROG"

g_observation() {  # <args…> -> the agent id the OBSERVATION resolved, or "refused"
  local out st
  out=$( cd "$RREPO" && bash "$OBSERVE" "$@" 2>&1 ); st=$?
  if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -qF 'Usage:'; then echo refused; return; fi
  printf '%s' "$out" | grep -E '^Resolved:' | grep -oE 'a[a-z0-9-]*-[0-9a-f]{16}' | head -1
}
g_recorder() {  # <args…> -> the agent id the RECORDER wrote, or "nothing"
  rm -f "$RREPO/.bionic/tmp/stop-check.state"
  run_pair "$RREPO" "$RTR" "$SID_A" "$@"
  local rec
  rec=$(grep '^v1|' "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null \
    | tr '|' '\n' | grep '^target=' | cut -d= -f2 | head -1)
  [ -n "$rec" ] && echo "$rec" || echo nothing
}

# The documented interface line: target first, flag trailing. Both halves must
# name the SAME agent — this is the row that would have caught F-1's sibling had
# it been written for the trailing form only.
expect_eq "C6 trailing form — the observation resolves the typed target" \
  "aworker-7777777777777777" "$(g_observation worker report.md --progress "$GPROG")"
expect_eq "C6 trailing form — the recorder records the SAME agent from the same line" \
  "aworker-7777777777777777" \
  "$(g_recorder worker report.md --progress "$GPROG")"

# The leading form, which is what diverged. Both halves refuse together — the
# producer with a usage error, the recorder because a usage error prints no
# machine line.
expect_eq "C6 leading form — the observation refuses it" \
  "refused" "$(g_observation --progress "$GPROG" worker)"
expect_eq "C6 leading form — the recorder writes no record for it" \
  "nothing" "$(g_recorder --progress "$GPROG" worker)"

# THE RESIDUAL, CLOSED (critic finding A, spec AC-3). This was the row that
# pinned a refused command still leaving a record because some token in it named
# a live agent: the flag VALUE `solo` was taken as the target while the operator
# saw a usage error. A PreToolUse reader could not do better — it fires before
# the command runs and never learns the outcome. The PostToolUse recorder does
# not read the command line at all, so there is no token for it to mistake.
expect_eq "C6 CLOSED — a refused command whose flag VALUE names a live agent records NOTHING" \
  "nothing" "$(g_recorder --progress solo worker)"
expect_eq "C6 CLOSED — and the observation gave that operator nothing to act on" \
  "refused" "$(g_observation --progress solo worker)"

# THE SAME CLASS IN THE TARGET-FIRST DIRECTION, which the row above does not
# reach: it pins only the flag-VALUE variant. Two ordinary typos — a mistyped
# flag and the `=`-joined spelling — leave the target as the first non-flag
# token, which is exactly what the old recorder took, so the operator saw a usage
# error and zero evidence while the record still named the target and carried the
# working log's mtime and size that the gate's D-1 comparison spends. Both now
# record nothing, for the one reason that covers every member of the class: the
# run printed no machine line.
expect_eq "C6 CLOSED — a mistyped flag AFTER the target: the observation refuses it" \
  "refused" "$(g_observation worker --progres "$GPROG")"
expect_eq "C6 CLOSED — and the recorder writes nothing for it" \
  "nothing" "$(g_recorder worker --progres "$GPROG")"
expect_eq "C6 CLOSED — the =-joined spelling: the observation refuses it" \
  "refused" "$(g_observation worker "--progress=$GPROG")"
expect_eq "C6 CLOSED — and the recorder writes nothing for that one either" \
  "nothing" "$(g_recorder worker "--progress=$GPROG")"

# The class, not the instances: the observation's exit status and the recorder's
# output are now ONE fact. Any command line at all — including ones nobody has
# thought of — agrees by construction, because a non-zero producer prints no
# machine line and the recorder has no other input.
for form in "worker --unknown-flag" "--progress" "ghost" "worker@" ; do
  # shellcheck disable=SC2086
  if [ "$(g_observation $form)" = "refused" ] || [ -z "$(g_observation $form)" ]; then
    # shellcheck disable=SC2086
    expect_eq "C6 CLOSED — no evidence tier, no record: '$form'" "nothing" "$(g_recorder $form)"
  else
    # shellcheck disable=SC2086
    expect_eq "C6 CLOSED — an evidence tier IS recorded: '$form'" \
      "aworker-7777777777777777" "$(g_recorder $form)"
  fi
done

# The derived FILE FACTS agree too: what the observation shows the reader as the
# working log's size is what the recorder writes down as the activity level. Two
# computations of one truth, previously untested together (D2).
plant "$RPROJ/$SID_A/subagents" "afacts-5555555555555555" "facts"
OBS_OUT=$( cd "$RREPO" && bash "$OBSERVE" facts 2>&1 )
OBS_SIZE=$(printf '%s' "$OBS_OUT" | grep -E '^  size:' | grep -oE '[0-9]+' | head -1)
q_recorder facts >/dev/null
REC_SIZE=$(grep -F 'target=afacts-5555555555555555' "$RREPO/.bionic/tmp/stop-check.state" \
  | tr '|' '\n' | grep '^size=' | cut -d= -f2)
expect_eq "the size the observation PRINTS is the size the recorder STORES" \
  "$OBS_SIZE" "$REC_SIZE"

# ============================================================
echo ""
echo "=== D — cross-script security regressions (AC-8, TDD §8) ==="
# ============================================================
#
# Per-script coverage already exists for: the credential value never reaching
# the attestation or the producer's own output (preflight-probe.test.sh S4), and
# command text never reaching the observation state file (stop-guard.test.sh
# §7). What no per-script suite can assert is the CROSS-SCRIPT property: after
# driving all four with a secret-bearing command, NOTHING anywhere under the
# sandbox — repo, state, temp, or $HOME (where the evidence gate's audit stream
# lives) — contains that text.

SECRET="sk-ant-LEAKCANARY-9f2b41"
SREPO=$(new_repo "secrets")
# The metadata lives under the CONFIGURED root, because the producer now has to
# resolve the target for real before anything can be recorded (slice 4/4).
SSLUG=$(printf '%s' "$SREPO" | sed 's/[^a-zA-Z0-9]/-/g')
SPROJ="$CLAUDE_CONFIG_DIR/projects/$SSLUG"
mkdir -p "$SPROJ/$SID_A/subagents"
STR="$SPROJ/$SID_A.jsonl"; printf '{}\n' > "$STR"
SSUB="$SPROJ/$SID_A/subagents"
printf '{"name":"worker"}' > "$SSUB/agent-aworker-2222222222222222.meta.json"
printf '{}\n' > "$SSUB/agent-aworker-2222222222222222.jsonl"
write_plan "$SREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"

# 1. the recorder, with the secret in the command line beside a real run
SOUT=$( cd "$SREPO" && bash "$OBSERVE" worker 2>/dev/null )
mk_bash_post "$SID_A" "$STR" "$SREPO" \
  "export TOKEN=$SECRET && bash ~/.claude/hooks/stop-check.sh worker" "$SOUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
# 2. the start gate, with the secret in the dispatch description
jq -n --arg s "$SID_A" --arg c "$SREPO" --arg d "dispatch carrying $SECRET" \
  '{session_id:$s, transcript_path:"/x.jsonl", cwd:$c, hook_event_name:"PreToolUse",
    tool_name:"Agent", tool_input:{description:$d, subagent_type:"implementor"}}' \
  | bash "$PARTY_DP" >/dev/null 2>&1
# 3. the stop gate, with the secret as the typed target
mk_stop_payload "$SID_A" "$STR" "$SREPO" "$SECRET" | bash "$PARTY_SG" >/dev/null 2>&1
# 4. the producer, with the secret as the live credential
( cd "$SREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" ANTHROPIC_API_KEY="$SECRET" \
    HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
    bash "$PROBE" >/dev/null 2>&1 )
# 5. the observation, with the secret as the target it fails to resolve
( cd "$SREPO" && bash "$OBSERVE" "$SECRET" >/dev/null 2>&1 )

LEAKS=$(grep -rlF "$SECRET" "$SREPO" "$SANDBOX/home" 2>/dev/null | grep -c . | tr -d ' ')
expect_eq "no file under the repo or \$HOME holds the secret after all five runs" "0" "$LEAKS"

# The recorder DOES record the typed target — that is its contract — so the
# check above must not be passing merely because nothing was written at all.
expect_contains "…and the state file the sweep covered is genuinely populated" \
  "target=" "$(cat "$SREPO/.bionic/tmp/stop-check.state" 2>/dev/null)"

# Temp-name unpredictability, all four scripts (AC-8). Static pins first: the
# A2 defect was a literal `"${X}.tmp.$$"`.
for s in "$PROBE" "$OBSERVE" "$PARTY_DP" "$PARTY_SG" "$PARTY_ER"; do
  b=$(basename "$s")
  expect_absent "$b: no PID-derived temp name" '.tmp.$$' "$(cat "$s")"
  if grep -q 'mktemp' "$s"; then
    if grep -qE 'mktemp[^|&;]*XXXXXX' "$s"; then ok "$b: every mktemp carries an X-template"
    else no "$b: every mktemp carries an X-template"; fi
  else
    ok "$b: creates no temp files at all (nothing to make predictable)"
  fi
done

# Behavioural, not merely static: two recorder runs must produce two unrelated
# temp names. The instrumentation is applied to a COPY (§9's technique) so the
# shipped script carries no fault-injection seam; the original is re-checksummed.
ER_SUM_BEFORE=$(shasum "$PARTY_ER")
SGI="$MUTDIR/execution-recorder-showtmp.sh"
awk '{ print }
     /^  tmp=\$\(mktemp "\$STATE_DIR\/\.stop-check\.XXXXXX" 2>\/dev\/null\)/ {
       print "  printf \"TMPNAME=%s\\n\" \"$tmp\" >&2" }' "$PARTY_ER" > "$SGI"
if cmp -s "$PARTY_ER" "$SGI"; then
  no "the recorder's mktemp call can be instrumented" "awk matched nothing — the mktemp step moved"
else
  ok "the recorder's mktemp call can be instrumented"
  N1=$(mk_bash_post "$SID_A" "$STR" "$SREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$SOUT" \
       | bash "$SGI" 2>&1 >/dev/null | sed -n 's/^TMPNAME=//p' | head -1)
  N2=$(mk_bash_post "$SID_A" "$STR" "$SREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$SOUT" \
       | bash "$SGI" 2>&1 >/dev/null | sed -n 's/^TMPNAME=//p' | head -1)
  if [ -n "$N1" ] && [ -n "$N2" ] && [ "$N1" != "$N2" ]; then
    ok "two recorder runs produce two different temp names ($(basename "$N1") vs $(basename "$N2"))"
  else
    no "two recorder runs produce two different temp names" "got '$N1' and '$N2'"
  fi
  expect_absent "the temp name is not derived from the PID" "$$" "$(basename "${N1:-x}")"
fi
expect_eq "execution-recorder.sh is byte-identical after the instrumented copy ran" \
  "$ER_SUM_BEFORE" "$(shasum "$PARTY_ER")"

# The components' repo footprint — the strongest form of "no artefact holds the
# command text". Snapshot the whole sandbox around a run.
#
# RESCOPED at epic-16 wave-02, not relaxed. The start gate stopped being read-only
# when R5 ("the environment probe auto-runs when needed") folded the attestation
# into the combined preflight: with no attestation on disk the gate now runs
# hooks/preflight-probe.sh inline, which creates its state directory and writes the
# session-keyed attestation, and the gate then journals the accepted dispatch to the
# session roster (wave-01 roster row, R8's "a refused dispatch leaves no row" read
# in the positive direction). Those three paths are the whole ratified set.
#
# The direction the pin now runs: an EXACT delta, never a blanket exclusion of
# .bionic/tmp. Three named paths may appear and a FOURTH entry of ANY kind — file
# or directory, inside .bionic/tmp or anywhere else — still goes RED. The security
# property this block exists for ("gates do not scribble in repos") therefore
# survives at full strength for everything unsanctioned; what changed is that the
# sanctioned set is enumerated instead of empty.
#
# The credential is PINNED rather than inherited. The probe's credential sources are
# $ANTHROPIC_API_KEY first and the machine's LOGIN KEYCHAIN third, so an unpinned
# drive lands on the refused path or the accepted one depending on whose machine
# runs the suite — and only the accepted path writes any file at all. Pinning it
# present is both hermetic and the stronger drive: it exercises the branch that
# actually creates the artefacts this assertion is here to bound. The value is a
# syntactic placeholder; the probe tests PRESENCE, never validity.
QREPO=$(new_repo "quiet")
write_plan "$QREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
before=$(find "$QREPO" | sort)
expected_after=$(printf '%s\n%s\n%s\n%s\n' "$before" \
  "$QREPO/.bionic/tmp" \
  "$QREPO/.bionic/tmp/preflight-$SID_A.state" \
  "$QREPO/.bionic/tmp/roster-$SID_A.state" | sort)
mk_agent_payload "$SID_A" "$QREPO" \
  | env ANTHROPIC_API_KEY="pinned-placeholder-not-a-credential" bash "$PARTY_DP" >/dev/null 2>&1
after_start=$(find "$QREPO" | sort)
expect_eq "the start gate writes ONLY the attestation, the roster row and their state dir" \
  "$expected_after" "$after_start"
# The observation stays read-only ABSOLUTELY — zero footprint, no sanctioned set at
# all. Compared against the POST-start listing rather than the pre-start one, so it
# answers for its own writes instead of inheriting the start gate's.
( cd "$QREPO" && bash "$OBSERVE" nobody >/dev/null 2>&1 )
expect_eq "the observation creates no file anywhere in the repo" "$after_start" "$(find "$QREPO" | sort)"

# ============================================================
echo ""
echo "=== E — classification + contract-source ride the machine line into the recorded observation (slice 4/5) ==="
# ============================================================
#
# hooks/stop-check.sh (producer) computes classification/deliverable_source/
# progress_source and prints them on its machine line; hooks/execution-recorder.sh
# (consumer) is supposed to copy them into the observation record verbatim,
# unparsed — the same "one computation, two renderings" property §D2 above pins
# for the file-facts fields. This section drives the REAL producer's REAL output
# into the REAL recorder over the §C fixture world, so a divergence between the
# two parsers (the F-1 shape this whole file exists to catch) shows up here
# rather than in two suites that never compare notes.
#
# Reuses the §C fixture world (RREPO/RPROJ/RTR/SID_A, the "worker" and "solo"
# agents already planted there) rather than building a new one, because the
# claim under test is agreement over ONE resolution, not a new resolver case.

roster_row "$RREPO" "$SID_A" "worker" "aworker-7777777777777777"

# --- a target THIS session's roster records: OURS, end to end ---
E_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" worker 2>&1 )
expect_contains "the observation classifies the roster-recorded target OURS" \
  "Classification: OURS" "$E_OUT"
E_MLINE=$(printf '%s\n' "$E_OUT" | grep '^stop-check-observation/')
expect_contains "the machine line carries classification=ours" "classification=ours" "$E_MLINE"

mk_bash_post "$SID_A" "$RTR" "$RREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$E_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
E_STATE=$(cat "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null)
expect_contains "the recorded observation agrees: classification=ours" \
  "classification=ours" "$E_STATE"
expect_contains "the recorded observation carries deliverable_source=none (no CLI arg, no roster deliverable)" \
  "deliverable_source=none" "$E_STATE"
expect_contains "the recorded observation carries progress_source=none" "progress_source=none" "$E_STATE"

# --- an UNROSTERED target under this session's OWN directory: OURS, because the
# metadata's own filing is what ownership reads (slice 4/9). Before that fix this
# classified foreign, of an agent this session had launched — the live defect, and
# the standing state for everything dispatched before the roster hook shipped. ---
plant "$RPROJ/$SID_A/subagents" "aloner-9999999999999999" "loner"
E3_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" loner 2>&1 )
E3_MLINE=$(printf '%s\n' "$E3_OUT" | grep '^stop-check-observation/')
expect_contains "an unrostered target under this session's own directory classifies OURS" \
  "|classification=ours|" "$E3_MLINE"

mk_bash_post "$SID_A" "$RTR" "$RREPO" "bash ~/.claude/hooks/stop-check.sh loner" "$E3_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
E3_STATE=$(cat "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null)
expect_contains "the recorder forwards that classification into the record" \
  "|classification=ours|" "$E3_STATE"

# --- and the not-ours direction, on the shape that really produced it: a target
# filed under ANOTHER session's directory, carrying a name this session's roster
# also carries on an UNCONFIRMED row. The row must grant nothing, and whatever the
# producer decides must reach the record verbatim — this suite's whole subject.
# Recording it needs a payload whose transcript names that other session, which is
# the only way the recorder resolves outside this session's own directory. ---
plant "$RPROJ/$SID_B/subagents" "acorpse-aaaaaaaaaaaaaaaa" "corpse"
roster_row "$RREPO" "$SID_A" "corpse" "" "" intended
E5_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" corpse 2>&1 )
E5_MLINE=$(printf '%s\n' "$E5_OUT" | grep '^stop-check-observation/')
expect_contains "an unconfirmed row's NAME does not make another session's agent ours" \
  "|classification=foreign|" "$E5_MLINE"
expect_absent "…and the retired liveness label is gone from the vocabulary" \
  "foreign-live" "$E5_MLINE"
mk_bash_post "$SID_A" "$RPROJ/$SID_B.jsonl" "$RREPO" \
  "bash ~/.claude/hooks/stop-check.sh corpse" "$E5_OUT" | bash "$PARTY_ER" >/dev/null 2>&1
E5_STATE=$(cat "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null)
expect_contains "the recorder forwards a non-ours classification into the record too" \
  "|classification=foreign|" "$E5_STATE"

# --- with no own session id at all, the producer says UNKNOWN and the recorder
# copies that verbatim rather than defaulting to any other label ---
E4_OUT=$( cd "$RREPO" && env -u CLAUDE_CODE_SESSION_ID bash "$OBSERVE" worker 2>&1 )
E4_MLINE=$(printf '%s\n' "$E4_OUT" | grep '^stop-check-observation/')
expect_contains "with no own session id the machine line carries classification=unknown" \
  "classification=unknown" "$E4_MLINE"
mk_bash_post "$SID_A" "$RTR" "$RREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$E4_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
E4_STATE=$(cat "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null)
expect_contains "the recorded observation agrees: classification=unknown" \
  "classification=unknown" "$E4_STATE"

# ============================================================
echo ""
echo "=== F — the roster row and the observer/progress fields: writer, producer and GATE agree (slice 4/6) ==="
# ============================================================
#
# Slice 4/6 turned the stop gate into a reader of four things it had never read:
# the session roster's `name=`/`agent_id=` (the foreign-stop rule), and the
# record's `observer=`, `progress=`/`progress_mtime=`/`progress_state=` (the
# same-actor and progress-staleness checks). Every one of them is written by one
# script and read by another, which is this suite's whole subject — a field whose
# producer and consumer drift apart fails silently and in the OPEN direction (the
# gate simply stops finding what it is looking for).
#
# The roster row here is the one hooks/dispatch-preflight.sh REALLY WROTE in
# section B, from the real brief in mk_agent_payload — not a fixture. So the
# chain driven below is writer → producer → recorder → gate, end to end, over one
# row.

ROSTER_F="$IREPO/.bionic/tmp/roster-$SID_A.state"
expect_contains "the start gate really journalled the dispatch (section B's own row)" \
  "name=w99-impl" "$(cat "$ROSTER_F" 2>/dev/null)"
expect_contains "…carrying the progress path lifted from the brief" \
  "progress=.bionic/tmp/w99.progress" "$(cat "$ROSTER_F" 2>/dev/null)"

# The agent that row describes, now spawned. Its id is what a confirmed row would
# carry; the row itself is still `intended`, which is the mid-dispatch state the
# NAME fallback exists for.
plant "$ISUB" "aw99impl-8888888888888888" "w99-impl"
printf 'stage 1\n' > "$IREPO/.bionic/tmp/w99.progress"

F_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
expect_contains "the producer reads that row and calls the target OURS" \
  "Classification: OURS" "$F_OUT"
F_MLINE=$(printf '%s\n' "$F_OUT" | grep '^stop-check-observation/')
expect_contains "…and takes the contracted progress path from it" \
  "progress=.bionic/tmp/w99.progress" "$F_MLINE"
expect_contains "…recording where the contract came from" "progress_source=roster" "$F_MLINE"
expect_contains "…and the state it found the artifact in" "progress_state=present" "$F_MLINE"

mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$F_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
F_STATE=$(cat "$IREPO/.bionic/tmp/stop-check.state" 2>/dev/null)
expect_contains "the recorder copies the progress path into the record verbatim" \
  "progress=.bionic/tmp/w99.progress" "$F_STATE"
expect_contains "…and the progress state beside it" "progress_state=present" "$F_STATE"
expect_contains "…and the observer, which only it can see" "observer=orchestrator" "$F_STATE"

# The gate now reads that record. Same row, same path, same answer: nothing has
# moved, so the stop stands.
ST=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" >/dev/null 2>&1; echo $?)
expect_eq "the gate agrees the target is OURS and spends the record" "0" "$ST"

# …and a write to THAT path — the one the writer named, the producer resolved and
# the recorder stored — is what the gate calls stale. A disagreement anywhere in
# that chain shows up here as a stop that quietly stays permitted.
F2_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$F2_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
sleep 1
printf 'stage 2\n' >> "$IREPO/.bionic/tmp/w99.progress"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "a write to the roster-contracted progress path stales the look" "2" "$ST"
expect_contains "…and the gate names the same path the writer wrote" \
  ".bionic/tmp/w99.progress" "$OUT"

# THE SAME CHAIN, WITH THE ROSTER LONG (Step-6 critic F-1). The shipped
# performance remediation capped the roster at 200 rows and evicted by RECENCY,
# which knows nothing about whether the evicted row belongs to an agent that is
# still running. A live agent's row is the only copy of its contract, and the
# refusal just proven above is sourced from it — so past the cap the wall did not
# weaken, it disappeared: `record/w3-critic-repro-cap.sh` measured the identical
# sequence as exit 2 under the cap and exit 0 over it, with the operator shown
# `progress=(none recorded)`, indistinguishable from a brief that declared none.
#
# This is the row that failed. It belongs in THIS suite rather than the
# recorder's own, because the property is cross-script: the file the recorder
# writes is the file the gate reads, and the recorder alone cannot see that
# dropping a row disarms another program. `hooks/execution-recorder.test.sh`
# asserted only that the row THIS event confirmed survived the fold, which is why
# 110/110 was green over the defect.
F4_ROSTER="$IREPO/.bionic/tmp/roster-$SID_A.state"
F4_BEFORE=$(grep -c '^roster-state/v1|' "$F4_ROSTER" 2>/dev/null || echo 0)
{
  _i=0
  while [ "$_i" -lt 260 ]; do
    printf 'roster-state/v1|status=confirmed|session=%s|name=old-%s|agent_id=aold-%s|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_OLD%s\n' \
      "$SID_A" "$_i" "$_i" "$_i"
    _i=$((_i + 1))
  done
} >> "$F4_ROSTER"

# A SECOND dispatch, journalled by the REAL start gate, whose completion is the
# event that used to rewrite the file. The live agent's row is the OLDEST in it,
# which is exactly the position eviction-by-recency takes first.
mk_agent_payload "$SID_A" "$IREPO" \
  | jq '.tool_input.name = "w99-other" | .tool_use_id = "toolu_OTHERDISPATCH"' \
  | bash "$PARTY_DP" >/dev/null 2>&1
mk_agent_post "$SID_A" "$ITR" "$IREPO" "toolu_OTHERDISPATCH" "w99-other" \
  | bash "$PARTY_ER" >/dev/null 2>&1
expect_contains "the other dispatch's completion is journalled" \
  "agent_id=a26bd30bf8616411b" "$(grep 'status=confirmed|.*name=w99-other|' "$F4_ROSTER" 2>/dev/null)"
expect_eq "no row is evicted to make room for it (append-only, unbounded)" \
  "$((F4_BEFORE + 262))" "$(grep -c '^roster-state/v1|' "$F4_ROSTER" 2>/dev/null || echo 0)"
# Both of these read the ROW, never the file. Scoping is load-bearing twice over:
# the second dispatch above carries the same brief, so a file-wide grep for the
# contract would stay green with the live row gone — and `expect_contains` cannot
# be trusted on a haystack this size at all. It is `printf | grep -qF` under
# `pipefail`, so a match near the TOP of a 68 KB haystack makes grep exit before
# printf finishes, printf takes SIGPIPE, and the pipeline returns 141: a FALSE
# FAIL on a string that is present. Verified in isolation — same haystack, early
# match 141, late match 0, and 0 with pipefail off. It fails safe (red, not
# green) and it is not this slice's to fix in six suites at once, but it is why
# nothing here hands a whole roster to an assertion.
F4_LIVE_ROW=$(grep 'name=w99-impl|' "$F4_ROSTER" 2>/dev/null)
expect_contains "the LIVE agent's row survives a long session" \
  "name=w99-impl" "$F4_LIVE_ROW"
expect_contains "…carrying the contract state that is its only copy" \
  "progress=.bionic/tmp/w99.progress" "$F4_LIVE_ROW"

# …and the wall that hangs off that row still fires. Same three steps as the
# refusal above — observe, the agent writes, stop — with nothing different but
# the length of the file.
F4_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
expect_contains "the producer still reads the contract off the long roster" \
  "progress_source=roster" "$(printf '%s\n' "$F4_OUT" | grep '^stop-check-observation/')"
mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$F4_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
sleep 1
printf 'stage 3\n' >> "$IREPO/.bionic/tmp/w99.progress"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "the D-6 staleness wall still refuses past the old cap (critic F-1)" "2" "$ST"
expect_contains "…still naming the contracted path rather than (none recorded)" \
  ".bionic/tmp/w99.progress" "$OUT"

# THE OBSERVER FIELD, both ends. The recorder learns who looked from its own
# payload's top-level `agent_id` (absent = the orchestrator); the gate learns who
# is stopping from ITS payload's identical field. One key, two payloads.
F3_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$F3_OUT" \
  | jq '. + {agent_id:"asubagent-2020202020202020", agent_type:"general-purpose"}' \
  | bash "$PARTY_ER" >/dev/null 2>&1
expect_contains "a subagent-invoked observation records that subagent as observer" \
  "observer=asubagent-2020202020202020" "$(cat "$IREPO/.bionic/tmp/stop-check.state" 2>/dev/null)"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "the orchestrator cannot spend a subagent's look" "2" "$ST"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" \
      | jq '. + {agent_id:"asubagent-2020202020202020", agent_type:"general-purpose"}' \
      | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "the subagent that looked can" "0" "$ST"

# The field NAMES themselves, stated as the agreement they are — so a rename
# breaks this suite with a legible reason rather than turning a wall inert.
expect_contains "the recorder writes the observer key" "observer=" "$(cat "$PARTY_ER")"
expect_contains "the stop gate reads the observer key" "observer" "$(cat "$PARTY_SG")"
expect_contains "the recorder and the gate read the same actor field" ".agent_id" "$(cat "$PARTY_ER")"
expect_contains "…on both sides" ".agent_id" "$(cat "$PARTY_SG")"
expect_contains "the producer prints the progress state key" "progress_state=" "$(cat "$OBSERVE")"
expect_contains "the stop gate reads the progress state key" \
  'record_field "$RECORD" progress_state' "$(cat "$PARTY_SG")"
expect_contains "the roster writer spells the row's name key" "|name=" "$(cat "$PARTY_DP")"
expect_contains "the stop gate reads the roster row by that key" \
  'record_field "$rline" name' "$(cat "$PARTY_SG")"
expect_contains "the roster writer spells the row's id key" "|agent_id=" "$(cat "$PARTY_DP")"
expect_contains "the stop gate reads the roster row's id key too" \
  'record_field "$rline" agent_id' "$(cat "$PARTY_SG")"
expect_contains "the gate reads the per-session roster filename the writer writes" \
  "roster-" "$(cat "$PARTY_SG")"

# ============================================================
echo ""
echo "=== G — the roster FILENAME is one pattern with five sites (6-axis D-1) ==="
# ============================================================
#
# `roster-<session-id>.state` under `.bionic/tmp/` is constructed independently in
# five places: hooks/dispatch-preflight.sh (the writer, via ROSTER_PREFIX/SUFFIX),
# hooks/preflight-probe.sh (a declared reader copy of the same two constants), and
# BARE LITERALS in hooks/execution-recorder.sh, hooks/stop-guard.sh and
# hooks/stop-check.sh. The spec's ownership table named no owner for it, and the
# only cross-surface guard was a substring grep for `roster-` in the gate's source
# — which a change to the SUFFIX, or to the directory, passes untouched.
#
# So the pattern is driven, not grepped: the writer writes at the canonical path,
# each reader is shown finding it there, and the same file at a MUTATED name is
# found by NONE of them. The mutation is what makes this an agreement test rather
# than a restatement — a suffix change goes red here in four places at once.
G_ROSTER="$IREPO/.bionic/tmp/roster-$SID_A.state"
G_MUTANT="$IREPO/.bionic/tmp/roster-$SID_A.txt"
expect_eq "the writer's roster is at .bionic/tmp/roster-<session>.state" "yes" \
  "$([ -f "$G_ROSTER" ] && echo yes || echo no)"

# READER 1 — the recorder's completion arm. At the canonical name a dispatch's
# `intended` row reaches `confirmed`; at any other name there is no row to
# complete and none is invented.
g_confirm() {  # -> the confirmed row, if any
  jq -n --arg s "$SID_A" --arg t "$ITR" --arg c "$IREPO" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PostToolUse",
      tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                  name:"w99-impl", run_in_background:true},
      tool_response:{isAsync:true, status:"async_launched", agentId:"ag99confirm-5555555555",
                     description:"a dispatch"},
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}' \
    | bash "$PARTY_ER" >/dev/null 2>&1
  grep 'agent_id=ag99confirm-5555555555' "$G_ROSTER" 2>/dev/null
}
mv "$G_ROSTER" "$G_MUTANT"
g_confirm >/dev/null 2>&1
expect_eq "a roster at any other filename is not completed by the recorder" "no" \
  "$([ -f "$G_ROSTER" ] && echo yes || echo no)"
expect_absent "…and the mutant file is not written through either" \
  "ag99confirm-5555555555" "$(cat "$G_MUTANT" 2>/dev/null)"
mv "$G_MUTANT" "$G_ROSTER"
expect_contains "the recorder completes the row at the canonical filename" \
  "status=confirmed" "$(g_confirm)"

# READER 2 — the observation. Its contract source is the roster; at any other
# filename the same look reports no contract at all.
g_progress_source() {
  ( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 ) \
    | grep '^stop-check-observation/' | tr '|' '\n' | grep '^progress_source=' | cut -d= -f2-
}
expect_eq "the observation takes its contract from the canonical roster" \
  "roster" "$(g_progress_source)"
mv "$G_ROSTER" "$G_MUTANT"
expect_eq "…and finds no contract when the roster is named anything else" \
  "none" "$(g_progress_source)"
mv "$G_MUTANT" "$G_ROSTER"

# READER 3 — the stop gate. An observation that never opened the contracted
# progress channel is refused BECAUSE the roster names one (D-6); with the roster
# at any other name the gate cannot know a channel exists, and the stop stands.
g_stop_unnamed() {  # -> the gate's exit status for a channel-blind observation
  local out
  out=$( cd "$IREPO" && env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$OBSERVE" w99-impl 2>&1 )
  mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$out" \
    | bash "$PARTY_ER" >/dev/null 2>&1
  mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" >/dev/null 2>&1
  echo $?
}
expect_eq "the stop gate reads the contracted channel out of the canonical roster" \
  "2" "$(g_stop_unnamed)"
mv "$G_ROSTER" "$G_MUTANT"
expect_eq "…and knows of no channel when the roster is named anything else" \
  "0" "$(g_stop_unnamed)"
mv "$G_MUTANT" "$G_ROSTER"

# READER 4 — the probe's roster coverage, which scans OTHER live sessions' roster
# files by the same pattern.
printf '{}\n' > "$IPROJ/$SID_B.jsonl"
G_ROSTER_B="$IREPO/.bionic/tmp/roster-$SID_B.state"
cp "$G_ROSTER" "$G_ROSTER_B"
g_probe_roster() {
  ( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" ANTHROPIC_API_KEY="sk-fixture-not-a-real-key" \
      HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$PROBE" 2>&1 ) \
    | grep -F "another live session on this project: $SID_B"
}
expect_contains "the probe finds another session's roster at the canonical filename" \
  "roster: present" "$(g_probe_roster)"
mv "$G_ROSTER_B" "$IREPO/.bionic/tmp/roster-$SID_B.txt"
expect_contains "…and reports absent for the same file under any other name" \
  "roster: absent" "$(g_probe_roster)"
rm -f "$IREPO/.bionic/tmp/roster-$SID_B.txt" "$IPROJ/$SID_B.jsonl"

# Both halves of the name, spelled by all five sites — so a rename of either half
# fails with a legible reason rather than silently halving the fleet's view.
for _party in "$PARTY_DP" "$PROBE" "$PARTY_ER" "$PARTY_SG" "$OBSERVE"; do
  _src=$(cat "$_party")
  expect_contains "$(basename "$_party") spells the roster filename prefix" "roster-" "$_src"
  expect_contains "$(basename "$_party") spells the roster filename suffix" ".state" "$_src"
  expect_contains "$(basename "$_party") resolves it under .bionic/tmp" ".bionic/tmp" "$_src"
done

# ============================================================
echo ""
echo "=== H — the LIVENESS fields: writer lifts them, the observation displays them (6-axis A-1) ==="
# ============================================================
#
# The axis-3 FAIL: hooks/stop-check.sh read `claims=` off the roster row and NO
# writer emitted it, while slice 4/7 shipped procedure prose instructing authors
# to declare both a `cadence` and a subprocess claim. A reader with no producer is
# dead substrate, and the only test exercising it hand-wrote a row shape the
# writer could not produce. Here the row is the one the real start gate wrote from
# a real brief, and the real observation is run over it.

H_BRIEF='Canonical-sdlc Step 4, slice 4/13 of epic-99 wave-01; build · audited · wave.
Expected artifact: .bionic/docs/record/w99-live.txt
Expected duration: ~45 minutes. Progress: .bionic/tmp/w99-live.progress, cadence ~7m.
Subprocess claim: `w99-suite-marker` → .bionic/tmp/w99-live.log
Exit condition: the artifact exists.'
plant "$ISUB" "aw99live-9999999999999999" "w99-live"
jq -n --arg s "$SID_A" --arg c "$IREPO" --arg p "$H_BRIEF" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    permission_mode:"bypassPermissions", hook_event_name:"PreToolUse", tool_name:"Agent",
    tool_input:{description:"a liveness dispatch", subagent_type:"implementor",
                name:"w99-live", prompt:$p},
    tool_use_id:"toolu_01LIVENESS"}' \
  | bash "$PARTY_DP" >/dev/null 2>&1
H_ROW=$(grep 'name=w99-live' "$G_ROSTER" 2>/dev/null | tail -1)
expect_contains "the writer lifted the subprocess claim's pattern into the row" \
  "claims=w99-suite-marker" "$H_ROW"
expect_contains "the writer lifted the cadence declared beside the progress path" \
  "cadence=~7m." "$H_ROW"

H_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-live 2>&1 )
expect_contains "the observation reads that claim back off the row it was written to" \
  "w99-suite-marker" "$H_OUT"
expect_contains "…as the P2 claimed-process section, sourced from the roster" \
  "source=roster" "$H_OUT"
expect_contains "…and displays the declared cadence beside the progress age" \
  "cadence:" "$H_OUT"
expect_contains "…with the value the brief declared" "~7m." "$H_OUT"
# The field NAMES, both ends — a rename fails here rather than turning the
# display silently blank, which is how this defect shipped in the first place.
expect_contains "the writer spells the claims key" "|claims=" "$(cat "$PARTY_DP")"
expect_contains "the observation reads that same key" 'line_field "$ROSTER_ROW" claims' "$(cat "$OBSERVE")"
expect_contains "the writer spells the cadence key" "|cadence=" "$(cat "$PARTY_DP")"
expect_contains "the observation reads that same key" 'line_field "$ROSTER_ROW" cadence' "$(cat "$OBSERVE")"

# ============================================================
echo ""
echo "=== I — DONE-DETECTION, and the primitives the sweeper says it copied (6-axis D-2, R-1) ==="
# ============================================================
#
# hooks/session-sweeper.sh's own header declares four functions "DELIBERATELY DUPLICATED
# from hooks/stop-check.sh, byte for byte… held together by the cross-gate agreement
# suite". Until this section existed that last clause was false: nothing here compared a
# single copy, so the comment named a guardrail the next reader would trust and the copies
# could drift silently (6-axis R-1). Below it is true.
#
# The heavier half is D-2. "Is this roster row's deliverable delivered?" has TWO owners and
# they answered differently on the same input. Both answers are asked here of the REAL
# scripts on ONE set of fixtures, and compared to each other rather than only to a literal —
# which is what goes red on the next divergence, whichever side moves.
#
# THE SWEEPER SIDE MOVED IN epic-16 wave-02, and this section moved with it. The sweeper
# used to answer through its watch loop: a row whose declared deliverables were all present
# was SATISFIED, dropped from watching, never woken on, and the loose `[ -s <dir> ]` reading
# behind that was the original defect (true for an EMPTY directory on both BSD and GNU, so a
# freshly-created directory read as landed work). The loop and its satisfied-check are
# deleted. The sweeper is still an owner of this question — through `verdict`, which is now
# its ONLY delivered-predicate — so the pairing is preserved and re-asked against that verb
# rather than dropped with the loop.

# --- I.1 the copied primitives ---
# BODIES are compared, not whole definitions: each file explains its copy in its own terms,
# so the signature comments legitimately differ and only the executable text must not.
fn_body() {  # <file> <function name> -> the function's body, signature and its comment stripped
  awk -v n="$2" '
    !f && index($0, n "()") == 1 {
      f = 1; line = $0
      sub(/^[^{]*\{/, "", line)
      sub(/^[[:space:]]*#.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") print line
      if (line ~ /\}$/) exit
      next
    }
    f { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; if ($0 == "}") exit }
  ' "$1"
}

expect_eq "the extractor returns a body at all (this section is not vacuous)" "yes" \
  "$([ -n "$(fn_body "$SWEEPER" line_field)" ] && echo yes || echo no)"
for _fn in file_mtime line_field claims_live; do
  expect_eq "the sweeper's ${_fn}() is the stop gate's, body for body" \
    "$(fn_body "$OBSERVE" "$_fn")" "$(fn_body "$SWEEPER" "$_fn")"
done
# Same body, different name: the sweeper normalizes its findings exactly as the stop gate
# normalizes its machine line, and says so in its comment.
expect_eq "the sweeper's clean() is the stop gate's mline_value(), body for body" \
  "$(fn_body "$OBSERVE" mline_value)" "$(fn_body "$SWEEPER" clean)"

# --- I.2 done-detection: one concept, two implementations, one answer ---

DREPO=$(new_repo "done-detection")
DSLUG=$(printf '%s' "$DREPO" | sed 's/[^a-zA-Z0-9]/-/g')
DPROJ="$CLAUDE_CONFIG_DIR/projects/$DSLUG"
mkdir -p "$DPROJ/$SID_A/subagents"
printf '{}\n' > "$DPROJ/$SID_A.jsonl"
plant "$DPROJ/$SID_A/subagents" "adeliv-2222222222222222" "deliv"

DFX="$DREPO/deliv"
mkdir -p "$DFX/empty-dir" "$DFX/full-dir"
: > "$DFX/empty-file.md"
echo "the report"   > "$DFX/full-file.md"
echo "the report"   > "$DFX/full-dir/one.md"
echo "the report"   > "$DREPO/relative-target.md"
# An hour back, so every fixture written above is NEWER than the launch and the landing
# predicate's staleness conjunct is satisfied for all of them. Staleness is a NAMED
# divergence between these two owners (the stop gate never dates the artifact at all), and
# it is pinned separately below rather than smuggled into every row here.
D_LAUNCHED=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)

DROSTER="$DREPO/.bionic/tmp/roster-$SID_A.state"
mkdir -p "$DREPO/.bionic/tmp"
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$DROSTER"
d_row() {  # <name> <deliverable value>
  printf 'roster-state/v1|status=confirmed|session=%s|name=%s|agent_id=adeliv-2222222222222222|launched_at=%s|subagent_type=implementor|model=opus|deliverable=%s|source=declared|duration=1 minute|progress=|claims=|cadence=|absent=|waiver=|tool_use_id=toolu_01%s\n' \
    "$SID_A" "$1" "$D_LAUNCHED" "$2" "$1" >> "$DROSTER"
}

# The stop gate's answer, read off the evidence it prints for a human rather than off a
# reimplementation of its branches here.
sc_answer() {  # <path as typed> -> delivered|not-delivered
  local out
  out=$( cd "$DREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" deliv "$1" 2>&1 )
  case "$out" in
    *"${1} — PRESENT as a directory, 0 file(s)"*) echo not-delivered ;;
    *"${1} — PRESENT as a directory,"*)           echo delivered ;;
    *"${1} — PRESENT but EMPTY"*)                 echo not-delivered ;;
    *"${1} — PRESENT,"*)                          echo delivered ;;
    *"${1} — ABSENT"*)                            echo not-delivered ;;
    *) echo "other" ;;
  esac
}

# The sweeper's answer, read off the state its ONE surviving predicate computes. MET is
# delivered; anything else is not. The row carries no claims and no progress, so STILL-LIVE
# cannot mask a failure to deliver — the state is the predicate's answer and nothing else.
sw_answer() {  # <row name> -> delivered|not-delivered
  local st
  st=$( cd "$DREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict "$1" 2>/dev/null \
        | grep -F 'landing-verdict/v1|' | grep -F "|name=$1|" | head -1 \
        | tr '|' '\n' | grep '^state=' | head -1 | cut -d= -f2- )
  [ "$st" = "MET" ] && echo delivered || echo not-delivered
}

agree_on() {  # <label> <row name> <path as typed> <the right answer>
  local sc sw
  d_row "$2" "$3"
  sc=$(sc_answer "$3"); sw=$(sw_answer "$2")
  expect_eq "$1: the stop gate answers $4" "$4" "$sc"
  expect_eq "$1: the sweeper gives the stop gate's answer" "$sc" "$sw"
}

agree_on "a written file"        wfile "$DFX/full-file.md"  delivered
agree_on "an empty file"         efile "$DFX/empty-file.md" not-delivered
agree_on "an absent path"        nofile "$DFX/never.md"     not-delivered
agree_on "an EMPTY directory"    edir  "$DFX/empty-dir"     not-delivered
agree_on "a populated directory" fdir  "$DFX/full-dir"      delivered
# A repo-relative path, asked from the repo root — which is where the roster's own paths are
# written from, and the one place the two owners resolve it identically (the sweeper reads
# it against the REPO, the stop gate against the operator's typed cwd).
agree_on "a repo-relative path, asked from the repo root" relrow "relative-target.md" delivered

# THE NAMED DIVERGENCES, pinned as INEQUALITIES rather than left for the next reader to
# discover. These are the cases where the two owners are SUPPOSED to disagree, and a suite
# that only asserted agreement would go green on a drift that collapsed one into the other.
#
# SYMLINKS (Step-6 security review S-3). The stop gate follows a link on its file branch;
# the landing predicate refuses one on BOTH branches, because a contract satisfied by
# `ln -s` is satisfied with zero bytes written.
ln -s "$DFX/full-file.md" "$DFX/linked-file.md"
d_row linkrow "$DFX/linked-file.md"
expect_eq "a symlink to a written file: the stop gate reads it as delivered" \
  "delivered" "$(sc_answer "$DFX/linked-file.md")"
expect_eq "…while the landing predicate refuses it, by design" \
  "not-delivered" "$(sw_answer linkrow)"

# STALENESS. The landing predicate requires an mtime AFTER the row's own launched_at; the
# stop gate does not date the artifact at all. Same file, same moment, two answers.
echo "written before this agent was ever dispatched" > "$DFX/prelaunch.md"
touch -t 202001010000 "$DFX/prelaunch.md"
d_row stalerow "$DFX/prelaunch.md"
expect_eq "a PRE-LAUNCH file: the stop gate reads it as delivered (it never dates it)" \
  "delivered" "$(sc_answer "$DFX/prelaunch.md")"
expect_eq "…while the landing predicate calls it stale, by design" \
  "not-delivered" "$(sw_answer stalerow)"

# ============================================================
echo ""
echo "=== J — THE LANDING CONTRACT: the gate refuses exactly when the verdict says UNMET ==="
# ============================================================
#
# epic-16 wave-01 split one answer across two scripts on purpose.
# hooks/session-sweeper.sh's `verdict` verb OWNS the delivered predicate (spec
# §Design ownership table); hooks/landing-gate.sh consumes it on SubagentStop and
# refuses the stop when it reads UNMET. The gate holds NO copy of the predicate —
# "a third copy of the delivered predicate in the landing gate" is a rejected
# alternative in the spec — so the property worth driving here is not whether the
# gate stats a file correctly, which it never does. It is AGREEMENT: over one
# roster and one set of artifacts, the gate refuses a stop if and only if the verb
# an orchestrator runs by hand says that contract is UNMET. Two people asking the
# same question about the same agent must not get two answers.
#
# THE ASYMMETRY IS THE SUBJECT, and both directions are asserted rather than
# assumed. §J.2 shows that only a change to the GATE can split the two answers,
# and §J.3 shows that a change to the PREDICATE moves both together. That is what
# having one owner buys operationally, and it is the claim this section keeps true.

JREPO=$(new_repo "landing-contract")
write_plan "$JREPO/.bionic/docs/plans/epic-16/wave-01.md" "current: 4"
JDELIV="$JREPO/deliv"
mkdir -p "$JDELIV" "$JREPO/.bionic/tmp"
JROSTER="$JREPO/.bionic/tmp/roster-$SID_A.state"
J_LAUNCHED=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)

# Roster rows in the shape hooks/dispatch-preflight.sh's `ROW=` line really writes
# TODAY — field for field, including `source=` (slice 4/4) and `waiver=` (the
# absent-deliverable wall). A fixture missing a field the writer emits is how a
# suite ends up green over a row shape nothing produces; the sweeper's and the
# recorder's suites each had to make this same correction mid-wave.
#
# `agent_id=` is filled here because it is the SWEEP's join key (epic-16 wave-03, T4c): a
# row whose id is absent from the Stop payload's `background_tasks[]` has landed and is
# judged, and one still listed there is skipped. The rest of the row is the writer's own.
jrow() {  # <name> <deliverable> <progress> <cadence> <waiver> [tool_use_id]
  printf 'roster-state/v1|status=confirmed|session=%s|name=%s|agent_id=a-%s|launched_at=%s|subagent_type=implementor|model=opus|deliverable=%s|source=declared|duration=|progress=%s|claims=|cadence=%s|absent=|waiver=%s|tool_use_id=%s\n' \
    "$SID_A" "$1" "$1" "$J_LAUNCHED" "$2" "$3" "$4" "$5" "${6:-toolu_01LANDING}" >> "$JROSTER"
}

printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$JROSTER"
echo "the report" > "$JDELIV/met.md"
: > "$JDELIV/empty.md"
echo "written before the agent was ever dispatched" > "$JDELIV/stale.md"
touch -t 202001010000 "$JDELIV/stale.md"
printf 'stage 1\n' > "$JREPO/.bionic/tmp/live.progress"

ln -s "$JDELIV/met.md" "$JDELIV/linked.md"

jrow met    "$JDELIV/met.md"   ""                                    ""     ""
jrow unmet  "$JDELIV/never.md" ""                                    ""     ""
jrow empty  "$JDELIV/empty.md" ""                                    ""     ""
jrow stale  "$JDELIV/stale.md" ""                                    ""     ""
jrow live   "$JDELIV/never.md" "$JREPO/.bionic/tmp/live.progress"    "~5m"  ""
# A GENUINE waiver names no artifact — the wall's own label reads "why this dispatch
# produces nothing durable" (Step-6 review S-1). The row below it is the contradictory
# shape: a declared artifact AND a waiver, which one line of quoted documentation in a
# brief used to produce, and which used to silence the contract entirely.
jrow waived ""                 ""                                    ""     "this dispatch produces nothing durable"
jrow quoter "$JDELIV/never.md" ""                                    ""     "<why this dispatch produces nothing durable>"
# The symlink half of S-3: a contract satisfied by `ln -s` is satisfied with zero bytes
# written, so the landing predicate refuses it and the gate refuses the stop.
jrow linked "$JDELIV/linked.md" ""                                   ""     ""
# C-2: two dispatches share a name, so the fold cannot tell whose contract is whose. The
# verb says AMBIGUOUS and the gate passes — a stop let through is recoverable, the wrong
# agent blocked is not.
jrow dup    "$JDELIV/met.md"   ""                                    ""     ""     toolu_01DUPA
jrow dup    "$JDELIV/never.md" ""                                    ""     ""     toolu_01DUPB

# The battery's baseline, restored before every gate call (see j_gate): the sweep is
# idempotent by design and journals a marker into this file to stay that way.
cp "$JROSTER" "$JROSTER.pristine"

j_line() {  # <name> -> the verb's machine line for that name, or empty
  ( cd "$JREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict "$1" 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | grep -F "|name=$1|" | head -1
}
j_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}
j_verdict() {  # <name> -> the state the verb computed, or NONE when it prints no line
  local l; l=$(j_line "$1")
  if [ -z "$l" ]; then echo NONE; else j_field "$l" state; fi
}
# THE SWEEP JUDGES EVERY LANDED ROW AT ONCE, so asking it about ONE row means declaring
# every OTHER row still in flight. That is the mechanism's own vocabulary rather than a test
# seam: `background_tasks[]` is the payload's list of what is still running, and the gate
# skips exactly those. `ghost` is on no roster row, so nothing lands and nothing is judged.
J_ALL="met unmet empty stale live waived quoter linked dup"
j_live_except() {  # <name> -> every OTHER row's agent id
  local want="$1" n
  for n in $J_ALL; do [ "$n" = "$want" ] || printf 'a-%s\n' "$n"; done
}

# Globals rather than a captured echo: the refusal TEXT is asserted below, and a
# `$(…)` call would throw the stderr away.
J_ANSWER=""; J_GATE_ERR=""
j_gate() {  # <name> [stop_hook_active] -> sets J_ANSWER + J_GATE_ERR
  local st
  # THE ROSTER IS RESTORED FIRST. The sweep verdicts each landed row exactly ONCE and
  # journals a marker into the roster file to keep that promise; a battery that asked twice
  # about one row would be measuring the marker, not the agreement. Restoring is also what
  # every real session gets — a fresh roster per session.
  cp "$JROSTER.pristine" "$JROSTER"
  # shellcheck disable=SC2046
  J_GATE_ERR=$( mk_stopsweep_payload "$JREPO" "$SID_A" "${2:-false}" $(j_live_except "$1") \
                | bash "$PARTY_LG" 2>&1 >/dev/null )
  st=$?
  case "$st" in
    0) J_ANSWER=pass ;;
    2) J_ANSWER=refuse ;;
    *) J_ANSWER="other:exit-$st" ;;
  esac
}

# name|the verb's state|the gate's answer.  `ghost` is on no roster row at all —
# the phantom class the capture probe found firing three times per teammate run,
# where the verb prints nothing and the gate must not invent a contract.
J_CASES='
met|MET|pass
unmet|UNMET|refuse
empty|UNMET|refuse
stale|UNMET|refuse
waived|WAIVED|pass
quoter|UNMET|refuse
linked|UNMET|refuse
dup|AMBIGUOUS|pass
live|STILL-LIVE|pass
ghost|NONE|pass
'

run_j_battery() {  # assert|detect
  local mode="$1" name want ans v
  while IFS='|' read -r name want ans; do
    [ -n "$name" ] || continue
    v=$(j_verdict "$name"); j_gate "$name"
    if [ "$mode" = "assert" ]; then
      expect_eq "the verb computes $want for '$name'" "$want" "$v"
      expect_eq "…and the gate answers $ans, which is what $want means for a stop" \
        "$ans" "$J_ANSWER"
      # The agreement itself, computed from the verb's own answer rather than from
      # the table — so a case added to J_CASES with the wrong pairing cannot pass.
      expect_eq "…gate refuses IFF the verb says UNMET ('$name')" \
        "$([ "$v" = "UNMET" ] && echo refuse || echo pass)" "$J_ANSWER"
    else
      if [ "$v" != "$want" ]; then
        printf 'the verb moved on %s: want=%s got=%s\n' "$name" "$want" "$v"; return 1
      fi
      if [ "$J_ANSWER" != "$ans" ]; then
        printf 'gate/verb disagree on %s: verb=%s gate=%s (expected %s)\n' \
          "$name" "$v" "$J_ANSWER" "$ans"; return 1
      fi
    fi
  done <<EOF
$(printf '%s' "$J_CASES")
EOF
  return 0
}

run_j_battery assert

# The refusal is the VERB's detail, unedited — the strongest form of the agreement,
# because the stopping agent is handed the same sentence the orchestrator reads.
j_gate unmet
expect_contains "the refusal quotes the verb's own detail, character for character" \
  "$(j_field "$(j_line unmet)" detail)" "$J_GATE_ERR"
expect_contains "…which names the missing artifact by the path the roster declared" \
  "missing=$JDELIV/never.md" "$J_GATE_ERR"
j_gate empty
expect_contains "an EMPTY deliverable refuses naming the empty= conjunct" \
  "empty=$JDELIV/empty.md" "$J_GATE_ERR"
j_gate stale
expect_contains "a PRE-LAUNCH file refuses naming the stale= conjunct and both stamps" \
  "stale=$JDELIV/stale.md (mtime " "$J_GATE_ERR"
expect_contains "…dated against the row's own launched_at" "launched_at $J_LAUNCHED" "$J_GATE_ERR"
j_gate quoter
expect_contains "a waiver beside a DECLARED artifact refuses, naming the artifact" \
  "missing=$JDELIV/never.md" "$J_GATE_ERR"
expect_contains "…and says the waiver was disregarded rather than silently honouring it" \
  "waiver disregarded" "$J_GATE_ERR"
j_gate linked
expect_contains "a symlinked deliverable refuses naming the symlink= conjunct" \
  "symlink=$JDELIV/linked.md" "$J_GATE_ERR"
j_gate dup
expect_eq "a name carrying two contracts is not blocked on either of them" "pass" "$J_ANSWER"
expect_eq "…and is told nothing about an artifact that may not be its job" "" "$J_GATE_ERR"

# THE ONE DELIBERATE DIVERGENCE, pinned rather than left implicit. On re-entry the
# gate passes a contract the verb still calls UNMET — and the verb is re-run here
# rather than assumed, so this asserts a difference in AUTHORITY, not a difference
# of opinion about the disk. Blocking once is the R7 term: only the gate has a stop
# to refuse, and an agent refused twice has no way out of the loop.
j_gate unmet true
expect_eq "on re-entry (stop_hook_active true) the gate passes" "pass" "$J_ANSWER"
expect_eq "…while the verb's answer is unchanged, because the disk did not change" \
  "UNMET" "$(j_verdict unmet)"

# ============================================================
echo ""
echo "=== J.2 — only a GATE change can split the two answers (mutation goes RED) ==="
# ============================================================
#
# Each mutation is applied to a COPY of the gate, installed in its own directory
# beside a real sweeper — which is how bootstrap's flat `hooks/*.sh` install lets
# the gate find its sibling, and therefore the production resolution rather than a
# test seam. Every one is a plausible drift, not damage.

JMUT="$SANDBOX/landing-mutants"
J_CKSUM_BEFORE=$(shasum "$PARTY_LG" "$PARTY_SW" 2>/dev/null)

j_mutant() {  # <kind> -> path to a mutant gate with a sibling sweeper, or empty
  # Two statements, not one: `local a=1 b="$a"` expands every word BEFORE it
  # assigns any of them, so under `set -u` the second reference is unbound.
  local kind="$1"
  local d="$JMUT/$kind"
  mkdir -p "$d"
  cp "$PARTY_SW" "$d/session-sweeper.sh"
  case "$kind" in
    # THE LANDED/LIVE DISCRIMINATION DROPPED. `background_tasks[]` is the payload's
    # list of what is STILL RUNNING (T4b §2.2), and skipping those rows is the whole
    # of "judge it when it lands". Without the skip the sweep holds every mid-flight
    # agent to a contract it has not finished — the false-alarm direction.
    ignore-background-tasks)
      awk '{ if (index($0, "$LIVE_IDS") > 0 && index($0, "case ") > 0) next
             print }' "$PARTY_LG" > "$d/landing-gate.sh" ;;
    # The hook process's ambient session key instead of the payload's (the gate
    # documents why at the code) — a wrong or absent roster, silently.
    ambient-session-key)
      awk '{ sub(/CLAUDE_CODE_SESSION_ID="[$]SID" /, ""); print }' \
        "$PARTY_LG" > "$d/landing-gate.sh" ;;
    # The sweeper resolves its own state directory from the working directory, so
    # dropping the cd asks the verb about whatever repo the hook happened to run in.
    no-cd-to-repo)
      awk '{ if (index($0, "VERDICT=$( cd ") > 0) $0 = "VERDICT=$( true"
             print }' "$PARTY_LG" > "$d/landing-gate.sh" ;;
    *) return 1 ;;
  esac
  cmp -s "$PARTY_LG" "$d/landing-gate.sh" && return 1
  printf '%s' "$d/landing-gate.sh"
}

for m in ignore-background-tasks ambient-session-key no-cd-to-repo; do
  mpath=$(j_mutant "$m") || mpath=""
  if [ -z "$mpath" ]; then
    # A mutation that matched nothing is not a passing test — it means the code
    # moved and this proof has gone vacuous.
    no "gate mutation '$m' applies to landing-gate.sh" "the sed target matched nothing — the code moved"
    continue
  fi
  j_saved="$PARTY_LG"; PARTY_LG="$mpath"
  if jdetail=$(run_j_battery detect); then
    no "one-gate mutation '$m' makes the landing battery RED" \
       "the battery stayed green with the gate mutated — it does not discriminate"
  else
    ok "one-gate mutation '$m' makes the landing battery RED"
  fi
  PARTY_LG="$j_saved"
done

# ============================================================
echo ""
echo "=== J.3 — a PREDICATE change moves BOTH answers, never one (the single owner) ==="
# ============================================================
#
# The mutant sweeper below reads an EMPTY file as delivered — the `[ -s ]` defect
# §I.2 pins on the tick loop, here in the landing predicate. It is installed as the
# sibling of an UNMUTATED copy of the gate, so the only thing that changed is the
# owner of the predicate. Both answers flip together: that is not a lucky
# coincidence, it is what "the gate owns no predicate" means in operation, and it
# is the reason the two can never be caught telling different people different
# things about one contract.
JP="$JMUT/predicate"
mkdir -p "$JP"
cp "$PARTY_LG" "$JP/landing-gate.sh"
awk '{ sub(/\[ ! -s "[$]p" \]/, "[ ! -e \"$p\" ]"); print }' "$PARTY_SW" > "$JP/session-sweeper.sh"
if cmp -s "$PARTY_SW" "$JP/session-sweeper.sh"; then
  no "predicate mutation applies to session-sweeper.sh" "the sed target matched nothing — the code moved"
else
  ok "predicate mutation applies to session-sweeper.sh"
fi
j_saved_lg="$PARTY_LG"; j_saved_sw="$PARTY_SW"
PARTY_LG="$JP/landing-gate.sh"; PARTY_SW="$JP/session-sweeper.sh"
j_gate empty
expect_eq "with the predicate loosened, the verb calls the empty file delivered" \
  "MET" "$(j_verdict empty)"
expect_eq "…and the gate passes the same stop it refused a moment ago" "pass" "$J_ANSWER"
PARTY_LG="$j_saved_lg"; PARTY_SW="$j_saved_sw"
expect_eq "the shipped gate and sweeper are byte-identical to before the mutations" \
  "$J_CKSUM_BEFORE" "$(shasum "$PARTY_LG" "$PARTY_SW" 2>/dev/null)"

# ============================================================
echo ""
echo "=== J.4 — still-live has ONE owner now; the row that split the two is pinned ==="
# ============================================================
#
# "Is this row still live?" used to be computed at TWO sites in hooks/session-sweeper.sh
# that served different masters and were SUPPOSED to disagree (wave-01 Step-6 critic D-2):
#   * evaluate_row — the tick loop, a WAKE heuristic. A row that declared `claims=` opted
#     into process-liveness as its ONLY signal, so a dead claimed process was a dead-claim
#     finding full stop and progress was never consulted.
#   * row_still_live — the verdict verb, a STOP exemption. A dead claim falls THROUGH to
#     progress/cadence, so fresh progress can still answer STILL-LIVE and spare a stopping
#     agent a false UNMET.
# On a dead-claim-plus-fresh-progress row the two answered DIFFERENTLY, and this section
# pinned that inequality so neither could drift toward the other.
#
# THE TICK LOOP IS DELETED (epic-16 wave-02), so there is no second owner and no inequality
# left to pin — an equality assertion between one implementation and nothing is not a test,
# and asserting the difference persists would be asserting that deleted code still runs. What
# survives is the SURVIVOR'S HALF, driven on the identical fixture: the row shape that split
# the two owners is exactly the row shape most likely to be misjudged, and the verdict verb
# must still call it STILL-LIVE. If a future edit collapses row_still_live into the loop's
# old "a dead claim ends the question" reading, this goes red.
DLREPO=$(new_repo "still-live-divergence")
write_plan "$DLREPO/.bionic/docs/plans/epic-16/wave-01.md" "current: 4"
mkdir -p "$DLREPO/.bionic/tmp"
DL_ROSTER="$DLREPO/.bionic/tmp/roster-$SID_A.state"
DL_LAUNCHED=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)
# FRESH progress written now, well inside the declared cadence; a DEAD claim no live process
# carries; an ABSENT deliverable so the row has not landed and is genuinely judged.
printf 'stage 1\n' > "$DLREPO/.bionic/tmp/dl.progress"
DL_CLAIM="bionic-xgate-D2-deadclaim-no-such-process-9f5c1a2b"
{
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
  printf 'roster-state/v1|status=confirmed|session=%s|name=dl-row|agent_id=adl-row-0001|launched_at=%s|subagent_type=implementor|model=opus|deliverable=.bionic/docs/record/never-dl.md|source=declared|duration=|progress=%s|claims=%s|cadence=~5m|absent=|waiver=|tool_use_id=toolu_DL\n' \
    "$SID_A" "$DL_LAUNCHED" ".bionic/tmp/dl.progress" "$DL_CLAIM"
} > "$DL_ROSTER"
# Not vacuous: the claimed process really is dead.
expect_eq "the claimed process is genuinely not running (test not vacuous)" "no" \
  "$(pgrep -f -- "$DL_CLAIM" >/dev/null 2>&1 && echo yes || echo no)"

DL_VERDICT=$( cd "$DLREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict dl-row 2>/dev/null \
  | grep -F 'landing-verdict/v1|' | grep -F '|name=dl-row|' | head -1 \
  | tr '|' '\n' | grep '^state=' | head -1 | cut -d= -f2- )
expect_eq "the verdict verb calls the dead-claim-plus-fresh-progress row STILL-LIVE" \
  "STILL-LIVE" "$DL_VERDICT"

# The DISCRIMINATING half, and what makes the assertion above mean something: it is the
# PROGRESS that carries the row, not a blanket refusal to judge a claimed row. Stale the
# progress and the same row — same dead claim, same absent deliverable — reads UNMET.
touch -t 202001010000 "$DLREPO/.bionic/tmp/dl.progress"
DL_VERDICT_STALE=$( cd "$DLREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict dl-row 2>/dev/null \
  | grep -F 'landing-verdict/v1|' | grep -F '|name=dl-row|' | head -1 \
  | tr '|' '\n' | grep '^state=' | head -1 | cut -d= -f2- )
expect_eq "…and once that progress goes stale the same row is UNMET" "UNMET" "$DL_VERDICT_STALE"

# The gate consumes exactly that, both ways round — one owner, and the stop follows it.
j_saved_lg2="$PARTY_LG"
# The sweep answers once per row, ever, so the marker it journals is cleared between the
# two halves: what is being asked twice is the PREDICATE, not the idempotency.
dl_sweep() {  # -> sets JDL_ST; echoes the refusal
  /usr/bin/grep -v '^landing-swept/' "$DL_ROSTER" > "$DL_ROSTER.tmp" 2>/dev/null
  mv "$DL_ROSTER.tmp" "$DL_ROSTER"
  mk_stopsweep_payload "$DLREPO" "$SID_A" false | bash "$PARTY_LG" 2>&1 >/dev/null
}
JDL_ERR=$(dl_sweep); JDL_ST=$?
expect_eq "the gate refuses the stop on the UNMET reading" "2" "$JDL_ST"
printf 'stage 2\n' > "$DLREPO/.bionic/tmp/dl.progress"
JDL_ERR2=$(dl_sweep); JDL_ST2=$?
expect_eq "…and passes it the moment the progress is fresh again" "0" "$JDL_ST2"
PARTY_LG="$j_saved_lg2"

# ============================================================
echo ""
echo "=== K — the IDENTITY CHAIN: intended → confirmed → identified, one contract ==="
# ============================================================
#
# The roster is append-only and a contract ADVANCES along it: `intended` at the
# dispatch wall, `confirmed` when the spawn returns, `identified` when the subagent
# starts (spec §1). Three rows, ONE contract — and four readers that must not
# disagree about it: the sweeper's verdict folds to the latest row per name,
# hooks/stop-check.sh and hooks/stop-guard.sh take the row by id and fall back to
# the row by name, and the recorder's own join reads the chain to extend it.
#
# The chain below is built by the REAL writers from a REAL brief — the start gate,
# then the recorder's completion arm on a teammate-shaped payload, then the
# recorder's identification arm on a SubagentStart. Nothing here is a hand-written
# row, because the defect this section exists to catch is a writer that stops
# copying a field forward, and a hand-written fixture would carry the fields the
# test author remembered rather than the ones the writer emits.

KREPO=$(new_repo "identity-chain")
KSLUG=$(printf '%s' "$KREPO" | sed 's/[^a-zA-Z0-9]/-/g')
KPROJ="$CLAUDE_CONFIG_DIR/projects/$KSLUG"
KSUB="$KPROJ/$SID_A/subagents"
KSUB_B="$KPROJ/$SID_B/subagents"
mkdir -p "$KSUB" "$KSUB_B" "$KREPO/.bionic/tmp"
KTR="$KPROJ/$SID_A.jsonl"; printf '{}\n' > "$KTR"
KTR_B="$KPROJ/$SID_B.jsonl"; printf '{}\n' > "$KTR_B"
write_plan "$KREPO/.bionic/docs/plans/epic-16/wave-01.md" "current: 4"
KROSTER="$KREPO/.bionic/tmp/roster-$SID_A.state"
KID="aw16chain-1234567890abcdef"

# The attestation the dispatch wall demands, as a fixture: whether the producer and
# the wall spell that key the same way is §B's subject, not this one.
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\nkind=preflight-attestation\n'
  printf 'session_id=%s\nwritten_at=1785790000\nrepo=%s\n' "$SID_A" "$KREPO"
} > "$KREPO/.bionic/tmp/preflight-$SID_A.state"

K_BRIEF='Canonical-sdlc Step 4, slice 6 of epic-16 wave-01; build · audited · wave.
Expected artifact: .bionic/docs/record/w16-chain.md
Expected duration: ~30 minutes. Progress artifact: .bionic/tmp/w16-chain.progress, cadence ~7m.
Subprocess claim: `w16-chain-marker` → .bionic/tmp/w16-chain.log
Exit condition: the artifact exists.'

# STAGE 1 — the dispatch wall writes `intended`.
mk_agent_payload "$SID_A" "$KREPO" \
  | jq --arg p "$K_BRIEF" '.tool_input.name = "w16-chain" | .tool_input.prompt = $p
                           | .tool_use_id = "toolu_01CHAIN"' \
  | bash "$PARTY_DP" >/dev/null 2>&1
K_INTENDED=$(grep 'status=intended|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_contains "the dispatch wall journalled the launch as intended" \
  "status=intended" "$K_INTENDED"
expect_contains "…carrying the deliverable the brief declared" \
  "deliverable=.bionic/docs/record/w16-chain.md" "$K_INTENDED"

# STAGE 2 — the spawn returns; the recorder completes the row to `confirmed`. The
# ASYNC shape, which is the one the id join spans end to end: `tool_response.agentId`
# here is the same string SubagentStart carries below and the same string the landing
# sweep matches against `background_tasks[].id` (t4b-probe-report.md §4). The TEAMMATE
# shape — addressing id recorded, `agent_id=` deliberately left empty, and therefore
# never identified — is pinned in hooks/execution-recorder.test.sh Section 10.
mk_agent_post "$SID_A" "$KTR" "$KREPO" "toolu_01CHAIN" "w16-chain" "$KID" \
  | bash "$PARTY_ER" >/dev/null 2>&1
K_CONFIRMED=$(grep 'status=confirmed|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_contains "the spawn's completion advances the row to confirmed" \
  "status=confirmed" "$K_CONFIRMED"
expect_contains "…recording the transcript-form id the join needs" \
  "agent_id=$KID" "$K_CONFIRMED"
expect_absent "…and no teammate_id, because this dispatch was not a teammate spawn" \
  "teammate_id=" "$K_CONFIRMED"

# STAGE 3 — the subagent starts; the recorder joins BY THAT ID and writes `identified`.
mk_start_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" "$KID" | bash "$PARTY_ER" >/dev/null 2>&1
K_IDENTIFIED=$(grep 'status=identified|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_contains "the start advances the row to identified" "status=identified" "$K_IDENTIFIED"
expect_contains "…carrying the transcript-form id" "agent_id=$KID" "$K_IDENTIFIED"
expect_eq "the chain is three rows for one name, in order" "intended confirmed identified" \
  "$(grep '|name=w16-chain|' "$KROSTER" 2>/dev/null | tr '|' '\n' | grep '^status=' | cut -d= -f2 | tr '\n' ' ' | sed 's/ $//')"

# --- K.1 the chain invariant: every contract field survives every advance ---
#
# "Every field copied forward" is the recorder's own claim, and it is load-bearing
# rather than tidy: the verdict folds to the LATEST row per name and reads the whole
# contract — deliverable, launch clock, progress path, cadence, claims, waiver — off
# that row alone. A row that dropped a field would not merely be terse; it would
# silently RETRACT the contract it inherited, and the verdict would then call it MET
# for naming nothing. Compared generically, so a field added later is covered by this
# test the day it is added rather than the day someone remembers to list it.
k_contract_fields() {  # <row> -> the fields that must not change, one per line
  printf '%s' "$1" | tr '|' '\n' \
    | grep -v '^roster-state/' | grep -v '^status=' | grep -v '^agent_id=' \
    | grep -v '^teammate_id='
}
expect_eq "every contract field survives intended → confirmed" \
  "$(k_contract_fields "$K_INTENDED")" "$(k_contract_fields "$K_CONFIRMED")"
expect_eq "every contract field survives confirmed → identified" \
  "$(k_contract_fields "$K_CONFIRMED")" "$(k_contract_fields "$K_IDENTIFIED")"

# --- K.2 the four readers, one row, one contract ---
plant "$KSUB" "$KID" "w16-chain"

# READER 1 — the sweeper's verdict. ONE line for the name, not three: a gate handed
# a line per roster row would have to guess which to believe. Taken BEFORE the
# progress artifact exists, because a progress file inside its declared cadence is
# STILL-LIVE by design and this reader is being asked about the deliverable.
K_VERDICT=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict w16-chain 2>/dev/null )
expect_eq "the verdict prints exactly ONE line for a three-row chain" "1" \
  "$(printf '%s\n' "$K_VERDICT" | grep -cF 'landing-verdict/v1|')"
K_VLINE=$(printf '%s\n' "$K_VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
# STILL-LIVE, and asserted rather than engineered away: this chain is seconds old
# and its brief declared a ~7m cadence, so an agent that has not written anything
# yet is visibly in flight, not in breach. What matters here is that the verb read
# the CONTRACT off the chain at all — it names the outstanding artifact either way.
expect_eq "…and it reads the contract off the chain, not off nothing" "STILL-LIVE" \
  "$(j_field "$K_VLINE" state)"
expect_contains "…naming the artifact the brief declared at dispatch, still outstanding" \
  "outstanding: missing=.bionic/docs/record/w16-chain.md" "$(j_field "$K_VLINE" detail)"

# The paired positive (AC-4's absence-readback rule): the same chain, the same verb,
# with the artifact on disk. `sleep 1` because the delivered predicate is
# mtime > launched_at and the row was written this second.
sleep 1
mkdir -p "$KREPO/.bionic/docs/record"
echo "the slice report" > "$KREPO/.bionic/docs/record/w16-chain.md"
K_VERDICT=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict w16-chain 2>/dev/null )
K_VLINE=$(printf '%s\n' "$K_VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
expect_eq "…and the same chain reads MET once the artifact lands" "MET" \
  "$(j_field "$K_VLINE" state)"
expect_contains "…naming it delivered, by the path the brief declared" \
  "delivered=.bionic/docs/record/w16-chain.md" "$(j_field "$K_VLINE" detail)"

# READER 2 — the observation. Same chain, same contract, reached by its own means:
# it takes no payload, so it finds the roster by slugifying its own cwd.
printf 'stage 1\n' > "$KREPO/.bionic/tmp/w16-chain.progress"
K_OBS=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w16-chain 2>&1 )
K_MLINE=$(printf '%s\n' "$K_OBS" | grep '^stop-check-observation/')
expect_contains "the observation calls the identified agent OURS" "Classification: OURS" "$K_OBS"
expect_contains "…and shows the contract it read off the chain" \
  "deliverables=.bionic/docs/record/w16-chain.md" "$K_OBS"
expect_contains "…naming the roster as where that contract came from" \
  "deliverable_source=roster" "$K_MLINE"
expect_contains "…and the same progress path" "progress=.bionic/tmp/w16-chain.progress" "$K_MLINE"
expect_contains "…from the same source" "progress_source=roster" "$K_MLINE"

# THE READERS COMPARED TO EACH OTHER, not each to a literal — which is what goes red
# when either one starts resolving a different row of the chain. The observation's
# machine line renders each deliverable as `<state>:<path>`, so the state is stripped
# before the paths are compared; the STATE itself is asserted separately, because
# both readers must also agree the artifact is not there.
k_sw_path() {  # the path the VERB says the contract names, whatever state it reports
  j_field "$K_VLINE" detail \
    | grep -oE '(missing|delivered|empty)=[^ ]+' | head -1 | cut -d= -f2-
}
K_SC_DELIV=$(printf '%s' "$K_MLINE" | tr '|' '\n' | grep '^deliverables=' | head -1 | cut -d= -f2-)
expect_eq "the verb and the observation name the same deliverable" \
  "$(k_sw_path)" "${K_SC_DELIV#*:}"
expect_eq "…and agree it is on disk" "present" "${K_SC_DELIV%%:*}"
expect_eq "…and it is the value on the row the writer wrote" \
  "$(printf '%s' "$K_IDENTIFIED" | tr '|' '\n' | grep '^deliverable=' | head -1 | cut -d= -f2-)" \
  "$(k_sw_path)"

# READER 3 — the stop gate, over the D-6 channel the chain contracted. The refusal
# is sourced from the roster row this gate resolved, so it names the path the START
# gate lifted out of the brief three rows ago.
mk_bash_post "$SID_A" "$KTR" "$KREPO" "bash ~/.claude/hooks/stop-check.sh w16-chain" "$K_OBS" \
  | bash "$PARTY_ER" >/dev/null 2>&1
sleep 1
printf 'stage 2\n' >> "$KREPO/.bionic/tmp/w16-chain.progress"
# THE CONTRACT IS TAKEN BACK OFF DISK FIRST (epic-16 wave-02 slice S3). D-6 is a rule about
# a stop that would end UNFINISHED work: since this wave, a LANDED contract discharges the
# stop outright and no channel is consulted, which is AC-1 and is asserted as the paired
# half below. Reader 3's question — does the chain carry the progress path all the way to
# the gate's refusal — is only askable while the contract is outstanding, so the artifact
# reader 1 delivered is moved aside for it and restored immediately after. Same chain, same
# roster, same gate; the only thing that varies is the one fact that decides.
mv "$KREPO/.bionic/docs/record/w16-chain.md" "$SANDBOX/k-chain-artifact.md"
K_SG_OUT=$(mk_stop_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" | bash "$PARTY_SG" 2>&1); K_SG_ST=$?
expect_eq "the stop gate refuses a stop whose contracted channel moved under the look" \
  "2" "$K_SG_ST"
expect_contains "…naming the very path the chain carried forward" \
  ".bionic/tmp/w16-chain.progress" "$K_SG_OUT"

# THE OTHER DIRECTION, one fact apart: the artifact comes back, the verdict says MET, and
# the identical stop — same stale observation, same moved progress channel — passes with no
# ceremony at all. This is AC-1 read across the gates rather than inside one: the fact that
# discharges the stop is the same fact the verb reports and the operator can see.
mv "$SANDBOX/k-chain-artifact.md" "$KREPO/.bionic/docs/record/w16-chain.md"
K_SG_OUT=$(mk_stop_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" | bash "$PARTY_SG" 2>&1); K_SG_ST=$?
expect_eq "…and once the contract has landed, the same stop passes with no ceremony" \
  "0" "$K_SG_ST"
expect_eq "…silently — nothing is demanded of a stop the disk already answers for" \
  "" "$K_SG_OUT"

# READER 4 — the recorder's own join. A SECOND start for the SAME agent (the resume
# shape) re-joins the `confirmed` row rather than chaining off its own output — states
# advance, and a repeated start must not compound a field loss — and the row it writes
# still carries the original dispatch's tool_use_id, which is the proof it joined the
# chain rather than starting a new one. The id is the key, so a start for a DIFFERENT
# id is a different agent and joins nothing here.
mk_start_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" "$KID" \
  | bash "$PARTY_ER" >/dev/null 2>&1
K_IDENT2=$(grep 'status=identified|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_eq "a second start writes a second identified row" \
  "2" "$(grep -c 'status=identified|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tr -d ' ')"
expect_contains "…carrying the id it joined on" "agent_id=$KID" "$K_IDENT2"
expect_contains "…still carrying the original dispatch's tool_use_id" \
  "tool_use_id=toolu_01CHAIN" "$K_IDENT2"
expect_eq "…and the same contract as every row before it" \
  "$(k_contract_fields "$K_INTENDED")" "$(k_contract_fields "$K_IDENT2")"

# --- K.3 the identified row is what makes the by-id walls reachable (paired) ---
#
# R4's whole point, re-aimed at what actually supplies the key (epic-16 wave-03). The
# by-id walls can only vouch for an agent whose TRANSCRIPT-form id is on the roster;
# a row that carries no such id is a row no by-id reader can satisfy. On an async
# dispatch the roster arm supplies it at confirmation and the identification arm
# re-states it; on a TEAMMATE dispatch neither does — `agent_id=` is deliberately
# empty because the launch response carries only the addressing form, and since the
# identification join is by id there is nothing to join with. That gap is real and
# named in hooks/execution-recorder.sh; what is pinned HERE is the consequence, over
# ONE roster, in the one shape where the answer is observable: the agent's metadata
# filed under ANOTHER session's directory, where only the roster can vouch for it.
# The negative half strips the transcript id from every row and nothing else.
# The agent MOVES rather than being copied: the same id filed under two session
# directories of one project is the AMBIGUOUS case (§C2), which would answer this
# question with "the operator was shown a candidate list" instead of with the
# ownership rule under test.
mkdir -p "$SANDBOX/k-own-meta"
mv "$KSUB/agent-$KID.meta.json" "$KSUB/agent-$KID.jsonl" "$SANDBOX/k-own-meta/"
plant "$KSUB_B" "$KID" "w16-chain"
K_ROSTER_NOID="$SANDBOX/k-roster-without-identified.state"
grep -v 'status=identified' "$KROSTER" | sed -e "s/|agent_id=$KID|/|agent_id=|/" > "$K_ROSTER_NOID"
K_ROSTER_FULL="$SANDBOX/k-roster-full.state"
cp "$KROSTER" "$K_ROSTER_FULL"

k_observation_says() {  # -> the classification of the cross-session agent
  local out
  out=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$KID" 2>&1 )
  case "$out" in
    *"Classification: OURS"*)         echo ours ;;
    *"Classification: FOREIGN"*)      echo foreign ;;
    *"Classification: DEAD HISTORY"*) echo dead ;;
    *) echo "other" ;;
  esac
}
# The stop is BY NAME, which is the only shape the foreign wall guards: a by-id
# stop is the documented escape hatch (an id is unambiguous by construction), so
# asking by id would answer a different question. The payload's session key and its
# transcript path DISAGREE — the gate's own comment names that as the one way a
# cross-session target reaches it — and the observation/record pair runs first,
# because the record wall sits behind the foreign one and an unrecorded look would
# refuse both halves for the same uninteresting reason.
k_stop_gate_says() {  # -> foreign | ours
  local out
  rm -f "$KREPO/.bionic/tmp/stop-check.state"
  out=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$KID" 2>&1 )
  mk_bash_post "$SID_A" "$KTR_B" "$KREPO" "bash ~/.claude/hooks/stop-check.sh $KID" "$out" \
    | bash "$PARTY_ER" >/dev/null 2>&1
  out=$(mk_stop_payload "$SID_A" "$KTR_B" "$KREPO" "w16-chain" | bash "$PARTY_SG" 2>&1)
  case "$out" in
    *"was not launched by this session"*) echo foreign ;;
    *) echo ours ;;
  esac
}
expect_eq "with the identified row, the observation vouches for a cross-session agent" \
  "ours" "$(k_observation_says)"
expect_eq "…and the stop gate's foreign wall stands down over the same row" \
  "ours" "$(k_stop_gate_says)"
cp "$K_ROSTER_NOID" "$KROSTER"
expect_eq "without the transcript id anywhere on the roster, the observation calls it foreign" \
  "foreign" "$(k_observation_says)"
expect_eq "…and the stop gate refuses it, both readers flipping on the same row" \
  "foreign" "$(k_stop_gate_says)"
cp "$K_ROSTER_FULL" "$KROSTER"

# --- K.4 a forward-copy that drops a field goes RED here ---
#
# The mutation is the plausible one: an identification arm that writes a fresh row
# instead of copying the joined row forward. It is applied to a COPY of the recorder
# and driven over a SECOND chain, so the chain above is untouched.
KMUT="$SANDBOX/recorder-mutant.sh"
awk '{ print; if (index($0, "if (f ~ /^status=/)")) print "      if (f ~ /^deliverable=/) f = \"deliverable=\"" }' \
  "$PARTY_ER" > "$KMUT"
if cmp -s "$PARTY_ER" "$KMUT"; then
  no "forward-copy mutation applies to execution-recorder.sh" "the awk target matched nothing — the code moved"
else
  ok "forward-copy mutation applies to execution-recorder.sh"
  mk_agent_payload "$SID_A" "$KREPO" \
    | jq --arg p "$K_BRIEF" '.tool_input.name = "w16-mut" | .tool_input.prompt = $p
                             | .tool_use_id = "toolu_01MUT"' \
    | bash "$PARTY_DP" >/dev/null 2>&1
  mk_agent_post "$SID_A" "$KTR" "$KREPO" "toolu_01MUT" "w16-mut" "aw16mut-1111111111111111" \
    | bash "$KMUT" >/dev/null 2>&1
  mk_start_payload "$SID_A" "$KTR" "$KREPO" "w16-mut" "aw16mut-1111111111111111" \
    | bash "$KMUT" >/dev/null 2>&1
  K_MUT_INTENDED=$(grep 'status=intended|.*|name=w16-mut|' "$KROSTER" 2>/dev/null | tail -1)
  K_MUT_IDENT=$(grep 'status=identified|.*|name=w16-mut|' "$KROSTER" 2>/dev/null | tail -1)
  if [ "$(k_contract_fields "$K_MUT_INTENDED")" = "$(k_contract_fields "$K_MUT_IDENT")" ]; then
    no "a dropped forward-copy makes the chain invariant RED" \
       "the invariant stayed green with the recorder mutated — it does not discriminate"
  else
    ok "a dropped forward-copy makes the chain invariant RED"
  fi
  # …and the consequence the invariant is a proxy for: the contract is RETRACTED.
  # The verdict now calls a row MET for naming nothing, which is the false clean
  # answer the landing gate would pass a stopping agent on.
  expect_eq "…and the verdict then calls the retracted contract MET, vacuously" "MET" \
    "$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict w16-mut 2>/dev/null \
        | grep -F 'landing-verdict/v1|' | head -1 | tr '|' '\n' | grep '^state=' | cut -d= -f2- )"
fi

# ============================================================
echo ""
echo "=== L — the WIRING: registration is three-sided (frontmatter, absence, presence) ==="
# ============================================================
#
# A hook that reads an event nobody registered it for is inert, and inert in the
# quietest possible way: it is installed, it is syntactically fine, its own suite is
# green, and it never runs. Epic-16 wave-2 moves the seven sdlc hook scripts' ten
# event/matcher registrations OUT of MANAGED_HOOKS/settings.json and INTO the
# `hooks:` frontmatter block of skills/canonical-sdlc/SKILL.md, so the walls bind
# only in sessions that actually invoke the skill (R1). Three sides now have to
# agree or the move is silently wrong in one of three ways: the frontmatter could
# name the wrong shape, a moved script could linger behind in MANAGED_HOOKS (firing
# in EVERY session, defeating R1), or a script that should stay global could get
# swept out by mistake.
BOOTSTRAP_SRC=$(cat "$REPO_ROOT/claude-bootstrap.sh")
SKILL_SRC="$REPO_ROOT/skills/canonical-sdlc/SKILL.md"
MANAGED_HOOKS_SRC=$(awk '/^MANAGED_HOOKS=\(/{f=1} f{print} f&&/^\)$/{exit}' "$REPO_ROOT/claude-bootstrap.sh")

# the shell's bare `grep` is ugrep with ignore-files active and lies about absence
# (reports 0 hits inside paths it silently skips) — every absence check below goes
# through /usr/bin/grep instead.
expect_absent_ug() {
  if printf '%s' "$3" | /usr/bin/grep -qF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi
}

# --- L.1 frontmatter <-> script: the ten sdlc registrations live in SKILL.md's
# `hooks:` frontmatter block, same event/matcher/command shape MANAGED_HOOKS used to
# carry, each entry bounded by the same timeout: 10 the Step-6 review demanded.
# Line-anchored extraction of the pinned shape — pin the span, not the label.
SKILL_HOOKS_ROWS=$(awk '
  /^hooks:$/ { active=1; next }
  active && /^---$/ { active=0 }
  active && /^[A-Za-z]/ { active=0 }
  !active { next }
  /^  [A-Za-z]+:$/ { event=$0; sub(/^  /,"",event); sub(/:$/,"",event); matcher=""; next }
  /^    - matcher: "/ { matcher=$0; sub(/^    - matcher: "/,"",matcher); sub(/"$/,"",matcher); next }
  /^    - hooks:$/ { matcher=""; next }
  /^          command: / { cmd=$0; sub(/^          command: /,"",cmd); next }
  /^          timeout: / { t=$0; sub(/^          timeout: /,"",t); print event "|" matcher "|" cmd "|" t }
' "$SKILL_SRC")

expect_contains "frontmatter registers the evidence gate on PreToolUse|Bash, timeout 10" \
  "PreToolUse|Bash|~/.claude/hooks/canonical-sdlc-evidence-gate.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…the stop guard on PreToolUse|TaskStop, timeout 10" \
  "PreToolUse|TaskStop|~/.claude/hooks/stop-guard.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…dispatch-preflight on PreToolUse|Agent, timeout 10" \
  "PreToolUse|Agent|~/.claude/hooks/dispatch-preflight.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…the governing-skill gate on PreToolUse|Write, timeout 10" \
  "PreToolUse|Write|~/.claude/hooks/canonical-sdlc-governing-skill.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…and on PreToolUse|Edit, timeout 10" \
  "PreToolUse|Edit|~/.claude/hooks/canonical-sdlc-governing-skill.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…the recorder's observation arm on PostToolUse|Bash, timeout 10" \
  "PostToolUse|Bash|~/.claude/hooks/execution-recorder.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…its completion arm on PostToolUse|Agent, timeout 10" \
  "PostToolUse|Agent|~/.claude/hooks/execution-recorder.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…its identification arm on SubagentStart (no matcher), timeout 10" \
  "SubagentStart||~/.claude/hooks/execution-recorder.sh|10" "$SKILL_HOOKS_ROWS"
expect_contains "…context-spend on Stop (no matcher), timeout 10" \
  "Stop||~/.claude/hooks/context-spend.sh|10" "$SKILL_HOOKS_ROWS"
# THE LANDING SWEEP MOVED TO Stop (epic-16 wave-03, T4c). SubagentStop is dispatched in the
# SUBAGENT's context, and skill-frontmatter hooks are looked up by SESSION id — so no
# subagent-context event can ever reach this channel (T4b §3, from the shipped binary). A
# registration left on SubagentStop is a wall that is installed, syntactically fine, green in
# its own suite, and never runs.
expect_contains "…and the landing sweep on Stop (no matcher), timeout 10" \
  "Stop||~/.claude/hooks/landing-gate.sh|10" "$SKILL_HOOKS_ROWS"
expect_absent_ug "…with NOTHING left registered on SubagentStop" \
  "SubagentStop" "$SKILL_HOOKS_ROWS"
expect_eq "…exactly ten registrations in the frontmatter block, nothing extra" \
  "10" "$(printf '%s\n' "$SKILL_HOOKS_ROWS" | /usr/bin/grep -c '|')"

expect_contains "…and the landing sweep itself guards on that same event name" \
  '"$EVENT" = "Stop"' "$(cat "$PARTY_LG")"
expect_absent_ug "…and no longer answers to the event it can never receive" \
  'SubagentStop"' "$(cat "$PARTY_LG")"
expect_contains "…and the recorder's identification arm guards on that same event name" \
  '= "SubagentStart"' "$(cat "$PARTY_ER")"

# --- L.5 THE EVENT-NAME WHITELIST: one bad key voids the WHOLE block, silently ---
#
# T4b §5, bisected over four single-variable fixture skills: a `hooks:` block naming an
# event the harness does not know disarms EVERY registration in that skill — including the
# valid ones — with no error, no warning in `--output-format stream-json`, and no stderr.
# The skill still loads and its slash command still resolves. `TaskStop` is the proven case
# (it is a valid PreToolUse MATCHER, which is exactly why a hand would reach for it as an
# event key), and nothing else in this repo would notice: every other assertion in §L reads
# the file rather than the harness, so a voided block passes all of them.
#
# This test is therefore the only detector, and it is a WHITELIST rather than a blacklist:
# the failure is silent, so the safe default for an unrecognised key is red.
VALID_HOOK_EVENTS="PreToolUse PostToolUse Notification UserPromptSubmit Stop SubagentStop SubagentStart PreCompact SessionStart SessionEnd"
SKILL_EVENT_KEYS=$(awk '
  /^hooks:$/ { active=1; next }
  active && /^---$/ { active=0 }
  active && /^[A-Za-z]/ { active=0 }
  !active { next }
  /^  [A-Za-z]+:$/ { k=$0; sub(/^  /,"",k); sub(/:$/,"",k); print k }
' "$SKILL_SRC")
expect_eq "the frontmatter block declares at least one event key (this test is not vacuous)" \
  "yes" "$([ -n "$SKILL_EVENT_KEYS" ] && echo yes || echo no)"
L5_BAD=""
for k in $SKILL_EVENT_KEYS; do
  case " $VALID_HOOK_EVENTS " in
    *" $k "*) : ;;
    *) L5_BAD="${L5_BAD}${L5_BAD:+, }$k" ;;
  esac
done
expect_eq "every top-level key in the hooks: block is a hook event the harness knows" \
  "" "$L5_BAD"

# --- L.2 MANAGED_HOOKS absence: none of the five sdlc scripts that stayed
# skill-only appears ANYWHERE in the array bootstrap still converges on install — a
# lingering entry would fire the wall in every session, defeating R1 even after the
# frontmatter side is right.
for script in canonical-sdlc-evidence-gate.sh stop-guard.sh \
              execution-recorder.sh context-spend.sh landing-gate.sh; do
  expect_absent_ug "MANAGED_HOOKS no longer names $script (moved to frontmatter)" \
    "hooks/$script" "$MANAGED_HOOKS_SRC"
done
# THE TWO WALLS THAT CAME BACK (session-20260815 T6) are a conditional absence, not
# an absence: they are named in this array again, and every occurrence must sit
# behind hooks/agent-context-guard.sh. A bare entry would be the R1 regression this
# section was written to catch — the wall firing in every session on the machine —
# wearing the new registration's clothes, and §L.6 below (which asserts the guarded
# form is PRESENT) would still pass beside it.
L2_UNGUARDED=$(printf '%s\n' "$MANAGED_HOOKS_SRC" \
  | /usr/bin/grep -E 'dispatch-preflight\.sh|canonical-sdlc-governing-skill\.sh' \
  | /usr/bin/grep -v 'agent-context-guard\.sh')
expect_eq "…and the two walls that returned are never named UNGUARDED" "" "$L2_UNGUARDED"

# --- L.3 MANAGED_HOOKS presence: the three non-sdlc hooks are untouched by the move
# (R2: guard-set parity for everything that was never sdlc-scoped) — exact set, not
# just "still there somewhere among leftovers."
expect_contains "MANAGED_HOOKS keeps protect-main.sh on PreToolUse|Bash" \
  '"PreToolUse|Bash|~/.claude/hooks/protect-main.sh"' "$MANAGED_HOOKS_SRC"
expect_contains "…protect-database.sh on PreToolUse|Bash" \
  '"PreToolUse|Bash|~/.claude/hooks/protect-database.sh"' "$MANAGED_HOOKS_SRC"
expect_contains "…and farm-out-reminder.sh on PreToolUse|Bash" \
  '"PreToolUse|Bash|~/.claude/hooks/farm-out-reminder.sh"' "$MANAGED_HOOKS_SRC"
expect_eq "…and exactly six entries total — three unconditional, three guarded" \
  "6" "$(printf '%s\n' "$MANAGED_HOOKS_SRC" | /usr/bin/grep -c '"')"

# --- L.4 EVERY registration is bounded by a timeout, whichever branch writes it ---
#
# The Step-6 review's C-4: `wire_managed_hooks` attached `"timeout": 10` only on the
# matcher branch, so the two events this wave added — the ones that carry no matcher —
# registered with no ceiling at all, and the platform default was the only thing in front
# of the landing gate's verdict subprocess. A timeout is the safe direction here precisely
# because the gate is fail-open: a hook that is killed lets the stop through.
#
# Driven rather than grepped: the real function is extracted from the real script and run
# against a sandboxed settings file, the same convention tests/installer-behavior.test.sh
# uses, so this asserts what bootstrap WRITES and not what its source looks like.
LSBX="$SANDBOX/wiring"
mkdir -p "$LSBX"
LCODE="$LSBX/wire.sh"
awk '/^wire_managed_hooks\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$REPO_ROOT/claude-bootstrap.sh" > "$LCODE"
awk '/^MANAGED_HOOKS=\(/{f=1} f{print} f&&/^\)$/{exit}' "$REPO_ROOT/claude-bootstrap.sh" >> "$LCODE"
LSETTINGS="$LSBX/settings.json"
echo '{}' > "$LSETTINGS"
# shellcheck disable=SC1090
( . "$LCODE"; settings="$LSETTINGS"; wire_managed_hooks ) >/dev/null 2>&1
L_RC=$?
expect_eq "wire_managed_hooks runs against a sandboxed settings file" "0" "$L_RC"
expect_eq "…and registers every managed hook (this section is not vacuous)" \
  "$(printf '%s\n' "$BOOTSTRAP_SRC" | awk '/^MANAGED_HOOKS=\(/{f=1;next} f&&/^\)$/{exit} f&&/"/{n++} END{print n+0}')" \
  "$(jq '[.hooks[][].hooks[]] | length' "$LSETTINGS" 2>/dev/null)"
expect_eq "EVERY registered hook carries a timeout — the no-matcher branch included" "0" \
  "$(jq '[.hooks[][].hooks[] | select(has("timeout") | not)] | length' "$LSETTINGS" 2>/dev/null)"

# --- L.6 THE AGENT-CONTEXT CHANNEL: one wall, two channels, one partition ---
# (session-20260815-landing-supervision T6; design D1, plan AC-7/AC-8.)
#
# A tool-class event raised inside a teammate or subagent context is dispatched under
# the AGENT key and never reaches a skill-frontmatter registration (t1-probe-report.md
# §3, both directions, main-thread positive control in the same session). So the
# dispatch wall and the artifact wall are registered a SECOND time, through settings —
# the channel that is alive there — behind hooks/agent-context-guard.sh, which runs the
# named wall only for a payload carrying a top-level agent_id in a session that has a
# roster on disk.
#
# THE TOPOLOGY IS THE THING THIS SECTION OWNS, and it has three ways to be silently
# wrong, one per assertion below: the settings entry could point straight at a wall
# (that wall then fires in every session on the machine — L.2 above), the guard could
# ALSO be registered on the skill channel (both channels live on one event, so a
# main-thread refusal prints twice and a dispatch journals twice), or the two channels
# could drift onto different events (a wall covering the main thread on one event and
# agent contexts on another, which reads as coverage and is not).
ACG_PATH="$REPO_ROOT/hooks/agent-context-guard.sh"
expect_eq "the partition guard exists as a hook script" "yes" \
  "$([ -f "$ACG_PATH" ] && echo yes || echo no)"
expect_contains "MANAGED_HOOKS registers the DISPATCH wall for agent contexts, behind the guard" \
  '"PreToolUse|Agent|~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/dispatch-preflight.sh"' \
  "$MANAGED_HOOKS_SRC"
expect_contains "…the ARTIFACT wall on Write, behind the guard" \
  '"PreToolUse|Write|~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/canonical-sdlc-governing-skill.sh"' \
  "$MANAGED_HOOKS_SRC"
expect_contains "…and on Edit, behind the guard" \
  '"PreToolUse|Edit|~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/canonical-sdlc-governing-skill.sh"' \
  "$MANAGED_HOOKS_SRC"
expect_absent_ug "…and the guard itself is NOT on the skill channel (no event has two live channels)" \
  "agent-context-guard" "$SKILL_HOOKS_ROWS"

# The two channels cover the SAME three events: for each guarded settings entry there is
# a frontmatter row registering the same wall on the same event/matcher, straight (that
# is the main-thread half, asserted by value in L.1 and re-read here as a pair).
for _pair in "PreToolUse|Agent|~/.claude/hooks/dispatch-preflight.sh|10" \
             "PreToolUse|Write|~/.claude/hooks/canonical-sdlc-governing-skill.sh|10" \
             "PreToolUse|Edit|~/.claude/hooks/canonical-sdlc-governing-skill.sh|10"; do
  expect_contains "the skill channel still covers the main thread for ${_pair%%|*}|$(echo "$_pair" | cut -d'|' -f2)" \
    "$_pair" "$SKILL_HOOKS_ROWS"
done

# Driven, not grepped: what bootstrap WRITES for a guarded entry is one command string
# carrying both paths, with its matcher and its timeout — the shape the harness executes
# through a shell, and the shape that hands the guard its argument.
L6_CMDS=$(jq -r '.hooks.PreToolUse[]? | select(.matcher=="Agent") | .hooks[].command' "$LSETTINGS" 2>/dev/null)
expect_contains "wire_managed_hooks writes the guarded dispatch entry as ONE command with the wall as its argument" \
  "agent-context-guard.sh ~/.claude/hooks/dispatch-preflight.sh" "$L6_CMDS"
expect_eq "…and the guarded entries are bounded by the same timeout: 10" "0" \
  "$(jq '[.hooks.PreToolUse[]? | select(.matcher=="Agent" or .matcher=="Write" or .matcher=="Edit")
         | .hooks[] | select(.timeout != 10)] | length' "$LSETTINGS" 2>/dev/null)"

# The wall behind the guard is the one that skips its JOURNAL in an agent context —
# the reader and the writer of BIONIC_HOOK_CHANNEL are one pair across two files, and a
# rename on either side silently restores nested rostering.
expect_contains "the guard sets the channel marker the dispatch wall reads" \
  'BIONIC_HOOK_CHANNEL=agent-context' "$(cat "$ACG_PATH")"
expect_contains "…and the dispatch wall skips its roster append on exactly that value" \
  '"${BIONIC_HOOK_CHANNEL:-}" = "agent-context"' "$(cat "$PARTY_DP")"

# ============================================================
echo ""
echo "=== M — THE ACK, and the stop order: ONE owner, three consumers (epic-16 w2 S3/S9) ==="
# ============================================================
#
# Two facts reach the stop arc from outside it, and each has ONE writer and several readers:
#
#   the ACK   — written by `hooks/session-sweeper.sh ack`, consumed by the stop gate, the
#               landing gate and the stand-down helper. Until epic-16 wave-02 S9 each of
#               those three opened the ledger itself through a byte-identical copy of a
#               `ledger_acked()` reader, and this section pinned the three bodies against
#               each other — the §9 convention, with the drift risk that convention always
#               carries. S9 promoted the answer onto the verdict machine line as `acked=`,
#               so the ledger now has ONE reader in the fleet: the file that owns it. The
#               three consumers read a field off a line they were already invoking the verb
#               to get.
#   the ORDER — written by `hooks/stop-orders.sh order`, read by the stop gate. Writer and
#               reader each hold the validity window as a literal.
#
# Per-component suites drive each consumer against its own fixtures. What none of them can
# see is the CROSS-SCRIPT property: that no consumer carries an ack-reading of its own, that
# the window is the same number, and that all three answer the same about one ledger the
# real writer wrote — including when the single owner is mutated to lie (§M.5).

SG_M="$REPO_ROOT/hooks/stop-guard.sh"
LG_M="$REPO_ROOT/hooks/landing-gate.sh"
SO_M="$REPO_ROOT/hooks/stop-orders.sh"

# --- M.1 ONE OWNER: no consumer reads the ledger, in any of the three ways it could ---
#
# The extractor is checked against a function that DOES survive, so an emptied `fn_body`
# result below means "the reader is gone" rather than "the extractor stopped working".
expect_eq "the extractor still finds a live function in the stop gate (not vacuous)" "yes" \
  "$([ -n "$(fn_body "$SG_M" take_verdict)" ] && echo yes || echo no)"
for _m in "$SG_M" "$LG_M" "$SO_M"; do
  expect_eq "$(basename "$_m") carries no ledger_acked() of its own" "" \
    "$(fn_body "$_m" ledger_acked)"
  # Defining the reader is one way back; building the ledger's PATH is the other, and it is
  # the one an edit reaches first. `sweeper-$` is how all three used to spell it.
  expect_eq "…and never builds the ack ledger's path" "0" \
    "$(grep -cF 'sweeper-$' "$_m")"
  # And the ack EVENT itself: a grep against the ledger would need this literal.
  expect_eq "…and never matches the ack event itself" "0" \
    "$(grep -cF 'event=ack' "$_m")"
done

# --- M.2 one window, two holders ---
_ttl_of() { grep -E '^ORDER_TTL_SECONDS=' "$1" | head -1 | cut -d= -f2; }
expect_eq "the order window is a number at all" "yes" \
  "$([ -n "$(_ttl_of "$SO_M")" ] && echo yes || echo no)"
expect_eq "the order's WRITER and the gate that READS it hold one window" \
  "$(_ttl_of "$SO_M")" "$(_ttl_of "$SG_M")"

# --- M.3 one ledger, written by the real ack verb, read the same by all three ---
MREPO=$(new_repo "ack-agreement")
MSLUG=$(printf '%s' "$MREPO" | sed 's/[^a-zA-Z0-9]/-/g')
MPROJ="$CLAUDE_CONFIG_DIR/projects/$MSLUG"
MSUB="$MPROJ/$SID_A/subagents"
mkdir -p "$MSUB" "$MREPO/.bionic/tmp"
MTR="$MPROJ/$SID_A.jsonl"
printf '{}\n' > "$MTR"
plant "$MSUB" "afinished-1111111111111111" "finished"
write_plan "$MREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
# A contract that will NEVER land: the artifact is not written, so every party's verdict is
# UNMET and the ack is the only thing that can discharge anything. A fixture whose contract
# landed would agree for the wrong reason.
printf 'roster-state/v1|status=confirmed|session=%s|name=finished|agent_id=afinished-1111111111111111|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=.bionic/docs/record/never.md|duration=|progress=|absent=|waiver=|teammate_id=finished@session-%s|tool_use_id=toolu_01FIXTURE\n' \
  "$SID_A" "$(printf '%s' "$SID_A" | cut -c1-8)" \
  >> "$MREPO/.bionic/tmp/roster-$SID_A.state"

# The landing sweep answers for each row ONCE, ever, and journals a marker into the roster
# to keep that promise. Each of the three drives below is a separate question about the same
# fixture, so the marker is cleared first — the property under test is what the consumers
# read off ONE ledger, not the sweep's idempotency (which hooks/landing-gate.test.sh owns).
MROSTER="$MREPO/.bionic/tmp/roster-$SID_A.state"
m_sweep() {  # <gate path> -> the gate's exit status, refusal on stdout
  /usr/bin/grep -v '^landing-swept/' "$MROSTER" > "$MROSTER.tmp" 2>/dev/null
  mv "$MROSTER.tmp" "$MROSTER"
  mk_stopsweep_payload "$MREPO" "$SID_A" false | bash "$1" 2>&1
}

m_vline() {  # -> the verdict machine line all three consumers read for this fixture
  ( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict finished 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1
}

# BEFORE the ack — all three say the row is open. This is the paired positive without which
# the three assertions after it would pass over a fixture nothing could ever block.
expect_contains "before the ack: the one line all three read says acked=no" \
  "|acked=no|" "$(m_vline)"
OUT=$(mk_stop_payload "$SID_A" "$MTR" "$MREPO" "finished" | bash "$SG_M" 2>&1); ST=$?
expect_eq "before the ack: the stop gate refuses" "2" "$ST"
OUT=$(m_sweep "$LG_M"); ST=$?
expect_eq "before the ack: the landing gate refuses" "2" "$ST"
OUT=$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" standdown 2>&1 )
expect_contains "before the ack: the stand-down leaves it alone" "LEFT ALONE" "$OUT"

# THE REAL WRITER writes the one file all three read.
( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" ack finished ) >/dev/null 2>&1
expect_eq "the ack verb wrote its ledger where its one reader looks" "yes" \
  "$([ -f "$MREPO/.bionic/tmp/sweeper-$SID_A.state" ] && echo yes || echo no)"

# THE PROMOTION, end to end over the real writer: the same line now says acked=yes, and the
# STATE beside it did not move. The ack changed what the consumers know, not what the disk
# says — which is what "the ack's semantics are unchanged" means concretely.
M_VLINE=$(m_vline)
expect_contains "after the ack: the one line all three read says acked=yes" "|acked=yes|" "$M_VLINE"
expect_contains "…while the contract itself is still UNMET, computed from the disk alone" \
  "|state=UNMET|" "$M_VLINE"

OUT=$(mk_stop_payload "$SID_A" "$MTR" "$MREPO" "finished" | bash "$SG_M" 2>&1); ST=$?
expect_eq "after the ack: the stop gate passes" "0" "$ST"
OUT=$(m_sweep "$LG_M"); ST=$?
expect_eq "after the ack: the landing gate passes" "0" "$ST"
OUT=$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" standdown 2>&1 )
expect_contains "after the ack: the stand-down puts it in the batch" "1 row(s) have landed" "$OUT"
expect_contains "…addressed the way the stop primitive takes it" \
  "finished@session-$(printf '%s' "$SID_A" | cut -c1-8)" "$OUT"

# --- M.3b ONE OWNER, PROVEN BY MUTATION: blind the field, all three go back to holding ---
#
# What the three-copy pin used to buy was drift detection between the copies. With the
# copies gone that proof has to be replaced rather than dropped, and this is the stronger
# form of it: the three consumers are byte-identical copies of what ships, only the OWNER is
# mutated — to report every row unacked — and all three answers move together. A consumer
# that had kept a private reader would stay green here, which is exactly the regression
# §M.1's greps cannot catch on their own (a reader spelled some other way).
#
# The mutant is installed in its own directory beside the gates, which is how bootstrap's
# flat `hooks/*.sh` install lets each of them find its sibling — the production resolution,
# not a test seam.
MMUT="$SANDBOX/ack-mutant"
mkdir -p "$MMUT"
cp "$SG_M" "$MMUT/stop-guard.sh"
cp "$LG_M" "$MMUT/landing-gate.sh"
cp "$SO_M" "$MMUT/stop-orders.sh"
awk '{ if (index($0, "row_acked \"$_pname\"") > 0) $0 = "    _acked=no"
       print }' "$SWEEPER" > "$MMUT/session-sweeper.sh"
if cmp -s "$SWEEPER" "$MMUT/session-sweeper.sh"; then
  no "the acked= mutation applies to session-sweeper.sh" \
     "the mutation target matched nothing — the code moved and this proof is vacuous"
else
  ok "the acked= mutation applies to session-sweeper.sh"
fi
expect_contains "the mutated owner reports the acked row as unacked" "|acked=no|" \
  "$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$MMUT/session-sweeper.sh" verdict finished 2>/dev/null )"
OUT=$(mk_stop_payload "$SID_A" "$MTR" "$MREPO" "finished" | bash "$MMUT/stop-guard.sh" 2>&1); ST=$?
expect_eq "…and the stop gate refuses the stop it passed a moment ago" "2" "$ST"
OUT=$(m_sweep "$MMUT/landing-gate.sh"); ST=$?
expect_eq "…and the landing gate refuses it too" "2" "$ST"
OUT=$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$MMUT/stop-orders.sh" standdown 2>&1 )
expect_contains "…and the stand-down puts it back in LEFT ALONE" "LEFT ALONE" "$OUT"
# The shipped files were never touched: the substitution is by path, and this says so.
expect_eq "the three shipped consumers are byte-identical to before the mutation" "" \
  "$(cmp -s "$SG_M" "$MMUT/stop-guard.sh" || echo differs
     cmp -s "$LG_M" "$MMUT/landing-gate.sh" || echo differs
     cmp -s "$SO_M" "$MMUT/stop-orders.sh" || echo differs)"

# --- M.4 the order: one writer, one reader, one boundary ---
_now=$(date -u +%s)
_ttl=$(_ttl_of "$SO_M")
# JUST INSIDE the window and JUST OUTSIDE it, placed by arithmetic rather than by waiting:
# a suite that slept through a thirty-minute window would not be a suite. The pair is what
# makes this an assertion about the boundary rather than about the happy path.
# A FRESH WORLD, and no ack in it: the row above is acked, so an order placed there would
# be discharged by the ack whatever the window said, and the boundary would go untested
# while looking green.
mk_order_world() {  # <label> <name> <agent-id> -> "<repo>|<transcript>"
  local repo tr slug proj sub
  repo=$(new_repo "$1")
  slug=$(printf '%s' "$repo" | sed 's/[^a-zA-Z0-9]/-/g')
  proj="$CLAUDE_CONFIG_DIR/projects/$slug"
  sub="$proj/$SID_A/subagents"
  mkdir -p "$sub" "$repo/.bionic/tmp"
  tr="$proj/$SID_A.jsonl"
  printf '{}\n' > "$tr"
  plant "$sub" "$3" "$2"
  write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
  roster_row "$repo" "$SID_A" "$2" "$3"
  printf '%s|%s\n' "$repo" "$tr"
}

IFS='|' read -r IN_REPO IN_TR <<< "$(mk_order_world "order-inside" "inside" "ainside-1111111111111111")"
( cd "$IN_REPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" order inside --at $((_now - _ttl + 60)) ) >/dev/null 2>&1
OUT=$(mk_stop_payload "$SID_A" "$IN_TR" "$IN_REPO" "inside" | bash "$SG_M" 2>&1); ST=$?
expect_eq "an order inside the shared window discharges the stop" "0" "$ST"
expect_contains "…reporting what is given up rather than refusing" "STOP ORDERED" "$OUT"

IFS='|' read -r EX_REPO EX_TR <<< "$(mk_order_world "order-expiry" "expired" "aexpired-2222222222222222")"
( cd "$EX_REPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" order expired --at $((_now - _ttl - 60)) ) >/dev/null 2>&1
OUT=$(mk_stop_payload "$SID_A" "$EX_TR" "$EX_REPO" "expired" | bash "$SG_M" 2>&1); ST=$?
expect_eq "an order just outside it does not — the ceremony is where it was" "2" "$ST"

# ============================================================
echo ""
echo "=== N — the wave-02 facts: one root, one vocabulary, one launch reference (S9) ==="
# ============================================================
#
# Six rows specified by the slices that could not add them: `record/w2-s45-wallfacts.md` §6
# (the wall and the probe became one preflight, and duplicated the root resolver a fourth
# time doing it) and `record/w2-s6-launchref.md` §6 (the launch reference stopped being
# re-stamped on resume, in a file whose readers live elsewhere). Each is a property no
# single-component suite can see, because in each case the writer and the reader are
# different scripts.
#
# WHAT IS DEFERRED, and named rather than quietly dropped: w2-s6 §6 row 3, teammate-mode
# resume driven end to end. It needs a real repeated `teammate_spawned` PostToolUse capture —
# the same payload delivered twice for one agent — and no such capture exists on disk. The
# suite's `mk_agent_post_teammate` is faithful to a SINGLE spawn (capture probe §3-A); a
# second one synthesized here would be this suite asserting against its own guess about what
# a resume looks like in that mode, which is the fixture-fidelity failure the header forbids.
# The async half of the same property IS driven, at §N.6.

# -------------------------------------------------------------- N.1 seven bodies, one root
#
# `resolve_project_root()` is a SEVEN-copy family: FOUR since S4+S5 (w2-s45 §5 call 7) — the
# governing-skill hook is the origin, the evidence gate its long-standing twin, and the
# dispatch wall and the probe took copies when R5 made the wall run the probe inline — plus
# TWO MORE from epic-16 w2 Step-6 remediation R3 (ap review A-1): the poker and stop-orders
# used to answer `git rev-parse --show-toplevel`, which names a worktree's own root rather
# than the main repository the roster lives under, and DISARM is terminal by doctrine once
# a tick takes that wrong answer. Extending this loop rather than adding a second one is
# what keeps D-2's "exactly four copies, no fifth" pin from failing on this wave's own fix
# — the critic named the trap by number (remediation-trap analysis #4): a resolver swap
# that does not extend the agreement test manufactures a fresh duplication finding in the
# act of closing A-1. The SEVENTH joined for the same reason as the sixth
# (session-20260815-landing-supervision T6): hooks/agent-context-guard.sh decides whether
# a session is armed by stating a roster under the project root, and a guard that rooted a
# worktree at its own tree would answer "unarmed" for every agent context inside a worktree
# of an armed session — a wall that goes quiet exactly where it was added to bind.
DP_N="$REPO_ROOT/hooks/dispatch-preflight.sh"
PB_N="$REPO_ROOT/hooks/preflight-probe.sh"
GS_N="$REPO_ROOT/hooks/canonical-sdlc-governing-skill.sh"
EG_N="$REPO_ROOT/hooks/canonical-sdlc-evidence-gate.sh"
SP_N="$REPO_ROOT/hooks/session-poker.sh"
SO_N="$REPO_ROOT/hooks/stop-orders.sh"
ACG_N="$REPO_ROOT/hooks/agent-context-guard.sh"

expect_eq "the root resolver extracts at all (this section is not vacuous)" "yes" \
  "$([ -n "$(fn_body "$GS_N" resolve_project_root)" ] && echo yes || echo no)"
for _n in "$DP_N" "$PB_N" "$EG_N" "$SP_N" "$SO_N" "$ACG_N"; do
  expect_eq "$(basename "$_n")'s resolve_project_root() is the origin's, body for body" \
    "$(fn_body "$GS_N" resolve_project_root)" "$(fn_body "$_n" resolve_project_root)"
done

# -------------------------------------------------------------- N.2 seven ANSWERS, one root
#
# Bodies being equal is a claim about the text. This is the claim about the ANSWER, taken
# where the field case took it: inside a real `git worktree add`, which is the input that
# separates a resolver that maps a worktree onto its main repository from one that does not.
# Each function is extracted from its own shipped file and run in its own subshell, so four
# definitions of one name cannot shadow each other.
NREPO="$SANDBOX/fx/nroot/repo"
mkdir -p "$NREPO"
git -C "$NREPO" init -q 2>/dev/null
git -C "$NREPO" config user.email t@example.com
git -C "$NREPO" config user.name "T"
echo seed > "$NREPO/README.md"
git -C "$NREPO" add README.md >/dev/null 2>&1
git -C "$NREPO" commit -qm seed >/dev/null 2>&1
NWT="$SANDBOX/fx/nroot/wt"
git -C "$NREPO" worktree add -q -b n-root-wt "$NWT" >/dev/null 2>&1
expect_eq "fixture: a real git worktree exists (never a mocked path)" "yes" \
  "$([ -e "$NWT/.git" ] && echo yes || echo no)"

root_via() {  # <file> <path-inside-the-tree> [fallback] -> that file's answer
  local f="$1" p="$2" fb="${3:-}"
  ( eval "$(awk '/^resolve_project_root\(\)/,/^\}/' "$f")"
    resolve_project_root "$p" "$fb" ) 2>/dev/null
}

NMAIN=$(cd "$NREPO" && pwd -P)
# Deep inside the worktree AND deep inside a directory that does not exist yet — a
# PreToolUse gate meets the second shape on the first artifact write into a project, and
# the climb-to-the-nearest-existing-ancestor is the part of the resolver that handles it.
for _p in "$NWT/.bionic/docs/record/x.md" "$NWT/deep/not/created/yet/x.md"; do
  for _n in "$GS_N" "$EG_N" "$DP_N" "$PB_N" "$SP_N" "$SO_N" "$ACG_N"; do
    expect_eq "$(basename "$_n") roots '${_p#$NWT/}' at the MAIN repository, not the worktree" \
      "$NMAIN" "$(cd "$NWT" && root_via "$_n" "$_p")"
  done
done
# The paired negative: outside any repository all seven fall back, and to the SAME fallback.
# Without it the seven could agree by having all stopped resolving anything.
NOUT="$SANDBOX/fx/nroot/notarepo"
mkdir -p "$NOUT"
for _n in "$GS_N" "$EG_N" "$DP_N" "$PB_N" "$SP_N" "$SO_N" "$ACG_N"; do
  expect_eq "$(basename "$_n") falls back outside any repository" \
    "$NOUT" "$(cd "$NOUT" && root_via "$_n" "$NOUT/x.md" "$NOUT")"
done

# --------------------------------------- N.2b no-git fallback follows the TARGET, not the shell
#
# session-20260812-bionic-root-pin: outside any git repository, the fallback used to answer
# `pwd` unconditionally — the pin followed the SHELL's cwd, not the project the target path
# actually named (live repro: .bionic/docs/record/session-20260812-bionic-root-pin/
# ac1-red-live.md). The fix walks up from the nearest existing ancestor of the target path
# for the nearest directory that already carries a `.bionic/` tree and answers there; only
# when none exists does the supplied fallback remain. NBWS is a non-git workspace carrying a
# real `.bionic/` — never `git init`'d, which is the point: this is the arm the two
# git-derived checks above never reach.
NBWS="$SANDBOX/fx/nroot/bws"
mkdir -p "$NBWS/.bionic/docs/record"
mkdir -p "$NBWS/sub"
expect_eq "fixture: NBWS carries a real .bionic/ and is NOT a git repository" "yes-nogit" \
  "$([ -d "$NBWS/.bionic" ] && ! git -C "$NBWS" rev-parse --show-toplevel >/dev/null 2>&1 \
       && echo yes-nogit || echo no)"
# Asked from $NOUT — a directory unrelated to NBWS and itself outside any repository, so a
# resolver that answered `pwd` (the old bug) would land on $NOUT, not $NBWS.
for _p in "$NBWS/.bionic/docs/record/x.md" "$NBWS/sub/deep/not/created/yet/x.md"; do
  for _n in "$GS_N" "$EG_N" "$DP_N" "$PB_N" "$SP_N" "$SO_N" "$ACG_N"; do
    expect_eq "$(basename "$_n") roots '${_p#$NBWS/}' at NBWS from an unrelated cwd, not the fallback" \
      "$NBWS" "$(cd "$NOUT" && root_via "$_n" "$_p" "$NOUT")"
  done
done

# ONE-COPY MUTATION GOES RED, the §A2 discipline applied to this family: drop the
# `--git-common-dir` half from a copy of the wall's resolver and it answers the WORKTREE —
# the pre-R9 behaviour, and the one that made a worktree its own address space.
N_MUT_ROOT="$SANDBOX/fx/rootless-preflight.sh"
awk '{ if (index($0, "--path-format=absolute --git-common-dir") > 0 || index($0, "--git-common-dir 2") > 0)
         sub(/--git-common-dir/, "--show-toplevel")
       print }' "$DP_N" > "$N_MUT_ROOT"
if cmp -s "$DP_N" "$N_MUT_ROOT"; then
  no "the root mutation applies to dispatch-preflight.sh" \
     "the mutation target matched nothing — the resolver moved and this proof is vacuous"
else
  ok "the root mutation applies to dispatch-preflight.sh"
fi
expect_eq "a resolver that stops mapping worktrees no longer answers the main repository" "no" \
  "$([ "$(cd "$NWT" && root_via "$N_MUT_ROOT" "$NWT/.bionic/docs/record/x.md")" = "$NMAIN" ] \
     && echo yes || echo no)"

# ------------------------------------------- N.3 producer and consumer, one attestation path
#
# w2-s45 §6 row 2. The probe WRITES the attestation and the dispatch wall READS it, and since
# R5 the wall runs the probe itself when it finds none. From a worktree cwd those two paths
# are only equal because both sides resolve the root the same way — the inequality that would
# silently re-break the combined preflight, and it would present as a wall that auto-probes on
# every single dispatch while an attestation sits on disk one directory over.
#
# The credential is pinned PRESENT (a syntactic placeholder — the probe tests presence, never
# validity) for the reason §D records: unpinned, the probe consults the machine login keychain
# and the drive lands on the refused path or the accepted one depending on whose machine runs
# the suite. Only the accepted path writes anything, which is the path under test here.
write_plan "$NREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
NENV=(env HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"
      ANTHROPIC_API_KEY="pinned-placeholder-not-a-credential")

( cd "$NWT" && "${NENV[@]}" CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PROBE" ) >/dev/null 2>&1
NATT="$NREPO/.bionic/tmp/preflight-$SID_A.state"
expect_eq "the PRODUCER, run from the worktree, writes under the main repository" "yes" \
  "$([ -f "$NATT" ] && echo yes || echo no)"
expect_eq "…and leaves no phantom .bionic in the worktree (R9: one address space)" "no" \
  "$([ -e "$NWT/.bionic" ] && echo yes || echo no)"

# THE CONSUMER, from the same worktree cwd. It must FIND that record — the observable is the
# absence of the auto-probe announce line, which the wall prints only when it had to take an
# attestation of its own. A wall that looked in the worktree would announce every time.
N_OUT=$(mk_agent_payload "$SID_A" "$NWT" | "${NENV[@]}" bash "$PARTY_DP" 2>&1); N_ST=$?
expect_eq "the CONSUMER, from the same worktree, passes the dispatch" "0" "$N_ST"
expect_absent "…without re-taking an attestation it already had" \
  "the environment check was run automatically" "$N_OUT"
expect_eq "…and its roster row landed under the main repository too" "yes" \
  "$([ -f "$NREPO/.bionic/tmp/roster-$SID_A.state" ] && echo yes || echo no)"
expect_eq "…with no phantom .bionic in the worktree from the gate either" "no" \
  "$([ -e "$NWT/.bionic" ] && echo yes || echo no)"

# THE DISCRIMINATING HALF: remove the record and the same dispatch announces. Without it the
# assertions above would pass over a wall that had simply stopped announcing anything.
rm -f "$NATT"
N_OUT=$(mk_agent_payload "$SID_A" "$NWT" | "${NENV[@]}" bash "$PARTY_DP" 2>&1); N_ST=$?
expect_eq "with the record gone the dispatch still passes (R5: attestation never blocks)" "0" "$N_ST"
expect_contains "…and says it took one automatically" \
  "the environment check was run automatically" "$N_OUT"
expect_eq "…writing it back to the same path the consumer reads" "yes" \
  "$([ -f "$NATT" ] && echo yes || echo no)"

# --------------------------------------------------- N.4 source=: one word, and one reader
#
# w2-s45 §6 row 3, RE-EXPRESSED at R1 (inference withdrawn — plan assumption 48). Wave-02 R4
# let `hooks/dispatch-preflight.sh` write `source=inferred` for a deliverable it GUESSED from
# prose; the Step-6 critic (N-1) showed the guess was then enforced with a declared fact's
# full weight, so Chris withdrew inference. The wall now writes `source=` with exactly one
# non-empty value, `declared`. `hooks/session-sweeper.sh` is still its only reader, branching
# on `!= "inferred"` — a branch that is now always true (no writer emits `inferred`), harmless,
# and left in place because touching the sweeper is outside R1's file set. One word, one reader.
N_SRC_VALUES=$(grep -oE '^[[:space:]]*C_SOURCE="[a-z]*"' "$DP_N" \
  | sed -E 's/.*"([a-z]*)"/\1/' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//')
expect_eq "the writer's vocabulary is one word" "declared" "$N_SRC_VALUES"
expect_eq "…and the sweeper is the only script that reads the field" "1" \
  "$(grep -rlF 'line_field "$row" source' "$REPO_ROOT/hooks" | grep -c .)"
expect_eq "…reading it exactly once" "1" "$(grep -cF 'line_field "$row" source' "$SWEEPER")"

# Driven, not just grepped: three briefs, three routes to a path, and what the writer does with
# each now that it never guesses. A LABELED slot-free path is `declared` and lands; an UNLABELED
# prose path and a TEMPLATED `<slot>` are both REFUSED at dispatch (exit 2, no roster row) —
# the withdrawal, asserted from the writer's own output in the paired exit-AND-inventory shape.
NSRC=$(new_repo "source-vocab")
write_plan "$NSRC/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
# Run in the CURRENT shell (never a command-substitution subshell) so the wall's own exit
# code survives to the assertion; read the roster row in a separate step.
n_dispatch() {  # <name> <prompt> — runs the wall in this shell; its exit is the function's exit
  jq -n --arg s "$SID_A" --arg c "$NSRC" --arg n "$1" --arg p "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:"implementor", name:$n, prompt:$p},
      tool_use_id:("toolu_01" + $n)}' \
    | "${NENV[@]}" bash "$PARTY_DP" >/dev/null 2>&1
}
n_row() { grep -F "|name=$1|" "$NSRC/.bionic/tmp/roster-$SID_A.state" 2>/dev/null | tail -1; }

n_dispatch declaring 'Expected artifact: .bionic/docs/record/declared.md'; N_ST=$?
expect_eq "a LABELED slot-free path passes the wall" "0" "$N_ST"
expect_contains "…and records source=declared" "|source=declared|" "$(n_row declaring)"
n_dispatch inferring 'the notes go in .bionic/docs/record/inferred.md when done'; N_ST=$?
expect_eq "an UNLABELED record/ path is REFUSED at dispatch (no inference)" "2" "$N_ST"
expect_eq "…and writes no roster row" "" "$(n_row inferring)"
n_dispatch filling 'Expected artifact: .bionic/docs/record/<name>.md'; N_ST=$?
expect_eq "a TEMPLATED <slot> path is REFUSED at dispatch (no fill)" "2" "$N_ST"
expect_eq "…and writes no roster row" "" "$(n_row filling)"

# ------------------------------------------------- N.5 the ghost row, asked of every writer
#
# w2-s45 §6 row 4. AC-12's "a refused dispatch leaves no row" is pinned in the wall's own
# suite, where the wall is the only writer in the room. The roster has THREE writers, and the
# other two are stop-side: a refused dispatch that later drew a row from `execution-recorder`
# would be a ghost with a different author, invisible to the wall's own before/after check.
#
# The recorder's two roster arms both key on a row the LAUNCH half wrote — ARM 2 on a matching
# `intended` row for the tool_use_id, ARM 3 on a matching intended/confirmed row for the name.
# A refused dispatch wrote neither, so both must find nothing and write nothing. In the field
# the tool call never runs at all (the wall exits 2), which is exactly why the defensive
# question is worth asking here rather than assuming the ordering holds.
NGH=$(new_repo "ghost-row")
write_plan "$NGH/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
mkdir -p "$NGH/.bionic/tmp"
# A brief naming NO inferable deliverable: the one shape R4 still refuses (AC-3's planted
# failure), and therefore the one that reaches this section with a refusal to leave no trace.
N_REFUSED=$(jq -n --arg s "$SID_A" --arg c "$NGH" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PreToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", subagent_type:"implementor", name:"ghosted",
                prompt:"Go and do the thing. Report back when you are finished."},
    tool_use_id:"toolu_01GHOST"}')
printf '%s' "$N_REFUSED" | "${NENV[@]}" bash "$PARTY_DP" >/dev/null 2>&1
N_WALL_ST=$?
expect_eq "the wall refuses a brief naming no inferable deliverable" "2" "$N_WALL_ST"
N_INV_BEFORE=$(cat "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null; echo "[no roster]")

# Now both stop-side writers, for the dispatch that never happened.
jq -n --arg s "$SID_A" --arg c "$NGH" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PostToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                run_in_background:true, name:"ghosted"},
    tool_response:{isAsync:true, status:"async_launched", agentId:"aghosted-1111111111111111"},
    tool_use_id:"toolu_01GHOST"}' | bash "$PARTY_ER" >/dev/null 2>&1
mk_start_payload "$SID_A" "/irrelevant.jsonl" "$NGH" "ghosted" "aghosted-1111111111111111" \
  | bash "$PARTY_ER" >/dev/null 2>&1
N_INV_AFTER=$(cat "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null; echo "[no roster]")
expect_eq "no stop-side writer manufactures a row for a dispatch the wall refused" \
  "$N_INV_BEFORE" "$N_INV_AFTER"
expect_eq "…and the sweeper has no contract to answer for either" "0" \
  "$( cd "$NGH" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict ghosted >/dev/null 2>&1; echo $? )"

# THE PAIRED POSITIVE, over the identical machinery: an ACCEPTED dispatch draws exactly one
# row from the wall and one more from each stop-side arm. Without it the three assertions
# above would pass over a recorder that had stopped writing rows at all.
printf '%s' "$N_REFUSED" \
  | jq '.tool_input.prompt = "Expected artifact: .bionic/docs/record/accepted.md"
        | .tool_input.name = "accepted" | .tool_use_id = "toolu_01ACCEPT"' \
  | "${NENV[@]}" bash "$PARTY_DP" >/dev/null 2>&1
expect_eq "an accepted dispatch draws exactly one row from the wall" "1" \
  "$(grep -cF '|name=accepted|' "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null)"
jq -n --arg s "$SID_A" --arg c "$NGH" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PostToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                run_in_background:true, name:"accepted"},
    tool_response:{isAsync:true, status:"async_launched", agentId:"aaccepted-2222222222222222"},
    tool_use_id:"toolu_01ACCEPT"}' | bash "$PARTY_ER" >/dev/null 2>&1
expect_eq "…and the recorder advances it rather than ignoring the roster" "1" \
  "$(grep -cF '|status=confirmed|' "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null)"

# ------------------------------------- N.6 the launch reference: written once, read by three
#
# w2-s6 §6 rows 1 and 2, driven as one arc because they are two halves of one property. The
# roster row is written by `hooks/dispatch-preflight.sh`, carried forward and pinned by
# `hooks/execution-recorder.sh`, and DATED AGAINST by `hooks/session-sweeper.sh` — three
# scripts, one field, and S6 could only prove the middle one from inside its own suite.
#
# THE FIELD-SHAPE HALF FIRST (row 2), because the rest is meaningless without it: a silent
# rename of `launched_at=` at the writer would make the pin scan for a key that no longer
# exists and FAIL OPEN — find nothing, treat every resume as a new agent, restore the exact
# bug S6 fixed, and stay green everywhere. This is what makes that rename fail loud.
n_row_keys() {  # <file> -> the keys the roster ROW template emits, in order
  grep -F 'ROW="roster-state/' "$1" | head -1 | tr '|' '\n' | sed -n 's/^\([a-z_]*\)=.*/\1/p' \
    | tr '\n' ' ' | sed 's/ $//'
}
N_KEYS=$(n_row_keys "$DP_N")
expect_contains "the writer's row template carries launched_at at all" "launched_at" "$N_KEYS"
expect_contains "…and the recorder's immutability helper scans for that exact spelling" \
  "launched_at" "$(fn_body "$REPO_ROOT/hooks/execution-recorder.sh" prior_launch_for_agent)"
expect_contains "…and the verdict dates its staleness conjunct against it" \
  'line_field "$row" launched_at' "$(cat "$SWEEPER")"
# Proven loud by mutation: rename the key at the writer and the first assertion above is the
# one that goes red, which is the point — the failure is a suite failure, not a silent
# fail-open at 3am.
N_MUT_DP="$SANDBOX/fx/renamed-preflight.sh"
awk '{ if (index($0, "ROW=\"roster-state/") > 0) gsub(/launched_at=/, "launchedat=")
       print }' "$DP_N" > "$N_MUT_DP"
if cmp -s "$DP_N" "$N_MUT_DP"; then
  no "the launched_at rename applies to dispatch-preflight.sh" \
     "the mutation target matched nothing — the row template moved and this proof is vacuous"
else
  ok "the launched_at rename applies to dispatch-preflight.sh"
fi
expect_absent "a renamed launched_at is CAUGHT, not silently tolerated" \
  "launched_at" "$(n_row_keys "$N_MUT_DP")"

# THE END-TO-END HALF (row 1): every writer real, every reader real, and the observable is the
# VERDICT rather than the roster row — which is the gap S6's own suite could not close, since
# it owns the recorder and not the thing that reads it.
NLR=$(new_repo "launch-ref")
write_plan "$NLR/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
NLR_ART="$NLR/.bionic/docs/record/resumed.md"
mkdir -p "$NLR/.bionic/docs/record"
NLR_ID="aresumed-3333333333333333"

n_cycle() {  # <tool_use_id> — one full dispatch cycle through all three real hooks
  jq -n --arg s "$SID_A" --arg c "$NLR" --arg u "$1" --arg d "$NLR_ART" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:"implementor", name:"resumed",
                  prompt:("Expected artifact: " + $d)},
      tool_use_id:$u}' | "${NENV[@]}" bash "$PARTY_DP" >/dev/null 2>&1
  jq -n --arg s "$SID_A" --arg c "$NLR" --arg u "$1" --arg a "$NLR_ID" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      hook_event_name:"PostToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                  run_in_background:true, name:"resumed"},
      tool_response:{isAsync:true, status:"async_launched", agentId:$a},
      tool_use_id:$u}' | bash "$PARTY_ER" >/dev/null 2>&1
  mk_start_payload "$SID_A" "/irrelevant.jsonl" "$NLR" "resumed" "$NLR_ID" \
    | bash "$PARTY_ER" >/dev/null 2>&1
}
n_state() {  # -> the verdict's state for the row, over the live roster
  ( cd "$NLR" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict resumed 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1 | tr '|' '\n' | grep '^state=' | cut -d= -f2-
}
n_latest_row() {  # -> the last row the real recorder wrote for this name
  grep -F '|name=resumed|' "$NLR/.bionic/tmp/roster-$SID_A.state" | tail -1
}
# THE READER, ASKED ABOUT ONE ROW. The row handed over is the REAL recorder's own output
# line, copied verbatim onto a fresh roster — not a hand-built fixture — because the
# discriminating question here is what a reader makes of the row the resume produced, and on
# the live roster that same reader answers AMBIGUOUS about the NAME (see below) whatever the
# row says. This is `latest_rows`' fold with the two-contract count removed, and nothing else.
n_state_of_row() {  # <roster row> -> the verdict's state for it alone
  local d="$SANDBOX/fx/lr-fold"
  rm -rf "$d"; mkdir -p "$d/.bionic/tmp"
  git -C "$d" init -q 2>/dev/null
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$d/.bionic/tmp/roster-$SID_A.state"
  printf '%s\n' "$1" >> "$d/.bionic/tmp/roster-$SID_A.state"
  ( cd "$d" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict resumed 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1 | tr '|' '\n' | grep '^state=' | cut -d= -f2-
}

n_cycle toolu_01CYCLEA
# THE ROSTER IS AGED, and only the roster: both cycles would otherwise be stamped in the same
# second and there would be no difference for the pin to preserve. An hour between a dispatch
# and its resume is the field case's own shape (`record/w1-rc-verify-floor.md` §Amendment-2),
# and every hook that reads these rows below is the real one reading a real row.
N_T0=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)
sed -i.bak -E "s/launched_at=[^|]*/launched_at=$N_T0/" "$NLR/.bionic/tmp/roster-$SID_A.state"
rm -f "$NLR/.bionic/tmp/roster-$SID_A.state.bak"
# The takeover's delivery: written between the original launch and the resume, which is the
# artifact the field case's landing gate called missing.
echo "the takeover wrote this" > "$NLR_ART"
touch -t "$(date -v-1800S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-1800 seconds" +%Y%m%d%H%M.%S)" "$NLR_ART"
expect_eq "before the resume, the delivered contract reads MET" "MET" "$(n_state)"

n_cycle toolu_01CYCLEB
N_RESUMED_ROW=$(n_latest_row)
expect_eq "the resume kept the ORIGINAL launch reference, through the real hooks" "$N_T0" \
  "$(printf '%s' "$N_RESUMED_ROW" | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)"
expect_eq "…and appended its own row rather than rewriting one" "2" \
  "$(grep -cF '|status=identified|' "$NLR/.bionic/tmp/roster-$SID_A.state")"
expect_eq "…so the reader still calls the delivered contract MET over that row" \
  "MET" "$(n_state_of_row "$N_RESUMED_ROW")"

# WHAT THE LIVE ROSTER SAYS, and it is not MET — recorded here because it is the thing no
# component suite could see, and because the honest answer is worth more than a green line.
#
# A resume through the real hook path is a SECOND Agent-tool cycle, so it writes a second
# `tool_use_id` under one name, and `verdict` counts contracts by distinct tool_use_id
# (wave-01 Step-6 review C-2: two dispatches sharing a name are indistinguishable to every
# reader downstream). The name therefore reads AMBIGUOUS, not MET, and no row is judged.
#
# THE FAIL DIRECTION IS THE SAFE ONE and that is why this is pinned rather than fixed here:
# the landing gate PASSES an AMBIGUOUS name (§J's `dup` row), so R6 holds — work delivered
# before a resume still cannot be read as undelivered, and the gate still cannot manufacture
# an UNMET over an artifact that exists. What is lost is only the sharpness of AC-5's "yields
# MET": through this route it yields "not judged". Reconciling C-2's contract count with S6's
# resume (same agent id, two tool_use_ids — arguably ONE contract resumed, not two dispatched)
# is a change to a wave-01 remediation and to S6's own keying rule, which is a cross-slice
# decision this slice surfaces rather than takes.
expect_eq "on the LIVE roster the resumed name reads AMBIGUOUS, not MET (recorded finding)" \
  "AMBIGUOUS" "$(n_state)"
expect_eq "…and AMBIGUOUS is the state the landing gate passes, so R6 still holds" "pass" \
  "$(printf '%s' "$J_CASES" | grep '^dup|' | cut -d'|' -f3)"

# THE DISCRIMINATING HALF, by mutation of the middle party: with the override removed the
# resume re-stamps, the artifact predates the fresh stamp, and the verdict manufactures the
# UNMET the field case actually suffered. This is the assertion that proves the three above
# are about the pin rather than about a fixture that could never have failed.
N_MUT_ER="$SANDBOX/fx/unpinned-recorder.sh"
awk '{ if (index($0, "PRIOR_LAUNCH=$(prior_launch_for_agent") > 0)
         sub(/prior_launch_for_agent/, "true prior_launch_for_agent")
       print }' "$REPO_ROOT/hooks/execution-recorder.sh" > "$N_MUT_ER"
if cmp -s "$REPO_ROOT/hooks/execution-recorder.sh" "$N_MUT_ER"; then
  no "the launch-pin mutation applies to execution-recorder.sh" \
     "the mutation target matched nothing — the code moved and this proof is vacuous"
else
  ok "the launch-pin mutation applies to execution-recorder.sh"
fi
n_saved_er="$PARTY_ER"; PARTY_ER="$N_MUT_ER"
n_cycle toolu_01CYCLEC
N_UNPINNED_ROW=$(n_latest_row)
expect_eq "with the pin removed the resume re-stamps the launch reference" "no" \
  "$([ "$(printf '%s' "$N_UNPINNED_ROW" | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)" \
      = "$N_T0" ] && echo yes || echo no)"
expect_eq "…and the reader then calls the SAME delivered artifact stale — the field case" \
  "UNMET" "$(n_state_of_row "$N_UNPINNED_ROW")"
PARTY_ER="$n_saved_er"

# ============================================================
echo ""
echo "=== O — session-poker's copied primitives, CODE-identical (6-axis D-1) ==="
# ============================================================
#
# hooks/session-poker.sh's own header declared five functions "DELIBERATELY DUPLICATED from
# hooks/session-sweeper.sh, byte for byte" and called parse_seconds's copy "verbatim" —
# rd review D-1 (blocking-grade): nothing anywhere compared a single copy, and the
# "verbatim" claim was already false. `parse_seconds`'s SWEEPER copy carries nine lines of
# internal rationale comments (why "0.5h" and "1h30m" are refused) that the POKER copy
# drops, because that rationale describes the sweeper's own history — reading `cadence=` —
# which this script never does; it reads `duration=` instead. The §I.1 precedent this loop
# follows already excludes SIGNATURE comments from its body comparison ("each file explains
# its copy in its own terms"); this loop goes one step further and excludes every
# pure-comment line inside the body too, because parse_seconds is the one primitive here
# whose internal comments are legitimately script-specific. What must not drift silently is
# the EXECUTABLE TEXT, so that is what is compared — epic-16 w2 Step-6 remediation R3, and
# the two header comments this closes (session-poker.sh:84-88, :109-111) now say exactly
# this: code-identical, not byte-identical (R-3).
SPO="$REPO_ROOT/hooks/session-poker.sh"

fn_code() {  # <file> <function name> -> fn_body with pure-comment lines stripped too
  fn_body "$1" "$2" | grep -v '^#'
}

expect_eq "the extractor returns code at all (this section is not vacuous)" "yes" \
  "$([ -n "$(fn_code "$SWEEPER" parse_seconds)" ] && echo yes || echo no)"
for _fn in now_epoch iso_now line_field clean parse_seconds; do
  expect_eq "the poker's ${_fn}() is the sweeper's, CODE for code" \
    "$(fn_code "$SWEEPER" "$_fn")" "$(fn_code "$SPO" "$_fn")"
done
# The discriminating half: parse_seconds is NOT byte-identical (the comments legitimately
# differ), which is the whole reason this loop compares code rather than bytes. Without this
# the five expect_eq's above could be silently vacuous by fn_code stripping everything.
expect_eq "…and parse_seconds is genuinely NOT byte-identical (comments differ, proving fn_code isn't vacuous)" \
  "no" "$([ "$(fn_body "$SWEEPER" parse_seconds)" = "$(fn_body "$SPO" parse_seconds)" ] && echo yes || echo no)"

# ============================================================
echo ""
echo "=== P — the three roster folds agree that the LATER row wins (ap review P-1) ==="
# ============================================================
#
# The roster is append-only and a contract advances along it (`intended` → `confirmed` →
# `identified`), every writer copying the contract fields forward — so the LAST row carrying
# a name is the authoritative one. Three scripts fold the file on that rule and none of them
# can share code with the others (there is no library in this repo by decision, and each
# fold answers its own caller: hooks/session-sweeper.sh latest_rows also counts contracts
# and filters by session; hooks/session-poker.sh takes one row by name; hooks/stop-orders.sh
# needs a whole batch at once and, since epic-16 w2 Step-6 remediation R4, folds ONCE
# instead of re-walking the file per verdict row — the fix for P-1, whose per-row re-walk
# cost ~14·N² processes and 63 s at N=100).
#
# A code-comparison loop like §O cannot hold these three together, because they are
# legitimately different code. This is the behavioural equivalent: ONE roster in which a
# name appears TWICE, and all three asked what they see. A fold that silently starts taking
# the FIRST row — the plausible drift, and the one an off-by-one in a rewrite produces —
# turns this section red in three places at once.
#
# Overridable for the same reason the parties at the top of this file are: the
# discrimination proof for this section is a MUTATED copy of one fold — made to take the
# first row instead of the last — driven against the same fixture, with the shipped files
# never touched. A mutant copy must sit in a directory that also carries session-sweeper.sh,
# since both scripts resolve it as a sibling:
#   W2_PARTY_ORD=/tmp/mut/stop-orders.sh bash tests/cross-gate-agreement.test.sh
PORD="${W2_PARTY_ORD:-$REPO_ROOT/hooks/stop-orders.sh}"
PPOKE="${W2_PARTY_POKE:-$REPO_ROOT/hooks/session-poker.sh}"
PREPO=$(new_repo "fold-agreement")
mkdir -p "$PREPO/.bionic/tmp" "$PREPO/.bionic/docs/record"
PROSTER="$PREPO/.bionic/tmp/roster-$SID_A.state"
P_LANDED="$PREPO/.bionic/docs/record/p-landed.md"
printf 'landed\n' > "$P_LANDED"
P_OLD=$(date -u -v-100000S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d '-100000 seconds' +%Y-%m-%dT%H:%M:%SZ)
P_NEW=$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d '-60 seconds' +%Y-%m-%dT%H:%M:%SZ)

p_row() {  # <name> <deliverable> <duration> <launched_at> <teammate_id>
  printf 'roster-state/v1|status=confirmed|session=%s|name=%s|agent_id=|launched_at=%s|subagent_type=implementor|model=opus|deliverable=%s|source=declared|duration=%s|progress=|claims=|cadence=|absent=|waiver=|teammate_id=%s|tool_use_id=toolu_P%s\n' \
    "$SID_A" "$1" "$4" "$2" "$3" "$5" "$1"
}

printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
  > "$PROSTER"
# dup-open: the EARLIER row would read as landed and unhurried (a delivered artifact, four
# hours to do it, launched a minute ago); the LATER row is the true contract and is neither.
p_row dup-open "$P_LANDED"                "4 hours"  "$P_NEW" "first@session-p"  >> "$PROSTER"
p_row dup-open "$PREPO/never-written.md"  "1 minute" "$P_OLD" "second@session-p" >> "$PROSTER"
# dup-landed: both rows have landed, so the row that wins is visible in the ADDRESS the
# stand-down prints — the one field standdown reads off the roster for a landed row.
p_row dup-landed "$P_LANDED" "4 hours" "$P_NEW" "first@session-p"  >> "$PROSTER"
p_row dup-landed "$P_LANDED" "4 hours" "$P_NEW" "second@session-p" >> "$PROSTER"

expect_eq "fixture: each name really is on the roster twice (this section is not vacuous)" \
  "2" "$(grep -c '|name=dup-open|' "$PROSTER")"

P_VERDICT=$( cd "$PREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict 2>/dev/null )
# PARTY 1 — the sweeper latest_rows. The earlier row points at a file that EXISTS; reading
# it would make this row MET.
expect_contains "the sweeper judges dup-open from the LATER row (UNMET, not the earlier landed one)" \
  "|name=dup-open|state=UNMET|" "$P_VERDICT"
expect_contains "…and its detail names the LATER row deliverable" \
  "never-written.md" "$P_VERDICT"

# PARTY 2 — the poker per-row lookup. `duration=`/`launched_at=` come from the roster, not
# from the verdict line: the earlier row (four hours, launched a minute ago) is nowhere near
# due, the later one (one minute, launched a day ago) is long past.
P_TICK=$( cd "$PREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PPOKE" tick 2>&1 )
expect_contains "the poker reads dup-open duration off the LATER row (NOTIFY, not QUIET)" \
  "decision=NOTIFY" "$P_TICK"
expect_contains "…naming that row" "rows=dup-open" "$P_TICK"

# PARTY 3 — stop-orders single pre-loop fold. Both dup-landed rows have landed, so the
# stand-down prints an address, and the address is the discriminator.
P_STAND=$( cd "$PREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PORD" standdown 2>&1 )
expect_contains "the stand-down addresses dup-landed by the LATER row teammate id" \
  "second@session-p   (met — dup-landed)" "$P_STAND"
expect_absent "…and never by the earlier one" "first@session-p" "$P_STAND"
# The stand-down must still leave the unlanded row alone, folded or not.
expect_contains "…while dup-open is left alone, not stood down" "LEFT ALONE" "$P_STAND"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "cross-gate-agreement: ${PASS} passed, ${FAIL} failed, ${TOTAL} total"
[ "$FAIL" -eq 0 ]
