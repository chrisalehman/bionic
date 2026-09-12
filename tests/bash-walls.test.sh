#!/bin/bash
# tests/bash-walls.test.sh — ONE PROCESS ON PreToolUse|Bash
# (epic-23 wave-11-lean-spine, REQ-1f (v), AC-1f.5; ADR-004; T23 rulings R3–R7).
#
# WHAT THIS FILE OWNS: the COMPOSITION. Five walls fired on every Bash tool call —
# protect-main, protect-database, the canonical-sdlc evidence gate, farm-out-reminder and
# background-suite-guard — each as its own process, each paying the loader and the preamble,
# and NO RULE said how five verdicts combine when more than one had something to say. The
# platform collected whichever arrived. This file drives the one process that replaced them
# and asserts the rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# EACH WALL'S OWN VERDICT IS *NOT* RE-TESTED HERE. Those five suites keep their own files
# and drive this same process through their own seam — tests/protect-main.test.sh,
# tests/protect-database.test.sh, tests/canonical-sdlc-evidence-gate.test.sh,
# tests/farm-out-reminder.test.sh and tests/background-suite-guard.test.sh. What is here is
# only what no per-wall suite can see: two walls speaking on one payload, two CHANNELS
# speaking on one payload, the manifest order, the partition that used to be a wrapper, and
# the fail-closed arm when the library is gone.
#
# THE TWO CHANNELS ARE THE POINT (T23 ruling R3). Four of the five refuse by exit 2 with the
# text on stderr; farm-out-reminder alone answers on stdout as JSON — `permissionDecision:
# deny` for a block and `hookSpecificOutput.additionalContext` for a nudge. Before the merge
# those were different processes and the harness reconciled them. Now they share one stdout,
# and the fold has to keep both wires legible: at most one JSON document, the refusal owning
# it when there is one.
#
# HERMETIC. Every payload is crafted and piped in; repos are throwaway git inits under a
# mktemp'd sandbox; HOME, CLAUDE_PROJECT_DIR and BIONIC_PLUGINS_DIR are pointed inside it so
# the loader cannot reach this machine's installed plugin and the audit stream cannot reach
# this machine's real one.
#
# FIXTURE FIDELITY (declared, per .claude memory fixtures-can-pin-away-the-test):
#   * PreToolUse|Bash payload envelope — the shape tests/cmd-class.test.sh pins, plus the
#     top-level `agent_id` measured for an agent context in
#     record/session-20260815-landing-supervision/t1-probe-report.md §3 (CLI 2.1.233).
#   * the engagement marker, the roster file name, the plan's `## SDLC State` block and its
#     frontmatter — each copied from the suite that owns it.
#   * session ids, agent ids, commands and plan text — SYNTHESIZED.
#
# Usage: bash tests/bash-walls.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

HOOK="${BIONIC_BASH_WALLS_UNDER_TEST:-${BIONIC_HOOKS_DIR}/bash-walls.sh}"

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
rigor: tested
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
  printf '%s' "$repo"
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
}

# arm_roster <repo> — the roster file agent-context-guard.sh required before it would let
# background-suite-guard run at all. Its PRESENCE is the whole predicate; no row is needed
# for the backgrounded-suite arm, which is the arm this suite drives.
arm_roster() { : > "$1/.bionic/tmp/roster-$SID.state"; }

