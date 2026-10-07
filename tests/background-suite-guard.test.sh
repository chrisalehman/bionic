#!/bin/bash
# Tests for hooks/background-suite-guard.sh — THE BUDGET ARM
# (wave-01 verification-cannot-lie, S13; spec AC-21; seed suite-allowance-wall.md item 3.)
#
# THE INCIDENT. Two dispatched writers finished their own work green at ~45 minutes and
# then spent 40 more re-running the whole tree, one suite at a time, in parallel, on an
# 8 GB machine at load 10. Their briefs said "run impacted suites only; never
# tests/run.sh; run X, Y, Z as consumers", and "consumers" was read as "everything". The
# Patrol notified both as overdue and they were killed by hand. Prose in a brief is a
# wish. This file tests the wall.
#
# WHAT IT COVERS. `hooks/dispatch-preflight.sh` records the budget on the roster row at
# launch — `suites_allowed=`, derived from the tree by the configured impact command or
# declared by the brief (tests/dispatch-preflight.test.sh §S27 owns that half). This file
# owns the other half: inside a dispatched agent, a suite invocation outside that set is
# refused, `tests/run.sh` is refused unless the row carries it, and `FARM_OUT_ALLOW=1`
# does not widen either.
#
# §WRAP (wave-26 T7, D8) owns the booking wrap: an allowed suite command, on any thread,
# comes back rewritten into payload/scripts/booked.sh, and the wrapped command behaves as
# the unwrapped one does when run the way the harness runs a Bash call.
#
# THE B-9 ARM IS NOT RE-TESTED HERE. The backgrounded-suite refusal this hook has carried
# since bionic 1.3.2 belongs to tests/cmd-class.test.sh §C4, which drives it through
# hooks/agent-context-guard.sh exactly as hooks.json registers it. What IS asserted here
# is the one interaction between them: which arm speaks when both apply.
#
# HERMETIC. Every payload is crafted and piped into the hook; repos are throwaway git
# inits under a mktemp'd sandbox, and HOME / CLAUDE_CONFIG_DIR / BIONIC_PLUGINS_DIR are
# all pointed inside it so the loader cannot reach this machine's installed plugin.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * PreToolUse|Bash payload envelope — the shape tests/cmd-class.test.sh pins, plus the
#     top-level `agent_id` measured for an agent context in
#     record/session-20260815-landing-supervision/t1-probe-report.md §3 (CLI 2.1.233).
#   * agent id VALUE — the transcript form measured there (`a<name>-<16 hex>`). The hook
#     never parses it; it compares it to the row.
#   * ROSTER ROWS — built through tests/lib/roster-row.sh, which delegates to the one
#     production writer (payload/scripts/lib/roster.sh). No row here is hand-typed, so a
#     field this suite believes in that the writer stopped emitting fails loudly.
#   * THE AGENT'S FIRST ROW — the dispatch wall's shape, `agent_id=` empty, with the id
#     written by hooks/execution-recorder.sh's start arm (`dispatched`, wave-27 T5). Only a
#     successor row (ARM 2's confirmation, an amend) is planted carrying the id.
#   * session ids, plan text — SYNTHESIZED.
#
# Usage: bash tests/background-suite-guard.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PAYLOAD_HOOKS="$REPO_ROOT/payload/hooks"
# A run of this suite may itself be inside a booked command; §WRAP measures an unbooked caller.
unset BIONIC_SLOT_HELD BIONIC_SLOT_PLACE BIONIC_SLOT_QUIET BIONIC_QUIET
# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23), and there is no
# longer a WRAPPER to drive through. This wall is `wall_background_suite_guard` in
# payload/scripts/lib/walls.sh, and the partition hooks/agent-context-guard.sh used to
# apply in front of it — an agent context, an armed session — is the first thing that
# function asks. A wrapper around the compound would have silenced protect-main,
# protect-database, the evidence gate and farm-out-reminder on every main-thread call,
# so the predicate moved inside and the wrapper's Bash-side registration is gone. The
# guard file itself stays, registered on SubagentStop, untouched.
GUARD="$PAYLOAD_HOOKS/bash-walls.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/bg-suite-guard-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

SID="4e2b9a17-55c8-4d0e-9b31-7f6a2c4e18d9"
ACTOR="as13writer-4c9f1e07ab32d650"
OTHER="as13other-1122334455667788"

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude/projects/-sandbox"
: > "$FAKE_HOME/.claude/projects/-sandbox/$SID.jsonl"

# ---------- fixtures ----------

# mk_repo <name> — an ENGAGED, ARMED repo with an empty roster (header only).
mk_repo() {
  local repo="$SANDBOX/$1/repo"
  mkdir -p "$repo/.bionic/tmp"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  # THE PROJECT HAS THE RUNNER'S DOOR (wave-28 T54): the one door fires only where tests/run.sh says --only,
  # so this world plants the same runner as tests/bash-walls.test.sh's bw_door, committed with the seed.
  mkdir -p "$repo/tests"; printf '#!/bin/bash\n# usage: tests/run.sh [--only <suite>.test.sh ...]\ncase "${1:-}" in --only) shift ;; esac\n' > "$repo/tests/run.sh"
  git -C "$repo" add README.md tests/run.sh
  git -C "$repo" commit -qm seed 2>/dev/null
  : > "$repo/.bionic/tmp/engaged-$SID.state"
  roster_header > "$repo/.bionic/tmp/roster-$SID.state"
  chmod 600 "$repo/.bionic/tmp/roster-$SID.state"
  printf '%s' "$repo"
}

# add_row <repo> <key=value>... — one more row on that repo's roster, through the writer.
add_row() {
  local repo="$1"; shift
  roster_row_fixture "session=$SID" "$@" >> "$repo/.bionic/tmp/roster-$SID.state"
}

# dispatched <repo> <agent id> <key=value>... — THE LAUNCH ROW AS THE DISPATCH WALL WRITES IT,
# then the agent's own start (wave-27 T5, D15, AC-8.1). The row is `status=intended` with
# `agent_id=` EMPTY, as hooks/dispatch-preflight.sh writes it; the id reaches the roster only
# through hooks/execution-recorder.sh's SubagentStart arm, driven here with the agent's id and
# its type. Rows planted with the id already on them hid walk-triage-3's defect: every budget
# case started from a row whose id was known before any hook had written it. A later row that
# carries the id (ARM 2's confirmation, an amend) is still `add_row`'s, because those writers do.
REC="$PAYLOAD_HOOKS/execution-recorder.sh"
BSG_TYPE="bionic:senior-implementor"
BSG_TUID=0
# LAUNCHED NOW (wave-27 T38): the start joins only a launch inside the window it can follow, so the
# launch row carries the moment the dispatch wall would have stamped. `launched=` writes the row
# alone and `started` drives the start alone, for a case that needs them apart.
launched() {  # <repo> <key=value>... — the launch row the dispatch wall writes, nothing else
  local repo="$1"; shift
  BSG_TUID=$((BSG_TUID + 1))
  add_row "$repo" status=intended agent_id= "subagent_type=$BSG_TYPE" "tool_use_id=toolu_01bsgdisp$BSG_TUID" \
    "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@"
}
dispatched() {
  local repo="$1" aid="$2"; shift 2
  launched "$repo" "$@"
  started "$repo" "$aid"
}
started() {  # <repo> <agent id> [agent type] — the agent's own start, through the recorder
  local repo="$1" aid="$2"
  jq -n --arg s "$SID" --arg c "$repo" --arg a "$aid" --arg t "${3:-$BSG_TYPE}" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"95b0701b-7814-42ca-a26f-58123e667f9a",
      agent_id:$a, agent_type:$t, hook_event_name:"SubagentStart"}' \
    | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
        BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
        CLAUDE_PROJECT_DIR= bash "$REC" >/dev/null 2>&1
}

# `agent_type` TRAVELS WITH `agent_id` (T23). A dispatched agent's tool-class payload
# carries both — the type or the teammate name in `agent_type`
# (record/session-20260815-landing-supervision/t1-probe-report.md §2.1) and the transcript
# id in `agent_id` — and the fixture omitted the first because the wall it drove reads
# only the second. Now that one process carries all five walls it matters:
# hooks/farm-out-reminder.sh's function leaves on a non-empty `agent_type`, and a payload
# without it is a MAIN-THREAD payload by that wall's own rule, so every suite command
# below would draw a farm-out deny beside this wall's verdict. The field is added rather
# than the expectations changed, because an agent-context payload really does carry it.
# A FIXED, HUGE `timeout` ON EVERY PAYLOAD (T3, REQ-3, D4). `wall_background_suite_guard`
# gained a repair arm between ARM 1 and ARM 2 that rewrites ANY suite call whose timeout is
# absent or below the harness maximum — and this file's fixtures never declared one, which
# is exactly the shape that arm now repairs. This suite tests the BUDGET arm (ARM 2) and the
# backgrounded-suite arm (ARM 1) only; a timeout the repair can never treat as "too low"
# keeps its assertions reading the same verdict they always did — tests/bash-walls.test.sh
# §14 is where the repair itself is proved. 86400000 (24h) is comfortably above any ceiling
# this suite's environment could set (none of its rows touch `BASH_MAX_TIMEOUT_MS`).
mk_payload() {  # <cwd> <command> [agent_id] [run_in_background:true|false|omit]
  local bg="${4:-omit}"
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" --arg a "${3:-}" --arg bg "$bg" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      permission_mode:"bypassPermissions",
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:({command:$cmd, timeout: 86400000}
                  + (if $bg == "omit" then {} else {run_in_background: ($bg == "true")} end)),
      tool_use_id:"toolu_01s13budget"}
     + (if $a == "" then {} else {agent_id:$a, agent_type:"test-runner"} end)'
}

OUT=""; ERR=""; ST=0
EXTRA_ENV=""
# THE WRAP IS TAKEN OFF STDOUT INTO ITS OWN VARIABLES (wave-26 T7, D8). An allowed suite
# command now comes back rewritten into the booking shim: stdout carries one object whose
# only content is `updatedInput`. That is not a verdict and not an advisory, so the rows
# above §WRAP, which read `$OUT$ERR` as "nothing was refused and nothing was said", keep
# reading exactly that. The split takes ONLY that shape: an object whose hookSpecificOutput
# holds nothing but the event name and an updatedInput whose command runs booked.sh. Any
# other stdout (a deny, a nudge, a wrap beside a nudge) stays in `$OUT` whole. §WRAP reads
# `$WRAP` (the rewritten command) and `$WRAP_INPUT` (the whole rewritten tool_input).
WRAP=""; WRAP_INPUT=""
run_hook() {  # <payload> <hook> [args...]
  local payload="$1"; shift
  local _sid; _sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  # shellcheck disable=SC2086  # EXTRA_ENV is this file's own space-free assignments
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$_sid" \
          CLAUDE_PROJECT_DIR= $EXTRA_ENV bash "$@" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  WRAP=""; WRAP_INPUT=""
  if [ -n "$OUT" ] && printf '%s' "$OUT" | jq -e '(.hookSpecificOutput | keys) == ["hookEventName","updatedInput"]
        and (.hookSpecificOutput.updatedInput.command | test("/scripts/booked\\.sh"))' >/dev/null 2>&1; then
    WRAP_INPUT=$(printf '%s' "$OUT" | jq -c '.hookSpecificOutput.updatedInput')
    WRAP=$(printf '%s' "$WRAP_INPUT" | jq -r '.command')
    OUT=""
  fi
  return 0
}

# THROUGH THE GUARD, as hooks/hooks.json registers the pair. Every cell below is driven
# this way unless it is specifically about the guard being absent: what ships is the pair,
# and a wall proved only when driven straight is a wall nobody proved.
VERR=""
guarded() {  # <repo> <command> [agent_id] [bg]
  # TWO DRIVES OF THE SAME CALL, and the pair is what task 13's ruling D-1 made
  # necessary. The user stream is ONE line now — `bionic: <verb> refused — <fact>
  # (<fix>)` — and everything this suite used to read off it (the suite asked for, the
  # recorded set, the word BUDGET, the standing ruling) is `detail`, which reaches a
  # reader only under BIONIC_WALL_VERBOSE=1. So `$ERR` is asserted for the LINE and
  # `$VERR` for the detail; asserting the detail on `$ERR` would now be asserting that
  # the wall leaks it.
  run_hook "$(mk_payload "$1" "$2" "${3-$ACTOR}" "${4:-omit}")" "$GUARD"
  local _st="$ST" _out="$OUT" _err="$ERR" _saved="$EXTRA_ENV"
  VERR=""
  # ONLY WHEN THE FIRST DRIVE REFUSED, so an allowed command is never run twice.
  if [ "$_st" -ne 0 ]; then
    EXTRA_ENV="$EXTRA_ENV BIONIC_WALL_VERBOSE=1"
    run_hook "$(mk_payload "$1" "$2" "${3-$ACTOR}" "${4:-omit}")" "$GUARD"
    VERR="$ERR"
  fi
  EXTRA_ENV="$_saved"; ST="$_st"; OUT="$_out"; ERR="$_err"
}

