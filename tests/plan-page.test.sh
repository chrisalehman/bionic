#!/bin/bash
# tests/plan-page.test.sh — the plan is the person's: what a version-15 plan may hold, judged where it is
# written and read through the one parser of its authored parts (payload/scripts/lib/plan-read.sh).
#
#   §SECTIONS  a version-15 plan holding a verification matrix, a state or a handoff section is refused at
#              the write with the heading's line named; a version-14 plan holding all three is admitted, and
#              so is a version-15 plan whose only copy of one is inside a fence.
#   §ROW       a version-15 Tasks table with a status or an agent cell is refused, naming the cell; its nine
#              authored cells alone are admitted.
#   §KEYS      each header key the version-15 header has no place for is refused on a version-15 plan, the
#              refusal naming it; the same key on a version-14 plan is admitted.
#   §GATE      the commit gate (hooks/bash-walls.sh) asks the run's facts for the step's evidence: a commit at
#              Step 6 whose log holds no review event is refused, and admitted once the log holds one per question.
#              The same run at 15, brought forward, is refused as the 14 is, and with its reviews still refused, naming each fact its log lacks.
#              At 15 a step's evidence is asked where it is held, owed while missing and not once it stands; a step
#              pending in an advance's judgment moves the gate only in the advance's own session, and is never held.
#
# FIXTURE FIDELITY. Each plan is a real file in a scratch git repository with an engaged session, written
# through hooks/canonical-sdlc-governing-skill.sh as the Write tool would post it. Every plan carries the
# whole header the hook demands, so a refusal is the shape's and never a missing flag's: each refused plan
# has an admitted twin that differs only in the part under test (SYNTHESIZED from that header list).
#
# ANTI-VACUITY. Every refusal row stands beside its admitted twin on the same driver, and the line a
# refusal names is computed from the fixture with `grep -n`, never typed.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"
PLAN_READ="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/plan-read.sh"
[ -r "$HOOK" ] && bash -n "$HOOK" || { echo "plan-page: the write hook is missing or does not parse: $HOOK"; exit 1; }

SID="7c1e5b2a-9d40-4f6e-8a31-2b0c9e4d7f15"
R="$(cd "$(mktemp -d)" && pwd -P)"; HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$R" "$HOME_DIR"' EXIT
git -C "$R" init -q .
mkdir -p "$R/.bionic/docs/plans/epic-01-demo" "$R/.bionic/tmp"
: > "$R/.bionic/tmp/engaged-$SID.state"

# page <version> [extra header line]... -> a plan's text: the whole header, a Goal, and the body on stdin.
page() {
  local v="$1" l; shift
  printf -- '---\ngoverning-skill: canonical-sdlc\nsdlc-step: 4\nepic: epic-01-demo\nwave: wave-01-x\n'
  printf 'canonical_sdlc_version: %s\nintent: build\nrigor: double\nscale: wave\n' "$v"
  printf 'cleanup_on_finish: true\nuse_worktree: false\nsurface_type: cli-plugin\nlanguage: bash\n'
  printf 'has_ui: false\nmulti_agent: true\ndeploy_target: n/a\nmodel_plan: orchestrator=a; implementor=b\n'
  for l in "$@"; do printf '%s\n' "$l"; done
  printf -- '---\n\n## Goal\n\nA plan written by a person.\n\n'
  cat
}

# write_plan <text> -> HOOK_EXIT, and HOOK_SAID: the refusal with its detail (BIONIC_WALL_VERBOSE=1).
write_plan() {
  local in
  in="$(jq -n --arg p "$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" --arg c "$1" --arg s "$SID" \
    '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}')"
  HOOK_SAID="$(HOME="$HOME_DIR" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$in" 2>&1 >/dev/null)"
  HOOK_EXIT=$?
}

NINE='| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the first | — | 30 | REQ-1 | a.sh | record/T1.md |'
MACHINE='## Verification Matrix