# mk_payload <cwd> <command> [agent_id] [run_in_background] [tool_name] [agent_type]
#
# `agent_type` IS A SEPARATE FIELD FROM `agent_id` and the two walls read different ones:
# hooks/farm-out-reminder.sh leaves on a non-empty `agent_type` (it moves work OFF the
# orchestrator thread, so the thread it moved work TO must not be nudged), while the
# agent-context predicate is `agent_id`. A row that wants ONE wall to answer sets both.
mk_payload() {
  jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" --arg a "${3:-}" \
        --arg bg "${4:-omit}" --arg t "${5:-Bash}" --arg at "${6:-}" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:$t,
      tool_input:({command:$cmd}
                  + (if $bg == "omit" then {} else {run_in_background: ($bg == "true")} end)),
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
# line_of <regex> — the 1-based line of the first stderr line matching, or empty.
line_of()     { printf '%s\n' "$ERR" | awk -v re="$1" '$0 ~ re {print NR; exit}'; }

require_helpers mk_repo block_plan arm_roster mk_payload run_hook json_docs deny_reason \
                context_of line_of

setup_section "the repos"
R_QUIET="$(mk_repo quiet)"
R_PUSH="$(mk_repo push)"
R_TWO="$(mk_repo twoblocks)"
R_COMMIT="$(mk_repo commit)";   block_plan "$R_COMMIT"
R_CROSS="$(mk_repo crosschan)"
R_BG="$(mk_repo background)"
R_PLAIN="$(mk_repo bystander no)"
ok "seven repos built under $SANDBOX"

# ---------------------------------------------------------------------------
section "1 — five zeros: one process, one silence"

run_hook "$(mk_payload "$R_QUIET" 'ls -la')"
expect_status "1a: a command no wall objects to exits 0" 0 "$ST"
expect_empty "1b: …writing nothing to stdout" "$OUT"
expect_empty "1c: …and nothing to stderr" "$ERR"

run_hook "$(mk_payload "$R_QUIET" 'ls -la' '' omit Read)"
expect_status "1d: a non-Bash payload exits 0" 0 "$ST"
expect_empty "1e: …silently" "$OUT$ERR"

run_hook 'not json at all {'
expect_status "1f: a malformed payload exits 0" 0 "$ST"
expect_empty "1g: …silently" "$OUT$ERR"

run_hook "$(mk_payload "$R_PLAIN" 'bash tests/run.sh')"
expect_status "1h: a session that never invoked canonical-sdlc exits 0" 0 "$ST"
expect_empty "1i: …with every wall silent" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "2 — the anti-vacuity control: each of the five still speaks through the one process"
#
# One payload per wall, chosen so that only that wall answers. If any row here goes quiet
# the merge dropped a verdict, and every composition assertion below would be measuring a
# process with fewer walls in it than it claims.

run_hook "$(mk_payload "$R_QUIET" 'git push origin main')"
expect_status "2a: protect-main still refuses a push to main" 2 "$ST"
expect_contains "2b: …in its own words" "main is a protected branch here" "$ERR"

run_hook "$(mk_payload "$R_QUIET" 'psql -c "DROP TABLE users"')"
expect_status "2c: protect-database still refuses a DROP" 2 "$ST"
expect_contains "2d: …in its own words" "this command DROPs a database object" "$ERR"

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m "step 5"')"
expect_status "2e: the evidence gate still refuses a commit with placeholder evidence" 2 "$ST"
expect_contains "2f: …in its own words" "this step's evidence line is a placeholder" "$ERR"

run_hook "$(mk_payload "$R_QUIET" 'bash tests/run.sh')"
expect_status "2g: farm-out-reminder still denies at exit 0 — its channel, not exit 2" 0 "$ST"
expect_eq "2h: …on the deny wire" "deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)"
expect_contains "2i: …naming the role it redirects to" "subagent_type: test-runner" "$(deny_reason)"

# `agent_type` SILENCES farm-out-reminder so this row reads ONE wall. Without it the
# same payload is a main-thread suite command by farm-out's own rule and BOTH walls
# block — which is faithful, and section 6's business rather than this one's.
arm_roster "$R_BG"
run_hook "$(mk_payload "$R_BG" 'bash tests/run.sh' "$ACTOR" true Bash test-runner)"
expect_status "2j: background-suite-guard still refuses a backgrounded suite" 2 "$ST"
expect_contains "2k: …in its own words" "a backgrounded suite's result is never read" "$ERR"

# ---------------------------------------------------------------------------
section "3 — two walls, one payload: both reasons print, in manifest order"
#
# THE CASE ADR-004 EXISTS FOR. `git push origin main` refused by protect-main and
# `DROP TABLE` refused by protect-database, on one command line. Before the merge these
# were two processes with two unreconciled verdicts and no rule; after it, one composed
# refusal carrying both reasons in the order the manifest listed the walls.

# THE DESTRUCTIVE LITERAL IS ASSEMBLED AT RUN TIME, never spelled in this file. Every
# command a run of this suite issues passes through the machine's own installed walls,
# and a fixture that spells the statement in a tool call is refused by the very wall it
# is here to drive.
DROPSQL="$(printf 'D%sP T%sLE users' 'RO' 'AB')"
run_hook "$(mk_payload "$R_TWO" "git push origin main && psql -c \"$DROPSQL\"")"
expect_status "3a: two blockers still block" 2 "$ST"
expect_contains "3b: the FIRST wall's sentence is on the user stream" \
  "bionic: push refused — main is a protected branch here (push from your own terminal)" "$ERR"
expect_contains "3c: the SECOND wall's sentence is too — not just the first" \
  "bionic: sql refused — this command DROPs a database object (run the migration yourself)" "$ERR"
expect_true "3d: …in manifest order, by line" \
  test "$(line_of 'push refused')" -lt "$(line_of 'sql refused')"