section "B0 — the hook exists and parses"
if [ -f "$GUARD" ]; then ok "hooks/bash-walls.sh is on disk"; else
  no "hooks/bash-walls.sh is on disk" "$GUARD"
fi
if bash -n "$GUARD" 2>"$SANDBOX/.syn"; then ok "it parses (bash -n)"; else
  no "it parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi

section "B1 — a stated budget: on it passes, off it refuses"
R1=$(mk_repo b1)
dispatched "$R1" "$ACTOR" name=w-b1 "suites_allowed=alpha.test.sh beta.test.sh" \
  suites_source=derived files=payload/scripts/lib/widget.sh

guarded "$R1" 'tests/run.sh --only alpha.test.sh'
expect_eq "B1a a suite ON the budget is allowed" "0" "$ST"
expect_empty "B1a …silently" "$OUT$ERR"

guarded "$R1" 'tests/run.sh --only beta.test.sh 2>&1 | tee /tmp/b.log'
expect_eq "B1b …and so is the other one, tee'd as a real brief would run it" "0" "$ST"
expect_empty "B1b …silently" "$OUT$ERR"

guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_eq "B1c a suite OFF the budget is REFUSED" "2" "$ST"
expect_contains "B1c …naming the suite that was asked for" "gamma.test.sh" "$VERR"
expect_contains "B1c …naming the set that was recorded" "alpha.test.sh beta.test.sh" "$VERR"
# ADR-002: this arm is an instrument budget, not a safety wall, and the refusal says the
# word — an agent that reads it must be able to tell "you may not" from "this costs".
expect_contains "B1c …and calling itself a BUDGET, not a wall" "BUDGET" "$VERR"
expect_empty "B1c …with nothing on stdout" "$OUT"

# EVERY spelling the classifier recognises reaches this arm, or the budget is bypassable by
# typing the same command differently — the superset rule read from the budget side.
for sp in 'sudo bash tests/gamma.test.sh' '( bash tests/gamma.test.sh )' \
          './tests/gamma.test.sh' 'tests/gamma.test.sh' \
          'cd /tmp && bash tests/gamma.test.sh' 'PIN=/tmp/p bash tests/gamma.test.sh'; do
  guarded "$R1" "$sp"
  expect_eq "B1d off-budget through [$sp] is REFUSED" "2" "$ST"
done

# A CHAIN IS REFUSED FOR ITS OFF-BUDGET MEMBER, even when the first member is allowed —
# the arm reads every suite the command names, not the first one.
guarded "$R1" 'tests/run.sh --only alpha.test.sh && tests/run.sh --only gamma.test.sh'
expect_eq "B1e a chain carrying one off-budget suite is REFUSED" "2" "$ST"
expect_contains "B1e …naming the member that was off it" "gamma.test.sh" "$VERR"

# NEGATIVE CONTROL: prose naming an off-budget suite is not an invocation.
guarded "$R1" 'echo "next up: bash tests/gamma.test.sh"'
expect_eq "B1f prose naming an off-budget suite is allowed" "0" "$ST"
expect_empty "B1f …silently" "$OUT$ERR"

guarded "$R1" 'git status --short'
expect_eq "B1g a non-suite command is allowed" "0" "$ST"
expect_empty "B1g …silently" "$OUT$ERR"

# SUITE-CLASS AND FILELESS, AND NOW HELD (REQ-1 AC-1.5, 1.8.3). Until this wave `pytest`
# ran a suite and named no file this row could speak about, so it passed in silence — and a
# writer in a repository whose tests are not shell suites had a budget in name only
# (research R1 Q2). The classifier now names the RUN a runner form makes, so the row's
# recorded set is a statement about the whole instrument: a runner form the brief did not
# declare is refused with the same budget refusal a suite file draws. R1's row declares no
# runs, so `pytest` is outside its set.
guarded "$R1" 'pytest'
expect_eq "B1h a suite-class runner form outside the row's set is REFUSED" "2" "$ST"
expect_contains "B1h …naming the run that was asked for" "pytest" "$VERR"
expect_contains "B1h …and calling itself a BUDGET, not a wall" "BUDGET" "$VERR"
expect_empty "B1h …with nothing on stdout" "$OUT"

section "B2 — tests/run.sh is refused unless the row carries it"
guarded "$R1" 'bash tests/run.sh'
expect_eq "B2a the full tree is REFUSED against a narrow budget" "2" "$ST"
expect_contains "B2a …naming the full tree" "tests/run.sh" "$VERR"
expect_contains "B2a …calling itself a BUDGET" "BUDGET" "$VERR"
expect_contains "B2a …and naming the rule it makes mechanical: the full run is the released head's" \
  "The full suite runs once, on the head being released" "$VERR"

R2=$(mk_repo b2)
dispatched "$R2" "$ACTOR" name=w-b2 suites_allowed=run.sh suites_source=declared files=
guarded "$R2" 'bash tests/run.sh'
expect_eq "B2b the Step-5 runner, whose row carries run.sh, is allowed" "0" "$ST"
expect_empty "B2b …silently" "$OUT$ERR"
# …and that row is not a licence for everything else.
guarded "$R2" 'tests/run.sh --only alpha.test.sh'
expect_eq "B2c …but its row does not license a suite it does not name" "2" "$ST"

section "B3 — FARM_OUT_ALLOW does not widen a budget (AC-21)"
# The override exists so the ORCHESTRATOR can run something on its own thread when
# dispatching it genuinely will not work — it is farm-out-reminder.sh's escape from
# farm-out-reminder.sh's wall. A writer that could set an environment variable on itself
# to widen its own instrument would have a budget in name only.
guarded "$R1" 'FARM_OUT_ALLOW=1 bash tests/run.sh'
expect_eq "B3a the override as a command prefix does not open the full tree" "2" "$ST"
guarded "$R1" 'cd /tmp && FARM_OUT_ALLOW=1 tests/run.sh --only gamma.test.sh'
expect_eq "B3b …nor mid-chain, for an off-budget suite" "2" "$ST"
EXTRA_ENV="FARM_OUT_ALLOW=1"
guarded "$R1" 'bash tests/run.sh'
expect_eq "B3c …nor set in the agent's own environment" "2" "$ST"
guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_eq "B3d …for either arm" "2" "$ST"
# NON-VACUITY: with the override set, an ON-budget suite still passes — so B3c/B3d are the
# budget refusing, not the override breaking the hook.
guarded "$R1" 'tests/run.sh --only alpha.test.sh'
expect_eq "B3e non-vacuity: an on-budget suite still passes with the override set" "0" "$ST"
EXTRA_ENV=""

section "B4 — the three states of suites_allowed, and no row at all"
# `none` is a DECLARED empty set (the `Suites: none` waiver); an empty value is a budget
# that was stated and came out empty; an absent key is a row written before the wall; no row
# is an agent whose id never reached the roster. The last three record NO SET, and since
# wave-27 T5 (D15) a suite command from an agent with no recorded set is REFUSED, naming why:
# admitted, it ran unbudgeted and stamped `?` (walk-triage-3 §1).

R4A=$(mk_repo b4a)
dispatched "$R4A" "$ACTOR" name=w-b4a suites_allowed=none suites_source=declared files=
guarded "$R4A" 'tests/run.sh --only alpha.test.sh'
expect_eq "B4a a Suites: none row refuses every named suite" "2" "$ST"
expect_contains "B4a …saying the brief declared none" "Suites: none" "$VERR"
guarded "$R4A" 'bash tests/run.sh'
expect_eq "B4a …and the full tree with it" "2" "$ST"

R4B=$(mk_repo b4b)
dispatched "$R4B" "$ACTOR" name=w-b4b suites_allowed= suites_source=derived files=x/y.sh
guarded "$R4B" 'tests/run.sh --only alpha.test.sh'
expect_eq "B4b an EMPTY budget refuses a named suite" "2" "$ST"
expect_contains "B4b …saying no set is recorded" "no suite set is recorded for this agent" "$ERR"
expect_contains "B4b …and why: the row records none" "your roster row records no suite set" "$VERR"
expect_contains "B4b …with the verb that records one, for this row" "amend w-b4b --suites+ alpha.test.sh" "$VERR"
expect_empty "B4b …and nothing staged to run it" "$WRAP"
guarded "$R4B" 'bash tests/run.sh'
expect_eq "B4b …and the full tree too" "2" "$ST"

R4C=$(mk_repo b4c)
dispatched "$R4C" "$ACTOR" name=w-b4c          # a pre-wall row: no key at all
guarded "$R4C" 'tests/run.sh --only alpha.test.sh'
expect_eq "B4c a row from before the wall refuses a named suite" "2" "$ST"
expect_contains "B4c …saying no set is recorded" "no suite set is recorded for this agent" "$ERR"
guarded "$R4C" 'bash tests/run.sh'
expect_eq "B4c …and the full tree" "2" "$ST"
expect_contains "B4c …saying no set was recorded" "no set was recorded" "$VERR"
# NON-VACUITY: the row really is on the roster and really carries this agent's id, so B4c
# is the ABSENT KEY being read and not a row the hook failed to find.
expect_contains "B4c non-vacuity: the row is on the roster under this agent's id" \
  "agent_id=$ACTOR" "$(cat "$R4C/.bionic/tmp/roster-$SID.state")"
expect_absent "B4c …and it carries no suites_allowed key" \
  "suites_allowed=" "$(cat "$R4C/.bionic/tmp/roster-$SID.state")"

R4D=$(mk_repo b4d)                                   # no row for this agent at all
dispatched "$R4D" "$OTHER" name=someone-else suites_allowed=alpha.test.sh suites_source=declared files=
guarded "$R4D" 'tests/run.sh --only alpha.test.sh'
expect_eq "B4d no row for this agent refuses a named suite" "2" "$ST"
expect_contains "B4d …saying no set is recorded" "no suite set is recorded for this agent" "$ERR"
expect_contains "B4d …and why: no row carries its id" "no roster row carries your agent id $ACTOR" "$VERR"
# REBUILT SO IT CAN FAIL (wave-27 T38; review pass 8 note 6). It asserted that `On the budget:
# alpha.test.sh` was absent, and the no-set refusal never prints `On the budget:` at all. The claim
# is that another agent's row is never this agent's: so the remedy line, read out of the refusal,
# names THIS agent by its own id, and never the one row on the roster, which is someone else's.
B4D_FIX=$(printf '%s\n' "$VERR" | grep -F 'widen it: ' | head -1)
expect_contains "B4d …and the remedy records a set for this agent, by its own id" "amend $ACTOR --suites+ alpha.test.sh" "$B4D_FIX"
expect_absent "B4d …never the other agent's row, whose set is not its budget" "someone-else" "$B4D_FIX"
guarded "$R4D" 'bash tests/run.sh'
expect_eq "B4d …and still refuses the full tree" "2" "$ST"
# A NAME THE HOOK CANNOT EXPAND, from an agent with no set: refused for the missing set.
guarded "$R4D" 'for s in alpha beta; do s=gamma; tests/run.sh --only "$s.test.sh"; done'
expect_eq "B4d a suite named by a variable is refused too" "2" "$ST"
expect_contains "B4d …for the missing set" "no suite set is recorded for this agent" "$ERR"
expect_empty "B4d …with nothing staged to run it" "$WRAP"
# NON-VACUITY: the other agent's row IS on this roster, joined at its start, and binds IT.
guarded "$R4D" 'tests/run.sh --only alpha.test.sh' "$OTHER"
expect_eq "B4d control: the other agent's own budgeted suite is admitted" "0" "$ST"
guarded "$R4D" 'tests/run.sh --only gamma.test.sh' "$OTHER"
expect_eq "B4d control: …and its off-budget suite refused by its own set" "2" "$ST"
expect_contains "B4d control: …the set its start joined" "alpha.test.sh" "$VERR"

# B4e — AN AGENT ITS START COULD NOT PLACE IS NOT REFUSED FOR LIFE (wave-27 T38; review pass 8 F3).
# A type that is not a bionic: role is never joined at its start (the recorder takes bionic roles
# only), so until its launch call returns it has no row, and a foreground call returns when the
# agent has finished. 1.11.0 let its named suites run unbudgeted; T5 refused them with a remedy
# that named an act no verb performed. The refusal now says why, and prints an `amend` line for the
# agent's id. The orchestrator runs that line EXACTLY AS PRINTED, and the suite then runs.
# fails-when: the reason is missing; the printed line does not run; it runs and the suite is still
# refused; the set it records reaches past the suite it named.
R4E=$(mk_repo b4e)
BSG_TYPE_WAS="$BSG_TYPE"; BSG_TYPE=test-runner
launched "$R4E" name=w-b4e suites_allowed=alpha.test.sh suites_source=declared files=
started "$R4E" "$ACTOR"
BSG_TYPE="$BSG_TYPE_WAS"
expect_absent "B4e precondition: the start of a test-runner joined no row (no row carries the id)" \
  "agent_id=$ACTOR" "$(cat "$R4E/.bionic/tmp/roster-$SID.state")"
