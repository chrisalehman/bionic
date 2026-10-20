#!/bin/bash
# Tests for hooks/session-poker.sh — shard 3 of 4: Sections 56 through 74.
#
# THE SUITE IS FOUR SHARDS (wave-30 T2; design-ledger Δ7, D8). Its governing design, its
# hermetic posture and its clock discipline are written once, in tests/session-poker.test.sh's
# header; the sandbox, the pins and the shared fixture builders are
# tests/session-poker.prelude.sh, sourced below after the framework and the POKER seam.
#
# SPLIT WHERE NO FIXTURE CROSSES. The judge sections share repositories: Section 63 reads the
# ones Sections 57 and 58 build, Section 68 reads 61, 62 and 64, Section 70 reads 61, and
# Section 67 reads 66. So Sections 57 to 70 cannot be parted, and Section 56, whose checks and
# tree helpers 57 to 63 call, opens the shard with them.
#
# Usage: bash tests/session-poker-3.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

# THE SEAM, exactly as tests/session-poker.test.sh offers it, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker-3.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

# THE FILES THIS SHARD'S HOISTED HELPERS READ, NAMED HERE. tests/lib/impact.sh maps a suite
# from its own lines and never follows it into the prelude, so a path a prelude helper
# reads is named by every shard that calls that helper.
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
S31_STOP_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