# ONE LINE PER BLOCKER, NOT ONE PER FOLD. `refuse`'s "the user sees exactly one line" is
# the rule for ONE refusal; two walls refusing one command are two refusals, and two
# lines is exactly what the two processes this replaced put on that stream. Measured
# against the originals at the base SHA — T23 report section 7.
expect_eq "3e: exactly one user line per blocker — no more, no fewer" "2" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
# …AND STILL NO `detail` ON THE exit2 WIRE. Ruling D-1 spends that channel's one stream
# on the sentence alone; a fold composing two reasons must not start leaking the
# paragraphs behind them onto a stream that never carried one.
expect_absent "3f: the exit2 channel still carries no detail" \
  "The destination this segment resolved to" "$ERR$OUT"

# ---------------------------------------------------------------------------
section "4 — a block and a model-facing nudge on one payload (R7)"
#
# A push to main that is ALSO a chain-class command. protect-main refuses on stderr at
# exit 2; farm-out-reminder nudges on stdout as JSON. Two channels, one process, and
# neither may eat the other.

run_hook "$(mk_payload "$R_PUSH" 'git push origin main && ./build.sh && ./deploy.sh')"
expect_status "4a: the refusal decides the status" 2 "$ST"
expect_contains "4b: …and the user stream carries the push refusal" \
  "bionic: push refused — main is a protected branch here" "$ERR"
expect_eq "4c: stdout carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "4d: …the nudge, on its own channel" "chain-class command on the main thread" \
  "$(context_of)"
expect_absent "4e: the nudge never leaks onto the user's stream" \
  "production-shaped work belongs in a subagent" "$ERR"

# ---------------------------------------------------------------------------
section "5 — a refused commit and a nudge: the same shape from the other gate"

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m "step 5" && ./build.sh && ./deploy.sh')"
expect_status "5a: the gate's refusal decides the status" 2 "$ST"
expect_contains "5b: …with the gate's own words on the user stream" \
  "bionic: commit refused" "$ERR"
expect_eq "5c: stdout still carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "5d: …and it is the nudge" "chain-class command" "$(context_of)"

# ---------------------------------------------------------------------------
section "6 — two channels blocking at once: the JSON wire wins, and keeps both reasons"
#
# farm-out-reminder blocks on `deny` (exit 0 + JSON) while protect-main blocks on `exit2`
# (exit 2 + stderr). refuse.sh's channel table is what settles it: `exit2` spends its one
# wire on the user line and carries no `detail` at all, so composing onto it would DISCARD
# the very reasons the fold exists to keep. The fold picks the first mode whose channel
# carries detail, which is `deny` — and every reason survives.

run_hook "$(mk_payload "$R_CROSS" 'bash tests/run.sh && git push origin main')"
expect_eq "6a: stdout carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "6b: the push refusal's reason survives the cross-channel fold" \
  "main is a protected branch here" "$(deny_reason)$ERR"
expect_contains "6c: …and so does the farm-out redirect" "belongs in a subagent" \
  "$(deny_reason)$ERR"
# ONE USER LINE HERE, AND THAT IS THE RULING RATHER THAN A LOSS. `deny` carries the
# composed detail to the MODEL in full, so the second wall's own sentence is inside the
# reason above; refuse.sh's D-1 spends the user's stream on one line whenever the model
# has the rest, and T12 pinned that shape. Section 3's exit2-only fold is the case with
# nowhere else to put a second sentence, and it prints two.
expect_eq "6d: the user stream keeps one line when the model got the rest" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
expect_contains "6e: …and the other wall's sentence is on the model's wire" \
  "bionic: run refused — this command belongs in a subagent" "$(deny_reason)"

# ---------------------------------------------------------------------------
section "7 — the partition that used to be a wrapper (R2)"
#
# hooks/agent-context-guard.sh wrapped background-suite-guard's registration and was the
# ONLY thing keeping its backgrounded-suite arm off the main thread: driven straight, that
# wall refuses a main-thread backgrounded suite; driven through the guard it did not. The
# guard cannot wrap the compound — it would silence the other four walls in every
# main-thread session — so its predicate is a gate on that ONE function now.

run_hook "$(mk_payload "$R_BG" 'bash tests/run.sh' '' true Bash test-runner)"
expect_status "7a: a MAIN-THREAD backgrounded suite is not this wall's business" 0 "$ST"
expect_absent "7b: …the backgrounded-suite refusal does not fire there" \
  "a backgrounded suite's result is never read" "$ERR"

