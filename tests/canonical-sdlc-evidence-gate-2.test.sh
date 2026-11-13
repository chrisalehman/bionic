#!/bin/bash
# Tests for canonical-sdlc-evidence-gate.sh — shard 2 of 2 (Section 29 onward).
#
# The evidence-gate suite was sharded in two at wave-30 T3 (D8b) so a landing that touches the
# gate proves in minutes. The runners, helpers and shared plan fixtures live in
# tests/canonical-sdlc-evidence-gate.prelude.sh, sourced by both shards; the strategy note
# there applies to each. Usage: bash tests/canonical-sdlc-evidence-gate-2.test.sh
#
# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/canonical-sdlc-evidence-gate.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_evidence_gate` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# THE FLOOR A RUN PAST STEP 6 CARRIES (wave-35 T31; D20, A-orch-50): shard 1's eg_floor, the same helper,
# since the prelude both shards source is outside the row that added the arm.
eg_floor() {  # <plan content> -> the content with the readings and one floor proof line
  eg_readings "$1" | EG_H="$EG_HEAD" awk '{ print }
    !done && /^[[:space:]]*current[[:space:]]*:[[:space:]]*[7-9][ab]?[[:space:]]*$/ {
      printf "proved: kind=regression head=%s at=2026-10-12T00:00:00Z evidence=record/floor.log\n", ENVIRON["EG_H"]; done = 1 }'
}

# ============================================================
# Section 29: Step 9's delivery, and the trio a named target owes
# ============================================================
#
# Every run's Step 9 owes its delivery; a run whose frontmatter names a live deploy_target owes deployed, verified and
# monitored too, each given to its step by close-out. At 15 they are fields of the run's step-9 event.
# FIXTURE FIDELITY: eg_page's run at 15 at Step 9, its readings and floor proved, the step event as close-out writes it.
# fails-when: a Step 9 with no delivery admitted (29b), or a named target's missing trio admitted (29d).
section "Section 29: Step 9's delivery, and the trio a named target owes"

s29_home() {  # <deploy_target> -> S29_H, a run at 15 at Step 9 whose step event holds no delivery
  local q p; S29_H=$(make_home); eg_head_repo "$S29_H"
  p=$(eg_page "$S29_H" 9 "run/v1|ev=proof|kind=regression|head=$EG_HEAD|evidence=record/floor.log|at=2026-10-04T01:00:00Z" \
    $(for q in evidence adversarial structure; do printf 'run/v1|ev=proof|kind=review|head=%s|question=%s|result=pass|scope=piece|reader=w-read|evidence=record/generic-evidence.md|at=2026-10-04T01:00:01Z\n' "$EG_HEAD" "$q"; done) \
    "run/v1|ev=proof|ac=AC-1.1|evidence=record/generic-evidence.md|at=2026-10-04T01:00:02Z")
  awk -v t="$1" '/^deploy_target: /{ $0 = "deploy_target: " t } { print }' "$p" > "$p.t" && mv "$p.t" "$p"
}
s29_home none
expect_block "29b Step 9 without its delivery → block naming it" "$S29_H" 'git commit -m "x"' "Step 9's delivery"
s29_home local-harness
expect_block "29d Step 9, deploy_target named, the trio missing → block naming it" "$S29_H" 'git commit -m "x"' "deployed"

# ============================================================
# Section 31: a refusal on a call that also writes the plan (B-6)
# ============================================================
#
# The gate reads the plan off disk when the CALL starts. So a single Bash call
# that edits the plan and then commits is judged against the PRE-EDIT plan: the
# fix the agent just wrote is invisible, and the refusal reads as though it had
# never been made. The observed reflex is to re-run the same combined call. When
# the refused command's text names the plan, the refusal now says so.

section "Section 31: refusal names the edit-then-commit split"

# s31_home -> S31_H, a sandbox whose run is at Step 6, readings and floor proved, the first criterion proved and the
#   second pending; P31, its page.
s31_home() {
  local q; S31_H=$(make_home); eg_head_repo "$S31_H"
  P31=$(eg_page "$S31_H" 6 "run/v1|ev=proof|kind=regression|head=$EG_HEAD|evidence=record/floor.log|at=2026-10-04T01:00:00Z" \
    $(for q in evidence adversarial structure; do printf 'run/v1|ev=proof|kind=review|head=%s|question=%s|result=pass|scope=piece|reader=w-read|evidence=record/generic-evidence.md|at=2026-10-04T01:01:00Z\n' "$EG_HEAD" "$q"; done) \
    "run/v1|ev=proof|ac=AC-1.1|evidence=record/generic-evidence.md|at=2026-10-04T01:02:00Z")
  awk '{ print } /^\| REQ-1 \| fixture \| AC-1\.1 /{ print "| REQ-1 | fixture | AC-2 | hermetic | `tests/b.test.sh` | the second is wrong |" }' "$P31" > "$P31.t" && mv "$P31.t" "$P31"
}
# 31a — a python3 heredoc writing the plan's absolute path, then a commit,
# refused by the matrix arm → the refusal carries the split line.
s31_home; h31a="$S31_H"; p31a="$P31"
cmd31a=$(printf 'python3 - <<%s\nopen("%s","a").write("\\nAC-2:\\n  tier-run: x\\n")\nEOF\ngit commit -m "discharge AC-2"' "'EOF'" "$p31a")

# 31a — the same refusal still names the row it refused (the note is an extra
# line, not a replacement).
expect_block "31a the split line does not displace the original refusal" "$h31a" "$cmd31a" "AC-2"

# 31b — the project-relative spelling of the same path (what an agent actually
# types) is matched too.
s31_home; h31b="$S31_H"