| AC | tier | status |
|---|---|---|
| AC-1 | T1 | pending |

## SDLC State

current: 4

## Handoff

The next session reads this.'

section "SECTIONS"
write_plan "$(printf '## Tasks\n\n%s\n' "$NINE" | page 15)"
expect_status "a version-15 plan of the person's parts alone is admitted" 0 "$HOOK_EXIT"
for h in "Verification Matrix" "SDLC State" "Handoff"; do
  body="$(printf '## Tasks\n\n%s\n\n%s\n' "$NINE" "$MACHINE")"
  text="$(printf '%s\n' "$body" | page 15)"
  n="$(printf '%s\n' "$text" | grep -n "^## $h\$" | cut -d: -f1)"
  expect_nonempty "the fixture holds ## $h" "$n"
  write_plan "$text"
  expect_status "a version-15 plan holding ## $h is refused" 2 "$HOOK_EXIT"
  expect_contains "the refusal names ## $h at its line" "line $n: ## $h" "$HOOK_SAID"
done
write_plan "$(printf '%s\n' "$MACHINE" | page 14)"
expect_status "a version-14 plan holding all three is admitted" 0 "$HOOK_EXIT"
write_plan "$(printf '## Tasks\n\n%s\n\nAn example:\n\n```\n## Handoff\n```\n' "$NINE" | page 15)"
expect_status "a fenced ## Handoff is prose, and admitted" 0 "$HOOK_EXIT"
FP="$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"; printf '## SDLC State\n\ncurrent: 4\n\n## Tasks\n\n%s\n\n### T1 — a fenced comment\n\nRuling one.\n\n```bash\n# run it like this\n## run\n```\n\nRuling two: never commit.\n' "$NINE" | page 14 > "$FP"
expect_contains "a section holding a fenced # line is read whole" "Ruling two: never commit." "$(bash -c '. "$1" && plan_read_section "$2" T1' _ "$PLAN_READ" "$FP")"
bash -c '. "$1" && plan_read_section "$2" run' _ "$PLAN_READ" "$FP" >/dev/null; expect_status "a heading inside a fence starts no section" 1 "$?"
printf 'plan=%s\n' "$FP" > "$R/.bionic/tmp/engaged-$SID.state"; ( cd "$R" && HOME="$HOME_DIR" CLAUDE_CODE_SESSION_ID="$SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" brief T1 w01-T1 ) >/dev/null 2>&1
expect_contains "a brief rendered from that section carries the ruling after the fence" "Ruling two: never commit." "$(cat "$R/.bionic/docs/record/wave-01-x/briefs/w01-T1.md" 2>/dev/null)"

section "ROW"
for c in status agent; do
  table="$(printf '%s\n' "$NINE" | awk -v c="$c" 'NR == 1 { sub(/ artifact \|$/, " artifact | " c " |") } NR == 2 { $0 = $0 "---|" } NR == 3 { $0 = $0 " x |" } { print }')"
  text="$(printf '## Tasks\n\n%s\n' "$table" | page 15)"
  n="$(printf '%s\n' "$text" | grep -n '^| id |' | cut -d: -f1)"
  expect_contains "the fixture's header names the cell $c" "| $c |" "$table"
  write_plan "$text"
  expect_status "a version-15 row with the cell $c is refused" 2 "$HOOK_EXIT"
  expect_contains "the refusal names the $c cell at the header's line" "line $n: the Tasks table holds the cell $c" "$HOOK_SAID"
done

section "KEYS"
gone="$(bash -c '. "$1" && printf "%s" "$PLAN_READ_GONE_KEYS"' _ "$PLAN_READ")"
expect_nonempty "the parser lists the keys a version-15 header has no place for" "$gone"
for k in $gone; do
  write_plan "$(printf '## Tasks\n\n%s\n' "$NINE" | page 15 "$k: 2026-11-10")"
  expect_status "a version-15 header with $k: is refused" 2 "$HOOK_EXIT"
  expect_contains "the refusal names $k" "header key $k:" "$HOOK_SAID"
  write_plan "$(printf '%s\n' "$MACHINE" | page 14 "$k: 2026-11-10")"
  expect_status "a version-14 header with $k: is admitted" 0 "$HOOK_EXIT"
