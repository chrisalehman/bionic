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
gate() {  # -> GATE_EXIT, and GATE_SAID: the gate's words on a commit from the repository
  local in
  in="$(jq -n --arg s "$SID" --arg c "$R" '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git commit -m x"}}')"
  GATE_SAID="$(HOME="$HOME_DIR" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 bash "$BIONIC_HOOKS_DIR/bash-walls.sh" <<< "$in" 2>&1 >/dev/null)"
  GATE_EXIT=$?
}
printf 'run/v1|ev=step|n=6|by=f|at=2026-11-01T00:00:01Z\n' > "$GL"
gate
expect_status "a commit at step 6 with no review event in the log is refused" 2 "$GATE_EXIT"
expect_contains "the refusal names the unanswered reading" "evidence: no review, and no waiver" "$GATE_SAID"
for q in evidence adversarial structure; do
  printf 'run/v1|ev=proof|evidence=record/%s.md|head=%s|kind=review|question=%s|reader=r|result=pass|scope=piece|at=2026-11-01T00:00:02Z\n' "$q" "$H" "$q" >> "$GL"
done
gate
expect_status "the same commit with a review event of each question is admitted" 0 "$GATE_EXIT"

# The same run at 15, made by the act from a version-14 plan: judged on what its log holds, and refused naming what it lacks.
P2="$R/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md"; L2="$R/.bionic/docs/record/wave-02-y/run.log"; mkdir -p "$R/.bionic/docs/specs"; : > "$R/.bionic/docs/specs/r.md"
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\nmulti_agent: true\ndeploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | One. | — | — | 30 | REQ-1 | a.sh | — | — | landed |\n\n'
  printf '## SDLC State\n\ncurrent: 6\napproved-by: f 2026-11-01T00:00Z "approved"\n- Step 1: requirements: specs/r.md\n- Step 5: floor green, record/floor.log\n- T1: landed record/generic-evidence.md\n\n'
  printf '## Verification Matrix\n\nstack-health: n/a: no serve\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\nAC-1:\n  fails-when: a planted defect\n  evidence: record/generic-evidence.md\n'
} > "$P2"; printf 'plan=%s\n' "$P2" > "$R/.bionic/tmp/engaged-$SID.state"
gate; S14="$GATE_EXIT ${GATE_SAID%%$'\n'*}"
bash "$BIONIC_SCRIPTS_DIR/payload/scripts/bring-forward.sh" "$P2" >/dev/null; expect_contains "the act wrote the plan at 15" "canonical_sdlc_version: 15" "$(cat "$P2")"
gate; expect_eq "at 15 with no review event, refused as the 14 is, by the same refusal" "$S14" "$GATE_EXIT ${GATE_SAID%%$'\n'*}"
expect_contains "the 14 was refused for the reviews" "2 bionic: commit refused — a review question is unanswered" "$S14"
grep -h 'kind=review' "$GL" >> "$L2"; gate
expect_status "at 15 with each review, still refused: the step's other facts are not in the log" 2 "$GATE_EXIT"
for f in "Step 1's requirements:" "each row's '- T<id>:' evidence line" "each criterion's fails-when:" "the matrix:"; do
  expect_contains "the refusal names what it could not read at 15: $f" "could not be read at 15: $f" "$GATE_SAID"; done
printf 'run/v1|ev=step|n=5|at=2026-11-01T00:00:03Z\n' >> "$L2"; gate
expect_contains "at Step 5 the refusal names the step's line" "could not be read at 15: Step 5's line and its fields" "$GATE_SAID"
# A row's declared red at 15 is judged on the proofs the log holds: owed with none after it, cleared by a later one.
printf 'run/v1|ev=step|n=6|at=2026-11-01T00:00:04Z\nrun/v1|ev=admitted|id=d1|row=T1|suite=a.test.sh|token=ext:gone|at=2026-11-01T00:00:05Z\n' >> "$L2"; gate
expect_contains "at 15 a declared red the log holds, no proof after it, is owed" "a.test.sh: landed red until ext:gone" "$GATE_SAID"
printf 'run/v1|ev=proof|kind=regression|head=%s|evidence=record/floor.log|at=2026-11-01T00:00:06Z\n' "$H" >> "$L2"; gate
expect_eq "…a regression proof after it in the log clears it: the refusal is the facts the log lacks, and names no proof" "could not be read at 15" \
  "$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o 'landed red until\|could not be read at 15\|the proofs that clear' | LC_ALL=C sort -u | paste -sd'|' -)"

finish
