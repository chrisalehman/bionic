#!/bin/bash
# tests/plan-page.test.sh — the plan is the person's: what a version-15 plan may hold, judged where it is
# written and read through the one parser of its authored parts (payload/scripts/lib/plan-read.sh).
#
#   §SECTIONS  a version-15 plan holding a verification matrix, a state or a handoff section is refused at
#              the write with the heading's line named; a version-15 plan whose only copy of one is inside a
#              fence is admitted.
#   §ROW       a version-15 Tasks table with a status or an agent cell is refused, naming the cell; its nine
#              authored cells alone are admitted.
#   §KEYS      each header key the version-15 header has no place for is refused on a version-15 plan, the
#              refusal naming it.
#   §TASK      a criterion's Task cell at 15 naming a token no Tasks row carries is refused at the write, naming it and
#              what to write; an id, `9`, a dash or no column is admitted; the reader answers the task from the column at
#              15 and from the block's `task:` line at 14.
#   §GATE      the commit gate (hooks/bash-walls.sh) asks the run's facts for the step's evidence: a run at 15 whose
#              log holds what its older homes said is refused for its reviews, and with its reviews still refused,
#              naming each fact its log lacks.
#              At 15 a step's evidence is asked where it is held, owed while missing and not once it stands; a step
#              pending in an advance's judgment moves the gate only in the advance's own session, and is never held.
#              A page at 15 whose landed tasks stand out of order is admitted: the hook judges its copy with the plan's log.
#   §V14       a plan at 14 is a document and never a run: a new one refused at the write, naming 15; one on disk
#              admitted at the write and the commit, open or closed, under any name, an epic too; a plan at 15 with its
#              log lowered to 14 refused at the write and, lowered by hand or its version line lost by a shell edit, at
#              the commit; a page with no version and no step in a log admitted at the commit; a spec at 14 or 15
#              admitted, at 13 refused; an epic at 15 whose log holds its older homes' facts owes only Step 2's approval.
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
. "$(dirname "$0")/lib/seal-fixture.sh"
HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"
PLAN_READ="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/plan-read.sh"
[ -r "$HOOK" ] && bash -n "$HOOK" || { echo "plan-page: the write hook is missing or does not parse: $HOOK"; exit 1; }

SID="7c1e5b2a-9d40-4f6e-8a31-2b0c9e4d7f15"
R="$(cd "$(mktemp -d)" && pwd -P)"; HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$R" "$HOME_DIR"' EXIT
git -C "$R" init -q .
mkdir -p "$R/.bionic/docs/plans/epic-01-demo" "$R/.bionic/tmp"
: > "$R/.bionic/tmp/engaged-$SID.state"
# The person typed `yes` in this session: its transcript under the scratch home's config and its load record here, the two
# witnesses the approve verb holds an approval's words to (lib/said.sh). Each approve call below names that config.
PP_TX="$HOME_DIR/.claude/projects/$(printf '%s' "$R" | sed 's/[^a-zA-Z0-9]/-/g')/$SID.jsonl"; mkdir -p "${PP_TX%/*}"; : > "$R/.bionic/tmp/loaded-$SID.state"
jq -c '.message.content = "yes"' "$BIONIC_SCRIPTS_DIR/tests/fixtures/transcript-move/typed.jsonl" > "$PP_TX"

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

