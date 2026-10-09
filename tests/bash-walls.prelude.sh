# tests/bash-walls.prelude.sh — the shared half of the two bash-walls suites
# (wave-30 T9, D8). NOT A SUITE: the name does not end in `.test.sh`, so the roster glob
# never launches it.
#
# tests/bash-walls.test.sh (the composition and every wall's arms) and
# tests/bash-walls-egd.test.sh (the §EG-DERIVE sections, held out of the parallel batch
# because they carry wall-clock bounds) each source this file. It holds what both read: the
# jq and hook guards, the sandbox, the session constants, the fixture repository and payload
# builders, the hook runner and its readers, and §EG-6's plan writer and gate drive that
# §EG-DERIVE builds on (moved here, not copied).
#
# A SUITE SETS `HOOK=` BEFORE SOURCING THIS FILE, in its own text (so the impact map reaches
# the hook from each suite), and sources it BEFORE tests/lib/assert.sh: assert.sh derives, at
# its own load, every `expect_*` the suite calls and refuses one that is neither defined yet
# nor defined in that file. Nothing below calls `ok`/`no`/`section` at load time.

command -v jq >/dev/null 2>&1 || { echo "bash-walls: jq absent — suite cannot run"; exit 1; }

# NOT VACUOUS. Most assertions below read a refusal off a stream, but several read
# SILENCE — and a HOOK path that names nothing is silent too, at exit 127. A suite whose
# seam is wrong must stop rather than report the walls behaving.
[ -f "$HOOK" ] || { echo "bash-walls: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "bash-walls: $HOOK does not parse — suite refuses to run"; exit 1; }

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/bash-walls-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="5f4e3d2c-1b0a-4998-8877-665544332211"
ACTOR="at23writer-9f8e7d6c5b4a3210"
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"

FM='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: single
scale: wave
deploy_target: none
use_worktree: false
has_ui: false
---'

# ---------- fixtures ----------

# mk_repo <name> [engaged: yes|no] — a git repo on a feature branch, engaged by default.
#
# A REAL GIT INIT, because hooks/protect-main.sh asks `git symbolic-ref --short HEAD` for
# the current branch and a directory that is not a repo answers nothing — which would make
# its third arm silent for a reason this suite never chose.
mk_repo() {
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp" "$repo/.bionic/docs/plans" "$repo/.bionic/docs/record"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  git -C "$repo" checkout -q -b feature/t23 2>/dev/null
  printf 'generic fixture proof\n' > "$repo/.bionic/docs/record/generic-evidence.md"
  [ "${2:-yes}" = yes ] && : > "$repo/.bionic/tmp/engaged-$SID.state"
  bw_door "$repo" "${3:-with}"
  printf '%s' "$repo"
}

# bw_door <dir> [with|noonly|none] — what <dir>'s tests/run.sh is (wave-28 T54, D27). THE ONE DOOR
# fires only in a project whose runner takes `--only`, so a world is built WITH one by default (the
# project this suite's agent rows stand in is bionic's own shape); `noonly` is a runner of the
# project's own that takes no flag, and `none` is a project with suites and no runner at all.
bw_door() {
  mkdir -p "$1/tests"
  case "${2:-with}" in
    none)   rm -f "$1/tests/run.sh" ;;
    noonly) printf '#!/bin/bash\n# the project'"'"'s own runner: every suite, in order, no flags\nfor s in tests/*.test.sh; do bash "$s" || exit 1; done\n' > "$1/tests/run.sh" ;;
    *)      printf '#!/bin/bash\n# usage: tests/run.sh [--only <suite>.test.sh ...]\ncase "${1:-}" in --only) shift ;; esac\n' > "$1/tests/run.sh" ;;
  esac
}

# bw_bind <repo> — an ENGAGED session in <repo> is bound to the plan the case just wrote at
# `active.md` (wave-23-fixit-1810, REQ-1, D1). An empty marker beside an open plan is the
# unbound state, whose newest-plan fallback is announced and never acted on: the evidence
# gate would judge no commit at all. An unengaged repo stays unengaged.
bw_bind() {
  [ -f "$1/.bionic/tmp/engaged-$SID.state" ] || return 0
  bound_marker "$1" "$SID" "$1/.bionic/docs/plans/active.md"
}

# block_plan <repo> — a plan whose current step's evidence is a placeholder, so the
# evidence gate refuses any `git commit` made under it.
block_plan() {
  printf '%s\n' "$FM
# plan

## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z \"approved\"
Step 5: TODO" > "$1/.bionic/docs/plans/active.md"
  bw_bind "$1"
}

# arm_roster <repo> — the roster file agent-context-guard.sh required before it would let
# background-suite-guard run at all. Its PRESENCE is the whole predicate; no row is needed
# for the backgrounded-suite arm, which is the arm this suite drives.
arm_roster() { : > "$1/.bionic/tmp/roster-$SID.state"; }