expect_contains "B4e precondition: …while its launch row is there" "|name=w-b4e|" "$(cat "$R4E/.bionic/tmp/roster-$SID.state")"
guarded "$R4E" 'tests/run.sh --only alpha.test.sh'
expect_eq "B4e1 the unplaced agent's suite is refused" "2" "$ST"
expect_contains "B4e2 …saying no set is recorded" "no suite set is recorded for this agent" "$ERR"
expect_contains "B4e3 …and why: its type is not a bionic: role, so its start is never placed" \
  "your type test-runner is not a bionic: role, and its start is never placed on a row" "$VERR"
B4E_FIX=$(printf '%s\n' "$VERR" | grep -F 'widen it: ' | head -1)
B4E_CMD="${B4E_FIX#*widen it: }"; B4E_CMD="${B4E_CMD% (main runs it)}"
expect_contains "B4e4 …printing the amend line for its id" "session-poker.sh amend $ACTOR --suites+ alpha.test.sh --reason" "$B4E_CMD"
# The agent's transcript is on disk, as it is for any agent that has run a command.
mkdir -p "$FAKE_HOME/.claude/projects/-sandbox/$SID/subagents"
: > "$FAKE_HOME/.claude/projects/-sandbox/$SID/subagents/agent-$ACTOR.jsonl"
# With NO remedy line printed there is nothing to run, and `bash -c ""` exits 0, so the row would
# pass on the very defect it pins (wave-27 T59; review pass 36 S3): no line is a failure here.
if [ -n "$B4E_FIX" ]; then
  B4E_OUT=$( cd "$R4E" && env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
    BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
    bash -c "$B4E_CMD" 2>&1 ); B4E_RC=$?
else
  B4E_OUT=""; B4E_RC="no remedy line was printed"
fi
expect_eq "B4e5 the printed line, run as printed by the orchestrator, exits 0" "0" "$B4E_RC"
expect_contains "B4e6 …saying it recorded the set for that id" "poker: amended — $ACTOR" "$B4E_OUT"
guarded "$R4E" 'tests/run.sh --only alpha.test.sh'
expect_eq "B4e7 …and the suite it named now runs" "0" "$ST"
expect_nonempty "B4e8 …wrapped in the booking shim" "$WRAP"
guarded "$R4E" 'tests/run.sh --only gamma.test.sh'
expect_eq "B4e9 a suite it did not name is still refused" "2" "$ST"
expect_contains "B4e10 …against the set it recorded" "alpha.test.sh" "$VERR"
expect_contains "B4e11 …and its remedy names the same id" "amend $ACTOR --suites+ gamma.test.sh" "$VERR"

section "B5 — the LAST row carrying this id wins"
# One dispatch becomes several rows: the launch row, hooks/execution-recorder.sh's
# `status=confirmed` copy, and — across a /clear — hooks/session-poker.sh's adopted row.
# Each carries the budget forward, and the newest is the current statement about the agent.
R5=$(mk_repo b5)
dispatched "$R5" "$ACTOR" name=w-b5 suites_allowed=alpha.test.sh \
  suites_source=declared files=
add_row "$R5" name=w-b5 "agent_id=$ACTOR" status=confirmed suites_allowed="alpha.test.sh delta.test.sh" \
  suites_source=declared files=
guarded "$R5" 'tests/run.sh --only delta.test.sh'
expect_eq "B5a a suite the LATER row allows is allowed" "0" "$ST"
guarded "$R5" 'tests/run.sh --only epsilon.test.sh'
expect_eq "B5b …and one neither row allows is still refused" "2" "$ST"
expect_contains "B5b …against the later row's set" "alpha.test.sh delta.test.sh" "$VERR"

section "B5c — a successor row carrying re_executes= admits the run (T6, AC-5.3)"
# The remedy the refusal now names is `amend --reexec+`, which appends a successor row with
# `re_executes=`. The round trip is green today; this pins it so the remedy cannot rot into
# a command that is accepted and then does nothing. The positive and its refused control sit
# together: a pin on the admit alone would also pass a wall that admitted everything.
R5C=$(mk_repo b5c)
dispatched "$R5C" "$ACTOR" name=w-b5c suites_allowed=alpha.test.sh \
  suites_source=declared files=
guarded "$R5C" "npx jest --testPathPatterns 'x'"
expect_eq "B5c before the widen, the run is refused" "2" "$ST"
add_row "$R5C" name=w-b5c "agent_id=$ACTOR" status=confirmed suites_allowed=alpha.test.sh \
  suites_source=declared files= "re_executes=\`npx jest --testPathPatterns 'x'\`"
guarded "$R5C" "npx jest --testPathPatterns 'x'"
expect_eq "B5c after the successor row, the declared run is admitted" "0" "$ST"
guarded "$R5C" 'npx jest'
expect_eq "B5c …and an undeclared run is still refused" "2" "$ST"

section "B6 — scope: the arm is the AGENT's, and the session must be engaged"
# A main-thread payload has no top-level agent_id (t1-probe-report.md §3). The
# orchestrator's own thread is hooks/farm-out-reminder.sh's, which answers the same
# question differently, so this arm never speaks there.
# SILENT FOR THIS WALL, WHICH IS NOT THE SAME AS AN EMPTY STREAM (T23). A main-thread
# suite command is hooks/farm-out-reminder.sh's business and it denies it — that is the
# sentence below about the orchestrator's own thread, and in one process its answer shares
# these streams. So the assertion is that THIS wall said nothing, by its own words, rather
# than that nobody did.
run_hook "$(mk_payload "$R1" 'bash tests/gamma.test.sh' "")" "$GUARD"
expect_eq "B6a a MAIN-THREAD payload leaves the budget arm silent" "0" "$ST"
expect_absent "B6a …with no budget refusal in it" "budget" "$ERR"
expect_absent "B6a …and no backgrounded-suite refusal either" "never read" "$ERR"
# POSITIVE CONTROL: the same command, same repo, from an agent context, refuses — so B6a
# is the partition and not a dud fixture.
guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_eq "B6a control: the same command from an agent context REFUSES" "2" "$ST"

# THE SAME PAYLOAD BACKGROUNDED, which is the arm the wrapper used to scope. Driven
# straight into the wall before T23 this refused on the main thread and only the wrapper
# in front stopped it; the predicate is inside the function now, so the main thread is
# silent here and the control below shows the arm is alive in an agent context.
run_hook "$(mk_payload "$R1" 'bash tests/gamma.test.sh' "" true)" "$GUARD"
expect_eq "B6b …and a MAIN-THREAD backgrounded suite is silent too" "0" "$ST"
expect_absent "B6b …the backgrounded-suite refusal does not fire there" \
  "a backgrounded suite's result is never read" "$ERR"
guarded "$R1" 'tests/run.sh --only gamma.test.sh' "$ACTOR" true
expect_eq "B6b control: backgrounded from an agent context, REFUSED" "2" "$ST"

# UNENGAGED: bionic's walls bind only a session that invoked canonical-sdlc.
rm -f "$R1/.bionic/tmp/engaged-$SID.state"
guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_eq "B6c an unengaged session is silent even off-budget (through the guard)" "0" "$ST"
run_hook "$(mk_payload "$R1" 'bash tests/gamma.test.sh' "$ACTOR")" "$GUARD"
expect_eq "B6c …and with an agent context as well" "0" "$ST"
expect_empty "B6c …silently" "$OUT$ERR"
: > "$R1/.bionic/tmp/engaged-$SID.state"
guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_eq "B6c control: with the marker back, it REFUSES again" "2" "$ST"

# UNARMED (no roster): the guard in front never runs the wall, so nothing is refused, and
# the wall driven straight has no row to read and takes the no-statement path.
R6=$(mk_repo b6)
rm -f "$R6/.bionic/tmp/roster-$SID.state"
guarded "$R6" 'tests/run.sh --only gamma.test.sh'
expect_eq "B6d an unarmed session is silent (the guard in front never runs the wall)" "0" "$ST"

section "B7 — which arm speaks when both apply"
# A backgrounded suite is refused whether or not it is on the budget, and being on the
# budget is no answer to "nobody read the result" — so the B-9 arm speaks first.
guarded "$R1" 'tests/run.sh --only alpha.test.sh' "$ACTOR" true
expect_eq "B7a an ON-budget suite, backgrounded, is still REFUSED" "2" "$ST"
expect_contains "B7a …by the B-9 arm, whose fact is on the user line" \
  "a backgrounded suite's result is never read" "$ERR"
expect_absent "B7a …and not by the budget arm" "BUDGET" "$ERR"

guarded "$R1" 'tests/run.sh --only gamma.test.sh' "$ACTOR" true
expect_eq "B7b an OFF-budget suite, backgrounded, is refused too" "2" "$ST"
expect_contains "B7b …still by the B-9 arm, which is the wider refusal" \
  "a backgrounded suite's result is never read" "$ERR"

guarded "$R1" 'tests/run.sh --only alpha.test.sh' "$ACTOR" false
expect_eq "B7c run_in_background false is not backgrounded, and on-budget passes" "0" "$ST"
expect_empty "B7c …silently" "$OUT$ERR"

section "B8 — the arm is scoped to THIS repo, and a mode that runs nothing spends nothing"
# THE THREE FALSE REFUSALS (critic K-2, review-a A-7, the walk A-36a). The reading behind
# this arm used to answer with a bare basename, so any file on the machine ending
# `.test.sh` was judged against this row's budget, and `--dry-run` — documented as "run
# nothing" — was refused on the same terms as a forty-minute run.

guarded "$R1" 'bash tests/run.sh --dry-run'
expect_eq "B8a the runner's --dry-run mode is ALLOWED against a narrow budget" "0" "$ST"
expect_empty "B8a …silently" "$OUT$ERR"

# CONTROL: the same command without the flag is the full tree, and still refused.
guarded "$R1" 'bash tests/run.sh'
expect_eq "B8b control: without the flag the full tree is still REFUSED" "2" "$ST"

# A SUITE FILE THAT IS NOT THIS REPO'S is not this row's business either.
guarded "$R1" 'bash /tmp/scratch-probe/probe2.test.sh'
expect_eq "B8c an off-budget basename OUTSIDE the repo is allowed" "0" "$ST"
expect_empty "B8c …silently" "$OUT$ERR"
guarded "$R1" 'bash /some/other/tree/tests/run.sh'
expect_eq "B8d …and so is a full tree that is not this one" "0" "$ST"
guarded "$R1" '/bin/bash /private/tmp/scratch/replay/run.sh'
expect_eq "B8d2 a script merely NAMED run.sh is not the full tree, and is allowed (T24)" "0" "$ST"
expect_empty "B8d2 …silently" "$OUT$ERR"

# CONTROL: the same basename inside the repo is refused, so B8c is scoping and not silence.
guarded "$R1" 'tests/run.sh --only probe2.test.sh'
expect_eq "B8e control: the same basename INSIDE the repo is REFUSED" "2" "$ST"