# write_to <path> <text> -> HOOK_EXIT, and HOOK_SAID: the refusal with its detail (BIONIC_WALL_VERBOSE=1).
write_plan() { write_to "$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$1"; }
write_to() {
  local in
  in="$(jq -n --arg p "$1" --arg c "$2" --arg s "$SID" \
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
write_plan "$(printf '## Tasks\n\n%s\n\nAn example:\n\n```\n## Handoff\n```\n' "$NINE" | page 15)"
expect_status "a fenced ## Handoff is prose, and admitted" 0 "$HOOK_EXIT"
FP="$R/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"; printf '## Tasks\n\n%s\n\n### T1 — a fenced comment\n\nRuling one.\n\n```bash\n# run it like this\n## run\n```\n\nRuling two: never commit.\n' "$NINE" | page 15 > "$FP"
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
done

# A run with a log is read from the log alone, so the plan below holds no proved: line and the planted log holds
# the run's step and, in the admitted twin, its readings: the gate admits on the facts the reader answers.
section "TASK"
# evp <cell|-> -> the Tasks table, then an Eval design whose one criterion names <cell> in its Task column; `-` writes no column.
evp() {
  local h='| Requirement | Approach | Criterion | Eval type | Eval | Fails when |' s='|---|---|---|---|---|---|' r='| REQ-1 | a suite | AC-1 | hermetic | `a.test.sh` | a is red |'
  [ "$1" = - ] || { h="$h Task |"; s="${s}---|"; r="$r $1 |"; }
  printf '## Tasks\n\n%s\n\n## Eval design\n\n%s\n%s\n%s\n' "$NINE" "$h" "$s" "$r"
}
for v in T1 9 — '' -; do write_plan "$(evp "$v" | page 15)"; expect_status "a criterion whose Task is '$v' (- for no column) is admitted" 0 "$HOOK_EXIT"; done
for v in "T99|T99" "T1, 9|9" "T1, T99|T99"; do write_plan "$(evp "${v%|*}" | page 15)"
  expect_status "a criterion whose Task is '${v%|*}' is refused" 2 "$HOOK_EXIT"
  expect_contains "…naming the token no row of the table carries, and what to write" "AC-1: task ${v#*|} names no row in the Tasks table; write a task id the table holds, several joined by commas, or 9 alone for the close" "$HOOK_SAID"
done
ask_task() { bash -c '. "$1" && plan_read_criterion_task "$2"' _ "$PLAN_READ" "$FP"; }
evp T1 | page 15 > "$FP"; expect_eq "at 15 the reader answers a criterion's task from its column" "AC-1	T1" "$(ask_task)"
evp — | page 15 > "$FP"; expect_eq "…and a dash names none" "" "$(ask_task)"

section "GATE"
git -C "$R" -c user.name=f -c user.email=f@x.invalid -c core.hooksPath=/dev/null commit -q --allow-empty -m base
H="$(git -C "$R" rev-parse HEAD)"; GL="$R/.bionic/docs/record/wave-01-x/run.log"
mkdir -p "${GL%/*}"; printf 'proof\n' > "$R/.bionic/docs/record/generic-evidence.md"
gate_as() {  # <session> <a pending step, or nothing> [the tree it commits in] -> GATE_EXIT, and GATE_SAID: the gate's words on a commit from the repository
  local in
  seal_fixture "$(sed -n 's/^plan=//p' "$R/.bionic/tmp/engaged-$1.state" 2>/dev/null)"
  in="$(jq -n --arg s "$1" --arg c "${3:-$R}" '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git commit -m x"}}')"
  GATE_SAID="$(cd "${3:-$R}" && HOME="$HOME_DIR" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$1" BIONIC_DRY_STEP="$2" BIONIC_WALL_VERBOSE=1 bash "$BIONIC_HOOKS_DIR/bash-walls.sh" <<< "$in" 2>&1 >/dev/null)"
  GATE_EXIT=$?
}
gate() { gate_as "$SID" ""; }
for q in evidence adversarial structure; do
  printf 'run/v1|ev=proof|evidence=record/%s.md|head=%s|kind=review|question=%s|reader=r|result=pass|scope=piece|at=2026-11-01T00:00:02Z\n' "$q" "$H" "$q" >> "$GL"
done