done

# A run with a log is read from the log alone, so the plan below holds no proved: line and the planted log holds
# the run's step and, in the admitted twin, its readings: the gate admits on the facts the reader answers.
section "GATE"
git -C "$R" -c user.name=f -c user.email=f@x.invalid -c core.hooksPath=/dev/null commit -q --allow-empty -m base
H="$(git -C "$R" rev-parse HEAD)"; GL="$R/.bionic/docs/record/wave-01-x/run.log"
mkdir -p "${GL%/*}"; printf 'proof\n' > "$R/.bionic/docs/record/generic-evidence.md"
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
  printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n\n## SDLC State\n\ncurrent: 6\n'
  printf 'approved-by: f 2026-11-01T00:00Z "approved"\n- Step 5: floor green, record/floor.log\n\n## Verification Matrix\n\n'
  printf 'stack-health: n/a: no serve\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\nAC-1:\n  fails-when: a planted defect\n  evidence: record/generic-evidence.md\n'
} > "$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"
printf 'plan=%s\n' "$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" > "$R/.bionic/tmp/engaged-$SID.state"
gate_as() {  # <session> <a pending step, or nothing> -> GATE_EXIT, and GATE_SAID: the gate's words on a commit from the repository
  local in
  in="$(jq -n --arg s "$1" --arg c "$R" '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git commit -m x"}}')"
  GATE_SAID="$(HOME="$HOME_DIR" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$1" BIONIC_DRY_STEP="$2" BIONIC_WALL_VERBOSE=1 bash "$BIONIC_HOOKS_DIR/bash-walls.sh" <<< "$in" 2>&1 >/dev/null)"
  GATE_EXIT=$?
}
gate() { gate_as "$SID" ""; }
printf 'run/v1|ev=step|n=6|by=f|at=2026-11-01T00:00:01Z\n' > "$GL"
gate
expect_status "a commit at step 6 with no review event in the log is refused" 2 "$GATE_EXIT"
expect_contains "the refusal names the unanswered reading" "evidence: no review, and no waiver" "$GATE_SAID"
for q in evidence adversarial structure; do
  printf 'run/v1|ev=proof|evidence=record/%s.md|head=%s|kind=review|question=%s|reader=r|result=pass|scope=piece|at=2026-11-01T00:00:02Z\n' "$q" "$H" "$q" >> "$GL"
done
gate
expect_status "the same commit with a review event of each question is admitted" 0 "$GATE_EXIT"
# At 14 too the step and the plan's approval are the run's facts: a step the log alone holds past current: is judged.
printf 'run/v1|ev=step|n=7|by=f|at=2026-11-01T00:00:03Z\n' >> "$GL"; gate
expect_eq "a step 7 the log holds past current: 6 is the step judged, refused for its line" "2|has no 'Step 7:' line" "$GATE_EXIT|$(printf '%s' "$GATE_SAID" | /usr/bin/grep -o "has no 'Step 7:' line" | head -1)"
printf 'run/v1|ev=step|n=6|by=f|at=2026-11-01T00:00:04Z\n' >> "$GL"; GP="$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"
sed -i.bak '/^approved-by:/d' "$GP"; gate
expect_eq "taken back to 6 with no approval anywhere, refused for the approval" "2|approved-by" "$GATE_EXIT|$(printf '%s' "$GATE_SAID" | /usr/bin/grep -o 'approved-by' | head -1)"
printf 'run/v1|ev=approval|key=step3|by=f|said=approved|at=2026-11-01T00:00:05Z\n' >> "$GL"; gate
expect_status "an approval the log alone holds admits the same commit" 0 "$GATE_EXIT"