# THE SPLIT IS GUARDED. `bash tests/*.test.sh` names the literal `*.test.sh`, and the loop
# that reads the targets runs with `set -f` — so the HOOK PROCESS'S OWN CWD cannot expand
# that word into whatever files happen to sit there (review-a A-7b). The cwd below holds
# `alpha.test.sh` and `beta.test.sh`, which are exactly this row's budget: without the
# guard the word expands into two allowed names and the command passes.
BSG_GLOBDIR="$SANDBOX/globcwd"
mkdir -p "$BSG_GLOBDIR"
: > "$BSG_GLOBDIR/alpha.test.sh"
: > "$BSG_GLOBDIR/beta.test.sh"
guarded_from() {  # <cwd for the hook process> <repo> <command>
  local _dir="$1" _payload
  _payload=$(mk_payload "$2" "$3" "$ACTOR" omit)
  OUT=$(cd "$_dir" && printf '%s' "$_payload" | env HOME="$FAKE_HOME" \
          CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" \
          CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
          bash "$GUARD" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  # The same call again with the knob, for the arms that read `detail` (task 13, D-1).
  VERR=$(cd "$_dir" && printf '%s' "$_payload" | env HOME="$FAKE_HOME" \
          CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" \
          CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= BIONIC_WALL_VERBOSE=1 \
          bash "$GUARD" 2>&1 >/dev/null)
  return 0
}
guarded_from "$BSG_GLOBDIR" "$R1" 'bash tests/*.test.sh'
expect_eq "B8f a glob target is REFUSED by its literal name" "2" "$ST"
expect_contains "B8f …naming the unexpanded word, not the files beside the hook" "*.test.sh" "$VERR"

section "B9 — a suite named by a shell VARIABLE is a different refusal (C-5, A-35c)"
# THE DEFECT. A hook reads the command text BEFORE the shell expands it. A writer looping
# over four suites all of which are on its budget got
#     BLOCKED: $s.test.sh is not on this agent's suite budget.
# — a headline that is false in the case that produces it, sending the reader to check a
# set that is not the problem. Two independent readers hit it (A-35c; the walk's heading
# 10(b), a fresh agent on its first attempt). The correct behaviour is still to refuse;
# the wrong thing was the sentence.

# Re-spelled (wave-14 T8 c088189 → T18 fcd5a16 → T25): the label "unexpanded name; budget: "
# read as if the SET named the budget rather than the set of what is ALLOWED; renamed to
# "unexpanded name; allowed: ".
# A LITERAL LOOP IS NO LONGER THIS STATE (wave-24 T5, AC-6.3, D9). The reading resolves
# `for s in alpha beta` into the two suites it names before the arm compares, so the loop
# over two on-budget suites passes, and the same loop carrying an off-budget word draws the
# ORDINARY refusal naming it. The unexpanded refusal is kept for a body that reassigns the
# variable, which is the shape B9a now drives.
guarded "$R1" 'for s in alpha beta; do tests/run.sh --only "$s.test.sh"; done'
expect_eq "B9a0 a loop over a literal list of on-budget suites is ALLOWED" "0" "$ST"
expect_empty "B9a0 …silently" "$OUT$ERR"
guarded "$R1" 'for s in alpha gamma; do tests/run.sh --only "$s.test.sh"; done'
expect_eq "B9a1 the same loop naming an off-budget suite is REFUSED" "2" "$ST"
expect_contains "B9a1 …naming the off-budget suite, resolved" "gamma.test.sh" "$VERR"
expect_absent "B9a1 …not as an unexpanded name" "unexpanded name" "$ERR"

guarded "$R1" 'for s in alpha beta; do s=gamma; tests/run.sh --only "$s.test.sh"; done'
expect_eq "B9a a variable-named suite is still REFUSED" "2" "$ST"
expect_contains "B9a …saying the name could not be resolved at hook time" \
  "unexpanded name; allowed: alpha.test.sh" "$ERR"
# The sentence and its line shape are the ones tests/bash-walls.test.sh 15b5b pins on the same
# reassigning fixture (wave-24 T28, A-T28.7): one wording, owned by walls.sh's unexpanded arm.
expect_contains "B9a …and telling the reader what to type instead: literal lines, one call each" \
  "Write the literal names you mean, through the one door: tests/run.sh --only <name>.test.sh" "$VERR"
# THE HEADLINE THE READER ACTS ON must not claim the suite is off a budget the hook never
# managed to check it against.
expect_absent "B9a …never claiming it is off the budget" "is not on this agent's suite budget" "$ERR"

# THE BRACE FORM AND A COMMAND SUBSTITUTION ARE THE SAME STATE.
guarded "$R1" 'tests/run.sh --only "${s}.test.sh"'
expect_eq "B9b the brace spelling reads the same way" "2" "$ST"
expect_contains "B9b …with the same refusal" \
  "unexpanded name; allowed: alpha.test.sh" "$ERR"
guarded "$R1" 'tests/run.sh --only `suite_name`.test.sh'
expect_eq "B9c a command substitution reads the same way" "2" "$ST"
expect_contains "B9c …with the same refusal" \
  "unexpanded name; allowed: alpha.test.sh" "$ERR"

# CONTROL: the literal spelling the refusal asks for is allowed, so B9a is about the
# spelling and not about the suite.
guarded "$R1" 'tests/run.sh --only alpha.test.sh'
expect_eq "B9e control: the literal spelling of an on-budget suite passes" "0" "$ST"
expect_empty "B9e …silently" "$OUT$ERR"

# THE ORDINARY REFUSAL'S OWN ALIGNMENT. `You asked for : x` carried a space before the
# colon — column alignment against the line above it, and a typo to everyone who did not
# notice. Both labels now end at the colon and the values align on the padding.
guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_eq "B9f control: an ordinary off-budget suite still refuses" "2" "$ST"
expect_contains "B9f …and its label carries no space before the colon" "You asked for:" "$VERR"
expect_absent "B9f …the stray space is gone" "You asked for :" "$ERR"

section "B10 — the shape rule is applied ONCE, and every path-forming site asks for it (A-10, REQ-1h)"
# THE INCONSISTENCY. `session_id` (payload/scripts/lib/session.sh) prefers
# CLAUDE_CODE_SESSION_ID, falls back to the payload value, and returns whichever it got
# VERBATIM — it validates nothing. Two hooks that build a roster path apply the shape rule
# before doing so; this hook's roster READ is new in this wave and did not inherit it.
# hooks/landing-gate.sh:284 states the rationale for `agent_id`: a key carrying path
# separators does not trip the symlink guards, it reads outside what those guards protect.
#
# WHY THIS IS A SOURCE ASSERTION AND NOT A DRIVEN ONE, said plainly. The rule is
# UNREACHABLE through the supported path: it is applied to the same id ~70 lines before any
# roster path is formed, so a malformed id leaves the hook at the engagement switch and
# never reaches the path. A test that piped a malformed id into this hook and watched it
# pass would be asserting the ENGAGEMENT check while claiming to assert this one — a green
# that proves a different line than the one it names, which is the exact class this wave
# exists to close. What IS true and checkable is the family property A-10 names.
#
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1h). A-10's property was "the same rule at
# every path-forming site", and three hooks each carried their own copy of it. The property
# is now stronger and cheaper to hold: there is ONE rule, in `bionic_context`
# (payload/scripts/lib/context.sh), applied to the RESOLVED id, and a hook that fails it
# exits rather than blanking the variable and carrying on. So the family row below asks
# whether each hook takes its id from that one call — which is the same question A-10 asked,
# put to the site that can now answer it — and the row after it pins the rule itself.
B10_LIB="$REPO_ROOT/payload/scripts/lib/context.sh"
B10_HOOKS="bash-walls.sh execution-recorder.sh agent-context-guard.sh"
B10_RULE='case .*\[!A-Za-z0-9_-\]\*\)'
for _h in $B10_HOOKS; do
  expect_regex "B10 $_h takes its session id from the one call that shape-checks it" \
    'bionic_context' "$(cat "$PAYLOAD_HOOKS/$_h")"
  expect_eq "B10 …and restates the rule nowhere in its own body" "0" \
    "$(/usr/bin/grep -cE "$B10_RULE" "$PAYLOAD_HOOKS/$_h" | tr -d ' ')"
done
# THE RULE ITSELF, at the one site that now owns it.
expect_regex "B10 lib/context.sh carries the shape rule" "$B10_RULE" "$(cat "$B10_LIB")"
# NON-VACUITY: the pattern is not one that matches any shell file. A file with no such rule
# fails it, so the rows above are reading the rule and not the language.
expect_no_regex "B10 …and the pattern discriminates (a hook without the rule fails it)" \
  "$B10_RULE" "$(cat "$PAYLOAD_HOOKS/engage.sh")"
# AND IT IS APPLIED BEFORE THIS HOOK'S OWN PATH-FORMING SITE, not merely somewhere in the
# file. A rule that drifted away from the line it protects is the state A-10 found, spelled
# differently — so the ORDER is what is pinned, by line number, and an absent literal fails
# loudly rather than comparing two empty strings.
# THE ORDER IS STRUCTURAL NOW, AND STILL PINNED. The call and the path-forming site used
# to be two line numbers in one file; they are in two files since T23 — `bionic_context`
# runs once in hooks/bash-walls.sh, before `bionic_fold` calls any wall, and the roster
# path is formed inside `wall_background_suite_guard` in the library the hook sources.
# The hook cannot reach a wall without passing the call, so what is pinned is that each
# site exists exactly once and on the side it belongs to.
B10_WALLS="$REPO_ROOT/payload/scripts/lib/walls.sh"
expect_eq "B10 anchor: the hook calls bionic_context at column 0, once" "1" \
  "$(/usr/bin/grep -c '^bionic_context' "$GUARD" | tr -d ' ')"
expect_eq "B10 anchor: the library forms exactly one roster path" "1" \
  "$(/usr/bin/grep -c '^ROSTER_FILE=' "$B10_WALLS" | tr -d ' ')"
expect_eq "B10 …and the wall forms none of its own outside that one site" "0" \
  "$(/usr/bin/grep -c '^ROSTER_FILE=' "$GUARD" | tr -d ' ')"
expect_eq "B10 …the call precedes the fold that reaches every wall" "yes" \
  "$([ "$(/usr/bin/grep -n '^bionic_context' "$GUARD" | head -1 | cut -d: -f1)" \
      -lt "$(/usr/bin/grep -n '^bionic_fold' "$GUARD" | head -1 | cut -d: -f1)" ] && echo yes || echo no)"

section "B11 — AC-E1.3/E1.5: every refusal is one line, in the criterion's shape"
#
# fails-when: a refusal reaches the user as more than one VERDICT line, or in any shape
# but `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`. All four of this wall's refusal
# sites are tripped for real and asserted against the criterion's own regex and then
# against the exact wording the ruled table gives them (s12-refusal-wording-draft.md §1
# rows 11 through 14). B11e is the pair that proves the split rather than assuming it.
#
# AC-E1.3 IS ABOUT THE VERDICT, AND ADR-030 MADE THAT DISTINCTION VISIBLE (epic-23
# wave-16 T4/T19/T22). `exit2`'s field 9 (`detail_to_user`) is `yes` now, so the detail
# every arm above reads rides the same wire as the verdict, bounded at twelve lines, with
# no knob needed. Until that flip, "the user stream is one line" and "the verdict is one
# line" were the same measurement on `exit2`, and these pins took the cheaper one. What
# AC-E1.3 actually asks for — a sentence the reader is interrupted by, never wrapped — is
# the VERDICT, so that is what is counted and compared below; the detail is asserted
# present as well, with a POSITIVE beside each narrowed count, so a wall that went silent
# still fails a check that used to catch it (A-T4.9, A-T22.1).

B11_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
b11_line() {  # <label> <expected line>   (reads $ERR from the last `guarded`)
  local _n _line _rest
  _n="$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ' | tr -d ' ')"
  _line="$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
  # WHAT FOLLOWS THE VERDICT, if anything: the stream minus its rendered line(s). Read
  # here rather than asserted per caller, because every one of this wall's four sites
  # carries a `detail` and a site that stopped carrying one is the regression worth
  # seeing — narrowing the count without this would quietly weaken the section.
  _rest="$(printf '%s\n' "$ERR" | /usr/bin/grep -v '^bionic: ' | /usr/bin/grep -c . | tr -d ' ')"
  if [ "$_n" = "1" ]; then ok "$1: exactly one VERDICT line on the user stream"
  else no "$1: exactly one VERDICT line on the user stream" "got $_n lines: [$ERR]"; fi
  if printf '%s' "$_line" | /usr/bin/grep -qE "$B11_RE"; then ok "$1: in AC-E1.3's shape"
  else no "$1: in AC-E1.3's shape" "line=[$_line]"; fi
  if [ "$_line" = "$2" ]; then ok "$1: and it is the table's own wording"
  else no "$1: and it is the table's own wording" "want [$2] got [$_line]"; fi
  # THE POSITIVE THAT KEEPS THE COUNT HONEST (ADR-030, A-T4.9): the verdict is one line
  # BECAUSE the detail is a separate thing beneath it, not because the wall went quiet.
  if [ "$_rest" -ge 1 ]; then ok "$1: with its detail beneath it, no knob set"
  else no "$1: with its detail beneath it, no knob set" "nothing after the verdict"; fi
}

guarded "$R1" 'tests/run.sh --only alpha.test.sh' "$ACTOR" true
b11_line "B11a row 11 (backgrounded)" \
  "bionic: suite-run refused — a backgrounded suite's result is never read (run it in the foreground)"

# Re-spelled (wave-14 T8 c088189 → T18 fcd5a16 → T25): T25 renamed all three labels because
# the old wording put the ALLOWED set right after the words "off budget"/"budget:", which
# reads as the opposite of what it means — see record/wave-14-tune-181/review-readability-
# d3930dd.md half (b) item 1. "off budget: " -> "allowed: ", "unexpanded name; budget: " ->
# "unexpanded name; allowed: ", "full tree off budget: " -> "full tree refused; allowed: ".
# The longer full-tree label leaves six fewer columns for the set, which is why B11d's line
# now shows one token instead of "alpha.test.sh +1 more" — recomputed through
# `_budget_wire_fact`, not hand-guessed (T25 report).
# A body that reassigns `s` (wave-24 T5): a literal loop alone now resolves (B9a0).
guarded "$R1" 'for s in alpha beta; do s=gamma; tests/run.sh --only "$s.test.sh"; done'
b11_line "B11b row 12 (an unexpanded name)" \
  "bionic: suite-run refused — unexpanded name; allowed: alpha.test.sh (spell each suite literally)"

guarded "$R1" 'tests/run.sh --only gamma.test.sh'
b11_line "B11c row 13 (off the budget)" \
  "bionic: suite-run refused — allowed: alpha.test.sh beta.test.sh (run only the budgeted suites)"

guarded "$R1" 'bash tests/run.sh'
b11_line "B11d row 14 (the full tree)" \
  "bionic: suite-run refused — full tree refused; allowed: alpha.test.sh (run your brief's suites)"

# NO RECORDED SET (wave-27 T5, D15): R4D carries no row for this agent.
guarded "$R4D" 'tests/run.sh --only alpha.test.sh'
b11_line "B11d2 no set recorded" \
  "bionic: suite-run refused — no suite set is recorded for this agent (send main the suites you need)"

# AC-E1.5, the pair — RE-SPELLED (wave-14 T8 c088189 → T18 fcd5a16 → T25), then
# RE-AUTHORED BY ADR-030 (T22, the A-T4.10 precedent). What the knob gates has moved
# twice. First the compact fact line took the allowed set onto the DEFAULT stream
# (AC-5.2's own fix), leaving the explanatory PROSE ("On the budget:"/"You asked for:")
# as the thing behind the knob. Then field 9 flipped and the prose came onto the default
# stream too, beneath the verdict. So what this pair holds now is the SPLIT rather than
# the absence: the verdict line is the ruled sentence and carries none of the prose, and
# the prose is on the stream beneath it with no knob set. Asserted on the line and on the
# stream separately, so neither half can pass over an empty capture.
guarded "$R1" 'tests/run.sh --only gamma.test.sh'
expect_contains "B11e even without the knob the allowed set now reaches the DEFAULT stream" \
  "alpha.test.sh beta.test.sh" "$ERR"
expect_absent "B11e …but the explanatory PROSE is NOT on the verdict line" "On the budget:" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "B11e …it is beneath it, with no knob set at all" \
  "On the budget: alpha.test.sh beta.test.sh" "$ERR"
# BIONIC_WALL_VERBOSE=1 ADDS NOTHING THIS SUITE CAN TELL APART (A-T22.1, the A-T19.1
# precedent): field 9 already puts the bounded detail on the wire, and the longest detail
# this wall composes is twelve lines, so the knob's "whole detail" and the channel's
# "bounded detail" are byte-identical here — measured, `$ERR` and `$VERR` do not differ
# for any of this section's four sites. The row stays and stays true, but it no longer
# discriminates the knob from the default for THIS wall's messages; only a >12-line
# detail would, and this wall has none. Kept for parity with the fleet's shape rather
# than deleted, and flagged here rather than left to look like it proves knob-gating.
expect_contains "B11e …and with BIONIC_WALL_VERBOSE=1 the prose is there too" \
  "On the budget: alpha.test.sh beta.test.sh" "$VERR"
expect_eq "B11e …with the one line still first" \
  "bionic: suite-run refused — allowed: alpha.test.sh beta.test.sh (run only the budgeted suites)" \
  "$(printf '%s\n' "$VERR" | head -1)"

section "B12 — a shell-backgrounded suite is caught like a tool-backgrounded one (D8, REQ-6)"
# THE GAP RESEARCH ROW 6 MEASURED. ARM 1 used to read only the Bash tool's
# `run_in_background` flag; every one of these six forms backgrounds the suite through
# ordinary shell syntax instead, with the flag left UNSET (never declared false — the CLI
# omits the key, and `guarded`'s default bg arg is "omit", the same shape). ARM 1 fires
# regardless of budget (B7), so R1's off-budget row is reused rather than a fresh repo.
for sp in 'bash tests/run.sh &' \
          'nohup bash tests/run.sh &' \
          'while :; do bash tests/run.sh; done &' \
          '( bash tests/run.sh ) &' \
          'bash tests/run.sh > /tmp/bg-x.log 2>&1 &' \
          'bash tests/run.sh & disown'; do
  guarded "$R1" "$sp"
  expect_eq "B12a shell-backgrounded [$sp] is REFUSED" "2" "$ST"
  expect_contains "B12a …by the same B-9 fact" \
    "a backgrounded suite's result is never read" "$ERR"
done

# AC-6.2: setsid alone (no trailing &) is caught too — cmd_class classifies it `suite`
# (tests/cmd-class.test.sh C1/C9 own the classifier fact) and ARM 1 refuses it here.
guarded "$R1" 'setsid bash tests/run.sh'
expect_eq "B12b setsid (no &) is REFUSED" "2" "$ST"
expect_contains "B12b …by the same B-9 fact" \
  "a backgrounded suite's result is never read" "$ERR"

# AC-6.3: the foreground forms are untouched. alpha.test.sh is ON R1's budget so a false
# refusal here can only be this new arm, never ARM 2.
guarded "$R1" 'tests/run.sh --only alpha.test.sh'
expect_eq "B12c a plain foreground suite is ALLOWED" "0" "$ST"
expect_empty "B12c …silently" "$OUT$ERR"

guarded "$R1" 'tests/run.sh --only alpha.test.sh > /tmp/bg-log 2>&1; echo rc=$?'
expect_eq "B12d a redirected foreground suite (2>&1, no trailing &) is ALLOWED" "0" "$ST"
expect_empty "B12d …silently" "$OUT$ERR"

guarded "$R1" 'tests/run.sh --only alpha.test.sh && echo done'
expect_eq "B12e a suite followed by && is ALLOWED" "0" "$ST"
expect_empty "B12e …silently" "$OUT$ERR"

guarded "$R1" 'tests/run.sh --only alpha.test.sh --note "a & b"'
expect_eq "B12f a & INSIDE QUOTES is not read as backgrounding" "0" "$ST"
expect_empty "B12f …silently" "$OUT$ERR"

# AC-6.4: main-thread calls (no agent_id) are unchanged by this arm. THIS arm's own
# engagement-guard predicate returns 0 in silence for a main-thread payload (no `agent_id`)
# regardless of IS_BACKGROUND — but farm-out-reminder.sh, a SIBLING arm in the same
# compound (hooks/bash-walls.sh), independently refuses a suite-class command on the
# orchestrator thread for its own reason. So the observable here is not silence; it is
# that THIS arm's fact never speaks — the refusal that does reach the user is farm-out's.
guarded "$R1" 'bash tests/run.sh &' ""
expect_absent "B12g the main thread never hears this arm's fact" \
  "a backgrounded suite's result is never read" "$OUT$ERR"

section "B13 — REQ-1 AC-1.5: the row's DECLARED runs are the budget for a runner form"
# THE HOLE THIS CLOSES. `suites_allowed=` is a set of shell-suite BASENAMES, and a repo whose
# tests are jest or pytest can put nothing in it — its brief declares its runs under
# `Re-executes:` instead, which `hooks/dispatch-preflight.sh` lifts (marks kept, collapsed,
# at most three — A-T1.4) onto the roster row as `re_executes=`. This section is the other
# end of that field: the arm admits a suite-class command that is on `suites_allowed=` OR
# equals one of the declared runs, and refuses the rest with the refusal B1c already pins.
#
# EXACTLY the declared run, not a prefix of it. `npx jest` and `npx jest --testPathPatterns
# 'x'` are different spends — the first runs the whole tree — so a set that admitted the
# bare form because the declared one starts with it would be the one-regression rule lost
# by a spelling.

R13=$(mk_repo b13)
dispatched "$R13" "$ACTOR" name=w-b13 "suites_allowed=alpha.test.sh" \
  suites_source=declared files=src/widget.ts \
  "re_executes=\`npx jest --testPathPatterns 'x'\`"

guarded "$R13" "npx jest --testPathPatterns 'x'"
expect_eq "B13a the run the brief DECLARED is allowed" "0" "$ST"
expect_empty "B13a …silently" "$OUT$ERR"

guarded "$R13" 'npx jest'
expect_eq "B13b a runner form OUTSIDE the declared set is REFUSED" "2" "$ST"
expect_contains "B13b …naming the run that was asked for" "npx jest" "$VERR"
expect_contains "B13b …and the run that was on the budget" "--testPathPatterns" "$VERR"
expect_contains "B13b …and calling itself a BUDGET, not a wall" "BUDGET" "$VERR"
expect_empty "B13b …with nothing on stdout" "$OUT"

# ONE RUN, TYPED WIDER. The lift collapses whitespace inside a marked run before it writes
# the row, so the comparison collapses the command the same way or the two ends disagree
# about a run they both hold.
guarded "$R13" "npx   jest  --testPathPatterns 'x'"
expect_eq "B13c the same run typed with wider spacing is the same run" "0" "$ST"
expect_empty "B13c …silently" "$OUT$ERR"

# A PREFIX THE LIBRARY ALREADY STRIPS is the same run too — the reading, not the typing,
# decides. `timeout <n>` is the shape a dispatched writer's own brief tells it to use.
guarded "$R13" "timeout 600 npx jest --testPathPatterns 'x'"
expect_eq "B13d the declared run under a stripped prefix is allowed" "0" "$ST"
expect_empty "B13d …silently" "$OUT$ERR"

# THE SHELL SPELLING READS THE SAME FIELD. A declared run naming a shell suite admits that
# suite even when `suites_allowed=` does not carry it: the two labels are two spellings of
# one declaration (AC-1.2), and an arm that honoured only one of them would refuse a brief
# the dispatch wall admitted.
R13B=$(mk_repo b13b)
dispatched "$R13B" "$ACTOR" name=w-b13b "suites_allowed=alpha.test.sh" \
  suites_source=declared files=payload/scripts/lib/widget.sh \
  "re_executes=\`tests/run.sh --only gamma.test.sh\`"
guarded "$R13B" 'tests/run.sh --only gamma.test.sh'
expect_eq "B13e a declared run naming a shell suite is allowed" "0" "$ST"
expect_empty "B13e …silently" "$OUT$ERR"
guarded "$R13B" 'tests/run.sh --only delta.test.sh'
expect_eq "B13f …and a suite NEITHER channel names is still refused" "2" "$ST"
expect_contains "B13f …naming the suite that was asked for" "delta.test.sh" "$VERR"

# NO RECORDED SET REFUSES THE RUNNER SPELLING TOO (wave-27 T5, D15). A row with neither
# `suites_allowed=` nor `re_executes=` records no set, and a named run is refused with the
# reason, exactly as a named suite is (B4b-B4d) — never admitted unbudgeted.
R13C=$(mk_repo b13c)
dispatched "$R13C" "$ACTOR" name=w-b13c files=src/widget.ts
guarded "$R13C" "npx jest --testPathPatterns 'x'"
expect_eq "B13g with NO budget on the row a runner form is refused" "2" "$ST"
expect_contains "B13g …saying no set is recorded" "no suite set is recorded for this agent" "$ERR"
expect_contains "B13g …naming the run it was asked for" "npx jest --testPathPatterns 'x'" "$VERR"

# …AND `Suites: none` IS A STATED EMPTY SET, for the runner spelling too. AC-1.7's words are
# "admitted at dispatch, every suite refused at run time"; before this wave the runner forms
# were the exception that made that sentence false.
R13D=$(mk_repo b13d)
dispatched "$R13D" "$ACTOR" name=w-b13d suites_allowed=none suites_source=declared files=
guarded "$R13D" 'pytest tests/x.py'
expect_eq "B13h a waived row refuses the runner spelling too" "2" "$ST"
expect_contains "B13h …with the budget refusal" "BUDGET" "$VERR"

# THE FULL-TREE ARM IS NOT WEAKENED BY THE NEW CHANNEL. `tests/run.sh` fails closed against
# a row that does not carry it, whatever that row declares under `re_executes=`.
guarded "$R13" 'bash tests/run.sh'
expect_eq "B13i the full tree is still REFUSED against a row that does not carry it" "2" "$ST"
expect_contains "B13i …by the full-tree arm, not the budget one" \
  "The full suite runs once, on the head being released" "$VERR"

# …AND A BRIEF CANNOT BUY THE FULL TREE WITH THE NEW LABEL. The dispatch wall judges the
# `run.sh` token in `suites_allowed=` and reads nothing else, so a run declared under
# `Re-executes:` is unjudged at dispatch; if it were also admitted here, one spelling would
# spend a full run the proof record never weighed.
# The full-tree arm therefore runs AHEAD of the declared runs, and this row is why.
R13E=$(mk_repo b13e)
dispatched "$R13E" "$ACTOR" name=w-b13e "suites_allowed=alpha.test.sh" \
  suites_source=declared files=payload/scripts/lib/widget.sh \
  "re_executes=\`bash tests/run.sh\`"
guarded "$R13E" 'bash tests/run.sh'
expect_eq "B13j a DECLARED run naming the full tree is still REFUSED" "2" "$ST"
expect_contains "B13j …by the full-tree arm" "The full suite runs once, on the head being released" "$VERR"
# The same row still holds its other half: the declared set is not voided by the refusal.
guarded "$R13E" 'tests/run.sh --only alpha.test.sh'
expect_eq "B13k …and the row's budgeted suite still runs" "0" "$ST"
expect_empty "B13k …silently" "$OUT$ERR"


# ---- B13m/B13n (epic-23 wave-18, T4; REQ-7 AC-7.2, D4): the row ROUND-TRIPS its delimiter ----
#
# THE FAR END OF THE QUOTED-PIPE FIX. tests/dispatch-preflight.test.sh 18T4a proves the lift
# now admits a run whose pipe is inside quotes; this is the half that decides whether that
# admission was worth anything. The row is pipe-delimited, the writer used to fold `|` to a
# space in every field, and this arm compares the declared run to the agent's command
# character for character — so before the fix the dispatch wall admitted a command this
# wall then refused, forty minutes later, as undeclared. That is the wave-16 T25 failure
# reached through a different door.
#
# THE ROW HERE IS BUILT BY THE PRODUCTION WRITER (this file's `add_row`), so the encoding
# under test is the one dispatch actually writes, never a spelling this suite invented.
#
# fails-when: the declared command is refused; the row carries a raw `|` or a folded space
# where the pipe was; or the refusal prints the budget with the encoding still in it.
R13F=$(mk_repo b13f)
B13_QP="npx jest --testPathPattern='(a|b).spec.ts'"
dispatched "$R13F" "$ACTOR" name=w-b13f "suites_allowed=alpha.test.sh" \
  suites_source=declared files=src/widget.ts "re_executes=\`${B13_QP}\`"

B13_ROW="$(grep -v '^#' "$R13F/.bionic/tmp/roster-$SID.state" | tail -1)"
expect_contains "B13m the row carries the declared run with its pipe percent-encoded" \
  "re_executes=\`npx jest --testPathPattern='(a%7Cb).spec.ts'\`" "$B13_ROW"
# THE SEGMENT COUNT IS THE PROPERTY, not the field text: a raw pipe would have made the
# value one more segment to every by-key reader in the fleet, which is what the fold
# existed to prevent and what the encoding has to prevent without losing the character.
expect_eq "B13m2 …and it forged no segment of its own" "1" \
  "$(printf '%s' "$B13_ROW" | tr '|' '\n' | grep -c '^re_executes=' | tr -d ' ')"

guarded "$R13F" "$B13_QP"
expect_eq "B13n the exact declared run, quoted pipe and all, is ALLOWED" "0" "$ST"
expect_empty "B13n2 …silently" "$OUT$ERR"

# AND THE REFUSAL SPEAKS THE AUTHOR'S SPELLING. `On the budget:` is read by a human who is
# about to retype the command; printing the row's storage form there would hand them a
# command that cannot run.
guarded "$R13F" 'npx jest'
expect_eq "B13n3 a command outside the declared set is still REFUSED" "2" "$ST"
expect_contains "B13n4 …and the budget it prints holds the pipe, not the encoding" \
  "(a|b).spec.ts" "$VERR"
expect_absent "B13n5 …with no percent-encoding shown to the reader" "%7C" "$VERR"

# ---- B13o/B13p (epic-23 wave-18, T5; REQ-8 AC-8.1, D12): TWO declared runs, both on the
# budget, an undeclared third still refused ----
#
# THE CONTROL FOR THE DISPATCH-SIDE FIX. `tests/dispatch-preflight.test.sh` 18T5a proves the
# LIFT reads two runs back onto the roster row; this is the far end, over a row the
# production writer built the same way B13m/B13n above prove it for one run — the
# suite-run wall (`_run_is_declared`, `payload/scripts/lib/walls.sh`) loops every
# backtick-marked run on `re_executes=`, so a row declaring two must admit either one, and
# still refuse a run neither declares.
#
# fails-when: the second declared run is refused, or the undeclared control is admitted.
R13G=$(mk_repo b13g)
dispatched "$R13G" "$ACTOR" name=w-b13g \
  suites_source=declared files=src/widget.ts \
  "re_executes=\`npx jest --testPathPatterns 'x'\` \`pytest tests/unit\`"

guarded "$R13G" "npx jest --testPathPatterns 'x'"
expect_eq "B13o the first declared run is allowed" "0" "$ST"
expect_empty "B13o …silently" "$OUT$ERR"

guarded "$R13G" 'pytest tests/unit'
expect_eq "B13o2 the second declared run is allowed too" "0" "$ST"
expect_empty "B13o2 …silently" "$OUT$ERR"

guarded "$R13G" 'go test ./...'
expect_eq "B13p a run NEITHER declared run named is still REFUSED" "2" "$ST"
expect_contains "B13p …naming the run that was asked for" "go test" "$VERR"
expect_contains "B13p …and calling itself a BUDGET, not a wall" "BUDGET" "$VERR"


section "B14 — wave-24 T5 (AC-6.4, 7.3, 7.5, 7.6): the classifier is right in both directions, at the wall"
# The library rows live in tests/cmd-class.test.sh §WAIT/§CASE/§REDIR/§LOOP/§VAR; these are
# the same shapes through the shipped hook, against R1's row (alpha, beta on the budget), so
# a false refusal the library stopped making and a bypass it closed are both seen where an
# agent meets them.

# ADMITTED NOW (were refused).
guarded "$R1" 'tests/run.sh --only alpha.test.sh & tests/run.sh --only beta.test.sh & wait'
expect_eq "B14a a fan-out that waits is ALLOWED" "0" "$ST"
expect_empty "B14a …silently" "$OUT$ERR"
guarded "$R1" '<tests/gamma.test.sh wc -l'
expect_eq "B14b reading an off-budget suite through a glued redirect is ALLOWED" "0" "$ST"
expect_empty "B14b …silently" "$OUT$ERR"
guarded "$R1" 'case $x in (tests/gamma.test.sh) echo hit;; esac'
expect_eq "B14c an off-budget suite named only in a case pattern is ALLOWED" "0" "$ST"
expect_empty "B14c …silently" "$OUT$ERR"

# STILL REFUSED beside them, the same arm speaking.
guarded "$R1" 'tests/run.sh --only alpha.test.sh & tests/run.sh --only beta.test.sh'
expect_eq "B14d a fan-out that does not wait is still REFUSED" "2" "$ST"
expect_contains "B14d …by the backgrounded-suite fact" "a backgrounded suite's result is never read" "$ERR"

# REFUSED NOW (were bypasses — class none, so no arm saw a suite).
guarded "$R1" '2>/dev/null tests/run.sh --only gamma.test.sh'
expect_eq "B14e an off-budget run behind a leading redirect is REFUSED" "2" "$ST"
expect_contains "B14e …naming it" "gamma.test.sh" "$VERR"
guarded "$R1" 'case $x in a) tests/run.sh --only gamma.test.sh;; esac'
expect_eq "B14f an off-budget run inside a case arm is REFUSED" "2" "$ST"
expect_contains "B14f …naming it" "gamma.test.sh" "$VERR"
guarded "$R1" 'X=gamma.test.sh; bash tests/$X'
expect_eq "B14g an off-budget suite held whole in a variable is REFUSED" "2" "$ST"
expect_contains "B14g …naming it, resolved" "gamma.test.sh" "$VERR"
guarded "$R1" 'X=alpha.test.sh; tests/run.sh --only $X'
expect_eq "B14h control: the same shape holding an on-budget suite is ALLOWED" "0" "$ST"
expect_empty "B14h …silently" "$OUT$ERR"


section "B15 — wave-25 T12: a command NAME is read the way the machine resolves it"
# On a case-blind filesystem `BASH` runs bash, `SUDO` sudo and `NOHUP` nohup, so a suite
# reached through any of them is the run its lower-case form is: on the budget, off it, or
# backgrounded. Before T12 the classifier left the capitalised word as argv[0] and read
# class none, so an off-budget suite passed this arm in silence. R1's row is the budget.
guarded "$R1" 'tests/run.sh --only alpha.test.sh'
expect_eq "B15a control: an on-budget suite is allowed" "0" "$ST"
guarded "$R1" 'BASH tests/run.sh --only alpha.test.sh'
expect_eq "B15a …and so is its capitalised form" "0" "$ST"
for sp in 'BASH tests/gamma.test.sh' 'SUDO bash tests/gamma.test.sh' 'Bash -c "bash tests/gamma.test.sh"' \
          'ENV PIN=1 Bash tests/gamma.test.sh' 'cd /tmp && BASH tests/gamma.test.sh'; do
  guarded "$R1" "$sp"
  expect_eq "B15b off-budget through [$sp] is REFUSED" "2" "$ST"
  expect_contains "B15b …naming the suite that was asked for [$sp]" "gamma.test.sh" "$VERR"
done
guarded "$R1" 'PYTEST'
expect_eq "B15c a capitalised runner form outside the row's set is REFUSED, as pytest is" "2" "$ST"
guarded "$R1" 'NOHUP tests/run.sh --only alpha.test.sh'
expect_eq "B15d NOHUP backgrounds an on-budget suite: REFUSED, as nohup is" "2" "$ST"
expect_contains "B15d …by the B-9 fact" "a backgrounded suite's result is never read" "$ERR"
# WAIT is /usr/bin/WAIT, which collects no job of this shell: the suite is still backgrounded.
guarded "$R1" 'tests/run.sh --only alpha.test.sh & WAIT'
expect_eq "B15e WAIT is not wait: the backgrounded suite is REFUSED" "2" "$ST"
expect_contains "B15e …by the B-9 fact" "a backgrounded suite's result is never read" "$ERR"
# ONLY THE WORD FOLDS: an operand path keeps its case, beside B15a's positive.
guarded "$R1" 'bash TESTS/GAMMA.TEST.SH'
expect_eq "B15f an operand never folds: TESTS/GAMMA.TEST.SH is no suite file this arm budgets" "0" "$ST"

section "WRAP — an allowed suite command is rewritten into the booking shim (wave-26 T7, D8)"
# THE CLAIM. Every suite-class Bash call the walls allow comes back with `updatedInput`
# whose command is `bash <plugin-root>/scripts/booked.sh [--shell <s>] [--quiet] -- <cmd>`,
# on the main thread and in an agent, so the booking and the run stamp happen for any
# project's runner. Left alone: a command already the shim, a non-suite command, a command the
# shell itself backgrounds, and any call a wall refuses. A suite segment carrying
# `BIONIC_SLOT_HELD=1` in its own prefix is wrapped too since wave-28 T12 (W4f). The quoting rows run the wrapped
# command against THIS tree's shim and compare it with the unwrapped one run the way the
# harness runs a Bash call: `<shell> -c 'eval <cmd> < /dev/null'`.
#
# FIXTURE FIDELITY: the harness shape is measured (wave-26 T7 record, the process table of
# a live Bash call). The plugin root is this tree's payload, reached through
# payload/hooks/bash-walls.sh exactly as the plugin cache lays it out. The gate's store is a
# scratch directory, and its memory reading is pinned low, so a wrapped run is admitted at once. The harness shell is zsh where the machine has it, as on the machine
# the ruling was made on; without zsh the rows run with bash as the harness.
SHIM="$REPO_ROOT/payload/scripts/booked.sh"
WSH="$(command -v zsh 2>/dev/null)"; [ -n "$WSH" ] || WSH="$(command -v bash)"
export GIT_CEILING_DIRECTORIES="${SANDBOX%/*}"
sq() { local s="$1" r="'\\''"; s="${s//\'/$r}"; printf "'%s'" "$s"; }
# mw — the --max-wait every wrap without a kill limit carries: the staged timeout, in seconds,
# less ten (wave-27 T6, AC-8.3). The rule's own rows are tests/bash-walls.test.sh §WAIT-CEIL;
# here it is read off the same updatedInput as the command, so each row pins the relation.
mw() {
  local t; t="$(printf '%s' "$WRAP_INPUT" | jq -r '.timeout // empty' 2>/dev/null)"
  printf -- '--max-wait %s' "$(( ${t:-120000} / 1000 - 10 ))"
}

RW=$(mk_repo wrap)
dispatched "$RW" "$ACTOR" name=w-wrap "suites_allowed=t.test.sh solo.test.sh" \
  suites_source=declared files=
mkdir -p "$RW/tests"
printf '#!/bin/bash\necho t\n' > "$RW/tests/t.test.sh"
printf '#!/bin/bash\n# a timing suite\n# runner: solo\necho solo\n' > "$RW/tests/solo.test.sh"

EXTRA_ENV="SHELL=$WSH CLAUDE_CODE_SHELL="
# An agent runs a suite through the one door (wave-28 T36; D27): its wrap names the suite and
# tells the shim it is the runner (--runner), so the runner's own suites ask the gate.
guarded "$RW" 'tests/run.sh --only t.test.sh'
expect_eq "W1a an armed agent's on-budget suite is allowed" "0" "$ST"
expect_eq "W1b …and comes back as the shim around the original, under the harness's shell" \
  "bash $SHIM --shell $WSH --agent w-wrap $(mw) --suites t.test.sh --runner -- 'tests/run.sh --only t.test.sh'" "$WRAP"
expect_empty "W1c …with nothing said on stderr" "$ERR"
# THE GATE'S WHO (wave-28 T12; T2's A-T2.6). A shell does not know which agent it runs for, so
# the wall, which reads the agent's roster row, hands the shim `--agent <roster name>`; the shim
# exports it as BIONIC_GATE_AGENT, and the gate's request reads `who=<session>:<name>`.
expect_contains "W1e an armed agent's wrap names the agent by its roster name" "--agent w-wrap " "$WRAP"
expect_eq "W1d …and every other field of tool_input rides through" "86400000" \
  "$(printf '%s' "$WRAP_INPUT" | jq -r '.timeout')"

# MAIN THREAD. A suite there is farm-out's to refuse; the sanctioned override lets it run,
# and then it is wrapped like any other.
run_hook "$(mk_payload "$RW" 'FARM_OUT_ALLOW=1 bash tests/t.test.sh' "")" "$GUARD"
expect_eq "W2a the main thread's overridden suite is wrapped too" \
  "bash $SHIM --shell $WSH $(mw) --suites t.test.sh -- 'FARM_OUT_ALLOW=1 bash tests/t.test.sh'" "$WRAP"
run_hook "$(mk_payload "$RW" 'bash tests/t.test.sh' "")" "$GUARD"
expect_contains "W2b without the override farm-out refuses it" "permissionDecision" "$OUT"
expect_empty "W2c …and a refused call carries no wrap" "$WRAP"
expect_absent "W2c …anywhere on stdout" "booked.sh" "$OUT"

# UNARMED: an engaged session's agent with no roster is wrapped, so booking does not depend
# on the dispatch wall having armed the session.
RU=$(mk_repo wrap-unarmed)
rm -f "$RU/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$RU" 'bash tests/t.test.sh' "$ACTOR")" "$GUARD"
expect_eq "W3 an unarmed agent's suite is wrapped" \
  "bash $SHIM --shell $WSH --agent $ACTOR $(mw) --suites t.test.sh -- 'bash tests/t.test.sh'" "$WRAP"