# bw_dispatched <repo> <name> <key=value>... — ACTOR's launch row as the dispatch wall writes it,
# `agent_id=` EMPTY, on a fresh roster, and then ACTOR's own start through
# hooks/execution-recorder.sh, which is what writes the id (wave-27 T5, D15, AC-8.1). A row
# planted with the id already on it hid walk-triage-3's defect: the budget arm was only ever
# shown an id no hook had written.
REC_HOOK="${BIONIC_HOOKS_DIR}/execution-recorder.sh"
BW_TUID=0
bw_dispatched() {
  local repo="$1" name="$2"; shift 2
  BW_TUID=$((BW_TUID + 1))
  roster_header > "$repo/.bionic/tmp/roster-$SID.state"
  roster_row_fixture "session=$SID" status=intended "name=$name" agent_id= \
    subagent_type=bionic:test-runner "tool_use_id=toolu_01bwdisp$BW_TUID" \
    "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@" \
    >> "$repo/.bionic/tmp/roster-$SID.state"
  jq -n --arg s "$SID" --arg c "$repo" --arg a "$ACTOR" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      agent_id:$a, agent_type:"bionic:test-runner", hook_event_name:"SubagentStart"}' \
    | env HOME="$FAKE_HOME" BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" \
        CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash "$REC_HOOK" >/dev/null 2>&1
}

# mk_payload <cwd> <command> [agent_id] [run_in_background] [tool_name] [agent_type] [timeout]
#
# `agent_type` IS A SEPARATE FIELD FROM `agent_id` and the two walls read different ones:
# hooks/farm-out-reminder.sh leaves on a non-empty `agent_type` (it moves work OFF the
# orchestrator thread, so the thread it moved work TO must not be nudged), while the
# agent-context predicate is `agent_id`. A row that wants ONE wall to answer sets both.
#
# `timeout` (T3, REQ-3, D4): omitted by default, matching the CLI's own shape — the Bash
# tool input schema declares it optional and the harness drops the key rather than send a
# null (record/wave-13-fixit-180/research-R2-walls.md §4). A row driving the repair arm
# passes a bare integer string; `tonumber` gives it the JSON number type a real payload
# carries, not a quoted string a real one never would.
mk_payload() {
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" --arg a "${3:-}" \
        --arg bg "${4:-omit}" --arg t "${5:-Bash}" --arg at "${6:-}" --arg to "${7:-omit}" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:$t,
      tool_input:({command:$cmd}
                  + (if $bg == "omit" then {} else {run_in_background: ($bg == "true")} end)
                  + (if $to == "omit" then {} else {timeout: ($to | tonumber)} end)),
      tool_use_id:"toolu_01t23walls"}
     + (if $a == "" then {} else {agent_id:$a} end)
     + (if $at == "" then {} else {agent_type:$at} end)'
}

OUT=""; ERR=""; ST=0
run_hook() {  # <payload> [extra env assignments...]
  local payload="$1"; shift
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
          CLAUDE_PROJECT_DIR= "$@" bash "$HOOK" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# The three readers of the composed verdict. Each goes through jq or through an offset,
# never through a substring of the raw stream, so a test cannot pass on a malformed wire.
json_docs()   { printf '%s' "$OUT" | jq -s 'length' 2>/dev/null; }
deny_reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
context_of()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
# updated_timeout_of / has_updated_input — T3 readers. `has_updated_input` distinguishes
# "no updatedInput key at all" from "updatedInput.timeout happens to be empty", which
# `updated_timeout_of` alone cannot: both read "" from jq's `// empty`.
updated_timeout_of()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.timeout // empty' 2>/dev/null; }
has_updated_input()   { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.updatedInput' >/dev/null 2>&1 && echo yes || echo no; }
# updated_command_of — the rewritten command (wave-26 T7): the booking wrap, when one rode.
updated_command_of()  { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null; }
# line_of <regex> — the 1-based line of the first stderr line matching, or empty.
line_of()     { printf '%s\n' "$ERR" | awk -v re="$1" '$0 ~ re {print NR; exit}'; }

# ---------- §EG-6's plan writer and gate drive (also the base of §EG-DERIVE) ----------
EG6_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
eg6_reading() {  # <head> <question> <result> [<evidence>] -> one reading line
  bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" piece' \
    _ "$EG6_LIB" "$1" "${4:-record/w27/$2-$3.md}" "$2" "$3"
}
eg6_waiver() {  # <head> <question>
  bash -c '. "$1" && proof_waiver_line "$2" "$3" "T" 2026-10-04T12:00:00Z "ship it"' _ "$EG6_LIB" "$2" "$1"
}
eg6_plan() {  # <current> <scale> <lines> [<Step 6 line>] -> a double plan the gate admits at Step 6 bar the readings
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: %s\n' "$2"
  printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
  printf 'current: %s\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
  printf -- '- Step 4: dispatched, record/w27/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: feature/t23\n' "$H_EG6"
  printf -- '- Step 5: floor green, record/w27/floor.log\n'
  [ -n "${4:-}" ] && printf -- '%s\n' "$4"
  [ -n "$3" ] && printf '%s\n' "$3"
  printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
  printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
  printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
  printf '  tier-run: bash tests/x.test.sh\n  readback: the line it wrote\n'
}
R_EG6="$(mk_repo eg6)"
H_EG6="$(git -C "$R_EG6" rev-parse HEAD)"
eg6_gate() {  # <plan text> -> ST, ERR of a main-checkout commit
  printf '%s\n' "$1" > "$R_EG6/.bionic/docs/plans/active.md"
  bw_bind "$R_EG6"
  run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')"
}