# The same run at 15, made by the act from a version-14 plan: judged on what its log holds, and refused naming what it lacks.
P2="$R/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md"; L2="$R/.bionic/docs/record/wave-02-y/run.log"; mkdir -p "$R/.bionic/docs/specs"; : > "$R/.bionic/docs/specs/r.md"
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\nmulti_agent: true\ndeploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | One. | — | — | 30 | REQ-1 | a.sh | — | — | landed |\n\n'
  printf '## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n| REQ-1 | x | AC-1 | unit | e | a planted defect |\n\n'
  printf '## SDLC State\n\ncurrent: 6\napproved-by: f 2026-11-01T00:00Z "approved"\n- Step 1: requirements: specs/r.md\n- Step 5: floor green, record/floor.log\n- T1: landed record/generic-evidence.md\n\n'
  printf '## Verification Matrix\n\nstack-health: n/a: no serve\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\nAC-1:\n  fails-when: a planted defect\n  evidence: record/generic-evidence.md\n'
} > "$P2"; printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$SID.state"
gate; S14="$GATE_EXIT ${GATE_SAID%%$'\n'*}"
bash "$BIONIC_SCRIPTS_DIR/payload/scripts/bring-forward.sh" "$P2" >/dev/null; expect_contains "the act wrote the plan at 15" "canonical_sdlc_version: 15" "$(cat "$P2")"
gate; expect_eq "at 15 with no review event, refused as the 14 is, by the same refusal" "$S14" "$GATE_EXIT ${GATE_SAID%%$'\n'*}"
expect_contains "the 14 was refused for the reviews" "2 bionic: commit refused — a review question is unanswered" "$S14"
grep -h 'kind=review' "$GL" >> "$L2"; gate
expect_status "at 15 with each review, still refused: the step's other facts are not in the log" 2 "$GATE_EXIT"
owed() { printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o "owed at 15: $1" | head -1; }
expect_eq "…and owes Step 1's requirements, which a header naming no epic and wave cannot find" "owed at 15: Step 1's requirements" "$(owed "Step 1's requirements")"
expect_absent "…and asks a row's landing and launch of the reader, never naming each row's line as unread" "could not be read at 15: each row's" "$GATE_SAID"
cp "$P2" "$P2.keep"; awk '{ print } /^\| T1 \|/ { t = $0; print; sub(/^\| T1 \|/, "| T2 |", t); sub(/\| build \|/, "| bogus |", t); print t }' "$P2.keep" > "$P2"; gate
expect_eq "at 15 a second row of one id and a row of an unknown kind are refused at the commit, each named" "2|T1: duplicate id|T2: kind bogus" \
  "$GATE_EXIT|$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o 'T1: duplicate id\|T2: kind bogus' | paste -sd'|' -)"
awk '{ print } /^\| T1 \|/ { sub(/^\| T1 \|/, "| T2 |"); print }' "$P2.keep" > "$P2"; printf 'run/v1|ev=dispatch|row=T2|name=w-T2|brief=b|at=2026-11-01T00:00:02Z\n' >> "$L2"; gate
expect_eq "a row the log holds dispatched under a name stands at 15 on its dispatch: the gate names neither it nor an evidence line, and owes the requirements still" \
  "|owed at 15: Step 1's requirements" "$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o "T2[^ ]*\\|evidence line" | head -1)|$(owed "Step 1's requirements")"
cp "$P2.keep" "$P2"; for f in "each criterion's fails-when:" "the matrix:"; do expect_absent "…and no longer names $f" "could not be read at 15: $f" "$GATE_SAID"; done
unruled() { ( . "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/run.sh"; . "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/units.sh"; . "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/proof.sh"
  . "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh"; matrix_unruled "$P2" 8 "$@" | tr '\n' ' ' ); }
