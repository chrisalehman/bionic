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
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
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
. "$(dirname "$0")/lib/roster-row.sh"
# The one bound-marker builder (wave-23-fixit-1810 T1), for bw_bind below.
. "$(dirname "$0")/lib/bound-marker.sh"

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

require_helpers mk_repo block_plan arm_roster mk_payload run_hook json_docs deny_reason \
                context_of line_of updated_timeout_of has_updated_input updated_command_of

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

# THE SCREEN AND THE PARSER MUST AGREE (wave-14 T24, security 1b). `_wall_mentions_git` is a
# cheap superset in front of `git_argv_*`: it strips backslashes and quotes and looks for the
# substring `git`, and only a MISS short-circuits. A backslash-NEWLINE is a line continuation
# — the backslash goes and a newline is left standing between `g` and `it` — so the screen
# said "provably not a git command" for a command the parser reads as a push. Both readers of
# the screen are in this one process: protect-main (here) and the evidence gate's IS_COMMIT
# (25g(n) in tests/canonical-sdlc-evidence-gate.test.sh), so one repair has to serve both.
run_hook "$(mk_payload "$R_QUIET" "$(printf 'g\\\n''it push origin main')")"
expect_status "2b1: a 'g\<newline>it push' is a push — the screen does not hide it from protect-main" 2 "$ST"
expect_contains "2b2: …refused in protect-main's own words" "main is a protected branch here" "$ERR"

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
# …AND THE `detail` RIDES THAT WIRE NOW (ADR-030, epic-23 wave-16). Ruling D-1 spent the
# channel's one stream on the sentences alone; field 9 is `yes` for `exit2` since that
# ruling was superseded, so the composed detail follows them, bounded at twelve lines.
# WHAT 3e GUARDS IS UNCHANGED AND IS THE POINT: one SENTENCE per blocker, never two. The
# fold's extra-lines branch used to print each later blocker's line because the detail
# reached nobody; now that the detail carries that line itself, the branch stands down
# (fold.sh, A-T4.6), and 3f2 is where a return of the doubling would show.
expect_contains "3f: the exit2 channel carries the composed detail too" \
  "The destination this segment resolved to" "$ERR"
expect_eq "3f2: …with the second wall's sentence on it exactly once, not twice" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'sql refused')"
expect_absent "3f3: …and none of it on stdout, which is the JSON modes' wire" \
  "The destination this segment resolved to" "$OUT"

# ---------------------------------------------------------------------------
section "4 — a block and a model-facing nudge on one payload (R7)"
#
# A push to main that ALSO draws a farm-out nudge (a `git clone` head — the chain tier-2 nudge
# this fixture used to ride is retired, wave-24 T11). protect-main refuses on stderr at
# exit 2; farm-out-reminder nudges on stdout as JSON. Two channels, one process, and
# neither may eat the other.

run_hook "$(mk_payload "$R_PUSH" 'git clone u d && git push origin main')"
expect_status "4a: the refusal decides the status" 2 "$ST"
expect_contains "4b: …and the user stream carries the push refusal" \
  "bionic: push refused — main is a protected branch here" "$ERR"
expect_eq "4c: stdout carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "4d: …the nudge, on its own channel" "clone-class command on the main thread" \
  "$(context_of)"
expect_absent "4e: the nudge never leaks onto the user's stream" \
  "production-shaped work belongs in a subagent" "$ERR"

# ---------------------------------------------------------------------------
section "5 — a refused commit and a nudge: the same shape from the other gate"

run_hook "$(mk_payload "$R_COMMIT" 'git clone u d && git commit -m "step 5"')"
expect_status "5a: the gate's refusal decides the status" 2 "$ST"
expect_contains "5b: …with the gate's own words on the user stream" \
  "bionic: commit refused" "$ERR"
expect_eq "5c: stdout still carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "5d: …and it is the nudge" "clone-class command" "$(context_of)"

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

# ---------------------------------------------------------------------------
section "11 — the refusal staging is private, and its old name buys an attacker nothing (security F-1, performance A-1)"
#
# WHAT THIS OWNS. `wall_evidence_gate` stages its refusal in files, because the body runs in
# a subshell and a subshell cannot hand a variable back. T23 named that staging directory
# `$TMPDIR/bionic-gate-$$-$RANDOM` and created it with `mkdir -p` — a name an attacker on the
# same machine can pre-create (32,768 per pid) and a creation that accepts whatever is
# already there. Two consequences were DRIVEN by the Step-6 security axis: a symlink planted
# at `<stage>/1` was followed and its target truncated, and a regular file planted there was
# read back as a refusal the gate never made, on EVERY Bash call in an engaged session
# rather than only on a refusing one.
#
# HOW THESE ROWS PLANT DETERMINISTICALLY, which is the only reason this is testable at all.
# The old name needs the hook's pid and its first `$RANDOM` draw, and an outside attacker has
# neither. The driver below is the process under test, so it has both: `$$` is its own, and
# seeding `RANDOM` makes the first draw predictable (`a=$( RANDOM=n; echo $RANDOM )` yields
# the same value the next in-process read will). The driver plants, then re-seeds, then calls
# the wall. A trap laid at the vulnerable path is therefore laid EXACTLY, not approximately.
#
# THE BODY IS STUBBED, NOT DRIVEN. `_eg_body` is the gate's whole evidence walk; what is
# under test here is the STAGING its caller does around it, so the stub refuses (row a/b) or
# stays silent (rows c/d) on demand. The stub is installed after the library is sourced,
# which is what a shell function permits and what keeps these rows off the gate's fixtures.

TMPC="$SANDBOX/tmpctl"; mkdir -p "$TMPC"
VICTIM_DIR="$SANDBOX/victim"; mkdir -p "$VICTIM_DIR"
WALLS_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
[ -d "$WALLS_LIB" ] || WALLS_LIB="$BIONIC_HOOKS_DIR/../scripts/lib"

# tmp_drive <seed> <plant script> <stub body> -> runs wall_evidence_gate in a scratch
# process whose TMPDIR is ours, with `$RANDOM` seeded so <plant script> can name the old
# staging directory exactly. Sets TD_OUT / TD_ERR / TD_ST.
TD_OUT=""; TD_ERR=""; TD_ST=0; TD_TMPDIR=""
tmp_drive() {  # <seed> <plant> <stub>
  local seed="$1" plant="$2" stub="$3" d
  d=$(mktemp -d "$SANDBOX/drive.XXXXXX")
  # ONE TMPDIR PER DRIVE, so a row asking "what is left under TMPDIR" is asking about this
  # drive and not about the traps an earlier row deliberately left lying there.
  TD_TMPDIR="$TMPC/t$seed"; mkdir -p "$TD_TMPDIR"
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'set -uo pipefail'
    printf 'export TMPDIR=%s\n' "$TD_TMPDIR"
    printf 'export PATH=%s:$PATH\n' "$SHIMDIR"
    printf '. "%s/refuse.sh"\n' "$WALLS_LIB"
    printf '. "%s/fold.sh"\n' "$WALLS_LIB"
    printf '. "%s/walls.sh"\n' "$WALLS_LIB"
    # The old name, named here and nowhere in the shipped tree: seed, predict, plant, re-seed.
    printf 'T20_SEED=%s\n' "$seed"
    printf '%s\n' 'T20_PRED=$( RANDOM=$T20_SEED; echo $RANDOM )'
    printf '%s\n' 'T20_OLD="$TMPDIR/bionic-gate-$$-$T20_PRED"'
    printf '%s\n' "$plant"
    printf '%s\n' 'RANDOM=$T20_SEED'
    printf '%s\n' "$stub"
    printf '%s\n' 'COMMAND="git commit -m x"'
    # THROUGH THE FOLD, because `wall_evidence_gate` only STAGES its verdict — the render
    # that puts a refusal on a reader's stream is `bionic_fold`'s, and a row asserting what
    # a reader saw has to go the way the hook goes.
    printf '%s\n' 'bionic_fold PreToolUse wall_evidence_gate; exit $?'
  } > "$d/drive.sh"
  TD_OUT=$(bash "$d/drive.sh" 2>"$d/.err")
  TD_ST=$?
  TD_ERR=$(cat "$d/.err" 2>/dev/null)
}

# The `rm` shim: logs every call and then does the real thing, so row (d) can count forks
# on the path that must not fork at all.
SHIMDIR="$SANDBOX/shim"; mkdir -p "$SHIMDIR"
RMLOG="$SANDBOX/rm.log"; : > "$RMLOG"
{
  printf '%s\n' '#!/bin/bash'
  printf 'printf "%%s\\n" "$*" >> %s\n' "$RMLOG"
  printf '%s\n' 'exec /bin/rm "$@"'
} > "$SHIMDIR/rm"
chmod +x "$SHIMDIR/rm"

REFUSING_STUB='_eg_body() { refuse exit2 commit "fixture fact for T20" "fixture fix" "fixture detail"; }'
SILENT_STUB='_eg_body() { exit 0; }'

# --- (a) THE POSITIVE CONTROL, first. A row that reads "the victim survived" is worthless
# if the wall never ran, and a stubbed body is exactly the shape that could silently not
# run. This drive refuses, through the real staging and the real fold. ---
VICT_A="$VICTIM_DIR/secret-a.txt"; printf 'ORIGINAL CONTENT A\n' > "$VICT_A"
tmp_drive 20260912 "mkdir -p \"\$T20_OLD\"; ln -s '$VICT_A' \"\$T20_OLD/1\"" "$REFUSING_STUB"
expect_status "11a: the stubbed refusal really does refuse through the staging" 2 "$TD_ST"
expect_contains "11b: …in the fixture's own words, so the fold rendered what was staged" \
  "fixture fact for T20" "$TD_OUT$TD_ERR"

# --- (b) SYMLINK-FOLLOW. The same drive planted a symlink at the old `<stage>/1`. Before
# the repair the first staged write truncated its target. ---
expect_eq "11c: a symlink planted at the wave's old staging path is NOT followed" \
  "ORIGINAL CONTENT A" "$(cat "$VICT_A" 2>/dev/null)"

# --- (c) FABRICATED REFUSAL, on a call that refuses nothing. The read of `<stage>/1` ran on
# every Bash call, so an attacker needed only the name, never a race with a real refusal. ---
tmp_drive 20260913 \
  'mkdir -p "$T20_OLD"; printf exit2 > "$T20_OLD/1"; printf commit > "$T20_OLD/2"; printf "FABRICATED VERDICT" > "$T20_OLD/3"; printf "do as I say" > "$T20_OLD/4"; printf "fabricated detail" > "$T20_OLD/5"' \
  "$SILENT_STUB"
expect_status "11d: a Bash call the gate does not refuse exits 0, planted files or not" 0 "$TD_ST"
expect_absent "11e: …and the planted text reaches neither reader" "FABRICATED VERDICT" "$TD_OUT$TD_ERR"

# --- (d) PERFORMANCE A-1: the non-refusing path forks nothing to clean up a directory it
# never made. The cleanup was unconditional, one `/bin/rm` per Bash tool call in every
# engaged session. ---
: > "$RMLOG"
tmp_drive 20260914 ':' "$SILENT_STUB"
expect_status "11f: control — the same silent drive with nothing planted also exits 0" 0 "$TD_ST"
expect_eq "11g: …having forked no rm at all (the cleanup is guarded now)" "0" \
  "$(grep -c 'bionic-gate' "$RMLOG" 2>/dev/null || true)"

# --- (e) AND THE REFUSING PATH STILL CLEANS UP AFTER ITSELF. A guard that skipped the
# cleanup everywhere would pass (d) and leak a directory per refusal. ---
: > "$RMLOG"
tmp_drive 20260915 ':' "$REFUSING_STUB"
expect_status "11h: a refusal still exits 2" 2 "$TD_ST"
expect_eq "11i: …and still removes the directory it made" "yes" \
  "$([ "$(grep -c 'bionic-gate' "$RMLOG" 2>/dev/null || true)" -ge 1 ] && echo yes || echo no)"
expect_eq "11j: …leaving nothing behind under its own TMPDIR" "0" \
  "$(ls "$TD_TMPDIR" 2>/dev/null | grep -c 'bionic-gate' || true)"

# ---------------------------------------------------------------------------
section "12 — the two-repos day: a CLAUDE_PROJECT_DIR that is no project may not disarm the walls (critic Issue 2, A-85)"
#
# THE CONDITION IS ORDINARY. A session launched outside a bionic project and then worked
# inside one keeps CLAUDE_PROJECT_DIR at the LAUNCH directory while every payload carries
# the project as its `.cwd`. Before A-85 the ladder took the launch directory on `-d`
# alone, resolved a root that held no engagement marker, and every wall in this process
# went silent: the critic measured `push refused, rc 2` becoming rc 0 and an empty stream.
# Nine of the fifteen pre-fold hooks recovered through `.cwd` and stayed armed, so this
# suite is asserting base-faithful reach, not a new one.
#
# TWO WALLS, DELIBERATELY. protect-main refuses whether or not the session is engaged, so
# it proves the ROOT was found; the evidence gate refuses only an ENGAGED session under a
# blocking plan, so it proves the engagement marker was found under that root too. A fix
# that resolved the root and lost the marker would pass the first row and fail the second.

R_NOPROJ="$SANDBOX/launched-elsewhere"
mkdir -p "$R_NOPROJ"
git -C "$R_NOPROJ" init -q 2>/dev/null
expect_eq "12a: the launch directory is a git repo and NOT a bionic project" "yes" \
  "$([ -d "$R_NOPROJ/.git" ] && [ ! -e "$R_NOPROJ/.bionic" ] && echo yes || echo no)"

run_hook "$(mk_payload "$R_PUSH" 'git push origin main')" CLAUDE_PROJECT_DIR="$R_NOPROJ"
expect_status "12b: a push to main is still refused, rc 2" 2 "$ST"
expect_contains "12c: …in protect-main's own words" \
  "main is a protected branch here" "$ERR"

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m wip')" CLAUDE_PROJECT_DIR="$R_NOPROJ"
expect_status "12d: the evidence gate still refuses a commit under a blocking plan" 2 "$ST"

# THE CONTROLS. The same two payloads with CLAUDE_PROJECT_DIR pointing at the project
# itself — the rung is still taken when it names one — and with it empty, which is how
# every other row in this file drives the hook.
run_hook "$(mk_payload "$R_PUSH" 'git push origin main')" CLAUDE_PROJECT_DIR="$R_PUSH"
expect_status "12e: control — the env naming the project itself refuses too" 2 "$ST"
run_hook "$(mk_payload "$R_PUSH" 'git push origin main')"
expect_status "12f: control — the env empty refuses too" 2 "$ST"

