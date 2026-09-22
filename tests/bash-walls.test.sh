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
# line_of <regex> — the 1-based line of the first stderr line matching, or empty.
line_of()     { printf '%s\n' "$ERR" | awk -v re="$1" '$0 ~ re {print NR; exit}'; }

require_helpers mk_repo block_plan arm_roster mk_payload run_hook json_docs deny_reason \
                context_of line_of updated_timeout_of has_updated_input

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
expect_eq "14h: …and carries no updatedInput — there is nothing to repair" "no" "$(has_updated_input)"
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
run_hook "$(mk_payload "$R15" 'for s in a b; do bash "tests/$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15b: an unexpanded suite name is still refused" 2 "$ST"
expect_contains "15b2: …and the recorded budget is on the DEFAULT stderr too" \
  "archive.test.sh" "$ERR"

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
expect_empty "15f2: …and both streams stay empty" "$OUT$ERR"

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
run_hook "$(mk_payload "$R15L" 'for s in a b; do bash "tests/$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15g1: an unexpanded name against a too-long single suite is still refused" 2 "$ST"
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
run_hook "$(mk_payload "$R_BELOW_TRUE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_BELOW_TRUE"
expect_status "16o: the use_worktree: true twin refuses the same commit for the same fields" 2 "$ST"
expect_contains "16o: …naming them" "worktree base-sha branch" "$ERR"


finish