R_UNARMED="$(mk_repo unarmed)"
run_hook "$(mk_payload "$R_UNARMED" 'bash tests/run.sh' "$ACTOR" true Bash test-runner)"
expect_status "7c: an agent context with NO roster is not armed" 0 "$ST"
expect_absent "7d: …and the wall stays silent" "a backgrounded suite's result" "$ERR"

# THE OTHER FOUR ARE NOT GATED BY IT. This is the failure the wrapper would have caused:
# a main-thread push must still be refused, in a session with no roster at all.
run_hook "$(mk_payload "$R_UNARMED" 'git push origin main')"
expect_status "7e: the other four walls are NOT silenced on the main thread" 2 "$ST"
expect_contains "7f: …the push is still refused with no roster and no agent context" \
  "main is a protected branch here" "$ERR"

# ---------------------------------------------------------------------------
section "8 — blocks before advisories, by offset"
#
# A rule about OUTPUT order, not run order: farm-out-reminder's instrument line is written
# while it runs, which is before the fold renders anything, and the refusal still leads the
# user's stream.

run_hook "$(mk_payload "$R_TWO" "git push origin main && psql -c \"$DROPSQL\"")"
expect_nonempty "8a: the composed refusal reached the user stream" "$(line_of '^bionic: ')"
expect_eq "8b: …as the FIRST bionic line on it" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -n '^bionic: ' | head -1 | cut -d: -f1)"

# ---------------------------------------------------------------------------
section "9 — no library: fail-closed direction and reach, unchanged (R4)"
#
# THE CLASSES DISAGREE, AND THE COMPOUND ASKS FOR ONLY WHAT THE CLOSED ONES NEED.
# protect-main and the evidence gate refuse when the library cannot load; the other three
# step aside. `BIONIC_LIB_WANT` in hooks/bash-walls.sh is therefore the two CLOSED walls'
# lists and nothing else. This section's fixture has NO library at all, so the closed arm
# is the one that fires — and protect-main's arm is armed in EVERY project on the machine
# with no `.bionic` needed, which is what makes its reach every project. The four repair
# commands are still matched as whole strings, ahead of everything, and the refusal names
# `bash-walls` — what actually refused (A-54).
#
# SECTION 10 IS THE OTHER HALF of this one: a library that is whole except for a file only
# an ADVISORY wall wants, which must NOT reach this arm.

BROKEN="$SANDBOX/broken-plugin"
mkdir -p "$BROKEN/hooks" "$SANDBOX/plugins-empty"
BROKEN_REAL="$(cd "$BROKEN" && pwd -P)"
cp "$HOOK" "$BROKEN/hooks/bash-walls.sh"
NOBIONIC="$SANDBOX/nowhere/deep"
mkdir -p "$NOBIONIC"

DRV_ST=0; DRV_ERR=""; DRV_OUT=""
drive_broken() {  # <command> <cwd>
  DRV_OUT=$(jq -n --arg s "$SID" --arg c "$2" --arg m "$1" \
      '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$m}}' \
    | env HOME="$SANDBOX/home" BIONIC_PLUGINS_DIR="$SANDBOX/plugins-empty" \
          CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
          bash "$BROKEN/hooks/bash-walls.sh" 2>"$SANDBOX/.berr")
  DRV_ST=$?
  DRV_ERR=$(cat "$SANDBOX/.berr")
  return 0
}
require_helpers drive_broken

drive_broken 'git push origin main' "$NOBIONIC"
expect_status "9a: with no library the compound refuses a push" 2 "$DRV_ST"
expect_contains "9b: …in the ruled one line" "cannot load the bionic library (run /bionic:doctor)" "$DRV_ERR"

drive_broken 'ls' "$NOBIONIC"
expect_status "9c: …and refuses a command it cannot classify, in a project with no .bionic" \
  2 "$DRV_ST"

drive_broken "claude plugin update bionic@bionic" "$NOBIONIC"
expect_status "9d: the repair itself is PERMITTED, whole-string matched" 0 "$DRV_ST"
expect_empty "9e: …silently" "$DRV_ERR"

drive_broken "bash $BROKEN_REAL/scripts/doctor.sh" "$NOBIONIC"
expect_status "9f: …and so is doctor" 0 "$DRV_ST"

drive_broken "bash $BROKEN_REAL/scripts/doctor.sh; git push origin main" "$NOBIONIC"
expect_status "9g: a repair with a command chained after it is not a repair" 2 "$DRV_ST"

expect_contains "9h: …and the line names the compound, which is what refused (A-54)" \
  "bash-walls cannot load the bionic library" "$DRV_ERR"

