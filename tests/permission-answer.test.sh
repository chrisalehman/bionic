#!/bin/bash
# tests/permission-answer.test.sh — hooks/permission-answer.sh, THE CARRIER (epic-23
# wave-25-never-paused, REQ-1, REQ-2, REQ-3, REQ-5, REQ-6, REQ-7; spec D1, D8, D9, D10).
#
# WHAT IT OWNS. The one hook that answers the platform's permission question for an engaged
# run. It is registered on PermissionRequest only, collects the facts (who asked, which
# class, which roots, what the action writes and deletes), hands them to the grant
# (payload/scripts/lib/grant.sh) and prints ONE decision object, allow or deny. Every answer
# leaves one line in the answer log beside the audit log; a reserved denial leaves one gate
# line for the lead.
#
# THE FAIL DIRECTION IS THE POINT, and it is the one hook whose direction differs from the
# fleet's. Before engagement is known it is silent (the stock dialog shows, bionic claims no
# authority it cannot establish). Once the session is known to be engaged and the switch is
# on, every exit that has not printed a decision prints a DENY naming the failure: never an
# allow, never empty stdout. §A5 drives the faults and the trap itself.
#
# One section per Eval-design row of the spec that names this suite (§A1, §A2, §A4–§A12),
# each built to go red on the planted defect its matrix block names under `fails-when:`; then
# §A13–§A16, the brief's additions (main= for every class, allow paths end to end, the gate
# line, the size bound). §A8 and §A9 read EVERY decision the suite collected, so they run last
# but one.
#
# HERMETIC. Every project is a fixture under one mktemp sandbox: a git repository on the
# run's working branch, a `.bionic` tree with a plan, an engagement marker, a roster and a
# workspace file built by the production writers' shapes. HOME is a scratch directory inside
# the sandbox, so the answer log (which lives under $HOME/.claude/logs, beside the audit log)
# lands in the sandbox and nowhere else. No network, no real `claude`. The hook is the real
# file, fed a JSON payload on stdin, exactly as the harness delivers it.
#
# FIXTURE FIDELITY (per .claude/rules/test-harness.md). The payload is the shape the live
# check measured (record/wave-25-never-paused/verify-first-permission-hook.md E2, E3, E7):
# session_id, transcript_path, cwd, scratchpad_dir, permission_mode, hook_event_name,
# tool_name, tool_input, permission_suggestions, plus agent_id and agent_type for an agent.
# The session id is the LEAD's for every asker (measured). Roster rows come from the
# production writer (`roster_row` through tests/lib/roster-row.sh); workspace lines are the
# T1 interface shape, written by hand, and the trees they name are real linked worktrees of
# the fixture project (the reader counts nothing else, T18).
#
# ANTI-VACUITY (per .claude/rules/test-harness.md). Every silence (§A4, §A10, §A11, §A5.h) sits
# beside an answer on the same fixture; every deny section carries an allow on the same facts;
# §A8 and §A9 prove their key extractor on a planted object before reading an absence; the
# trap rows (§A5.g) anchor the plant and run the unmutated copy as their control.
#
# Usage: bash tests/permission-answer.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOK="${PA_TEST_HOOK:-$BIONIC_HOOKS_DIR/permission-answer.sh}"
LIBDIR="$REPO_ROOT/payload/scripts/lib"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/permission-answer-test.XXXXXX")" && pwd -P)"
cleanup() { chmod -R u+rwX "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT

HOME_FX="$SANDBOX/home"
mkdir -p "$HOME_FX" "$SANDBOX/plugins"
SID="pa0swer1-2222-3333-4444-555555555555"
BRANCH="wave/99-fx"
PLAN_BASE="wave-99-fx"
TAB=$'\t'
NL=$'\n'

# Every stdout the hook printed in the whole suite, one per drive, for §A8 and §A9.
ALL_OUT="$SANDBOX/all-answers.txt"
: > "$ALL_OUT"

# ---------- fixture builders ----------

# make_project <name> <bound|none> -> the project dir. A git repo whose main checkout holds the
# run's working branch, so `worktree_checkout_of` answers with the main root (the A13 shape: a
# lead whose checkout IS the main root). The plan is OPEN, and the engagement marker either
# binds it (`bound`) or says `plan=none` (`none`, the AC-2.5 shape: an unbound session in a
# root whose newest open plan is somebody's).
make_project() {
  local name="$1" mode="$2" dir plan
  dir="$SANDBOX/$name"
  mkdir -p "$dir/src" "$dir/.bionic/tmp" "$dir/.bionic/docs/plans/epic-99" \
           "$dir/.bionic/docs/specs/epic-99" "$dir/.bionic/docs/record/$PLAN_BASE" \
           "$SANDBOX/$name-scratch"
  git -C "$dir" init -q 2>/dev/null
  git -C "$dir" checkout -q -b "$BRANCH" 2>/dev/null
  git -C "$dir" -c user.email=fx@example.invalid -c user.name=fx commit -q --allow-empty -m init 2>/dev/null
  # The two trees the sections name are LINKED WORKTREES of the project, as `create` makes
  # them: a recorded path counts only when git lists it as one (wave-25 T18, §A2b).
  git -C "$dir" worktree add -q -b wt/25-T1 "$dir/.worktrees/25-T1" HEAD >/dev/null 2>&1
  git -C "$dir" worktree add -q -b wt/25-T9 "$dir/.worktrees/25-T9" HEAD >/dev/null 2>&1
  plan="$dir/.bionic/docs/plans/epic-99/$PLAN_BASE.plan.md"
  cat > "$plan" <<PAPLAN
---
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
working-branch: $BRANCH
spec: specs/epic-99/$PLAN_BASE.spec.md
requirements: specs/epic-99/$PLAN_BASE.requirements.md
---

# fixture plan

## SDLC State

integration-branch: main
intent: build
rigor: audited
scale: wave
current: 4

- Step 4: tasks in flight
PAPLAN
  : > "$dir/.bionic/docs/specs/epic-99/$PLAN_BASE.spec.md"
  : > "$dir/.bionic/docs/specs/epic-99/$PLAN_BASE.requirements.md"
  if [ "$mode" = bound ]; then
    printf 'plan=%s\n' "$plan" > "$dir/.bionic/tmp/engaged-$SID.state"
  else
    printf 'plan=none\n' > "$dir/.bionic/tmp/engaged-$SID.state"
  fi
  printf '%s' "$dir"
}

scratch_of() { printf '%s-scratch' "$1"; }
record_of() { printf '%s/.bionic/docs/record/%s' "$1" "$PLAN_BASE"; }

# add_roster_row <project> <name> <agent_id> <subagent_type> <deliverable>
add_roster_row() {
  local f="$1/.bionic/tmp/roster-$SID.state"
  [ -f "$f" ] || roster_header > "$f"
  roster_row_fixture status=confirmed session="$SID" name="$2" agent_id="$3" \
    subagent_type="$4" deliverable="$5" >> "$f"
}

# add_workspace <project> <name> <tree> — the T1 interface line, verbatim.
add_workspace() {
  printf 'workspace/v1|session=%s|name=%s|path=%s|branch=wt/%s|base=abc1234|plan=none|at=2026-10-03T23:00:00Z\n' \
    "$SID" "$2" "$3" "$2" >> "$1/.bionic/tmp/workspaces-$SID.state"
}

# payload <project> <tool> <tool_input json> [agent_id] [agent_type] [cwd]
payload() {
  local proj="$1" tool="$2" ti="$3" aid="${4:-}" atype="${5:-}" cwd="${6:-}"
  [ -n "$cwd" ] || cwd="$proj"
  jq -n --arg s "$SID" --arg c "$cwd" --arg sc "$(scratch_of "$proj")" --arg t "$tool" \
        --argjson ti "$ti" --arg aid "$aid" --arg aty "$atype" \
        --arg tp "$HOME_FX/.claude/projects/fx/$SID.jsonl" '
    {session_id:$s, transcript_path:$tp, cwd:$c, scratchpad_dir:$sc,
     permission_mode:"bypassPermissions", hook_event_name:"PermissionRequest",
     tool_name:$t, tool_input:$ti, permission_suggestions:[]}
    + (if $aid == "" then {} else {agent_id:$aid, agent_type:$aty} end)'
}
bash_ti() { jq -n --arg c "$1" '{command:$c, description:"a fixture command"}'; }
file_ti() { jq -n --arg p "$1" '{file_path:$p, content:"x"}'; }

# drive <project> <payload> [env…] -> OUT RC ERR; the hook runs with cwd = <project>,
# CLAUDE_PROJECT_DIR = <project> (the platform sets it for every hook command, so the root is
# the project's whatever the asker's own cwd is) and the scratch HOME.
OUT=""; RC=0; ERR=""
drive() {
  local proj="$1" pl="$2"; shift 2
  OUT="$(cd "$proj" && printf '%s' "$pl" | env HOME="$HOME_FX" CLAUDE_PROJECT_DIR="$proj" \
      BIONIC_PLUGINS_DIR="$SANDBOX/plugins" CLAUDE_CODE_SESSION_ID="$SID" "$@" \
      bash "$HOOK" 2>"$SANDBOX/.err")"
  RC=$?
  ERR="$(cat "$SANDBOX/.err")"
  [ -z "$OUT" ] || printf '%s\n' "$OUT" >> "$ALL_OUT"
  return 0
}

# Readers of one answer. n_obj counts JSON values on stdout; behavior and message read the
# decision. A stdout that is not JSON reads as `bad`.
n_obj() { printf '%s' "$1" | jq -s 'length' 2>/dev/null || printf 'bad'; }
behavior() { printf '%s' "$1" | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null || printf 'bad'; }
message() { printf '%s' "$1" | jq -r '.hookSpecificOutput.decision.message // ""' 2>/dev/null; }
event_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null; }