# ============================================================
section "Section 56 §FACT: a reading is a review proof with a question, a reader, a result and a scope (wave-27 T2; REQ-2 AC-2.1, REQ-1 AC-1.4, REQ-4 AC-4.3; D1, D7)"
# ============================================================
#
# `proof-add review <record> --question <q> --reader <name>` writes the review proof line with
# four more fields, ` question=<q> reader=<name> result=<pass|flag|fail> scope=<piece|whole>`.
# The result and the scope are the record's own flush-left lines, its `question:` line must be the
# operand, and the reader must have a roster row on this machine (any session's roster of the
# project) whose role is a reader role dealt that question. A `structure` record answers every
# check id its checks file names. The head is still the record's `reviewed:` end, and the range
# starts at or before the last proof of THAT question. Every refusal leaves the plan byte-identical.
#
# FIXTURE FIDELITY. The roster rows are the production writer's (`roster_row_fixture`) with one
# key appended by hand, `questions=<q>[,<q>]`: SYNTHESIZED until row T15 teaches the dispatch wall
# to write it (the Interfaces table's roster key); the verb reads it by key, as every roster reader
# does. The checks file is planted in a copy of the hook tree, where the verb resolves it through
# its own lib root, so a case can remove it or empty it; 56g11 holds the shipped one (row T8's) to
# the same reading.
S56_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s56_last() {  # <plan> <kind> [<question>] -> proof_last's answer, from the library itself
  bash -c '. "$1" && proof_last "$2" "$3" "$4"' _ "$S46_LIB" "$1" "$2" "${3:-}" 2>/dev/null
}
R56="$(make_repo s56-fact)"; ( cd "$R56" && git commit -q --allow-empty -m init )
S56_B="$(git -C "$R56" rev-parse HEAD)"
P56="$(s42_plan "$R56" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S56_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P56" > "$P56.tmp" && mv "$P56.tmp" "$P56"
s42_builds_landed "$P56"  # whole reads are registered here, so no build row is open (T45)
( cd "$R56" && git add -f "$P56" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R56/.worktrees/01-fixture" "$S56_B" ) >/dev/null 2>&1
for s56c in 1 2 3 4; do git -C "$R56/.worktrees/01-fixture" commit -q --allow-empty -m "C$s56c" >/dev/null 2>&1; done
S56_C2="$(git -C "$R56/.worktrees/01-fixture" rev-parse HEAD~2)"
S56_C3="$(git -C "$R56/.worktrees/01-fixture" rev-parse HEAD~1)"; S56_C4="$(git -C "$R56/.worktrees/01-fixture" rev-parse HEAD)"
S56_REC="$R56/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S56_REC"
# s56_rec <file> <a> <b> <question> <result> <scope> [<line>...] -> a reading record; a field given
# as - is left out, and each further argument is one more line.
s56_rec() {
  local f="$S56_REC/$1" a="$2" b="$3" q="$4" r="$5" s="$6" l; shift 6
  { printf '# reading\n\n'
    [ "$a" = - ] || printf 'reviewed: %s..%s\n' "$a" "$b"
    [ "$q" = - ] || printf 'question: %s\n' "$q"
    [ "$r" = - ] || printf 'result: %s\n' "$r"
    [ "$s" = - ] || printf 'scope: %s\n' "$s"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\nwhat the reader found\n'; } > "$f"
}
# THE ROSTERS: this session's, and a predecessor's the verb must scan too.
S56_OSID="5f5f5f5f-0000-4000-8000-000000000055"
new_roster "$R56"; roster_header > "$(roster_of "$R56" "$S56_OSID")"
# A row dealt questions carries, in its files=, the records this section registers under its name
# (wave-27 T41: the record must be the reader's own), and no other: a record one roster row names is
# that reader's alone (T45; review pass 16 finding 2). Each case here meets the rule it was written for.
s56_files() { local o="" n; for n in "$@"; do o="${o:+$o,}.bionic/docs/record/wave-01-fixture/$n.md"; done; printf '%s' "$o"; }
s56_row() {  # <roster> <name> <type> [<questions> [<files>]] -> one row appended; no questions key when none
  local r
  if [ $# -ge 4 ]; then
    r="$(roster_row_fixture session="$SID" name="$2" agent_id="a-$2" subagent_type="$3" files="${5-}")"
    printf '%s|questions=%s\n' "$r" "$4"
  else
    roster_row_fixture session="$SID" name="$2" agent_id="a-$2" subagent_type="$3"
  fi >> "$1"
}
S56_RS="$(roster_of "$R56")"; S56_RO="$(roster_of "$R56" "$S56_OSID")"
# The plan's active T2 row names `implementor` as its agent, and with a roster present the commit
# gate asks this session's roster for that name, so it carries the row the dispatch would have.
s56_row "$S56_RS" implementor implementor
s56_row "$S56_RS" w-aud bionic:auditor evidence \
  "$(s56_files ev1 no-reviewed no-question no-result no-scope fine partial other-q ev-fail ev-narrow ev2)"
s56_row "$S56_RS" w-crit bionic:critic adversarial,structure "$(s56_files adv-late adv1 st-crit)"
s56_row "$S56_RS" w-rev bionic:critic structure "$(s56_files st-all st-no-single st-maybe st-bare)"
s56_row "$S56_RS" w-impl bionic:implementor evidence
s56_row "$S56_RS" w-noq bionic:auditor
s56_row "$S56_RO" w-old bionic:critic adversarial "$(s56_files adv2)"
s56_row "$S56_RS" w-two bionic:critic adversarial
s56_row "$S56_RO" w-two bionic:implementor adversarial
expect_regex "56a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S56_C4"
expect_eq "56a0b precondition: a fixture row carries the appended questions key, read by key" "evidence" \
  "$(/usr/bin/grep -F '|name=w-aud|' "$S56_RS" | tr '|' '\n' | sed -n 's/^questions=//p')"
expect_eq "56a0c precondition: …and its role, as the production writer wrote it" "bionic:auditor" \
  "$(/usr/bin/grep -F '|name=w-aud|' "$S56_RS" | tr '|' '\n' | sed -n 's/^subagent_type=//p')"
s34_gate "$R56"
expect_eq "56a0d precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- §FACT-shape (AC-2.1): question, reader, range and result, or refused ----------
s56_rec ev1.md "${S56_B:0:10}" "$S56_C2" evidence pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question evidence --reader w-aud
expect_eq "56a §FACT-shape a whole reading record registers (exit 0)" "0" "$RC"
expect_eq "56a2 …one line added" "1 0;" "$(s42_numstat "$R56")"
expect_regex "56a3 …the proof line with the four reading fields, in the table's order" \
  "^proved: kind=review head=${S56_C2} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/ev1.md question=evidence reader=w-aud result=pass scope=piece$" \
  "$(s46_proved "$P56")"
expect_contains "56a4 …and the success line names them" "question=evidence reader=w-aud result=pass scope=piece" "$OUT"
expect_eq "56a5 proof_last review evidence reads that question's head" "$S56_C2" "$(s56_last "$P56" review evidence)"
expect_eq "56a6 …a question never read reads nothing" "" "$(s56_last "$P56" review adversarial)"
expect_eq "56a7 …and with no question, the last review proof of any question (1.11.0's reading)" "$S56_C2" "$(s56_last "$P56" review)"
s34_gate "$R56"
expect_eq "56a8 …and the next commit is admitted by the real gate" "0" "$GATE_RC"

s56_rec no-reviewed.md - - evidence pass piece
s56_rec no-question.md "$S56_C2" "$S56_C3" - pass piece
s56_rec no-result.md "$S56_C2" "$S56_C3" evidence - piece
s56_rec no-scope.md "$S56_C2" "$S56_C3" evidence pass -
s56_rec fine.md "$S56_C2" "$S56_C3" evidence fine piece
s56_rec partial.md "$S56_C2" "$S56_C3" evidence pass partial
s56_rec other-q.md "$S56_C2" "$S56_C3" adversarial pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/no-reviewed.md --question evidence --reader w-aud
s42_unchanged "56b a record with no reviewed: line" 1 "$P56"
expect_contains "56b2 …naming the line" "reviewed:" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/no-question.md --question evidence --reader w-aud
s42_unchanged "56b3 a record with no question: line" 1 "$P56"
expect_contains "56b4 …naming the line" "question:" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/no-result.md --question evidence --reader w-aud
s42_unchanged "56b5 a record with no result: line" 1 "$P56"
expect_contains "56b6 …naming the line and the set" "no result: line; write result: pass, flag or fail" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/no-scope.md --question evidence --reader w-aud
s42_unchanged "56b7 a record with no scope: line" 1 "$P56"
expect_contains "56b8 …naming the line and the set" "no scope: line; write scope: piece or whole" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/fine.md --question evidence --reader w-aud
s42_unchanged "56b9 AC-2.1 result: fine, outside the set" 1 "$P56"
expect_contains "56b10 …naming the value and the set" "'fine'" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/partial.md --question evidence --reader w-aud
s42_unchanged "56b11 scope: partial, outside the set" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/other-q.md --question evidence --reader w-aud
s42_unchanged "56b12 a record whose question: is not the operand" 1 "$P56"
expect_contains "56b13 …naming both" "question: adversarial" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question style --reader w-aud
s42_unchanged "56b14 a question outside evidence, adversarial, structure" 1 "$P56"
expect_contains "56b15 …naming the three" "evidence, adversarial or structure" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question evidence
s42_unchanged "56b16 --question with no --reader is the usage error" 2 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --reader w-aud
s42_unchanged "56b17 --reader with no --question is the usage error" 2 "$P56"
poke "$R56" proof-add regression record/wave-01-fixture/ev1.md --question evidence --reader w-aud
s42_unchanged "56b18 the reading flags on a floor proof are the usage error" 2 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev1.md --question evidence --reader w-aud --scope whole
s42_unchanged "56b19 …and so is a flag the verb does not take" 2 "$P56"

# A FLAGGED OR FAILING READING IS A FACT TOO: the verb records what the reader found; whether it
# holds is the judge's question (row T9). A whole reading starts at the plan's base (T41, F5).
s56_rec ev-fail.md "${S56_B:0:10}" "$S56_C3" evidence fail whole
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev-fail.md --question evidence --reader w-aud
expect_eq "56c a failing reading registers (exit 0)" "0" "$RC"
expect_contains "56c2 …carrying result=fail scope=whole" \
  "evidence=record/wave-01-fixture/ev-fail.md question=evidence reader=w-aud result=fail scope=whole" "$(s46_proved "$P56" | tail -1)"

# A PLAN BUILT UNDER 1.11.0 STILL WORKS: no --question, today's line and today's range start (the
# last review proof of any question, here the failing evidence reading at C3).
printf '# review\n\nreviewed: %s..%s\n' "$S56_C3" "$S56_C4" > "$S56_REC/legacy.md"
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/legacy.md
expect_eq "56d a review proof with no --question registers as before (exit 0)" "0" "$RC"
expect_regex "56d2 …in 1.11.0's four-field shape" \
  "^proved: kind=review head=${S56_C4} at=[^ ]+ evidence=record/wave-01-fixture/legacy.md$" "$(s46_proved "$P56" | tail -1)"
expect_eq "56d3 …which no question reads as its own" "$S56_C3" "$(s56_last "$P56" review evidence)"

# THE RANGE STARTS AT THAT QUESTION'S LAST PROOF (D1; research §A.4). The adversarial question has
# no proof yet, so its first reading starts at the plan's base, though evidence was read to C3 and
# the legacy review to C4.
s56_rec adv-late.md "$S56_C2" "$S56_C4" adversarial pass piece
s56_rec adv1.md "${S56_B:0:10}" "$S56_C4" adversarial flag whole
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv-late.md --question adversarial --reader w-crit
s42_unchanged "56e a first adversarial reading starting past the plan's base" 1 "$P56"
expect_contains "56e2 …naming the base" "past the plan's base ${S56_B:0:12}" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/adv1.md --question adversarial --reader w-crit
expect_eq "56e3 …and one from the base registers" "0" "$RC"
expect_eq "56e4 proof_last review adversarial reads its head" "$S56_C4" "$(s56_last "$P56" review adversarial)"
s56_rec ev-narrow.md "$S56_C4" "$S56_C4" evidence pass piece
s56_rec ev2.md "$S56_C3" "$S56_C4" evidence pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/ev-narrow.md --question evidence --reader w-aud
s42_unchanged "56e5 an evidence reading past evidence's own last proof, though the last review of any question is at C4" 1 "$P56"
expect_contains "56e6 …naming that proof" "past the last evidence proof ${S56_C3:0:12}" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev2.md --question evidence --reader w-aud
expect_eq "56e7 …and one from it registers" "0" "$RC"

# ---------- §FACT-reader (AC-1.4): a reader never reads its own code ----------
s56_rec adv2.md "$S56_C2" "$S56_C4" adversarial pass piece
s42_snap "$R56" "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader ghost
s42_unchanged "56f AC-1.4 a reader with no roster row on this machine" 1 "$P56"
expect_contains "56f2 …naming the name" "ghost" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev2.md --question evidence --reader w-impl
s42_unchanged "56f3 AC-1.4 a reader whose row is a writer's, though it names the question" 1 "$P56"
expect_contains "56f4 …naming its role" "bionic:implementor" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/ev2.md --question evidence --reader w-noq
s42_unchanged "56f5 a reader role whose row names no questions" 1 "$P56"
expect_contains "56f6 …naming the question it was not dealt" "evidence" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader w-aud
s42_unchanged "56f7 a reader role dealt another question" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader w-two
s42_unchanged "56f8 a name a writer row carries in another session's roster" 1 "$P56"
expect_contains "56f9 …naming the writer role" "bionic:implementor" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader 'w old'
s42_unchanged "56f10 a reader name the space-separated line cannot hold" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/adv2.md --question adversarial --reader w-old
expect_eq "56f11 a reader row in a predecessor session's roster is found (exit 0)" "0" "$RC"
expect_contains "56f12 …and reader= is that row's name" "question=adversarial reader=w-old result=pass scope=piece" \
  "$(s46_proved "$P56" | tail -1)"

# ---------- §FACT-checks (AC-4.3): every structure check answered ----------
S56_IDS="reuse one-site single-job open-closed substitution narrow-interface dependency-direction"
s56_tree() {  # <root> [<checks file body>] -> a copy of the hook tree, the checks file planted when given
  mkdir -p "$1/hooks" "$1/scripts"
  cp "$BIONIC_HOOKS_DIR"/*.sh "$1/hooks/"; cp -R "$BIONIC_HOOKS_DIR/poker" "$1/hooks/poker"   # the dispatcher loads its parts from poker/
  cp -R "$(cd "$BIONIC_HOOKS_DIR/../payload/scripts/lib" && pwd -P)" "$1/scripts/lib"
  cp "$BIONIC_HOOKS_DIR"/../payload/scripts/*.sh "$1/scripts/"
  if [ $# -ge 2 ]; then mkdir -p "$1/context"; printf '%s' "$2" > "$1/context/checks-structure.md"; fi
}
S56_CHECKS="$(printf '# Structure checks\n\n'; for s56i in $S56_IDS; do printf -- '- **%s** — the check, and a failing case.\n' "$s56i"; done)"
s56_tree "$TMPROOT/s56-tree" "$S56_CHECKS"
s56_tree "$TMPROOT/s56-bare"
s56_tree "$TMPROOT/s56-noids" "$(printf '# Structure checks\n\nNo items here.\n')"
s56_checks() {  # <omit id> [<replace line>] -> one check: line per id but <omit id>, then <replace line>
  local i; for i in $S56_IDS; do [ "$i" = "$1" ] || printf 'check: %s PASS nothing to report\n' "$i"; done
  [ -z "${2:-}" ] || printf '%s\n' "$2"
}
S56_ALL="$(s56_checks none)"
expect_eq "56g0 precondition: the planted checks file names seven ids as - **<id>** items" "7" \
  "$(/usr/bin/grep -cE '^- \*\*[a-z-]+\*\*' "$TMPROOT/s56-tree/context/checks-structure.md")"
s56_rec st-all.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$S56_ALL"
s56_rec st-no-single.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$(s56_checks single-job)"
s56_rec st-maybe.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$(s56_checks single-job 'check: single-job MAYBE unsure')"
s56_rec st-bare.md "${S56_B:0:10}" "$S56_C4" structure pass whole "$(s56_checks single-job 'check: single-job PASS')"
S56_POKER_REAL="$POKER"
s42_snap "$R56" "$P56"
POKER="$TMPROOT/s56-tree/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-no-single.md --question structure --reader w-rev
s42_unchanged "56g AC-4.3 a structure record that leaves single-job unanswered" 1 "$P56"
expect_contains "56g2 …naming the id" "single-job" "$OUT"
poke "$R56" proof-add review record/wave-01-fixture/st-maybe.md --question structure --reader w-rev
s42_unchanged "56g3 a check answered outside PASS, FLAG, FAIL, n/a" 1 "$P56"
poke "$R56" proof-add review record/wave-01-fixture/st-bare.md --question structure --reader w-rev
s42_unchanged "56g4 a check answered with no reason" 1 "$P56"
POKER="$TMPROOT/s56-bare/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-all.md --question structure --reader w-rev
s42_unchanged "56g5 a structure reading where the hook's lib root holds no checks file" 1 "$P56"
expect_contains "56g6 …naming the file it read for the ids" "checks-structure.md" "$OUT"
POKER="$TMPROOT/s56-noids/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-all.md --question structure --reader w-rev
s42_unchanged "56g7 a checks file that names no check id" 1 "$P56"
POKER="$TMPROOT/s56-tree/hooks/session-poker.sh"
poke "$R56" proof-add review record/wave-01-fixture/st-all.md --question structure --reader w-rev
expect_eq "56g8 a structure record answering all seven registers (exit 0)" "0" "$RC"
expect_contains "56g9 …as a structure reading by a critic dealt structure alone" "question=structure reader=w-rev result=pass scope=whole" \
  "$(s46_proved "$P56" | tail -1)"
s56_rec st-crit.md "$S56_C4" "$S56_C4" structure flag piece "$S56_ALL"
poke "$R56" proof-add review record/wave-01-fixture/st-crit.md --question structure --reader w-crit
expect_eq "56g10 …and by a critic whose row lists it among two questions" "0" "$RC"
POKER="$S56_POKER_REAL"
# THE SHIPPED CHECKS FILE AND THE VERB AGREE: read through the same function the verb runs.
# RE-POINTED (wave-30 T4; AC-9.5, A-orch-6): the shipped file owes a check: line for `reuse` and
# `one-site` only, the five SOLID checks and over-engineering being findings a reader may raise.
# So it accepts a record answering all seven or those two alone, and refuses one that leaves
# one-site out.
S56_SHIPPED="${BIONIC_HOOKS_DIR}/../payload/context/checks-structure.md"
s56_read() { bash -c '. "$1" && proof_reading "$2" structure "$3"' _ "$S46_LIB" "$1" "$S56_SHIPPED" 2>/dev/null; }
s56_rec st-two.md "${S56_B:0:10}" "$S56_C4" structure pass whole 'check: reuse PASS nothing to report' 'check: one-site PASS nothing to report'
s56_rec st-no-onesite.md "${S56_B:0:10}" "$S56_C4" structure pass whole 'check: reuse PASS nothing to report'
expect_eq "56g11 the shipped checks file accepts a record answering the seven ids" "pass whole ${S56_B:0:10}" "$(s56_read "$S56_REC/st-all.md")"
expect_eq "56g11b …and one answering reuse and one-site alone" "pass whole ${S56_B:0:10}" "$(s56_read "$S56_REC/st-two.md")"
expect_contains "56g12 …and refuses one that leaves one-site unanswered" "leaves one-site unanswered" \
  "$(s56_read "$S56_REC/st-no-onesite.md")"
expect_eq "56h no projection copy is left beside the plan" "" \
  "$(find "$R56/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"
POKE_BOUND="$S56_BOUND_WAS"

# ============================================================
section "Section 57 §JUDGE §WHOLE §WAIVE: facts_state says, per owed fact, whether it holds at a head; waive is the user's act (wave-27 T9; REQ-1 AC-1.2 AC-1.6, REQ-2 AC-2.3 AC-2.4, REQ-3 AC-3.1; D2, D10)"
# ============================================================
#
# `facts_owed <rigor> <scale>` (payload/scripts/lib/proof.sh) deals what a run owes: the floor, and
# one review fact per question for the role the rigor gives it, with a `scope=whole` fact more per
# code question at wave scale. `facts_state <plan> <head>` answers each owed line: covered,
# uncovered and the range nobody read, failing and the evidence that failed, or absent; rc 0 only
# when every line is covered. A question's facts and waivers are one chain in plan order: it holds
# at <head> when its newest link is not a failing fact and that link's head is <head>, or every
# commit past it touches only the docs root. `waive <question> '<reply>'` writes the user's waiver
# through the verb transaction, at the working head.
#
# FIXTURE FIDELITY. The fact lines are written by the production writer, proof.sh `proof_line`
# placed by `proof_add_line`, and waivers by `proof_waiver_line`, not by the verb: §56 holds the
# verb's admission of a reading, and the judge reads plan text whatever wrote it. 57t registers
# through the verb itself. The working branch's commits are real: two code commits, one commit
# under the docs root alone, one code commit. The 57t roster row carries `questions=` appended by
# hand (s56_row): SYNTHESIZED until row T15 teaches the dispatch wall to write it.
S57_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S57_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
R57="$(make_repo s57-judge)"; ( cd "$R57" && git commit -q --allow-empty -m init )
git -C "$R57" config user.name "Dana Fixture"
S57_B="$(git -C "$R57" rev-parse HEAD)"
P57="$(s42_plan "$R57" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S57_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P57" > "$P57.tmp" && mv "$P57.tmp" "$P57"
( cd "$R57" && git add -f "$P57" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R57/.worktrees/01-fixture" "$S57_B" ) >/dev/null 2>&1
S57_WT="$R57/.worktrees/01-fixture"
# HOISTED to tests/session-poker.prelude.sh: s57_commit — Section 64, Sections 66–68, §SEV, §RC-DEFER and §PASS-KEY commit with it.
S57_C1="$(s57_commit "$S57_WT" lib/a.sh C1)"
S57_C2="$(s57_commit "$S57_WT" lib/a.sh C2)"
S57_C3="$(s57_commit "$S57_WT" .bionic/docs/record/wave-01-fixture/note.md C3)"
S57_C4="$(s57_commit "$S57_WT" lib/b.sh C4)"
cp "$P57" "$TMPROOT/s57-clean"
s57_reset() { cp "$TMPROOT/s57-clean" "$P57"; }
s57_add() {  # <plan> <line> -> the line placed by the production placer
  bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$S57_LIB" "$1" "$2" > "$1.new" && mv "$1.new" "$1"
}
s57_fact() {  # <question> <head> <result> <scope> [<plan>] -> a reading line, its evidence named after it
  s57_add "${5:-$P57}" "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" "$6"' \
    _ "$S57_LIB" "$2" "record/wave-01-fixture/$1-$3-$4.md" "$1" "$3" "$4")"
}
s57_floor() {  # <head> [<plan>]
  s57_add "${2:-$P57}" "$(bash -c '. "$1" && proof_line regression "$2" 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log' _ "$S57_LIB" "$1")"
}
s57_waiver() {  # <question> <head>
  s57_add "$P57" "$(bash -c '. "$1" && proof_waiver_line "$2" "$3" "Dana Fixture" 2026-10-04T12:00:00Z "ship it"' _ "$S57_LIB" "$1" "$2")"
}
s57_state() {  # <plan> <head> -> S57_OUT, S57_RC: what facts_state prints and its exit
  S57_OUT="$(bash -c '. "$1" && facts_state "$2" "$3"' _ "$S57_LIB" "$1" "$2" 2>/dev/null)"; S57_RC=$?
}
s57_of() {  # <owed line> -> the state facts_state gave that line (what follows it and a tab)
  printf '%s\n' "$S57_OUT" | F="$1" awk 'index($0, ENVIRON["F"] "\t") == 1 { print substr($0, length(ENVIRON["F"]) + 2); exit }'
}
S57_EV="$(printf 'review\tevidence\tbionic:auditor\tpiece')"
S57_AD="$(printf 'review\tadversarial\tbionic:critic\tpiece')"
S57_ST="$(printf 'review\tstructure\tbionic:critic\tpiece')"
S57_ADW="$(printf 'review\tadversarial\tbionic:critic\twhole')"
S57_STW="$(printf 'review\tstructure\tbionic:critic\twhole')"
s57_all() {  # <state>... -> the six owed lines of this plan, each with the next state
  printf 'regression\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s' "$1" "$S57_EV" "$2" "$S57_AD" "$3" "$S57_ST" "$4" "$S57_ADW" "$5" "$S57_STW" "$6"
}
expect_regex "57a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S57_C4"
expect_eq "57a0b precondition: C3 touches the docs root alone" ".bionic/docs/record/wave-01-fixture/note.md" \
  "$(git -C "$S57_WT" show --name-only --format= "$S57_C3")"
expect_eq "57a0c precondition: …and C4 a tracked path outside it" "lib/b.sh" "$(git -C "$S57_WT" show --name-only --format= "$S57_C4")"
expect_eq "57a0d precondition: the dealing for this plan (double, wave): the floor, three piece reads, two whole reads" \
  "$(printf 'regression\n%s\n%s\n%s\n%s\n%s' "$S57_EV" "$S57_AD" "$S57_ST" "$S57_ADW" "$S57_STW")" \
  "$(bash -c '. "$1" && facts_owed double wave' _ "$S57_LIB")"

# ---------- §JUDGE (AC-2.3): covered, uncovered naming its range, a docs-only tail ----------
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C4" pass piece; done
s57_fact adversarial "$S57_C4" pass whole; s57_fact structure "$S57_C4" pass whole
s57_state "$P57" "$S57_C4"
expect_eq "57a §JUDGE every owed fact read at the head: each owed line, covered" \
  "$(s57_all covered covered covered covered covered covered)" "$S57_OUT"
expect_eq "57a2 …and rc 0" "0" "$S57_RC"
s57_reset; s57_floor "$S57_C4"
s57_fact evidence "$S57_C4" pass piece; s57_fact structure "$S57_C4" pass piece; s57_fact structure "$S57_C4" pass whole
s57_fact adversarial "$S57_C1" pass whole; s57_fact adversarial "$S57_C1" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57b §JUDGE AC-2.3 code landed past the last adversarial head: uncovered, naming the range nobody read" \
  "uncovered	${S57_C1}..${S57_C4}" "$(s57_of "$S57_AD")"
expect_eq "57b2 …the run does not hold (rc 1)" "1" "$S57_RC"
expect_eq "57b3 …while the questions read at the head stay covered" "covered" "$(s57_of "$S57_ST")"
expect_eq "57b4 …and the whole read taken at C1 holds only as far as its question's chain: uncovered over the same range (wave-36 T7; D9: the whole-scope rule is gone)" \
  "uncovered	${S57_C1}..${S57_C4}" "$(s57_of "$S57_ADW")"
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C2" pass piece; done
s57_fact adversarial "$S57_C2" pass whole; s57_fact structure "$S57_C2" pass whole
s57_state "$P57" "$S57_C3"
# C3 is an older head than the floor proof's (C4), so the floor is uncovered from its proof's head (T45; review pass
# 13 F3), with the judge's reason after the range (wave-35 T9); every reading line is covered.
expect_eq "57c §JUDGE a docs-only tail: past the last head only the docs root changed, so every reading line is covered" \
  "$(s57_all "uncovered	${S57_C4}..${S57_C3}	the proved head ${S57_C4:0:7} is not in the history of ${S57_C3:0:12}" covered covered covered covered covered)" "$S57_OUT"
expect_eq "57c2 …rc 1, for the floor alone" "1" "$S57_RC"
s57_state "$P57" "$S57_C4"
expect_eq "57c3 …and one code commit more is uncovered from the same last head" "uncovered	${S57_C2}..${S57_C4}" "$(s57_of "$S57_EV")"
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C1" pass piece; done
s57_state "$P57" "$S57_C3"
expect_eq "57c4 …a tail whose docs commit follows a code commit is not docs-only" "uncovered	${S57_C1}..${S57_C3}" "$(s57_of "$S57_ST")"

# ---------- §JUDGE (AC-2.4): failing, and what clears it ----------
s57_reset; s57_floor "$S57_C4"
s57_fact evidence "$S57_C2" pass piece; s57_fact evidence "$S57_C4" fail piece
s57_state "$P57" "$S57_C4"
expect_eq "57d §JUDGE AC-2.4 the question's newest fact is result=fail: failing, naming its evidence" \
  "failing	record/wave-01-fixture/evidence-fail-piece.md" "$(s57_of "$S57_EV")"
expect_eq "57d2 …rc 1" "1" "$S57_RC"
s57_fact evidence "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57d3 …a later pass over the fix clears it" "covered" "$(s57_of "$S57_EV")"
s57_fact evidence "$S57_C4" flag piece
s57_state "$P57" "$S57_C4"
expect_eq "57d4 …and a flag is not a failure" "covered" "$(s57_of "$S57_EV")"

# ---------- §JUDGE: a waiver ----------
s57_reset; s57_fact evidence "$S57_C4" fail piece; s57_waiver evidence "$S57_C4"
s57_state "$P57" "$S57_C4"
expect_eq "57e §JUDGE a waiver newer than the failing fact covers the question" "covered" "$(s57_of "$S57_EV")"
s57_reset; s57_waiver evidence "$S57_C4"; s57_fact evidence "$S57_C4" fail piece
s57_state "$P57" "$S57_C4"
expect_eq "57e2 …a waiver older than it does not" "failing	record/wave-01-fixture/evidence-fail-piece.md" "$(s57_of "$S57_EV")"
s57_reset; s57_fact evidence "$S57_C2" fail piece; s57_waiver evidence "$S57_C2"
s57_state "$P57" "$S57_C4"
expect_eq "57e3 …a waiver covers its question up to its own head, and code past it is uncovered" \
  "uncovered	${S57_C2}..${S57_C4}" "$(s57_of "$S57_EV")"
s57_reset; s57_waiver structure "$S57_C4"
s57_state "$P57" "$S57_C4"
expect_eq "57e4 …a waiver alone covers its question at its head" "covered" "$(s57_of "$S57_ST")"
expect_eq "57e5 …and its whole read, which the user waived with the question" "covered" "$(s57_of "$S57_STW")"

# ---------- §JUDGE: absent ----------
s57_reset; s57_floor "$S57_C4"; s57_fact evidence "$S57_C4" pass piece
s57_add "$P57" "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z record/wave-01-fixture/old.md' _ "$S57_LIB" "$S57_C4")"
s57_state "$P57" "$S57_C4"
expect_eq "57f §JUDGE a question with no fact and no waiver is absent" "absent" "$(s57_of "$S57_ST")"
expect_eq "57f2 …a review line carrying no question (1.11.0's) answers no question" "absent" "$(s57_of "$S57_AD")"
expect_eq "57f3 …while the question that has a fact is judged" "covered" "$(s57_of "$S57_EV")"
expect_eq "57f4 …and the floor is proof_state's answer: the floor proof names the working head, covered" "covered" "$(s57_of regression)"
s57_reset; s57_fact evidence "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57f5 …with no floor proof the floor is absent" "absent" "$(s57_of regression)"
sed '/^rigor: /d' "$P57" > "$TMPROOT/s57-norigor.plan.md"
s57_state "$TMPROOT/s57-norigor.plan.md" "$S57_C4"
expect_eq "57f6 a plan whose rigor cannot be read is judged nothing: rc 2" "2" "$S57_RC"
expect_eq "57f7 …and no line is printed for it" "" "$S57_OUT"

# ---------- §WHOLE (AC-1.6): piece facts alone do not hold a wave ----------
# A proof line carries no range start, so the judge cannot see what a `scope=whole` reading read:
# it takes the line as the verb wrote it, and relies on the verb (row T41) refusing a whole read
# whose range starts after the plan's base-sha. 57w8 pins the answer on a planted whole line.
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C4" pass piece; done
s57_state "$P57" "$S57_C4"
expect_eq "57w §WHOLE AC-1.6 a wave with piece facts and no scope=whole fact: every piece covered, each whole read absent" \
  "$(s57_all covered covered covered covered absent absent)" "$S57_OUT"
expect_eq "57w2 …so the run does not hold (rc 1)" "1" "$S57_RC"
s57_fact adversarial "$S57_C4" pass whole
s57_state "$P57" "$S57_C4"
expect_eq "57w3 …a whole read of one code question covers that line alone" "covered absent" \
  "$(s57_of "$S57_ADW") $(s57_of "$S57_STW")"
s57_fact structure "$S57_C4" fail whole
s57_state "$P57" "$S57_C4"
expect_eq "57w4 …a failing whole read is failing, on the whole line" "failing	record/wave-01-fixture/structure-fail-whole.md" "$(s57_of "$S57_STW")"
expect_eq "57w5 …and on the question's piece line, whose newest fact it is" "failing	record/wave-01-fixture/structure-fail-whole.md" "$(s57_of "$S57_ST")"
s57_reset; s57_floor "$S57_C4"
s57_fact adversarial "$S57_C2" pass whole; s57_fact adversarial "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57w6 D10 a fix landed after the whole read is covered by a piece read" "covered covered" \
  "$(s57_of "$S57_AD") $(s57_of "$S57_ADW")"
s57_reset; s57_fact structure "$S57_C4" pass whole
s57_state "$P57" "$S57_C4"
expect_eq "57w8 a planted scope=whole line, whatever range its record read, is taken as written: the whole read and the piece chain both covered at its head" \
  "covered covered" "$(s57_of "$S57_STW") $(s57_of "$S57_ST")"
expect_eq "57w7 a task-scale dealing owes no whole read" "" \
  "$(bash -c '. "$1" && facts_owed double task' _ "$S57_LIB" | /usr/bin/grep -F whole)"

# ---------- §WAIVE: the verb, through the plan transaction ----------
s57_reset; s42_snap "$R57" "$P57"
poke "$R57" waive adversarial 'Ship it, the fix is one line.'
expect_eq "57v §WAIVE waive writes the waiver (exit 0)" "0" "$RC"
expect_eq "57v2 …one line added" "1 0;" "$(s42_numstat "$R57")"
expect_regex "57v3 …the waiver line: the question, the working head, the git user, the instant and the reply" \
  "^waived: question=adversarial head=${S57_C4} by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \"Ship it, the fix is one line\.\"$" \
  "$(/usr/bin/grep -E '^waived: ' "$P57")"
expect_contains "57v4 …and the success line names it" "question=adversarial head=${S57_C4}" "$OUT"
s57_state "$P57" "$S57_C4"
expect_eq "57v5 …which the judge reads: adversarial covered at the working head" "covered" "$(s57_of "$S57_AD")"
s57_fact adversarial "$S57_C4" fail piece
expect_eq "57v6 …a fact registered after it is placed after it" "waived: proved:" \
  "$(/usr/bin/grep -oE '^(waived|proved):' "$P57" | tr '\n' ' ' | sed 's/ $//')"
s57_state "$P57" "$S57_C4"
expect_eq "57v7 …so a later failing fact is newer than the waiver" "failing	record/wave-01-fixture/adversarial-fail-piece.md" "$(s57_of "$S57_AD")"
poke "$R57" waive structure 'keep C:\new\t as written'
expect_eq "57v7b a reply with backslashes is written (exit 0)" "0" "$RC"
expect_contains "57v7c …byte for byte" '"keep C:\new\t as written"' "$(/usr/bin/grep -F 'waived: question=structure' "$P57")"
s42_snap "$R57" "$P57"
poke "$R57" waive verdict 'Ship it.'
s42_unchanged "57v8 a question outside the set" 1 "$P57"
# MOVED BY WAVE-38 T2 (AC-4.2): the waiver also takes the regression and all four at once (session-poker-5 §WORD).
expect_contains "57v9 …naming the questions it waives: the three, the regression, or all" "evidence, adversarial, structure, regression or all" "$OUT"
poke "$R57" waive adversarial $'two\nlines'
s42_unchanged "57v10 a reply with a line break" 1 "$P57"
poke "$R57" waive adversarial
s42_unchanged "57v11 no reply (the usage error)" 2 "$P57"
poke "$R57" waive adversarial '   '
s42_unchanged "57v12 a blank reply (the usage error)" 2 "$P57"
expect_eq "57v13 no projection copy is left beside the plan" "" \
  "$(find "$R57/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"

# ---------- §TASK: a task-scale plan registers a reading and is judged (the Step-2 assumption) ----------
R57T="$(make_repo s57-task)"; ( cd "$R57T" && git commit -q --allow-empty -m init )
S57T_B="$(git -C "$R57T" rev-parse HEAD)"
P57T="$R57T/.bionic/docs/plans/epic-99-fixture/task-01-fixture.plan.md"
# THE ONE TABLE AT TASK SCALE (wave-31 T24; REQ-1, D2): tests/lib/plan-fixture.sh's plan at
# `scale: task`, `current: 4`, one row in flight. Its base is the Step-4 block's `base-sha:`, where
# the one shape carries it at either scale (A-T24-12); with none, a first reading is refused and the
# judge exits 2 (section 63 pins that twin, its Step-4 key empty).
s57t_task_plan() {  # <plan> <Step-4 base-sha value, or "" for the key alone> -> the plan, with the run's branch and the row's line
  plan_fixture "$1" task "| T1 | 4 | build | the fix | — | — | — | 30 | REQ-1 | lib/fix.sh | — | — | active |" > /dev/null || return 1
  S57T_BASE="$2" awk '
    /^  base-sha: / { print "  base-sha:" (ENVIRON["S57T_BASE"] != "" ? " " ENVIRON["S57T_BASE"] : ""); next }
    { print }
    /^approved-by: / { print "working-branch: task/01-fixture"; print "- T1: the fix, in .worktrees/01-task" }' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
s57t_task_plan "$P57T" "$S57T_B"
expect_eq "57t0a precondition: the fixture is a task-scale plan at current: 4 whose Step-4 base is the init commit" \
  "scale: task|current: 4|  base-sha: $S57T_B" \
  "$(/usr/bin/grep -E '^scale: |^current: |^  base-sha: ' "$P57T" | tr '\n' '|' | sed 's/|$//')"
bound_marker "$R57T" "$SID" "$P57T" >/dev/null 2>&1
( cd "$R57T" && git add -f "$P57T" && git commit -qm plan \
  && git worktree add -q -b task/01-fixture "$R57T/.worktrees/01-task" "$S57T_B" ) >/dev/null 2>&1
S57T_C1="$(s57_commit "$R57T/.worktrees/01-task" lib/fix.sh C1)"
new_roster "$R57T"
s56_row "$(roster_of "$R57T")" w-tcrit bionic:critic evidence,adversarial,structure \
  .bionic/docs/record/task-01-fixture/evidence.md,.bionic/docs/record/task-01-fixture/adversarial.md,.bionic/docs/record/task-01-fixture/structure.md
S57T_REC="$R57T/.bionic/docs/record/task-01-fixture"; mkdir -p "$S57T_REC"
S57T_CHECKS="$(awk '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s); printf "check: %s PASS nothing to report\n", s }' \
  "${BIONIC_HOOKS_DIR}/../payload/context/checks-structure.md")"
for s57q in evidence adversarial structure; do
  { printf 'reviewed: %s..%s\nquestion: %s\nresult: pass\nscope: piece\n' "$S57T_B" "$S57T_C1" "$s57q"
    [ "$s57q" = structure ] && printf '%s\n' "$S57T_CHECKS"; printf '\nwhat the reader found\n'; } > "$S57T_REC/$s57q.md"
done
expect_regex "57t0 precondition: the shipped checks file names check ids the structure record answers" \
  '^check: [a-z-]+ PASS' "$(printf '%s\n' "$S57T_CHECKS" | head -1)"
s34_gate "$R57T"
expect_eq "57t0b precondition: the task-scale fixture plan is admitted by the real commit gate" "0" "$GATE_RC"
for s57q in evidence adversarial structure; do
  poke "$R57T" proof-add review "record/task-01-fixture/$s57q.md" --question "$s57q" --reader w-tcrit
  expect_eq "57t §TASK a task-scale plan registers a $s57q reading through the verb (exit 0)" "0" "$RC"
done
expect_eq "57t2 …three reading lines, at the task branch's head" "3" \
  "$(/usr/bin/grep -cE "^proved: kind=review head=${S57T_C1} .* reader=w-tcrit result=pass scope=piece$" "$P57T")"
s57_floor "$S57T_C1" "$P57T"
s57_state "$P57T" "$S57T_C1"
expect_eq "57t3 …and facts_state judges it by facts_owed single task: the floor and one critic's three questions, covered" \
  "$(printf 'regression\tcovered\nreview\tevidence\tbionic:critic\tpiece\tcovered\nreview\tadversarial\tbionic:critic\tpiece\tcovered\nreview\tstructure\tbionic:critic\tpiece\tcovered')" \
  "$S57_OUT"
expect_eq "57t4 …rc 0" "0" "$S57_RC"
S57T_C2="$(s57_commit "$R57T/.worktrees/01-task" lib/fix.sh C2)"
s57_state "$P57T" "$S57T_C2"
expect_eq "57t5 …and a commit past the readings is uncovered there too" "uncovered	${S57T_C1}..${S57T_C2}" \
  "$(s57_of "$(printf 'review\tadversarial\tbionic:critic\tpiece')")"
POKE_BOUND="$S57_BOUND_WAS"

# ============================================================
section "Section 58 §READING: a reading is one pass, by the reader dealt it, saying what its record says (wave-27 T41; review pass 10 F1 to F6, F8; REQ-2 AC-2.1, REQ-1 AC-1.4, REQ-4 AC-4.3; D1, D7)"
# ============================================================
#
# `proof-add review <record> --question <q> --reader <name>` reads ONE pass of the record: the
# lines from its first `reviewed:` line to the next one, nothing outside them (F1). Each value
# is matched whole against its set, so `pass|whole` never fills a missing scope (F2). The reader
# name is matched byte for byte, its characters `[A-Za-z0-9_-]`, never through awk's escape
# decoding (F3). The record must be the reader row's `deliverable=` or one of its `files=`, on a
# row past `intended` (F4). `scope: whole` starts at the plan's base or before it (F5). A
# structure `result: pass` stands beside no FLAG or FAIL check, a `flag` beside no FAIL (F6).
# A roster value reaches the terminal cleaned (F8). A floor, a task and a plain review proof are
# written exactly as before.
#
# FIXTURE FIDELITY. The roster rows are the production writer's (`roster_row_fixture`) carrying
# `deliverable=` and `files=` as dispatch writes them (a repository-relative path, a comma-joined
# list; one deliverable absolute, as section 21's are), each lineage an `intended` row and then a
# later one, as dispatch-preflight and execution-recorder write them. The `questions=` key is
# appended by hand: SYNTHESIZED until row T15 writes it. The checks file is planted in a copy of
# the hook tree (section 56's `s56_tree`). The plan's base is C1, the branch's first commit, so a
# read from the root commit B starts at an ancestor of the base.
S58_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R58="$(make_repo s58-reading)"
mkdir -p "$R58/tests"; for s58s in a b c; do printf '#!/bin/bash\n' > "$R58/tests/$s58s.test.sh"; done
( cd "$R58" && git add tests && git commit -qm init ) >/dev/null 2>&1
S58_B="$(git -C "$R58" rev-parse HEAD)"
git -C "$R58" worktree add -q -b wave/01-fixture "$R58/.worktrees/01-fixture" "$S58_B" >/dev/null 2>&1
for s58c in 1 2 3 4; do git -C "$R58/.worktrees/01-fixture" commit -q --allow-empty -m "C$s58c" >/dev/null 2>&1; done
S58_C1="$(git -C "$R58/.worktrees/01-fixture" rev-parse HEAD~3)"; S58_C2="$(git -C "$R58/.worktrees/01-fixture" rev-parse HEAD~2)"
S58_C3="$(git -C "$R58/.worktrees/01-fixture" rev-parse HEAD~1)"; S58_C4="$(git -C "$R58/.worktrees/01-fixture" rev-parse HEAD)"
P58="$(s42_plan "$R58" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S58_C1:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P58" > "$P58.tmp" && mv "$P58.tmp" "$P58"
s42_builds_landed "$P58"  # whole reads are registered here, so no build row is open (T45)
( cd "$R58" && git add -f "$P58" && git commit -qm wb ) >/dev/null 2>&1
S58_REC="$R58/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S58_REC"
S58_REL=".bionic/docs/record/wave-01-fixture"
s58_rec() {  # <file> <line>... -> a record, one line per argument, then the reader's prose
  local f="$S58_REC/$1"; shift
  { printf '# reading\n\n'; printf '%s\n' "$@"; printf '\nwhat the reader found\n'; } > "$f"
}
s58_files() { local o="" n; for n in "$@"; do o="${o:+$o,}$S58_REL/$n"; done; printf '%s' "$o"; }
new_roster "$R58"; S58_RS="$(roster_of "$R58")"
s58_row() {  # <name> <type> <status> <questions> <deliverable> <files> -> one row appended
  printf '%s|questions=%s\n' "$(roster_row_fixture session="$SID" name="$1" agent_id="a-$1" subagent_type="$2" \
    status="$3" deliverable="$5" files="$6")" "$4" >> "$S58_RS"
}
roster_row_fixture session="$SID" name=implementor agent_id=a-implementor subagent_type=implementor >> "$S58_RS"
S58_REV_FILES="$(s58_files stack.md rc-pass-flag.md rc-pass-fail.md rc-flag-fail.md rc-flag-flag.md rc-fail-fail.md rc-pass-na.md)"
S58_CRIT_FILES="$(s58_files stack-ok.md stack-one.md w-tail.md w-base.md w-anc.md w-piece-tail.md)"
S58_AUD_FILES="$(s58_files above.md v-pipe.md v-two.md v-scope.md aud-files.md)"
for s58st in intended confirmed; do
  s58_row r-rev bionic:critic "$s58st" structure "$S58_REC/rev.md" "$S58_REV_FILES"
  s58_row r-crit bionic:critic "$s58st" adversarial "$S58_REL/crit.md" "$S58_CRIT_FILES"
  s58_row r-aud bionic:auditor "$s58st" evidence "$S58_REL/aud.md" "$S58_AUD_FILES"
done
s58_row r-int bionic:auditor intended evidence "$S58_REL/int.md" ""
# A planted row whose name carries a dot, its own record, so 58c3 is refused for the character
# alone: before T41 this name and record registered (review pass 16 note 4).
s58_row r.aud bionic:auditor confirmed evidence "$S58_REL/dot.md" ""
s58_row r-tint "$(printf 'bionic:impl\033[31mementor')" confirmed evidence "$S58_REL/tint.md" ""
S58_ALL="$(s56_checks none)"
s56_tree "$TMPROOT/s58-tree" "$S56_CHECKS"
S58_POKER_REAL="$POKER"; S58_POKER_TREE="$TMPROOT/s58-tree/hooks/session-poker.sh"
expect_regex "58a0 precondition: C1 to C4 are 40-hex commits on the working branch" '^[0-9a-f]{40}$' "$S58_C1"
expect_eq "58a0b precondition: the root commit B is C1's parent, so B is an ancestor of the base" "$S58_B" \
  "$(git -C "$R58/.worktrees/01-fixture" rev-parse "$S58_C1~1")"
expect_eq "58a0c precondition: the confirmed r-aud row carries its files= list, read by key" "$S58_AUD_FILES" \
  "$(/usr/bin/grep -F '|status=confirmed|' "$S58_RS" | /usr/bin/grep -F '|name=r-aud|' | tr '|' '\n' | sed -n 's/^files=//p')"
expect_eq "58a0d precondition: …and its deliverable=" "$S58_REL/aud.md" \
  "$(/usr/bin/grep -F '|status=confirmed|' "$S58_RS" | /usr/bin/grep -F '|name=r-aud|' | tr '|' '\n' | sed -n 's/^deliverable=//p')"
s34_gate "$R58"
expect_eq "58a0e precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- §ONE-PASS (F1): a reading record is one pass ----------
# The reviewer's reproduction: the newest pass on top wrote no result, no scope and one FAIL
# check; the older pass below it wrote result: pass, scope: piece and seven PASS checks. From T45
# (review pass 16) a reading record holds one pass, so a stacked record is refused whatever its
# passes hold; T41's "the top pass is read" stays for a plain review proof alone.
s58_rec stack.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "check: reuse FAIL dup" "" \
  "reviewed: ${S58_C1}..${S58_C2}" "question: structure" "result: pass" "scope: piece" "$S58_ALL"
s58_rec above.md "result: pass" "scope: piece" "" "reviewed: ${S58_C1}..${S58_C2}" "question: evidence"
s58_rec stack-ok.md "reviewed: ${S58_C1}..${S58_C3}" "question: adversarial" "result: fail" "scope: piece" "" \
  "reviewed: ${S58_C1}..${S58_C2}" "question: adversarial" "result: pass" "scope: whole"
s58_rec stack-one.md "reviewed: ${S58_C1}..${S58_C3}" "question: adversarial" "result: fail" "scope: piece"
s42_snap "$R58" "$P58"
POKER="$S58_POKER_TREE"
poke "$R58" proof-add review record/wave-01-fixture/stack.md --question structure --reader r-rev
s42_unchanged "58a F1 a top pass with no result: is not given the older pass's result: a stacked record is refused" 1 "$P58"
expect_contains "58a2 …naming the count of its passes (T45)" "holds 2 passes" "$OUT"
POKER="$S58_POKER_REAL"
poke "$R58" proof-add review record/wave-01-fixture/above.md --question evidence --reader r-aud
s42_unchanged "58a3 F1 a result: and scope: above the first reviewed: line are outside the pass" 1 "$P58"
expect_contains "58a4 …naming the line" "no result: line" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/stack-ok.md --question adversarial --reader r-crit
s42_unchanged "58a5 a complete top pass over an older one is refused too: a reading record is one pass (T45)" 1 "$P58"
expect_contains "58a5b …naming the count" "holds 2 passes" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/stack-one.md --question adversarial --reader r-crit
expect_eq "58a5c control: that top pass alone, one pass, registers (exit 0)" "0" "$RC"
expect_contains "58a6 …with its head, result and scope" \
  "proved: kind=review head=${S58_C3} " "$(s46_proved "$P58" | tail -1)"
expect_contains "58a7 …result=fail scope=piece" "reader=r-crit result=fail scope=piece" "$(s46_proved "$P58" | tail -1)"

# ---------- §WHOLE-VALUE (F2): a value is its set's word, whole ----------
s58_rec v-pipe.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass|whole"
s58_rec v-two.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass flag" "scope: piece"
s58_rec v-scope.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass" "scope: piece whole"
s42_snap "$R58" "$P58"
poke "$R58" proof-add review record/wave-01-fixture/v-pipe.md --question evidence --reader r-aud
s42_unchanged "58b F2 result: pass|whole with no scope: line" 1 "$P58"
expect_contains "58b2 …the value is refused against its set, never split into the missing scope" \
  "which is not one of pass, flag or fail" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/v-two.md --question evidence --reader r-aud
s42_unchanged "58b3 F2 result: pass flag, two of the set's words" 1 "$P58"
expect_contains "58b4 …naming the set" "which is not one of pass, flag or fail" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/v-scope.md --question evidence --reader r-aud
s42_unchanged "58b5 F2 scope: piece whole" 1 "$P58"
expect_contains "58b6 …naming the set" "which is not one of piece or whole" "$OUT"

# ---------- §READER-NAME (F3): byte for byte, [A-Za-z0-9_-] ----------
s58_rec aud.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass" "scope: piece"
poke "$R58" proof-add review record/wave-01-fixture/aud.md --question evidence --reader 'r\055aud'
s42_unchanged "58c F3 an escaped name that awk would decode to r-aud" 1 "$P58"
expect_contains "58c2 …naming the characters a reader name may carry" "A-Z, a-z, 0-9, _ and -" "$OUT"
s58_rec dot.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass" "scope: piece"
poke "$R58" proof-add review record/wave-01-fixture/dot.md --question evidence --reader 'r.aud'
s42_unchanged "58c3 a name with a character outside the set, though a reader row carries it and names the record" 1 "$P58"
expect_contains "58c4 …naming the characters" "A-Z, a-z, 0-9, _ and -" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/aud.md --question evidence --reader r-aud
expect_eq "58c5 control: the row's own name registers its deliverable (exit 0)" "0" "$RC"
expect_contains "58c6 …and reader= is the row's name" "question=evidence reader=r-aud result=pass scope=piece" \
  "$(s46_proved "$P58" | tail -1)"

# ---------- §READER-RECORD (F4): the reader's own record, from a row past intended ----------
s58_rec stranger.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass" "scope: piece"
s58_rec aud-files.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: flag" "scope: piece"
s58_rec int.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass" "scope: piece"
s58_rec tint.md "reviewed: ${S58_C1}..${S58_C2}" "question: evidence" "result: pass" "scope: piece"
s42_snap "$R58" "$P58"
poke "$R58" proof-add review record/wave-01-fixture/stranger.md --question evidence --reader r-aud
s42_unchanged "58d F4 a record that is neither the reader's deliverable nor one of its files" 1 "$P58"
expect_contains "58d2 …naming the record" "record/wave-01-fixture/stranger.md" "$OUT"
expect_contains "58d3 …and the rule" "deliverable" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/int.md --question evidence --reader r-int
s42_unchanged "58d4 F4 a reader whose only row is still intended, its deliverable named" 1 "$P58"
expect_contains "58d5 …naming the status" "intended" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/aud-files.md --question evidence --reader r-aud
expect_eq "58d6 control: a record among the row's files= registers (exit 0)" "0" "$RC"
expect_contains "58d7 …as that reader's reading" "evidence=record/wave-01-fixture/aud-files.md question=evidence reader=r-aud result=flag" \
  "$(s46_proved "$P58" | tail -1)"

# ---------- §ROSTER-CLEAN (F8): a roster value reaches the terminal cleaned ----------
s42_snap "$R58" "$P58"
poke "$R58" proof-add review record/wave-01-fixture/tint.md --question evidence --reader r-tint
s42_unchanged "58e F8 a reader name a writer row carries, its subagent_type holding an escape" 1 "$P58"
expect_contains "58e2 …refused as a writer" "which is not a reader role" "$OUT"
expect_absent "58e3 …and the escape character never reaches the terminal" "$(printf '\033')" "$OUT"

# ---------- §WHOLE-READ (F5): scope: whole starts at the plan's base or before it ----------
# adversarial was read to C3 by stack-one.md above, so C3..C4 continues its chain.
s58_rec w-tail.md "reviewed: ${S58_C3}..${S58_C4}" "question: adversarial" "result: pass" "scope: whole"
s58_rec w-piece-tail.md "reviewed: ${S58_C3}..${S58_C4}" "question: adversarial" "result: pass" "scope: piece"
s58_rec w-base.md "reviewed: ${S58_C1:0:10}..${S58_C4}" "question: adversarial" "result: pass" "scope: whole"
s58_rec w-anc.md "reviewed: ${S58_B}..${S58_C4}" "question: adversarial" "result: flag" "scope: whole"
s42_snap "$R58" "$P58"
poke "$R58" proof-add review record/wave-01-fixture/w-tail.md --question adversarial --reader r-crit
s42_unchanged "58f F5 scope: whole over a tail range C3..C4" 1 "$P58"
expect_contains "58f2 …naming the plan's base" "base ${S58_C1:0:12}" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/w-piece-tail.md --question adversarial --reader r-crit
expect_eq "58f3 control: the same tail as scope: piece registers (exit 0)" "0" "$RC"
poke "$R58" proof-add review record/wave-01-fixture/w-base.md --question adversarial --reader r-crit
expect_eq "58f4 control: scope: whole from the base registers (exit 0)" "0" "$RC"
expect_contains "58f5 …as a whole reading" "evidence=record/wave-01-fixture/w-base.md question=adversarial reader=r-crit result=pass scope=whole" \
  "$(s46_proved "$P58" | tail -1)"
poke "$R58" proof-add review record/wave-01-fixture/w-anc.md --question adversarial --reader r-crit
expect_eq "58f6 control: scope: whole from an ancestor of the base registers (exit 0)" "0" "$RC"

# ---------- §RESULT-CHECKS (F6): a structure result the checks bear out ----------
s58_rec rc-pass-flag.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: pass" "scope: piece" \
  "$(s56_checks reuse 'check: reuse FLAG a second copy')"
s58_rec rc-pass-fail.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: pass" "scope: piece" \
  "$(s56_checks one-site 'check: one-site FAIL two sites')"
s58_rec rc-flag-fail.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: flag" "scope: piece" \
  "$(s56_checks one-site 'check: one-site FAIL two sites')"
s58_rec rc-flag-flag.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: flag" "scope: piece" \
  "$(s56_checks reuse 'check: reuse FLAG a second copy')"
s58_rec rc-fail-fail.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: fail" "scope: piece" \
  "$(s56_checks one-site 'check: one-site FAIL two sites')"
s58_rec rc-pass-na.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: pass" "scope: piece" \
  "$(s56_checks substitution 'check: substitution n/a no subtypes')"
s42_snap "$R58" "$P58"
POKER="$S58_POKER_TREE"
poke "$R58" proof-add review record/wave-01-fixture/rc-pass-flag.md --question structure --reader r-rev
s42_unchanged "58g F6 result: pass beside a FLAG check" 1 "$P58"
expect_contains "58g2 …naming the check" "check: reuse FLAG" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/rc-pass-fail.md --question structure --reader r-rev
s42_unchanged "58g3 F6 result: pass beside a FAIL check" 1 "$P58"
expect_contains "58g4 …naming the check" "check: one-site FAIL" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/rc-flag-fail.md --question structure --reader r-rev
s42_unchanged "58g5 F6 result: flag beside a FAIL check" 1 "$P58"
expect_contains "58g6 …naming the check" "check: one-site FAIL" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/rc-flag-flag.md --question structure --reader r-rev
expect_eq "58g7 control: result: flag beside a FLAG check registers (exit 0)" "0" "$RC"
poke "$R58" proof-add review record/wave-01-fixture/rc-fail-fail.md --question structure --reader r-rev
expect_eq "58g8 control: result: fail beside a FAIL check registers (exit 0)" "0" "$RC"
poke "$R58" proof-add review record/wave-01-fixture/rc-pass-na.md --question structure --reader r-rev
expect_eq "58g9 control: result: pass beside PASS and n/a registers (exit 0)" "0" "$RC"
expect_contains "58g10 …from the absolute deliverable's reader, as a pass" \
  "evidence=record/wave-01-fixture/rc-pass-na.md question=structure reader=r-rev result=pass scope=piece" \
  "$(s46_proved "$P58" | tail -1)"
POKER="$S58_POKER_REAL"

# ---------- controls: a floor, a task and a plain review proof are written as before ----------
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture --pre 'floor log' "$P58" "$S58_REC/floor.txt" "$S58_C4" 0 0  # with its run line (wave-37 T4; D7)
printf '# review\n\nreviewed: %s..%s\n' "$S58_C1" "$S58_C4" > "$S58_REC/plain.md"
s42_snap "$R58" "$P58"
poke "$R58" proof-add regression record/wave-01-fixture/floor.txt
expect_eq "58h control: a floor proof registers (exit 0)" "0" "$RC"
expect_regex "58h2 …in its four-field shape" \
  "^proved: kind=regression head=${S58_C4} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/floor\\.txt run=[^ ]+ head=${S58_C4} rc=0$" \
  "$(s46_proved "$P58" | tail -1)"
poke "$R58" proof-add task record/wave-01-fixture/floor.txt
expect_eq "58h3 control: a task proof registers (exit 0)" "0" "$RC"
expect_regex "58h4 …in its four-field shape" \
  "^proved: kind=task head=${S58_C4} at=[^ ]+ evidence=record/wave-01-fixture/floor.txt$" "$(s46_proved "$P58" | tail -1)"
poke "$R58" proof-add review record/wave-01-fixture/plain.md
expect_eq "58h5 control: a review proof with no flags registers (exit 0)" "0" "$RC"
expect_regex "58h6 …in 1.11.0's four-field shape, its record in no reader's row" \
  "^proved: kind=review head=${S58_C4} at=[^ ]+ evidence=record/wave-01-fixture/plain.md$" "$(s46_proved "$P58" | tail -1)"
expect_eq "58i no projection copy is left beside the plan" "" \
  "$(find "$R58/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"
POKE_BOUND="$S58_BOUND_WAS"

# ============================================================
section "Section 59 §RANGE-Q: the tick offers each read row its own range, and a reading returns the row carrying its question (wave-27 T10; REQ-1 AC-1.5, REQ-2 AC-2.3; D4)"
# ============================================================
#
# A double plan carries two read rows: T3 reads `live:head:evidence` (the auditor), T4
# `live:head:adversarial+structure` (the critic). The plan already holds three readings, planted
# in the shape proof_line writes: adversarial at A, structure at B, evidence at B; the working
# branch is at C. The tick offers both rows and prints a RANGE line for each, from the oldest last
# head among that row's own questions: T3 B..C, T4 A..C. Through 1.11.0 there was one range, from
# the last review proof of any question, so T4 would have been offered B..C and A..B never read.
# A reading registered with --question returns to pending the active row carrying that question,
# whatever its record is called: the critic's second adversarial pass is written as adv-2.md, a
# name T4's Files do not hold, and still returns T4 alone. §48 and §49e stay the controls for the
# bare live:head row: its RANGE line and its return by Files are 1.11.0's.
# FIXTURE FIDELITY: §48's repository and worktree shape; the readings are planted lines; the
# roster rows are §58's lineage shape (an `intended` row, then a `confirmed` one, each record the
# reader's deliverable= or one of its files=, as T41's verb requires), the questions key
# SYNTHESIZED until T15 writes it.
S59_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R59="$(make_repo s59-range-q)"; new_roster "$R59"; ( cd "$R59" && git commit -q --allow-empty -m init )
S59_RS="$(roster_of "$R59")"
# HOISTED to tests/session-poker.prelude.sh: S59_REL — the hoisted s59w_q names the record directory with it.
s59_row() {  # <name> <type> <status> <questions> <deliverable> <files> -> one row appended (§58's lineage shape)
  printf '%s|questions=%s\n' "$(roster_row_fixture session="$SID" name="$1" agent_id="a-$1" subagent_type="$2" \
    status="$3" deliverable="$5" files="$6")" "$4" >> "$S59_RS"
}
for s59st in intended confirmed; do
  s59_row w-aud bionic:auditor "$s59st" evidence "$S59_REL/ev.md" ""
  s59_row w-crit bionic:critic "$s59st" adversarial,structure "$S59_REL/adv.md" "$S59_REL/adv-2.md,$S59_REL/str-2.md"
  s59_row w-rev bionic:critic "$s59st" structure "$S59_REL/str-rev.md" ""
done
# A BASE THE JUDGE CAN HOLD (wave-36 T28; D9): live:head asks facts_state, which judges only a plan whose base-sha:
# is a commit, so the Step-4 block names the init commit, not s42_plan's placeholder.
P59="$(s42_plan "$R59" 4 "  worktree: .worktrees/01-fixture
  base-sha: $(git -C "$R59" rev-parse --short=8 HEAD)
  branch: wave/01-fixture")"
# EACH LANDING TOUCHES CODE (wave-36 T28; D9): the judge reads a commit that touches nothing as prose, and a review
# row is ready again only past a commit that owes, so A, B and C each change a.sh.
( cd "$R59" && git worktree add -q -b wave/01-fixture "$R59/.worktrees/01-fixture" \
  && for c in A B C; do printf '%s\n' "$c" >> "$R59/.worktrees/01-fixture/a.sh" \
       && git -C "$R59/.worktrees/01-fixture" add a.sh && git -C "$R59/.worktrees/01-fixture" commit -q -m "landing $c"; done ) >/dev/null 2>&1
S59_A="$(git -C "$R59/.worktrees/01-fixture" rev-parse HEAD~2 2>/dev/null)"
S59_B="$(git -C "$R59/.worktrees/01-fixture" rev-parse HEAD~1 2>/dev/null)"
S59_C="$(git -C "$R59/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
s59_read() {  # <question> <head> <minute> <reader> -> a reading's proof line
  printf 'proved: kind=review head=%s at=2026-10-04T10:%s:00Z evidence=record/wave-01-fixture/%s.md question=%s reader=%s result=pass scope=piece' \
    "$2" "$3" "$1" "$1" "$4"
}
awk -v l1="$(s59_read adversarial "$S59_A" 01 w-crit)" -v l2="$(s59_read structure "$S59_B" 02 w-crit)" \
    -v l3="$(s59_read evidence "$S59_B" 03 w-aud)" '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; print l1; print l2; print l3; wb = 1; next }
  /^- T5: / { print "- T3: the evidence read — record/wave-01-fixture/ev.md"; print "- T4: the adversarial and structure read — record/wave-01-fixture/adv.md" }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
    print "| T3 | 6 | review | the evidence read | auditor | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/ev.md | — | — | pending | approval:plan, live:head:evidence |"
    print "| T4 | 6 | review | the adversarial and structure read | critic | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/adv.md | — | — | pending | approval:plan, live:head:adversarial+structure |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P59" > "$P59.tmp" && mv "$P59.tmp" "$P59"
( cd "$R59" && git add -f "$P59" && git commit -qm "two read rows" ) >/dev/null 2>&1
mkdir -p "$R59/.bionic/docs/record/wave-01-fixture"
expect_eq "59a0 precondition: three readings planted, each with its question" "adversarial structure evidence" \
  "$(/usr/bin/grep -E '^proved: kind=review ' "$P59" | sed 's/.* question=\([a-z]*\) .*/\1/' | tr '\n' ' ' | sed 's/ $//')"
expect_true "59a0b precondition: A, B and C are three commits" test -n "$S59_A" -a "$S59_A" != "$S59_B" -a "$S59_B" != "$S59_C"
s34_gate "$R59"
expect_eq "59a0c precondition: the two-read-row plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- the tick: both rows offered, each with its own range ----------
rm -f "$R59/.bionic/tmp/tick-digest-$SID.state"
poke_pressure "$R59" 8192 1.0 tick
expect_nonempty "59a the tick prints a FILL line (the extractor reads real output)" "$(s47_lines FILL)"
expect_eq "59a2 AC-1.5 both read rows are offered at once" "yes yes" \
  "$(s48_fill_has T3) $(s48_fill_has T4)"
expect_eq "59b §RANGE-Q the evidence row's RANGE line starts at the last evidence reading" \
  "poker: RANGE T3 ${S59_B}..${S59_C} — the review reads what landed past the last review proof, and no more" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T3 ')"
expect_eq "59b2 §RANGE-Q the critic's row starts at the oldest of its two questions, the adversarial reading at A" \
  "poker: RANGE T4 ${S59_A}..${S59_C} — the review reads what landed past the last review proof, and no more" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T4 ')"

# ---------- a reading returns the row carrying its question, and that row alone ----------
poke "$R59" task-set T3 status=active agent=w-aud
expect_eq "59c0 precondition: task-set moves T3 active" "0" "$RC"
poke "$R59" task-set T4 status=active agent=w-crit
expect_eq "59c0b precondition: task-set moves T4 active" "0" "$RC"
printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: pass\nscope: piece\n\nthe second pass\n' "$S59_A" "$S59_C" \
  > "$R59/.bionic/docs/record/wave-01-fixture/adv-2.md"
s42_snap "$R59" "$P59"
poke "$R59" proof-add review record/wave-01-fixture/adv-2.md --question adversarial --reader w-crit
expect_eq "59c the adversarial reading registers (exit 0)" "0" "$RC"
expect_contains "59c2 …with its question" "evidence=record/wave-01-fixture/adv-2.md question=adversarial reader=w-crit" \
  "$(s46_proved "$P59" | tail -1)"
# RE-PINNED BY T43 (review pass 17 F3): T4 carries adversarial AND structure, and structure was
# last read at B, so the adversarial reading at C leaves T4 active under its reader, not offered;
# its structure reading at C (59c6) returns it. Through T10 the first reading returned it at once.
expect_eq "59c3 §RANGE-Q F3 the adversarial reading leaves T4, the row carrying it, active under w-crit while structure is unread at C" \
  "active|w-crit" "$(s48_row "$P59" T4 | awk -F'|' '{ print $12 "|" $5 }')"
expect_eq "59c4 …and leaves the evidence row T3 active under its reader" "active|w-aud" \
  "$(s48_row "$P59" T3 | awk -F'|' '{ print $12 "|" $5 }')"
expect_contains "59c5 …and says T4 waits for its other questions" "T4 stays active until every question it carries is read at ${S59_C:0:12}" "$OUT"
expect_absent "59c5b …and gives no Files advice for it" "its Files name another record" "$OUT"
# A reading by a reader that is not the row's agent never moves it (F3): w-rev's structure reading
# at C leaves T4 active under w-crit; only w-crit's own structure reading returns it.
printf '# reading\n\nreviewed: %s..%s\nquestion: structure\nresult: pass\nscope: piece\n%s\n\nanother reader\n' "$S59_B" "$S59_C" "$S56_ALL" \
  > "$R59/.bionic/docs/record/wave-01-fixture/str-rev.md"
poke "$R59" proof-add review record/wave-01-fixture/str-rev.md --question structure --reader w-rev
expect_eq "59c5c F3 w-rev's structure reading at C registers (exit 0)" "0" "$RC"
expect_eq "59c5d F3 …and never moves T4, which carries structure: still active under w-crit" \
  "active|w-crit" "$(s48_row "$P59" T4 | awk -F'|' '{ print $12 "|" $5 }')"
printf '# reading\n\nreviewed: %s..%s\nquestion: structure\nresult: pass\nscope: piece\n%s\n\nthe structure pass\n' "$S59_B" "$S59_C" "$S56_ALL" \
  > "$R59/.bionic/docs/record/wave-01-fixture/str-2.md"
poke "$R59" proof-add review record/wave-01-fixture/str-2.md --question structure --reader w-crit
expect_eq "59c6 F3 w-crit's structure reading at C registers (exit 0)" "0" "$RC"
expect_eq "59c7 F3 …and with both its questions read at C, T4 returns to pending, its agent cleared" \
  "pending|—" "$(s48_row "$P59" T4 | awk -F'|' '{ print $12 "|" $5 }')"
expect_contains "59c8 …naming the row it returned" "T4 back to pending" "$OUT"
printf '# reading\n\nreviewed: %s..%s\nquestion: evidence\nresult: pass\nscope: piece\n\nthe evidence pass\n' "$S59_B" "$S59_C" \
  > "$R59/.bionic/docs/record/wave-01-fixture/ev.md"
poke "$R59" proof-add review record/wave-01-fixture/ev.md --question evidence --reader w-aud
expect_eq "59d the evidence reading registers (exit 0)" "0" "$RC"
expect_eq "59d2 …and returns T3" "pending" "$(s48_row "$P59" T3 | awk -F'|' '{ print $12 }')"

# ---------- the next tick: the evidence row idle, the critic's row offered from structure's B ----------
rm -f "$R59/.bionic/tmp/tick-digest-$SID.state"
poke_pressure "$R59" 8192 1.0 tick
expect_eq "59e at C the evidence row waits, naming its own question's reading" \
  "poker: WAIT T3 — live:head:evidence: nothing landed past the evidence review proof at ${S59_C:0:12}" \
  "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T3 ')"
# RE-PINNED BY T43 (review pass 17 F3): both of the critic's questions were read at C before it
# went back to pending, so at C it is idle too, and is not offered the range it just read.
expect_eq "59e2 F3 …and the critic's row waits, both its questions read at C" \
  "poker: WAIT T4 — live:head:adversarial+structure: nothing landed past the adversarial+structure review proof at ${S59_C:0:12}" \
  "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T4 ')"
expect_absent "59e3 …and neither idle row has a RANGE line" "poker: RANGE T" "$OUT"

# ---------- review pass 17 F1 (blocker) and F2 through the real tick (wave-27 T43) ----------
# HOISTED to tests/session-poker.prelude.sh: s59_world — §60's world, which §LINE-TELL and §REPORT-RTL build, is built on it.
S59W_T1="| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
# HOISTED to tests/session-poker.prelude.sh: S59W_T5 — the hoisted s60_world plants the floor row with it.
S59W_BARE="| T3 | 6 | review | the bare pass, reads empty | critic | — | 30 | REQ-1 | $S59_REL/review.md | — | — | pending |  |"
# HOISTED to tests/session-poker.prelude.sh: s59w_q — the hoisted s60_world plants a read row with it.
s59w_bare() { printf 'proved: kind=review head=%s at=2026-10-04T09:00:00Z evidence=record/wave-01-fixture/review.md' "$1"; }
# F1: the bare T3 above the adversarial row T4; adversarial read at A, the bare proof at C, head C.
s59_world s59-f1 "$(s59_read adversarial @A 01 w-crit)
$(s59w_bare @C)" "$S59W_T1" "$S59W_BARE" "$(s59w_q T4 adversarial)" "$S59W_T5"
s34_gate "$R59W"
expect_eq "59f0 precondition: the bare-above-read plan is admitted by the real commit gate" "0" "$GATE_RC"
poke_pressure "$R59W" 8192 1.0 tick
expect_nonempty "59f F1 the tick prints a FILL line (the extractor reads real output)" "$(s47_lines FILL)"
expect_eq "59f2 F1 the idle bare T3 waits on nothing landed past its proof, in 1.11.0's words" \
  "poker: WAIT T3 — live:head: nothing landed past the review proof at ${S59W_C:0:12}" \
  "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T3 ')"
expect_eq "59f3 F1 (blocker) …and no longer holds T4: T4 is offered, with its own range A..C" \
  "yes|poker: RANGE T4 ${S59W_A}..${S59W_C} — the review reads what landed past the last review proof, and no more" \
  "$(s48_fill_has T4)|$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T4 ')"
expect_absent "59f4 F1 …and no WAIT line says T3 goes first" "review T3 goes first" "$(s47_lines WAIT)"
# Two bare rows idle together keep 1.11.0's lines byte for byte.
s59_world s59-f1-bare "$(s59w_bare @A)
$(s59w_bare @C)" "$S59W_T1" "$S59W_BARE" \
  "| T4 | 6 | review | a second bare pass | critic | — | 30 | REQ-1 | $S59_REL/r4.md | — | — | pending |  |" "$S59W_T5"
poke_pressure "$R59W" 8192 1.0 tick
expect_eq "59f5 F1 two bare rows idle at C: 1.11.0's two WAIT lines, unchanged" \
  "poker: WAIT T3 — live:head: nothing landed past the review proof at ${S59W_C:0:12}|poker: WAIT T4 — live:head: review T3 goes first" \
  "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T[34] ' | tr '\n' '|' | sed 's/|$//')"
# F2: structure read at B on the first line, adversarial at A on the second, head C: A..C.
s59_world s59-f2 "$(s59_read structure @B 01 w-crit)
$(s59_read adversarial @A 02 w-crit)" "$S59W_T1" "$(s59w_q T3 adversarial+structure)" "$S59W_T5"
poke_pressure "$R59W" 8192 1.0 tick
expect_eq "59f6 F2 the tick's range starts at the older commit, A, whatever the line order" \
  "poker: RANGE T3 ${S59W_A}..${S59W_C} — the review reads what landed past the last review proof, and no more" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T3 ')"
POKE_BOUND="$S59_BOUND_WAS"

# ============================================================
finish