# 31c — a refused commit that does NOT name the plan gets the ordinary 3-line
# refusal and no split line. Same fixture and same extractor as 31a, so this
# pins the note's scope rather than asserting an empty world.
run_hook "$h31a" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && grep -q "AC-2" <<<"$HOOK_VSTDERR" \
   && ! grep -q "also writes the plan" <<<"$HOOK_STDERR"; then
  ok "31c plain commit refusal carries no split line"
else
  no "31c plain commit refusal carries no split line" "expected a block naming AC-2 with NO split line; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# 31d — the note rides on a refusal, never on its own: a command that names the
# plan but has nothing to refuse is still allowed silently.
s31_home; h31d="$S31_H"; p31d="$P31"
printf 'run/v1|ev=proof|ac=AC-2|evidence=record/generic-evidence.md|at=2026-10-04T01:03:00Z\n' >> "$(plan_fixture_log "$p31d")"
expect_allow "31d naming the plan in an otherwise-clean commit → allow, silent" "$h31d" "python3 -c \"open('$p31d','a')\" && git commit -m \"x\""

# ============================================================
# Section 32b: the auditor and the confirmation, read from the run
# ============================================================
#
# A criterion's auditor cell is the evidence review standing at the working branch's head, CONFIRMED on a pass and
# REFUTED on a fail, empty with none; its confirmation is the approval naming it. At double rigor the auditor owes
# a verdict from Step 6 and a ruling from Step 8; at single the column is unread; with no rigor the strict reading
# holds. A T4 criterion is ruled by its approval unless the auditor's finding stands.
# FIXTURE FIDELITY: eg_page's run at 15, its branch at the fixture head, AC-1.1 discharged by a proof after the rest.
# fails-when: matrix_auditor_required reads single as required (m32-single), or an unknown rigor as not (m32-norigor);
# matrix_row_owes admits an empty cell at 6 (m32-6v) or a REFUTED one at 8 (m32-8r); the finding-stands arm admits a
# confirmed T4 row the auditor refuted (m32-t4r).

section "Section 32b: the auditor and the confirmation, read from the run"

m32_home() {  # <step> <rigor, or - for none> <eval type> <evidence review: pass|fail|none, waived unless pass> [<log line>...]
  local q; M32_H=$(make_home); eg_head_repo "$M32_H"; git -C "$M32_H" branch wave/01-fixture 2>/dev/null
  P32=$(eg_page "$M32_H" "$1" "run/v1|ev=proof|kind=regression|head=$EG_HEAD|evidence=record/floor.log|at=2026-10-04T01:00:00Z" \
    $(for q in adversarial structure; do printf 'run/v1|ev=proof|kind=review|head=%s|question=%s|result=pass|scope=piece|reader=w-read|evidence=record/generic-evidence.md|at=2026-10-04T01:00:01Z\n' "$EG_HEAD" "$q"; done))
  case "$2" in -) awk '!/^rigor: /' "$P32" ;; *) awk -v r="$2" '/^rigor: /{ $0 = "rigor: " r } { print }' "$P32" ;; esac \
    | awk -v t="$3" '{ sub(/\| AC-1\.1 \| hermetic \|/, "| AC-1.1 | " t " |"); print }' > "$P32.t" && mv "$P32.t" "$P32"
  case "$4" in
    pass|fail) printf 'run/v1|ev=proof|kind=review|head=%s|question=evidence|result=%s|scope=piece|reader=w-read|evidence=record/generic-evidence.md|at=2026-10-04T01:00:03Z\n' "$EG_HEAD" "$4" >> "$(plan_fixture_log "$P32")" ;;
  esac
  [ "$4" = pass ] || printf 'run/v1|ev=waiver|question=evidence|head=%s|by=Dana|said=ship it|at=2026-10-04T01:00:04Z\n' "$EG_HEAD" >> "$(plan_fixture_log "$P32")"
  [ "$1" != 8 ] || printf 'run/v1|ev=step|n=8|cleanup=n/a|at=2026-10-04T01:00:05Z\n' >> "$(plan_fixture_log "$P32")"
  shift 4; [ "$#" -eq 0 ] || printf '%s\n' "$@" >> "$(plan_fixture_log "$P32")"
  printf 'run/v1|ev=proof|ac=AC-1.1|evidence=record/generic-evidence.md|at=2026-10-04T01:00:09Z\n' >> "$(plan_fixture_log "$P32")"
}
m32_ap='run/v1|ev=approval|key=AC-1.1|by=Dana Fixture|said=I watched it hold|at=2026-10-04T01:00:06Z'
m32_home 6 double hermetic none
expect_block "m32-6v double rigor at 6, the evidence question waived with no review: the criterion owes the auditor's verdict" "$M32_H" 'git commit -m "x"' "get the auditor's verdict"
m32_home 6 double hermetic fail
expect_allow "m32-6r …and a REFUTED verdict, its review waived, is a verdict at 6: admitted" "$M32_H" 'git commit -m "x"'
m32_home 8 double hermetic fail
expect_block "m32-8r at 8 the same REFUTED row owes a ruling, naming the verdict" "$M32_H" 'git commit -m "x"' "verdict is 'REFUTED', not CONFIRMED"
m32_home 8 double hermetic pass
expect_allow "m32-8c at 8 a CONFIRMED row is ruled: admitted" "$M32_H" 'git commit -m "x"'
m32_home 8 single hermetic fail
expect_allow "m32-single at single rigor the column is unread: the REFUTED row is admitted at 8" "$M32_H" 'git commit -m "x"'
m32_home 8 - hermetic fail
expect_block "m32-norigor with no rigor the strict reading holds: the REFUTED row is refused at 8" "$M32_H" 'git commit -m "x"' "not CONFIRMED"
m32_home 8 double human pass "$m32_ap"
expect_allow "m32-t4c a T4 row CONFIRMED and confirmed by its approval is admitted at 8" "$M32_H" 'git commit -m "x"'
m32_home 8 double human pass
expect_block "m32-t4n …and with no approval naming it, owes its confirmation" "$M32_H" 'git commit -m "x"' "no user-confirmed evidence"
m32_home 6 reviewed hermetic pass
expect_block "m32-enum a rigor that names no level is refused on its rigor, ahead of the matrix" "$M32_H" 'git commit -m "x"' "rigor is not single or double"
m32_home 6 double hermetic pass
printf 'run/v1|ev=proof|ac=AC-1.1|evidence=TBD|at=2026-10-04T01:00:10Z\n' >> "$(plan_fixture_log "$P32")"
expect_block "m32-ph a criterion whose proof names a placeholder for its evidence is refused as one" "$M32_H" 'git commit -m "x"' "AC-1.1 has placeholder evidence evidence"
m32_home 8 double human fail "$m32_ap"
expect_block "m32-t4r a T4 row its approval confirms is refused while the auditor's REFUTED stands" "$M32_H" 'git commit -m "x"' "finding on AC-1.1 stands"