# The answer log for a project: beside the audit log, read from the lib that names that one.
log_of() {
  local a
  a="$(HOME="$HOME_FX" bash -c '. "$1/root.sh" >/dev/null 2>&1; audit_path "$2"' _ "$LIBDIR" "$1")"
  printf '%s/permission-answers.log' "${a%/*}"
}
log_lines() { local f; f="$(log_of "$1")"; if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else printf 0; fi; }
gate_of() { printf '%s/.bionic/tmp/gate-%s.state' "$1" "$SID"; }

# Recorded for the report, not used as a knob: these suites carry no width setting.
if [ -r "$LIBDIR/resources.sh" ]; then
  _pl="$(bash -c '. "$1" >/dev/null 2>&1 && pressure_level 8' _ "$LIBDIR/resources.sh" 2>/dev/null)" || _pl=""
  echo "pressure at suite start: ${_pl:-unread}"
fi

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A1 the lead's question is answered: the incident payload yields exactly one decision object"

A1P="$(make_project a1 bound)"
A1S="$(scratch_of "$A1P")"
INCIDENT="echo TR; bash -c 'TR=./x.jsonl; touch \$TR; rm -f \$TR'"
drive "$A1P" "$(payload "$A1P" Bash "$(bash_ti "$INCIDENT")" "" "" "$A1S")"
expect_eq "A1.1 rc 0" "0" "$RC"
expect_eq "A1.2 exactly one JSON value on stdout" "1" "$(n_obj "$OUT")"
expect_eq "A1.3 it is a PermissionRequest decision" "PermissionRequest" "$(event_of "$OUT")"
expect_regex "A1.4 its behavior is allow or deny" '^(allow|deny)$' "$(behavior "$OUT")"
expect_eq "A1.5 the incident (an unread rm target) is denied" "deny" "$(behavior "$OUT")"
expect_eq "A1.6 …and it leaves one answer line" "1" "$(log_lines "$A1P")"
# The paired allow on the same fixture: the lead inside its own checkout.
drive "$A1P" "$(payload "$A1P" Bash "$(bash_ti "touch $A1P/src/a.txt")")"
expect_eq "A1.7 the same lead touching a file in its checkout is allowed" "allow" "$(behavior "$OUT")"
expect_eq "A1.8 …as exactly one object" "1" "$(n_obj "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A2 a subagent's and a teammate's question are answered for THAT asker's workspace"

A2P="$(make_project a2 bound)"
A2T="$A2P/.worktrees/25-T1"
A2R="$(record_of "$A2P")/R9-report.md"
add_roster_row "$A2P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A2P")/T1.md"
add_roster_row "$A2P" w99-R9 af32d07b37c07888c general-purpose "$A2R"
add_workspace "$A2P" w99-T1 "$A2T"

# The teammate (a writer: its name has a recorded tree).
drive "$A2P" "$(payload "$A2P" Bash "$(bash_ti "touch $SANDBOX/elsewhere.txt")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2T")"
expect_eq "A2.1 teammate outside its tree: one decision" "1" "$(n_obj "$OUT")"
expect_eq "A2.2 …a deny" "deny" "$(behavior "$OUT")"
expect_contains "A2.3 …naming the teammate's own recorded tree" "$A2T" "$(message "$OUT")"
expect_contains "A2.3b …as a writer's grant, not the lead's" "This writer may write under" "$(message "$OUT")"
drive "$A2P" "$(payload "$A2P" Bash "$(bash_ti "touch $A2T/a.txt")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2T")"
expect_eq "A2.4 teammate inside its tree: allow" "allow" "$(behavior "$OUT")"
# The lead on the same fixture is not the teammate: its checkout is the main root, so the
# lead's answer to the same outside target names the checkout, not the teammate's tree alone.
drive "$A2P" "$(payload "$A2P" Bash "$(bash_ti "touch $SANDBOX/elsewhere.txt")")"
expect_contains "A2.5 the lead's answer on the same fixture names the lead's checkout" "$A2P" "$(message "$OUT")"
expect_contains "A2.6 …and calls the asker the lead" "lead" "$(message "$OUT")"

# The subagent (a reader: no recorded tree; its declared report is its workspace).
drive "$A2P" "$(payload "$A2P" Bash "$(bash_ti "touch $A2P/src/b.txt")" af32d07b37c07888c general-purpose)"
expect_eq "A2.7 subagent outside its workspace: one decision" "1" "$(n_obj "$OUT")"
expect_eq "A2.8 …a deny" "deny" "$(behavior "$OUT")"
expect_contains "A2.9 …naming the subagent's declared report" "$A2R" "$(message "$OUT")"
expect_absent "A2.10 …and not the teammate's tree" "$A2T" "$(message "$OUT")"
drive "$A2P" "$(payload "$A2P" Write "$(file_ti "$A2R")" af32d07b37c07888c general-purpose)"
expect_eq "A2.11 subagent writing its declared report: allow" "allow" "$(behavior "$OUT")"
drive "$A2P" "$(payload "$A2P" Write "$(file_ti "$A2T/x.txt")" af32d07b37c07888c general-purpose)"
expect_eq "A2.12 subagent writing into the teammate's tree: deny" "deny" "$(behavior "$OUT")"

# The unnamed subagent: dispatched without a name, so its roster row's name= is empty (the
# shape the live walk rehearsal recorded). Not a fault: a reader, labelled by its agent id.
A2UID=a30eccfe52f18bc99
A2UR="$(record_of "$A2P")/w3-unnamed.md"
add_roster_row "$A2P" "" "$A2UID" general-purpose "$A2UR"
A2ULOG="$(log_of "$A2P")"
A2UN0="$(log_lines "$A2P")"
drive "$A2P" "$(payload "$A2P" Bash "$(bash_ti "touch $A2P/src/c.txt")" "$A2UID" general-purpose)"
expect_eq "A2.13 unnamed subagent outside its workspace: one decision" "1" "$(n_obj "$OUT")"
expect_eq "A2.14 …a deny" "deny" "$(behavior "$OUT")"
expect_contains "A2.15 …naming the unnamed agent's declared report" "$A2UR" "$(message "$OUT")"
expect_absent "A2.16 …not as a failure" "failure:" "$(message "$OUT")"
expect_absent "A2.17 …and not as a roster row that names no agent" "names no agent" "$(message "$OUT")"
expect_absent "A2.17b …nor the teammate's tree" "$A2T" "$(message "$OUT")"
expect_contains "A2.18 …its answer-log line carries the agent id as the asker" "|agent $A2UID|" "$(tail -1 "$A2ULOG" 2>/dev/null)"
expect_absent "A2.18a …and the line records no failure" "failure:" "$(tail -1 "$A2ULOG" 2>/dev/null)"
expect_eq "A2.18b …as exactly one new answer line" "$((A2UN0 + 1))" "$(log_lines "$A2P")"
drive "$A2P" "$(payload "$A2P" Write "$(file_ti "$A2UR")" "$A2UID" general-purpose)"
expect_eq "A2.19 unnamed subagent writing its declared report: allow" "allow" "$(behavior "$OUT")"
drive "$A2P" "$(payload "$A2P" Write "$(file_ti "$A2T/x.txt")" "$A2UID" general-purpose)"
expect_eq "A2.20 unnamed subagent writing into the teammate's tree: deny" "deny" "$(behavior "$OUT")"
# The control: an agent id the roster has no row for is still the failure.
drive "$A2P" "$(payload "$A2P" Bash "$(bash_ti "touch $A2P/src/d.txt")" a00000000000000000 general-purpose)"
expect_eq "A2.21 an agent id with no roster row: one decision" "1" "$(n_obj "$OUT")"
expect_eq "A2.22 …a deny" "deny" "$(behavior "$OUT")"
expect_contains "A2.23 …that is still the failure naming the missing row" "the roster has no row for the asking agent a00000000000000000" "$(message "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A2b a forged workspace line never widens a grant: only a tree git lists counts (wave-25 T18, critic C1)"
#
# The record lives in .bionic/tmp, and a script the hook never sees can append to it (N7). A
# line naming the main checkout, or its parent, after the writer's true line made the reader
# answer the forged path and the hook grant the writer the hook libraries themselves. Driven
# through the hook, for the writer's own root and for the lead's tree roots, each deny beside
# the allow the true tree still gets.