expect_eq "at 15 the merge advance asks the evidence review at the head of a criterion: none read, AC-1 owes its ruling; read, none" "AC-1 |" "$(unruled)|$(unruled "$H")"
printf 'run/v1|ev=step|n=5|at=2026-11-01T00:00:03Z\n' >> "$L2"; gate
expect_eq "at Step 5 with no regression proof in the log the regression is owed" "owed at 15: Step 5's regression" "$(owed "Step 5's regression")"
# A row's declared red at 15 is judged on the proofs the log holds: owed with none after it, cleared by a later one.
printf 'run/v1|ev=step|n=6|at=2026-11-01T00:00:04Z\nrun/v1|ev=admitted|id=d1|row=T1|suite=a.test.sh|token=ext:gone|at=2026-11-01T00:00:05Z\n' >> "$L2"; gate
expect_contains "at 15 a declared red the log holds, no proof after it, is owed" "a.test.sh: landed red until ext:gone" "$GATE_SAID"
printf 'run/v1|ev=proof|kind=regression|head=%s|evidence=record/floor.log|at=2026-11-01T00:00:06Z\n' "$H" >> "$L2"; gate
expect_eq "…a regression proof after it in the log clears it: still refused for the facts the log lacks, it names no proof" "2|" \
  "$GATE_EXIT|$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o 'landed red until\|could not be read at 15\|the proofs that clear' | LC_ALL=C sort -u | paste -sd'|' -)"
printf 'run/v1|ev=admitted|id=d2|row=T1|suite=b.test.sh|token=approval:ship|at=2026-11-01T00:00:06Z\n' >> "$L2"; gate; AS="$GATE_SAID"; printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%sZ\n' 'approval|key=ship|by=f' 7 "proof|kind=regression|head=$H|evidence=record/floor-2.log" 8 >> "$L2"; gate
expect_eq "…one held until an approval is owed while the log holds none, and cleared by the approval and a proof after it" "1|0" "$(grep -c 'b.test.sh: landed red until approval:ship' <<< "$AS")|$(grep -c 'b.test.sh: landed red' <<< "$GATE_SAID")"

# Each fact a step owes at 15 is asked where it is held, owed while it is missing and not once it stands.
hdr() { awk -v l="$1" '{ print } /^walk: exempt$/ { print l }' "$P2" > "$P2.t" && mv "$P2.t" "$P2"; }   # <a header line> -> the plan's header gains it
hdr 'epic: epic-01-demo'; hdr 'wave: wave-02-y'; hdr 'environments: mac'; mkdir -p "$R/.bionic/docs/specs/epic-01-demo"
: > "$R/.bionic/docs/specs/epic-01-demo/wave-02-y.requirements.md"; printf 'run/v1|ev=step|n=5|at=2026-11-01T00:00:07Z\n' >> "$L2"; gate
expect_eq "at 5: the regression and the requirements found by the header stand; the environments a walk covered are owed" \
  "||owed at 15: Step 5's environments covered" "$(owed "Step 5's regression")|$(owed "Step 1's requirements")|$(owed "Step 5's environments covered")"
printf 'run/v1|ev=proof|kind=walk|head=%s|evidence=record/generic-evidence.md|environments=mac|at=2026-11-01T00:00:08Z\n' "$H" >> "$L2"; gate
expect_eq "…and stand once the walk's proof names them" "" "$(owed "Step 5's environments covered")"
for c in "2|approval|step1|Step 1's approval" "7|header|adrs: none — no decision this run|Step 7's document" "9|step|delivered=v1|Step 9's delivery"; do
  IFS='|' read -r n k v w <<< "$c"; ev="run/v1|ev=step|n=$n"; [ "$n" != 9 ] || ev="$ev|delivered=no"; printf '%s|at=2026-11-01T00:00:09Z\n' "$ev" >> "$L2"; gate
  expect_eq "at $n the log lacking it, $w is owed" "owed at 15: $w" "$(owed "$w")"
  case "$k" in approval) printf 'run/v1|ev=approval|key=%s|by=f|said=yes|at=2026-11-01T00:00:10Z\n' "$v" >> "$L2" ;;
    header) hdr "$v" ;; step) printf 'run/v1|ev=step|n=%s|%s|at=2026-11-01T00:00:10Z\n' "$n" "$v" >> "$L2" ;; esac; gate
  expect_eq "…and not owed once it stands" "" "$(owed "$w")"; done