# AND THE BYSTANDER IS STILL A BYSTANDER: falling through to `.cwd` may not arm a session
# that never engaged. The evidence gate is the arm to ask, since protect-main refuses
# unconditionally by design (§7).
run_hook "$(mk_payload "$R_PLAIN" 'bash tests/run.sh')" CLAUDE_PROJECT_DIR="$R_NOPROJ"
expect_status "12g: an unengaged session is still silent through the fall-through" 0 "$ST"
expect_empty "12h: …on both streams" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "13 — §cwd-split: the push wall judges the payload's cwd, not the hook process's own (D2, REQ-5)"
#
# walls.sh:265 used to ask `git symbolic-ref --short HEAD` with no `-C`, which answers
# about the directory the HOOK PROCESS happens to be running in — an accident of how the
# CLI launched the hook — rather than the directory the PAYLOAD names (P-B: a wall reads
# facts from its input, never from ambient process state). Every other row in this file
# lets the hook inherit this suite's own cwd, so the two are always the same directory
# and the bug is invisible (A2). This section is the one place they are made to differ
# on purpose.
#
# run_hook_in <dir> <payload> [env...] — like run_hook, but the HOOK PROCESS itself
# starts in <dir> rather than wherever this suite runs from.
run_hook_in() {
  local dir="$1" payload="$2"; shift 2
  OUT=$(cd "$dir" && printf '%s' "$payload" | env HOME="$FAKE_HOME" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
          CLAUDE_PROJECT_DIR= "$@" bash "$HOOK" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# mk_cwd_repo <name> <branch> <engaged:yes|no> — a real repo pinned to <branch> by
# `git init -b`, never mk_repo's automatic `feature/t23` checkout, because this section
# needs BOTH a main-branch and a feature-branch repo under its own control.
mk_cwd_repo() {
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp"
  git -C "$repo" init -q -b "$2" 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  [ "$3" = yes ] && : > "$repo/.bionic/tmp/engaged-$SID.state"
  printf '%s' "$repo"
}

# THE LAUNCH REPOS — where the hook PROCESS starts. Not engaged: engagement is resolved
# from the PAYLOAD's cwd (CLAUDE_PROJECT_DIR is empty in every row below, same as the
# rest of this file), so these two never need the marker.
CWD_LAUNCH_MAIN="$(mk_cwd_repo cwd-launch-main main no)"
CWD_LAUNCH_FEATURE="$(mk_cwd_repo cwd-launch-feature feature/launch no)"

# THE PAYLOAD REPOS — the directory `.cwd` names. Engaged, because this is the root
# `bionic_context` resolves and the engagement guard in hooks/bash-walls.sh reads it
# before any wall runs.
CWD_PAYLOAD_FEATURE="$(mk_cwd_repo cwd-payload-feature feature/payload yes)"
CWD_PAYLOAD_MAIN="$(mk_cwd_repo cwd-payload-main main yes)"
CWD_FALLBACK="$(mk_cwd_repo cwd-fallback main yes)"

expect_eq "13-setup: the launch repo is on main" "main" \
  "$(git -C "$CWD_LAUNCH_MAIN" symbolic-ref --short HEAD 2>/dev/null)"
expect_eq "13-setup: the other launch repo is on a feature branch" "feature/launch" \
  "$(git -C "$CWD_LAUNCH_FEATURE" symbolic-ref --short HEAD 2>/dev/null)"

# (a) Process on a main checkout, payload cwd a sandbox on a feature branch → ALLOWED.
# `git push origin HEAD` (no explicit destination name) reaches Block 3 only — the block
# a fix must scope to the PAYLOAD's branch, not the launch directory's.
run_hook_in "$CWD_LAUNCH_MAIN" "$(mk_payload "$CWD_PAYLOAD_FEATURE" 'git push origin HEAD')"
expect_status "13a: process on main + payload cwd on a feature branch — allowed" 0 "$ST"
expect_empty "13b: …silently, on both streams" "$OUT$ERR"

# (b) The reverse — process on a feature checkout, payload cwd a sandbox on main →
# REFUSED, in the existing words. Before the fix this row passed the current directory's
# OWN branch (feature/launch, not protected) and let the push through.
run_hook_in "$CWD_LAUNCH_FEATURE" "$(mk_payload "$CWD_PAYLOAD_MAIN" 'git push origin HEAD')"
expect_status "13c: process on a feature branch + payload cwd on main — refused" 2 "$ST"
expect_contains "13d: …in the existing words" "the current branch is protected" "$ERR"

# (c) A payload with no usable cwd — today's outcome, UNCHANGED. `bionic_context`'s own
# rung 3 falls back to `pwd` when the payload names nothing usable, so launching the hook
# FROM the engaged repo and handing it an empty `.cwd` reproduces exactly the behaviour
# this wall always had (AC-5.4): the branch it judges is the directory it is standing in.
run_hook_in "$CWD_FALLBACK" "$(mk_payload "" 'git push origin HEAD')"
expect_status "13e: no usable payload cwd — falls back to the hook's own directory, refused" 2 "$ST"
expect_contains "13f: …in the existing words" "the current branch is protected" "$ERR"

# ---------------------------------------------------------------------------
section "14 — repair: a suite call's timeout is raised to the harness maximum (T3, REQ-3, D4)"
#
# THE NEW ARM, between ARM 1 (backgrounded → refuse) and ARM 2 (the budget). It never
# refuses: a subagent's suite call whose `timeout` is absent, non-numeric, or below
# `BASH_MAX_TIMEOUT_MS` is rewritten via `hookSpecificOutput.updatedInput` and allowed to
# proceed, so every row here that repairs still exits 0.
#
# `agent_type: test-runner` on every repairing row, same as section 2j's convention: it
# silences farm-out-reminder so exactly one wall answers and these assertions are not
# reading a composed verdict by accident.

R_REPAIR="$(mk_repo repair)"
arm_roster "$R_REPAIR"

# (a) no `timeout` at all — the harness's own default (two minutes) is what kills a real
# suite, and this is the shape a dispatched worker's Bash call carries when it names none.
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14a: a subagent suite call with no timeout is not refused" 0 "$ST"
expect_eq "14b: …updatedInput.timeout is raised to the harness maximum" "600000" "$(updated_timeout_of)"
expect_contains "14c: …command and tool_name ride through unchanged" "bash tests/x.test.sh" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null)"
expect_contains "14d: …the repair is logged, naming the agent" \
  "canonical-sdlc [suite-timeout]: repaired from=absent to=600000 agent=$ACTOR" "$ERR"
# `log_finding`'s CHANNEL/SUBJECT/ROOT are declared lazily by the evidence gate's own
# internal body, reached only along a commit-class path a suite call never takes — a
# repair firing without its own declaration calls an undefined `bionic_finding_root`,
# which fails "command not found" on stderr beside the log line `expect_contains` above
# would still find. This is the ONE line that would have caught it.
expect_eq "14e0: …and stderr is EXACTLY that one log line — no stray shell error beside it" \
  "canonical-sdlc [suite-timeout]: repaired from=absent to=600000 agent=$ACTOR" "$ERR"
# ONE ANSWER, BOTH REWRITES (wave-26 T7, D8). The repair sets `timeout`; the booking wrap
# then rewrites `command` on the SAME object, so neither change overwrites the other.
expect_eq "14e1: …one JSON document on stdout" "1" "$(json_docs)"
expect_regex "14e2: …whose command is the booking wrap around the original" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)? --suites x\\.test\\.sh -- 'bash tests/x\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_eq "14e3: …beside the repaired timeout" "600000" "$(updated_timeout_of)"

# (b) a timeout BELOW the maximum — raised, not left alone.
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh' "$ACTOR" omit Bash test-runner 3000)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_eq "14e: a timeout below the maximum is raised to it" "600000" "$(updated_timeout_of)"
expect_contains "14f: …logged with the ORIGINAL value, not the repaired one" \
  "repaired from=3000 to=600000 agent=$ACTOR" "$ERR"

# (c) a timeout AT the maximum — nothing to repair, and ARM 2's budget arm decides the call
# instead (an empty roster row passes in silence, same as section 7's unarmed-suite rows).
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh' "$ACTOR" omit Bash test-runner 600000)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14g: a suite call already at the harness maximum is not refused" 0 "$ST"
# THE WRAP RIDES EVERY ALLOWED SUITE CALL (wave-26 T7, D8), so updatedInput is present here
# too — but its timeout is the caller's own, untouched: there was nothing to repair.
expect_eq "14h: …its timeout is left as the caller set it — there is nothing to repair" \
  "600000" "$(updated_timeout_of)"
expect_regex "14h2: …and the only rewrite is the booking wrap around the original command" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)? --suites x\\.test\\.sh -- 'bash tests/x\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_empty "14i: …no repair logged either" "$ERR"

# (d) ARM 1 UNCHANGED — a backgrounded suite is still refused, and the repair arm (which
# sits textually after ARM 1) never gets a chance to speak for it.
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh' "$ACTOR" true Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14j: a backgrounded suite is still refused — ARM 1's own verdict, unchanged" 2 "$ST"
expect_contains "14k: …in ARM 1's own words" "a backgrounded suite's result is never read" "$ERR"
expect_eq "14l: …and carries no updatedInput" "no" "$(has_updated_input)"

# (e) MAIN-THREAD CONTROL — no `agent_id` at all. The partition above ARM 1 already
# returns before the repair arm is reached; whatever else fires on this payload (farm-out-
# reminder's own tier-1 deny, unrelated to this wall), no updatedInput ever appears.
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh')" BASH_MAX_TIMEOUT_MS=600000
expect_eq "14m: a main-thread suite call carries no updatedInput — the repair never reaches it" \
  "no" "$(has_updated_input)"
# …BUT WHERE THE MAIN THREAD MAY RUN IT, IT IS BOOKED (wave-26 T7, D8). Under
# `farm-out-mode: advisory` farm-out nudges instead of refusing; the call is allowed, so the
# wrap rides beside the nudge in one document, and the timeout is the main thread's own.
R_ADV="$(mk_repo advisory)"
printf 'farm-out-mode: advisory\n' > "$R_ADV/.bionic/config.yaml"
run_hook "$(mk_payload "$R_ADV" 'bash tests/x.test.sh')" BASH_MAX_TIMEOUT_MS=600000
expect_status "14m1: an advisory main-thread suite call is allowed" 0 "$ST"
expect_eq "14m2: …one JSON document on stdout" "1" "$(json_docs)"
expect_regex "14m3: …carrying the booking wrap" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)? --suites x\\.test\\.sh -- 'bash tests/x\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_eq "14m4: …and no timeout repair on the main thread" "" "$(updated_timeout_of)"
expect_nonempty "14m4: …(the reader works: the wrap's command is non-empty on the same object)" \
  "$(updated_command_of)"

# (f) SUBAGENT, NON-SUITE CONTROL — `cmd_class` never answers "suite", so the whole
# function returns before ARM 1 or the repair arm, exactly as section 1's `ls -la` row.
run_hook "$(mk_payload "$R_REPAIR" 'ls -la' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14n: a subagent's non-suite command is untouched" 0 "$ST"
expect_eq "14o: …no updatedInput — cmd_class never reaches 'suite'" "no" "$(has_updated_input)"
expect_empty "14p: …and nothing on either stream" "$OUT$ERR"

# (g) THE CEILING ITSELF MOVES — bionic setup's 30-minute ceiling, not the 600000 stock
# default, is what a repair on an armed machine raises to.
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=1800000
expect_eq "14q: a wider harness ceiling (bionic setup's 30 minutes) is the value repaired to" \
  "1800000" "$(updated_timeout_of)"

# (h) NON-NUMERIC — a `timeout` that is not a plain integer repairs exactly like an absent
# one (D4: "absent, non-numeric, or < MAX" all repair the same way), and the log line's own
# two-shape contract (`from=<absent|n>`) has no third case for a name it cannot show, so it
# reads "absent" rather than the unusable text.
NONNUM_PAYLOAD=$(jq -n --arg s "$SID" --arg c "$R_REPAIR" --arg a "$ACTOR" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"bash tests/x.test.sh", timeout:"soon"},
    tool_use_id:"toolu_01t23nonnum", agent_id:$a, agent_type:"test-runner"}')
run_hook "$NONNUM_PAYLOAD" BASH_MAX_TIMEOUT_MS=600000
expect_eq "14r: a non-numeric timeout repairs the same as an absent one" "600000" \
  "$(updated_timeout_of)"
expect_contains "14s: …logged as 'absent', the contract's own shape for it" \
  "repaired from=absent to=600000 agent=$ACTOR" "$ERR"

# (i) THE ARM ORDER (T13, A-orch-39) — the BUDGET arm decides BEFORE the repair arm, so an
# OFF-BUDGET suite call carrying no `timeout` is REFUSED, not repaired and allowed.
#
# THIS IS THE DISCRIMINATING PAYLOAD and it is why the fixture above states no `timeout`:
# ARM R shipped (T3) between ARM 1 and ARM 2 and `return`ed the moment it staged a rewrite,
# so this exact shape — the one a dispatched worker's Bash call carries when it names no
# ceiling — never reached the budget at all. Give the row a timeout and the defect vanishes
# from the fixture along with the test for it.
#
# THREE WIRES, NOT ONE. `fold.sh` drops a staged `updatedInput` whenever anything blocked,
# so 14w alone would pass even with the arms in the wrong order; 14v is the assertion that
# cannot be satisfied by the fold, because `log_finding`'s stderr line (and its audit write)
# leave the process before the fold ever renders a verdict.
R_ORDER="$(mk_repo armorder)"
arm_roster "$R_ORDER"
# Through the one production writer, same as tests/agent-context-guard.test.sh §G9: a field
# this fixture believes in that `roster_row` stopped emitting fails loudly instead of
# quietly budgeting nothing.
. "$(dirname "$0")/lib/roster-row.sh"
roster_row_fixture "session=$SID" name=t13writer "agent_id=$ACTOR" \
  suites_allowed=alpha.test.sh suites_source=declared files= \
  >> "$R_ORDER/.bionic/tmp/roster-$SID.state"

run_hook "$(mk_payload "$R_ORDER" 'bash tests/gamma.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14t: off-budget + NO timeout: refused — the budget arm runs before the repair" \
  2 "$ST"
# Re-spelled (wave-14 T8 c088189 → T18 fcd5a16 → T25): "off budget:" inverted its own
# meaning (the set printed is the ALLOWED set, not what is off it) — the label is now
# "allowed:".
expect_contains "14u: …in the budget arm's own words" \
  "allowed:" "$ERR"
expect_contains "14u2: …and AC-5.2's set: the row's own allowed token is on this line, not just detail" \
  "alpha.test.sh" "$ERR"
expect_absent "14v: …and a REFUSED call is never repaired — no repair line on stderr" \
  "suite-timeout" "$ERR"
expect_eq "14w: …and no updatedInput on stdout either" "no" "$(has_updated_input)"

# (j) ITS PAIR — the same payload shape ON the budget is still repaired exactly as T3
# shipped it. Without this row, 14t-14w are satisfied by a wall that simply stopped
# repairing anything.
run_hook "$(mk_payload "$R_ORDER" 'bash tests/alpha.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14x: on-budget + no timeout: allowed — reaching the repair arm at all proves the budget arm passed it" 0 "$ST"
expect_eq "14y: …updatedInput.timeout still raised to the harness maximum" "600000" \
  "$(updated_timeout_of)"
expect_contains "14z: …and the repair is still logged, naming the agent" \
  "repaired from=absent to=600000 agent=$ACTOR" "$ERR"