# ============================================================
# Section 34: the session never invoked the skill (AC-6)
# ============================================================
#
# THE PAIRED WORLD for every section above. Chris, 2026-09-03: "all guardrails imposed
# by bionic should only apply when exercising bionic. Nothing should apply until bionic
# is triggered." The trigger is the canonical-sdlc skill and the record of it is
# `.bionic/tmp/engaged-<sid>.state` under the project root; every fixture above carries
# one because every fixture above describes a run somebody started. Take it away and this
# gate is not quieter, it is absent: exit 0, nothing on stdout, nothing on stderr.
#
# EACH ARM IS A COMMIT THIS GATE REFUSES TWO LINES LATER, on the identical fixture with
# the marker restored — the control is what stops the whole section passing on a gate
# that had simply stopped working.
#
# THE ORDERING CONTRACT IS UNCHANGED BY THIS. Plan hygiene still sits above the run
# predicate, so an ENGAGED session committing against a malformed plan is still refused
# whether or not a run is open (34b's control). What the guard adds is prior to both
# questions, not a fourth clause inside either.

section "Section 34: no engagement marker — the gate is not there at all"

# Captures stdout as well as stderr and the exit code: "silent" here means all three.
run_hook_full() {  # <home> <command> -> S34_EXIT / S34_OUT / S34_ERR
  local home_dir="$1" command="$2" input tmp_err tmp_out
  input=$(jq -n --arg c "$command" --arg cwd "$home_dir" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp); tmp_out=$(mktemp)
  eg_autobind "$home_dir"
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$EG_SID" \
       bash "$HOOK" <<< "$input" >"$tmp_out" 2>"$tmp_err"; then
    S34_EXIT=0
  else
    S34_EXIT=$?
  fi
  S34_OUT=$(cat "$tmp_out"); S34_ERR=$(cat "$tmp_err")
  rm -f "$tmp_err" "$tmp_out"
}

expect_silent() {  # <label> — asserts on the last run_hook_full
  if [ "$S34_EXIT" -eq 0 ] && [ -z "$S34_OUT" ] && [ -z "$S34_ERR" ]; then
    ok "$1"
  else
    no "$1" "expected exit 0 and total silence; got exit=$S34_EXIT stdout='$S34_OUT' stderr='$S34_ERR'"
  fi
}

expect_refused() {  # <label> — the control: the SAME fixture, marker restored
  expect_eq "$1" 2 "$S34_EXIT"
}

# --- 34a: an open run whose current step has no evidence — the gate's core refusal ---
h34a=$(make_home)
eg_page "$h34a" 5 > /dev/null
unengage "$h34a"
run_hook_full "$h34a" 'git commit -m "x"'
expect_silent "34a a Step 5 with no regression proof passes an unengaged session"
engage "$h34a"
run_hook_full "$h34a" 'git commit -m "x"'
expect_refused "34a control: the same commit, marker restored, is REFUSED"

# --- 34b: PLAN HYGIENE, the half that sits ABOVE the run predicate ---
# A run whose step cannot be read is refused whether or not a run is open, because a
# plan that lies is a defect in every state. That refusal is owed to an ENGAGED session
# and to nobody else.
h34b=$(make_home)
eg_page "$h34b" 5 'run/v1|ev=step|n=banana|at=2026-10-04T01:00:00Z' > /dev/null
unengage "$h34b"
run_hook_full "$h34b" 'git commit -m "x"'
expect_silent "34b a step that is not a number passes an unengaged session"
engage "$h34b"
run_hook_full "$h34b" 'git commit -m "x"'
expect_refused "34b control: plan hygiene still refuses the ENGAGED session"

# --- 34c: the misplacement sweep, which needs no open run either ---
h34c=$(make_home)
p34c=$(mktemp -d); cleanup_dirs+=("$p34c")
mkdir -p "$p34c/docs/bionic/plans/epic-01-demo"
plan_fixture --current 3 "$p34c/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" task > /dev/null
run_hook_with_project "$h34c" "$p34c" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  ok "34c the misplacement sweep does not fire in an unengaged session"
else
  no "34c the misplacement sweep does not fire in an unengaged session" "expected allow; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi
engage "$p34c"
run_hook_with_project "$h34c" "$p34c" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && grep -q "misplaced" <<<"$HOOK_VSTDERR"; then
  ok "34c control: the same tree, marker planted, is REFUSED as misplaced"
else
  no "34c control: the same tree, marker planted, is REFUSED as misplaced" "expected block; exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
fi

# --- 34d: the shapes that are NOT engagement, on a fixture that otherwise refuses ---
h34d=$(make_home)
eg_page "$h34d" 5 > /dev/null