# At 8 the merge is owed only when the plan holds an integrate row and the run is not parked, and then until it lands.
printf 'run/v1|ev=step|n=8|at=2026-11-01T00:00:11Z\n' >> "$L2"; gate
expect_eq "at 8 with no integrate row no merge is owed, and the close's cleanup is" "|owed at 15: Step 8's cleanup" "$(owed "Step 8's merge")|$(owed "Step 8's cleanup")"
awk '{ print } /^\| T1 \| 4 \| build /{ print "| T2 | 8 | integrate | Merge. | T1 | 10 | REQ-1 | — | — |" }' "$P2" > "$P2.t" && mv "$P2.t" "$P2"; gate
expect_eq "…with one, its landing is owed" "owed at 15: Step 8's merge" "$(owed "Step 8's merge")"
cp "$P2" "$P2.w"; printf '\n## Wake Note\n\nParked: the person holds the merge.\n' >> "$P2"; gate; mv "$P2.w" "$P2"
expect_eq "…and not while the run is parked" "" "$(owed "Step 8's merge")"
printf 'run/v1|ev=step|n=8|cleanup=n/a: kept|at=2026-11-01T00:00:12Z\n' >> "$L2"; gate
expect_eq "…and the cleanup not once the close gives it to the step" "owed at 15: Step 8's merge|" "$(owed "Step 8's merge")|$(owed "Step 8's cleanup")"
# A step pending in an advance's judgment moves the gate only in the advance's own session, and is never held.
printf 'run/v1|ev=cancel|of=approval|key=step1|at=2026-11-01T00:00:13Z\n' >> "$L2"
for d in planverb-4242 closeout-preflight-4243; do printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$d.state"; gate_as "$d" 2
  expect_eq "a dry judgment's own session ($d) is judged at the step pending" "owed at 15: Step 1's approval" "$(owed "Step 1's approval")"; done
gate_as "$SID" 2
expect_eq "a real session's commit with the same variable set is judged at the step its log holds, nothing held of the pending one" "owed at 15: Step 8's merge|" "$(owed "Step 8's merge")|$(owed "Step 1's approval")"
# The close's own judgment folds, last, the facts its acts will write, on the one channel the pending step rides: its step
# with its fields, the landing of a row it lands, a tree it removes. Nothing else may ride there.
printf 'run/v1|ev=tree|row=T1|path=.worktrees/t1|at=2026-11-01T00:00:14Z\n' >> "$L2"; mkdir -p "$R/.worktrees/t1"
contains() { case "$1" in *"$2"*) printf yes ;; *) printf no ;; esac; }
CF="8|cleanup=done|tmp-wiped=0 entries|tasks-completed=T1"$'\n'"published|row=T2|commit=$H|kind=close|by=close-out|why=merged"$'\n'"tree|row=T1|path="
L2_SUM="$(cksum < "$L2")"; gate_as closeout-preflight-4243 "$CF"
expect_eq "the close's own session is judged with its facts pending: no merge, tree or cleanup owed, the log's other asks still made" "|||yes" "$(owed "Step 8's merge")|$(owed "Step 8's trees")|$(owed "Step 8's cleanup")|$(contains "$GATE_SAID" "could not be read at 15: each row's")"
gate_as "$SID" "$CF"
expect_eq "a real session with the same facts set is judged on the log, nothing held of them" "owed at 15: Step 8's merge|owed at 15: Step 8's trees" "$(owed "Step 8's merge")|$(owed "Step 8's trees")"
expect_eq "nothing pending is appended: the log is as it was" "$L2_SUM" "$(cksum < "$L2")"
for v in "8|delivered=x" "8"$'\n'"approval|key=step3|by=f|said=yes" "8"$'\n'"proof|kind=regression|head=$H|evidence=x" "8"$'\n'"waiver|question=evidence" "8"$'\n'"finding|ref=r.md#1" "8"$'\n'"published|row=T2|commit=$H|kind=hand|by=f" "8"$'\n'"tree|row=T1|path=.worktrees/t9"; do
  gate_as closeout-preflight-4243 "$v"
  expect_eq "a pending line the close does not write is refused by the fold: ${v//$'\n'/ / }" "2|yes" "$GATE_EXIT|$(contains "$GATE_SAID" "the facts pending in closeout-preflight-4243 are refused")"
