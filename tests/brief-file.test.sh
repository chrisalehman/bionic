#!/bin/bash
# tests/brief-file.test.sh — `session-poker.sh brief <row> [<name>]`: the dispatch brief rendered whole.
#
# The brief is one file per dispatch, record/<wave>/briefs/<name>.md, rendered from the row, the task's own
# section of the plan (a heading whose first word is the row id) and the reader's answers. Nothing in it is
# typed into the brief: the judgment is the section's, the review range, the Questions and Lands-red are the
# reader's, and every verb the file names is one the verb listing holds.
#
#   §RENDER  a review brief's range starts at the last proof's head; the Questions and Lands-red are rendered;
#            a row's section is its judgment, and a row with none is marked absent in words; every verb the
#            file names is listed; a section naming no verb, or typing a contract label, is refused with
#            nothing written; a brief this verb did not render is never rewritten.
#
# FIXTURE FIDELITY. The session-poker prelude's sandbox (an engaged, bound session in a scratch repository),
# a version-14 Tasks table, real commits on the working branch for the proof heads, and a planted run log the
# reader reads alone. SYNTHESIZED: the sections and the log lines.
#
# ANTI-VACUITY. Every absence sits beside a positive read through the same extractor on the same file.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

section "§RENDER: the brief is the row, its section and the reader's answers, and nothing typed"
BR="$(make_repo brief-render)"; git -C "$BR" config user.name "Dana Fixture"; git -C "$BR" config user.email d@example.com
cm() { git -C "$BR" commit -q --allow-empty -m "$1" && git -C "$BR" rev-parse HEAD; }
( cd "$BR" && git checkout -q -b wave/01-fixture )
O="$(cm old)"; A="$(cm a)"; B="$(cm b)"; C="$(cm c)"; HD="$(cm head)"
REC="$BR/.bionic/docs/record/wave-01-fixture"; BD="$REC/briefs"; mkdir -p "$BD"
BP="$BR/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"; mkdir -p "${BP%/*}"
{ printf -- '---\nrigor: double\nscale: wave\nworking-branch: wave/01-fixture\nbase-sha: %s\n---\n\n# fixture\n\n' "${O:0:9}"
  printf '## SDLC State\n\ncurrent: 4\n\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | the build with a section | — | — | 30 | REQ-1 | lib/a.sh, tests/a.test.sh | pending | — |\n'
  printf '| T2 | 4 | build | the build with none | — | — | 30 | REQ-1 | lib/b.sh, tests/b.test.sh | pending | — |\n'
  printf '| T3 | 4 | build | a section naming no verb | — | — | 30 | REQ-1 | lib/c.sh, tests/c.test.sh | pending | — |\n'
  printf '| T4 | 4 | build | a section typing a contract | — | — | 30 | REQ-1 | lib/d.sh, tests/d.test.sh | pending | — |\n'
  printf '| R1 | 6 | review | the critic reads it · questions: adversarial,structure | — | — | 30 | REQ-1 | record/wave-01-fixture/critic-adversarial.md, record/wave-01-fixture/critic-structure.md | pending | — |\n\n'
  printf '## T1 — the build with a section\n\nResearch to read: record/wave-01-fixture/research.md\nRulings: render again with bash /x/hooks/session-poker.sh brief T1 once this section changes.\n\nsuites: a.test.sh, shared.test.sh\n\n'
  printf '## T3 — naming no verb\n\nRun bash /x/hooks/session-poker.sh floor-run first.\n\n'
  printf '## T4 — typing a contract\n\nRe-executes: `cd /tmp/x && bash tests/d.test.sh`\n'
} > "$BP"
bind_marker "$BR" "$BP"
t=2026-11-01T00:00
cat > "$REC/run.log" <<EOF
run/v1|ev=proof|kind=review|head=$O|question=adversarial|result=pass|scope=piece|at=${t}:01Z
run/v1|ev=proof|kind=review|head=$A|question=adversarial|result=flag|scope=piece|at=${t}:02Z
run/v1|ev=proof|kind=review|head=$A|question=structure|result=pass|scope=piece|at=${t}:03Z
run/v1|ev=proof|kind=review|head=$B|question=evidence|result=pass|scope=piece|at=${t}:04Z
run/v1|ev=proof|kind=regression|head=$C|rc=0|at=${t}:05Z
run/v1|ev=admitted|id=d1|row=T1|suite=a.test.sh|token=ext:ci|at=${t}:06Z
EOF
printf '# typed by hand before the brief was rendered\n' > "$BD/T2.md"; cp "$BD/T2.md" "$TMPROOT/T2.before"