# A SYMLINK at the marker path is refused before it is followed (lib/run.sh), so a link
# into an engaged tree cannot open this gate from outside it.
unengage "$h34d"
ln -s "$h34a/.bionic/tmp/engaged-$EG_SID.state" "$h34d/.bionic/tmp/engaged-$EG_SID.state"
run_hook_full "$h34d" 'git commit -m "x"'
expect_silent "34d a SYMLINK at the marker path is not engagement"
rm -f "$h34d/.bionic/tmp/engaged-$EG_SID.state"

# ANOTHER SESSION'S marker is not this session's: the path interpolates the key.
: > "$h34d/.bionic/tmp/engaged-99999999-8888-7777-6666-555555555555.state"
run_hook_full "$h34d" 'git commit -m "x"'
expect_silent "34d another session's marker is not engagement"

# A DIRECTORY at the marker path is not a regular file.
mkdir -p "$h34d/.bionic/tmp/engaged-$EG_SID.state"
run_hook_full "$h34d" 'git commit -m "x"'
expect_silent "34d a DIRECTORY at the marker path is not engagement"
rmdir "$h34d/.bionic/tmp/engaged-$EG_SID.state"

# ============================================================
# Section 35: THE SESSION'S OWN RUN (wave-session-bound-run, AC-1/AC-3/AC-6)
# ============================================================
#
# Until 2026-09-04 this gate answered "which run am I in" by scanning the project root
# for the newest plan carrying `## SDLC State`. Two engaged sessions in one repository
# therefore shared one run identity: a commit from EITHER was measured against whichever
# plan was newest, so the second session's own evidence was never the evidence checked.
# The resolution is session-keyed now — lib/run.sh's `session_run` reads the `plan=`
# field hooks/engage.sh has written into `engaged-<sid>.state` since 1.4.1 and nothing
# read — and both of this hook's resolution sites take its verdict.
#
# EVERY FIXTURE HERE IS ONE ROOT WITH TWO OPEN PLANS, and that is the point: it is the
# only shape in which the old rule and the new one disagree. A one-plan root cannot tell
# them apart, so a section built on one would pass under either and prove nothing.
#
# THE TWO DIRECTIONS ARE BOTH DRIVEN (35a and 35b). "The bound session is gated on its
# own plan" is only half an assertion if the bound plan is also the newest one — the old
# rule agrees there. 35b swaps which plan carries the evidence, so the bound session
# blocks on the OLDER plan while the newest one is clean, which the old rule cannot do.

# ============================================================
section "§ORDER-VERB, §WHOLE-RUN, §FIX-ROW, §APPROVED-HEAD — build, regression, review, release, approval, merge, through the verbs"
# ============================================================
# FIXTURE FIDELITY: one real repository; tests/run.sh is a fixture runner printing the real runner's verdict lines (a suite
# is green unless tests/red names it); the plan is bound to this session and hooks/session-poker.sh runs as it. The proofs
# and landing lines are written in their writers' shapes; the judge reads text whatever wrote it. fails-when: a regression
# runs beside an open build row or twice at one head, a fixed red asks a second whole run, or current 8 passes at a head the user did not approve.
OD_SID="6e7f8091-2a3b-4c4d-9e0f-1a2b3c4d5e6f"; OD_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
OD_ROOT="$(mktemp -d)"; cleanup_dirs+=("$OD_ROOT"); OD="$(cd "$OD_ROOT" && pwd -P)/repo"
OD_RL="record/wave-01-fixture"; OD_REC="$OD/.bionic/docs/$OD_RL"; OD_PLAN="$OD/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
mkdir -p "$OD/.bionic/tmp" "$OD_REC" "${OD_PLAN%/*}" "$OD/.bionic/docs/specs/epic-99-fixture" "$OD/tests" "$OD/lib"
od_git() { git -C "$OD" -c user.email=dana@fixture.test "$@"; }
od_git init -q; od_git config user.name "Dana Fixture"; od_git checkout -q -b wave/01-fixture
printf '.bionic/\n' > "$OD/.gitignore"; printf 'one\n' > "$OD/lib/b.sh"; : > "$OD/tests/red"
printf 'true\n' > "$OD/tests/a.test.sh"; printf 'true\n' > "$OD/tests/b.test.sh"
cat > "$OD/tests/run.sh" <<'OD_RUN'
#!/bin/bash
cd "$(dirname "$0")" || exit 1
p=0; f=0; bad=""; printf 'Gating suites: a.test.sh b.test.sh\n'
for s in a.test.sh b.test.sh; do
  if grep -qx "$s" red; then printf '  %s  ✗ FAIL\n' "$s"; f=$((f + 1)); bad="$bad    - $s"$'\n'; else printf '  %s  ✓ PASS\n' "$s"; p=$((p + 1)); fi