expect_contains "W3b …naming the agent by its id, since no roster row names it" "--agent $ACTOR " "$WRAP"
run_hook "$(mk_payload "$RW" 'FARM_OUT_ALLOW=1 bash tests/t.test.sh' "")" "$GUARD"
expect_nonempty "W3c the main thread's suite is wrapped (the reader works here)" "$WRAP"
expect_absent "W3c …and names no agent: the gate's who is main" "--agent" "$WRAP"

# LEFT ALONE, each beside W1's positive on the same repo and the same reader.
for sp in "bash $SHIM -- 'bash tests/t.test.sh'" \
          "bash $SHIM --shell $WSH -- 'bash tests/t.test.sh'" \
          'ls -la'; do
  guarded "$RW" "$sp"
  expect_eq "W4a [$sp] is allowed" "0" "$ST"
  expect_empty "W4a …and left alone: no wrap" "$WRAP"
  expect_empty "W4a …and nothing else on either stream" "$OUT$ERR"
done
# BIONIC_SLOT_HELD=1 IS NO OPT-OUT ANY MORE (wave-28 T12; D13): a suite segment carrying it in its
# own prefix is wrapped like any other, so it asks the gate.
for sp in 'BIONIC_SLOT_HELD=1 tests/run.sh --only t.test.sh' \
          'cd . && BIONIC_SLOT_HELD=1 tests/run.sh --only t.test.sh 2>&1 | tee /tmp/w.log'; do
  guarded "$RW" "$sp"
  expect_eq "W4f [$sp] is allowed" "0" "$ST"
  expect_contains "W4f …and wrapped in the shim: the prefix skips nothing" "booked.sh" "$WRAP"