A2BP="$(make_project a2b bound)"
A2BT="$A2BP/.worktrees/25-T1"
mkdir -p "$A2BP/hooks"; : > "$A2BP/hooks/x.sh"
add_roster_row "$A2BP" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A2BP")/T1.md"
add_workspace "$A2BP" w99-T1 "$A2BT"
expect_contains "A2b.0 fixture: the writer's tree is one git lists" "worktree $A2BT" "$(git -C "$A2BP" worktree list --porcelain)"
drive "$A2BP" "$(payload "$A2BP" Write "$(file_ti "$A2BP/hooks/x.sh")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.0b control: before any forged line, the writer may not write the main checkout's hooks" "deny" "$(behavior "$OUT")"

# A line naming the main checkout, appended after the true one.
add_workspace "$A2BP" w99-T1 "$A2BP"
drive "$A2BP" "$(payload "$A2BP" Write "$(file_ti "$A2BP/hooks/x.sh")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.1 forged path=<main>: a writer's Write to <main>/hooks/x.sh is denied" "deny" "$(behavior "$OUT")"
expect_contains "A2b.2 …and the writer's grant it names holds the true tree" "$A2BT" "$(message "$OUT")"
drive "$A2BP" "$(payload "$A2BP" Bash "$(bash_ti "rm -rf $A2BP/hooks")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.3 forged path=<main>: a writer's delete of <main>/hooks is denied" "deny" "$(behavior "$OUT")"
drive "$A2BP" "$(payload "$A2BP" Write "$(file_ti "$A2BT/inside.txt")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.4 paired positive: a write inside the writer's true tree is still allowed" "allow" "$(behavior "$OUT")"

# A line naming the parent of the main checkout, appended after both.
add_workspace "$A2BP" w99-T1 "${A2BP%/*}"
drive "$A2BP" "$(payload "$A2BP" Write "$(file_ti "$A2BP/hooks/x.sh")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.5 forged path=<parent of main>: the Write to <main>/hooks/x.sh is denied" "deny" "$(behavior "$OUT")"
drive "$A2BP" "$(payload "$A2BP" Bash "$(bash_ti "touch $SANDBOX/a2b-elsewhere.txt")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.6 …and so is a write beside the project" "deny" "$(behavior "$OUT")"
drive "$A2BP" "$(payload "$A2BP" Bash "$(bash_ti "touch $A2BT/inside2.txt")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A2BT")"
expect_eq "A2b.7 paired positive: the true tree is still the writer's" "allow" "$(behavior "$OUT")"

# The rule is by place, not by a `.worktrees/` prefix: `create` accepts another parent
# directory, and a writer whose tree git lists there keeps it.
A2BT4="$A2BP/trees/25-T4"
git -C "$A2BP" worktree add -q -b wt/25-T4 "$A2BT4" HEAD >/dev/null 2>&1
add_roster_row "$A2BP" w99-T4 aw99-T4-1 bionic:senior-implementor "$(record_of "$A2BP")/T4.md"
add_workspace "$A2BP" w99-T4 "$A2BT4"
drive "$A2BP" "$(payload "$A2BP" Write "$(file_ti "$A2BT4/inside.txt")" aw99-T4-1 w99-T4 "$A2BT4")"
expect_eq "A2b.8 a writer whose tree git lists under <root>/trees writes inside it: allow" "allow" "$(behavior "$OUT")"

# THE LEAD'S TREE ROOTS. The lead's checkout is a linked worktree holding the working branch,
# so the main checkout is no root of its own; every recorded tree of the session is.
A2LP="$(make_project a2l bound)"
A2LW="$A2LP/.worktrees/25-wave"
git -C "$A2LP" checkout -q -b side 2>/dev/null
git -C "$A2LP" worktree add -q "$A2LW" "$BRANCH" >/dev/null 2>&1
mkdir -p "$A2LP/hooks"; : > "$A2LP/hooks/x.sh"
add_workspace "$A2LP" w99-T1 "$A2LP/.worktrees/25-T1"
drive "$A2LP" "$(payload "$A2LP" Write "$(file_ti "$A2LW/x.txt")")"
expect_eq "A2b.lead.0 control: the lead writes inside its checkout (a linked worktree)" "allow" "$(behavior "$OUT")"
drive "$A2LP" "$(payload "$A2LP" Write "$(file_ti "$A2LP/hooks/x.sh")")"
expect_eq "A2b.lead.0b control: before any forged line, the lead may not write the main checkout's hooks" "deny" "$(behavior "$OUT")"
add_workspace "$A2LP" w99-X "$A2LP"
add_workspace "$A2LP" w99-Y "${A2LP%/*}"
drive "$A2LP" "$(payload "$A2LP" Write "$(file_ti "$A2LP/hooks/x.sh")")"
expect_eq "A2b.lead.1 forged path=<main>: the lead's Write to <main>/hooks/x.sh is denied" "deny" "$(behavior "$OUT")"
drive "$A2LP" "$(payload "$A2LP" Bash "$(bash_ti "rm -rf $A2LP/hooks")")"
expect_eq "A2b.lead.2 …and its delete of <main>/hooks" "deny" "$(behavior "$OUT")"
drive "$A2LP" "$(payload "$A2LP" Bash "$(bash_ti "touch $SANDBOX/a2l-elsewhere.txt")")"
expect_eq "A2b.lead.3 forged path=<parent of main>: a write beside the project is denied" "deny" "$(behavior "$OUT")"
drive "$A2LP" "$(payload "$A2LP" Write "$(file_ti "$A2LP/.worktrees/25-T1/y.txt")")"
expect_eq "A2b.lead.4 paired positive: the session's true recorded tree is still the lead's" "allow" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A4 tools that collect human input are never answered"

A4P="$(make_project a4 bound)"
for tool in AskUserQuestion ExitPlanMode; do
  drive "$A4P" "$(payload "$A4P" "$tool" '{"questions":[{"question":"ok?"}],"plan":"p"}')"
  expect_eq "A4.$tool.1 rc 0" "0" "$RC"
  expect_empty "A4.$tool.2 empty stdout" "$OUT"
done
expect_eq "A4.3 …and no answer line for either" "0" "$(log_lines "$A4P")"
# The control on the same fixture: a tool that is not a human-input tool IS answered.
drive "$A4P" "$(payload "$A4P" WebFetch '{"url":"https://example.invalid"}')"
expect_eq "A4.4 control: an unreadable tool on the same fixture is answered (deny)" "deny" "$(behavior "$OUT")"
expect_contains "A4.5 …saying bionic cannot read what it does" "cannot read what this tool does" "$(message "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A5 after engagement, a failure answers deny naming the fault: never allow, never silence"

A5P="$(make_project a5 bound)"
A5T="$A5P/.worktrees/25-T1"
# (a) Input the hook cannot read, in an engaged project (engagement comes from the session
#     id and the cwd, so it is established before the payload is parsed).
drive "$A5P" '{"tool_name": "Bash", "tool_input": {"command": "ls"'
expect_eq "A5.a1 malformed input: one decision" "1" "$(n_obj "$OUT")"
expect_eq "A5.a2 …deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.a3 …naming the fault" "could not read the question" "$(message "$OUT")"

# (b) An agent, and no roster at all for this session.
A5L0="$(log_lines "$A5P")"
drive "$A5P" "$(payload "$A5P" Bash "$(bash_ti "touch $A5T/a.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A5.b1 missing roster: deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.b2 …naming the missing roster" "no roster" "$(message "$OUT")"
expect_eq "A5.b3 …and the failure is on the record" "$((A5L0 + 1))" "$(log_lines "$A5P")"
expect_contains "A5.b4 …as a deny-fix line" "|deny-fix|" "$(tail -1 "$(log_of "$A5P")" 2>/dev/null)"

# (c) A roster, but no row for this agent id.
add_roster_row "$A5P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A5P")/T1.md"
drive "$A5P" "$(payload "$A5P" Bash "$(bash_ti "touch $A5T/a.txt")" aw99-stranger-1111 w99-X)"
expect_eq "A5.c1 an agent id with no roster row: deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.c2 …naming the id" "aw99-stranger-1111" "$(message "$OUT")"