done
printf 'Gating: %s passed, %s failed\n' "$p" "$f"; [ "$f" -eq 0 ] && exit 0; printf 'Failed:\n%s' "$bad"; exit 1
OD_RUN
od_git add -A; od_git commit -qm base; OD_B="$(od_git rev-parse HEAD)"
: > "$OD/.bionic/tmp/engaged-$OD_SID.state"
printf '# r\n' > "$OD/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
printf '# s\n' > "$OD/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
for od_f in dispatch audit review docs generic-evidence; do printf 'fixture evidence\n' > "$OD_REC/$od_f.md"; done
od_row() { printf '| %s | %s | %s | %s | %s | %s | — | 30 | REQ-1 | %s | — | — | %s |\n' "$1" "$2" "$3" "$4" "$5" "$8" "$6" "$7"; }  # id step kind task agent Files status deps
od_plan() {  # <current> <log lines> <row>... -> OD_PLAN at 15, bound to this session: the fixture's page and events, the
  # run's own runs and verdicts kept, then each line given. The lines planted are the run's whole proof state.
  local cur="$1" sd="$2" keep=""; shift 2
  # A log holding only the lines dropped here leaves nothing to keep, and grep's exit 1 must not end the suite.
  [ ! -f "$OD_REC/run.log" ] || keep="$(/usr/bin/grep -vE '^run/v1\|ev=(step|approval|proof|dispatch|tree|published)\|' "$OD_REC/run.log" || :)"
  plan_fixture --current "$cur" "$OD_PLAN" wave "$@" > /dev/null
  awk -v b="$OD_B" '/^rigor: single$/ { $0 = "rigor: double" } /^use_worktree: true$/ { $0 = "use_worktree: false" }
    /^base-sha: / { print "base-sha: " b; print "integration-branch: main"; print "adrs: none — no decision this run"; next } { print }' "$OD_PLAN" > "$OD_PLAN.t" && mv "$OD_PLAN.t" "$OD_PLAN"
  { [ -z "$keep" ] || printf '%s\n' "$keep"; printf 'run/v1|ev=proof|ac=AC-1.1|evidence=%s/generic-evidence.md|at=2026-10-04T01:00:00Z\n' "$OD_RL"
    [ -z "$sd" ] || printf '%s\n' "$sd"; } >> "$OD_REC/run.log"
  bound_marker "$OD" "$OD_SID" "$OD_PLAN" >/dev/null 2>&1 || :
}
od_rows() {  # <T1 status> <T2 status> <T3 and T4 status> -> the order's rows: build, regression, review, release, integrate
  od_row T1 4 build 'the lib writer' implementor lib/b.sh "$1" 'approval:plan'
  od_row T2 5 test 'the whole regression' test-runner — "$2" 'approval:plan'
  od_row T3 6 review 'the critic' critic .bionic/docs/record/w/T3.md "$3" 'approval:plan'
  od_row T4 7 doc 'the release' implementor README.md "$3" 'approval:plan'
  od_row T5 8 integrate 'merge into main' orchestrator — pending 'approval:release, approval:merge'
}
od_poke() {  # <args...> -> OD_OUT, OD_RC: session-poker.sh as this session, in the repository
  OD_RC=0
  OD_OUT="$(cd "$OD" && env CLAUDE_CODE_SESSION_ID="$OD_SID" HOME="$OD_ROOT/home" CLAUDE_CONFIG_DIR="$OD_ROOT/config" \
    BIONIC_GATE_DIR="$OD_ROOT/gate" bash "${BIONIC_HOOKS_DIR}/session-poker.sh" "$@" 2>&1)" || OD_RC=$?
}
od_logs() { find "$OD_REC" -name 'regression-run-*.log' | wc -l | tr -d ' '; }
od_lrec() { bash -c '. "$1/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "$OD_LIB" "$OD_PLAN" || printf '%s/none' "$OD_ROOT"; }
od_lall() { cat "$(od_lrec)" "$(dirname "$(od_lrec)")/run.log" 2>/dev/null; }   # the record's lines, then the run log's
od_state() { bash -c '. "$1/roots.sh" 2>/dev/null; . "$1/proof.sh" && proof_state "$2" "$3"' _ "$OD_LIB" "$OD_PLAN" "$OD" 2>/dev/null | cut -f1; }

od_plan 4 '' "$(od_rows pending pending pending; od_row T9 7 test 'a second regression. The suite runs again after the release.' test-runner .bionic/docs/record/w/T9.md pending 'approval:plan')"
cp "$OD_PLAN" "$OD_ROOT/before"; od_poke task-add T9
expect_eq "OV-1 AC-7.1 task-add of a regression row after the review and the release is refused (exit 1)" "1" "$OD_RC"
expect_eq "OV-1b …and the refusal is the validator's one line for T9, naming T3, the review row it follows" \
  'T9: the regression row comes after the review row T3; the order is build, regression, review, release: put T9 at step 5, ahead of T3' \
  "$(printf '%s\n' "$OD_OUT" | grep '^T9:' || :)"
expect_true "OV-1c …and the plan is byte-identical" cmp -s "$OD_ROOT/before" "$OD_PLAN"

od_plan 5 '' "$(od_rows pending pending pending)"
od_poke regression-run
expect_eq "WR-1 AC-6.1 a build row open: regression-run refuses (exit 1), and nothing ran" "1|0" "$OD_RC|$(od_logs)"
expect_contains "WR-1b …naming the open row" "T1 (step 4, pending)" "$OD_OUT"
od_plan 5 '' "$(od_rows landed pending pending)"
od_poke regression-run
expect_eq "WR-2 AC-6.1 every build row landed: one whole run at the head (exit 0, one log)" "0|1" "$OD_RC|$(od_logs)"
expect_eq "WR-2b …recording one verdict per suite at that commit" "2" "$(od_lall | /usr/bin/grep -c "^run/v1|ev=verdict|row=regression|commit=$OD_B|")"
od_poke regression-run
expect_eq "WR-3 AC-6.1 a second whole run at the same green head: refused (exit 1), no second log" "1|1" "$OD_RC|$(od_logs)"
expect_contains "WR-3b …saying the head has its whole run" "runs once at a head" "$OD_OUT"
od_poke proof-add regression "$OD_RL/regression-run-$OD_B.log"; printf 'notes\n' > "$OD/README.md"; od_git add README.md; od_git commit -qm 'docs only'
od_poke regression-run
expect_eq "WR-3c AC-1.4 one docs commit past the green whole run: refused (exit 1), no log written for the head" "1|1" "$OD_RC|$(od_logs)"
expect_contains "WR-3d …naming the pass at B, its log, and that nothing since moved code" "green at ${OD_B:0:8}, 1 landing since moved no code" "$OD_OUT"
expect_contains "WR-3e …and the full pass's log" "$OD_RL/regression-run-$OD_B.log" "$OD_OUT"
expect_contains "WR-3f …and the exit that lands code" "spawn-worktree.sh ready" "$OD_OUT"

printf 'b.test.sh\n' > "$OD/tests/red"; od_git commit -qam 'b breaks'; OD_H="$(od_git rev-parse HEAD)"
# A head past a whole run is run again: the verb is stopped only by the dirty tree planted here, the last refusal before the runner.
printf 'dirt\n' >> "$OD/lib/b.sh"
od_poke regression-run
od_git checkout -q -- lib/b.sh
expect_eq "FX-1 a new head H past the one whole run: regression-run is not refused as a second whole run; it reaches the dirty-tree check before the runner (exit 1, no log)" "1|1" "$OD_RC|$(od_logs)"
expect_contains "FX-1b …the refusal is the dirty tree's, the last one before the runner" "is dirty (dirty=1)" "$OD_OUT"
expect_absent "FX-1d …and no refusal names the whole run's head as having the run" "${OD_B:0:12} has it" "$OD_OUT"
expect_absent "FX-1e …nor the green pass: the code commit past B put the head out of its reach (the mutant of WR-3c)" "moved no code" "$OD_OUT"
# THE RED RUN THE PLAN'S WHOLE RUN WAS, left at H as the verb leaves one: the runner's report as the log's body, the run line and the per-suite facts through the product's writers.
OD_PLANT=0
(cd "$OD" && { bash tests/run.sh 2>&1 || :; }) | regression_fixture "$OD_PLAN" "$OD_REC/regression-run-$OD_H.log" "$OD_H" 0 1 || OD_PLANT=$?
bash -c '. "$1/proof.sh" && proof_regression_fold "$2" "$3" "$4" "$5" "$6"' _ "$OD_LIB" "$OD_PLAN" "$OD" "$OD_H" \
  "$OD_REC/regression-run-$OD_H.log" "$OD_RL/regression-run-$OD_H.log" || OD_PLANT=$((OD_PLANT + 10))
expect_eq "FX-1c precondition: the red run is left at H (both writers exit 0), its run line and its one red verdict in the record" "0|1|1" \
  "$OD_PLANT|$(od_lall | /usr/bin/grep -c "^run/v1|ev=run|log=$OD_RL/regression-run-$OD_H.log|head=$OD_H|")|$(od_lall | /usr/bin/grep -c "^run/v1|ev=verdict|row=regression|commit=$OD_H|suite=b.test.sh|result=red|")"
OD_FL="run/v1|ev=proof|kind=regression|head=$OD_H|evidence=$OD_RL/regression-run-$OD_H.log|owed=b.test.sh|at=2026-10-12T11:00:00Z"
od_plan 5 "$OD_FL" "$(od_rows landed landed pending)"
expect_eq "FX-1b precondition: the regression at H owes the red suite" "owed" "$(od_state)"
: > "$OD/tests/red"; printf 'two\n' > "$OD/lib/b.sh"; od_git commit -qam 'T6: the fix'; OD_C="$(od_git rev-parse HEAD)"
OD_S2="$(od_state)"
expect_true "FX-2 the fix commit C with no run of its own is not covered (FX-1b and FX-3 read the same extractor)" test -n "$OD_S2" -a "$OD_S2" != covered
{ printf 'line/v1|ev=ready|row=T6|suites=tests/a.test.sh,tests/b.test.sh|at=2026-10-12T12:00:00Z\n'
  printf 'line/v1|ev=published|row=T6|commit=%s|at=2026-10-12T12:10:00Z\n' "$OD_C"
  for od_s in a.test.sh b.test.sh; do
    printf 'line/v1|ev=verdict|row=T6|commit=%s|suite=%s|result=green|log=/fixture/T6.log|at=2026-10-12T12:05:00Z\n' "$OD_C" "$od_s"
  done; } >> "$(od_lrec)"
expect_eq "FX-3 AC-6.2 the fix row green on its own suite and the red one: the head is accepted" "covered" "$(od_state)"
printf 'dirt\n' >> "$OD/lib/b.sh"
od_poke regression-run
od_git checkout -q -- lib/b.sh
expect_eq "FX-4 …and a covered head C is run again: regression-run at C is not refused as proved; it reaches the dirty-tree check before the runner (exit 1, no log)" \
  "1|2" "$OD_RC|$(od_logs)"
expect_contains "FX-4b …the refusal is the dirty tree's, the last one before the runner" "is dirty (dirty=1)" "$OD_OUT"
expect_absent "FX-4c …and no refusal says the head is already proved" "is already proved" "$OD_OUT"
od_git checkout -q -b row/T7; printf 'three\n' > "$OD/lib/b.sh"; od_git commit -qam 'T7: a second fix'; OD_R="$(od_git rev-parse HEAD)"
od_git checkout -q wave/01-fixture; od_git merge -q --no-ff -m 'land T7 by hand' row/T7; OD_M="$(od_git rev-parse HEAD)"
OD_S3="$(od_state)"
expect_true "HL-1 a hand landing M with no verdict recorded is not covered (HL-2 reads the same extractor)" test -n "$OD_S3" -a "$OD_S3" != covered
printf 'line/v1|ev=verdict|row=T7|commit=%s|suite=b.test.sh|result=green|log=/fixture/T7.log|at=2026-10-12T12:20:00Z\n' "$OD_R" >> "$(od_lrec)"
expect_eq "HL-2 AC-6.2 …and covered by the row's green verdict keyed by the row head M brought in" "covered" "$(od_state)"
od_git checkout -q -b row/T8; printf 'eight\n' > "$OD/lib/b.sh"; od_git commit -qam 'T8: a third fix'; OD_R2="$(od_git rev-parse HEAD)"
od_git checkout -q wave/01-fixture; od_git merge -q --no-ff -m 'land T8 by hand' row/T8; OD_M2="$(od_git rev-parse HEAD)"
{ printf 'line/v1|ev=ready|row=T8|commit=%s|suites=none|at=2026-10-12T12:30:00Z\n' "$OD_R2"
  printf 'line/v1|ev=published|row=T8|commit=%s|kind=hand|by=Fixture|at=2026-10-12T12:31:00Z\n' "$OD_M2"; } >> "$(od_lrec)"
OD_S4="$(od_state)"
expect_true "HL-3 a hand landing whose ready says none, with no verdict recorded, is not covered (HL-4 reads the same extractor)" test -n "$OD_S4" -a "$OD_S4" != covered
printf 'line/v1|ev=verdict|row=T8|commit=%s|suite=b.test.sh|result=green|log=/fixture/T8.log|at=2026-10-12T12:32:00Z\n' "$OD_R2" >> "$(od_lrec)"
expect_eq "HL-4 …and covered once the verdicts the row recorded name a green suite at the row head" "covered" "$(od_state)"

section "§HL — a ready line's none is no suite at every landing kind, so a hand and a queue landing of one row read alike"
# ============================================================
# A queue ready writes `suites=none` for a row that lands on no suite, and so does a hand ready. The landing-record fold maps
# that none to no suite once, for both kinds; read as a suite name for the queue kind alone, it printed `none has no run
# recorded at it` for a commit the verdicts could prove. FIXTURES: the repository above; the lines are written in the
# writers' shapes (`ev=ready … suites=none`, `ev=published … kind=hand|queue`); the judge is proof_state, the one reader.
# fails-when: the fold keeps none as a suite for a queue landing, so the queue's judge line names none and the hand's does not.
hl_judge() { bash -c '. "$1/roots.sh" 2>/dev/null; . "$1/proof.sh" && proof_state "$2" "$3"' _ "$OD_LIB" "$OD_PLAN" "$OD" 2>/dev/null | tr '\t' ' '; }
hl_land() {  # <hand|queue> -> the record holds T9's ready (suites=none) and one published line of that kind at M3
  /usr/bin/grep -v '^line/v1|ev=published|row=T9|' "$OD_ROOT/hl-record" > "$(od_lrec)"
  printf 'line/v1|ev=published|row=T9|commit=%s|kind=%s|by=Fixture|at=2026-10-12T12:41:00Z\n' "$OD_M3" "$1" >> "$(od_lrec)"
}
od_git checkout -q -b row/T9; printf 'nine\n' > "$OD/lib/b.sh"; od_git commit -qam 'T9: a fourth fix'; OD_R3="$(od_git rev-parse HEAD)"
od_git checkout -q wave/01-fixture; od_git merge -q --no-ff -m 'land T9' row/T9; OD_M3="$(od_git rev-parse HEAD)"
printf 'line/v1|ev=ready|row=T9|commit=%s|suites=none|at=2026-10-12T12:40:00Z\n' "$OD_R3" >> "$(od_lrec)"
cp "$(od_lrec)" "$OD_ROOT/hl-record"
hl_land hand; HL_HAND="$(hl_judge)"
hl_land queue; HL_QUEUE="$(hl_judge)"
expect_contains "HL-5 precondition: a hand landing recording none is judged by the verdicts, and none are recorded at it" "no run of its row's suites is recorded at it" "$HL_HAND"
expect_eq "HL-5b AC-2.2 a hand landing and a queue landing of the same row at the same commit print the same judge line" "$HL_HAND" "$HL_QUEUE"
expect_absent "HL-5c AC-2.1 …and the queue's line does not name none as a suite" "none has no run recorded at it" "$HL_QUEUE"
hl_s8() {  # the plan at current 8, approved at the working head, every row but integrate landed, T9's landing in the record
  od_plan 8 "run/v1|ev=approval|key=release|by=Dana Fixture|head=$OD_M3|said=Ship it.|at=2026-10-12T14:00:00Z"$'\n'"$OD_FL" \
    "$(od_rows landed landed landed)"
  od_poke current 8 --check
}
hl_s8
expect_contains "HL-5d precondition: current 8 --check prints the landing's line, the commit unproved (HL-5e reads the same output)" "(row T9) is not proved: " "$OD_OUT"
expect_absent "HL-5e AC-2.1 …and prints no none as a suite that has no run recorded" "none has no run recorded at it" "$OD_OUT"
printf 'line/v1|ev=verdict|row=T9|commit=%s|suite=b.test.sh|result=green|log=/fixture/T9.log|at=2026-10-12T12:42:00Z\n' "$OD_R3" >> "$(od_lrec)"
expect_eq "HL-6 AC-2.1 a queue landing whose ready recorded none reads covered once a green verdict stands at the row head" "covered" "$(od_state)"

printf '# fixture\n' > "$OD/README.md"; od_git add README.md; od_git commit -qm 'T4: the release'; OD_A="$(od_git rev-parse HEAD)"
od_reads() {  # the five readings a double wave plan is dealt, at A
  local q
  for q in evidence adversarial structure; do
    printf 'question: %s\nresult: pass\nscope: piece\nreviewed: %s..%s\nfindings: 0\n' "$q" "${OD_B:0:10}" "${OD_A:0:10}" > "$OD_REC/$q.md"
    printf 'run/v1|ev=proof|kind=review|head=%s|evidence=%s|question=%s|reader=w-read|result=pass|scope=piece|at=2026-10-12T13:00:00Z\n' "$OD_A" "$OD_RL/$q.md" "$q"
  done
  for q in adversarial structure; do
    printf 'question: %s\nresult: pass\nscope: whole\nreviewed: %s..%s\nfindings: 0\n' "$q" "${OD_B:0:10}" "${OD_A:0:10}" > "$OD_REC/$q-whole.md"
    printf 'run/v1|ev=proof|kind=review|head=%s|evidence=%s|question=%s|reader=w-read|result=pass|scope=whole|at=2026-10-12T13:00:00Z\n' "$OD_A" "$OD_RL/$q-whole.md" "$q"
  done
}
od_appr() { printf 'run/v1|ev=approval|key=release|by=Dana Fixture|head=%s|said=Ship it.|at=2026-10-12T14:00:00Z' "$1"; }
od_s8() {  # <approval line> -> the plan at current: ${OD_S:-8}, every row but integrate landed
  od_plan "${OD_S:-8}" "${1:+$1$'\n'}$OD_FL"$'\n'"$(od_reads)" "$(od_rows landed landed landed)"$'\n'"$(od_row T6 5 build 'the fix' implementor lib/b.sh landed 'approval:plan')"$'\n'
}
od_s8 "$(od_appr "$OD_A")"
expect_eq "AH-0 precondition: the plan is in the order, the regression row named" "T2" \
  "$(bash -c '. "$1/units.sh" && units_order "$2"' _ "$OD_LIB" "$OD_PLAN" 2>/dev/null || :)"
od_poke current 8 --check
expect_eq "AH-1 approved head A, the working head A, the whole run at H with C fixed on its suites: refused as regression unproved, naming both exits" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q 'regression.*unproved' && printf '%s\n' "$OD_OUT" | /usr/bin/grep -q 'reply .* on the release card' && echo yes || echo no)"
od_mu() { printf 'run/v1|ev=approval|key=merge-unproved|by=chris|head=%s|said=merge|at=2026-10-26T00:00:00Z' "$1"; }  # the merge approval, at the head it names
od_s8 "$(od_appr "$OD_A")"$'\n'"$(od_mu "$OD_A")"; od_poke current 8 --check
expect_eq "AH-1b …and with the person's merge-unproved word at head A beside it: passes" "0" "$OD_RC"
od_s8 "$(od_appr "$OD_A")"$'\n'"$(od_mu "$OD_C")"; od_poke current 8 --check
expect_eq "AH-1c …the same word naming a head that is not A leaves it refused" "1" "$OD_RC"
# §EXIT7: the unproved exit is the step's. At 7 no release card can exist yet, so the exit is the pass; at 8 it is the card's reply, and a
# docs head past the whole run is admitted at 7. fails-when: current 7 over an unproved head names a reply or a release card, current 8
# stops naming the reply, or a docs commit past the run draws a refusal at 7.
OD_N7='needs: the pass — wait for it (the tick starts it once no row is ready), or start it: session-poker.sh regression-run'
od_x7() { OD_FL="$2" OD_S=$(($1 - 1)) od_s8 "$(od_appr "$OD_A")"; od_poke current "$1" --check; }  # <step> <floor line> -> the plan one step before it, asked for <step>
od_rg() { printf '%s\n' "$OD_OUT" | /usr/bin/grep 'regression.*unproved' | awk -F'\t' '{ print $NF }'; }
od_x7 7 "$OD_FL"
expect_eq "X7-1 AC-2.1 current 7 over the unproved head A: refused, the exit is the pass and names no reply and no release card" "1|$OD_N7|0" \
  "$OD_RC|$(od_rg)|$(od_rg | /usr/bin/grep -ciE 'reply|release card' || :)"