done
# At 14 steps 8 and 9 are asked what they are asked at 15, of the reader, with no Step line asked for.
printf 'plan=%s\n' "$GP" > "$R/.bionic/tmp/engaged-$SID.state"
owed14() { printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o "owed at 14: $1" | head -1; }
printf 'run/v1|ev=step|n=8|at=2026-11-01T00:00:20Z\n' >> "$GL"; gate
expect_eq "at 14 a step 8 the log holds is asked of its event: its cleanup owed, no Step 8 line asked for" "2|owed at 14: Step 8's cleanup|no" "$GATE_EXIT|$(owed14 "Step 8's cleanup")|$(contains "$GATE_SAID" "has no 'Step 8:' line")"
printf 'run/v1|ev=proof|kind=regression|head=%s|evidence=record/floor.log|at=2026-11-01T00:00:21Z\nrun/v1|ev=step|n=8|cleanup=done|tmp-wiped=0 entries|tasks-completed=T1|at=2026-11-01T00:00:21Z\n' "$H" >> "$GL"; gate
expect_status "…and admitted once the close gives the step its fields" 0 "$GATE_EXIT"
printf 'run/v1|ev=step|n=9|delivered=no|at=2026-11-01T00:00:22Z\n' >> "$GL"; gate
expect_eq "at 14 a step 9 not delivered owes its delivery, no Step 9 line asked for" "2|owed at 14: Step 9's delivery|no" "$GATE_EXIT|$(owed14 "Step 9's delivery")|$(contains "$GATE_SAID" "has no 'Step 9:' line")"
# The doctrine grows on the person's approval, asked of the run at 14 and at 15; at 15 the row's read stays unseen beside it.
mkdir -p "$R/payload/.claude-plugin" "$R/agents"; printf '{"name": "bionic"}\n' > "$R/payload/.claude-plugin/plugin.json"; printf 'a\n' > "$R/agents/a.md"; git -C "$R" add payload agents; git -C "$R" -c user.name=f -c user.email=f@x.invalid -c core.hooksPath=/dev/null commit -q -m set; printf 'ab\n' > "$R/agents/a.md"; git -C "$R" add agents/a.md
nz() { gate; for w in 'no reads cell' 'no approval of doctrine-growth' 'no .## Tasks. row owns'; do printf '%s\n' "$GATE_SAID" | /usr/bin/grep -q "Not admitted: .*$w" && printf 'y' || printf 'n'; done; }
for c in "$P2|$L2|yyn" "$GP|$GL|nyy"; do IFS='|' read -r p l w <<< "$c"; printf 'plan=%s\n' "$p" > "$R/.bionic/tmp/engaged-$SID.state"; A="$(nz)"; printf 'run/v1|ev=approval|key=doctrine-growth|by=f|said=yes|at=2026-11-01T00:00:14Z\n' >> "$l"
  expect_eq "growth of the loaded set at ${p##*/} names the approval while the run holds none, and not once it does" "$w|${w:0:1}n${w:2:1}" "$A|$(nz)"; done

finish