# A run at 15 whose log holds what its older homes said: judged on what its log holds, and refused naming what it lacks.
P2="$R/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md"; L2="$R/.bionic/docs/record/wave-02-y/run.log"; mkdir -p "$R/.bionic/docs/specs" "${L2%/*}"; : > "$R/.bionic/docs/specs/r.md"
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 15\nintent: build\nrigor: double\nscale: wave\nmulti_agent: true\ndeploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n\n## Tasks\n\n'
  printf '| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | One. | — | 30 | REQ-1 | a.sh | — |\n\n'
  printf '## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n| REQ-1 | x | AC-1 | unit | e | a planted defect |\n\n'
} > "$P2"; printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$SID.state"
printf 'run/v1|ev=%s|at=2026-11-01T00:00:00Z\n' 'step|n=1' 'step|n=5' 'step|n=6' 'approval|key=step3|by=f|said=approved' 'proof|ac=AC-1|evidence=record/generic-evidence.md' > "$L2"
gate; expect_eq "at 15 with no review event, refused for the reviews" "2 bionic: commit refused — a review question is unanswered (record or waive each review)" "$GATE_EXIT ${GATE_SAID%%$'\n'*}"
expect_contains "…naming the unanswered one" "evidence: no review, and no waiver" "$GATE_SAID"
grep -h 'kind=review' "$GL" >> "$L2"; gate
expect_status "at 15 with each review, still refused: the step's other facts are not in the log" 2 "$GATE_EXIT"
owed() { printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o "owed at 15: $1" | head -1; }
expect_eq "…and owes Step 1's requirements, which a header naming no epic and wave cannot find" "owed at 15: Step 1's requirements" "$(owed "Step 1's requirements")"
expect_absent "…and asks a row's landing and launch of the reader, never naming each row's line as unread" "could not be read at 15: each row's" "$GATE_SAID"
cp "$P2" "$P2.keep"; awk '{ print } /^\| T1 \|/ { t = $0; print; sub(/^\| T1 \|/, "| T2 |", t); sub(/\| build \|/, "| bogus |", t); print t }' "$P2.keep" > "$P2"; gate
expect_eq "at 15 a second row of one id and a row of an unknown kind are refused at the commit, each named" "2|T1: duplicate id|T2: kind bogus" "$GATE_EXIT|$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o 'T1: duplicate id\|T2: kind bogus' | paste -sd'|' -)"
awk '{ print } /^\| T1 \|/ { sub(/^\| T1 \|/, "| T2 |"); print }' "$P2.keep" > "$P2"; printf 'run/v1|ev=dispatch|row=T2|name=w-T2|brief=b|at=2026-11-01T00:00:02Z\n' >> "$L2"; gate
expect_eq "a row the log holds dispatched under a name stands at 15 on its dispatch: the gate names neither it nor an evidence line, and owes the requirements still" "|owed at 15: Step 1's requirements" "$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -oE '(^|[^A-Za-z0-9/])T2([^A-Za-z0-9/]|$)|evidence line' | head -1)|$(owed "Step 1's requirements")"
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
expect_eq "…a regression proof after it in the log clears it: still refused for the facts the log lacks, it names no proof" "2|" "$GATE_EXIT|$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o 'landed red until\|could not be read at 15\|the proofs that clear' | LC_ALL=C sort -u | paste -sd'|' -)"
printf 'run/v1|ev=admitted|id=d2|row=T1|suite=b.test.sh|token=approval:ship|at=2026-11-01T00:00:06Z\n' >> "$L2"; gate; AS="$GATE_SAID"; printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%sZ\n' 'approval|key=ship|by=f' 7 "proof|kind=regression|head=$H|evidence=record/floor-2.log" 8 >> "$L2"; gate
expect_eq "…one held until an approval is owed while the log holds none, and cleared by the approval and a proof after it" "1|0" "$(grep -c 'b.test.sh: landed red until approval:ship' <<< "$AS")|$(grep -c 'b.test.sh: landed red' <<< "$GATE_SAID")"