# ---------------------------------------------------------------------------
section "15 — §budget-on-the-wire (T8, AC-5.2): the allowed set reaches exit-2 stderr"
#
# Re-spelled (wave-14 T8 c088189 → T18 fcd5a16 → T25): T25 renamed the three fact labels
# ("off budget: " -> "allowed: ", "full tree off budget: " -> "full tree refused; allowed: ",
# "unexpanded name; budget: " -> "unexpanded name; allowed: ") because the old wording put
# the ALLOWED set right after the words "off budget", which reads backwards, and rendered
# an empty set as "off budget: none" — "nothing is off budget" on a line that is refusing.
# Every assertion below checks a TOKEN or COUNT, never the label text itself, so none of
# their values change; only this note and 14u (which pinned the label) needed a re-spell.
#
# T7's repro (record/wave-14-tune-181/T7-req5-repro.md §4, ruling D-1): "On the budget: …"
# lived only in `detail`, and refuse.sh's channel table marks exit2's `detail_to_user`
# `no` — a dispatched writer's own tool_result on a budget refusal never carried the
# recorded set, only the one-line fact/fix, and that line named no set. AC-5.2's
# fails-when is exactly this: "the stderr the harness relays on exit 2 carries no suite
# tokens." This section drives all three call sites `budget_refuse` (walls.sh) folds
# through and proves each one now does, on the DEFAULT (non-verbose) channel — never
# through $VERR, which section 14 and tests/agent-context-guard.test.sh §G9 already cover.

R15="$(mk_repo budgetwire)"
: > "$R15/.bionic/tmp/roster-$SID.state"
. "$(dirname "$0")/lib/roster-row.sh"
roster_row_fixture "session=$SID" name=t15writer "agent_id=$ACTOR" \
  "suites_allowed=archive.test.sh run.sh" suites_source=derived files= \
  >> "$R15/.bionic/tmp/roster-$SID.state"

WIRE_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'

# (a) the ordinary per-suite refusal — the primary AC-5.2 site (walls.sh's own line
# number for "On the budget:" cited by the wave plan).
run_hook "$(mk_payload "$R15" 'bash tests/close-out.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15a: an off-budget suite is still refused" 2 "$ST"
expect_contains "15a2: …and the DEFAULT (non-verbose) exit-2 stderr carries the FIRST allowed token" \
  "archive.test.sh" "$ERR"
expect_contains "15a3: …and the SECOND" "run.sh" "$ERR"
# THE REMEDY (T6, REQ-5, AC-5.2): a refused writer is told who widens the budget and with
# which verb, so the report it sends is one the orchestrator can act on in one command.
expect_contains "15a6: …naming the remedy verb, amend" "session-poker.sh amend t15writer" "$ERR"
# THE FLAG FITS THE REFUSAL (wave-21 T13; walk-3b45d05 item 4). A refused SUITE is widened by
# `--suites+ <suite>`, the verb's own flag for a suite file; `--reexec+` is the flag for a run.
expect_contains "15a7: …and the flag that widens a SUITE, --suites+, naming the refused suite" \
  "amend t15writer --suites+ close-out.test.sh" "$ERR"
expect_absent "15a7b: …never the run flag --reexec+ for a suite" "--reexec+" "$ERR"
# THE LINE PASTES (wave-21 T14; critic-4e6d4a9 I4). `--reason <why>` was a redirect from a file
# named `why` with no word after it — a parse error, not a usage error — so the line the remedy
# promises is pasteable was not. The placeholder is quoted, and the whole line parses as bash.
expect_contains "15a7c: …and the reason placeholder is quoted, one shell word" \
  "amend t15writer --suites+ close-out.test.sh --reason '<why>' (main runs it)" "$ERR"
B15_LINE="$(printf '%s\n' "$ERR" | sed -n 's/.*widen it: \(.*\) (main runs it).*/\1/p' | head -1)"
expect_contains "15a7d precondition: the remedy line was read off the refusal" "session-poker.sh amend" "$B15_LINE"
expect_true "15a7e: …and the pasted line parses as bash [$B15_LINE]" bash -n -c "$B15_LINE"
expect_contains "15a8: …with the real plugin root, not the placeholder" "/hooks/session-poker.sh amend" "$ERR"
expect_absent "15a9: …never the literal <plugin-root> placeholder" "<plugin-root>" "$ERR"

# (a2) A REFUSED RUN keeps `--reexec+ '<cmd>'`: a runner command is no suite file, and a run
# is what that flag widens. A row whose budget declares one run, asked for another.
R15X="$(mk_repo budgetwirerun2)"
: > "$R15X/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" name=t15runner "agent_id=$ACTOR" \
  "re_executes=\`npx jest --testPathPatterns 'x'\`" suites_source=declared files= \
  >> "$R15X/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15X" 'npx jest --testPathPatterns y' "$ACTOR" omit Bash test-runner)"
expect_status "15a10: an undeclared run is refused" 2 "$ST"
expect_contains "15a11: …and its remedy names the run flag, --reexec+ '<cmd>'" \
  "amend t15runner --reexec+ '<cmd>'" "$ERR"
expect_absent "15a12: …never the suite flag" "--suites+" "$ERR"
expect_contains "15a12b: …with the reason placeholder quoted there too" \
  "amend t15runner --reexec+ '<cmd>' --reason '<why>' (main runs it)" "$ERR"
B15_LINE="$(printf '%s\n' "$ERR" | sed -n 's/.*widen it: \(.*\) (main runs it).*/\1/p' | head -1)"
expect_true "15a12c: …and that line parses as bash too [$B15_LINE]" bash -n -c "$B15_LINE"

# (a2b) A PLUGIN ROOT WITH A SPACE (wave-24 T28; critic I2, AC-6.5). The remedy line printed
# the root bare, so `<root with space>/hooks/session-poker.sh` pasted as two arguments. The
# line is built by `_budget_remedy_line` from `refuse_plugin_root`, which reads `$BIONIC_LIB`;
# no hook can be loaded from a root this test makes up, so the function is driven directly,
# extracted the way 15g2 extracts `_budget_wire_list`, with the loader's variable pointed at a
# root whose name holds a space. The printed line is then read back as the shell reads it.
SP_ROOT="$SANDBOX/plugin root"
mkdir -p "$SP_ROOT/scripts/lib"
SP_LINE=$(BIONIC_LIB="$SP_ROOT/scripts/lib" _BUDGET_ROW_NAME=t15sp bash -c '. "$1/refuse.sh"
  eval "$(awk "/^_budget_remedy_line\(\)/,/^}/" "$1/walls.sh")"; _budget_remedy_line alpha.test.sh' \
  _ "$WALLS_LIB")
SP_LINE="${SP_LINE#widen it: }"; SP_LINE="${SP_LINE% (main runs it)}"
expect_contains "15a13 precondition: the remedy line was built, under the spaced root" \
  "plugin root/hooks/session-poker.sh" "$SP_LINE"
SP_ARG2=$(eval "set -- $SP_LINE"; printf '%s' "$2")
expect_eq "15a13: …and pasted, the script path is ONE argument [$SP_LINE]" \
  "$SP_ROOT/hooks/session-poker.sh" "$SP_ARG2"
SP_ARG3=$(eval "set -- $SP_LINE"; printf '%s' "$3")
expect_eq "15a14: …and the verb is the next one, not the tail of a split path" "amend" "$SP_ARG3"

# (a3) THE WIRE-LIST COUNT NAMES DECLARATIONS (wave-22 T4; REQ-4, D7, AC-4.1/4.2). When the one
# declared run does not fit the verdict line's room, the line says what the count counts —
# `1 declared run (printed below)` — and the full command still prints after `On the budget:`.
# A fitting run is the command itself, unchanged (the short form, pinned below from a RED run).
R15W="$(mk_repo budgetwirelongrun)"
: > "$R15W/.bionic/tmp/roster-$SID.state"
W15_RUN="pytest tests/unit/test_a_very_long_module_name_that_cannot_fit_on_any_line.py -k widget"
roster_row_fixture "session=$SID" name=t15wide "agent_id=$ACTOR" \
  "re_executes=\`$W15_RUN\`" suites_source=declared files= \
  >> "$R15W/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15W" 'npx jest --testPathPatterns y' "$ACTOR" omit Bash test-runner)"
expect_status "15a20: an undeclared run against one over-wide declared run is refused" 2 "$ST"
W15_LINE="$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "15a21: …and the allowed clause counts the declaration, naming where the run prints" \
  "allowed: 1 declared run (printed below)" "$W15_LINE"
W15_BLOCK="$(printf '%s\n' "$ERR" | sed -n '/On the budget:/,$p')"
expect_contains "15a22: …and the full command still prints in the On the budget: block" \
  "$W15_RUN" "$W15_BLOCK"
expect_absent "15a23: …and the line no longer reads the bare count 'allowed: 1 run'" \
  "allowed: 1 run" "$W15_LINE"
# THE SHORT FORM, PINNED VERBATIM (AC-4.2): a declared run that FITS prints as itself; the verdict
# line below was copied from a RED-time run at a220bd6 and must not change.
R15S="$(mk_repo budgetwireshortrun)"
: > "$R15S/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" name=t15short "agent_id=$ACTOR" \
  "re_executes=\`npm test\`" suites_source=declared files= \
  >> "$R15S/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15S" 'npx jest --testPathPatterns y' "$ACTOR" omit Bash test-runner)"
expect_eq "15a24: a fitting declared run keeps the verdict line byte-for-byte" \
  "bionic: suite-run refused — allowed: \`npm test\` (run only the budgeted suites)" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"

# (a3) THE NAME AS THE ROSTER CARRIES IT. A row named `w budget;rm` was printed as
# `amend wbudgetrm`, a name no row carries, so the pasted command addressed nobody. A name a
# shell would split or act on is single-quoted instead, so the line is still pasteable and
# still names the row.
R15Q="$(mk_repo budgetwirequote)"
: > "$R15Q/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" "name=w budget;rm" "agent_id=$ACTOR" \
  "suites_allowed=archive.test.sh" suites_source=derived files= \
  >> "$R15Q/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15Q" 'bash tests/close-out.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15a13: an off-budget suite for a row with an unsafe name is refused" 2 "$ST"
expect_contains "15a14: …and the remedy names the row as the roster carries it, quoted" \
  "amend 'w budget;rm' --suites+ close-out.test.sh" "$ERR"
expect_absent "15a15: …never a sanitised name no row carries" "wbudgetrm" "$ERR"
# ONE VERDICT LINE, AND A DETAIL BENEATH IT (ADR-030). Until field 9 flipped, "the stream
# is one line" and "the verdict is one line" were the same measurement on `exit2`. AC-E1.3
# asks for the second — a sentence the reader is interrupted by, never wrapped — so that is
# what is counted, with the positive beside it so narrowing the count cannot pass over a
# wall that went quiet.
expect_eq "15a4: …still exactly one VERDICT line" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
expect_eq "15a4b: …with its detail beneath it, no knob set" "yes" \
  "$([ "$(printf '%s\n' "$ERR" | /usr/bin/grep -v '^bionic: ' | /usr/bin/grep -c .)" -ge 1 ] && echo yes || echo no)"
if printf '%s' "$ERR" | /usr/bin/grep -qE "$WIRE_RE"; then
  ok "15a5: …and still in AC-E1.3's one-line shape"
else
  no "15a5: …and still in AC-E1.3's one-line shape" "line=[$ERR]"
fi

# (b) the shell-variable-name case — an unexpanded `$s.test.sh` cannot be checked against
# the budget, but the budget it WOULD have checked against still belongs on the wire.
# THE BODY REASSIGNS THE VARIABLE (wave-24 T13, A-orch-15). Since T5 a loop over a literal
# word list resolves to its suites and meets the ORDINARY refusal, so the fixture that drives
# THIS arm is the one the classifier still cannot resolve: `s=c` in the body.
run_hook "$(mk_payload "$R15" 'for s in a b; do s=c; bash "tests/$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15b: an unexpanded suite name is still refused" 2 "$ST"
expect_contains "15b2: …and the recorded budget is on the DEFAULT stderr too" \
  "archive.test.sh" "$ERR"
expect_contains "15b3: …by the unexpanded-name arm, not the ordinary one" \
  "unexpanded name" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
# THE HEADER'S WORDS ARE NOT WHAT RUNS (wave-24 T26, walk-head-b surprise 3): `s=c` makes this
# loop run c twice, so printing `bash tests/a.test.sh` would be a false fix — the same wall
# refuses it. The refusal says no list can be derived and asks for the literal lines meant.
# fails-when: the reassigning loop's refusal prints its header words.
expect_contains "15b4: …saying no literal list can be derived from a body that reassigns" \
  "no literal list can be derived" "$ERR"
expect_contains "15b5: …naming the reassignment as the reason" "reassigns its variable" "$ERR"
expect_contains "15b5b: …and asking for the literal lines the agent means" \
  "Write the literal lines you mean, one call each: bash tests/<name>.test.sh" "$ERR"
expect_absent "15b6: …never the header's words as a line to run" "bash tests/a.test.sh" "$ERR"
expect_absent "15b6b: …never the canned alpha example the arm used to print" "alpha.test.sh" "$ERR"
# THE FIX IS THE LOOP'S OWN WORDS when the body leaves the variable alone (wave-24 T13, D10,
# AC-6.3): an `eval` keeps the classifier from expanding the command, and the lines the loop
# would have run are read off `cmd_suite_loop_lines` — never a canned example.
run_hook "$(mk_payload "$R15" 'for s in a b; do bash "tests/$s.test.sh"; done; eval :' "$ACTOR" omit Bash test-runner)"
expect_status "15b10: a loop the classifier will not expand is refused as unexpanded" 2 "$ST"
expect_contains "15b11: …by the unexpanded-name arm" \
  "unexpanded name" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "15b12: …printing the loop's first word as the literal line to run" \
  "    bash tests/a.test.sh" "$ERR"
expect_contains "15b13: …and its second" "    bash tests/b.test.sh" "$ERR"
# A `$` THE TEXT GIVES NO WORDS FOR still refuses, and says why it has no line to print.
run_hook "$(mk_payload "$R15" 'for s in $(ls tests); do bash "tests/$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15b7: a loop over a command substitution is refused as unexpanded" 2 "$ST"
expect_contains "15b8: …and says the text gives no literal list to print" \
  "no literal list" "$ERR"
expect_absent "15b9: …printing no line it cannot know" "bash tests/a.test.sh" "$ERR"

# (c) the full-tree case (`tests/run.sh`, not on this row's budget). A FRESH row: R15's
# own set literally contains the token "run.sh" as one of its two allowed SUITE NAMES,
# which is also the one token that waives this exact arm (walls.sh: `*" run.sh "*)
# continue`) — reusing it here would test nothing.
R15R="$(mk_repo budgetwirerun)"
: > "$R15R/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" name=t15run "agent_id=$ACTOR" \
  suites_allowed=archive.test.sh suites_source=declared files= \
  >> "$R15R/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15R" 'bash tests/run.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15c: the full tree is refused when the row does not carry it" 2 "$ST"
expect_contains "15c2: …and the recorded budget is on the DEFAULT stderr" \
  "archive.test.sh" "$ERR"