# The paired positive on the same fixture: once the workspace is recorded, the same agent's
# same command is allowed — so the denials below are the faults', not the fixture's.
add_workspace "$A5P" w99-T1 "$A5T"
drive "$A5P" "$(payload "$A5P" Bash "$(bash_ti "touch $A5T/a.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A5.ctl the recorded writer inside its tree is allowed" "allow" "$(behavior "$OUT")"

# (d) The workspace file cannot be read.
WSF="$A5P/.bionic/tmp/workspaces-$SID.state"
chmod 000 "$WSF"
drive "$A5P" "$(payload "$A5P" Bash "$(bash_ti "touch $A5T/a.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
chmod 644 "$WSF"
expect_eq "A5.d1 unreadable workspace file: deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.d2 …naming the workspace record" "workspace record" "$(message "$OUT")"

# (e) The workspace file is a symlink (refused, never followed).
mv "$WSF" "$SANDBOX/a5-workspaces-real"
ln -s "$SANDBOX/a5-workspaces-real" "$WSF"
drive "$A5P" "$(payload "$A5P" Bash "$(bash_ti "touch $A5T/a.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A5.e1 symlinked workspace file: deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.e2 …naming the workspace record" "workspace record" "$(message "$OUT")"
rm -f "$WSF"; mv "$SANDBOX/a5-workspaces-real" "$WSF"

# (f) A failing decision: a file path carrying a newline is an effect the decision cannot
#     take (grant_decide rc 2 on a malformed line).
drive "$A5P" "$(payload "$A5P" Write "$(file_ti "$A5T/a${NL}b.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A5.f1 a failing decision: deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.f2 …naming the decision" "decision" "$(message "$OUT")"

# (f2) A question whose shape is not the tool's: a Bash call with no command string, a Read
#      with no path. Nothing is read, so nothing is allowed.
drive "$A5P" "$(payload "$A5P" Bash '{"command":["rm","-rf","/"]}')"
expect_eq "A5.f3 a Bash question with no command string: deny" "deny" "$(behavior "$OUT")"
expect_contains "A5.f4 …saying it names no command" "names no command" "$(message "$OUT")"
drive "$A5P" "$(payload "$A5P" Read '{}')"
expect_eq "A5.f5 a Read with no path: deny" "deny" "$(behavior "$OUT")"

# (g) THE TRAP ITSELF. A copy of the hook beside a copy of the library, with an unplanned
#     exit planted right after the trap is armed, must still answer deny. The anchor proves
#     the plant landed; the unmutated copy proves the copy answers at all.
MUT="$SANDBOX/mut"
mkdir -p "$MUT/hooks" "$MUT/scripts/lib"
cp "$LIBDIR"/*.sh "$MUT/scripts/lib/"
cp "$HOOK" "$MUT/hooks/permission-answer.sh" 2>/dev/null
anchor "$HOOK" "trap '_pa_on_exit' EXIT" 1
for plant in 'exit 0' 'exit 3' 'printf %s "$PA_NEVER_SET_VARIABLE"'; do
  awk -v p="$plant" '{ print } $0 == "trap '"'"'_pa_on_exit'"'"' EXIT" { print p }' "$HOOK" > "$MUT/hooks/pa-mutant.sh"
  expect_eq "A5.g0 [$plant] the plant landed (the mutant differs from the hook by one line)" "1" \
    "$(diff "$HOOK" "$MUT/hooks/pa-mutant.sh" | /usr/bin/grep -c '^>')"
  OUT="$(cd "$A5P" && printf '%s' "$(payload "$A5P" Bash "$(bash_ti "touch $A5T/a.txt")")" \
         | env HOME="$HOME_FX" CLAUDE_PROJECT_DIR="$A5P" BIONIC_PLUGINS_DIR="$SANDBOX/plugins" \
           CLAUDE_CODE_SESSION_ID="$SID" bash "$MUT/hooks/pa-mutant.sh" 2>/dev/null)"
  [ -z "$OUT" ] || printf '%s\n' "$OUT" >> "$ALL_OUT"
  expect_eq "A5.g1 [$plant] an unplanned exit after the trap still answers one decision" "1" "$(n_obj "$OUT")"
  expect_eq "A5.g2 [$plant] …a deny" "deny" "$(behavior "$OUT")"
done
OUT="$(cd "$A5P" && printf '%s' "$(payload "$A5P" Bash "$(bash_ti "touch $A5P/src/a.txt")")" \
       | env HOME="$HOME_FX" CLAUDE_PROJECT_DIR="$A5P" BIONIC_PLUGINS_DIR="$SANDBOX/plugins" \
         CLAUDE_CODE_SESSION_ID="$SID" bash "$MUT/hooks/permission-answer.sh" 2>/dev/null)"
expect_eq "A5.g3 control: the unmutated copy answers allow for the lead in its checkout" "allow" "$(behavior "$OUT")"

# (h) BEFORE engagement a broken install is silent: the copy with no library anywhere.
mkdir -p "$SANDBOX/broken/hooks"
cp "$HOOK" "$SANDBOX/broken/hooks/permission-answer.sh" 2>/dev/null
OUT="$(cd "$A5P" && printf '%s' "$(payload "$A5P" Bash "$(bash_ti "touch $A5P/src/a.txt")")" \
       | env HOME="$HOME_FX" CLAUDE_PROJECT_DIR="$A5P" BIONIC_PLUGINS_DIR="$SANDBOX/plugins" \
         CLAUDE_CODE_SESSION_ID="$SID" bash "$SANDBOX/broken/hooks/permission-answer.sh" 2>/dev/null)"
RC=$?
expect_eq "A5.h1 no library: rc 0" "0" "$RC"
expect_empty "A5.h2 …and nothing on stdout (bionic claims no authority it cannot establish)" "$OUT"
expect_true "A5.h3 …and the copy really is the hook (not an empty file)" test -s "$SANDBOX/broken/hooks/permission-answer.sh"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A6 an unbound session has the scratch only, whatever plan is newest"

A6P="$(make_project a6 none)"
A6S="$(scratch_of "$A6P")"
drive "$A6P" "$(payload "$A6P" Write "$(file_ti "$A6S/notes.md")")"
expect_eq "A6.1 plan=none: a scratch target allows" "allow" "$(behavior "$OUT")"
drive "$A6P" "$(payload "$A6P" Bash "$(bash_ti "touch $A6S/y.txt")")"
expect_eq "A6.2 …through Bash too" "allow" "$(behavior "$OUT")"
drive "$A6P" "$(payload "$A6P" Write "$(file_ti "$(record_of "$A6P")/x.md")")"
expect_eq "A6.3 a target in the newest open plan's record dir is denied" "deny" "$(behavior "$OUT")"
expect_contains "A6.4 …and the message calls the asker this session" "This session" "$(message "$OUT")"
drive "$A6P" "$(payload "$A6P" Write "$(file_ti "$A6P/src/x.txt")")"
expect_eq "A6.5 …and the checkout too" "deny" "$(behavior "$OUT")"
# The bound control: the same fixture, the marker binding the plan, the record target allows.
printf 'plan=%s\n' "$A6P/.bionic/docs/plans/epic-99/$PLAN_BASE.plan.md" > "$A6P/.bionic/tmp/engaged-$SID.state"
drive "$A6P" "$(payload "$A6P" Write "$(file_ti "$(record_of "$A6P")/x.md")")"
expect_eq "A6.6 control: bound to that plan, the same record target allows" "allow" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A7 the incident command is denied with a fix naming the unread target"

A7P="$(make_project a7 bound)"
A7S="$(scratch_of "$A7P")"
drive "$A7P" "$(payload "$A7P" Bash "$(bash_ti "$INCIDENT")" "" "" "$A7S")"
expect_eq "A7.1 the incident: deny" "deny" "$(behavior "$OUT")"
# The rm's target is the variable $TR; the grant names the FIRST effect it could not read
# (the touch of the same $TR) and counts the rest, so the unread target is named either way.
expect_contains "A7.2 …naming the unread target, the variable the rm removes" 'in the target: $TR' "$(message "$OUT")"
expect_contains "A7.2b …and counting the rm's own unread effect beside it" "1 more of its effects" "$(message "$OUT")"
expect_contains "A7.3 …with the fix: a script file in the workspace" "script file" "$(message "$OUT")"
expect_contains "A7.4 …named by the asker's scratch" "$A7S" "$(message "$OUT")"
INCIDENT_FULL="cd $A7S/walkb; cat >> env.sh <<'EOF'
sweep() { ( cd \"\$R\" && CLAUDE_CODE_SESSION_ID=\"\$SID\" bash \$X/hooks/session-sweeper.sh \"\$@\" ); }
EOF
for v in head base; do echo \"=== \$v\"; bash -c '. ./env.sh '\$v'; SID=walk-b-0003; R=\"\$(mkrepo verdict \$SID)\"; mkdir -p \$R/out; TR=\$TR_DIR/\$SID.jsonl; rm -f \$TR;
echo \"--- (a0) no transcript at all\"; sweep verdict rep; echo rc=\$?' 2>&1; done"
drive "$A7P" "$(payload "$A7P" Bash "$(bash_ti "$INCIDENT_FULL")" "" "" "$A7S")"
expect_eq "A7.5 the fuller incident shape: deny" "deny" "$(behavior "$OUT")"
expect_regex "A7.6 …naming what could not be read" 'Could not tell what this command writes or deletes' "$(message "$OUT")"
# The paired allow: the same rm with a literal target in the scratch.
drive "$A7P" "$(payload "$A7P" Bash "$(bash_ti "touch $A7S/x.jsonl; rm -f $A7S/x.jsonl")" "" "" "$A7S")"
expect_eq "A7.7 control: the literal-target rewrite in the scratch allows" "allow" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A10 a session with no engagement marker gets no answer"

A10P="$(make_project a10 bound)"
rm -f "$A10P/.bionic/tmp/engaged-$SID.state"
drive "$A10P" "$(payload "$A10P" Bash "$(bash_ti "$INCIDENT")")"
expect_eq "A10.1 rc 0" "0" "$RC"
expect_empty "A10.2 empty stdout" "$OUT"
expect_eq "A10.3 no answer line" "0" "$(log_lines "$A10P")"
ln -s "$SANDBOX/a10-decoy" "$A10P/.bionic/tmp/engaged-$SID.state"
printf 'plan=none\n' > "$SANDBOX/a10-decoy"
drive "$A10P" "$(payload "$A10P" Bash "$(bash_ti "$INCIDENT")")"
expect_empty "A10.4 a symlinked marker is no engagement: empty stdout" "$OUT"
rm -f "$A10P/.bionic/tmp/engaged-$SID.state"
printf 'plan=none\n' > "$A10P/.bionic/tmp/engaged-$SID.state"
drive "$A10P" "$(payload "$A10P" Bash "$(bash_ti "$INCIDENT")")"
expect_eq "A10.5 control: the marker restored, the same payload is answered" "deny" "$(behavior "$OUT")"
expect_eq "A10.6 …and leaves its line" "1" "$(log_lines "$A10P")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A11 a project can turn the boundary off; only the literal false does"

A11P="$(make_project a11 bound)"
printf 'permission-answers: false\n' > "$A11P/.bionic/config.yaml"
drive "$A11P" "$(payload "$A11P" Bash "$(bash_ti "$INCIDENT")")"
expect_eq "A11.1 off: rc 0" "0" "$RC"
expect_empty "A11.2 off: empty stdout" "$OUT"
expect_eq "A11.3 off: no answer line" "0" "$(log_lines "$A11P")"
n=0
for v in true no False 0 off; do
  printf 'permission-answers: %s\n' "$v" > "$A11P/.bionic/config.yaml"
  drive "$A11P" "$(payload "$A11P" Bash "$(bash_ti "$INCIDENT")")"
  n=$((n + 1))
  expect_eq "A11.4 [$v] answers" "deny" "$(behavior "$OUT")"
done
: > "$A11P/.bionic/config.yaml"
drive "$A11P" "$(payload "$A11P" Bash "$(bash_ti "$INCIDENT")")"
n=$((n + 1))
expect_eq "A11.5 no key: answers" "deny" "$(behavior "$OUT")"
rm -f "$A11P/.bionic/config.yaml"
drive "$A11P" "$(payload "$A11P" Bash "$(bash_ti "$INCIDENT")")"
n=$((n + 1))
expect_eq "A11.6 no config file: answers" "deny" "$(behavior "$OUT")"
expect_eq "A11.7 every answer above left exactly one line" "$n" "$(log_lines "$A11P")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A12 every answer leaves one line, with the seven fields, outside the project"

A12P="$(make_project a12 bound)"
A12T="$A12P/.worktrees/25-T1"
add_roster_row "$A12P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A12P")/T1.md"
add_workspace "$A12P" w99-T1 "$A12T"
drive "$A12P" "$(payload "$A12P" Bash "$(bash_ti "touch $A12P/src/a.txt")")"
A12_1="$(behavior "$OUT")"
drive "$A12P" "$(payload "$A12P" Bash "$(bash_ti "echo a | cat > b.txt${NL}echo two")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A12T")"
A12_2="$(behavior "$OUT")"
drive "$A12P" "$(payload "$A12P" Bash "$(bash_ti "rm -f $A12P/src/a.txt; rm -f \$X")")"
A12_3="$(behavior "$OUT")"
drive "$A12P" "$(payload "$A12P" Bash "$(bash_ti "git push origin $BRANCH")" aw99-T1-0974313b7a6b74f2 w99-T1)"
A12_4="$(behavior "$OUT")"
drive "$A12P" "$(payload "$A12P" Edit "$(file_ti "$SANDBOX/outside.txt")")"
A12_5="$(behavior "$OUT")"
expect_eq "A12.0 the five answers were allow, allow, deny, deny, deny" "allow allow deny deny deny" \
  "$A12_1 $A12_2 $A12_3 $A12_4 $A12_5"
A12LOG="$(log_of "$A12P")"
expect_eq "A12.1 five answers, five lines" "5" "$(log_lines "$A12P")"
expect_eq "A12.2 every line has exactly seven fields" "5" "$(awk -F'|' 'NF == 7' "$A12LOG" 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "A12.3 every line opens with an ISO-UTC time" "5" \
  "$(/usr/bin/grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\|' "$A12LOG" 2>/dev/null)"
expect_eq "A12.4 every line names the session" "5" "$(awk -F'|' -v s="$SID" '$2 == s' "$A12LOG" 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "A12.5 the askers, in order" "lead w99-T1 lead w99-T1 lead" \
  "$(awk -F'|' '{print $3}' "$A12LOG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
expect_eq "A12.6 the tools, in order" "Bash Bash Bash Bash Edit" \
  "$(awk -F'|' '{print $4}' "$A12LOG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
expect_eq "A12.7 the decisions, in order (a deny writes a line)" "allow allow deny-fix deny-reserved deny-fix" \
  "$(awk -F'|' '{print $5}' "$A12LOG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
expect_eq "A12.8 every line carries a reason" "5" "$(awk -F'|' '$6 != ""' "$A12LOG" 2>/dev/null | wc -l | tr -d ' ')"
expect_contains "A12.9 the head is the command, its pipe and newline replaced" \
  "|echo a   cat > b.txt echo two" "$(sed -n 2p "$A12LOG" 2>/dev/null)"
expect_eq "A12.10 a head is at most 120 characters" "0" \
  "$(awk -F'|' 'length($7) > 120' "$A12LOG" 2>/dev/null | wc -l | tr -d ' ')"
expect_contains "A12.11 the Edit line's head is the path" "$SANDBOX/outside.txt" "$(sed -n 5p "$A12LOG" 2>/dev/null)"
expect_true "A12.12 the log exists" test -f "$A12LOG"
case "$A12LOG" in
  "$A12P"/*) no "A12.13 the log is not under the project" "$A12LOG" ;;
  "$HOME_FX/.claude/logs/"*) ok "A12.13 the log is not under the project: it is beside the audit log" ;;
  *) no "A12.13 the log is not under the project" "unexpected path $A12LOG" ;;
esac
expect_eq "A12.14 nothing named for the log appears inside the project" "" \
  "$(find "$A12P" -name 'permission-answers*' 2>/dev/null)"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A13 main= is passed for every class: the project's shared directories are no one's"

# The lead's checkout IS the main root (the fixture's main checkout holds the working branch).
A13P="$(make_project a13 bound)"
drive "$A13P" "$(payload "$A13P" Bash "$(bash_ti "rm -f $A13P/src/x.txt")")"
expect_eq "A13.lead.0 control: the lead deletes inside its checkout (the main root)" "allow" "$(behavior "$OUT")"
for t in "$A13P/.bionic/docs/notes.md" "$A13P/.worktrees/25-T9/f.txt" "$A13P/.git/config"; do
  drive "$A13P" "$(payload "$A13P" Bash "$(bash_ti "rm -f $t")")"
  expect_eq "A13.lead.1 the lead deleting ${t#"$A13P"/}: deny" "deny" "$(behavior "$OUT")"
  expect_contains "A13.lead.2 …because it is a shared directory of the project" "shared directories" "$(message "$OUT")"
done
# A writer with a recorded tree. (Until T18 this tree was the main root itself; a recorded
# main checkout is no one's tree now, §A2b, so the writer's tree is a linked worktree and the
# deny below still has to come from the shared-directory rule, which its reason names.)
add_roster_row "$A13P" w99-W aw99-W-1 bionic:senior-implementor "$(record_of "$A13P")/W.md"
add_workspace "$A13P" w99-W "$A13P/.worktrees/25-T1"
drive "$A13P" "$(payload "$A13P" Bash "$(bash_ti "rm -f $A13P/.worktrees/25-T1/y.txt")" aw99-W-1 w99-W)"
expect_eq "A13.writer.0 control: the writer deletes inside its recorded tree" "allow" "$(behavior "$OUT")"
drive "$A13P" "$(payload "$A13P" Bash "$(bash_ti "rm -f $A13P/.git/config")" aw99-W-1 w99-W)"
expect_eq "A13.writer.1 the writer deleting .git: deny" "deny" "$(behavior "$OUT")"
expect_contains "A13.writer.2 …because it is a shared directory" "shared directories" "$(message "$OUT")"
# A reader whose declared report sits in the main root's .git.
add_roster_row "$A13P" w99-RD aw99-RD-1 general-purpose "$A13P/.git/description"
drive "$A13P" "$(payload "$A13P" Write "$(file_ti "$(scratch_of "$A13P")/r.md")" aw99-RD-1 general-purpose)"
expect_eq "A13.reader.0 control: the reader writes its scratch" "allow" "$(behavior "$OUT")"
drive "$A13P" "$(payload "$A13P" Write "$(file_ti "$A13P/.git/description")" aw99-RD-1 general-purpose)"
expect_eq "A13.reader.1 the reader writing a report declared in .git: deny" "deny" "$(behavior "$OUT")"
expect_contains "A13.reader.2 …because it is a shared directory" "shared directories" "$(message "$OUT")"
# An unbound session whose scratch is the main root.
A13U="$(make_project a13u none)"
A13UPL="$(payload "$A13U" Write "$(file_ti "$A13U/notes.txt")" | jq --arg s "$A13U" '.scratchpad_dir = $s')"
drive "$A13U" "$A13UPL"
expect_eq "A13.unbound.0 control: an unbound session writes its scratch" "allow" "$(behavior "$OUT")"
drive "$A13U" "$(payload "$A13U" Write "$(file_ti "$A13U/.git/x")" | jq --arg s "$A13U" '.scratchpad_dir = $s')"
expect_eq "A13.unbound.1 …and is denied a write in .git under it" "deny" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A14 allow paths end to end, and the same paths through .. denied"

A14P="$(make_project a14 bound)"
A14T="$A14P/.worktrees/25-T1"
add_roster_row "$A14P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A14P")/T1.md"
add_workspace "$A14P" w99-T1 "$A14T"
: > "$A14T/old.txt"
drive "$A14P" "$(payload "$A14P" Bash "$(bash_ti "rm -f $A14T/old.txt 2>/dev/null")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A14T")"
expect_eq "A14.1 a writer deleting a literal path in its tree, with 2>/dev/null: allow" "allow" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" Bash "$(bash_ti "rm -f $A14T/../25-T9/old.txt 2>/dev/null")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A14T")"
expect_eq "A14.2 the same delete through .. out of the tree: deny" "deny" "$(behavior "$OUT")"
expect_contains "A14.3 …naming where it lands" "$A14P/.worktrees/25-T9/old.txt" "$(message "$OUT")"
drive "$A14P" "$(payload "$A14P" Write "$(file_ti "$A14T/new.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.4 a Write inside the tree: allow" "allow" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" Write "$(file_ti "$A14T/../25-T9/new.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.5 a Write through .. out of the tree: deny" "deny" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" Write "$(file_ti "$A14P/src/new.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.6 a Write in the main checkout: deny" "deny" "$(behavior "$OUT")"
ln -s "$A14P/src" "$A14T/out-link"
drive "$A14P" "$(payload "$A14P" Write "$(file_ti "$A14T/out-link/new.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.7 a Write through a symlink in the tree that points out: deny" "deny" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" Read "$(jq -n --arg p "$A14P/src/x" '{file_path:$p}')" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.8 a Read anywhere ordinary: allow (a read has no effect)" "allow" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" Read "$(jq -n '{file_path:"~/.ssh/id_ed25519"}')" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.9 a Read of a credential store: deny" "deny" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" Bash "$(bash_ti "ls -la $A14T")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.10 a pure reader: allow" "allow" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" NotebookEdit "$(jq -n --arg p "$A14T/n.ipynb" '{notebook_path:$p, new_source:"x"}')" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.11 a NotebookEdit inside the tree: allow" "allow" "$(behavior "$OUT")"
drive "$A14P" "$(payload "$A14P" MultiEdit "$(jq -n --arg p "$A14P/src/m.txt" '{file_path:$p, edits:[]}')" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A14.12 a MultiEdit in the main checkout: deny" "deny" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A15 a reserved question writes one gate line, once, and offers no file route"

A15P="$(make_project a15 bound)"
A15T="$A15P/.worktrees/25-T1"
add_roster_row "$A15P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A15P")/T1.md"
add_workspace "$A15P" w99-T1 "$A15T"
A15G="$(gate_of "$A15P")"
drive "$A15P" "$(payload "$A15P" Bash "$(bash_ti "git push origin $BRANCH")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A15.1 an agent's git push: deny" "deny" "$(behavior "$OUT")"
expect_contains "A15.2 …as reserved (the log says so)" "|deny-reserved|" "$(tail -1 "$(log_of "$A15P")" 2>/dev/null)"
expect_contains "A15.3 …the message names the human" "human" "$(message "$OUT")"
expect_no_regex "A15.4 …and offers no file route or workaround" '[Ff]ile|[Ss]cript|/|[Ww]orkspace|[Ii]nstead|run it' "$(message "$OUT")"
expect_eq "A15.5 one gate line" "1" "$( [ -f "$A15G" ] && wc -l < "$A15G" | tr -d ' ' || printf 0)"
expect_regex "A15.6 …in the gate/v1 shape" \
  "^gate/v1\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\|session=$SID\|asker=w99-T1\|category=leaves-the-machine\|head=git push origin $BRANCH\$" \
  "$(head -1 "$A15G" 2>/dev/null)"
drive "$A15P" "$(payload "$A15P" Bash "$(bash_ti "git push origin $BRANCH")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A15.7 the same question again: still deny" "deny" "$(behavior "$OUT")"
expect_eq "A15.8 …and no second gate line" "1" "$( [ -f "$A15G" ] && wc -l < "$A15G" | tr -d ' ' || printf 0)"
drive "$A15P" "$(payload "$A15P" Bash "$(bash_ti "git push origin $BRANCH")")"
expect_eq "A15.9 the lead asking the same: a second line, asker=lead" "2|asker=lead" \
  "$( [ -f "$A15G" ] && wc -l < "$A15G" | tr -d ' ' || printf 0)|$(sed -n 2p "$A15G" 2>/dev/null | tr '|' '\n' | /usr/bin/grep '^asker=')"
drive "$A15P" "$(payload "$A15P" Bash "$(bash_ti "touch $A15T/a.txt")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A15.10 control: an ordinary allow writes no gate line" "allow|2" \
  "$(behavior "$OUT")|$(wc -l < "$A15G" | tr -d ' ')"
# A symlinked gate file is refused, never written through; the answer is still a denial.
mv "$A15G" "$SANDBOX/a15-gate-real"
ln -s "$SANDBOX/a15-gate-real" "$A15G"
drive "$A15P" "$(payload "$A15P" Bash "$(bash_ti "gh pr create --fill")" aw99-T1-0974313b7a6b74f2 w99-T1)"
expect_eq "A15.11 symlinked gate file: still deny" "deny" "$(behavior "$OUT")"
expect_eq "A15.12 …and nothing written through the link" "2" "$(wc -l < "$SANDBOX/a15-gate-real" | tr -d ' ')"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A16 a command too large to read is denied, quickly"

A16P="$(make_project a16 bound)"
# Many lines, many pipes and a multibyte character on each line, read under a UTF-8 locale:
# what the log line has to flatten, at a size where flattening the whole text under bash 3.2
# (quadratic in characters) runs past the budget. The hook cuts the head first.
A16CMD="$(awk 'BEGIN { for (i = 0; i < 4000; i++) printf "echo %05d \342\200\224 | cat\n", i }')"
A16PL="$(payload "$A16P" Bash "$(bash_ti "$A16CMD")")"
TIMEFORMAT='%R'
A16T="$( { time drive "$A16P" "$A16PL" LANG=en_US.UTF-8 LC_ALL= LC_CTYPE= >/dev/null 2>&1; } 2>&1 )"
drive "$A16P" "$A16PL" LANG=en_US.UTF-8 LC_ALL= LC_CTYPE=
expect_true "A16.0 fixture: the command is over 64 KB" test "${#A16CMD}" -gt 65536
expect_eq "A16.1 a 70 KB command: deny" "deny" "$(behavior "$OUT")"
expect_contains "A16.2 …as too large to read" "too large to read" "$(message "$OUT")"
expect_eq "A16.3 …in under 2 s (took ${A16T}s)" "yes" \
  "$(awk -v t="$A16T" 'BEGIN { print (t != "" && t + 0 < 2.0) ? "yes" : "no" }')"
drive "$A16P" "$(payload "$A16P" Bash "$(bash_ti "touch $A16P/src/$(printf 'y%.0s' $(seq 1 200)).txt")")"
expect_eq "A16.4 control: a long but readable command is read (allow)" "allow" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A17 a credential store is refused through any path that reaches it"

# The reserved table used to be asked about the path a file tool TYPED, so a Read through a
# symlink into ~/.ssh was allowed (review B3a). The hook now asks about the resolved path as
# well, and either spelling matching is a credentials denial (wave-25 T17).
A17P="$(make_project a17 bound)"
A17T="$A17P/.worktrees/25-T1"
add_roster_row "$A17P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A17P")/T1.md"
add_workspace "$A17P" w99-T1 "$A17T"
mkdir -p "$HOME_FX/.ssh" "$HOME_FX/.kube"
: > "$HOME_FX/.ssh/id_rsa"
: > "$A17P/src/plain.txt"
: > "$A17T/.env"
ln -s "$HOME_FX/.ssh" "$A17T/k"
ln -s "$A17P/src" "$A17T/s"
ln -s "$A17T/.env" "$A17T/settings"
a17() {  # <tool> <path> -> drives the writer's file-tool question
  drive "$A17P" "$(payload "$A17P" "$1" "$(file_ti "$2")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A17T")"
}
a17 Read "$A17T/k/id_rsa"
expect_eq "A17.1 a Read through a link into ~/.ssh: deny" "deny" "$(behavior "$OUT")"
expect_contains "A17.2 …as credentials, on the record" "|deny-reserved|credentials:" "$(tail -1 "$(log_of "$A17P")" 2>/dev/null)"
expect_contains "A17.3 …and the message says credentials" "touches credentials" "$(message "$OUT")"
a17 Read "$A17T/s/plain.txt"
expect_eq "A17.4 control: a Read through a link to an ordinary place: allow" "allow" "$(behavior "$OUT")"
a17 Write "$A17T/k/authorized_keys"
expect_eq "A17.5 a Write through the link into ~/.ssh: deny" "deny" "$(behavior "$OUT")"
expect_contains "A17.6 …as credentials, not as an ordinary outside write" "|deny-reserved|credentials:" "$(tail -1 "$(log_of "$A17P")" 2>/dev/null)"
a17 Edit "$A17T/k/config"
expect_contains "A17.7 an Edit through the link: credentials" "|deny-reserved|credentials:" "$(tail -1 "$(log_of "$A17P")" 2>/dev/null)"
a17 Write "$A17T/settings"
expect_eq "A17.8 a Write to a name in its own tree that links to a .env: deny" "deny" "$(behavior "$OUT")"
expect_contains "A17.9 …as credentials" "|deny-reserved|credentials:" "$(tail -1 "$(log_of "$A17P")" 2>/dev/null)"
a17 Write "$A17T/notes.txt"
expect_eq "A17.10 control: a Write to an ordinary file in its tree: allow" "allow" "$(behavior "$OUT")"
for st in .npmrc .pypirc .git-credentials .kube/config .docker/config.json .gnupg/pubring.kbx .config/gcloud/credentials.db .cargo/credentials.toml .azure/msal_token_cache.json; do
  a17 Read "$HOME_FX/$st"
  expect_eq "A17.store Read ~/$st: deny" "deny" "$(behavior "$OUT")"
  drive "$A17P" "$(payload "$A17P" Bash "$(bash_ti "cat $HOME_FX/$st")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A17T")"
  expect_contains "A17.store 'cat ~/$st': credentials" "|deny-reserved|credentials:" "$(tail -1 "$(log_of "$A17P")" 2>/dev/null)"
done

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A18 a read-only agent's report is a root only inside what the lead holds"

# The roster's deliverable= became the reader's write root with no containment test, so a
# report named under the main checkout's hooks/ or in another writer's tree was writable
# (review S1). It now counts only when it is a file inside the run's record directory or the
# session scratch; otherwise it contributes no root (wave-25 T17).
A18P="$(make_project a18 bound)"
A18S="$(scratch_of "$A18P")"
A18R="$(record_of "$A18P")"
mkdir -p "$A18R/sub"
add_roster_row "$A18P" w99-RA aw99-RA-1 general-purpose "$A18P/src"
add_roster_row "$A18P" w99-RB aw99-RB-1 general-purpose "$A18P/.worktrees/25-T1/r.md"
add_roster_row "$A18P" w99-RC aw99-RC-1 general-purpose "$A18R/sub"
add_roster_row "$A18P" w99-RD aw99-RD-1 general-purpose "$A18R/RD.md"
add_roster_row "$A18P" "" a18unnamed00000001 general-purpose "$A18P/src/u.md"
add_roster_row "$A18P" w99-RE aw99-RE-1 general-purpose "src/rel.md"
a18() {  # <agent id> <path> -> the reader's Write question
  drive "$A18P" "$(payload "$A18P" Write "$(file_ti "$2")" "$1" general-purpose)"
}
a18 aw99-RA-1 "$A18P/src/x.txt"
expect_eq "A18.1 a report naming the main checkout's src: a write under it is denied" "deny" "$(behavior "$OUT")"
expect_contains "A18.2 …and the grant named is the scratch alone" "This read-only agent may write and delete under $A18S." "$(message "$OUT")"
a18 aw99-RB-1 "$A18P/.worktrees/25-T1/r.md"
expect_eq "A18.3 a report in another writer's tree: denied" "deny" "$(behavior "$OUT")"
a18 aw99-RC-1 "$A18R/sub/x.md"
expect_eq "A18.4 a report naming a directory in the record: a write under it is denied" "deny" "$(behavior "$OUT")"
a18 aw99-RD-1 "$A18R/RD.md"
expect_eq "A18.5 control: a report file in the record: allow" "allow" "$(behavior "$OUT")"
a18 a18unnamed00000001 "$A18P/src/u.md"
expect_eq "A18.6 an unnamed agent's report in the main checkout: denied" "deny" "$(behavior "$OUT")"
a18 aw99-RE-1 "$A18P/src/rel.md"
expect_eq "A18.7 a relative report outside the record: denied" "deny" "$(behavior "$OUT")"
a18 aw99-RA-1 "$A18S/notes.md"
expect_eq "A18.8 control: the same reader writing the scratch: allow" "allow" "$(behavior "$OUT")"
# An unbound session has no record directory: a report there contributes no root.
A18U="$(make_project a18u none)"
add_roster_row "$A18U" w99-RU aw99-RU-1 general-purpose "$(record_of "$A18U")/RU.md"
add_roster_row "$A18U" w99-RS aw99-RS-1 general-purpose "$(scratch_of "$A18U")/RS.md"
drive "$A18U" "$(payload "$A18U" Write "$(file_ti "$(record_of "$A18U")/RU.md")" aw99-RU-1 general-purpose)"
expect_eq "A18.9 unbound: a report in the record is denied (no run, no record held)" "deny" "$(behavior "$OUT")"
drive "$A18U" "$(payload "$A18U" Write "$(file_ti "$(scratch_of "$A18U")/RS.md")" aw99-RS-1 general-purpose)"
expect_eq "A18.10 unbound control: a report in the scratch: allow" "allow" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A19 a delete of a workspace root itself is denied; beneath it is allowed"

# `rm -rf <own tree>` and `rm -rf <scratch>` were allowed: containment matched the root
# itself (review N5). A delete must now be strictly beneath a delete root (wave-25 T17).
A19P="$(make_project a19 bound)"
A19T="$A19P/.worktrees/25-T1"
A19S="$(scratch_of "$A19P")"
add_roster_row "$A19P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A19P")/T1.md"
add_workspace "$A19P" w99-T1 "$A19T"
drive "$A19P" "$(payload "$A19P" Bash "$(bash_ti "rm -rf $A19T")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A19T")"
expect_eq "A19.1 a writer deleting its own tree: deny" "deny" "$(behavior "$OUT")"
expect_contains "A19.2 …because it is a root of the workspace" "a root of the workspace" "$(message "$OUT")"
expect_contains "A19.3 …and it is sent to the lead" "ask the lead" "$(message "$OUT")"
drive "$A19P" "$(payload "$A19P" Bash "$(bash_ti "rm -rf $A19T/build")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A19T")"
expect_eq "A19.4 control: a delete beneath its tree: allow" "allow" "$(behavior "$OUT")"
drive "$A19P" "$(payload "$A19P" Bash "$(bash_ti "rm -rf $A19S")")"
expect_eq "A19.5 the lead deleting the session scratch: deny" "deny" "$(behavior "$OUT")"
expect_contains "A19.6 …and it is sent to the human" "report it to the human" "$(message "$OUT")"
drive "$A19P" "$(payload "$A19P" Bash "$(bash_ti "rm -rf $A19S/tmp")")"
expect_eq "A19.7 control: a delete beneath the scratch: allow" "allow" "$(behavior "$OUT")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A20 a command with more targets than the hook reads is denied at once"

# One fork per target ran a 2000-operand rm past the hook's 10 s registration (review S3),
# and a killed hook leaves the stock dialog. The hook resolves in one process, and past a
# fixed number of effects it answers with one `?` and a denial instead of resolving them.
# The number is read from the hook, so the rows follow it.
A20P="$(make_project a20 bound)"
A20T="$A20P/.worktrees/25-T1"
add_roster_row "$A20P" w99-T1 aw99-T1-0974313b7a6b74f2 bionic:senior-implementor "$(record_of "$A20P")/T1.md"
add_workspace "$A20P" w99-T1 "$A20T"
A20_MAX="$(sed -n 's/^PA_EFFECTS_MAX=\([0-9][0-9]*\)$/\1/p' "$HOOK")"
expect_regex "A20.0 the hook states its number of effects (non-empty readback)" '^[0-9]+$' "$A20_MAX"
a20_cmd() { awk -v n="$1" 'BEGIN { s = "rm -f"; for (i = 1; i <= n; i++) s = s " f" i; printf "%s", s }'; }
TIMEFORMAT='%R'
A20PL="$(payload "$A20P" Bash "$(bash_ti "$(a20_cmd "$(( ${A20_MAX:-0} + 1 ))")")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A20T")"
A20_T1="$( { time drive "$A20P" "$A20PL" >/dev/null 2>&1; } 2>&1 )"
drive "$A20P" "$A20PL"
expect_eq "A20.1 one effect past the number: deny" "deny" "$(behavior "$OUT")"
expect_contains "A20.2 …as too many targets to read" "too many targets to read" "$(message "$OUT")"
expect_eq "A20.3 …in under 5 s (took ${A20_T1}s)" "yes" "$(awk -v t="$A20_T1" 'BEGIN { print (t != "" && t + 0 < 5.0) ? "yes" : "no" }')"
A20PL="$(payload "$A20P" Bash "$(bash_ti "$(a20_cmd 2000)")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A20T")"
A20_T2="$( { time drive "$A20P" "$A20PL" >/dev/null 2>&1; } 2>&1 )"
drive "$A20P" "$A20PL"
expect_eq "A20.4 the 2000-operand rm the review timed: deny, in under 5 s (took ${A20_T2}s)" "deny|yes" \
  "$(behavior "$OUT")|$(awk -v t="$A20_T2" 'BEGIN { print (t != "" && t + 0 < 5.0) ? "yes" : "no" }')"
A20PL="$(payload "$A20P" Bash "$(bash_ti "$(a20_cmd "${A20_MAX:-1}")")" aw99-T1-0974313b7a6b74f2 w99-T1 "$A20T")"
A20_T3="$( { time drive "$A20P" "$A20PL" >/dev/null 2>&1; } 2>&1 )"
drive "$A20P" "$A20PL"
echo "§A20: at the number (${A20_MAX:-?} targets) the hook took ${A20_T3}s; one past it ${A20_T1}s; 2000 targets ${A20_T2}s"
expect_eq "A20.5 control: exactly the number of targets, all inside the tree, is read: allow" "allow" "$(behavior "$OUT")"
expect_eq "A20.6 …inside the registration (took ${A20_T3}s)" "yes" "$(awk -v t="$A20_T3" 'BEGIN { print (t != "" && t + 0 < 10.0) ? "yes" : "no" }')"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A21 on and off are one reading: the hook and the doctor agree on one config"

# The ownership table names this suite for on/off across the hook and the doctor (spec §3),
# and each was tested alone (review S5). Here both read the SAME .bionic/config.yaml: the hook
# is silent exactly when the doctor's row reads off. The doctor runs on a tool directory of
# the fixture's (doctor-fleet.test.sh's pattern), so its run time is not this machine's
# package roster.
A21P="$(make_project a21 bound)"
A21BIN="$SANDBOX/a21-bin"
mkdir -p "$A21BIN" "$SANDBOX/a21-claude/plugins" "$SANDBOX/a21-claude/sessions"
: > "$SANDBOX/a21-dot.zshrc"
for t in bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail sort uniq wc cut jq \
         mktemp find xargs shasum uname date touch diff cmp printf true false sleep dirname basename realpath \
         id ps df sysctl vm_stat git strings cksum; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$A21BIN/$t"
done
for t in node pnpm gh rg uv docker aws; do
  printf '#!/bin/sh\ncase "$1" in --version) echo 1.0.0 ;; esac\nexit 0\n' > "$A21BIN/$t"
  chmod +x "$A21BIN/$t"
done
printf '#!/bin/sh\nexit 1\n' > "$A21BIN/claude"
chmod +x "$A21BIN/claude"
a21_doctor() {
  ( cd "$A21P" && HOME="$HOME_FX" PATH="$A21BIN" BIONIC_SHELL_RC="$SANDBOX/a21-dot.zshrc" \
      BIONIC_CLAUDE_HOME="$SANDBOX/a21-claude" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" \
      BIONIC_DOCTOR_PROBE_SECONDS=3 bash "$REPO_ROOT/payload/scripts/doctor.sh" < /dev/null 2>&1 ) \
    | /usr/bin/grep -m1 'permission answers'
}
for a21c in false False unset; do
  case "$a21c" in
    unset) rm -f "$A21P/.bionic/config.yaml"; a21want=on ;;
    false) printf 'permission-answers: false\n' > "$A21P/.bionic/config.yaml"; a21want=off ;;
    *) printf 'permission-answers: %s\n' "$a21c" > "$A21P/.bionic/config.yaml"; a21want=on ;;
  esac
  drive "$A21P" "$(payload "$A21P" Bash "$(bash_ti "$INCIDENT")")"
  a21hook=unknown
  if [ "$RC" = 0 ] && [ -z "$OUT" ]; then a21hook=off
  elif [ "$(behavior "$OUT")" = deny ]; then a21hook=on
  fi
  A21ROW="$(a21_doctor)"
  a21doc=unknown
  case "$A21ROW" in
    *"permission answers"*" off "*) a21doc=off ;;
    *"permission answers"*" on "*) a21doc=on ;;
  esac
  expect_nonempty "A21.$a21c.0 the doctor printed its permission-answers row" "$A21ROW"
  expect_eq "A21.$a21c.1 [$a21c] the hook and the doctor agree, and say $a21want" "$a21want|$a21want" "$a21hook|$a21doc"
done

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A8 no decision object anywhere in the suite carries interrupt"

# The extractor is proved on a planted object first, so an empty answer below is real.
keys_of() { jq -r '[.. | objects | keys[]] | unique | .[]' 2>/dev/null; }
expect_contains "A8.0 the key extractor finds a planted interrupt" "interrupt" \
  "$(printf '%s' '{"hookSpecificOutput":{"decision":{"behavior":"deny","interrupt":true}}}' | keys_of)"
A8_KEYS="$(keys_of < "$ALL_OUT")"
expect_contains "A8.1 the suite's decisions were read (behavior is among their keys)" "behavior" "$A8_KEYS"
expect_eq "A8.2 the suite collected many decisions" "yes" \
  "$([ "$(jq -s 'length' < "$ALL_OUT" 2>/dev/null || echo 0)" -ge 60 ] && echo yes || echo no)"
expect_absent "A8.3 no decision carries interrupt" "interrupt" "$A8_KEYS"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§A9 no decision changes a trust setting, even when the payload offers one"

A9P="$(make_project a9 bound)"
A9PL="$(payload "$A9P" Bash "$(bash_ti "touch $A9P/src/a.txt")" \
  | jq '.permission_suggestions = [{"type":"setMode","mode":"bypassPermissions","destination":"session"},
                                   {"type":"addRules","rules":[{"toolName":"Bash"}],"behavior":"allow","destination":"localSettings"}]')"
drive "$A9P" "$A9PL"
expect_eq "A9.1 the payload carrying suggestions is still answered (allow)" "allow" "$(behavior "$OUT")"
expect_absent "A9.2 …and the suggestions are not echoed" "setMode" "$OUT"
expect_contains "A9.3 the key extractor finds a planted updatedPermissions" "updatedPermissions" \
  "$(printf '%s' '{"hookSpecificOutput":{"decision":{"behavior":"allow","updatedPermissions":[]}}}' | keys_of)"
A9_KEYS="$(keys_of < "$ALL_OUT")"
expect_contains "A9.4 the suite's decisions were read" "hookEventName" "$A9_KEYS"
expect_absent "A9.5 no decision across the suite carries updatedPermissions" "updatedPermissions" "$A9_KEYS"
expect_absent "A9.6 no decision across the suite carries updatedInput" "updatedInput" "$A9_KEYS"
expect_eq "A9.7 every decision is allow or deny, with a message only on a deny" "0" \
  "$(jq -c 'select(.hookSpecificOutput.decision.behavior as $b | ($b != "allow" and $b != "deny")
         or ($b == "allow" and (.hookSpecificOutput.decision | has("message")))
         or ($b == "deny" and ((.hookSpecificOutput.decision.message // "") == "")))' < "$ALL_OUT" 2>/dev/null | wc -l | tr -d ' ')"

finish
