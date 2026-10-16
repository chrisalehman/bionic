#!/bin/bash
# Tests for hooks/session-poker.sh — shard 5: the verbs wave-38 adds.
#
# THE SUITE IS SHARDS (wave-30 T2; design-ledger Δ7, D8). Its governing design, its hermetic posture and its clock
# discipline are written once, in tests/session-poker.test.sh's header; the sandbox, the pins and the shared fixture
# builders are tests/session-poker.prelude.sh, sourced below after the framework and the POKER seam. Each section
# here builds its own repository, so no fixture crosses a shard.
#
# Usage: bash tests/session-poker-5.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/floor-fixture.sh"

# THE SEAM, exactly as tests/session-poker.test.sh offers it, for RED evidence against a mutated copy without ever
# touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker-5.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

# THE FILES THIS SHARD'S HOISTED HELPERS READ, NAMED HERE (tests/lib/impact.sh maps a suite from its own lines).
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

# ============================================================
section "§WORD: the user's word for the regression — waive regression '<reply>' writes one waived: line the regression judge and the Step-7 wall honour, and waive all '<reply>' writes four in one call (wave-38 T2; REQ-4 AC-4.2)"
# ============================================================
# A question's waiver covers it up to its head; the regression had no such line, so a head the regression could
# not prove waited on a run or on `approve regression-2`. `waive regression '<reply>'` writes
#
#   waived: question=regression head=<working head> by <git user.name> <ISO-UTC> "<reply>"
#
# in the grammar the three questions use (lib/proof.sh `proof_waiver_line`), and `waive all '<reply>'` writes four such
# lines, evidence, adversarial, structure and regression, in one transaction. The judge (lib/proof.sh
# `_proof_floor_judge`, asked by facts_state for `current 7` and `current 8`) reads a regression waiver newer than the
# plan's last regression proof as the regression's newest link, covered to its head; the Step-7 text wall
# (`_eg_refuse_floor_absent`) reads it through `proof_floor_absent`, the one reader of "is there a regression line".
# FIXTURE FIDELITY: §CUR7's shape (session-poker-4): a real repository on `wave/01-fixture` with two suites and
# lib/x.sh, base B and one code commit C; a double wave plan the real gate admits at Steps 6 and 7, bound to this
# session; every fact in the production writer's shape (`proof_line`, `proof_floor_line`). Every move is the real verb.
# fails-when: a gate still refuses at the waived head; the line is not the three questions' grammar; `waive all` writes
# other than four lines.
WD_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
WD_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
RWD="$(make_repo word)"
git -C "$RWD" config user.email t@example.com; git -C "$RWD" config user.name "Dana Fixture"
printf '.bionic\n' > "$RWD/.gitignore"
mkdir -p "$RWD/tests" "$RWD/lib" "$RWD/.bionic/docs/plans" "$RWD/.bionic/docs/record/w38"
printf '#!/bin/bash\nexit 0\n' > "$RWD/tests/a.test.sh"; printf '#!/bin/bash\nexit 0\n' > "$RWD/tests/b.test.sh"
printf 'one\n' > "$RWD/lib/x.sh"
( cd "$RWD" && git add .gitignore tests lib && git commit -qm base && git checkout -q -b wave/01-fixture ) >/dev/null 2>&1
printf 'generic fixture proof\n' > "$RWD/.bionic/docs/record/generic-evidence.md"
WD_B="$(git -C "$RWD" rev-parse HEAD)"
WD_C="$(s57_commit "$RWD" lib/x.sh 'C: a code change after the regression proof')"
PWD8="$RWD/.bionic/docs/plans/wave-x.plan.md"
wd_line() { bash -c '. "$1/proof.sh" && shift && proof_line "$@"' _ "$WD_LIB" "$@"; }
wd_floor() {  # <head> -> a regression proof at <head>, as proof-add floor writes it
  bash -c '. "$1/proof.sh" && proof_floor_line "$2" 2026-10-12T11:00:00Z record/w38/floor.log ""' _ "$WD_LIB" "$1"
}
wd_reads() {  # <head> -> the five readings a double wave plan is dealt, each passing, at <head>
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/evidence.md evidence w-read pass piece
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/adversarial.md adversarial w-read pass piece
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/structure.md structure w-read pass piece
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/adversarial-whole.md adversarial w-read pass whole
  wd_line review "$1" 2026-10-12T12:00:00Z record/w38/structure-whole.md structure w-read pass whole
}
wd_plan() {  # <current> <proof lines> -> PWD8, bound to this session (step lines through 7)
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: %s\nworking-branch: wave/01-fixture\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
    printf -- '- Step 4: dispatched, record/w38/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: wave/01-fixture\n' "$WD_B"
    printf -- '- Step 5: floor, record/w38/floor.log\n'
    printf -- '- Step 6: review at record/w38/review.md\n'
    printf -- '- Step 7: documented at record/w38/docs.md\n  n/a: no decision this run\n'
    printf '%s\n' "$2"
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
    printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
    printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/a.test.sh\n  readback: the line it wrote\n'
  } > "$PWD8"
  bind_marker "$RWD" "$PWD8"
}
wd_judge() {  # -> facts_state's lines for PWD8 at the working branch's ref, `<fact>[-<question>-<scope>] <state>`
  bash -c '. "$1/run.sh" && . "$1/proof.sh" && facts_state "$2" "$3"' _ "$WD_LIB" "$PWD8" "$(git -C "$RWD" rev-parse --verify -q wave/01-fixture)" 2>/dev/null \
    | awk -F'\t' '$1 == "floor" { print "floor " $2; next } $1 == "review" { print $2 "-" $4 " " $5 }'
}
wd_current() { sed -n 's/^current: //p' "$PWD8"; }
WD_ISO='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'