# (d) THE PAIRED NEGATIVE — a brief that declared `Suites: none` carries no fabricated
# token, and the wire says so honestly rather than silently going quiet about it.
R15N="$(mk_repo budgetwirenone)"
: > "$R15N/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" name=t15none "agent_id=$ACTOR" \
  suites_allowed=none suites_source=declared files= \
  >> "$R15N/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15N" 'bash tests/gamma.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15d: a Suites: none row still refuses" 2 "$ST"
expect_contains "15d2: …and the DEFAULT stderr says so honestly — 'none' on the wire" \
  "none" "$ERR"
# ON THE VERDICT LINE, which is where a fabricated token would do the damage: the line is
# what the reader is interrupted by and what names the budget. The refused command itself
# appears in the wall's `detail`, and since ADR-030 that detail is on the same stream, so a
# whole-stream grep can no longer tell the two apart.
expect_absent "15d3: …never a fabricated suite token on the verdict line" "gamma.test.sh" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"

# (e) A WIDE BUDGET (A-orch-17's own incident: "the row carried a 38-suite set") still
# fits ONE line — token boundaries, not a mid-name cut, and a "+N more" count for what
# does not fit.
R15W="$(mk_repo budgetwirewide)"
: > "$R15W/.bionic/tmp/roster-$SID.state"
WIDE_SET=""
for i in $(seq 1 38); do WIDE_SET="$WIDE_SET s${i}.test.sh"; done
WIDE_SET="${WIDE_SET# }"
roster_row_fixture "session=$SID" name=t15wide "agent_id=$ACTOR" \
  "suites_allowed=$WIDE_SET" suites_source=derived files= \
  >> "$R15W/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15W" 'bash tests/zzz-off-budget.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15e: an off-budget suite against a 38-suite row is refused" 2 "$ST"
expect_eq "15e2: …still exactly one VERDICT line" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
if printf '%s' "$ERR" | /usr/bin/grep -qE "$WIRE_RE"; then
  ok "15e3: …still in AC-E1.3's one-line shape (never overflows past refuse()'s own cap)"
else
  no "15e3: …still in AC-E1.3's one-line shape (never overflows past refuse()'s own cap)" "line=[$ERR]"
fi
expect_contains "15e4: …and it names at least one real suite token, not a mid-name ellipsis" \
  "s1.test.sh" "$ERR"
expect_contains "15e5: …with an honest count of what did not fit" "more" "$ERR"

# (f) CONTROL — an on-budget suite is still silent on both streams; the change above is
# additive to the refusal only, never a new nudge on the allowed path. A payload timeout
# pinned to the SAME value this call sets `BASH_MAX_TIMEOUT_MS` to keeps ARM R's
# repair-and-log silent too (section 14c: "a timeout AT the maximum — nothing to
# repair"), regardless of whatever ceiling the calling shell happens to have exported.
run_hook "$(mk_payload "$R15" 'bash tests/archive.test.sh' "$ACTOR" omit Bash test-runner 600000)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "15f: an on-budget suite is still allowed" 0 "$ST"
# THE ONLY STDOUT IS THE BOOKING WRAP (wave-26 T7, D8), which every allowed suite call
# carries: no nudge, no refusal, and nothing on stderr.
expect_empty "15f2: …stderr stays empty" "$ERR"
expect_regex "15f3: …and stdout is the booking wrap alone" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)? --suites archive\\.test\\.sh -- 'bash tests/archive\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_eq "15f4: …with no other channel beside it" '["hookEventName","updatedInput"]' \
  "$(printf '%s' "$OUT" | jq -c '.hookSpecificOutput | keys' 2>/dev/null)"

# (g) T25 fold-in (review-correctness-d3930dd.md F3, F7): THE HONEST FLOOR WHEN THERE IS NO
# ROOM AT ALL. (e) above proves the wide-budget case (a whole token plus a "+N more" count);
# these two prove the two ways that can still fail — a single token too long to fit even
# BARE (F3 — used to fall through to a character cut, printing a truncated, unrunnable
# suite name) and a column budget of zero or less on a NON-EMPTY set (F7 — used to print
# the literal `none`, the same word an EMPTY set gets). Both now render a bare count
# ("N suites") instead: never a cut name, never a false `none`.

# (g1) F3 — one suite name longer than the unexpanded-name label's own room (17 columns at
# this wave's other two literals in force) drives the deepest fallback for real, through
# the production hook.
R15L="$(mk_repo budgetwirelong)"
: > "$R15L/.bionic/tmp/roster-$SID.state"
LONG_SUITE="tests/a-suite-name-far-too-long-to-fit-even-bare-on-one-refusal-line.test.sh"
roster_row_fixture "session=$SID" name=t15long "agent_id=$ACTOR" \
  "suites_allowed=$LONG_SUITE" suites_source=derived files= \
  >> "$R15L/.bionic/tmp/roster-$SID.state"
run_hook "$(mk_payload "$R15L" 'for s in a b; do s=c; bash "tests/$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15g1: an unexpanded name against a too-long single suite is still refused" 2 "$ST"
expect_contains "15g1: …through the unexpanded-name arm this fallback is named for" \
  "unexpanded name" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "15g1: …and the line falls back to an honest count, never a cut name" \
  "1 suite" "$ERR"
expect_absent "15g1: …never a mid-name character cut (the ellipsis glyph)" "…" "$ERR"
# ON THE VERDICT LINE for the same reason as 15d3, and here the distinction is sharper
# still: the wall's detail names the suite in FULL, and the full name begins with the
# fragment a mid-name cut would leave. Only the line can answer whether anything was cut.
expect_absent "15g1: …and never the truncated fragment itself on the verdict line" \
  "tests/a-suite-name-far" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
if printf '%s' "$ERR" | /usr/bin/grep -qE "$WIRE_RE"; then
  ok "15g1: …still in AC-E1.3's one-line shape"
else
  no "15g1: …still in AC-E1.3's one-line shape" "line=[$ERR]"
fi

# (g2) F7 — a column budget of zero (or less) is not reachable through any live call site
# today (all three labels leave positive room — 17/18/32 columns, this report), so this
# drives `_budget_wire_list` directly. It is a NESTED function (defined only when
# `wall_background_suite_guard` itself runs, per bash scoping — confirmed: sourcing
# walls.sh alone registers the outer wall functions but not this one), so it is extracted
# the way cross-gate-agreement.test.sh already extracts nested/inline bodies for a
# unit-level pin: `awk` between its own `()` line and its closing `}`, then `eval`.
G7_LIB="$WALLS_LIB"
G7_NONEMPTY=$(bash -c '. "'"$G7_LIB"'/refuse.sh"; . "'"$G7_LIB"'/fold.sh"; \
  eval "$(awk "/^_budget_wire_list\(\)/,/^}/" "'"$G7_LIB"'/walls.sh")"; \
  _budget_wire_list "tests/a.test.sh tests/b.test.sh" 0')
expect_eq "15g2: a non-empty set at cols<=0 renders an honest count, never a false 'none'" \
  "2 suites" "$G7_NONEMPTY"
G7_EMPTY=$(bash -c '. "'"$G7_LIB"'/refuse.sh"; . "'"$G7_LIB"'/fold.sh"; \
  eval "$(awk "/^_budget_wire_list\(\)/,/^}/" "'"$G7_LIB"'/walls.sh")"; \
  _budget_wire_list "" 0')
expect_eq "15g2: …and a GENUINELY empty set still says 'none' (the control this pin needs)" \
  "none" "$G7_EMPTY"

# ---------------------------------------------------------------------------
section "16 — the evidence gate folds a mis-cased worktree cell too, as the landing gate does (critic C14, T46)"
#
# T41 folded `_lg_row_for_tree` (payload/scripts/lib/stop.sh) so the LANDING gate matches a
# plan row's `worktree` cell against a tree's real basename case-insensitively — the tree
# name a real dispatch produces is always `<NN>-T<n>` (capital T) while a hand-edited cell
# can drift in case. `_eg_row_for_worktree` (walls.sh) makes the SAME match for the EVIDENCE
# gate and, until this fold, still compared exactly: a row cell spelled `17-T5` against a
# real tree directory git itself named `17-t5` (lowercase) matched in one wall and not the
# other — one plan, two answers for which row owns the tree, exactly what ADR-032 exists to
# prevent. `## Tasks` at step 4/active drives the D1/ADR-031 subject fork
# (`_EG_RSTATUS = active` and `_EG_RSTEP >= 4`, both required): found, the commit is judged
# by the row's task arms and says so; missed, the gate falls back to `current:` and says
# THAT instead. Both plans below hold `current: 4`, so the fork is a no-op on `CURRENT`
# either way — the two arms differ only in which line they print, which is what these
# assertions read.
#
# A REAL LINKED WORKTREE, never a hand-planted `.git` file (mirrors
# tests/canonical-sdlc-evidence-gate.test.sh's 25g fixtures): the name the arm reads is the
# one git itself chose out of `<main>/.git/worktrees/<name>`, and on any filesystem that name
# is the literal basename `git worktree add` was given — lowercase here, deliberately, so the
# row's capitalized cell is the one thing this fixture makes wrong.
R_ROWFOLD="$(mk_repo rowfold)"
git -C "$R_ROWFOLD" worktree add -q "$R_ROWFOLD/.worktrees/17-t5" -b wt/17-t5 2>/dev/null
expect_eq "16a: the fixture's tree really is a linked worktree, named lowercase by git" \
  "17-t5" "$(basename "$(git -C "$R_ROWFOLD/.worktrees/17-t5" rev-parse --git-dir)")"

T46_ROWFOLD_PLAN='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
deploy_target: none
use_worktree: true
has_ui: false
walk: exempt
---
# plan

## SDLC State

current: 4
approved-by: fixture 2026-09-21T00:00Z "approved"
Step 4:
  worktree: .worktrees/17-t5
  base-sha: 0fe69ed
  branch: wt/17-t5

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | mis-cased worktree cell against the real (lowercase) tree | senior-implementor | — | 20m | REQ-2 | a.sh | 17-T5 | active |
'
printf '%s\n' "$T46_ROWFOLD_PLAN" > "$R_ROWFOLD/.bionic/docs/plans/active.md"
bw_bind "$R_ROWFOLD"

run_hook "$(mk_payload "$R_ROWFOLD/.worktrees/17-t5" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_ROWFOLD"
expect_status "16b: the commit is still allowed either way (Step 4's shape is honest regardless of which row answers)" 0 "$ST"
expect_contains "16c: the gate judges by the ROW's task arms — T1's cell (17-T5) still names the real (lowercase) tree" \
  "evidence-gate: judged by row T1's task arms (run at current: 4)" "$ERR"
expect_absent "16d: …never falling back to 'no ## Tasks row names worktree', which is the pre-fold miss" \
  "no ## Tasks row names worktree" "$ERR"

# THE MIRROR CASE (T50, T47's floor RED, §25g): 16a–16d's tree was lowercase, so `$_want`
# (the literal basename git gave the tree) happened to already equal a folded cell without
# needing any fold of its own — that fixture could not see a one-sided fold miss the OTHER
# direction. A real dispatch tree is never lowercase; `_eg_git_wt_name` hands back the
# capitalized name git itself chose (`<NN>-T<n>`, T46's own comment says so), and when the
# cell is spelled with the SAME case a one-sided fold still breaks the match: the cell gets
# folded to lowercase, `$_want` does not, and two identical strings compare unequal. That is
# the exact §25g failure (12 rows, `wt-T3`/`wt-T5`/`wt-T9`/`14-TC`), reproduced here with a
# real linked worktree so this file — not just the evidence-gate suite — pins it.
R_ROWFOLD2="$(mk_repo rowfold2)"
git -C "$R_ROWFOLD2" worktree add -q "$R_ROWFOLD2/.worktrees/17-T7" -b wt/17-T7 2>/dev/null
expect_eq "16e: the fixture's tree really is a linked worktree, named mixed-case by git (a real dispatch shape)" \
  "17-T7" "$(basename "$(git -C "$R_ROWFOLD2/.worktrees/17-T7" rev-parse --git-dir)")"

T50_ROWFOLD_PLAN='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
deploy_target: none
use_worktree: true
has_ui: false
walk: exempt
---
# plan

## SDLC State

current: 4
approved-by: fixture 2026-09-21T00:00Z "approved"
Step 4:
  worktree: .worktrees/17-T7
  base-sha: 0fe69ed
  branch: wt/17-T7

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | mixed-case worktree cell against the real (mixed-case) tree | senior-implementor | — | 20m | REQ-2 | a.sh | 17-T7 | active |
'
printf '%s\n' "$T50_ROWFOLD_PLAN" > "$R_ROWFOLD2/.bionic/docs/plans/active.md"
bw_bind "$R_ROWFOLD2"

run_hook "$(mk_payload "$R_ROWFOLD2/.worktrees/17-T7" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_ROWFOLD2"
expect_status "16f: the commit is still allowed either way (Step 4's shape is honest regardless of which row answers)" 0 "$ST"
expect_contains "16g: the gate judges by the ROW's task arms — T1's cell (17-T7) still names the real (mixed-case) tree" \
  "evidence-gate: judged by row T1's task arms (run at current: 4)" "$ERR"
expect_absent "16h: …never falling back to 'no ## Tasks row names worktree', which is the ONE-SIDED-fold miss (T47 §25g)" \
  "no ## Tasks row names worktree" "$ERR"

# THE `use_worktree: false` TWIN (wave-18 REQ-11, D7, backlog row 3; AC-11.1). 16a-16h both
# declare `use_worktree: true`, which is why nothing ever measured what the fork's
# substitution is WORTH. It announces "judged by row T1's task arms" and substitutes
# `CURRENT=4` — and Step 4 is a POINTER step, so a few hundred lines later the pointer exit
# takes `exit 0` on it unless the frontmatter says `use_worktree: true`. The one arm the
# substitution exists to reach — `shape_block worktree base-sha branch`, the task arms the
# note promises — was therefore skipped on every `use_worktree: false` plan, and the commit
# was admitted with the note printed and nothing checked. A substituted step is not a
# pointer step: the fork now flags its substitution and the pointer exit honours it, so the
# fork owns the arms it announces whatever `use_worktree` says.
#
# THE FIXTURE IS 16e-16h's, with two bytes changed: `use_worktree: false`, and a `Step 4:`
# block that carries a real value but NOT the three worktree fields. Both halves matter —
# the block is non-empty and placeholder-free, so it clears every arm upstream of the shape
# check and the shape check is the only thing left to refuse it.
W18_POINTER_TASKS='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the row whose tree this commit comes from | senior-implementor | — | 20m | REQ-11 | a.sh | 18-T1 | active |
'

w18_pointer_plan() {  # $1 = use_worktree value
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: audited\nscale: wave\ndeploy_target: none\nuse_worktree: %s\nhas_ui: false\nwalk: exempt\n---\n' "$1"
  printf '# plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-09-22T00:00Z approved\n'
  printf 'Step 4: dispatch ledger at .bionic/docs/record/w18/dispatch.md\n'
  printf '%s\n' "$W18_POINTER_TASKS"
}

R_PTR_FALSE="$(mk_repo ptrfalse)"
git -C "$R_PTR_FALSE" worktree add -q "$R_PTR_FALSE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
expect_eq "16i: the fixture's tree really is a linked worktree, named 18-T1 by git (a real dispatch shape)" \
  "18-T1" "$(basename "$(git -C "$R_PTR_FALSE/.worktrees/18-T1" rev-parse --git-dir)")"

