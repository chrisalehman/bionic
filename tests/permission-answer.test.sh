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
# T1 interface shape, written by hand because the writer needs a real `git worktree add`.
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
           "$dir/.worktrees/25-T1" "$dir/.worktrees/25-T9" "$SANDBOX/$name-scratch"
  git -C "$dir" init -q 2>/dev/null
  git -C "$dir" checkout -q -b "$BRANCH" 2>/dev/null
  git -C "$dir" -c user.email=fx@example.invalid -c user.name=fx commit -q --allow-empty -m init 2>/dev/null
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
# A writer whose recorded tree is the main root itself.
add_roster_row "$A13P" w99-W aw99-W-1 bionic:senior-implementor "$(record_of "$A13P")/W.md"
add_workspace "$A13P" w99-W "$A13P"
drive "$A13P" "$(payload "$A13P" Bash "$(bash_ti "rm -f $A13P/src/y.txt")" aw99-W-1 w99-W)"
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
