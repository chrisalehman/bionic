#!/bin/bash
# tests/asks.test.sh — THE RUN'S ONE REGISTER OF ASKS (payload/scripts/lib/owed.sh).
#
# WHAT IT HOLDS. An ask is something the person owes a run, and it belongs to the run, not to the session that
# raised it: every session acting for the run writes it to `<docs>/record/<run>/asks.state`, every reader reads it
# there, and answering it once closes it for every session. An ask raised with no run stays in its session's file.
# The miss this suite was opened on: the close-out preflight refused a merge on a failing review and opened the
# waiver under a stand-in session (`closeout-preflight-<pid>`) whose file nothing that reads the run ever read, so
# the run's page said nothing was owed while the merge waited on a waiver.
#
# §ONE-REGISTER  a close-out preflight's `waive:` reaches the plan's register; a bound session reads it as its own;
#                closed in one session, closed for all; an ask with no run, or under a name that is no plan, stays
#                with its session
#
# FIXTURE FIDELITY. The project is close-out's own (tests/close-out.prelude.sh, read by name): a git project at
# Step 8 whose newest structure reading fails, as close-out-1's E2E fixture plants it, and the preflight is the one
# `close-out.sh check` runs. The register is read through `owed_list_plan`, the reader the run's pages read.
#
# ANTI-VACUITY. Each absence is read through an extractor that, in the same fixture, returns the item it should:
# the list of session files holds the unbound session's file, and the register's open list holds a second ask.
#
# Usage: bash tests/asks.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

command -v jq >/dev/null 2>&1 || { echo "asks: jq absent — suite cannot run"; exit 1; }

AS_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"