done
guarded "$RW" 'bash tests/gamma.test.sh'
expect_eq "W4b an off-budget suite is refused" "2" "$ST"
expect_absent "W4b …and the refusal carries no wrap" "booked.sh" "$OUT$WRAP"
guarded "$RW" 'bash tests/t.test.sh' "$ACTOR" true
expect_eq "W4c a backgrounded suite is still refused by ARM 1" "2" "$ST"
expect_absent "W4c …with no wrap" "booked.sh" "$OUT$WRAP"
mkdir -p "$FAKE_HOME/.claude/projects/-sandbox/memory"
guarded "$RW" "bash tests/t.test.sh > $FAKE_HOME/.claude/projects/-sandbox/memory/MEMORY.md"
expect_eq "W4d a suite whose output another wall refuses (the memory store, folded AFTER this one)" "2" "$ST"
expect_contains "W4d …is refused by that wall" "memory store" "$ERR"
expect_absent "W4d …and the refusal wins: no wrap" "booked.sh" "$OUT$WRAP"
run_hook "$(mk_payload "$RU" 'FARM_OUT_ALLOW=1 bash tests/t.test.sh &' "")" "$GUARD"
expect_empty "W4e a suite the shell backgrounds is never wrapped (its stamp would read rc=0 at once)" "$WRAP"
run_hook "$(mk_payload "$RU" 'FARM_OUT_ALLOW=1 bash tests/t.test.sh' "")" "$GUARD"
expect_nonempty "W4e …while the same suite in the foreground is" "$WRAP"