od_x7 8 "$OD_FL"
expect_eq "X7-2 AC-2.2 current 8 at the same head: refused, the exit is the card's reply, as before" \
  "1|needs: the user — reply <n> on the release card (merge without a whole run at this head), or wait for the pass" "$OD_RC|$(od_rg)"
printf 'notes\n' >> "$OD/README.md"; od_git commit -qam 'a docs commit past the pass'
od_x7 7 "run/v1|ev=proof|kind=regression|head=$OD_A|evidence=$OD_RL/regression-run-$OD_H.log|at=2026-10-12T11:30:00Z"
expect_eq "X7-3 AC-2.3 the pass at A and one docs commit past it: current 7 admitted (exit 0), no regression unproved" "0|" "$OD_RC|$(od_rg)"
od_git reset -q --hard "$OD_A"

od_s8 "$(od_appr "$OD_C")"
od_poke current 8 --check
expect_eq "AH-2 AC-7.2 approved head C, the working head A: current 8 --check refuses (exit 1)" "1" "$OD_RC"
od_s8 'run/v1|ev=approval|key=release|by=Dana Fixture|said=Ship it.|at=2026-10-12T14:00:00Z'
od_poke current 8 --check
expect_eq "AH-3 an approval line that names no head: refused (exit 1), saying so" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q "names no head" && echo yes || echo no)"
od_s8 ''
od_poke current 8 --check
expect_eq "AH-4 no approved: release line: refused (exit 1), naming the verb that writes it" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q "approve release" && echo yes || echo no)"