# ---------- waive regression: the one line, and current 7 passes at a head the regression refuses without it ----------
wd_plan 6 "$(wd_floor "$WD_B")
$(wd_reads "$WD_C")"
expect_eq "WD-0 precondition: the regression proof at B, the head at C: the judge reads it uncovered, the readings covered" \
  "floor uncovered|evidence-piece covered" "$(wd_judge | awk 'NR <= 2' | paste -sd'|' -)"
poke "$RWD" current 7
expect_eq "WD-0b precondition: …so current 7 is refused at C (exit 1), the plan at current: 6" "1|6" "$RC|$(wd_current)"
expect_contains "WD-0c …in the judge's words" "uncovered" "$OUT"
poke "$RWD" waive regression '1'
expect_eq "WD-1 AC-4.2 waive regression '1' is admitted (exit 0)" "0" "$RC"
expect_regex "WD-1b …and writes one line in the three questions' grammar: the question, the working head, who, when, the reply" \
  "^waived: question=regression head=${WD_C} by Dana Fixture ${WD_ISO} \"1\"$" "$(/usr/bin/grep -E '^waived: ' "$PWD8")"
expect_contains "WD-1c …and the success line names it" "question=regression head=${WD_C}" "$OUT"
expect_eq "WD-2 AC-4.2 …which the judge reads: the regression covered at C" "floor covered" "$(wd_judge | awk 'NR == 1')"
poke "$RWD" current 7
expect_eq "WD-3 AC-4.2 current 7 passes at the waived head (exit 0), the plan at current: 7" "0|7" "$RC|$(wd_current)"

# ---------- waive all: four lines in one call, and current 8 passes ----------
wd_plan 7 "$(wd_floor "$WD_B")
$(wd_reads "$WD_B")"
expect_eq "WD-4 precondition: every reading and the regression at B, the head at C: the judge reads all six uncovered" \
  "6|0" "$(wd_judge | awk '$2 == "uncovered"' | awk 'END { print NR }')|$(wd_judge | awk '$2 == "covered"' | awk 'END { print NR }')"
poke "$RWD" current 8
expect_eq "WD-4b precondition: …so current 8 is refused at C (exit 1), the plan at current: 7" "1|7" "$RC|$(wd_current)"
poke "$RWD" waive all '1'
expect_eq "WD-5 AC-4.2 waive all '1' is admitted (exit 0)" "0" "$RC"
expect_eq "WD-5b …and writes four lines, evidence, adversarial, structure and regression, each at C with the reply" \
  "evidence ${WD_C} \"1\"|adversarial ${WD_C} \"1\"|structure ${WD_C} \"1\"|regression ${WD_C} \"1\"" \
  "$(/usr/bin/grep -E '^waived: ' "$PWD8" | awk '{ q = $2; h = $3; sub(/^question=/, "", q); sub(/^head=/, "", h); print q " " h " " $NF }' | paste -sd'|' -)"
expect_eq "WD-5c …each in the one grammar" "4" \
  "$(/usr/bin/grep -cE "^waived: question=(evidence|adversarial|structure|regression) head=${WD_C} by Dana Fixture ${WD_ISO} \"1\"$" "$PWD8" | tr -d ' ')"
expect_eq "WD-6 AC-4.2 …which the judge reads: all six covered at C" "6" "$(wd_judge | awk '$2 == "covered"' | awk 'END { print NR }')"
poke "$RWD" current 8
expect_eq "WD-7 AC-4.2 current 8 passes at the waived head (exit 0), the plan at current: 8" "0|8" "$RC|$(wd_current)"

# ---------- what the verb refuses ----------
wd_plan 6 "$(wd_floor "$WD_B")"
cp "$PWD8" "$TMPROOT/wd-before"
poke "$RWD" waive verdict '1'
expect_eq "WD-8 a word outside the five is refused (exit 1), the plan byte-identical" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/wd-before" "$PWD8" && echo same || echo changed)"
expect_contains "WD-8b …naming the five" "evidence, adversarial, structure, regression or all" "$OUT"
POKE_BOUND="$WD_BOUND_WAS"

finish