# Each fact a step owes at 15 is asked where it is held, owed while it is missing and not once it stands.
hdr() { awk -v l="$1" '{ print } /^walk: exempt$/ { print l }' "$P2" > "$P2.t" && mv "$P2.t" "$P2"; }   # <a header line> -> the plan's header gains it
hdr 'epic: epic-01-demo'; hdr 'wave: wave-02-y'; hdr 'environments: mac'; mkdir -p "$R/.bionic/docs/specs/epic-01-demo"
: > "$R/.bionic/docs/specs/epic-01-demo/wave-02-y.requirements.md"; printf 'run/v1|ev=step|n=5|at=2026-11-01T00:00:07Z\n' >> "$L2"; gate
expect_eq "at 5: the regression and the requirements found by the header stand; the environments a walk covered are owed" "||owed at 15: Step 5's environments covered" "$(owed "Step 5's regression")|$(owed "Step 1's requirements")|$(owed "Step 5's environments covered")"
printf 'run/v1|ev=proof|kind=walk|head=%s|evidence=record/generic-evidence.md|environments=mac|at=2026-11-01T00:00:08Z\n' "$H" >> "$L2"; gate
expect_eq "…and stand once the walk's proof names them" "" "$(owed "Step 5's environments covered")"
for c in "2|approval|step1|Step 1's approval" "7|header|adrs: none — no decision this run|Step 7's document" "9|step|delivered=v1|Step 9's delivery"; do
  IFS='|' read -r n k v w <<< "$c"; ev="run/v1|ev=step|n=$n"; [ "$n" != 9 ] || ev="$ev|delivered=no"; printf '%s|at=2026-11-01T00:00:09Z\n' "$ev" >> "$L2"; gate; B="$GATE_EXIT"
  expect_eq "at $n the log lacking it, $w is owed" "owed at 15: $w" "$(owed "$w")"
  case "$k" in approval) ( cd "$R" && git config user.name f && HOME="$HOME_DIR" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_NOW_EPOCH=1793491210 bash "$BIONIC_HOOKS_DIR/session-poker.sh" approve "$v" yes >/dev/null 2>&1 ) ;;
    header) hdr "$v" ;; step) printf 'run/v1|ev=step|n=%s|%s|at=2026-11-01T00:00:10Z\n' "$n" "$v" >> "$L2" ;; esac; gate
  [ "$k" != approval ] || expect_eq "at 2 a commit with no approval of step 1 is refused, and admitted once the approve command gives it" "2|0" "$B|$GATE_EXIT"
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
hdr "working-branch: $(git -C "$R" symbolic-ref --short HEAD)"; L2_SUM="$(cksum < "$L2")"; gate_as closeout-preflight-4243 "$CF"
expect_eq "the close's own session, every other fact standing and its own pending, is admitted at 15: no merge, tree or cleanup owed, no row a 15 lacks" "0|||" "$GATE_EXIT|$(owed "Step 8's merge")|$(owed "Step 8's trees")|$(owed "Step 8's cleanup")"
RQ="$R/.bionic/docs/specs/epic-01-demo/wave-02-y.requirements.md"; mv "$RQ" "$RQ.t"; gate_as closeout-preflight-4243 "$CF"; mv "$RQ.t" "$RQ"
expect_eq "…the log's other asks still made: a requirements record gone is owed beside the close's facts" "2|owed at 15: Step 1's requirements" "$GATE_EXIT|$(owed "Step 1's requirements")"
gate_as "$SID" "$CF"
expect_eq "a real session with the same facts set is judged on the log, nothing held of them" "owed at 15: Step 8's merge|owed at 15: Step 8's trees" "$(owed "Step 8's merge")|$(owed "Step 8's trees")"
expect_eq "nothing pending is appended: the log is as it was" "$L2_SUM" "$(cksum < "$L2")"
for v in "8|delivered=x" "8"$'\n'"approval|key=step3|by=f|said=yes" "8"$'\n'"proof|kind=regression|head=$H|evidence=x" "8"$'\n'"waiver|question=evidence" "8"$'\n'"finding|ref=r.md#1" "8"$'\n'"published|row=T2|commit=$H|kind=hand|by=f" "8"$'\n'"tree|row=T1|path=.worktrees/t9"; do
  gate_as closeout-preflight-4243 "$v"
  expect_eq "a pending line the close does not write is refused by the fold: ${v//$'\n'/ / }" "2|yes" "$GATE_EXIT|$(contains "$GATE_SAID" "the facts pending in closeout-preflight-4243 are refused")"