# THE TIMING CHECK: a target carrying `# runner: solo` in its first 30 lines, or
# BIONIC_QUIET=1 in the suite segment's own prefix, takes the whole machine.
# Since wave-28 T36 an agent's bare suite run is refused (the one door), so the wall's solo
# reading of a bare form is driven where bare forms still run: the main thread, by the override.
run_hook "$(mk_payload "$RW" 'FARM_OUT_ALLOW=1 bash tests/solo.test.sh' "")" "$GUARD"
expect_eq "W5a a solo suite is wrapped with --quiet" \
  "bash $SHIM --shell $WSH --quiet $(mw) --suites solo.test.sh -- 'FARM_OUT_ALLOW=1 bash tests/solo.test.sh'" "$WRAP"
run_hook "$(mk_payload "$RW" 'FARM_OUT_ALLOW=1 BIONIC_QUIET=1 bash tests/t.test.sh' "")" "$GUARD"
expect_eq "W5b BIONIC_QUIET=1 in the prefix is --quiet" \
  "bash $SHIM --shell $WSH --quiet $(mw) --suites t.test.sh -- 'FARM_OUT_ALLOW=1 BIONIC_QUIET=1 bash tests/t.test.sh'" "$WRAP"
run_hook "$(mk_payload "$RW" 'cd tests && FARM_OUT_ALLOW=1 bash solo.test.sh' "")" "$GUARD"
expect_eq "W5c a solo suite reached through a leading cd is --quiet too (and stamps where the cd went)" \
  "bash $SHIM --shell $WSH --quiet $(mw) --stamp-dir $RW/tests --suites bash_solo.test.sh -- 'cd tests && FARM_OUT_ALLOW=1 bash solo.test.sh'" "$WRAP"
run_hook "$(mk_payload "$RW" 'FARM_OUT_ALLOW=1 bash tests/t.test.sh' "")" "$GUARD"
expect_absent "W5d a plain suite is not" "--quiet" "$WRAP"
expect_nonempty "W5d …though it is wrapped" "$WRAP"
# THE DOOR'S SOLO SUITE (wave-28 T36): the runner holds a solo suite out of its batch and asks the
# gate for the whole machine itself (tests/run.sh _solo_run), so the wrap stays plain: --runner,
# never --quiet, which would make the shim hold the machine the runner then asks for.
guarded "$RW" 'tests/run.sh --only solo.test.sh'
expect_eq "W5e an agent's door call naming a solo suite is wrapped with --runner and no --quiet" \
  "bash $SHIM --shell $WSH --agent w-wrap $(mw) --suites solo.test.sh --runner -- 'tests/run.sh --only solo.test.sh'" "$WRAP"

# WHERE THE STAMP GOES (wave-26 T56, final review B1). The shim stands in the payload's cwd,
# the main checkout, while `cd <tree> || exit 1; bash tests/…` runs the suite in the tree. So
# the wall reads the command's leading literal `cd` segments up to the first suite segment —
# the same walk that finds a solo target — and hands the shim `--stamp-dir <where they lead>`.
# A `cd` the wall cannot read as a literal, or one whose reach it cannot be sure of (a
# subshell, a pipe, a background job, `pushd`), gives no option at all: the shim then stamps
# its own directory, as before, never a guessed one.
W10_ABS="$SANDBOX/trees/t1"
w10() {  # <label> <command> <expected --stamp-dir value, or "" for none> [<expected --suites word; default t.test.sh>]
  guarded "$RW" "$2"
  expect_eq "W10$1 [$2] is allowed" "0" "$ST"
  expect_nonempty "W10$1 …and wrapped" "$WRAP"
  if [ -n "$3" ]; then
    _wall_q="$3"; case "$3" in *' '*) _wall_q="$(sq "$3")" ;; esac
    expect_eq "W10$1 …with --stamp-dir $3" \
      "bash $SHIM --shell $WSH --agent w-wrap $(mw) --stamp-dir $_wall_q --suites ${4:-t.test.sh --runner} -- $(sq "$2")" "$WRAP"
  else
    expect_eq "W10$1 …with no --stamp-dir" "bash $SHIM --shell $WSH --agent w-wrap $(mw) --suites ${4:-t.test.sh --runner} -- $(sq "$2")" "$WRAP"
  fi
}
w10 a "cd $W10_ABS || exit 1; tests/run.sh --only t.test.sh" "$W10_ABS"
w10 b 'cd .worktrees/t1 && tests/run.sh --only t.test.sh' "$RW/.worktrees/t1"
w10 c "cd $SANDBOX/trees; cd t1 || exit 1; tests/run.sh --only t.test.sh" "$SANDBOX/trees/t1"
w10 d "cd '$SANDBOX/a tree' || exit 1; tests/run.sh --only t.test.sh" "$SANDBOX/a tree"
w10 e "cd \"$W10_ABS\" || exit 1; tests/run.sh --only t.test.sh" "$W10_ABS"
w10 f 'tests/run.sh --only t.test.sh' ""
# The doctrine's evidence shape (T58's), behind the cwd guard and in a brace group.
w10 g "cd $W10_ABS || exit 1; set -o pipefail; tests/run.sh --only t.test.sh 2>&1 | tee \"\$LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"\$LOG\"; exit \$rc" "$W10_ABS"
w10 h "{ cd $W10_ABS || exit 1; tests/run.sh --only t.test.sh; }" "$W10_ABS"
w10 i "cd $W10_ABS || exit 1; { tests/run.sh --only t.test.sh; echo \"rc=\$?\"; } > /dev/null 2>&1" "$W10_ABS"
# No sure reading: each of these stamps the shim's own directory, as before T56.
w10 j 'cd "$T" || exit 1; tests/run.sh --only t.test.sh' ""
w10 k "(cd $W10_ABS; true); tests/run.sh --only t.test.sh" ""
w10 l "true | cd $W10_ABS; tests/run.sh --only t.test.sh" ""
# (A `cd` the shell backgrounds, `cd x & bash tests/…`, never reaches the wrap: ARM 1 refuses it.)
w10 m "true || cd $W10_ABS; tests/run.sh --only t.test.sh" ""
w10 n "pushd $W10_ABS && tests/run.sh --only t.test.sh" ""
w10 o "cd $SANDBOX && pushd trees && tests/run.sh --only t.test.sh" ""
w10 p "if cd $W10_ABS; then tests/run.sh --only t.test.sh; fi" ""
w10 q 'cd $(git rev-parse --show-toplevel) && tests/run.sh --only t.test.sh' ""
w10 r "cd -P $W10_ABS && tests/run.sh --only t.test.sh" ""
# A cd the wall cannot read, then an ABSOLUTE one: the absolute one decides where the suite runs.
w10 s "cd \"\$T\"; cd $W10_ABS && tests/run.sh --only t.test.sh" "$W10_ABS"
# …but a RELATIVE one after it does not: relative to an unknown place is unknown.
w10 t 'cd "$T"; cd t1 && tests/run.sh --only t.test.sh' ""
# Only the cd segments AHEAD of the first suite count. (Two runs joined by `;` are named `?`, T63.)
w10 u "tests/run.sh --only t.test.sh; cd $W10_ABS; tests/run.sh --only t.test.sh" "" "'?'"
# A cd behind `&&` runs whenever the suite does (a failed step before it stops both), so it counts.
w10 v "true && cd $W10_ABS && tests/run.sh --only t.test.sh" "$W10_ABS"

# WHICH SUITES THE STAMP NAMES (wave-26 T61, critic F1; T63, critic K4-S1/N1/N2). The land keeps
# the newest stamp of each suite, so the wall hands the shim `--suites <names>`, one per suite the
# command runs, in position order, each once. A suite FILE that is this tree's own
# `tests/<basename>` (cmd_claim_scope, rooted at the stamp dir or the cwd) is its BASENAME: typed
# relative, `./`, absolute or inside the capture, one name. Every other claim is named by its RUN,
# each character outside the name set turned into `_` (`npm test` is `npm_test`). `?` is a run
# with a `$` in it, a run longer than 100 characters, a basename outside the set, and a command
# whose suite runs are joined by anything but `&&`. The unarmed agent's repo (W3) runs any suite.
w11() {  # <label> <command> <expected options between --shell and -->
  run_hook "$(mk_payload "$RU" "$2" "$ACTOR")" "$GUARD"
  expect_eq "W11$1 [$2] is wrapped naming its suites" "bash $SHIM --shell $WSH --agent $ACTOR $(mw) $3 -- $(sq "$2")" "$WRAP"
}
w11 a 'bash tests/a.test.sh && bash tests/b.test.sh' '--suites a.test.sh,b.test.sh'
w11 b 'bash tests/a.test.sh; bash tests/a.test.sh' "--suites '?'"
w11 c "bash $RU/tests/a.test.sh" '--suites a.test.sh'
w11 d "cd $W10_ABS || exit 1; set -o pipefail; bash tests/a.test.sh 2>&1 | tee \"\$LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"\$LOG\"; exit \$rc" \
  "--stamp-dir $W10_ABS --suites a.test.sh"