# ---------------------------------------------------------------------------
section "10 — fail-closed is PER WALL, not per compound (A-56.1)"
#
# THE DEFECT THIS SECTION EXISTS FOR, MEASURED. Folding five hooks into one made
# `BIONIC_LIB_WANT` the UNION of five want lists, and the loader qualifies a directory
# only when it holds EVERY name on the list — so `cmd-class.sh` absent, a file only
# farm-out-reminder and background-suite-guard read, failed the WHOLE compound closed and
# refused every Bash command in every project on the machine. Before the fold that same
# damage made those two walls step aside and touched nothing else
# (tests/cmd-class.test.sh §C5). R4 puts fail-closed per WALL; this is the proof.
#
# THE TREE IS C5's OWN: a plugin-shaped directory, hooks/ beside scripts/lib/, every
# library present except the classifier. Nothing outside $SANDBOX is touched — the
# shipped library is never moved, which is the correction §C5 carries in its own header.
NOCLASS="$SANDBOX/no-classifier"
mkdir -p "$NOCLASS/hooks" "$NOCLASS/scripts/lib"
for _nc in "${BIONIC_SCRIPTS_DIR}"/payload/scripts/lib/*.sh; do
  case "$(basename "$_nc")" in cmd-class.sh) continue ;; esac
  cp "$_nc" "$NOCLASS/scripts/lib/"
done
cp "$HOOK" "$NOCLASS/hooks/bash-walls.sh"
expect_true "10a: the fixture library is whole except for the classifier" \
  test ! -e "$NOCLASS/scripts/lib/cmd-class.sh" -a -r "$NOCLASS/scripts/lib/git-argv.sh"

R_NOCLASS="$(mk_repo noclassifier)"
arm_roster "$R_NOCLASS"
NC_ST=0; NC_ERR=""; NC_OUT=""
drive_noclass() {  # <payload>
  NC_OUT=$(printf '%s' "$1" | env HOME="$FAKE_HOME" \
      BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
      CLAUDE_PROJECT_DIR= bash "$NOCLASS/hooks/bash-walls.sh" 2>"$SANDBOX/.nerr")
  NC_ST=$?
  NC_ERR=$(cat "$SANDBOX/.nerr")
  return 0
}
require_helpers drive_noclass

# THE CLOSED WALLS ARE UNTOUCHED: a push is still refused, by its own wall and not by the
# loader — the fact is protect-main's, not "cannot load the bionic library".
drive_noclass "$(mk_payload "$R_NOCLASS" 'git push origin main')"
expect_status "10b: a push is STILL refused with the classifier absent" 2 "$NC_ST"
expect_contains "10c: …by protect-main's own fact, not by the loader arm" \
  "push refused" "$NC_ERR"
expect_absent "10d: …and nothing on this stream says the library would not load" \
  "cannot load the bionic library" "$NC_ERR"

# AND AN ORDINARY COMMAND PASSES, which is the row the union broke: before this fix `ls`
# was refused in every project on the machine.
drive_noclass "$(mk_payload "$R_NOCLASS" 'ls')"
expect_status "10e: an ordinary command PASSES, where the union refused it" 0 "$NC_ST"
expect_empty "10f: …writing nothing to stdout" "$NC_OUT"

# THE TWO ADVISORY WALLS STEP ASIDE, each naming the file, once, in the words its own hook
# used before the fold (`git show 60c528b:hooks/farm-out-reminder.sh`, loader_fail_open).
drive_noclass "$(mk_payload "$R_NOCLASS" 'bash tests/run.sh' "$ACTOR" true)"
expect_status "10g: a backgrounded suite is neither refused nor classified" 0 "$NC_ST"
expect_empty "10h: …with nothing on stdout" "$NC_OUT"
expect_contains "10i: farm-out-reminder names the file it could not load" \
  "farm-out-reminder: library cmd-class.sh not found" "$NC_ERR"
expect_contains "10j: background-suite-guard names it too, for itself" \
  "background-suite-guard: library cmd-class.sh not found" "$NC_ERR"
expect_contains "10k: …and both point at the diagnosis" "/bionic:doctor" "$NC_ERR"
expect_eq "10l: …one line per wall that stood down, and no more" "2" \
  "$(printf '%s\n' "$NC_ERR" | grep -c .)"

# ANTI-VACUITY: the same payload on the WHOLE library carries the background arm's refusal,
# so the silence above is the missing file and not a fixture that never reached the wall.
R_ARMED="$(mk_repo noclassifier-control)"
arm_roster "$R_ARMED"
run_hook "$(mk_payload "$R_ARMED" 'bash tests/run.sh' "$ACTOR" true)"
expect_contains "10m: control — with the classifier present that wall does refuse" \
  "a backgrounded suite's result is never read" "$OUT$ERR"

finish