poke "$BR" brief R1 w01-R1
expect_eq "R0 the review brief is written under its dispatch name (exit 0)" "0" "$RC"
expect_eq "R1 AC-6.3 its range starts at the last proof's head of its questions and ends at the working head" \
  "Reviewed range: $A..$HD" "$(grep '^Reviewed range:' "$BD/w01-R1.md")"
expect_eq "R2 its Questions are the row's, rendered" "Questions: adversarial, structure" "$(grep '^Questions:' "$BD/w01-R1.md")"

poke "$BR" brief T1 w01-T1
expect_eq "R3 a build row with a section of its own renders (exit 0)" "0" "$RC"
judg() { awk '/^## Judgment/ { f = 1; next } f' "$BD/$1.md"; }
expect_contains "R3b …the section's words are its judgment" "Research to read: record/wave-01-fixture/research.md" "$(judg w01-T1)"
expect_absent "R3c …and its suites line is no judgment line" "suites:" "$(judg w01-T1)"
expect_eq "R3d …it is the contract's Suites, read from the section" "Suites: a.test.sh, shared.test.sh" "$(grep '^Suites:' "$BD/w01-T1.md")"
expect_eq "R4 the row's admitted red is its Lands-red, with the evidence the writer writes" \
  "Lands-red: a.test.sh until ext:ci|Red-evidence: .bionic/docs/record/wave-01-fixture/w01-T1-red.md" \
  "$(grep '^Lands-red:\|^Red-evidence:' "$BD/w01-T1.md" | tr '\n' '|' | sed 's/|$//')"
expect_absent "R4b …and a row with none has no Lands-red line (beside R4's, the same reader)" "Lands-red:" "$(cat "$BD/w01-R1.md")"

poke "$BR" brief T2
expect_eq "R5 a brief this verb did not render is not rewritten (exit 1)" "1" "$RC"
expect_true "R5b …it is byte for byte as it was" cmp -s "$TMPROOT/T2.before" "$BD/T2.md"
poke "$BR" brief T2 w01-T2
expect_eq "R6 a row with no section renders under its dispatch name (exit 0)" "0" "$RC"
expect_contains "R6b …its judgment marked absent, in words" "NO JUDGMENT: the plan has no section for T2" "$(judg w01-T2)"
expect_contains "R6c …beside the way to give it one" "brief T2 w01-T2" "$(judg w01-T2)"
poke "$BR" brief T2 w01-T2
expect_eq "R6d a second render of a row not yet dispatched replaces its own file (exit 0)" "0" "$RC"

VL="$(bash "$POKER" 2>&1 | sed -n 's/.*session-poker\.sh \([a-z][a-z-]*\).*/\1/p' | sort -u)"
NAMED="$(cat "$BD/w01-T1.md" "$BD/w01-T2.md" "$BD/w01-R1.md" | grep -o 'session-poker\.sh [a-z][a-z-]*' | sed 's/^session-poker\.sh //' | sort -u)"
expect_contains "R7 setup: the verb listing is read" "brief" "$VL"
expect_contains "R7b setup: the rendered briefs name a verb" "brief" "$NAMED"
expect_eq "R7c AC-6.3 every verb a rendered brief names is in the verb listing" "" "$(comm -23 <(printf '%s\n' "$NAMED") <(printf '%s\n' "$VL"))"

poke "$BR" brief T3 w01-T3
expect_eq "R8 a section naming a verb the listing lacks is refused (exit 1)" "1" "$RC"
expect_contains "R8b …the refusal names it" "floor-run" "$OUT"
expect_false "R8c …and nothing is written" test -e "$BD/w01-T3.md"
poke "$BR" brief T4 w01-T4
expect_eq "R9 a section typing a contract label is refused: the contract is rendered (exit 1)" "1" "$RC"
expect_contains "R9b …the refusal names the label" "Re-executes:" "$OUT"
expect_false "R9c …and nothing is written" test -e "$BD/w01-T4.md"
poke "$BR" brief T1 w01-T2
expect_eq "R10 a name another row's dispatch carries is refused (exit 1)" "1" "$RC"
expect_true "R10b …and the row's own file stands" test -s "$BD/w01-T1.md"

finish