done
# The doctrine grows on the person's approval, asked of the run, and never from a tree no task owns.
mkdir -p "$R/payload/.claude-plugin" "$R/agents"; printf '{"name": "bionic"}\n' > "$R/payload/.claude-plugin/plugin.json"; printf 'a\n' > "$R/agents/a.md"; git -C "$R" add payload agents; git -C "$R" -c user.name=f -c user.email=f@x.invalid -c core.hooksPath=/dev/null commit -q -m set; printf 'ab\n' > "$R/agents/a.md"; git -C "$R" add agents/a.md
nz() { gate; for w in 'no approval of doctrine-growth' 'no .## Tasks. row owns'; do printf '%s\n' "$GATE_SAID" | /usr/bin/grep -q "Not admitted: .*$w" && printf 'y' || printf 'n'; done; }
printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$SID.state"; A="$(nz)"; printf 'run/v1|ev=approval|key=doctrine-growth|by=f|said=yes|at=2026-11-01T00:00:14Z\n' >> "$L2"
expect_eq "growth of the loaded set names the approval while the run holds none, and not once it does; no task owns the tree" "yy|ny" "$A|$(nz)"
# A task at 15 names the approval it waits on: its page is admitted, approve takes the name, and growth is admitted from its tree.
NW="$(printf '%s\n' "$NINE" '| T2 | 4 | build | the second | T1, approval:D7 | 30 | REQ-1 | b.sh | — |')"; write_plan "$(printf '## Tasks\n\n%s\n' "$NW" | page 15)"; A="$HOOK_EXIT"; write_plan "$(printf '## Tasks\n\n%s\n' "${NW/approval:D7/aproval:D7}" | page 15)"
expect_eq "a page at 15 whose task waits on approval:D7 is admitted; one misspelling it is refused, naming it" "0|2|1" "$A|$HOOK_EXIT|$(grep -c 'T2: dep aproval:D7 names no row' <<< "$HOOK_SAID")"
printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$SID.state"; T3W="$R/.worktrees/50-T3"; git -C "$R" worktree add -q "$T3W" -b wt/t3 2>/dev/null; printf 'ab\n' > "$T3W/agents/a.md"; git -C "$T3W" add agents/a.md
awk '{ print } /^\| T1 \| 4 \| build /{ print "| T3 | 4 | build | Grow. | — | 10 | REQ-1 | agents/a.md | — |" }' "$P2" > "$P2.t" && mv "$P2.t" "$P2"; printf 'run/v1|ev=tree|row=T3|path=.worktrees/50-T3|branch=wt/t3|base=%s|at=2026-11-01T00:00:15Z\n' "$H" >> "$L2"
ap() { ( cd "$R" && HOME="$HOME_DIR" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" CLAUDE_CODE_SESSION_ID="$SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" approve "$1" yes >/dev/null 2>&1 ); printf '%s' "$?"; }; grows() { gate_as "$SID" "" "$T3W"; printf '%s|%s' "$GATE_EXIT$(grep -c 'loaded set grows' <<< "$GATE_SAID")" "$(grep -o 'Not admitted: row T3 does not wait on approval:doctrine-growth\|edit the deps cell of T3 in the plan to: [^ ]*' <<< "$GATE_SAID" | paste -sd'|' -)"; }
hdr "base-sha: $H"; B="$(ap launch)|$(grows)"; sed -i '' 's/| Grow. | — |/| Grow. | approval:doctrine-growth, approval:launch |/' "$P2"
expect_eq "with the approval standing, growth from T3's tree is refused (exit 2) while T3 names no wait on it, saying what to write, and admitted (exit 0) once it does" "1|21|Not admitted: row T3 does not wait on approval:doctrine-growth|edit the deps cell of T3 in the plan to: approval:doctrine-growth|00|" "$B|$(grows)"
expect_eq "approve refuses launch while no task waits on it, takes it once T3 does, and refuses a name none waits on" "1|0|1" "${B%%|*}|$(ap launch)|$(ap nobody)"
# A tree whose name a second row's latest tree also carries is no row's: the gate names both, in the order their trees were set.
cp "$L2" "$L2.k"; printf 'run/v1|ev=tree|row=T1|path=.worktrees/50-T3/|branch=wt/t3|base=%s|at=2026-11-01T00:00:16Z\n' "$H" >> "$L2"; gate_as "$SID" "" "$T3W"; mv "$L2.k" "$L2"
expect_eq "a tree two rows' latest tree events name is judged at current, naming the rows" "evidence-gate: worktree 50-T3 is named by more than one ## Tasks row (T3, T1)" \
  "$(grep -o 'evidence-gate: worktree [^ ]* is named by more than one ## Tasks row ([^)]*)' <<< "$GATE_SAID")"
# A page at 15 whose landed tasks stand out of order is judged with its run's log: the hook names the plan its copy is of.
OL="$R/.bionic/docs/record/wave-01-x/run.log"; mkdir -p "${OL%/*}"; [ ! -f "$OL" ] || mv "$OL" "$OL.kept"
for t in T1 T5 T6 T7; do printf 'run/v1|ev=published|row=%s|commit=%s|kind=queue|by=-|why=-|at=2026-11-01T00:00:0%sZ\n' "$t" "$(printf 'a%.0s' {1..40})" "${t#T}"; done > "$OL"
OT='| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | — | 30 | REQ-1 | a.sh | — |
| T5 | 5 | test | the regression | — | 30 | REQ-1 | r/T5.md | — |
| T6 | 6 | review | the review | — | 30 | REQ-1 | r/T6.md | — |
| T7 | 7 | doc | the release | — | 30 | REQ-1 | CHANGELOG.md | — |
| T8 | 7 | build | the fix | — | 30 | REQ-1 | b.sh | — |
| T9 | 7 | review | the fix read | T8 | 30 | REQ-1 | r/T9.md | — |'
printf '## Tasks\n\n%s\n' "$OT" | page 15 > "$R/ot-copy"
expect_contains "a copy of that page judged with no plan it is of reads every task open, and its order refused" "T7: the release row comes ahead of the review row T9" \
  "$(bash -c '. "$1/units.sh" 2>/dev/null; units_validate "$2"' _ "${PLAN_READ%/*}" "$R/ot-copy")"
write_plan "$(cat "$R/ot-copy")"
expect_status "…the hook names the plan it writes, so the landed tasks are read from its log and the page is admitted" 0 "$HOOK_EXIT"
rm -f "$OL"; [ ! -f "$OL.kept" ] || mv "$OL.kept" "$OL"

# A plan at 14 is an older run's document and never a run: a new one is refused at the write, naming 15; one on disk is
# admitted at the write and at the commit, its run open or closed and under any name; a document that is no plan may
# say 14 or 15.
section "V14"
P3="$R/.bionic/docs/plans/epic-01-demo/wave-03-z.plan.md"; SP="$R/.bionic/docs/specs/epic-01-demo/wave-03-z.spec.md"; mkdir -p "${SP%/*}"
OPEN14="$(printf '%s\n' "$MACHINE" | page 14)"; SHUT14="${OPEN14/current: 4/current: 9
- Step 9: delivered: v1 tagged}"
expect_contains "the closed twin differs in its state alone" "delivered: v1 tagged" "$SHUT14"
printf '%s\n' "$OPEN14" > "$P3"; write_to "$P3" "$OPEN14"
expect_status "a plan at 14 on disk whose run reads open is admitted at the write" 0 "$HOOK_EXIT"
printf '%s\n' "$SHUT14" > "$P3"; write_to "$P3" "$SHUT14"
expect_status "…and so is a closed one" 0 "$HOOK_EXIT"
rm -f "$P3"; write_to "$P3" "$OPEN14"
expect_eq "a new plan at 14 is still refused at the write, naming version 15" "2|1|1" \
  "$HOOK_EXIT|$(grep -c 'a new plan is written at 15' <<< "$HOOK_SAID")|$(grep -c "set 'canonical_sdlc_version: 15'" <<< "$HOOK_SAID")"
for v in 14 15 13; do write_to "$SP" "$(printf '## Design\n\nOne design.\n' | page "$v")"; eval "SPEC$v=\$HOOK_EXIT"; done
expect_eq "a spec at 14 and a spec at 15 are admitted, and one at 13 refused naming the two it may say" "0|0|2|1" "$SPEC14|$SPEC15|$SPEC13|$(grep -c "'14' or '15'" <<< "$HOOK_SAID")"
printf 'plan=%s\n' "$P3" > "$R/.bionic/tmp/engaged-$SID.state"; printf '%s\n' "$OPEN14" > "$P3"; gate
expect_status "a plan at 14 on disk whose run reads open is admitted at the commit" 0 "$GATE_EXIT"
printf '%s\n' "$SHUT14" > "$P3"; gate; S="$GATE_EXIT"; printf '%s\n' "${OPEN14/version: 14/version: 13}" > "$P3"; gate
expect_eq "…and so is a closed one, while the same plan at 13 is refused, naming 15" "0|2|1" "$S|$GATE_EXIT|$(grep -c "set 'canonical_sdlc_version: 15'" <<< "$GATE_SAID")"
for P4 in "$R/.bionic/docs/plans/epic-01-demo/wave-04-w.md" "$R/.bionic/docs/incidents/inc-04/incident.md"; do
  mkdir -p "${P4%/*}"; printf 'plan=%s\n' "$P4" > "$R/.bionic/tmp/engaged-$SID.state"; printf '%s\n' "$OPEN14" > "$P4"; gate
  expect_status "an open plan at 14 under ${P4#"$R"/} is admitted at the commit" 0 "$GATE_EXIT"
  rm -f "$P4"
done
# A page at 15 bound to a session under a name not ending .plan.md is found by no walk and joined to no record, so
# nothing of it is judged under that name: it is refused, its words naming it for its directory.
for P5 in "$R/.bionic/docs/plans/epic-01-demo/wave-05-v.md" "$R/.bionic/docs/incidents/inc-05/incident.md"; do
  case "$P5" in */incidents/*) W5="${P5%/*}/inc-05.plan.md" ;; *) W5="${P5%.md}.plan.md" ;; esac
  mkdir -p "${P5%/*}"; cp "$P2" "$P5"; printf 'plan=%s\n' "$P5" > "$R/.bionic/tmp/engaged-$SID.state"; gate
  expect_eq "a page at 15 bound under ${P5#"$R"/} is refused at the commit, naming it for its directory" "2|1" \
    "$GATE_EXIT|$(grep -c "mv $P5 $W5\$" <<< "$GATE_SAID")"
  rm -f "$P5"
done
# A plan at 15 whose log holds a step stays at 15. A write that lowers its version line is refused at the write; the same
# line lowered by a shell edit meets no write hook, and is refused at the commit. The one header, its value quoted and
# spaced, is handed to both gates, and each names the version it read.
LOW="$(sed 's/^canonical_sdlc_version: 15$/canonical_sdlc_version:  "14"/' "$P2")"
expect_contains "the lowered twin of the plan at 15 differs in its version line" 'canonical_sdlc_version:  "14"' "$LOW"
write_to "$P2" "$LOW"
expect_eq "a write lowering a plan at 15 with its log to 14 is refused, naming the line read and 15" "2|1|1" \
  "$HOOK_EXIT|$(grep -c 'this write declares canonical_sdlc_version: 14' <<< "$HOOK_SAID")|$(grep -c "^Fix: leave 'canonical_sdlc_version: 15'" <<< "$HOOK_SAID")"
cp "$P2" "$P2.w"; printf '%s\n' "$LOW" > "$P2"; printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$SID.state"; gate; mv "$P2.w" "$P2"
expect_eq "…and lowered by hand, its commit is refused, naming the plan, the line read and 15" "2|1|1|1" \
  "$GATE_EXIT|$(grep -c "^Plan: $P2\$" <<< "$GATE_SAID")|$(grep -c 'this plan declares canonical_sdlc_version: 14' <<< "$GATE_SAID")|$(grep -c "^Fix: put the line back to 'canonical_sdlc_version: 15'" <<< "$GATE_SAID")"
# Every other shell edit that takes the line off 15 is refused by the same arm, naming what it found where 15 stood.
EDITS=('/^canonical_sdlc_version: 15$/d' 's/^canonical_sdlc_version: 15$/# &/' 's/^canonical_sdlc_version:/canonical-sdlc-version:/' '1s/^---$/\
---/'); FOUND=('declares no canonical_sdlc_version' 'declares no canonical_sdlc_version' 'declares no canonical_sdlc_version' 'has no header on its first line')
for i in 0 1 2 3; do
  cp "$P2" "$P2.w"; sed -i '' "${EDITS[$i]}" "$P2"; gate; mv "$P2.w" "$P2"
  expect_eq "…and so is its commit after the shell edit ${EDITS[$i]%%$'\n'*}, naming the plan, what it found and 15" "2|1|1|1" \
    "$GATE_EXIT|$(grep -c "^Plan: $P2\$" <<< "$GATE_SAID")|$(grep -c "this plan ${FOUND[$i]}" <<< "$GATE_SAID")|$(grep -c "^Fix: put the line back to 'canonical_sdlc_version: 15'" <<< "$GATE_SAID")"
done
# A page that declares no version and whose log holds no step is none of this lifecycle's: its commit goes through.
NR6="$R/.bionic/docs/plans/epic-01-demo/wave-06-u.plan.md"; sed '/^canonical_sdlc_version: 15$/d' "$P2" > "$NR6"
for P6 in "$SP" "$R/.bionic/docs/plans/epic-01-demo/notes.md" "$NR6"; do
  [ "$P6" = "$NR6" ] || printf '# A page\n\nNo header.\n' > "$P6"; printf 'plan=%s\n' "$P6" > "$R/.bionic/tmp/engaged-$SID.state"; gate
  expect_eq "a page with no version and no step in a log, ${P6#"$R"/}, is admitted at the commit" "0|1" "$GATE_EXIT|$(grep -c "bound plan closed — $P6;" <<< "$GATE_SAID")"
done
rm -f "$NR6" "$R/.bionic/docs/plans/epic-01-demo/notes.md"

# An open epic at 14 is admitted at the write and at the commit of a session bound to it. The same epic at 15, its log
# holding what its older homes said, is admitted at the write, and its commit is refused only for the debt it truly
# owes, named.
git -C "$R" reset -q; EP="$R/.bionic/docs/plans/epic-01-demo/epic.plan.md"; EL="$R/.bionic/docs/record/epic-01-demo/run.log"; mkdir -p "$R/.bionic/docs/specs/epic-01-demo" "${EL%/*}"; : > "$R/.bionic/docs/specs/epic-01-demo/epic.spec.md"
epic() { page "$1" | sed -e '/^wave: /d' -e 's/^scale: wave/scale: epic/'; }
EP14="$(printf '## Waves — shipped\n\n## SDLC State\n\ncurrent: 3\n\n- Step 0: configured at 2026-11-01T00:00:00Z via f "go"\n- Step 2: spec: specs/epic-01-demo/epic.spec.md\n- Step 3: plan: this file; approved-by: f 2026-11-01 "ok"\n\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| E-1 | T1 | discharged | see E-1 | self |\n' | epic 14)"
printf '%s\n' "$EP14" > "$EP"; printf 'plan=%s\n' "$EP" > "$R/.bionic/tmp/engaged-$SID.state"; write_to "$EP" "$EP14"; gate
expect_eq "an open epic at 14 is admitted at the write and at the commit" "0|0" "$HOOK_EXIT|$GATE_EXIT"
printf '## Waves — shipped\n\n## Eval design\n\n| Requirement | Criterion | Eval type | Eval | Fails when | Task |\n|---|---|---|---|---|---|\n| — | E-1 | T1 | — | — | — |\n' | epic 15 > "$EP"
printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%sZ\n' 'approval|key=step0|by=f|said=go' 0 'step|n=0' 0 'step|n=2' 1 'approval|key=step3|by=f|said=ok' 2 'step|n=3' 3 'proof|ac=E-1|auditor=self' 4 > "$EL"
write_to "$EP" "$(cat "$EP")"; gate
expect_eq "the epic at 15: the write is admitted; the commit owes Step 2's approval, which its older homes never held, and no requirements" "0|2|owed at 15: Step 2's approval|" \
  "$HOOK_EXIT|$GATE_EXIT|$(owed "Step 2's approval")|$(owed "Step 1's requirements")"
( cd "$R" && git config user.name f && HOME="$HOME_DIR" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_NOW_EPOCH=1793491210 bash "$BIONIC_HOOKS_DIR/session-poker.sh" approve step2 yes >/dev/null 2>&1 ); gate
expect_status "…and the commit is admitted once the person approves step 2" 0 "$GATE_EXIT"

finish