w18_pointer_plan false > "$R_PTR_FALSE/.bionic/docs/plans/active.md"
bw_bind "$R_PTR_FALSE"
run_hook "$(mk_payload "$R_PTR_FALSE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_PTR_FALSE"
expect_contains "16j: the fork still announces the subject it chose, on a use_worktree: false plan" \
  "evidence-gate: judged by row T1's task arms (run at current: 4)" "$ERR"
expect_status "16k: …and the arms it announced RUN — the Step-4 shape refuses a block with no worktree fields, though use_worktree is false" \
  2 "$ST"
expect_contains "16k: …naming the three fields the task arms owe" \
  "worktree base-sha branch" "$ERR"

# THE CONTROL: the same plan, the same tree, the same commit, `use_worktree: true` — refused
# for the same three fields. Two verdicts that now agree; before this they differed on the
# frontmatter key alone, which is the defect backlog row 3 named.
R_PTR_TRUE="$(mk_repo ptrtrue)"
git -C "$R_PTR_TRUE" worktree add -q "$R_PTR_TRUE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
w18_pointer_plan true > "$R_PTR_TRUE/.bionic/docs/plans/active.md"
bw_bind "$R_PTR_TRUE"
run_hook "$(mk_payload "$R_PTR_TRUE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_PTR_TRUE"
expect_status "16l: the use_worktree: true twin refuses the same commit for the same fields" 2 "$ST"
expect_contains "16l: …naming them" "worktree base-sha branch" "$ERR"

# THE STEP-BELOW TWIN (critic C1; wave-18 REQ-11 AC-11.1, D7). 16i-16l fixed the fork that
# fires when the row's step EQUALS current: (the `active` arm at walls.sh ~:2835). A second
# fork substitutes CURRENT the same way when the row's step is BELOW current: (walls.sh
# ~:2768, `_EG_RSTEP -lt _EG_CURNUM`) — the ordinary shape once a run has advanced past Step 4
# while writer trees are still live — and until this row it set `CURRENT` without setting
# `_EG_SUBSTITUTED`, so the pointer exit fell back to the frontmatter key alone on this branch
# even though 16i-16l closed the other one.
#
# THE FIXTURE IS 16i-16l's, with one byte changed: `current: 5` instead of `current: 4`, so
# the row's step 4 is now BELOW current: and the step-below arm fires instead of the
# step-equal arm. Same tree, same row, same missing fields.
W18_BELOW_TASKS='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the row whose tree this commit comes from | senior-implementor | — | 20m | REQ-11 | a.sh | 18-T1 | active |
'

w18_below_plan() {  # $1 = use_worktree value
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: audited\nscale: wave\ndeploy_target: none\nuse_worktree: %s\nhas_ui: false\nwalk: exempt\n---\n' "$1"
  printf '# plan\n\n## SDLC State\n\ncurrent: 5\napproved-by: fixture 2026-09-22T00:00Z approved\n'
  printf 'Step 4: dispatch ledger at .bionic/docs/record/w18/dispatch.md\n'
  printf '%s\n' "$W18_BELOW_TASKS"
}

R_BELOW_FALSE="$(mk_repo belowfalse)"
git -C "$R_BELOW_FALSE" worktree add -q "$R_BELOW_FALSE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
w18_below_plan false > "$R_BELOW_FALSE/.bionic/docs/plans/active.md"
bw_bind "$R_BELOW_FALSE"
run_hook "$(mk_payload "$R_BELOW_FALSE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_BELOW_FALSE"
expect_contains "16m: the step-below fork announces the row's step too, on a use_worktree: false plan" \
  "evidence-gate: judged at row T1's step 4 (run at current: 5)" "$ERR"
expect_status "16n: …and the arms it announced RUN — the Step-4 shape refuses a block with no worktree fields, though use_worktree is false" \
  2 "$ST"
expect_contains "16n: …naming the three fields the task arms owe" \
  "worktree base-sha branch" "$ERR"

# THE CONTROL: the same plan, the same tree, the same commit, `use_worktree: true` — refused
# for the same three fields, exactly as 16l controls 16j/16k.
R_BELOW_TRUE="$(mk_repo belowtrue)"
git -C "$R_BELOW_TRUE" worktree add -q "$R_BELOW_TRUE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
w18_below_plan true > "$R_BELOW_TRUE/.bionic/docs/plans/active.md"
bw_bind "$R_BELOW_TRUE"
run_hook "$(mk_payload "$R_BELOW_TRUE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_BELOW_TRUE"
expect_status "16o: the use_worktree: true twin refuses the same commit for the same fields" 2 "$ST"
expect_contains "16o: …naming them" "worktree base-sha branch" "$ERR"


# ---------------------------------------------------------------------------
section "17 — a read-only role's commit is refused by its roster row (wave-19 REQ-8, D9)"
#
# THE BREACH (wave-18 T7c-green, ideas row 5). A `bionic:test-runner` dispatched to run the
# green suites committed on its own. Nothing stopped it: the four read-only roles carry
# `disallowedTools: Write, Edit, NotebookEdit`, never `Bash`, so `git commit` was a promise
# in prose. The role arm in wall_background_suite_guard joins the payload's `agent_id` to the
# roster and reads the winning row's `subagent_type=`.
#
# FIXTURE FIDELITY. The rows are the LIVE teammate shape R3 Q2 measured: an `intended` and a
# `confirmed` row with `agent_id=` EMPTY, then the `identified` row the recorder's
# SubagentStart arm writes carrying the id. The role is plugin-qualified (`bionic:<role>`)
# and `agent_type` carries the dispatch NAME, not the role (R3 Q2, meta.json). No plan in the
# repo, so the evidence gate admits every commit here and the role arm is the only speaker.

RO_ID="aw18-T7c-green-0123456789abcdef"
R_RO="$(mk_repo readonly)"
roster_header > "$R_RO/.bionic/tmp/roster-$SID.state"

ro_rows() {  # <repo> <name> <agent_id> <subagent_type> — the three live rows, in order
  local rf="$1/.bionic/tmp/roster-$SID.state"
  roster_row_fixture "session=$SID" status=intended   "name=$2" agent_id=   "subagent_type=$4" >> "$rf"
  roster_row_fixture "session=$SID" status=confirmed  "name=$2" agent_id=   "subagent_type=$4" \
    "teammate_id=$2@session-x" >> "$rf"
  roster_row_fixture "session=$SID" status=identified "name=$2" "agent_id=$3" "subagent_type=$4" >> "$rf"
}
ro_rows "$R_RO" w18-T7c-green "$RO_ID" bionic:test-runner
RO_COMMIT="git -C $R_RO add -A && git -C $R_RO commit -qm \"T7c-green: suites green\""

run_hook "$(mk_payload "$R_RO" "$RO_COMMIT" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17a: AC-8.1 — the T7c-green shape (a bionic:test-runner row's git commit) is REFUSED" 2 "$ST"
expect_contains "17a: …naming the role" "bionic:test-runner" "$ERR"
expect_contains "17a: …and the rule" "a read-only role never commits" "$ERR"
expect_eq "17a: …on ONE refusal line" "1" "$(printf '%s\n' "$ERR" | grep -c 'a read-only role never commits')"

# THE OTHER THREE READ-ONLY ROLES, one row each on the same repo, each with its own id.
for _ro in researcher auditor critic; do
  ro_rows "$R_RO" "w19-$_ro" "a$_ro-0123456789abcdef" "bionic:$_ro"
  run_hook "$(mk_payload "$R_RO" 'git commit -m "x"' "a$_ro-0123456789abcdef" omit Bash "w19-$_ro")"
  expect_status "17b: AC-8.1 — a bionic:$_ro row's git commit is REFUSED" 2 "$ST"
  expect_contains "17b: …naming bionic:$_ro" "bionic:$_ro" "$ERR"
done

# `git -C <dir> commit` and `git -c k=v commit` are commits by argv position — the same
# parser the evidence gate reads (tests/git-argv.test.sh).
run_hook "$(mk_payload "$R_RO" "git -c user.name=x -C $R_RO commit -m x" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17c: a global-option spelling of the commit is refused too" 2 "$ST"

# THE CONTROLS (AC-8.1's second half, AC-8.2). Each is refused by nothing else here, so an
# arm that over-reaches turns one of these to 2.
R_RO_OK="$(mk_repo readonly-controls)"
roster_header > "$R_RO_OK/.bionic/tmp/roster-$SID.state"
ro_rows "$R_RO_OK" w19-T5 aimplementor-0123456789abcdef bionic:implementor
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' aimplementor-0123456789abcdef omit Bash w19-T5)"
expect_status "17d: AC-8.1 — a bionic:implementor row's commit is ADMITTED" 0 "$ST"
expect_absent "17d: …and this arm says nothing" "read-only role" "$ERR"

run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"')"
expect_status "17e: AC-8.2 — a nameless (main-thread, no agent_id) commit is ADMITTED" 0 "$ST"
expect_absent "17e: …silently on this arm" "read-only role" "$ERR"

run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' anorow-0123456789abcdef omit Bash w19-norow)"
expect_status "17f: AC-8.2 — an agent_id with NO roster row is ADMITTED" 0 "$ST"

ro_rows "$R_RO_OK" w19-norole anorole-0123456789abcdef ""
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' anorole-0123456789abcdef omit Bash w19-norole)"
expect_status "17g: AC-8.2 — a row with an EMPTY subagent_type is ADMITTED" 0 "$ST"

# THE SUFFIX TRAP (AC-8.2: "a role is guessed from a -runner suffix"). The dispatch NAME and
# `agent_type` both read `x-runner`; the row's role is an implementor. Admitted.
ro_rows "$R_RO_OK" x-runner axrunner-0123456789abcdef bionic:implementor
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' axrunner-0123456789abcdef omit Bash x-runner)"
expect_status "17h: AC-8.2 — a row NAMED x-runner with an implementor role is ADMITTED" 0 "$ST"

# A CONSUMER'S OWN ROLE of the same bare name is not bionic's (R3 Q2 spelling 1).
ro_rows "$R_RO_OK" w19-acme aacme-0123456789abcdef acme:test-runner
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' aacme-0123456789abcdef omit Bash w19-acme)"
expect_status "17i: a consumer's acme:test-runner row is ADMITTED (the match is exact, never a suffix)" 0 "$ST"

# NOT A COMMIT: a read-only role reading git, or quoting the words, is not this arm's.
run_hook "$(mk_payload "$R_RO" 'git status && echo "git commit later"' "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17j: a bionic:test-runner's git status / quoted 'git commit' is ADMITTED" 0 "$ST"

# EVERY COMMIT-CREATING VERB, IN BOTH SPELLINGS (wave-20 T3, REQ-3, AC-3.2). The arm read
# `git commit` only, so a test-runner's `git revert HEAD`, `git cherry-pick <sha>` or `git merge`
# made a commit the arm never saw, and `env -C <dir> git commit` hid even the one verb it read
# (triage-D row 3). The arm now asks one set of eight verbs over the env-aware reader.
for _v in commit merge revert cherry-pick am rebase commit-tree update-ref; do
  run_hook "$(mk_payload "$R_RO" "git $_v x" "$RO_ID" omit Bash w18-T7c-green)"
  expect_status "17k: AC-3.2 — a bionic:test-runner's 'git $_v' is REFUSED" 2 "$ST"
  expect_contains "17k: …by the role arm ('git $_v')" "a read-only role never commits" "$ERR"
  run_hook "$(mk_payload "$R_RO" "env -C $R_RO git $_v x" "$RO_ID" omit Bash w18-T7c-green)"
  expect_status "17k: AC-3.2 — a bionic:test-runner's 'env -C <dir> git $_v' is REFUSED" 2 "$ST"
  expect_contains "17k: …by the role arm ('env -C <dir> git $_v')" "a read-only role never commits" "$ERR"
done
run_hook "$(mk_payload "$R_RO" 'git revert HEAD' "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: AC-3.2 — the criterion's own 'git revert HEAD' is REFUSED" 2 "$ST"
run_hook "$(mk_payload "$R_RO" "env -C $R_RO git cherry-pick 0123abc" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: AC-3.2 — the criterion's own 'env -C <dir> git cherry-pick <sha>' is REFUSED" 2 "$ST"
run_hook "$(mk_payload "$R_RO" "env -i git commit -m x" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: …and 'env -i git commit' is REFUSED" 2 "$ST"
# NOT A COMMIT-CREATING VERB: reading history is still a read-only role's work.
run_hook "$(mk_payload "$R_RO" "env -C $R_RO git log --merge -1 && git diff HEAD~1" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: a bionic:test-runner's 'env -C <dir> git log --merge' / 'git diff' is ADMITTED" 0 "$ST"

# AC-3.3: A WRITER IS UNAFFECTED. An implementor merging its wave head into its task branch is
# exactly what the brief tells it to do before reporting; the widened set is the role arm's only.
run_hook "$(mk_payload "$R_RO_OK" 'git merge --no-ff wave/20-fixit-187' aimplementor-0123456789abcdef omit Bash w19-T5)"
expect_status "17l: AC-3.3 — a bionic:implementor's 'git merge --no-ff <wave head>' is ADMITTED" 0 "$ST"
expect_absent "17l: …and the role arm says nothing" "read-only role" "$ERR"
run_hook "$(mk_payload "$R_RO_OK" "git -C $R_RO_OK merge --no-ff wave/20-fixit-187" aimplementor-0123456789abcdef omit Bash w19-T5)"
expect_status "17l: AC-3.3 — …and spelled 'git -C <tree> merge --no-ff', ADMITTED" 0 "$ST"


# ---------------------------------------------------------------------------
section "18 — a commit into another repository is outside the evidence gate, and only it (wave-19 REQ-9, D10)"
#
# THE FAULT (A-T11.1). From an engaged session, `git -C <scratch repo> commit` was judged by
# the evidence gate against THIS repository's plan and refused for its evidence. The gate now
# asks which repository the commit lands in before it reads a plan; another repository — a
# scratch one, or one NESTED under the root — is admitted with one line. The walls folded
# beside the gate never read a plan and are not exempted with it: the read-only-role arm (T5)
# still refuses a test-runner's commit wherever it lands.
#
# R_COMMIT carries `block_plan` (current: 5, a placeholder Step-5 line), so every commit the
# gate still judges there is refused — the control that makes each allow a boundary verdict.
R_SCR="$SANDBOX/scratchpad/scratch-repo"
mkdir -p "$R_SCR"; git -C "$R_SCR" init -q 2>/dev/null
R_NEST="$R_COMMIT/.bionic/docs/record/x/bed"
mkdir -p "$R_NEST"; git -C "$R_NEST" init -q 2>/dev/null
jur_line() {  # <the commit's repository> [engaged root, default R_COMMIT]
  printf 'evidence-gate: %s is outside the engaged repository (%s); the evidence gate has no plan here' "$1" "${2:-$R_COMMIT}"
}

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m "x"')"
expect_status "18a: control — a commit inside the engaged root under block_plan is refused as before" 2 "$ST"
expect_contains "18a: …by the evidence gate" "commit refused" "$ERR"