# A WHOLE RUN AT AN ANCESTOR IS CITED THROUGH proof-add AS THE JUDGE JUDGES IT: the verb accepts the log at the head A
# where the judge says covered, and a later commit no run proves is refused by that commit, not by "a whole run".
od_plan 5 '' "$(od_rows landed landed pending)"
od_poke proof-add regression "$OD_RL/regression-run-$OD_H.log"
expect_eq "PA-1 a whole run at ancestor H, every commit since proved or excused: proof-add accepts it (exit 0), and the head is covered" \
  "0|covered" "$OD_RC|$(od_state)"
printf 'four\n' > "$OD/lib/b.sh"; od_git commit -qam 'a change no run proves'; OD_D="$(od_git rev-parse HEAD)"
od_plan 5 '' "$(od_rows landed landed pending)"
od_poke proof-add regression "$OD_RL/regression-run-$OD_H.log"
expect_eq "PA-2 …and one commit later that no landing proves: refused (exit 1), naming that commit and that it is not proved" "1|yes" \
  "$OD_RC|$(printf '%s\n' "$OD_OUT" | /usr/bin/grep -q "commit ${OD_D:0:12} .*is not proved" && echo yes || echo no)"
expect_absent "PA-2b …and the same refusal offers no second whole run (the positive above reads this output)" "run the whole" "$OD_OUT"

finish