# The close-out fixture's builders, read by name out of tests/close-out.prelude.sh, so this suite holds no second
# copy of the fixture and a builder that changes there changes here.
CO_TESTS="$(dirname "$0")/close-out.prelude.sh"
as_import_fn() {  # <name> -> the function, defined here, read out of close-out.prelude.sh
  local body
  body="$(awk -v n="$1" 'index($0, n "() {") == 1 { p = 1 } p { print } p && /^}/ { exit }' "$CO_TESTS")"
  if [ -z "$body" ]; then echo "as_import_fn: no $1 in $CO_TESTS" >&2; return 1; fi
  eval "$body"
}
REPO_ROOT="$BIONIC_SCRIPTS_DIR"
SCRIPT="$REPO_ROOT/payload/scripts/close-out.sh"
PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
UNITS_LIB="$REPO_ROOT/payload/scripts/lib/units.sh"
SANDBOX="$(cd "$(mktemp -d "$TMPROOT/co.XXXXXX")" && pwd -P)"
SB_HOME="$SANDBOX/home"; mkdir -p "$SB_HOME/.claude"
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# as_owed <root> <sid> <function> [args...] -> what owed.sh answers for that session, with run.sh and binding.sh
# loaded as a hook has them.
as_owed() {
  local root="$1" sid="$2"; shift 2
  OWED_ROOT="$root" OWED_SID="$sid" bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && shift && "$@"' \
    _ "$AS_LIB" "$@" 2>/dev/null
}
# as_register <root> <plan> -> the keys of the open asks the plan's register holds, one line, space-separated.
as_register() {
  bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && owed_list_plan "$2" "$3"' _ "$AS_LIB" "$2" "$1" 2>/dev/null \
    | cut -f1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
as_tmp_owed() { ( cd "$1/.bionic/tmp" && ls owed-*.state 2>/dev/null ) | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }

# ============================================================
section "§ONE-REGISTER: a close-out preflight's waiver is the run's ask; closed in one session, closed for all"
# ============================================================
# fails-when: the waiver the preflight opens is missing from the plan's register, or stays open for the run after
# a session bound to it answers.
AS_MISSING=""
for _f in in_fixture fixture_git fixture_plan_text fixture_epic_text plant_facts mk_fixture advance_to run_close_as; do
  as_import_fn "$_f" || AS_MISSING="$AS_MISSING $_f"
done
expect_eq "ONE-0 close-out.prelude.sh's fixture builders were all read out of it" "" "$AS_MISSING"

AS_SIDA="as-closeout-session-a1a1a1a1"   # runs close-out, bound to nothing, as the orchestrator's helper call does
AS_SIDB="as-bound-session-b2b2b2b2"      # bound to the run: answers the ask
AS_SIDC="as-bound-session-c3c3c3c3"      # bound to the run: reads it
AS_SIDD="as-free-session-d4d4d4d4"       # no run at all
AS_SIDE="as-copy-session-e5e5e5e5"       # bound to a name that is no plan: a plan verb's scratch copy

PA="$(mk_fixture as-one)"; advance_to "$PA" 8
PA_PLAN="$PA/$PLAN_REL"
PA_REG="$PA/.bionic/docs/record/wave-01-fixture/asks.state"
bash -c '. "$1/proof.sh" && proof_add_line "$2" "$(proof_line review "$3" 2026-10-04T13:00:00Z record/wave-01-fixture/structure-fail.md structure w-read fail piece)"' \
  _ "$AS_LIB" "$PA_PLAN" "$(fixture_git "$PA" rev-parse wave/01-fixture)" > "$PA_PLAN.n" && mv "$PA_PLAN.n" "$PA_PLAN"
rm -f "$PA"/.bionic/tmp/owed-*.state

# An ask with no run open stays with its session.
as_owed "$PA" "$AS_SIDD" owed_open gate:free "gate act: free" "poker: GATE free" >/dev/null

run_close_as "$AS_SIDA" "$PA" check
expect_contains "ONE-1 precondition: check names the failing structure reading the merge would refuse on" \
  "$(printf 'review\tstructure\tbionic:critic\tpiece\tfailing')" "$CO_OUT"
expect_eq "ONE-2 the preflight's waiver is an open ask in the plan's register (owed_list_plan)" \
  "waive:structure" "$(as_register "$PA" "$PA_PLAN")"
expect_contains "ONE-2b …filed at record/<run>/asks.state, carrying the refusal the commit gate printed" \
  "|key=waive:structure|state=open|" "$(cat "$PA_REG" 2>/dev/null)"
expect_eq "ONE-3 only the run-less session has a session file: no stand-in close-out session holds an ask" \
  "owed-$AS_SIDD.state" "$(as_tmp_owed "$PA")"
expect_contains "ONE-3b …and that file holds the run-less ask" "|key=gate:free|state=open|" \
  "$(cat "$PA/.bionic/tmp/owed-$AS_SIDD.state" 2>/dev/null)"

bound_marker "$PA" "$AS_SIDB" "$PA_PLAN"
bound_marker "$PA" "$AS_SIDC" "$PA_PLAN"
expect_eq "ONE-4 a session bound to the run reads the preflight's waiver as its own open ask (owed_list)" \
  "waive:structure" "$(as_owed "$PA" "$AS_SIDC" owed_list | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
as_owed "$PA" "$AS_SIDB" owed_open approve:release "approval: release" "poker: approve the release" >/dev/null
expect_eq "ONE-5 precondition: a second session's ask joins the same register" \
  "approve:release waive:structure" "$(as_register "$PA" "$PA_PLAN")"
as_owed "$PA" "$AS_SIDB" owed_close waive:structure waive >/dev/null
expect_eq "ONE-6 answered in one session, the waiver is closed for the run; the other ask stays open" \
  "approve:release" "$(as_register "$PA" "$PA_PLAN")"
expect_eq "ONE-6b …and for every session bound to it" \
  "approve:release" "$(as_owed "$PA" "$AS_SIDC" owed_list | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
expect_contains "ONE-6c …the register records who closed it" "|key=waive:structure|state=closed|by=waive|" \
  "$(cat "$PA_REG" 2>/dev/null)"
as_owed "$PA" "$AS_SIDC" owed_close approve:release approve >/dev/null
expect_eq "ONE-6d …and a third session's answer closes the second" "" "$(as_register "$PA" "$PA_PLAN")"

# A scratch copy's name ends past `.plan.md`: it names no run, so its session keeps its own file and no record
# directory is made for the copy.
AS_COPY="$PA/.bionic/docs/plans/epic-fx/.wave-01-fixture.plan.md.preflight.4242"
cp "$PA_PLAN" "$AS_COPY"
bound_marker "$PA" "$AS_SIDE" "$AS_COPY"
as_owed "$PA" "$AS_SIDE" owed_open gate:copy "gate act: copy" "poker: GATE copy" >/dev/null
expect_contains "ONE-7 a session bound to a name that is no plan keeps its ask in its own file" \
  "|key=gate:copy|state=open|" "$(cat "$PA/.bionic/tmp/owed-$AS_SIDE.state" 2>/dev/null)"
expect_eq "ONE-7b …and the record holds the run's directory alone" "generic-evidence.md wave-01-fixture" \
  "$(ls -A "$PA/.bionic/docs/record" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
rm -f "$AS_COPY"

finish