run_hook "$(mk_payload "$R_COMMIT" "git -C $R_SCR commit -q --allow-empty -m x")"
expect_status "18b: AC-9.1 — 'git -C <scratch repo> commit' from the engaged root is ADMITTED" 0 "$ST"
expect_eq "18b: …with exactly one line naming both repositories" "$(jur_line "$R_SCR")" "$ERR"
expect_empty "18b: …and nothing on stdout" "$OUT"

run_hook "$(mk_payload "$R_COMMIT" "git -C $R_NEST commit -q --allow-empty -m x")"
expect_status "18c: AC-9.3 — a repository nested at <root>/.bionic/docs/record/x/bed is ADMITTED" 0 "$ST"
expect_eq "18c: …with the same one line" "$(jur_line "$R_NEST")" "$ERR"

# THE EXEMPTION IS THE GATE'S ALONE. A bionic:test-runner row committing into the scratch
# repo is outside the gate's jurisdiction and still inside the role arm's: refused, by ARM C.
R_JUR_RO="$(mk_repo jurisdiction-ro)"; block_plan "$R_JUR_RO"
roster_header > "$R_JUR_RO/.bionic/tmp/roster-$SID.state"
ro_rows "$R_JUR_RO" w19-jur-runner ajurrunner-0123456789abcdef bionic:test-runner
run_hook "$(mk_payload "$R_JUR_RO" "git -C $R_SCR commit -q --allow-empty -m x" ajurrunner-0123456789abcdef omit Bash w19-jur-runner)"
expect_status "18d: a bionic:test-runner's commit into the scratch repo is still REFUSED (the role arm is not exempt)" 2 "$ST"
expect_contains "18d: …by the role arm" "a read-only role never commits" "$ERR"
expect_contains "18d: …while the gate itself only names the boundary" "$(jur_line "$R_SCR" "$R_JUR_RO")" "$ERR"
expect_eq "18d: …so exactly one refusal is rendered" "1" "$(printf '%s\n' "$ERR" | grep -c 'refused')"

# A LINKED WORKTREE of the engaged repository shares its common dir and is inside: judged.
git -C "$R_COMMIT" worktree add -q "$R_COMMIT/.worktrees/19-T6" -b wt/19-T6 2>/dev/null
run_hook "$(mk_payload "$R_COMMIT" "git -C $R_COMMIT/.worktrees/19-T6 commit -m x")"
expect_status "18e: a commit from a linked worktree of the engaged repository is still judged — refused" 2 "$ST"
expect_absent "18e: …and never called outside" "outside the engaged repository" "$ERR"