w11 e 'cd tests && bash a.test.sh' "--stamp-dir $RU/tests --suites bash_a.test.sh"
w11 f 'pytest -q' '--suites pytest_-q'
w11 g 'make test && bash tests/a.test.sh' '--suites make_test,a.test.sh'
w11 h "bash 'tests/a,b.test.sh'" "--suites '?'"
# A runner is named by its own text: a re-run of it clears its own red, another runner does not.
w11 i 'npm test' '--suites npm_test'
w11 j 'go test ./...' '--suites go_test_._...'
w11 k 'set -o pipefail; npm test 2>&1 | tee "$LOG"; rc=$?; echo "rc=$rc" >> "$LOG"; exit $rc' '--suites npm_test'
# Its text can never forge the field: a `,`, `|`, `=`, a quote and a space all become `_`.
w11 l 'npm test -- --grep "a,b|c=d"' '--suites npm_test_--_--grep__a_b_c_d_'
# A suite file that is not this tree's own tests/<basename> is named by its run (critic K4-N2).
w11 m 'bash other/a.test.sh' '--suites bash_other_a.test.sh'
w11 n 'bash ../x/tests/a.test.sh' '--suites bash_.._x_tests_a.test.sh'
# `?`: a `$` the reading could not resolve, and a run past 100 characters (exactly 100 is named).
w11 o 'pytest "$T"' "--suites '?'"
W11_X100="pytest tests/$(printf '%087d' 0)"
w11 p "$W11_X100" "--suites pytest_tests_$(printf '%087d' 0)"
w11 q "${W11_X100}1" "--suites '?'"
# Two suite runs whose one exit code may not speak for both (critic K4-N1): `||`, a pipe, a newline.
w11 r 'bash tests/a.test.sh || bash tests/b.test.sh' "--suites '?'"
w11 s 'bash tests/a.test.sh | tee l && bash tests/b.test.sh' "--suites '?'"
w11 t "bash tests/a.test.sh
npm test" "--suites '?'"

# A SUITE RUN THROUGH A GLOB LOOP OR A BARE VARIABLE IS WRAPPED (wave-28 T11, D13, AC-2.12). Until
# T11 the classifier read both as class none, so they ran unwrapped: no gate, no stamp. Their claim
# names a variable no stamp can place, so the shim is told `?`. Each beside a command of the same
# shape that plainly runs no suite, on the same repo and reader, which is left alone.
w11 u 'for s in tests/*.test.sh; do bash "$s"; done' "--suites '?'"
w11 v '{ for s in tests/*.test.sh; do if bash "$s"; then :; fi; done; } | tee log' "--suites '?'"
w11 w 'bash "$SUITE"' "--suites '?'"
w11 x 'sh $SUITE' "--suites '?'"
for sp in 'for f in docs/*.md; do bash "$f"; done' \
          'for s in tests/*.test.sh; do echo "$s"; done' \
          'S="$T/probe.sh"; bash "$S"'; do
  run_hook "$(mk_payload "$RU" "$sp" "$ACTOR")" "$GUARD"
  expect_eq "W12 [$sp] is allowed" "0" "$ST"
  expect_empty "W12 …and left alone: no wrap, so its cd and shell stay the harness's" "$WRAP"
done

# WHICH SHELL: CLAUDE_CODE_SHELL, then SHELL, each only when it names bash or zsh by an
# absolute path; otherwise no --shell, which is the shim's bash -c.
EXTRA_ENV="SHELL=$WSH CLAUDE_CODE_SHELL=$(command -v bash)"
guarded "$RW" 'tests/run.sh --only t.test.sh'
expect_eq "W6a CLAUDE_CODE_SHELL wins over SHELL" \
  "bash $SHIM --shell $(command -v bash) --agent w-wrap $(mw) --suites t.test.sh --runner -- 'tests/run.sh --only t.test.sh'" "$WRAP"
EXTRA_ENV="SHELL=/bin/sh CLAUDE_CODE_SHELL="
guarded "$RW" 'tests/run.sh --only t.test.sh'
expect_eq "W6b a shell the harness would not use names none: bash -c" \
  "bash $SHIM --agent w-wrap $(mw) --suites t.test.sh --runner -- 'tests/run.sh --only t.test.sh'" "$WRAP"
EXTRA_ENV="SHELL= CLAUDE_CODE_SHELL="
guarded "$RW" 'tests/run.sh --only t.test.sh'
expect_eq "W6c neither set: bash -c" "bash $SHIM --agent w-wrap $(mw) --suites t.test.sh --runner -- 'tests/run.sh --only t.test.sh'" "$WRAP"
EXTRA_ENV="SHELL=$WSH CLAUDE_CODE_SHELL="

# ONE ANSWER, BOTH REWRITES: ARM R raises a missing timeout and the wrap rewrites the
# command, in that order, on the same object.
NO_TIMEOUT=$(mk_payload "$RW" 'tests/run.sh --only t.test.sh' "$ACTOR" | jq -c 'del(.tool_input.timeout)')
EXTRA_ENV="SHELL=$WSH CLAUDE_CODE_SHELL= BASH_MAX_TIMEOUT_MS=600000"
run_hook "$NO_TIMEOUT" "$GUARD"
EXTRA_ENV="SHELL=$WSH CLAUDE_CODE_SHELL="
expect_eq "W7a a suite with no timeout is allowed" "0" "$ST"
expect_eq "W7b …its timeout is raised to the harness maximum" "600000" \
  "$(printf '%s' "$WRAP_INPUT" | jq -r '.timeout')"
expect_eq "W7c …and its command is wrapped, in the same updatedInput" \
  "bash $SHIM --shell $WSH --agent w-wrap $(mw) --suites t.test.sh --runner -- 'tests/run.sh --only t.test.sh'" "$WRAP"
expect_contains "W7d …and the repair is logged as before" "repaired from=absent to=600000" "$ERR"

# BEHAVIOUR. Each command runs once as the harness runs it and once as the harness runs its
# wrap, in the same fresh directory, with a free place. stdout, stderr, the exit code, every
# file written (path and content) and the working directory the suite saw must agree.
RX=$(mk_repo wrap-run)
rm -f "$RX/.bionic/tmp/roster-$SID.state"
EXD="$SANDBOX/exec"
fresh_exec() {
  rm -rf "$EXD"; mkdir -p "$EXD/tests" "$EXD/sub"
  printf '%s\n' '#!/bin/bash' \
    'echo "out:$#:$*:${FOO:-}:$(pwd -P)"' 'echo "err:$*" >&2' \
    'printf "%s\n" "$*" >> "$(dirname "$0")/written.txt"' \
    '[ "${1:-}" = fail ] && exit 3' 'exit 0' > "$EXD/tests/t.test.sh"
}
harness_run() {  # <command> — run it as the harness does, in $EXD; prints the observation
  ( cd "$EXD" && env -u BIONIC_GATE_ADMIT BIONIC_GATE_DIR="$SANDBOX/gate" BIONIC_GATE_POLL=0.1 BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 \
      "$WSH" -c "eval $(sq "$1") < /dev/null" > "$SANDBOX/.xo" 2> "$SANDBOX/.xe"; echo "rc=$?" > "$SANDBOX/.xr" )
  printf '%s\n--stdout--\n%s\n--stderr--\n%s\n--files--\n' "$(cat "$SANDBOX/.xr")" \
    "$(cat "$SANDBOX/.xo")" "$(cat "$SANDBOX/.xe")"
  ( cd "$EXD" && find . -type f | sort | while IFS= read -r f; do printf '%s:\n' "$f"; cat "$f"; done )
}
W8_CMDS=( "bash tests/t.test.sh 'single q' \"double q\" plain"
          'bash tests/t.test.sh "$HOME" '"'"'$HOME'"'"
          'bash tests/t.test.sh a && bash tests/t.test.sh b'
          'cd sub && bash ../tests/t.test.sh in-sub'
          'FOO=1 bash tests/t.test.sh env'
          'bash tests/t.test.sh redir > out.log 2> err.log'
          'set -o pipefail; bash tests/t.test.sh fail 2>&1 | tee run.log; echo "rc=$?"'
          'bash tests/t.test.sh fail; echo "rc=$?"'
          'bash tests/t.test.sh fail'
          "bash tests/t.test.sh \"it's\""
          "$(printf 'bash tests/t.test.sh one\nbash tests/t.test.sh two')"
          'echo "a\nb"; bash tests/t.test.sh esc'
          'F="x y"; bash tests/t.test.sh $F'
          'bash tests/t.test.sh fail | cat > /dev/null; echo "first=${pipestatus[1]}"'
          'ls nomatch*.zz; bash tests/t.test.sh glob' )
W8_I=0
for c in "${W8_CMDS[@]}"; do
  W8_I=$((W8_I + 1))
  run_hook "$(mk_payload "$RX" "$c" "$ACTOR")" "$GUARD"
  if [ -z "$WRAP" ]; then no "W8.$W8_I [$c] is wrapped" "no wrap came back (OUT=$OUT ERR=$ERR)"; continue; fi
  W8_WRAP="$WRAP"
  fresh_exec; W8_PLAIN="$(harness_run "$c")"
  fresh_exec; W8_WRAPPED="$(harness_run "$W8_WRAP")"
  expect_contains "W8.$W8_I the unwrapped run reached the suite [$c]" "./tests/written.txt:" "$W8_PLAIN"
  expect_eq "W8.$W8_I wrapped and unwrapped agree on rc, stdout, stderr, files and cwd [$c]" \
    "$W8_PLAIN" "$W8_WRAPPED"
done

# THE DIFFERENTIAL: the comparison above can fail. With no harness shell named the wrap is
# the shim's bash -c, and under a zsh harness the echo-escape command reads differently.
case "$WSH" in
  */zsh)
    EXTRA_ENV="SHELL= CLAUDE_CODE_SHELL="
    run_hook "$(mk_payload "$RX" 'echo "a\nb"; bash tests/t.test.sh esc' "$ACTOR")" "$GUARD"
    EXTRA_ENV="SHELL=$WSH CLAUDE_CODE_SHELL="
    expect_absent "W8d control: the bash -c wrap names no shell" "--shell" "$WRAP"
    expect_nonempty "W8d control: …and is a wrap" "$WRAP"
    fresh_exec; W8_PLAIN="$(harness_run 'echo "a\nb"; bash tests/t.test.sh esc')"
    fresh_exec; W8_WRAPPED="$(harness_run "$WRAP")"
    expect_ne "W8d control: …which a zsh harness disagrees with, so W8's comparison bites" \
      "$W8_PLAIN" "$W8_WRAPPED" ;;
  *) ok "W8d control skipped: no zsh, so bash is the harness and bash -c agrees with it" ;;
esac

# WHAT THE WRAP STILL LOSES, each failing LOUD, never doing something else.
# (a) A function or alias the harness's shell snapshot defines is not visible inside the
#     shim's shell: the command stops with "command not found" and exit 127.
run_hook "$(mk_payload "$RX" 't7fn && bash tests/t.test.sh fn' "$ACTOR")" "$GUARD"
W9_WRAP="$WRAP"
expect_nonempty "W9a a command calling a snapshot function is wrapped" "$W9_WRAP"
fresh_exec
W9_PLAIN="$(cd "$EXD" && "$WSH" -c "t7fn() { echo from-fn; }; eval $(sq 't7fn && bash tests/t.test.sh fn') < /dev/null" 2>&1; echo "rc=$?")"
fresh_exec
W9_WRAPPED="$(cd "$EXD" && env -u BIONIC_GATE_ADMIT BIONIC_GATE_DIR="$SANDBOX/gate" BIONIC_GATE_POLL=0.1 BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 \
  "$WSH" -c "t7fn() { echo from-fn; }; eval $(sq "$W9_WRAP") < /dev/null" 2>&1; echo "rc=$?")"
expect_contains "W9b unwrapped, the function runs" "from-fn" "$W9_PLAIN"
expect_contains "W9c wrapped, it is not found" "not found" "$W9_WRAPPED"
expect_contains "W9d …and the call ends 127, loud" "rc=127" "$W9_WRAPPED"
expect_absent "W9e …and nothing else ran in its place" "from-fn" "$W9_WRAPPED"
expect_absent "W9e …not even the suite behind &&" "out:" "$W9_WRAPPED"
# (b) A cd inside the command does not carry to the next call: the harness records the
#     directory in ITS shell after the command, and the cd happened in the shim's child.
run_hook "$(mk_payload "$RX" 'cd sub && bash ../tests/t.test.sh cd' "$ACTOR")" "$GUARD"
W9_WRAP="$WRAP"
fresh_exec
W9_PLAIN="$(cd "$EXD" && "$WSH" -c "eval $(sq 'cd sub && bash ../tests/t.test.sh cd') < /dev/null && pwd -P" 2>/dev/null | tail -1)"
fresh_exec
W9_WRAPPED="$(cd "$EXD" && env -u BIONIC_GATE_ADMIT BIONIC_GATE_DIR="$SANDBOX/gate" BIONIC_GATE_POLL=0.1 BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 \
  "$WSH" -c "eval $(sq "$W9_WRAP") < /dev/null && pwd -P" 2>/dev/null | tail -1)"
expect_eq "W9f unwrapped, the harness records the cd" "$EXD/sub" "$W9_PLAIN"
expect_eq "W9g wrapped, it records the directory the call started in" "$EXD" "$W9_WRAPPED"

finish