# wave-25 T12: the words in front of git are names, read as the machine resolves them. On a
# case-blind filesystem `ENV`, `SUDO` and `BASH` run env, sudo and bash, so each of these is a
# commit the gate judges exactly as its lower-case form, and R_COMMIT's block_plan refuses it.
# Before T12 the reader left `ENV` as argv[0], saw no git, and the gate admitted the commit.
for _bw12 in "env -C $R_SCR git commit -q --allow-empty -m x|ENV -C $R_SCR git commit -q --allow-empty -m x" \
             "env --chdir=$R_SCR git commit -m x|Env --chdir=$R_SCR git commit -m x" \
             "sudo git commit -m x|SUDO git commit -m x" \
             "bash -c 'git commit -m x'|BASH -c 'git commit -m x'"; do
  run_hook "$(mk_payload "$R_COMMIT" "${_bw12%%|*}")"
  expect_status "18f: control — [${_bw12%%|*}] is judged and refused" 2 "$ST"
  run_hook "$(mk_payload "$R_COMMIT" "${_bw12#*|}")"
  expect_status "18f: [${_bw12#*|}] is judged and refused exactly as its lower-case form" 2 "$ST"
  expect_contains "18f: …by the evidence gate" "commit refused" "$ERR"
done



# ---------------------------------------------------------------------------
section "REQ7 — a redirected run is the budgeted run, and every refusal's remedy is admitted (wave-20 T4, D7)"
#
# AC-7.1. The budget arm compared a run claim, redirections and all, to the author's
# declared run — so the spelling every role file prescribes for saving evidence,
# `<command> 2>&1 | tee <log>`, was refused for exactly the run the brief declared
# (triage-B B1, driven there). Eight spellings, three kinds of budget: a shell suite on
# `suites_allowed=`, a non-shell runner on `re_executes=`, and a shell suite that is on the
# budget only through `Re-executes:`. Every cell is admitted where the bare command is.
#
# AC-7.3. Three refusals suggested a command the same wall then refused: the full-tree
# refusal named no single-suite spelling (B1a), the backgrounded-suite remedy echoed the
# `&` that tripped it (B2), and the budget one-liner cut a declared run mid-token (B3).
# Each remedy row below takes the suggestion OFF the refusal's own text and drives it back
# through the wall.
#
# fails-when: a spelling is refused where the bare command is admitted; a remedy the wall
# printed is refused when run; the one-liner carries half a run.

T4_LOG="$SANDBOX/t4-ev.log"
T4_BT='`'
# WHAT A REMEDY ROW RUNS WHEN THE REFUSAL SUGGESTED NOTHING: an off-budget suite, which every
# row below refuses — so a missing suggestion fails the "admitted" row instead of passing it
# on a command no wall has an opinion about.
T4_NONE='bash tests/no-suggestion-was-printed.test.sh'
t4_row() {  # <repo> <name> <key=value>... — an armed roster with one budgeted row for ACTOR
  local repo="$1" name="$2"; shift 2
  roster_header > "$repo/.bionic/tmp/roster-$SID.state"
  roster_row_fixture "session=$SID" "name=$name" "agent_id=$ACTOR" "$@" \
    >> "$repo/.bionic/tmp/roster-$SID.state"
}
t4_drive() {  # <repo> <command> [run_in_background] — as a dispatched test-runner, timeout set
  run_hook "$(mk_payload "$1" "$2" "$ACTOR" "${3:-omit}" Bash test-runner 600000)"
}
t4_admitted() {  # <label> <repo> <command>
  t4_drive "$2" "$3"
  expect_status "$1" 0 "$ST"
  expect_absent "$1 …with no refusal on stderr" "refused" "$ERR"
}
t4_refused() {  # <label> <repo> <command>
  t4_drive "$2" "$3"
  expect_status "$1" 2 "$ST"
}
t4_eight() {  # <kind label> <repo> <bare command>
  local k="$1" r="$2" j="$3"
  t4_admitted "REQ7 $k: the bare command is admitted (control)" "$r" "$j"
  t4_admitted "REQ7 $k: > p"            "$r" "$j > $T4_LOG"
  t4_admitted "REQ7 $k: >> p"           "$r" "$j >> $T4_LOG"
  t4_admitted "REQ7 $k: 2>&1"           "$r" "$j 2>&1"
  t4_admitted "REQ7 $k: &> p"           "$r" "$j &> $T4_LOG"
  t4_admitted "REQ7 $k: | tee p"        "$r" "$j | tee $T4_LOG"
  t4_admitted "REQ7 $k: 2>&1 | tee p"   "$r" "$j 2>&1 | tee $T4_LOG"
  t4_admitted "REQ7 $k: |& tee p"       "$r" "$j |& tee $T4_LOG"
  t4_admitted "REQ7 $k: || true"        "$r" "$j || true"
}

# --- AC-7.1, the three budget kinds ---
R7S="$(mk_repo t4shell)"
t4_row "$R7S" t4shell suites_allowed=alpha.test.sh suites_source=declared files=
t4_eight "shell suite" "$R7S" 'bash tests/alpha.test.sh'

R7N="$(mk_repo t4runner)"
t4_row "$R7N" t4runner suites_allowed=alpha.test.sh suites_source=declared files= \
  "re_executes=${T4_BT}npx jest --testPathPatterns 'x'${T4_BT}"
t4_eight "non-shell runner" "$R7N" "npx jest --testPathPatterns 'x'"

R7R="$(mk_repo t4reonly)"
t4_row "$R7R" t4reonly suites_allowed=none suites_source=declared files= \
  "re_executes=${T4_BT}bash tests/gamma.test.sh${T4_BT}"
t4_eight "Re-executes-only budget" "$R7R" 'bash tests/gamma.test.sh'

# THE NEGATIVE CONTROLS: normalising cannot widen the budget. A run that is not the declared
# one is still refused however it is redirected, and so is a suite neither channel names.
t4_refused "REQ7 control: the whole-tree jest, redirected, is still REFUSED against a narrower declaration" \
  "$R7N" "npx jest 2>&1 | tee $T4_LOG"
t4_refused "REQ7 control: an undeclared shell suite, redirected, is still REFUSED on a Re-executes-only row" \
  "$R7R" "bash tests/delta.test.sh > $T4_LOG 2>&1"

# THE DECLARED SIDE IS NORMALISED AT ITS ONE DECODE. A row written before the lift refused
# redirections (or by hand) carries one inside its marks; the rule is written once and held
# on both sides of the compare, so the bare command and its redirected spelling both match.
R7L="$(mk_repo t4legacy)"
t4_row "$R7L" t4legacy suites_allowed=alpha.test.sh suites_source=declared files= \
  "re_executes=${T4_BT}npx jest --testPathPatterns 'x' 2>&1${T4_BT}"
t4_admitted "REQ7 decode: a declared run stored with a redirect admits the bare command" \
  "$R7L" "npx jest --testPathPatterns 'x'"
t4_admitted "REQ7 decode: …and its tee spelling" \
  "$R7L" "npx jest --testPathPatterns 'x' 2>&1 | tee $T4_LOG"

# --- AC-7.3 (1): the full-tree refusal names the single-suite spelling, and it runs ---
t4_refused "REQ7 remedy 1: bash tests/run.sh --one is refused as the full tree" \
  "$R7S" 'bash tests/run.sh --one alpha.test.sh'
T4_R1=$(printf '%s\n' "$ERR" | grep -o 'bash tests/[A-Za-z0-9._-]*\.test\.sh' | head -1)
expect_eq "REQ7 remedy 1: …and the refusal names the per-suite spelling from the budget" \
  "bash tests/alpha.test.sh" "$T4_R1"
expect_contains "REQ7 remedy 1: …and says --one is the runner's internal worker mode" "--one" "$ERR"
t4_admitted "REQ7 remedy 1: …and that spelling, run, is admitted" "$R7S" "${T4_R1:-$T4_NONE}"

# --- AC-7.3 (2): the backgrounded-suite remedy carries no &, and it runs ---
t4_remedy_bg() {  # <label> <repo> <backgrounded command>
  local label="$1" r="$2" cmd="$3" fix
  t4_refused "$label: the backgrounded suite is refused" "$r" "$cmd"
  expect_contains "$label: …by the backgrounded arm" "a backgrounded suite" "$ERR"
  fix=$(printf '%s\n' "$ERR" | grep '| tee <evidence log>' | head -1 | sed 's/^[[:space:]]*//')
  expect_nonempty "$label: …suggesting a foreground command" "$fix"
  fix="${fix//<evidence log>/$T4_LOG}"
  t4_admitted "$label: …and the suggestion, run as printed, is admitted" "$r" "${fix:-$T4_NONE}"
}
t4_remedy_bg "REQ7 remedy 2a shell suite &" "$R7S" 'bash tests/alpha.test.sh &'
t4_remedy_bg "REQ7 remedy 2b runner &" "$R7N" "npx jest --testPathPatterns 'x' &"
t4_remedy_bg "REQ7 remedy 2c nohup, redirected, &" "$R7S" "nohup bash tests/alpha.test.sh > $T4_LOG 2>&1 &"
# THE TOOL-FLAG CASE: the text is already foreground, so the remedy is the flag.
t4_drive "$R7S" 'bash tests/alpha.test.sh' true
expect_status "REQ7 remedy 2d: run_in_background true on a suite is refused" 2 "$ST"
expect_contains "REQ7 remedy 2d: …and the remedy names the flag to clear" "run_in_background: false" "$ERR"

# --- AC-7.3 (3): the budget one-liner shows whole runs or a count, never half a run ---
R7W="$(mk_repo t4wire)"
t4_row "$R7W" t4wire suites_allowed=none suites_source=declared files= \
  "re_executes=${T4_BT}npm test${T4_BT} ${T4_BT}pytest tests/unit/test_widget_rendering_pipeline_end_to_end.py${T4_BT} ${T4_BT}go test ./internal/rendering/pipeline/...${T4_BT}"
t4_refused "REQ7 remedy 3: an undeclared run is refused" "$R7W" 'npx jest'
T4_LINE=$(printf '%s\n' "$ERR" | grep -m1 '^bionic: ')
expect_eq "REQ7 remedy 3: …on a verdict line whose marks are balanced" "0" \
  "$(( $(printf '%s' "$T4_LINE" | tr -cd '`' | wc -c) % 2 ))"
expect_contains "REQ7 remedy 3: …showing the first declared run whole, and the rest counted as runs" \
  "${T4_BT}npm test${T4_BT} +2 more" "$T4_LINE"
T4_R3=$(printf '%s' "$T4_LINE" | awk -F'`' 'NF >= 3 { print $2 }')
t4_admitted "REQ7 remedy 3: …and the run it shows, run, is admitted" "$R7W" "${T4_R3:-$T4_NONE}"
# NOTHING FITS: the count, never a cut. Three runs each wider than the line has room for.
R7X="$(mk_repo t4wirewide)"
T4_LONG="pytest tests/unit/test_a_very_long_module_name_that_cannot_fit_on_any_line.py -k"
t4_row "$R7X" t4wirewide suites_allowed=none suites_source=declared files= \
  "re_executes=${T4_BT}$T4_LONG one${T4_BT} ${T4_BT}$T4_LONG two${T4_BT} ${T4_BT}$T4_LONG three${T4_BT}"
t4_refused "REQ7 remedy 3b: an undeclared run against three over-wide runs is refused" "$R7X" 'npx jest'
T4_LINE=$(printf '%s\n' "$ERR" | grep -m1 '^bionic: ')
expect_contains "REQ7 remedy 3b: …and the line counts them as declared runs, printed below (wave-22 T4)" "3 declared runs (printed below)" "$T4_LINE"
expect_absent "REQ7 remedy 3b: …never a cut run" "pytest" "$T4_LINE"


# ---------------------------------------------------------------------------
section "19 — a subagent may not change a contract or the plan (wave-20 T9, REQ-4, AC-4.2)"
#
# `session-poker.sh amend` widens a live row's Files/Suites/Re-executes, `extend` re-opens a
# MET row, and `task-add` writes the bound plan. All three are the orchestrator's: an agent
# that could run them would grant itself a wider budget, or schedule its own work. The
# script cannot tell who called it (in-process teammates share the session's environment,
# research D2 REQ-4), so the refusal is the Bash wall's, keyed on the payload's top-level
# `agent_id` — the same partition ARM C and the budget arm take. The match is on the
# segment's argv after `cd …&&` and `env` prefixes, never on the text: a quoted mention is
# an argument to something else and is admitted.
#
# The roster exists (the session is armed) and carries the writer's own row, so the
# refusal is not an artefact of an unarmed session.
R_AM="$(mk_repo amendwall)"
AM_ID="aw20-T9sub-0123456789abcdef"
roster_header > "$R_AM/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" status=identified name=w20-sub "agent_id=$AM_ID" \
  subagent_type=bionic:senior-implementor >> "$R_AM/.bionic/tmp/roster-$SID.state"
AM_POKER="/opt/plugin/hooks/session-poker.sh"

am_refused() {  # <label> <command>
  run_hook "$(mk_payload "$R_AM" "$2" "$AM_ID" omit Bash w20-sub)"
  expect_status "$1 — refused from a subagent" 2 "$ST"
  expect_contains "$1 — …naming the rule" "a subagent may not change a contract or the plan" "$ERR"
}
am_admitted() {  # <label> <command> [agent_id]
  run_hook "$(mk_payload "$R_AM" "$2" "${3-$AM_ID}" omit Bash w20-sub)"
  expect_status "$1 — admitted" 0 "$ST"
  expect_absent "$1 — …with no contract refusal" "a subagent may not change a contract" "$ERR"
}

am_refused "19a: bash session-poker.sh amend" \
  "bash $AM_POKER amend w20-sub --files+ hooks/x.sh --reason 'need x'"
am_refused "19b: bash session-poker.sh extend" "bash $AM_POKER extend w20-sub 'more time'"
am_refused "19c: bash session-poker.sh task-add" \
  "bash $AM_POKER task-add T99 4 build 'x' bionic:implementor — 30 REQ-1 hooks/x.sh"
am_refused "19d: behind cd … &&" "cd $R_AM && bash $AM_POKER amend w20-sub --suites+ a.test.sh --reason r"
am_refused "19e: behind an env prefix with options and an assignment" \
  "env -u FOO BAR=1 bash $AM_POKER extend w20-sub r"
am_refused "19f: the script run directly, by relative path" "./hooks/session-poker.sh amend w20-sub --reason r --files+ a/b.sh"
# wave-25 T12: BASH runs bash on a case-blind filesystem, so the runner word folds here too.
am_refused "19f2: BASH session-poker.sh amend" "BASH $AM_POKER amend w20-sub --reason r --files+ a/b.sh"
am_refused "19f3: SUDO Sh session-poker.sh task-set" "SUDO Sh $AM_POKER task-set T2 status=landed"
am_refused "19g: second segment of a chain" "echo hi; bash hooks/session-poker.sh task-add a b c d e f g h i"
am_refused "19h: inside bash -c" "bash -c 'bash $AM_POKER amend w20-sub --reason r --files+ a/b.sh'"
# §ARM-A (hold) — wave-24 T7, REQ-4 AC-4.6, D1: a hold is the orchestrator's standing answer to a
# stand-down, so an agent that could run it would keep itself up.
am_refused "19o: bash session-poker.sh hold" "bash $AM_POKER hold w20-sub 'idle on purpose'"
# §ARM-A (plan-row verbs) — wave-24 T15, REQ-9 AC-9.4, D14: the five verbs write the bound plan,
# and an agent that could run them could move `current:` or mark its own row landed.
am_refused "19p: bash session-poker.sh task-set" "bash $AM_POKER task-set T2 status=landed"
am_refused "19q: bash session-poker.sh step-line" "bash $AM_POKER step-line T2 'landed at abc1234'"
am_refused "19r: bash session-poker.sh current" "bash $AM_POKER current 5"
am_refused "19s: bash session-poker.sh ledger-add" "bash $AM_POKER ledger-add T2 agent=w20-sub"
am_refused "19t: bash session-poker.sh ledger-set" "bash $AM_POKER ledger-set T2 landed=yes"
# §ARM-A (proof-add) — wave-26 T5, REQ-3 D5/D6: a proof line decides whether the full run is
# admitted, so an agent that could write one could prove its own head.
am_refused "19u: bash session-poker.sh proof-add" \
  "bash $AM_POKER proof-add floor record/wave-26-never-idle/floor.txt"
# §ARM-A (approve) — wave-26 T5 after T13: an approval line is what releases a gate act, so an
# agent that could write one would approve its own step.
am_refused "19v: bash session-poker.sh approve" "bash $AM_POKER approve release 'approved'"

# THE PAIRED POSITIVES. The same verbs from the main thread (no agent_id) are the
# orchestrator's and pass this arm; a subagent's own read-only poker verbs pass; and a quoted
# mention is an argument to echo, not a call.
am_admitted "19i: amend from the main thread" "bash $AM_POKER amend w20-sub --reason r --files+ a/b.sh" ""
am_admitted "19j: task-add from the main thread" "bash $AM_POKER task-add a b c d e f g h i" ""
am_admitted "19j2: hold from the main thread" "bash $AM_POKER hold w20-sub 'idle on purpose'" ""
am_admitted "19j3: current from the main thread" "bash $AM_POKER current 5" ""
am_admitted "19j4: task-set from the main thread" "bash $AM_POKER task-set T2 status=landed" ""
am_admitted "19j5: proof-add from the main thread" \
  "bash $AM_POKER proof-add floor record/wave-26-never-idle/floor.txt" ""
am_admitted "19j6: approve from the main thread" "bash $AM_POKER approve release 'approved'" ""
am_admitted "19k: a subagent's tick" "bash $AM_POKER tick"
am_admitted "19l: a subagent's interval" "bash $AM_POKER interval"
am_admitted "19m: a quoted mention" "echo 'bash $AM_POKER amend w20-sub'"
am_admitted "19n: a different script's amend verb" "bash tools/other.sh amend w20-sub"

# ---------------------------------------------------------------------------
section "20 — an UNROSTERED nested delegate is bound by the verb wall through its own agent_type (wave-20 T7b; review R15)"
#
# THE COMPOSITION HOLE (review R15, security high). Δ12 made a delegate read-only by "no
# Write/Edit tools PLUS REQ-3's commit refusal", and AC-9.2 made every nested delegate
# UNROSTERED by design — the orchestrator's roster is the depth-one ledger. ARM C read the role
# only from a roster row, so the one population Δ12 created was admitted for every
# commit-creating verb (walk §3, "no row" column).
#
# THE PAYLOAD SHAPE IS THE LIVE ONE (T12, live-rows-802ee6d.md §AC-9.2/9.4): a nested
# delegate's own Bash payload carries its `agent_id` AND its own `agent_type`. When no roster
# row carries that `agent_id`, the arm reads the role from `agent_type`; a rostered agent keeps
# the row reading (§17: a teammate's `agent_type` is its dispatch NAME), and a payload with no
# `agent_id` is the orchestrator and never reaches the arm.
R_NEST="$(mk_repo nested-unrostered)"
roster_header > "$R_NEST/.bionic/tmp/roster-$SID.state"
# the orchestrator's own writer, so the roster is a live one and the join has rows to miss
ro_rows "$R_NEST" w20-T7 awriter-0123456789abcdef bionic:senior-implementor
NEST_ID="a8b824d95c81dd996"

for _nt in bionic:researcher Explore bionic:test-runner; do
  run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' "$NEST_ID" omit Bash "$_nt")"
  expect_status "20a: an unrostered nested $_nt's 'git commit' is REFUSED" 2 "$ST"
  expect_contains "20a: …naming the role $_nt" "$_nt: a read-only role never commits" "$ERR"
  run_hook "$(mk_payload "$R_NEST" 'git merge wave/20-fixit-187' "$NEST_ID" omit Bash "$_nt")"
  expect_status "20a: an unrostered nested $_nt's 'git merge' is REFUSED" 2 "$ST"
  expect_contains "20a: …naming the role $_nt (merge)" "$_nt: a read-only role never commits" "$ERR"
  run_hook "$(mk_payload "$R_NEST" "env -C $R_NEST git commit -m x" "$NEST_ID" omit Bash "$_nt")"
  expect_status "20a: an unrostered nested $_nt's 'env -C <r> git commit' is REFUSED" 2 "$ST"
  expect_contains "20a: …naming the role $_nt (env -C)" "$_nt: a read-only role never commits" "$ERR"
done
# every verb of the eight, once, from the harness's no-write type the live bed drove
for _v in revert cherry-pick am rebase commit-tree update-ref; do
  run_hook "$(mk_payload "$R_NEST" "git $_v x" "$NEST_ID" omit Bash Explore)"
  expect_status "20b: an unrostered nested Explore's 'git $_v' is REFUSED" 2 "$ST"
done
# the detail says where the role came from: there is no roster row to name
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' "$NEST_ID" omit Bash Explore)"
expect_contains "20c: the refusal's detail names the agent type, not a roster row" \
  "no roster row names you" "$ERR"
expect_eq "20c: …on ONE refusal line" "1" "$(printf '%s\n' "$ERR" | grep -c 'a read-only role never commits')"

# NOT A COMMIT: the read-only delegate's reading of history is its work.
run_hook "$(mk_payload "$R_NEST" 'git log -1 && git status' "$NEST_ID" omit Bash Explore)"
expect_status "20d: an unrostered nested Explore's 'git log' / 'git status' is ADMITTED" 0 "$ST"

# THE CONTROLS. Each is refused by nothing else here, so an arm that over-reaches turns one to 2.
for _nt in general-purpose bionic:implementor fork researcher; do
  run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' "$NEST_ID" omit Bash "$_nt")"
  expect_status "20e: an unrostered '$_nt'-typed payload's commit is ADMITTED (not a read-only type)" 0 "$ST"
  expect_absent "20e: …and the role arm says nothing ($_nt)" "read-only role" "$ERR"
done
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"')"
expect_status "20f: the orchestrator's own commit (no agent_id, no agent_type) is ADMITTED" 0 "$ST"
expect_absent "20f: …silently on this arm" "read-only role" "$ERR"
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' '' omit Bash bionic:test-runner)"
expect_status "20g: a 'claude --agent' main session (agent_type, no agent_id) commits — ADMITTED, it is the orchestrator" 0 "$ST"
expect_absent "20g: …silently on this arm" "read-only role" "$ERR"

# A ROSTERED AGENT KEEPS THE ROW READING: the row wins over the payload's agent_type in both
# directions, so a teammate named like a read-only type is not refused and a read-only row is
# not escaped by its name.
ro_rows "$R_NEST" Explore arowimpl-0123456789abcdef bionic:implementor
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' arowimpl-0123456789abcdef omit Bash Explore)"
expect_status "20h: a ROSTERED implementor whose agent_type reads 'Explore' is ADMITTED (the row wins)" 0 "$ST"
ro_rows "$R_NEST" w20-runner arowrun-0123456789abcdef bionic:test-runner
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' arowrun-0123456789abcdef omit Bash general-purpose)"
expect_status "20h: a ROSTERED test-runner whose agent_type reads 'general-purpose' is REFUSED (the row wins)" 2 "$ST"
expect_contains "20h: …naming the row's role" "bionic:test-runner: a read-only role never commits" "$ERR"
ro_rows "$R_NEST" w20-norole arownorole-0123456789abcdef ""
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' arownorole-0123456789abcdef omit Bash Explore)"
expect_status "20h: a ROSTERED row with an empty role is ADMITTED whatever its agent_type (§17g's reading)" 0 "$ST"

# 20i: ONE PICK, ONE SITE (wave-22 T10; review 2). The arm asks `roster_row_for_id` — the budget
# arm's own pick — which takes a row's FIRST `agent_id=` as its id. A forged row that carries a
# read-only role and a SECOND `agent_id=<id>` segment is not this agent's row (the old inline
# awk matched the id in any segment and would have refused it); a row naming the id in any
# other segment (`teammate_id=`) is not either. The payload's own agent_type then decides.
R_FORGE="$(mk_repo forged-segment)"
roster_header > "$R_FORGE/.bionic/tmp/roster-$SID.state"
FORGE_ID="aforged-0123456789abcdef"
printf '%s|agent_id=%s\n' "$(roster_row_fixture "session=$SID" status=identified name=w20-other \
  "agent_id=aother-0123456789abcdef" subagent_type=bionic:test-runner)" "$FORGE_ID" >> "$R_FORGE/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" status=identified name=w20-tm "agent_id=atm-0123456789abcdef" "teammate_id=$FORGE_ID" \
  subagent_type=bionic:test-runner >> "$R_FORGE/.bionic/tmp/roster-$SID.state"
expect_eq "20i meta: the forged roster holds the id in a second agent_id= segment" "1" \
  "$(grep -c "|agent_id=aother-0123456789abcdef|.*|agent_id=$FORGE_ID\$" "$R_FORGE/.bionic/tmp/roster-$SID.state")"
run_hook "$(mk_payload "$R_FORGE" 'git commit -m "x"' "$FORGE_ID" omit Bash general-purpose)"
expect_status "20i: an id found only in a SECOND agent_id= segment (or a teammate_id=) is no roster row — ADMITTED on its own type" 0 "$ST"
expect_absent "20i: …the role arm says nothing" "read-only role" "$ERR"
run_hook "$(mk_payload "$R_FORGE" 'git commit -m "x"' "$FORGE_ID" omit Bash bionic:test-runner)"
expect_status "20i: …and with no row the payload's own read-only type still binds (the fallback)" 2 "$ST"
expect_contains "20i: …saying no roster row names it" "no roster row names you" "$ERR"

# ---------------------------------------------------------------------------
section "21 — AC-5.3: the shared screen still says maybe for every spelling the parser reads (wave-24 T4, REQ-5, D6)"
#
# fails-when: `g\<newline>it`, `'g'it`, `"gi"t` or `\g\i\t` reads "provably not" through the new
# screen, or the screen's cache answers one command with another command's strip.
#
# THE SCREEN CHANGED SHAPE, NOT MEANING (wave-24-fixit-1811 T4). `_wall_mentions_git` used to
# strip the command itself with four `${v//…/}` passes, and so did three other screens in this
# process; bash 3.2 pays matches × length for each, and a quote-dense command timed the hook
# out. Now a literal `git` answers at once, and only a miss runs `_wall_screen` — one awk pass,
# cached at file scope keyed on the text. The T24 spellings are exactly the ones the literal
# check misses, so each of them is the awk path, read two ways: the function itself, and
# protect-main's refusal through the one process.
WALLS_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh"
mg_answer() {  # <command text>... -> one 0/1 per argument, space-joined, all in ONE process
  bash -c '. "$1" >/dev/null 2>&1; shift; o=""
    for c in "$@"; do _wall_mentions_git "$c"; o="$o$? "; done; printf "%s" "${o% }"' _ "$WALLS_LIB" "$@"
}
BW21_NL="$(printf 'g\\\n''it push origin main')"
expect_eq "21a: each obfuscated spelling is still 'maybe' (0), and a git-free quoted command is 'provably not' (1)" \
  "0 0 0 0 1" "$(mg_answer "$BW21_NL" "'g'it push origin main" '"gi"t push origin main' '\g\i\t push origin main' "echo 'hi' \"there\"")"
# THE CACHE IS KEYED ON THE TEXT: one process, three different commands asked in turn — a hit,
# a miss, the hit again. A single-slot cache that forgot to compare its key would answer the
# second with the first's strip, or the third with the second's.
expect_eq "21b: …asked in one process in turn, the cache never answers one command with another's strip" \
  "0 1 0" "$(mg_answer "'g'it push" "echo 'x'" "'g'it push")"

# 21d (wave-25 T12): the tier-2 screen in ANY letter case, answered by the same strip pass. A
# capitalised tier-2 word is a maybe, through the awk pass (a text holding a quote or a
# backslash, a continuation joining the word included) and through the fast path (a text with
# neither, which keeps the text as its strip); a text with no tier-2 word at all is not. The
# strip itself is the one the screen always made: the flag never reaches it.
t2_answer() {  # <command text>... -> "<rc>:<strip>" per argument, `|`-joined, all in ONE process
  bash -c '. "$1" >/dev/null 2>&1; shift; o=""
    for c in "$@"; do _wall_screen "$c"; _wall_tier2_any_case; o="$o$?:$_WALL_STRIPPED|"; done
    printf "%s" "$o"' _ "$WALLS_LIB" "$@"
}
BW21_T2NL="$(printf 'G\\\nIT clone x')"
expect_eq "21d: each capitalised tier-2 word is 'maybe' (0) by either path, prose is not (1), and the strip is unchanged" \
  "0:GIT clone x|0:NPX create-thing x y|0:Docker run x|0:GIT clone x|1:echo x y|1:ls -la|0:uvx tool|" \
  "$(t2_answer 'GIT clone x' 'NPX create-thing "x y"' "'Docker' run x" "$BW21_T2NL" "echo 'x y'" 'ls -la' 'uvx tool')"

for _bw21 in "$BW21_NL" "'g'it push origin main" '"gi"t push origin main' '\g\i\t push origin main'; do
  run_hook "$(mk_payload "$R_QUIET" "$_bw21")"
  expect_status "21c: [$(printf '%q' "$_bw21")] is still a push to main through the one process" 2 "$ST"
  expect_contains "21c: …refused in protect-main's own words" "main is a protected branch here" "$ERR"
done

# ---------------------------------------------------------------------------
section "§MEM — an engaged session never writes the auto-memory store (REQ-3, D16; AC-3.2)"
#
# THE INCIDENT (wave-23 A-orch-30). An engaged orchestrator obeyed the harness's standing
# memory directive in ONE Bash call: `cd <store> && cat >> <topic>.md <<'EOF' … EOF` then
# `sed -i '' …` on MEMORY.md. The store's path appeared only in the `cd`. The wall is
# `wall_memory_store` in payload/scripts/lib/walls.sh; this hook is its collector, handing it
# the store root and the command's write targets (`cmd_write_targets`, cmd-class.sh).
#
# THE STORE ROOT IS `${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/projects/*/memory`.
# run_hook pins HOME inside the sandbox; the two variables are emptied on every row that does
# not set them, so the machine's own values cannot leak in.
R_MEM="$(mk_repo memwall)"
MEM_STORE="$FAKE_HOME/.claude/projects/-x/memory"
mkdir -p "$MEM_STORE"
MEM_NOENV=(BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR=)
MEM_REPLAY="$(printf 'cd %s && cat >> decision-reframe.md <<%sEOF%s\n- refined: goal, options, recommendation\nEOF\nsed -i %s%s %ss|^- \\[Decision reframe|- [Decision reframe|%s MEMORY.md' \
  "$MEM_STORE" "'" "'" "'" "'" "'" "'")"

mem_refused() {  # <label> <cwd> <command> [env…]
  local _l="$1" _d="$2" _c="$3"; shift 3
  run_hook "$(mk_payload "$_d" "$_c")" "$@"
  expect_status "§MEM $_l: refused" 2 "$ST"
  expect_contains "§MEM $_l: …naming the run's own record" "record/<wave>/assumptions.md" "$ERR"
  expect_contains "§MEM $_l: …and a rule proposal" "rule proposal" "$ERR"
}

mem_refused "replay of A-orch-30 (cd + heredoc append + sed -i)" "$R_MEM" "$MEM_REPLAY" "${MEM_NOENV[@]}"
mem_refused "redirect under ~" "$R_MEM" 'echo x > ~/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "append under \$HOME" "$R_MEM" 'echo x >> $HOME/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "redirect under \"\${HOME}\"" "$R_MEM" 'printf x > "${HOME}/.claude/projects/-x/memory/a.md"' "${MEM_NOENV[@]}"
mem_refused "tee" "$R_MEM" 'printf x | tee ~/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "sed -i" "$R_MEM" "sed -i '' 's/a/b/' ~/.claude/projects/-x/memory/MEMORY.md" "${MEM_NOENV[@]}"
mem_refused "cp destination" "$R_MEM" 'cp /tmp/x ~/.claude/projects/-x/memory/' "${MEM_NOENV[@]}"
mem_refused "mv destination" "$R_MEM" 'mv /tmp/x ~/.claude/projects/-x/memory/b.md' "${MEM_NOENV[@]}"
mem_refused "touch" "$R_MEM" 'touch ~/.claude/projects/-x/memory/c.md' "${MEM_NOENV[@]}"
mem_refused "mkdir of the store itself" "$R_MEM" 'mkdir -p ~/.claude/projects/-x/memory' "${MEM_NOENV[@]}"
mem_refused "ln" "$R_MEM" 'ln -s /tmp/x ~/.claude/projects/-x/memory/d.md' "${MEM_NOENV[@]}"
# wave-25 T12: on a case-blind filesystem `TEE` runs tee and `CP` runs cp, so each writer is
# the same writer in any letter case, behind any prefix in any letter case.
mem_refused "TEE" "$R_MEM" 'printf x | TEE ~/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "CP destination" "$R_MEM" 'CP /tmp/x ~/.claude/projects/-x/memory/' "${MEM_NOENV[@]}"
mem_refused "SUDO Mv destination" "$R_MEM" 'SUDO Mv /tmp/x ~/.claude/projects/-x/memory/b.md' "${MEM_NOENV[@]}"
mem_refused "BASH -c touch" "$R_MEM" "BASH -c 'touch ~/.claude/projects/-x/memory/c.md'" "${MEM_NOENV[@]}"
mem_refused "cd into the store, SED -i" "$R_MEM" \
  "cd ~/.claude/projects/-x/memory && SED -i '' 's/a/b/' MEMORY.md" "${MEM_NOENV[@]}"
# …and `CD` is NOT cd: /usr/bin/CD runs `builtin cd` in a child and moves nothing, so the tee
# below still writes into the store. A reader that folded CD would place it under /tmp.
mem_refused "CD moves nothing, so a relative write stays in the store" "$R_MEM" \
  "cd ~/.claude/projects/-x/memory && CD /tmp && tee a.md" "${MEM_NOENV[@]}"
mem_refused "cd into the store, relative sed -i" "$R_MEM" \
  "cd ~/.claude/projects/-x && cd memory && sed -i '' 's/a/b/' MEMORY.md" "${MEM_NOENV[@]}"
mem_refused "a dot-dot spelling" "$R_MEM" 'touch ~/.claude/projects/-x/notes/../memory/e.md' "${MEM_NOENV[@]}"
# THE ROOT MOVES WITH ITS VARIABLES, each spelled out in the command and as a literal path.
MEM_BCH="$SANDBOX/bch"; MEM_CCD="$SANDBOX/ccd"
mem_refused "BIONIC_CLAUDE_HOME, literal path" "$R_MEM" "touch $MEM_BCH/projects/-y/memory/a.md" \
  BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
mem_refused "BIONIC_CLAUDE_HOME, spelled" "$R_MEM" 'echo x > "$BIONIC_CLAUDE_HOME/projects/-y/memory/a.md"' \
  BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
mem_refused "CLAUDE_CONFIG_DIR, literal path" "$R_MEM" "touch $MEM_CCD/projects/-y/memory/a.md" \
  BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR="$MEM_CCD"
mem_refused "CLAUDE_CONFIG_DIR, spelled" "$R_MEM" 'echo x >> $CLAUDE_CONFIG_DIR/projects/-y/memory/a.md' \
  BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR="$MEM_CCD"
mem_refused "CLAUDE_CONFIG_DIR given as ~/…" "$R_MEM" 'touch ~/ccd/projects/-y/memory/a.md' \
  BIONIC_CLAUDE_HOME= 'CLAUDE_CONFIG_DIR=~/ccd'
# THE STORE IS THE ROOT'S, NOT EVERY `memory` DIRECTORY: with BIONIC_CLAUDE_HOME set, the
# default root is not the store — the precedence the collector resolves.
run_hook "$(mk_payload "$R_MEM" "touch $MEM_BCH/projects/-y/memory/a.md")" BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
expect_status "§MEM precedence: BIONIC_CLAUDE_HOME's store is refused…" 2 "$ST"
run_hook "$(mk_payload "$R_MEM" 'touch ~/.claude/projects/-x/memory/a.md')" BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
expect_status "§MEM precedence: …and ~/.claude's is not the store while BIONIC_CLAUDE_HOME names another" 0 "$ST"
# A RELATIVE TARGET WITH NO cd RESOLVES AGAINST THE PAYLOAD'S cwd. The cwd is the engaged
# repo, because engagement is the cwd's project's: a payload whose cwd IS the store resolves
# no engaged root, and every wall in this process stands down for it (A-T12.6).
mem_refused "relative target joined to the payload cwd" "$R_MEM" \
  'echo x > ../home/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"

# ---------------------------------------------------------------------------
section "§MEM-ok — reading the store, and writing elsewhere, stay open (AC-3.3)"
#
# THE SAME ENGAGED REPO, THE SAME EXTRACTOR (the hook's exit status) as §MEM above, so each
# admission here is read beside a refusal of the same shape. The fourth row is the wave's own
# AC-5.4 readback: it names the store AND redirects, to a path outside it.
for _mo in \
  'cat ~/.claude/projects/-x/memory/MEMORY.md' \
  'ls -la ~/.claude/projects/-x/memory' \
  'find ~/.claude/projects/-x/memory -newer .bionic/tmp/m -type f' \
  '{ find ~/.claude/projects/-x/memory -newer .bionic/tmp/m -type f; } > .bionic/docs/record/x.txt' \
  'rm -f ~/.claude/projects/-x/memory/old.md' \
  'tar -cf /tmp/mem.tar ~/.claude/projects/-x/memory' \
  'cp ~/.claude/projects/-x/memory/MEMORY.md .bionic/docs/record/memory-copy.md' \
  "$(printf 'cat > .bionic/docs/record/n.md <<%sEOF%s\necho x > ~/.claude/projects/-x/memory/a.md\nEOF' "'" "'")" \
  'touch ~/.claude/projects/-x/notes.md'; do
  run_hook "$(mk_payload "$R_MEM" "$_mo")" "${MEM_NOENV[@]}"
  expect_status "§MEM-ok [$(printf '%.60s' "$_mo")]: admitted" 0 "$ST"
  expect_absent "§MEM-ok …and no memory refusal on the wire" "assumptions.md" "$ERR"
done

# ---------------------------------------------------------------------------
section "§MEM-unengaged — a session that never invoked bionic writes its store freely (AC-3.4)"
#
# R_PLAIN carries no engagement marker. The same writes §MEM refuses, with the same env.
for _mu in \
  "$(printf '%s' "$MEM_REPLAY")" \
  'echo x > ~/.claude/projects/-x/memory/a.md' \
  'printf x | tee ~/.claude/projects/-x/memory/a.md' \
  "sed -i '' 's/a/b/' ~/.claude/projects/-x/memory/MEMORY.md" \
  'touch ~/.claude/projects/-x/memory/c.md'; do
  run_hook "$(mk_payload "$R_PLAIN" "$_mu")" "${MEM_NOENV[@]}"
  expect_status "§MEM-unengaged [$(printf '%.60s' "$_mu")]: admitted" 0 "$ST"
  expect_empty "§MEM-unengaged …silently" "$OUT$ERR"
done

# ---------------------------------------------------------------------------
section "§CDT — the later-cd scan reads every segment before the first git, in one split (T28)"
#
# `_eg_cd_targets` lists the `cd` targets after the command's first separator and before its
# first `git`, for the evidence gate's ambiguity check. T28 replaced its one-pass-per-segment
# loop with a single `read` split (the 64 KB timing is tests/hook-timeout.test.sh b4). These
# rows pin what the split must still answer: the four separators, the empty segments a
# doubled or trailing separator leaves, a `git` inside a segment ending the scan there, and
# nothing read after it. Each row answers the same on the loop it replaced.
# The function is defined past walls.sh's early `return`, so it is extracted the way 15g2
# extracts `_budget_wire_list`: awk between its own `()` line and its closing `}`, then eval.
cdt_of() {  # <command> -> the targets, `|`-terminated
  # git-argv.sh is sourced first, as the evidence gate always has it (wave-25 T12): the scan
  # asks it whether a segment's word is git in another letter case.
  bash -c '. "${1%/*}/git-argv.sh"; eval "$(awk "/^_eg_cd_targets\(\)/,/^}/" "$1")"; _eg_cd_targets "$2"
    printf "%s" "$_EG_CDS" | tr "\n" "|"' _ "$WALLS_LIB" "$1"
}
expect_contains "§CDT the extractor finds the function" "_eg_cd_targets()" \
  "$(awk '/^_eg_cd_targets\(\)/,/^}/' "$WALLS_LIB")"
expect_eq "§CDT the leading cd is not in the list; the second is" "/b|" "$(cdt_of 'cd /a && cd /b && git commit')"
expect_eq "§CDT every separator splits, and a bare cd is home" "/b|/c d|/e|~|" \
  "$(cdt_of "$(printf 'cd /a; cd /b|cd "/c d"&cd %s/e%s\ncd\ngit commit' "'" "'")")"
expect_eq "§CDT doubled and trailing separators name nothing" "/b|" "$(cdt_of 'cd /a;; ;cd /b ;')"
expect_eq "§CDT blank lines name nothing" "/b|" "$(cdt_of "$(printf 'cd /a\n\n\ncd /b\n\ngit commit')")"
expect_eq "§CDT a subshell opener comes off the front" "/b|" "$(cdt_of 'cd /a && (cd /b && git commit)')"
expect_eq "§CDT the first git ends the scan, inside a word too" "/b|" "$(cdt_of 'cd /a && cd /b && echo legit; cd /c')"
expect_eq "§CDT a cd after the commit is never read" "" "$(cdt_of 'cd /a && git commit -m x && cd /z')"
expect_eq "§CDT one segment has nothing after it to read" "" "$(cdt_of 'cd /a')"
# wave-25 T12: a commit spelled GIT ends the scan exactly as git does. Before T12 the scan cut
# only at the literal `git`, so a cd AFTER `GIT commit` was read as a second directory and the
# commit refused where its lower-case form passes. Only a segment whose WORD folds to git
# ends it: an `echo GITHUB` is no commit, and the scan reads on past it.
expect_eq "§CDT a cd after a GIT commit is never read, as after git" "" "$(cdt_of 'cd /a && GIT commit -m x && cd /z')"
expect_eq "§CDT …nor after Git, behind its own subshell opener" "/b|" "$(cdt_of 'cd /a && cd /b && (Git commit -m x); cd /z')"
expect_eq "§CDT an uppercase word that is not git ends nothing" "/b|" "$(cdt_of 'cd /a && echo GITHUB && cd /b && git commit -m x')"

finish
