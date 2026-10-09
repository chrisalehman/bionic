#!/bin/bash
# Tests for hooks/session-poker.sh — shard 3 of 4: Sections 56 through 73.
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
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

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
poke "$R56" proof-add floor record/wave-01-fixture/ev1.md --question evidence --reader w-aud
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
  cp "$BIONIC_HOOKS_DIR"/*.sh "$1/hooks/"
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
  s57_add "${2:-$P57}" "$(bash -c '. "$1" && proof_line floor "$2" 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log' _ "$S57_LIB" "$1")"
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
  printf 'floor\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s\n%s\t%s' "$1" "$S57_EV" "$2" "$S57_AD" "$3" "$S57_ST" "$4" "$S57_ADW" "$5" "$S57_STW" "$6"
}
expect_regex "57a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S57_C4"
expect_eq "57a0b precondition: C3 touches the docs root alone" ".bionic/docs/record/wave-01-fixture/note.md" \
  "$(git -C "$S57_WT" show --name-only --format= "$S57_C3")"
expect_eq "57a0c precondition: …and C4 a tracked path outside it" "lib/b.sh" "$(git -C "$S57_WT" show --name-only --format= "$S57_C4")"
expect_eq "57a0d precondition: the dealing for this plan (double, wave): the floor, three piece reads, two whole reads" \
  "$(printf 'floor\n%s\n%s\n%s\n%s\n%s' "$S57_EV" "$S57_AD" "$S57_ST" "$S57_ADW" "$S57_STW")" \
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
expect_eq "57b4 …and the whole read, taken once, is not owed again for the later code" "covered" "$(s57_of "$S57_ADW")"
s57_reset; s57_floor "$S57_C4"
for s57q in evidence adversarial structure; do s57_fact "$s57q" "$S57_C2" pass piece; done
s57_fact adversarial "$S57_C2" pass whole; s57_fact structure "$S57_C2" pass whole
s57_state "$P57" "$S57_C3"
# C3 is not the working checkout's head (C4), so the floor, which proof_state judges there, is
# uncovered from its proof's head (T45; review pass 13 F3); every reading line is covered.
expect_eq "57c §JUDGE a docs-only tail: past the last head only the docs root changed, so every reading line is covered" \
  "$(s57_all "uncovered	${S57_C4}..${S57_C3}" covered covered covered covered covered)" "$S57_OUT"
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
expect_eq "57f4 …and the floor is proof_state's answer: the floor proof names the working head, covered" "covered" "$(s57_of floor)"
s57_reset; s57_fact evidence "$S57_C4" pass piece
s57_state "$P57" "$S57_C4"
expect_eq "57f5 …with no floor proof the floor is absent" "absent" "$(s57_of floor)"
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
expect_contains "57v9 …naming the three questions" "evidence, adversarial or structure" "$OUT"
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
mkdir -p "$(dirname "$P57T")"
{
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
  printf 'rigor: single\nscale: task\nmulti_agent: false\nuse_worktree: true\nhas_ui: false\n'
  printf 'walk: exempt\ndeploy_target: n/a\n'
  # A task-scale plan carries its base in the frontmatter (T45, A-orch-56): with none, a first
  # reading is refused and the judge exits 2 (section 63 pins that twin).
  printf 'base-sha: %s\n' "$S57T_B"
  printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
  printf '# fixture task\n\n## SDLC State\n\ncurrent: T1\n%s\nworking-branch: task/01-fixture\n\n' "$SP_APPROVED_LINE"
  printf -- '- T1: the fix, in .worktrees/01-task\n\n'
  printf '## Tasks\n\n| id | intent | rigor | description | status |\n|---|---|---|---|---|\n'
  printf '| T1 | bugfix | single | the fix | active |\n\n'
  printf '## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
  printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
} > "$P57T"
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
  "$(printf 'floor\tcovered\nreview\tevidence\tbionic:critic\tpiece\tcovered\nreview\tadversarial\tbionic:critic\tpiece\tcovered\nreview\tstructure\tbionic:critic\tpiece\tcovered')" \
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
printf 'floor log\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' "$S58_C4" > "$S58_REC/floor.txt"
printf '# review\n\nreviewed: %s..%s\n' "$S58_C1" "$S58_C4" > "$S58_REC/plain.md"
s42_snap "$R58" "$P58"
poke "$R58" proof-add floor record/wave-01-fixture/floor.txt
expect_eq "58h control: a floor proof registers (exit 0)" "0" "$RC"
expect_regex "58h2 …in its four-field shape" \
  "^proved: kind=floor head=${S58_C4} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/floor.txt$" \
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
P59="$(s42_plan "$R59" 4)"
( cd "$R59" && git worktree add -q -b wave/01-fixture "$R59/.worktrees/01-fixture" \
  && for c in A B C; do git -C "$R59/.worktrees/01-fixture" commit -q --allow-empty -m "landing $c"; done ) >/dev/null 2>&1
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
section "Section 60 §MOVED: beside a read after a fix the tick names the rows landed in its range (wave-27 T43; REQ-1 AC-1.5, REQ-2 AC-2.3; D10; A-orch-48, A-orch-71)"
# ============================================================
#
# The structure question already has its `scope=whole` reading, at W = A. T7 (serves REQ-2) and T8
# (serves REQ-4, REQ-5) are fixes that landed after it. The read row T3 reads structure and is offered
# A..C. Beside its RANGE line the tick prints one `MOVED` line per row whose landing merge lies inside
# the range, with the matrix criteria the row serves. A landing is the `merge=` of the row's last
# header in the run's landing record, `<docs-root>/record/<plan name>/landing-proofs.log`, which `land`
# writes (T44). The tick tests membership with git, which it already reads. A landed build row with no
# header (or a merge that is no commit) makes it print `MOVED unknown`, and then the read is the whole
# range. With no whole reading yet the tick prints no `MOVED` line at all.
# FIXTURE FIDELITY: §59's repository shape (s59_world). The landing record is PLANTED in the
# Interfaces table's header shape, with a stamp line under each header, because T44 is not built yet.
S60_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
# HOISTED to tests/session-poker.prelude.sh: S60_T1, S60_T7, S60_T8, s60_whole, s60_world — §LINE-TELL and §REPORT-RTL build §60's world with them.
s60_land() {  # <row> <merge> -> one header line and a stamp line appended to the landing record
  printf 'landed: row=%s branch=wt/01-%s head=%s merge=%s at=2026-10-05T04:00:00Z\nstamp/v1|head=%s|dirty=0|rc=0|at=2026-10-05T03:59:00Z|suites=a.test.sh\n' \
    "$1" "$1" "$2" "$2" "$2" >> "$S60_REC"
}
# HOISTED to tests/session-poker.prelude.sh: s60_tick — §LINE-TELL ticks §60's world with it.
s60_moved() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: MOVED ' | tr '\n' '|' | sed 's/|$//'; }
S60_RANGE_TAIL="— the review reads what landed past the last review proof, and no more"

# Two fixes in one range: T7 at B, T8 at C, past the whole reading at A; T1 landed before it.
s60_world s60-two @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 "$S59W_C"
s60_tick
expect_eq "60a precondition: the read row is offered from the whole reading at A" \
  "poker: RANGE T3 ${S59W_A}..${S59W_C} $S60_RANGE_TAIL" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T3 ')"
expect_eq "60a2 two fixes in one range: a MOVED line for T7 and one for T8, each naming its criteria; T1 is not named" \
  "poker: MOVED T7 — AC-2.1, AC-2.2|poker: MOVED T8 — AC-4.1, AC-5.1" "$(s60_moved)"
# One fix after the whole read: T8's landing sits before the range, so T7 alone is named.
s60_world s60-one @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 "$S60_INIT"
s60_tick
expect_eq "60b one fix after the whole read, the other landed before it: C is a commit no header names, so one MOVED unknown line (re-pinned, wave-27 T34)" \
  "poker: MOVED unknown — 1 commit(s) in the range are no recorded landing" "$(s60_moved)"
# A docs-only tail: the whole reading at C, every row landed by C, and one commit past C no row landed.
s60_world s60-tail @C whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 "$S59W_C"
git -C "$R59W/.worktrees/01-fixture" commit -q --allow-empty -m "a docs-only tail" >/dev/null 2>&1
S60_D="$(git -C "$R59W/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
s60_tick
expect_eq "60c a tail made straight on the working branch: RANGE C..D, and MOVED unknown, never none (re-pinned, wave-27 T34)" \
  "poker: RANGE T3 ${S59W_C}..${S60_D} $S60_RANGE_TAIL|poker: MOVED unknown — 1 commit(s) in the range are no recorded landing" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T3 ')|$(s60_moved)"
# No whole fact yet: the structure reading at A is a piece read. The range prints, and no MOVED line.
s60_world s60-nowhole @A piece
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 "$S59W_C"
s60_tick
expect_eq "60d no whole fact for the question: the RANGE line prints and no MOVED line of any kind" \
  "poker: RANGE T3 ${S59W_A}..${S59W_C} $S60_RANGE_TAIL|" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: RANGE T3 ')|$(s60_moved)"
# The cautious rule: a landed build row with no header, or with a merge that is no commit, makes the
# one line MOVED unknown in place of every MOVED line; T7, which has its record, is not named.
s60_world s60-unknown @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"
s60_tick
expect_eq "60e a landed build row with no landing record: one MOVED unknown line, in place of T7's (re-pinned, wave-27 T34)" \
  "poker: MOVED unknown — 1 commit(s) in the range are no recorded landing" "$(s60_moved)"
s60_world s60-nocommit @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
s60_tick
expect_eq "60f a merge that is no commit here is no landing record: C is unrecorded (re-pinned, wave-27 T34)" \
  "poker: MOVED unknown — 1 commit(s) in the range are no recorded landing" "$(s60_moved)"
# EVERY COMMIT OF THE RANGE IS A RECORDED LANDING, OR NO LIST (wave-27 T34; review pass 30 should-fix
# 1 and 2, A-orch-86). A header with row=—, and a commit made by hand past landings that all have
# headers, each make the one MOVED unknown line; the read is then the whole range.
s60_world s60-dash @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land — "$S59W_C"
s60_tick
expect_eq "60g a landing whose header says row=— is no recorded landing of a row: MOVED unknown" \
  "poker: MOVED unknown — 1 commit(s) in the range are no recorded landing" "$(s60_moved)"
s60_world s60-hand @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 "$S59W_C"
s60_tick
expect_eq "60h precondition: every commit of A..C recorded, the rows are named" \
  "poker: MOVED T7 — AC-2.1, AC-2.2|poker: MOVED T8 — AC-4.1, AC-5.1" "$(s60_moved)"
git -C "$R59W/.worktrees/01-fixture" commit -q --allow-empty -m "made by hand on the working branch" >/dev/null 2>&1
s60_tick
expect_eq "60h2 one more commit made by hand: MOVED unknown, in place of both lines" \
  "poker: MOVED unknown — 1 commit(s) in the range are no recorded landing" "$(s60_moved)"
# THE COST: one `git rev-list` per offered row, and no git process per landing. A shim logs every
# git the tick runs; fifty landings cost the tick the same git calls as two.
S60_SHIM="$TMPROOT/s60-shim"; S60_GITLOG="$TMPROOT/s60-git.log"; mkdir -p "$S60_SHIM"
printf '#!/bin/bash
printf "%%s\\n" "$*" >> %q
exec %q "$@"
' "$S60_GITLOG" "$(command -v git)" > "$S60_SHIM/git"
chmod +x "$S60_SHIM/git"
s60_counted_tick() {  # -> S60_ALL (git calls), S60_RL (rev-list calls) of one tick
  local was="$PATH"
  : > "$S60_GITLOG"; export PATH="$S60_SHIM:$PATH"; s60_tick; export PATH="$was"
  S60_ALL="$(awk 'END { print NR + 0 }' "$S60_GITLOG")"
  S60_RL="$(/usr/bin/grep -c 'rev-list --first-parent ' "$S60_GITLOG" | tr -d ' ')"
}
s60_world s60-cost @A whole
s60_land T1 "$S60_INIT"; s60_land T7 "$S59W_B"; s60_land T8 "$S59W_C"
s60_counted_tick
expect_eq "60i precondition: the shim saw the tick's git calls, and the rows are named" \
  "poker: MOVED T7 — AC-2.1, AC-2.2|poker: MOVED T8 — AC-4.1, AC-5.1" "$(s60_moved)"
expect_ne "60i0 …through the shim" "0" "$S60_ALL"
expect_eq "60i2 two landings in the range: one rev-list for the one offered row" "1" "$S60_RL"
S60_ALL2="$S60_ALL"
# Forty-eight more landed rows, each its own landing, so a cost per landing would show.
awk '{ print } /^\| T8 \| 4 \| build \|/ { for (i = 10; i < 58; i++) printf "| T%d | 4 | build | landing %d | implementor | — | 30 | REQ-1 | x%d.sh | — | — | landed |  |\n", i, i, i }' \
  "$P59W" > "$P59W.tmp" && mv "$P59W.tmp" "$P59W"
for s60n in $(seq 10 57); do
  git -C "$R59W/.worktrees/01-fixture" commit -q --allow-empty -m "landing $s60n" >/dev/null 2>&1
  s60_land "T$s60n" "$(git -C "$R59W/.worktrees/01-fixture" rev-parse HEAD)"
done
expect_eq "60i3 precondition: fifty landings in the record's range" "50" \
  "$(git -C "$R59W" rev-list --first-parent "${S59W_A}..$(git -C "$R59W/.worktrees/01-fixture" rev-parse HEAD)" | awk 'END { print NR }')"
s60_counted_tick
expect_eq "60i4 fifty landings: still one rev-list" "1" "$S60_RL"
expect_eq "60i5 …and the same git calls as two landings: none per landing" "$S60_ALL2" "$S60_ALL"
expect_contains "60i6 …and the rows are named, T7 and T8 first" "poker: MOVED T7 — AC-2.1, AC-2.2|poker: MOVED T8 — AC-4.1, AC-5.1|poker: MOVED T10 — AC-1.1" "$(s60_moved)"
expect_contains "60i7 …through the last of the fifty" "poker: MOVED T57 — AC-1.1" "$(s60_moved)"
POKE_BOUND="$S60_BOUND_WAS"

# ============================================================
section "Section 61 §CUR8 §CUR8-fail §CUR8-rigor: current 8 is admitted on the judge, not on the Step-8 block (wave-27 T14; REQ-2 AC-2.3 AC-2.4, REQ-3 AC-3.1, REQ-7 AC-7.1; D3, D14)"
# ============================================================
#
# `session-poker.sh current 8` no longer dry-commits the plan at Step 8, where the gate asked for
# the Step-8 block close-out writes. It asks lib/proof.sh `facts_state <plan> <working head>` and
# is refused, the plan byte-identical, unless every fact the run owes holds: each line that does
# not is printed as the judge gave it. rc 2 from the judge (a rigor or scale the dealing does not
# know) refuses too, saying so.
#
# FIXTURE FIDELITY. §57's: a plan bound to this session, its working branch checked out in a
# linked worktree, real commits on it. The fact lines are the production writer's (proof.sh
# `proof_line`, `proof_waiver_line`, placed by `proof_add_line`); §56 holds the verb that writes
# readings, and the judge reads plan text whatever wrote it. The plan sits at `current: 7` with no
# Step 8 line and no Step 9 line, the state a run is in before its tools close it.
S61_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S61_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
R61="$(make_repo s61-cur8)"; ( cd "$R61" && git commit -q --allow-empty -m init )
git -C "$R61" config user.name "Dana Fixture"
S61_B="$(git -C "$R61" rev-parse HEAD)"
P61="$(s42_plan "$R61" 7 "  worktree: .worktrees/01-fixture
  base-sha: ${S61_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P61" > "$P61.tmp" && mv "$P61.tmp" "$P61"
( cd "$R61" && git add -f "$P61" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R61/.worktrees/01-fixture" "$S61_B" ) >/dev/null 2>&1
S61_WT="$R61/.worktrees/01-fixture"
S61_C1="$(s57_commit "$S61_WT" lib/a.sh C1)"
s61_add() {  # <line> -> the line placed in P61 by the production placer
  bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$S61_LIB" "$P61" "$1" > "$P61.new" && mv "$P61.new" "$P61"
}
s61_fact() {  # <question> <head> <result> <scope>
  s61_add "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" "$6"' \
    _ "$S61_LIB" "$2" "record/wave-01-fixture/$1-$3-$4.md" "$1" "$3" "$4")"
}
s61_floor() { s61_add "$(bash -c '. "$1" && proof_line floor "$2" 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log' _ "$S61_LIB" "$1")"; }
s61_waiver() { s61_add "$(bash -c '. "$1" && proof_waiver_line "$2" "$3" "Dana Fixture" 2026-10-04T12:00:00Z "ship it"' _ "$S61_LIB" "$1" "$2")"; }
s61_owed() {  # <head> [<question> to leave out] -> the floor and every reading the plan owes, at <head>
  local q
  s61_floor "$1"
  for q in evidence adversarial structure; do [ "$q" = "${2:-}" ] || s61_fact "$q" "$1" pass piece; done
  for q in adversarial structure; do [ "$q" = "${2:-}" ] || s61_fact "$q" "$1" pass whole; done
}
cp "$P61" "$TMPROOT/s61-clean"
s61_reset() { cp "$TMPROOT/s61-clean" "$P61"; }
s61_rigor() { sed "s/^rigor: .*/rigor: $1/" "$P61" > "$P61.tmp" && mv "$P61.tmp" "$P61"; }
s61_cur() { sed -n 's/^current: //p' "$P61"; }
expect_eq "61a0 precondition: the fixture sits at current: 7 with no Step 8 or Step 9 line" "7/0" \
  "$(s61_cur)/$(/usr/bin/grep -cE '^- Step (8|9):' "$P61")"
expect_regex "61a0b precondition: the working branch's head is C1, a 40-hex commit" '^[0-9a-f]{40}$' "$S61_C1"

# ---------- §CUR8 (AC-2.3, AC-7.1): every fact at the head admits; code past a reading refuses ----------
s61_reset; s61_owed "$S61_C1"
poke "$R61" current 8
expect_eq "61a §CUR8 AC-7.1 with every owed fact at the working head, current 8 exits 0 (no Step-8 block asked)" "0" "$RC"
expect_eq "61a2 …and the plan reads current: 8" "8" "$(s61_cur)"
expect_contains "61a3 …saying what admitted it" "every fact the run owes holds at $S61_C1" "$OUT"
expect_eq "61a4 …and no Step 8 line was asked for or written" "0" "$(/usr/bin/grep -cE '^- Step 8:' "$P61")"
S61_C2="$(s57_commit "$S61_WT" lib/b.sh C2)"
s61_reset; s61_owed "$S61_C1"
s42_snap "$R61" "$P61"
poke "$R61" current 8
s42_unchanged "61b §CUR8 AC-2.3 a commit to a tracked file past the last adversarial and structure heads" 1 "$P61"
expect_contains "61b2 …naming the adversarial range nobody read" \
  "$(printf 'review\tadversarial\tbionic:critic\tpiece\tuncovered\t%s..%s' "$S61_C1" "$S61_C2")" "$OUT"
expect_contains "61b3 …and the structure range" \
  "$(printf 'review\tstructure\tbionic:critic\tpiece\tuncovered\t%s..%s' "$S61_C1" "$S61_C2")" "$OUT"
expect_contains "61b4 …saying it is the judge's answer at the working head" \
  "holds at the working head $S61_C2, and these do not (facts_state)" "$OUT"
expect_absent "61b5 …and printing no line that holds (beside 61b2 on the same output)" "	covered" "$OUT"
s61_reset; s61_owed "$S61_C2"
poke "$R61" current 8
expect_eq "61b6 …the readings taken again over the fix: current 8 is admitted" "0" "$RC"

# ---------- §CUR8-fail (AC-2.4): the newest failing reading holds the run ----------
s61_reset; s61_owed "$S61_C2"; s61_fact structure "$S61_C2" fail piece
s42_snap "$R61" "$P61"
poke "$R61" current 8
s42_unchanged "61c §CUR8-fail AC-2.4 the newest structure reading is result=fail" 1 "$P61"
expect_contains "61c2 …naming it failing, with its evidence" \
  "$(printf 'review\tstructure\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/structure-fail-piece.md')" "$OUT"
s61_fact structure "$S61_C2" pass piece
poke "$R61" current 8
expect_eq "61c3 …a later pass over the fix admits it" "0" "$RC"
s61_reset; s61_owed "$S61_C2"; s61_fact structure "$S61_C2" fail piece; s61_waiver structure "$S61_C2"
poke "$R61" current 8
expect_eq "61c4 …and so does a waived: line newer than the failing reading" "0" "$RC"
s61_reset; s61_owed "$S61_C2"; s61_fact adversarial "$S61_C2" fail whole
s42_snap "$R61" "$P61"
poke "$R61" current 8
s42_unchanged "61c5 …a failing whole read holds the run too" 1 "$P61"
expect_contains "61c6 …naming the whole line" \
  "$(printf 'review\tadversarial\tbionic:critic\twhole\tfailing\trecord/wave-01-fixture/adversarial-fail-whole.md')" "$OUT"

# ---------- §CUR8-rigor (AC-3.1): the critic at every rigor ----------
for s61r in single double double; do
  s61_reset; s61_rigor "$s61r"; s61_owed "$S61_C2" adversarial
  s42_snap "$R61" "$P61"
  poke "$R61" current 8
  s42_unchanged "61d §CUR8-rigor AC-3.1 at $s61r, current 8 with no adversarial fact" 1 "$P61"
  expect_contains "61d2 …at $s61r, naming the critic's adversarial question absent" \
    "$(printf 'review\tadversarial\tbionic:critic\tpiece\tabsent')" "$OUT"
  s61_fact adversarial "$S61_C2" pass piece; s61_fact adversarial "$S61_C2" pass whole
  poke "$R61" current 8
  expect_eq "61d3 …at $s61r, the same plan with it is admitted" "0" "$RC"
done
s61_reset; s61_rigor bogus; s61_owed "$S61_C2"
s42_snap "$R61" "$P61"
poke "$R61" current 8
s42_unchanged "61e a plan whose rigor the dealing does not know (the judge's rc 2)" 1 "$P61"
expect_contains "61e2 …saying the judge could not deal the plan" "the judge could not deal this plan (facts_state exit 2)" "$OUT"
expect_contains "61e3 …and printing what the judge said, whatever the reason" "declares no rigor and scale the dealing knows (rigor: bogus, scale: wave)" "$OUT"
s61_reset; s61_owed "$S61_C2"
s42_snap "$R61" "$P61"
poke "$R61" current 6
s42_unchanged "61f a move to another step is still dry-committed at that step (the matrix is pending at Step 6)" 1 "$P61"
expect_contains "61f2 …in the gate's own words" "bionic: commit refused" "$OUT"

# ---------- §CUR8-check (AC-6.1, last half; T16's check fact on the merged tree) ----------
# With `release-check:` set in the project's config, the judge owes `check` too (facts_owed's third
# operand, the tree), so `current 8` is refused, naming the check line absent, until the verb
# `release-check` records a passing run at the working head; then it is admitted. The declared
# command is a script this row writes that exits 0.
printf '#!/bin/bash
echo "scan: entries=0 hits=0"
exit 0
' > "$TMPROOT/s61-check.sh"
cp "$R61/.bionic/config.yaml" "$TMPROOT/s61-config" 2>/dev/null || : > "$TMPROOT/s61-config"
printf 'release-check: bash %s\n' "$TMPROOT/s61-check.sh" >> "$R61/.bionic/config.yaml"
s61_reset; s61_owed "$S61_C2"
s42_snap "$R61" "$P61"
poke "$R61" current 8
s42_unchanged "61g AC-6.1 with release-check: set and every reading at the head, current 8 with no check fact" 1 "$P61"
expect_contains "61g2 …naming the check line absent" "$(printf 'check\tabsent')" "$OUT"
poke "$R61" release-check
expect_eq "61g3 release-check runs the declared command and records the pass (exit 0)" "0" "$RC"
expect_eq "61g4 …a kind=check fact at the working head" "1" "$(/usr/bin/grep -c "^proved: kind=check head=${S61_C2} " "$P61")"
# The same verb under /bin/bash, the interpreter its shebang names and the one tests/run.sh pins
# (T80). T31's `case` arm inside the check's own-files `$( )` had no opening paren, which bash 3.2
# cannot parse, so the verb died there under /bin/bash while every hand run used PATH's bash 5.
POKE_BASH=/bin/bash poke "$R61" release-check
expect_eq "61g3b …and under /bin/bash it runs the declared command and records the pass too (exit 0)" "0" "$RC"
expect_contains "61g3c …its success line names the check at the working head" "kind=check head=${S61_C2}" "$OUT"
expect_absent "61g3d …and the shell reported no syntax error" "syntax error" "$OUT"
poke "$R61" current 8
expect_eq "61g5 AC-6.1 …and current 8 is then admitted (exit 0)" "0" "$RC"
expect_eq "61g6 …the plan reads current: 8" "8" "$(s61_cur)"
cp "$TMPROOT/s61-config" "$R61/.bionic/config.yaml"
POKE_BOUND="$S61_BOUND_WAS"

# ============================================================
section "Section 62 §RC: a declared release check is owed, run by its verb over the release range, and recorded as a check fact (wave-27 T16; REQ-6 AC-6.1; D12)"
# ============================================================
#
# A project may name one command in `.bionic/config.yaml` under `release-check:`. With the key set,
# `facts_owed <rigor> <scale> <tree>` adds the line `check`, and `facts_state` answers it: covered
# when the last `kind=check` line at the head asked about is a pass, failing when it carries
# `result=fail`, uncovered from the newest one's head, absent with none. `session-poker.sh
# release-check` runs the command in the working branch's checkout with BIONIC_CHECK_BASE (the
# nearest tag reachable from the plan's integration branch that is a proper ancestor of the working
# head, else its base-sha) and BIONIC_CHECK_HEAD (the working head), writes
# `record/<wave>/release-check-<head>.log` opening `head=<40-hex> rc=<exit>`, and the fact; on a
# non-zero exit it prints the command's output too and the fact carries `result=fail` (T31). With
# no key, nothing is owed, run or printed.
#
# FIXTURE FIDELITY. The declared command is a script this section writes, never this repository's
# own scan: it records the two variables, its directory and its arguments in a file, so a row reads
# the range it was given. The tags are real (one lightweight, one annotated, on `main`; one on the
# working branch alone, which no tag lookup from `main` may find). The plan is s42_plan's, bound to
# this session, with `integration-branch: main` added to its frontmatter and `working-branch:` to
# its `## SDLC State`. The facts and readings the judge rows plant beside the check are written by
# the production writers (s57_fact, s57_floor).
S62_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R62="$(make_repo s62-rc)"
git -C "$R62" symbolic-ref HEAD refs/heads/main
git -C "$R62" config user.name "Dana Fixture"
( cd "$R62" && git commit -q --allow-empty -m C0 && git tag v0.9.0 \
  && git commit -q --allow-empty -m C1 && git tag -a v1.0.0 -m 'release 1.0.0' ) >/dev/null 2>&1
S62_C0="$(git -C "$R62" rev-parse v0.9.0^{commit})"; S62_C1="$(git -C "$R62" rev-parse v1.0.0^{commit})"
P62="$(s42_plan "$R62" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S62_C0:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^scale: / && !f { print "integration-branch: main"; f = 1 }
     /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P62" > "$P62.tmp" && mv "$P62.tmp" "$P62"
( cd "$R62" && git add -f "$P62" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R62/.worktrees/01-fixture" "$S62_C1" ) >/dev/null 2>&1
S62_WT="$R62/.worktrees/01-fixture"
S62_W1="$(s57_commit "$S62_WT" lib/a.sh W1)"; git -C "$R62" tag v9-wip "$S62_W1"
S62_W2="$(s57_commit "$S62_WT" lib/b.sh W2)"
S62_REC="$R62/.bionic/docs/record/wave-01-fixture"
S62_SEEN="$TMPROOT/s62-seen"; S62_RCF="$TMPROOT/s62-check-rc"; echo 0 > "$S62_RCF"
S62_CHK="$TMPROOT/s62-check.sh"
cat > "$S62_CHK" <<S62_EOF
#!/bin/bash
printf 'base=%s head=%s cwd=%s args=%s\n' "\${BIONIC_CHECK_BASE:-}" "\${BIONIC_CHECK_HEAD:-}" "\$(pwd -P)" "\$*" >> "$S62_SEEN"
rc="\$(cat "$S62_RCF")"
if [ "\$rc" = 0 ]; then echo 'scan: entries=3 hits=0'; else echo 'HIT entry 2 in lib/b.sh'; echo 'scan: entries=3 hits=1' >&2; fi
exit "\$rc"
S62_EOF
s62_seen() { [ -f "$S62_SEEN" ] && tail -n 1 "$S62_SEEN"; }
s62_runs() { [ -f "$S62_SEEN" ] && awk 'END { print NR + 0 }' "$S62_SEEN" || echo 0; }
s62_owed() {  # [<tree>] -> what facts_owed double wave deals, with the tree given or not
  bash -c '. "$1" && facts_owed double wave ${2:+"$2"}' _ "$S57_LIB" "${1:-}"
}
s62_covered_but_check() {  # <head> -> the floor and every reading planted at <head>
  s57_floor "$1" "$P62"
  for s62q in evidence adversarial structure; do s57_fact "$s62q" "$1" pass piece "$P62"; done
  s57_fact adversarial "$1" pass whole "$P62"; s57_fact structure "$1" pass whole "$P62"
}
expect_regex "62a0 precondition: the working head W2 is a 40-hex commit" '^[0-9a-f]{40}$' "$S62_W2"
expect_eq "62a0b precondition: the newest tag reachable from main is v1.0.0, at C1" "v1.0.0" \
  "$(git -C "$R62" describe --tags --abbrev=0 main 2>/dev/null)"
expect_eq "62a0c precondition: v9-wip sits on the working branch alone" "no" \
  "$(git -C "$R62" merge-base --is-ancestor "$S62_W1" main 2>/dev/null && echo yes || echo no)"

# ---------- with no key: nothing owed, run or printed (the controls) ----------
expect_eq "62n0 no key: the dealing still starts with the floor" "floor" "$(s62_owed "$R62" | head -1)"
expect_eq "62n …and owes no check" "" "$(s62_owed "$R62" | /usr/bin/grep -x check)"
s62_covered_but_check "$S62_W2"
s57_state "$P62" "$S62_W2"
expect_eq "62n1 no key: the judge answers the floor" "covered" "$(s57_of floor)"
expect_eq "62n1b …and prints no check line" "" "$(printf '%s\n' "$S57_OUT" | /usr/bin/grep '^check')"
expect_eq "62n1c …so the run holds (rc 0)" "0" "$S57_RC"
s42_snap "$R62" "$P62"
poke "$R62" release-check
expect_eq "62n2 no key: release-check exits 0" "0" "$RC"
expect_eq "62n3 …prints nothing" "" "$OUT"
expect_eq "62n4 …runs nothing" "0" "$(s62_runs)"
expect_true "62n5 …and writes nothing: the plan is byte-identical" cmp -s "$TMPROOT/s42-before" "$P62"
expect_eq "62n6 …and no log" "" "$(ls "$S62_REC" 2>/dev/null | /usr/bin/grep '^release-check-')"

# ---------- with the key: owed, absent until the verb records a pass at the head ----------
printf 'release-check: bash %s list.txt\n' "$S62_CHK" > "$R62/.bionic/config.yaml"
expect_eq "62a §RC with release-check: set, the dealing owes check, last" "check" "$(s62_owed "$R62" | tail -1)"
expect_eq "62a2 …and only when it is asked about a tree: with two operands the last line dealt is a review" "review" "$(s62_owed | tail -1 | cut -f1)"
s57_state "$P62" "$S62_W2"
expect_eq "62b no check fact: the check line is absent" "absent" "$(s57_of check)"
expect_eq "62b2 …and the run does not hold (rc 1)" "1" "$S57_RC"
expect_eq "62b3 …while everything else is covered at the head" "covered" "$(s57_of "$S57_ADW")"

poke "$R62" release-check
S62_PASS_OUT="$OUT"
expect_eq "62c the verb runs the declared command and records the pass (exit 0)" "0" "$RC"
expect_eq "62c2 …with the base at the newest tag reachable from main (v1.0.0, not v9-wip), the head at the working head, in the working checkout, the command split on blanks" \
  "base=${S62_C1} head=${S62_W2} cwd=$(cd "$S62_WT" && pwd -P) args=list.txt" "$(s62_seen)"
S62_LOG2="$S62_REC/release-check-${S62_W2}.log"
expect_eq "62c3 …its log opens head=<working head> rc=0" "head=${S62_W2} rc=0" "$(head -n 1 "$S62_LOG2" 2>/dev/null)"
expect_contains "62c4 …and carries the command's output" "scan: entries=3 hits=0" "$(cat "$S62_LOG2" 2>/dev/null)"
expect_regex "62c5 …and the plan carries the check fact, with no reading fields" \
  "^proved: kind=check head=${S62_W2} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/release-check-${S62_W2}\.log$" \
  "$(/usr/bin/grep -E '^proved: kind=check ' "$P62")"
expect_contains "62c6 …and the success line names it" "kind=check head=${S62_W2}" "$S62_PASS_OUT"
s57_state "$P62" "$S62_W2"
expect_eq "62d the judge: check covered at the head" "covered" "$(s57_of check)"
expect_eq "62d2 …and the run holds (rc 0)" "0" "$S57_RC"

S62_W3="$(s57_commit "$S62_WT" lib/b.sh W3)"
s57_state "$P62" "$S62_W3"
expect_eq "62e code past the check: uncovered from the check's head" "uncovered	${S62_W2}..${S62_W3}" "$(s57_of check)"

# ---------- a failing command: its output printed, its log and a result=fail fact written ----------
# (wave-27 T31, review pass 22 S3, which replaces "a failing command writes nothing": 62f, 62f4 and
# 62f5 assert the new rule in place, under their old ids.)
echo 1 > "$S62_RCF"; s42_snap "$R62" "$P62"
poke "$R62" release-check
S62_FAIL_OUT="$OUT"
expect_eq "62f a failing declared command is refused (exit 1)" "1" "$RC"
expect_contains "62f2 …prints the command's output" "HIT entry 2 in lib/b.sh" "$S62_FAIL_OUT"
expect_contains "62f2b …its standard error too" "scan: entries=3 hits=1" "$S62_FAIL_OUT"
expect_eq "62f3 …ran at the new head" "head=${S62_W3}" "$(s62_seen | awk '{ print $2 }')"
expect_eq "62f4 …writes its log at that head, opening head=<head> rc=1" "head=${S62_W3} rc=1" \
  "$(head -n 1 "$S62_REC/release-check-${S62_W3}.log" 2>/dev/null)"
expect_true "62f4b …and the passing head's log stands" test -f "$S62_LOG2"
expect_regex "62f6 …and the plan carries a check fact at that head with result=fail" \
  "^proved: kind=check head=${S62_W3} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/release-check-${S62_W3}\.log result=fail$" \
  "$(/usr/bin/grep -E "^proved: kind=check head=${S62_W3} " "$P62" | tail -n 1)"
s57_state "$P62" "$S62_W3"
expect_eq "62f5 …and the judge says failing, naming that log" "failing	record/wave-01-fixture/release-check-${S62_W3}.log" "$(s57_of check)"

# ---------- refusals before the command runs ----------
echo 0 > "$S62_RCF"
S62_N="$(s62_runs)"
printf 'half\n' >> "$S62_WT/lib/b.sh"; s42_snap "$R62" "$P62"
poke "$R62" release-check
s42_unchanged "62h a working checkout with uncommitted changes" 1 "$P62"
expect_eq "62h2 …and the command did not run" "$S62_N" "$(s62_runs)"
git -C "$S62_WT" checkout -q -- lib/b.sh
poke "$R62" release-check extra
s42_unchanged "62i an operand (the base is the verb's own)" 2 "$P62"
mkdir -p "$S62_REC"; printf 'head=%s rc=0\n' "$S62_W3" > "$S62_REC/hand.log"
poke "$R62" proof-add check record/wave-01-fixture/hand.log
s42_unchanged "62j a check fact through proof-add, from a log nobody's run wrote" 1 "$P62"
expect_contains "62j2 …naming the verb that writes it" "release-check" "$OUT"

# ---------- no tag reachable from the integration branch: the plan's base-sha ----------
git -C "$R62" tag -d v0.9.0 v1.0.0 >/dev/null 2>&1
poke "$R62" release-check
expect_eq "62g with no tag reachable from main, the verb passes (exit 0)" "0" "$RC"
expect_eq "62g2 …and the base is the plan's base-sha, whole, while v9-wip on the working branch is still not read" \
  "base=${S62_C0} head=${S62_W3}" "$(s62_seen | awk '{ print $1, $2 }')"
s57_state "$P62" "$S62_W3"
expect_eq "62g3 …and the judge: check covered at the new head" "covered" "$(s57_of check)"

# ---------- proof_attested's own arm for a check log ----------
s62_att() {  # <log> -> PA_OUT, PA_RC
  PA_OUT="$(bash -c '. "$1" && proof_attested check "$2" "$3"' _ "$S57_LIB" "$1" "$S62_WT" 2>/dev/null)"; PA_RC=$?
}
s62_att "$S62_REC/release-check-${S62_W3}-2.log"
expect_eq "62p proof_attested check: a log opening head=<checkout head> rc=0 attests that head" "0 ${S62_W3}" "$PA_RC $PA_OUT"
s62_att "$S62_LOG2"
expect_eq "62p2 …a log of an older head is refused" "1" "$PA_RC"
expect_contains "62p3 …naming the head it ran at" "${S62_W2:0:12}" "$PA_OUT"
printf 'head=%s rc=1\nscan\n' "$S62_W3" > "$S62_REC/red.log"
s62_att "$S62_REC/red.log"
expect_eq "62p4 …a log opening rc=1 is refused" "1" "$PA_RC"
printf 'scan\nhead=%s rc=0\n' "$S62_W3" > "$S62_REC/late.log"
s62_att "$S62_REC/late.log"
expect_eq "62p5 …and so is a log whose first line is not the header" "1" "$PA_RC"

# ---------- T31: review pass 22's S2, S3, S4 and B1's verb half (wave-27 T31; A-orch-75) ----------
# Rows 62x…, each red on T16's verb. Logs at one head are numbered: the first run's is
# release-check-<head>.log, the n-th's release-check-<head>-<n>.log, so no run overwrites another's.
# At this point W3 holds three logs: 62f's fail (the first), 62g's pass (-2).
# S4: a tracked file touched, its content unchanged, is not dirt.
S62_N="$(s62_runs)"
touch -t 203001010000 "$S62_WT/lib/b.sh"
expect_eq "62x0p precondition: touch left lib/b.sh's content as the head has it" "0" \
  "$(git -C "$S62_WT" show HEAD:lib/b.sh | cmp -s - "$S62_WT/lib/b.sh"; echo $?)"
expect_eq "62x0 precondition: …while an unrefreshed index calls it changed" "1" \
  "$(git -C "$S62_WT" diff-index --quiet HEAD -- >/dev/null 2>&1; echo $?)"
s42_snap "$R62" "$P62"
poke "$R62" release-check
expect_eq "62x S4 a touched file with unchanged content is not dirt: the verb runs and passes (exit 0)" "0" "$RC"
expect_eq "62x2 …and the command ran" "$((S62_N + 1))" "$(s62_runs)"
git -C "$S62_WT" update-index -q --refresh >/dev/null 2>&1  # the rows below never ride on S4's answer
# S3: a pass at H, then the same command exiting 1 at H, then a pass.
echo 1 > "$S62_RCF"
poke "$R62" release-check
expect_eq "62x3 S3 a pass at H, then the same command exiting 1 at H: refused (exit 1)" "1" "$RC"
s57_state "$P62" "$S62_W3"
expect_eq "62x4 …and the judge says failing, naming the second run's log" \
  "failing	record/wave-01-fixture/release-check-${S62_W3}-4.log" "$(s57_of check)"
expect_eq "62x4b …so the run does not hold (rc 1)" "1" "$S57_RC"
expect_eq "62x5 …the later log does not overwrite the earlier: the third run's log opens rc=0, the fourth's rc=1" \
  "head=${S62_W3} rc=0|head=${S62_W3} rc=1" \
  "$(head -n 1 "$S62_REC/release-check-${S62_W3}-3.log" 2>/dev/null)|$(head -n 1 "$S62_REC/release-check-${S62_W3}-4.log" 2>/dev/null)"
echo 0 > "$S62_RCF"
poke "$R62" release-check
s57_state "$P62" "$S62_W3"
expect_eq "62x6 …and a run after it that passes: covered" "covered" "$(s57_of check)"

# S2: the base is the nearest release tag that is a PROPER ancestor of the working head. The working
# branch is merged into main, so tags on it are reachable from the integration branch; v9-wip (W1)
# becomes one too.
( cd "$R62" && git merge -q --no-edit -m 'release merge' wave/01-fixture ) >/dev/null 2>&1
S62_M="$(git -C "$R62" rev-parse main)"
expect_eq "62x7 precondition: the working head W3 is on main, and main's tip is past it" "yes no" \
  "$(git -C "$R62" merge-base --is-ancestor "$S62_W3" main && echo yes || echo no) $([ "$S62_M" = "$S62_W3" ] && echo yes || echo no)"
git -C "$R62" tag v62-a "$S62_W2"; git -C "$R62" tag v62-b "$S62_W3"
poke "$R62" release-check
expect_eq "62x8 S2 v62-a on an ancestor and v62-b on the head: the base is v62-a, the nearer of v62-a and v9-wip" \
  "0 base=${S62_W2} head=${S62_W3}" "$RC $(s62_seen | awk '{ print $1, $2 }')"
git -C "$R62" tag -d v62-a v9-wip >/dev/null 2>&1
poke "$R62" release-check
expect_eq "62x9 …only v62-b, on the head, and a base-sha: the base is the base-sha" \
  "0 base=${S62_C0} head=${S62_W3}" "$RC $(s62_seen | awk '{ print $1, $2 }')"
git -C "$R62" tag v62-c "$S62_M"
poke "$R62" release-check
expect_eq "62x10 …and a tag on a commit that is not an ancestor of the head (main's tip) is no base either" \
  "0 base=${S62_C0} head=${S62_W3}" "$RC $(s62_seen | awk '{ print $1, $2 }')"
cp "$P62" "$TMPROOT/s62-with-base"
awk '!/^  base-sha: /' "$TMPROOT/s62-with-base" > "$P62"
s42_snap "$R62" "$P62"; S62_N="$(s62_runs)"
poke "$R62" release-check
s42_unchanged "62x11 only v62-b on the head and no base-sha" 1 "$P62"
expect_contains "62x11b …refused as a range with no start" "so the release range has no start" "$OUT"
expect_eq "62x11c …and the command did not run" "$S62_N" "$(s62_runs)"
awk -v h="$S62_W3" '/^  base-sha: / { $0 = "  base-sha: " h } { print }' "$TMPROOT/s62-with-base" > "$P62"
s42_snap "$R62" "$P62"
poke "$R62" release-check
s42_unchanged "62x12 a base-sha at the head itself and no tag a proper ancestor: a range holding no commit" 1 "$P62"
expect_contains "62x12b …is refused, never judged" "holds no commit" "$OUT"
expect_eq "62x12c …and the command did not run" "$S62_N" "$(s62_runs)"
cp "$TMPROOT/s62-with-base" "$P62"; s42_snap "$R62" "$P62"

# B1, the verb's half: a range that changes a tracked path the declared command names as a word.
printf '#!/bin/bash\nexec bash %s "$@"\n' "$S62_CHK" > "$S62_WT/scan.sh"
( cd "$S62_WT" && git add scan.sh && git commit -qm W4 ) >/dev/null 2>&1
S62_W4="$(git -C "$S62_WT" rev-parse HEAD)"
printf 'release-check: bash scan.sh lib/a.sh\n' > "$R62/.bionic/config.yaml"
expect_eq "62x13 precondition: both words name tracked paths at W4" "lib/a.sh scan.sh" \
  "$(git -C "$S62_WT" ls-files -- scan.sh lib/a.sh | sort | tr '\n' ' ' | sed 's/ $//')"
poke "$R62" release-check
S62_B1_OK="$(printf '%s\n' "$OUT" | /usr/bin/grep -F 'release-check — kind=check')"
expect_eq "62x14 B1 a range (v62-b..W4) that changes scan.sh, which the command names: the check runs over it and passes" \
  "0 base=${S62_W3} head=${S62_W4}" "$RC $(s62_seen | awk '{ print $1, $2 }')"
expect_contains "62x15 …and the success line carries check-changed: scan.sh" "check-changed: scan.sh" "$S62_B1_OK"
expect_eq "62x15b …and so does the log's first line" "check-changed: scan.sh" \
  "$(head -n 1 "$S62_REC/release-check-${S62_W4}.log" 2>/dev/null)"
expect_eq "62x16 …while lib/a.sh, named but not changed by the range, is on no such line (the log holds one)" "1 0" \
  "$(/usr/bin/grep -c '^check-changed: ' "$S62_REC/release-check-${S62_W4}.log" 2>/dev/null) $(printf '%s\n' "$OUT" | /usr/bin/grep -c 'check-changed: lib/a.sh')"
s57_state "$P62" "$S62_W4"
expect_eq "62x17 …and the fact is still written: the judge says covered at W4" "covered" "$(s57_of check)"
# THE WORKING TREE IS HANDED TO THE CHECK (wave-27 T34; T50's record, S3): BIONIC_CHECK_TREE, the
# absolute path of the working checkout, beside BIONIC_CHECK_BASE and BIONIC_CHECK_HEAD.
S62_TREE_SEEN="$TMPROOT/s62-tree-seen"
printf '#!/bin/bash
printf "%%s\\n" "${BIONIC_CHECK_TREE:-unset}" > %q
' "$S62_TREE_SEEN" > "$TMPROOT/s62-tree.sh"
printf 'release-check: bash %s\n' "$TMPROOT/s62-tree.sh" > "$R62/.bionic/config.yaml"
s57_commit "$S62_WT" lib/t.sh W5 >/dev/null
poke "$R62" release-check
expect_eq "62t release-check with a check that reads the tree exits 0" "0" "$RC"
expect_eq "62t2 BIONIC_CHECK_TREE is the working checkout's absolute path" "$(cd "$S62_WT" && pwd -P)" \
  "$(cat "$S62_TREE_SEEN" 2>/dev/null)"
POKE_BOUND="$S62_BOUND_WAS"

# ============================================================
section "Section 63 §BASE §HEAD §FLOOR-HEAD §WHOLE-TIME §EDGES: the judge holds where a chain starts and which head it was asked about (wave-27 T45; review pass 13 F1 to F4, F6, F10; REQ-1 AC-1.2, REQ-2 AC-2.3 AC-2.4; D2, D10)"
# ============================================================
#
# A run's base is the plan's `base-sha:`, and nothing is derived in its place. With none,
# `proof-add review` refuses a question's first reading, its first line naming the line to add,
# and `facts_state` exits 2 printing nothing, for every dealing owes a reading (§DEAL in
# cross-gate-agreement holds one role per question at every rigor). `<head>` must resolve to a
# commit or the judge exits 2, and a line's head is compared after resolution. The floor line
# answers for `<head>` only when it is the working checkout's head, which `proof_state` judged;
# any other head is uncovered from the floor proof's head. A `scope: whole` record is refused while
# a `## Tasks` row of kind `build` is pending or active (D10: the whole read is taken once the
# last build piece has landed). The git edges of the chain (a merge, a rename across the docs root
# each way, a last head off the history of the head asked about) are pinned, each with a doctored
# copy of proof.sh that turns its row red. A waiver's question and head survive a reply and a git
# user name that spell ` by question=… head=…` (F6).
#
# FIXTURE FIDELITY. §BASE is section 57t's task-scale plan, written the same way, with no
# `base-sha:` (review pass 13's exp6.sh: commits init → unread code → read code), then with the
# base in its frontmatter, where A-orch-56 puts it at task scale. Readings register through the
# verb under the 57t roster row shape (s56_row, `questions=` SYNTHESIZED until T15). The judge's
# planted copies are written by the production writers (`proof_line`, `proof_add_line`). §WHOLE-TIME
# is §42's wave plan, admitted by the real commit gate, with its own `## Tasks` rows. §EDGES is
# exp3.sh's repository: real merges and real `git mv` renames. Each mutant is a copy of the whole
# lib directory with one line of proof.sh changed, run beside the shipped one.
S63_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s63_task_plan() {  # <repo> <plan> -> a scale: task plan as 57t writes it, with no base-sha:
  mkdir -p "$(dirname "$2")"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
    printf 'rigor: single\nscale: task\nmulti_agent: false\nuse_worktree: true\nhas_ui: false\n'
    printf 'walk: exempt\ndeploy_target: n/a\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture task\n\n## SDLC State\n\ncurrent: T1\n%s\nworking-branch: task/01-fixture\n\n' "$SP_APPROVED_LINE"
    printf -- '- T1: the fix, in .worktrees/01-task\n\n'
    printf '## Tasks\n\n| id | intent | rigor | description | status |\n|---|---|---|---|---|\n'
    printf '| T1 | bugfix | single | the fix | active |\n\n'
    printf '## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
  } > "$2"
}
s63_base() {  # <plan> <sha> -> the plan with `base-sha: <sha>` in its frontmatter, after scale:
  B="$2" awk '{ print } /^scale: / && !d { print "base-sha: " ENVIRON["B"]; d = 1 }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
S63_TAD="$(printf 'review\tadversarial\tbionic:critic\tpiece')"
s63_task_all() {  # <floor state> <review state> -> the four owed lines of a single task plan
  printf 'floor\t%s\nreview\tevidence\tbionic:critic\tpiece\t%s\nreview\tadversarial\tbionic:critic\tpiece\t%s\nreview\tstructure\tbionic:critic\tpiece\t%s' \
    "$1" "$2" "$2" "$2"
}

# ---------- §BASE (F1): no base, no first reading, no judgment ----------
R63="$(make_repo s63-base)"; ( cd "$R63" && git commit -q --allow-empty -m init )
S63_I="$(git -C "$R63" rev-parse HEAD)"
P63="$R63/.bionic/docs/plans/epic-99-fixture/task-01-fixture.plan.md"
s63_task_plan "$R63" "$P63"
bound_marker "$R63" "$SID" "$P63" >/dev/null 2>&1
( cd "$R63" && git add -f "$P63" && git commit -qm plan \
  && git worktree add -q -b task/01-fixture "$R63/.worktrees/01-task" "$S63_I" ) >/dev/null 2>&1
S63_WT="$R63/.worktrees/01-task"
S63_U="$(s57_commit "$S63_WT" lib/fix.sh 'unread code')"
S63_H="$(s57_commit "$S63_WT" lib/fix.sh 'read code')"
S63_RREL=".bionic/docs/record/task-01-fixture"; S63_REC="$R63/$S63_RREL"; mkdir -p "$S63_REC"
new_roster "$R63"
s56_row "$(roster_of "$R63")" w-tcrit bionic:critic evidence,adversarial,structure \
  "$S63_RREL/tail.md,$S63_RREL/evidence.md,$S63_RREL/adversarial.md,$S63_RREL/structure.md"
printf 'reviewed: %s..%s\nquestion: evidence\nresult: pass\nscope: piece\n\nthe last commit alone\n' "$S63_U" "$S63_H" > "$S63_REC/tail.md"
for s63q in evidence adversarial structure; do
  { printf 'reviewed: %s..%s\nquestion: %s\nresult: pass\nscope: piece\n' "$S63_I" "$S63_H" "$s63q"
    [ "$s63q" = structure ] && printf '%s\n' "$S57T_CHECKS"; printf '\nwhat the reader found\n'; } > "$S63_REC/$s63q.md"
done
expect_eq "63a0 precondition: unread code is the parent of read code, and init its parent" "$S63_I $S63_U" \
  "$(git -C "$S63_WT" rev-parse "$S63_H~2" "$S63_H~1" | tr '\n' ' ' | sed 's/ $//')"
expect_eq "63a0b precondition: the plan names no base-sha: anywhere" "0" "$(/usr/bin/grep -c 'base-sha' "$P63")"
s34_gate "$R63"
expect_eq "63a0c precondition: the task-scale plan with no base is admitted by the real commit gate" "0" "$GATE_RC"
s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/tail.md" --question evidence --reader w-tcrit
s42_unchanged "63a F1 with no base, a first reading over the last commit alone" 1 "$P63"
expect_contains "63a2 …the refusal's first line names the frontmatter line to add" \
  "base-sha: <the commit the work started from>" "$(printf '%s\n' "$OUT" | head -1)"
poke "$R63" proof-add review "record/task-01-fixture/evidence.md" --question evidence --reader w-tcrit
s42_unchanged "63a3 F1 with no base, a first reading over the whole branch is refused too: its start cannot be held" 1 "$P63"
expect_contains "63a4 …naming the same line" "base-sha: <the commit the work started from>" "$(printf '%s\n' "$OUT" | head -1)"
# A base-sha: that names no commit is no base (review pass 16, probe3): the same refusal, saying which.
cp "$P63" "$TMPROOT/s63-nobase"; s63_base "$P63" deadbeef; s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/tail.md" --question evidence --reader w-tcrit
s42_unchanged "63a5 with base-sha: deadbeef, which is no commit, a first reading over the tail" 1 "$P63"
expect_contains "63a6 …its first line naming the line to add" "add base-sha: <the commit the work started from> to the frontmatter of " \
  "$(printf '%s\n' "$OUT" | head -1)"
expect_contains "63a7 …and saying the base it names is no commit" "its base-sha: deadbeef is no commit here" \
  "$(printf '%s\n' "$OUT" | head -1)"
cp "$TMPROOT/s63-nobase" "$P63"; s42_snap "$R63" "$P63"
# The judge on the same plan text with its readings planted at the head (exp6.sh): no base, exit 2.
mkdir -p "$R63/.bionic/tmp"; S63_PP="$R63/.bionic/tmp/planted.plan.md"; cp "$P63" "$S63_PP"
for s63q in evidence adversarial structure; do s57_fact "$s63q" "$S63_H" pass piece "$S63_PP"; done
s57_floor "$S63_H" "$S63_PP"
s57_state "$S63_PP" "$S63_H"
expect_eq "63b F1 facts_state on a plan with no base that owes readings: exit 2" "2" "$S57_RC"
expect_eq "63b2 …printing nothing" "" "$S57_OUT"
cp "$S63_PP" "$R63/.bionic/tmp/badbase.plan.md"; s63_base "$R63/.bionic/tmp/badbase.plan.md" deadbeef
s57_state "$R63/.bionic/tmp/badbase.plan.md" "$S63_H"
expect_eq "63b2b with base-sha: deadbeef, which is no commit, the judge exits 2 and prints nothing" "2 " "$S57_RC $S57_OUT"
s63_base "$S63_PP" "$S63_I"
s57_state "$S63_PP" "$S63_H"
expect_eq "63b3 control: the same planted lines with the base in the frontmatter are judged, every line covered" \
  "$(s63_task_all covered covered)" "$S57_OUT"
expect_eq "63b4 …rc 0" "0" "$S57_RC"
# The same plan with its base: the tail is refused as a start past the base, the whole branch registers.
s63_base "$P63" "$S63_I"; s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/tail.md" --question evidence --reader w-tcrit
s42_unchanged "63c with base-sha: init, the last commit alone starts past the base" 1 "$P63"
expect_contains "63c2 …naming the range that is owed" "review ${S63_I:0:12}..${S63_H:0:12}" "$OUT"
for s63q in evidence adversarial structure; do
  poke "$R63" proof-add review "record/task-01-fixture/$s63q.md" --question "$s63q" --reader w-tcrit
  expect_eq "63c3 with the base, a $s63q reading from it registers (exit 0)" "0" "$RC"
done
s57_floor "$S63_H" "$P63"
s57_state "$P63" "$S63_H"
expect_eq "63c4 …and the judge answers every line covered" "$(s63_task_all covered covered)" "$S57_OUT"
expect_eq "63c5 …rc 0" "0" "$S57_RC"

# ---------- §HEAD (F10): the head asked about is a commit, compared after resolution ----------
s57_state "$P63" not-a-sha
expect_eq "63h a head that is no name git knows: exit 2" "2" "$S57_RC"
expect_eq "63h2 …printing nothing" "" "$S57_OUT"
s57_state "$P63" "$(git -C "$R63" rev-parse "$S63_H^{tree}")"
expect_eq "63h3 a tree id: exit 2, nothing printed" "2 " "$S57_RC $S57_OUT"
s57_state "$P63" "$(git -C "$R63" rev-parse "$S63_H:lib/fix.sh")"
expect_eq "63h4 a blob id: exit 2, nothing printed" "2 " "$S57_RC $S57_OUT"
s57_state "$P63" ""
expect_eq "63h5 an empty head: exit 2, nothing printed" "2 " "$S57_RC $S57_OUT"
S63_NC="$R63/.bionic/tmp/noncommit.plan.md"
awk '/^proved: kind=review / { sub(/ head=[0-9a-f]+ /, " head=abcdef0 ") } { print }' "$S63_PP" > "$S63_NC"
expect_eq "63h6 precondition: the copy's three readings name abcdef0, which is no commit" "3 1" \
  "$(/usr/bin/grep -c 'kind=review head=abcdef0 ' "$S63_NC") $(git -C "$R63" rev-parse -q --verify 'abcdef0^{commit}' >/dev/null 2>&1; echo $?)"
s57_state "$S63_NC" abcdef0
expect_eq "63h7 F10 readings naming a non-commit, asked at that same string, are never covered: exit 2" "2 " "$S57_RC $S57_OUT"

# ---------- §FLOOR-HEAD (F3): the floor line answers for the head proof_state judged ----------
S63_N="$(git -C "$R63" commit-tree "$S63_H^{tree}" -p "$S63_H" -m 'one past the checkout')"
expect_eq "63f0 precondition: the commit one past the checkout's head is not checked out" "$S63_H" "$(git -C "$S63_WT" rev-parse HEAD)"
s57_state "$P63" "$S63_N"
expect_eq "63f F3 asked about a commit one past the checkout's head: the floor is uncovered from the floor proof's head" \
  "uncovered	${S63_H}..${S63_N}" "$(s57_of floor)"
expect_eq "63f2 …the review lines, which changed no file, covered" "covered" "$(s57_of "$S63_TAD")"
expect_eq "63f3 …and the exit 1" "1" "$S57_RC"
s57_state "$P63" "$S63_U"
expect_eq "63f4 asked about an older head: the floor is uncovered too, never covered" "uncovered	${S63_H}..${S63_U}" "$(s57_of floor)"
sed '/^proved: kind=floor /d' "$P63" > "$R63/.bionic/tmp/nofloor.plan.md"
s57_state "$R63/.bionic/tmp/nofloor.plan.md" "$S63_N"
expect_eq "63f5 with no floor proof the floor line is absent, at any head" "absent" "$(s57_of floor)"
expect_eq "63f6 …the review lines judged beside it" "covered" "$(s57_of "$S63_TAD")"
# Asked by name: the head is resolved, so the range names the commit.
S63_X="$(s57_commit "$S63_WT" lib/fix.sh 'past the readings')"
s57_state "$P63" task/01-fixture
expect_eq "63f7 a head asked by its branch name is judged as the commit it names: the range ends at that commit" \
  "uncovered	${S63_H}..${S63_X}" "$(s57_of "$S63_TAD")"

# ---------- §WHOLE-TIME (F2; D10): a whole read waits for the last build piece ----------
R63W="$(make_repo s63-whole-time)"; ( cd "$R63W" && git commit -q --allow-empty -m init )
S63W_B="$(git -C "$R63W" rev-parse HEAD)"
P63W="$(s42_plan "$R63W" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S63W_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P63W" > "$P63W.tmp" && mv "$P63W.tmp" "$P63W"
( cd "$R63W" && git add -f "$P63W" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R63W/.worktrees/01-fixture" "$S63W_B" ) >/dev/null 2>&1
S63W_C1="$(s57_commit "$R63W/.worktrees/01-fixture" lib/a.sh C1)"
S63W_REC="$R63W/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S63W_REC"
printf 'reviewed: %s..%s\nquestion: adversarial\nresult: pass\nscope: whole\n\nthe whole wave\n' "$S63W_B" "$S63W_C1" > "$S63W_REC/whole.md"
new_roster "$R63W"; S63W_RS="$(roster_of "$R63W")"
s56_row "$S63W_RS" implementor implementor
s56_row "$S63W_RS" w-crit bionic:critic adversarial ".bionic/docs/record/wave-01-fixture/whole.md"
s63_status() {  # <id> <status> -> that row of P63W's ## Tasks given the status, its other cells kept
  I="$1" S="$2" awk -F'|' 'BEGIN { OFS = "|" } $2 == " " ENVIRON["I"] " " { $(NF - 1) = " " ENVIRON["S"] " " } { print }' \
    "$P63W" > "$P63W.tmp" && mv "$P63W.tmp" "$P63W"
}
expect_eq "63w0 precondition: the build rows T1 landed and T2 active, the verify row T5 pending" "T1 landed;T2 active;T5 pending;" \
  "$(bash -c '. "$1" && units_rows "$2"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib/units.sh" "$P63W" 2>/dev/null \
     | awk -F'\t' '{ printf "%s %s;", $1, $10 }')"
s34_gate "$R63W"
expect_eq "63w0b precondition: the plan is admitted by the real commit gate" "0" "$GATE_RC"
s42_snap "$R63W" "$P63W"
poke "$R63W" proof-add review record/wave-01-fixture/whole.md --question adversarial --reader w-crit
s42_unchanged "63w F2 a scope: whole record while build row T2 is active" 1 "$P63W"
expect_contains "63w2 …naming the open build row" "build rows are still open: T2 (active);" "$OUT"
s63_status T2 pending; s42_snap "$R63W" "$P63W"
poke "$R63W" proof-add review record/wave-01-fixture/whole.md --question adversarial --reader w-crit
s42_unchanged "63w3 …while T2 is pending" 1 "$P63W"
expect_contains "63w4 …naming it" "build rows are still open: T2 (pending);" "$OUT"
s63_status T1 pending; s63_status T2 active; s42_snap "$R63W" "$P63W"
poke "$R63W" proof-add review record/wave-01-fixture/whole.md --question adversarial --reader w-crit
s42_unchanged "63w5 …while two build rows are open" 1 "$P63W"
expect_contains "63w6 …naming both" "build rows are still open: T1 (pending), T2 (active);" "$OUT"
s63_status T1 landed; s63_status T2 dropped
S63W_DOC='| T6 | 4 | doc | the notes | implementor | — | 15 | REQ-1 | notes.md | — | — | pending |'
S63W_REV='| T7 | 4 | review | a read | — | — | 15 | REQ-1 | — | — | — | pending |'
D="$S63W_DOC" V="$S63W_REV" awk '{ print } /^\| T5 \| 5 \| verify \|/ { print ENVIRON["D"]; print ENVIRON["V"] }' "$P63W" > "$P63W.tmp" && mv "$P63W.tmp" "$P63W"
expect_eq "63w7 precondition: every build row landed or dropped, a verify, a doc and a review row pending" \
  "T1 build landed;T2 build dropped;T5 verify pending;T6 doc pending;T7 review pending;" \
  "$(bash -c '. "$1" && units_rows "$2"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib/units.sh" "$P63W" 2>/dev/null \
     | awk -F'\t' '{ printf "%s %s %s;", $1, $3, $10 }')"
s42_snap "$R63W" "$P63W"
poke "$R63W" proof-add review record/wave-01-fixture/whole.md --question adversarial --reader w-crit
expect_eq "63w8 with every build row landed or dropped, the whole read registers (a verify, a doc and a review row pending hold nothing)" "0" "$RC"
expect_contains "63w9 …as a whole reading" "evidence=record/wave-01-fixture/whole.md question=adversarial reader=w-crit result=pass scope=whole" \
  "$(s46_proved "$P63W" | tail -1)"
# A plan with no ## Tasks table is not held to it: §BASE's task plan, its table removed.
awk '/^## Tasks/ { skip = 1; next } skip && /^## / { skip = 0 } !skip' "$P63" > "$P63.tmp" && mv "$P63.tmp" "$P63"
printf 'reviewed: %s..%s\nquestion: adversarial\nresult: pass\nscope: whole\n\nthe whole task\n' "$S63_I" "$S63_X" > "$S63_REC/whole.md"
s56_row "$(roster_of "$R63")" w-tcrit bionic:critic evidence,adversarial,structure "$S63_RREL/whole.md"
expect_eq "63w10 precondition: the task plan holds no ## Tasks table" "0" "$(/usr/bin/grep -c '^## Tasks' "$P63")"
s42_snap "$R63" "$P63"
poke "$R63" proof-add review record/task-01-fixture/whole.md --question adversarial --reader w-tcrit
expect_eq "63w11 with no ## Tasks table, a whole read is not held to the build rows (exit 0)" "0" "$RC"
expect_contains "63w12 …written as a whole reading" "evidence=record/task-01-fixture/whole.md question=adversarial reader=w-tcrit result=pass scope=whole" \
  "$(s46_proved "$P63" | tail -1)"

# ---------- §EDGES (F4): a merge, renames across the docs root, a head off the history ----------
R63E="$TMPROOT/s63-edges"; mkdir -p "$R63E"
( cd "$R63E" && git init -q -b wave/1-x && git config user.name t && git config user.email t@t \
  && printf '.bionic/docs/plans/\n' > .gitignore && mkdir -p .bionic/docs/plans src \
  && echo a > src/a && git add -A && git commit -qm base ) >/dev/null 2>&1
S63E_B="$(git -C "$R63E" rev-parse HEAD)"
P63E="$R63E/.bionic/docs/plans/e.plan.md"
s63_edge_plan() {  # <reading head> -> P63E: single, task, with a base, the three questions read at that head
  printf -- '---\nrigor: single\nscale: task\nbase-sha: %s\n---\n# edges\n\n## SDLC State\n\nworking-branch: wave/1-x\n' "$S63E_B" > "$P63E"
  for s63q in evidence adversarial structure; do s57_fact "$s63q" "$1" pass piece "$P63E"; done
}
s63_adv_with() {  # <proof.sh> <head> -> the adversarial line's state under that library, on P63E
  bash -c '. "$1" && facts_state "$2" "$3"' _ "$1" "$P63E" "$2" 2>/dev/null \
    | F="$S63_TAD" awk 'index($0, ENVIRON["F"] "\t") == 1 { print substr($0, length(ENVIRON["F"]) + 2); exit }'
}
s63_mut() {  # <name> <needle> <replacement> -> a copy of the lib directory, its proof.sh with that one line changed
  local d="$TMPROOT/s63-mut-$1"
  rm -rf "$d"; cp -R "$(dirname "$S57_LIB")" "$d"
  N="$2" R="$3" awk '{ i = index($0, ENVIRON["N"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["R"] substr($0, i + length(ENVIRON["N"])); print }' \
    "$S57_LIB" > "$d/proof.sh"
  printf '%s' "$d/proof.sh"
}
( cd "$R63E" && git checkout -qb side && echo s > src/side && git add -A && git commit -qm side \
  && git checkout -q wave/1-x && echo d > .bionic/docs/n1 && git add -A && git commit -qm docs ) >/dev/null 2>&1
S63E_H0="$(git -C "$R63E" rev-parse HEAD)"
( cd "$R63E" && git merge -q --no-ff side -m merge ) >/dev/null 2>&1
S63E_HM="$(git -C "$R63E" rev-parse HEAD)"
( cd "$R63E" && git mv .bionic/docs/n1 src/n1 && git commit -qm 'rename out of the docs root' ) >/dev/null 2>&1
S63E_RO="$(git -C "$R63E" rev-parse HEAD)"
( cd "$R63E" && git mv src/n1 .bionic/docs/n2 && git commit -qm 'rename into the docs root' ) >/dev/null 2>&1
S63E_RI="$(git -C "$R63E" rev-parse HEAD)"
( cd "$R63E" && git checkout -qb gone && echo g >> src/a && git commit -qam gone && git checkout -q wave/1-x ) >/dev/null 2>&1
S63E_G="$(git -C "$R63E" rev-parse gone)"
expect_eq "63e0 precondition: the merge's second parent brought src/side; the renames moved n1 out and back in" \
  "src/side|R .bionic/docs/n1 src/n1|R src/n1 .bionic/docs/n2" \
  "$(git -C "$R63E" diff --name-only "$S63E_H0" "$S63E_HM")|$(git -C "$R63E" show -M --name-status --format= "$S63E_RO" | awk '{ print substr($1, 1, 1), $2, $3 }')|$(git -C "$R63E" show -M --name-status --format= "$S63E_RI" | awk '{ print substr($1, 1, 1), $2, $3 }')"
expect_eq "63e0b precondition: gone is not on the history of the working head" "1" \
  "$(git -C "$R63E" merge-base --is-ancestor "$S63E_G" "$S63E_RI"; echo $?)"
S63_NEEDLE_ANC='git -C "$tree" merge-base --is-ancestor "$lh" "$hh" 2>/dev/null || return 1'
S63_NEEDLE_REN='--no-renames --name-only --format= "$lh..$hh"'
S63_NEEDLE_MRG='--first-parent -m --no-renames'
S63_NEEDLE_ALL='[ "${f#"$pfx"}" != "$f" ] || _proof_docs_path "$f" || return 1'
for s63n in "$S63_NEEDLE_ANC" "$S63_NEEDLE_REN" "$S63_NEEDLE_MRG" "$S63_NEEDLE_ALL"; do
  expect_eq "63e0c precondition: the mutation site is one line of the shipped proof.sh: $s63n" "1" "$(/usr/bin/grep -cF -- "$s63n" "$S57_LIB")"
done
S63_M_ANC="$(s63_mut anc "$S63_NEEDLE_ANC" ':')"
S63_M_REN="$(s63_mut ren "$S63_NEEDLE_REN" '--name-only --format= "$lh..$hh"')"
S63_M_MRG="$(s63_mut mrg "$S63_NEEDLE_MRG" '--first-parent --diff-merges=off --no-renames')"
S63_M_ALL="$(s63_mut all "$S63_NEEDLE_ALL" '[ "${f#"$pfx"}" != "$f" ] || _proof_docs_path "$f" || return 1; return 0')"
# A merge, counted as what it brought in.
s63_edge_plan "$S63E_H0"
expect_eq "63e control: asked at the readings' own head, covered" "covered" "$(s63_adv_with "$S57_LIB" "$S63E_H0")"
expect_eq "63e2 F4 a merge that brings code from a side branch is uncovered from the last head" \
  "uncovered	${S63E_H0}..${S63E_HM}" "$(s63_adv_with "$S57_LIB" "$S63E_HM")"
expect_eq "63e3 mutation: a copy that lists no file for a merge (--diff-merges=off) still runs" "covered" "$(s63_adv_with "$S63_M_MRG" "$S63E_H0")"
expect_eq "63e4 …and reads the merge as covered, so 63e2 can fail" "covered" "$(s63_adv_with "$S63_M_MRG" "$S63E_HM")"
# A rename out of the docs root: the code path it adds is code.
s63_edge_plan "$S63E_HM"
expect_eq "63e5 F4 a rename out of the docs root into code is uncovered" "uncovered	${S63E_HM}..${S63E_RO}" "$(s63_adv_with "$S57_LIB" "$S63E_RO")"
expect_eq "63e6 mutation: a copy that judges a commit by its first path alone still runs" "covered" "$(s63_adv_with "$S63_M_ALL" "$S63E_HM")"
expect_eq "63e7 …and reads the rename out as covered, so 63e5 can fail" "covered" "$(s63_adv_with "$S63_M_ALL" "$S63E_RO")"
# A rename into the docs root: the code path it deletes is code.
s63_edge_plan "$S63E_RO"
expect_eq "63e8 F4 a rename of code into the docs root is uncovered" "uncovered	${S63E_RO}..${S63E_RI}" "$(s63_adv_with "$S57_LIB" "$S63E_RI")"
expect_eq "63e9 mutation: a copy without --no-renames still runs" "covered" "$(s63_adv_with "$S63_M_REN" "$S63E_RO")"
expect_eq "63e10 …and reads the rename in as docs only, covered, so 63e8 can fail" "covered" "$(s63_adv_with "$S63_M_REN" "$S63E_RI")"
# A last head that is not an ancestor of the head asked about.
s63_edge_plan "$S63E_G"
expect_eq "63e11 F4 a last head off the history of the head asked about is uncovered" "uncovered	${S63E_G}..${S63E_RI}" "$(s63_adv_with "$S57_LIB" "$S63E_RI")"
expect_eq "63e12 mutation: a copy without the ancestry check still runs" "covered" "$(s63_adv_with "$S63_M_ANC" "$S63E_G")"
expect_eq "63e13 …and reads it as covered, so 63e11 can fail" "covered" "$(s63_adv_with "$S63_M_ANC" "$S63E_RI")"
# A head that is not a commit: 63h to 63h7 above.

# ---------- §WAIVE-TEXT (F6): the reply and the name cannot move the question or the head ----------
s57_reset; s42_snap "$R57" "$P57"
git -C "$R57" config user.name 'Al "x" by question=structure head=0000000'
poke "$R57" waive adversarial "\" by question=structure head=${S57_C1} \\055 \\\\ \\\""
git -C "$R57" config user.name "Dana Fixture"
expect_eq "63v F6 waive with a crafted reply and git user.name writes (exit 0)" "0" "$RC"
expect_eq "63v2 …the line's question and head, read before its first by as the judge reads them, are the verb's" \
  "question=adversarial head=${S57_C4}" \
  "$(/usr/bin/grep -E '^waived: ' "$P57" | awk '{ for (i = 2; i <= NF && $i != "by"; i++) printf "%s%s", (i > 2 ? " " : ""), $i }')"
s57_state "$P57" "$S57_C4"
expect_eq "63v3 …so the judge covers adversarial and leaves structure absent" "covered absent" \
  "$(s57_of "$S57_AD") $(s57_of "$S57_ST")"

# ---------- §ONE-READER (review pass 16 findings 1 to 3): one pass, each key once, one reader ----------
# On section 58's repository and plan: its reader rows, its planted checks tree, its commits. New
# rows are planted for new names, each naming the records its cases register (the shape T41 holds).
s58_row r-dup bionic:auditor confirmed evidence "$S58_REL/dup-r.md" "$(s58_files dup-q.md dup-s.md dup-ok.md)"
s58_row r-dupc bionic:critic confirmed structure "$S58_REL/dup-c.md" "$(s58_files multi.md)"
s58_row r-sh1 bionic:auditor confirmed evidence "$S58_REL/shared.md" "$(s58_files solo.md)"
s58_row r-sh2 bionic:auditor confirmed evidence "" "$(s58_files shared.md)"
s58_rec dup-r.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: pass" "result: fail" "scope: piece"
s58_rec dup-q.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "question: adversarial" "result: pass" "scope: piece"
s58_rec dup-s.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: pass" "scope: piece" "scope: whole"
s58_rec dup-c.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: fail" "scope: piece" \
  "$S58_ALL" "check: reuse FAIL a second copy"
s58_rec dup-ok.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: pass" "scope: piece"
# The review's f1b record: a top pass whose checks leave out single-job, above a complete older pass.
s58_rec multi.md "reviewed: ${S58_C1}..${S58_C4}" "question: structure" "result: pass" "scope: piece" \
  "$(s56_checks single-job)" "" "reviewed: ${S58_C1}..${S58_C3}" "question: structure" "result: pass" "scope: piece" "$S58_ALL"
s58_rec shared.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: pass" "scope: piece"
s58_rec solo.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: flag" "scope: piece"
expect_eq "63r0 precondition: multi.md holds two flush-left reviewed: lines, its top pass without single-job" "2 0" \
  "$(/usr/bin/grep -c '^reviewed: ' "$S58_REC/multi.md") $(awk '/^reviewed: /{ n++ } n == 1 && /^check: single-job /' "$S58_REC/multi.md" | awk 'END { print NR }')"
s42_snap "$R58" "$P58"
POKER="$S58_POKER_TREE"
poke "$R58" proof-add review record/wave-01-fixture/dup-r.md --question evidence --reader r-dup
s42_unchanged "63r F1(16) result: pass then result: fail in one pass is not read as pass" 1 "$P58"
expect_contains "63r2 …naming the key given twice" "gives result: twice" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/dup-q.md --question evidence --reader r-dup
s42_unchanged "63r3 question: given twice" 1 "$P58"
expect_contains "63r4 …naming it" "gives question: twice" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/dup-s.md --question evidence --reader r-dup
s42_unchanged "63r5 scope: given twice" 1 "$P58"
expect_contains "63r6 …naming it" "gives scope: twice" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/dup-c.md --question structure --reader r-dupc
s42_unchanged "63r7 a check id answered twice (PASS, then FAIL)" 1 "$P58"
expect_contains "63r8 …naming the check" "gives check: reuse twice" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/multi.md --question structure --reader r-dupc
s42_unchanged "63r9 F3(16) a record of two passes whose top pass leaves single-job unanswered" 1 "$P58"
expect_contains "63r10 …refused for its passes, whatever they hold" "holds 2 passes" "$OUT"
POKER="$S58_POKER_REAL"
poke "$R58" proof-add review record/wave-01-fixture/shared.md --question evidence --reader r-sh1
s42_unchanged "63r11 F2(16) a record a second roster row also names, typed as the first reader" 1 "$P58"
expect_contains "63r12 …naming the other row" "named by the roster row r-sh2 (bionic:auditor)" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/shared.md --question evidence --reader r-sh2
s42_unchanged "63r13 …and typed as the second" 1 "$P58"
expect_contains "63r14 …naming the first" "named by the roster row r-sh1 (bionic:auditor)" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/solo.md --question evidence --reader r-sh1
expect_eq "63r15 control: a record only that reader names registers (exit 0)" "0" "$RC"
poke "$R58" proof-add review record/wave-01-fixture/dup-ok.md --question evidence --reader r-dup
expect_eq "63r16 control: one pass, each key once, registers (exit 0)" "0" "$RC"
expect_contains "63r17 …as that reader's pass" "evidence=record/wave-01-fixture/dup-ok.md question=evidence reader=r-dup result=pass scope=piece" \
  "$(s46_proved "$P58" | tail -1)"
# THE MUTATION: a proof.sh with the pass count switched off and the check scan reading the whole
# file admits multi.md, so 63r9 can fail; the shipped one refuses it.
S63_CK="$TMPROOT/s58-tree/context/checks-structure.md"
S63_NEEDLE_NP='[ "$got" -le 1 ] \'
S63_NEEDLE_MISS="miss=\"\$(printf '%s\\n' \"\$span\" | PROOF_IDS="
expect_eq "63r18 precondition: both mutation sites are one line each of the shipped proof.sh" "1 1" \
  "$(/usr/bin/grep -cF -- "$S63_NEEDLE_NP" "$S57_LIB") $(/usr/bin/grep -cF -- "$S63_NEEDLE_MISS" "$S57_LIB")"
S63_M_ONE="$(s63_mut one "$S63_NEEDLE_NP" 'true \')"
N="$S63_NEEDLE_MISS" R='miss="$(cat "$rec" | PROOF_IDS=' awk '{ i = index($0, ENVIRON["N"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["R"] substr($0, i + length(ENVIRON["N"])); print }' \
  "$S63_M_ONE" > "$S63_M_ONE.tmp" && mv "$S63_M_ONE.tmp" "$S63_M_ONE"
s63_read() {  # <proof.sh> <record> -> proof_reading's answer and exit, for structure
  bash -c '. "$1" && proof_reading "$2" structure "$3"; echo " rc=$?"' _ "$1" "$2" "$S63_CK" 2>/dev/null
}
expect_contains "63r19 the shipped proof_reading refuses multi.md for its passes" "holds 2 passes" "$(s63_read "$S57_LIB" "$S58_REC/multi.md")"
expect_contains "63r20 mutation: the doctored copy still reads a one-pass record (it runs)" "pass piece ${S58_C1} rc=0" \
  "$(s63_read "$S63_M_ONE" "$S58_REC/rc-pass-na.md")"
expect_contains "63r21 …and admits multi.md, so 63r9 can fail" "pass piece ${S58_C1} rc=0" "$(s63_read "$S63_M_ONE" "$S58_REC/multi.md")"

# ---------- §BASE-WORD, §BASE-FIRST, §RETRY (review pass 20 F1, F4, F3; wave-27 T14, A-orch-72) ----------
# F1: a `base-sha:` is a base only when it is 7 to 40 hex AND names a commit, so `HEAD` or a branch
# name, which resolve to wherever the checkout is, is no base, as `deadbeef` is not; the refusal
# says the value is not a commit id. F4: the base is the first of the places proof_plan_base reads
# (`## SDLC State`, then the frontmatter) whose value is 7 to 40 hex, so an empty or placeholder
# Step-4 value no longer hides a real frontmatter one; both refusals that send the user to add a
# base name the frontmatter. F3: the one-reader rule counts only a DIFFERENT name's row that is past
# `intended` and still open. On §BASE's plan (its readings registered from the base, above) and on
# §58's repository and rows.
s63x_sdlc() {  # <plan> <line> -> the line written under `working-branch:` inside ## SDLC State
  L="$2" awk '{ print } /^working-branch: / && !d { print ENVIRON["L"]; d = 1 }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
# The judge's rows plant at the head the working checkout is at NOW (S63X_H): §FLOOR-HEAD answers the
# floor line for that head alone, and the sections above have moved the checkout past S63_H.
S63X_H="$(git -C "$S63_WT" rev-parse HEAD)"
s63x_planted() {  # <copy> <frontmatter base or ""> [<SDLC line>] -> the no-base plan with its readings planted at S63X_H
  cp "$TMPROOT/s63-nobase" "$1"
  [ -z "$2" ] || s63_base "$1" "$2"
  [ -z "${3:-}" ] || s63x_sdlc "$1" "$3"
  for s63q in evidence adversarial structure; do s57_fact "$s63q" "$S63X_H" pass piece "$1"; done
  s57_floor "$S63X_H" "$1"
}
# The whole read first, on the plan as §BASE left it (three readings from the base registered).
cp "$P63" "$TMPROOT/s63x-registered"
sed "s/^base-sha: ${S63_I}\$/base-sha: HEAD/" "$P63" > "$P63.tmp" && mv "$P63.tmp" "$P63"
printf 'reviewed: %s..%s\nquestion: adversarial\nresult: pass\nscope: whole\n\nthe whole branch\n' "$S63_I" "$S63_H" > "$S63_REC/adversarial.md"
expect_eq "63x0 precondition: the plan's base reads HEAD, and its adversarial chain already has a reading" "1 yes" \
  "$(/usr/bin/grep -c '^base-sha: HEAD$' "$P63") $([ "$(/usr/bin/grep -c 'question=adversarial' "$P63")" -ge 1 ] && echo yes)"
s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/adversarial.md" --question adversarial --reader w-tcrit
s42_unchanged "63x F1 a whole read on a plan whose base-sha: is HEAD" 1 "$P63"
expect_contains "63x2 F4 …the whole-read refusal names the frontmatter, the place the other refusal names" "to the frontmatter of" "$OUT"
expect_contains "63x3 F1 …and says HEAD is not a commit id" "HEAD is not a commit id" "$OUT"
# A first reading on a plan whose base is HEAD, then a branch name.
cp "$TMPROOT/s63-nobase" "$P63"; s63_base "$P63" HEAD; s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/evidence.md" --question evidence --reader w-tcrit
s42_unchanged "63x4 F1 with base-sha: HEAD, a first reading over the whole branch" 1 "$P63"
expect_contains "63x5 …its first line naming the frontmatter line to add, and HEAD as no commit id" \
  "its base-sha: HEAD is not a commit id" "$(printf '%s\n' "$OUT" | head -1)"
cp "$TMPROOT/s63-nobase" "$P63"; s63_base "$P63" task/01-fixture; s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/evidence.md" --question evidence --reader w-tcrit
s42_unchanged "63x6 F1 with base-sha: task/01-fixture (the working branch), the same" 1 "$P63"
s63x_planted "$R63/.bionic/tmp/x-head.plan.md" HEAD
s57_state "$R63/.bionic/tmp/x-head.plan.md" "$S63X_H"
expect_eq "63x7 F1 facts_state on base-sha: HEAD exits 2, as on deadbeef (63b2b), printing nothing" "2 " "$S57_RC $S57_OUT"
s63x_planted "$R63/.bionic/tmp/x-branch.plan.md" task/01-fixture
s57_state "$R63/.bionic/tmp/x-branch.plan.md" "$S63X_H"
expect_eq "63x8 F1 …and on a branch name" "2 " "$S57_RC $S57_OUT"
s63x_planted "$R63/.bionic/tmp/x-abbr.plan.md" "${S63_I:0:7}"
s57_state "$R63/.bionic/tmp/x-abbr.plan.md" "$S63X_H"
expect_eq "63x9 F1 control: seven hex abbreviating a real commit is a base, every line covered" "0 $(s63_task_all covered covered)" "$S57_RC $S57_OUT"
# F4: a real frontmatter base beside a placeholder or empty Step-4 one.
s63x_planted "$R63/.bionic/tmp/x-tbd.plan.md" "$S63_I" "base-sha: TBD"
s57_state "$R63/.bionic/tmp/x-tbd.plan.md" "$S63X_H"
expect_eq "63x10 F4 frontmatter base real, ## SDLC State base-sha: TBD: judged against the frontmatter's, rc 0" \
  "0 $(s63_task_all covered covered)" "$S57_RC $S57_OUT"
s63x_planted "$R63/.bionic/tmp/x-empty.plan.md" "$S63_I" "base-sha:"
s57_state "$R63/.bionic/tmp/x-empty.plan.md" "$S63X_H"
expect_eq "63x11 F4 …and beside an empty one" "0 $(s63_task_all covered covered)" "$S57_RC $S57_OUT"
cp "$TMPROOT/s63-nobase" "$P63"; s63_base "$P63" "$S63_I"; s63x_sdlc "$P63" "base-sha: TBD"; s42_snap "$R63" "$P63"
poke "$R63" proof-add review "record/task-01-fixture/evidence.md" --question evidence --reader w-tcrit
expect_eq "63x12 F4 the verb on that plan: a first reading from the frontmatter base registers (exit 0)" "0" "$RC"
cp "$TMPROOT/s63x-registered" "$P63"
# F3: a reader dispatched again to the record of an earlier launch.
s58_row r-re1 bionic:auditor confirmed evidence "$S58_REL/retry1.md" ""
s58_row r-re0 bionic:auditor intended evidence "$S58_REL/retry1.md" ""
s58_row r-re2 bionic:auditor confirmed evidence "$S58_REL/retry2.md" ""
s58_row r-re0c bionic:auditor closed evidence "$S58_REL/retry2.md" ""
s58_row r-re3 bionic:auditor confirmed evidence "$S58_REL/retry3.md" ""
s58_row r-re3o bionic:auditor confirmed evidence "$S58_REL/retry3.md" ""
s58_row r-re4 bionic:auditor confirmed evidence "$S58_REL/retry4.md" ""
s58_row r-re4 bionic:auditor confirmed evidence "$S58_REL/retry4.md" ""
for s63n in 1 2 3 4; do
  s58_rec "retry$s63n.md" "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: pass" "scope: piece"
done
expect_eq "63x13 precondition: retry1.md is named by r-re1 (confirmed) and by r-re0 (intended)" "2" \
  "$(/usr/bin/grep -c 'retry1\.md' "$S58_RS")"
s42_snap "$R58" "$P58"
poke "$R58" proof-add review record/wave-01-fixture/retry1.md --question evidence --reader r-re1
expect_eq "63x14 F3 another name's row that is only intended is not counted: r-re1 registers (exit 0)" "0" "$RC"
poke "$R58" proof-add review record/wave-01-fixture/retry2.md --question evidence --reader r-re2
expect_eq "63x15 F3 …nor one that is closed: r-re2 registers (exit 0)" "0" "$RC"
s42_snap "$R58" "$P58"
poke "$R58" proof-add review record/wave-01-fixture/retry3.md --question evidence --reader r-re3
s42_unchanged "63x16 F3 another name's row launched and open still refuses, as today" 1 "$P58"
expect_contains "63x17 …naming it" "named by the roster row r-re3o (bionic:auditor)" "$OUT"
poke "$R58" proof-add review record/wave-01-fixture/retry4.md --question evidence --reader r-re4
expect_eq "63x18 F3 two rows of the reader's own name (a relaunch) register (exit 0)" "0" "$RC"
s58_row r-re5 bionic:auditor confirmed evidence "$S58_REL/retry5.md" ""
s58_row r-re5a bionic:auditor confirmed evidence "$S58_REL/retry5.md" ""
s58_rec retry5.md "reviewed: ${S58_C1}..${S58_C4}" "question: evidence" "result: pass" "scope: piece"
printf 'sweeper-ledger/v1|event=ack|name=r-re5a|at=2026-10-04T00:00:00Z|reason=landed\n' >> "$R58/.bionic/tmp/sweeper-$SID.state"
poke "$R58" proof-add review record/wave-01-fixture/retry5.md --question evidence --reader r-re5
expect_eq "63x19 F3 …nor another name's confirmed row acked after its launch: r-re5 registers (exit 0)" "0" "$RC"
# ---------- T31: a hex placeholder never hides a real base (wave-27 T31; review pass 25 F2) ----------
# The base is the first value, in the order of places, that is 7 to 40 hex AND names a commit in
# the plan's repository; a hex word that names none (`deadbeef`, forty zeros) is passed over as a
# non-hex word is. With no place naming a commit there is no base, and the refusal names the value.
R63Y="$(make_repo s63y-base)"; ( cd "$R63Y" && git commit -q --allow-empty -m B ) >/dev/null 2>&1
S63Y_B="$(git -C "$R63Y" rev-parse HEAD)"
S63Y_H="$(s57_commit "$R63Y" lib/a.sh H)"
s63y_plan() {  # <frontmatter base> <Step-4 base> -> the plan path
  local p
  p="$(s42_plan "$R63Y" 4 "  worktree: .
  base-sha: $2
  branch: main")"
  awk -v b="$1" '{ print } /^scale: / && !f { print "base-sha: " b; f = 1 }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  printf '%s' "$p"
}
P63Y="$(s63y_plan "$S63Y_B" deadbeef)"
expect_eq "63y F2 a real frontmatter base beside a Step-4 base-sha: deadbeef: the base is the real commit" "$S63Y_B" \
  "$(bash -c '. "$1" && proof_plan_base "$2" "$3"' _ "$S57_LIB" "$P63Y" "$R63Y")"
mkdir -p "$R63Y/.bionic/docs/record/wave-01-fixture"
printf 'reviewed: %s..%s\nquestion: evidence\nresult: pass\nscope: piece\n' "$S63Y_B" "$S63Y_H" > "$R63Y/.bionic/docs/record/wave-01-fixture/r63y.md"
expect_eq "63y2 …and a first reading from it is attested (proof_attested, what proof-add review holds a reading to)" "0 $S63Y_H" \
  "$(bash -c '. "$1" && x="$(proof_attested review "$2" "$3" "$4" evidence)"; printf "%s %s" "$?" "$x"' _ "$S57_LIB" \
      "$R63Y/.bionic/docs/record/wave-01-fixture/r63y.md" "$R63Y" "$P63Y")"
S63Y_ERR="$(bash -c '. "$1" && facts_state "$2" "$3" 2>&1 >/dev/null; echo "rc=$?"' _ "$S57_LIB" "$P63Y" "$S63Y_H")"
expect_eq "63y3 …and the judge deals the plan (no exit 2, nothing said about its base)" "rc=1" "$S63Y_ERR"
P63Y="$(s63y_plan 0000000000000000000000000000000000000000 deadbeef)"
S63Y_ERR="$(bash -c '. "$1" && facts_state "$2" "$3" 2>&1 >/dev/null; echo "rc=$?"' _ "$S57_LIB" "$P63Y" "$S63Y_H")"
expect_contains "63y4 both places hex and neither a commit: no base, the judge exits 2" "rc=2" "$S63Y_ERR"
expect_contains "63y5 …naming the value it found and that it is no commit here" "its base-sha: deadbeef is no commit here" "$S63Y_ERR"
POKE_BOUND="$S63_BOUND_WAS"

# ============================================================
section "Section 64 §DEBT: a declared red that landed is a fact the run owes until a green run after its token cleared (wave-27 T31; REQ-14 AC-14.3, AC-14.2; D23)"
# ============================================================
#
# `land` prints `landed-red=<suite>` for a row that declared its red at dispatch, and the
# orchestrator's state line for the row records `landed red: <suite> until <token>`.
# `facts_owed <rigor> <scale> <tree> <plan>` then deals one `debt<TAB><suite><TAB><token>` per such
# line, and `facts_state` answers it `covered` only when a floor proof, or a task proof whose log
# shows that suite green, carries an `at=` later than the token's clearing (an `approval:` token
# clears at its `approved:` line), `absent` otherwise; `current 8`, which asks the judge, refuses
# while it is open. `amend` has no way to add the declaration.
#
# FIXTURE FIDELITY. §61's shape: a plan bound to this session at `current: 7`, its working branch
# in a linked worktree, every reading and the floor at the head written by the production writers
# (s61-style, proof_line placed by proof_add_line, at 2026-10-04T12:00:00Z), and §47's reads
# column so `approve release` (the verb that writes the approved: line) has a row reading it; the row
# is a verify row, so it reads head beside it (wave-30 T13, AC-4.3: a verify row may not drop head). The
# debt is written to the run's landing record by `land`'s own writer (lib/worktree.sh
# `_wt_debt_write`, wave-27 T67; A-orch-120), never as a plan line: the judge reads the record.
S64_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R64="$(make_repo s64-debt)"; ( cd "$R64" && git commit -q --allow-empty -m init )
git -C "$R64" config user.name "Dana Fixture"
S64_B="$(git -C "$R64" rev-parse HEAD)"
P64="$(s42_plan "$R64" 7 "  worktree: .worktrees/01-fixture
  base-sha: ${S64_B:0:8}
  branch: wave/01-fixture")"
awk '
  /^current: / && !d { print; print "working-branch: wave/01-fixture"; d = 1; next }
  /^\| id \| step \|/ { print $0 " reads |"; next }
  /^\|---\|/ { print $0 "---|"; next }
  /^\| T5 \|/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " approval:release, head |"; next }
  /^\| T[0-9]+ \|/ { print $0 "  |"; next }
  { print }' "$P64" > "$P64.tmp" && mv "$P64.tmp" "$P64"
( cd "$R64" && git add -f "$P64" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R64/.worktrees/01-fixture" "$S64_B" ) >/dev/null 2>&1
S64_WT="$R64/.worktrees/01-fixture"
S64_H="$(s57_commit "$S64_WT" lib/a.sh C1)"
S64_REC="$R64/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S64_REC"
s64_add() {  # <line> -> placed in P64 by the production placer
  bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$S61_LIB" "$P64" "$1" > "$P64.new" && mv "$P64.new" "$P64"
}
s64_proof() {  # <kind> <at> <evidence under record/>
  s64_add "$(bash -c '. "$1" && proof_line "$2" "$3" "$4" "$5"' _ "$S61_LIB" "$1" "$S64_H" "$2" "$3")"
}
s64_owed() {  # the floor and every reading owed at the head, all at 2026-10-04T12:00:00Z
  local q
  s64_proof floor 2026-10-04T12:00:00Z record/wave-01-fixture/floor.log
  for q in evidence adversarial structure; do
    s64_add "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" piece' \
      _ "$S61_LIB" "$S64_H" "record/wave-01-fixture/$q.md" "$q" pass)"
  done
  for q in adversarial structure; do
    s64_add "$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" "$4" w-read "$5" whole' \
      _ "$S61_LIB" "$S64_H" "record/wave-01-fixture/$q-whole.md" "$q" pass)"
  done
}
s64_owed
cp "$P64" "$TMPROOT/s64-clean"
S64_WTLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/worktree.sh"
S64_LOG="$S64_REC/landing-proofs.log"
s64_debt() {  # <suite> <token> <at> [<id>] -> one debt line appended by land's own writer
  bash -c '. "$1" && _wt_debt_write "$2" "$3" T9 wt/27-T9 "$4" "$5" "$6" "$7"' _ "$S64_WTLIB" "$S64_LOG" \
    "${4:-d$RANDOM$RANDOM}" "$S64_H" "$1" "$2" "$3"
}
s64_debt_reset() { rm -f "$S64_LOG"; }
s64_debt widget.test.sh approval:release 2026-10-04T11:00:00Z
s64_reset() { cp "$TMPROOT/s64-clean" "$P64"; }
S64_DEBT="$(printf 'debt\twidget.test.sh\tapproval:release')"

# ---------- the dealing ----------
expect_eq "64a §DEBT facts_owed with the plan deals one debt line per debt land wrote to the landing record" "$S64_DEBT" \
  "$(bash -c '. "$1" && facts_owed double wave "$2" "$3"' _ "$S61_LIB" "$R64" "$P64" | /usr/bin/grep '^debt')"
expect_eq "64a2 …and the dealing of a rigor alone carries none (the positive above is the same function)" "" \
  "$(bash -c '. "$1" && facts_owed double wave "$2"' _ "$S61_LIB" "$R64" | /usr/bin/grep '^debt')"

# ---------- open: absent, and current 8 refused ----------
s57_state "$P64" "$S64_H"
expect_eq "64b AC-14.3 the judge says the debt absent while its token has not cleared" "absent" "$(s57_of "$S64_DEBT")"
expect_eq "64b2 …so the run does not hold (rc 1)" "1" "$S57_RC"
expect_eq "64b3 …while the floor at the head is covered" "covered" "$(s57_of floor)"
s42_snap "$R64" "$P64"
poke "$R64" current 8
s42_unchanged "64c AC-14.3 current 8 with the debt open" 1 "$P64"
expect_contains "64c2 …printing the judge's line for it" "$(printf 'debt\twidget.test.sh\tapproval:release\tabsent')" "$OUT"

# ---------- the token clears; a green proof dated before it does not cover ----------
poke "$R64" approve release 'Ship it.'
expect_eq "64d0 precondition: approve release wrote the approved: line" "0" "$RC"
S64_AP="$(sed -n 's/^approved: release by Dana Fixture \([^ ]*\) .*/\1/p' "$P64")"
expect_regex "64d0b …at a UTC time later than the fixture's proofs" '^20[0-9]{2}-' "$S64_AP"
s57_state "$P64" "$S64_H"
expect_eq "64d …with only the floor proof dated BEFORE the approval, the debt is still absent" "absent" "$(s57_of "$S64_DEBT")"
cp "$P64" "$TMPROOT/s64-approved"

# ---------- a floor proof after the clearing covers it, and current 8 is admitted ----------
s64_proof floor 2099-01-01T00:00:00Z record/wave-01-fixture/floor-late.log
s57_state "$P64" "$S64_H"
expect_eq "64e a floor proof whose at= is later than the approval covers the debt" "covered" "$(s57_of "$S64_DEBT")"
expect_eq "64e2 …and the run holds (rc 0)" "0" "$S57_RC"
s42_snap "$R64" "$P64"
poke "$R64" current 8
expect_eq "64f …and current 8 is admitted" "0" "$RC"

# ---------- a task proof covers it only when its log shows that suite green ----------
cp "$TMPROOT/s64-approved" "$P64"
printf 'widget.test.sh: 12/12 passed, 0 failed\nrc=0\n' > "$S64_REC/widget-green.log"
printf 'other.test.sh: 9/9 passed, 0 failed\nrc=0\n' > "$S64_REC/other-green.log"
s64_proof task 2099-01-01T00:00:00Z record/wave-01-fixture/other-green.log
s57_state "$P64" "$S64_H"
expect_eq "64g a later task proof whose log shows another suite green does not cover it" "absent" "$(s57_of "$S64_DEBT")"
s64_proof task 2099-01-01T00:00:01Z record/wave-01-fixture/widget-green.log
s57_state "$P64" "$S64_H"
expect_eq "64g2 …one whose log shows widget.test.sh green does" "covered" "$(s57_of "$S64_DEBT")"
cp "$TMPROOT/s64-approved" "$P64"
printf 'widget.test.sh: 11/12 passed, 1 failed\nrc=1\n' > "$S64_REC/widget-red.log"
s64_proof task 2099-01-01T00:00:00Z record/wave-01-fixture/widget-red.log
s57_state "$P64" "$S64_H"
expect_eq "64g3 …and one whose log shows it red does not" "absent" "$(s57_of "$S64_DEBT")"

# ---------- amend cannot add the declaration ----------
poke "$R64" amend w1 --lands-red+ 'widget.test.sh until approval:release' --reason 'land it red'
expect_eq "64h AC-14.2 amend has no way to add a declaration: --lands-red+ is a usage refusal (exit 2)" "2" "$RC"
expect_contains "64h2 …naming the argument" "unknown argument for amend: --lands-red+" "$OUT"
poke "$R64" amend w1 --red-evidence+ record/wave-01-fixture/T9-red.md --reason 'land it red'
expect_eq "64h3 …and so is --red-evidence+" "2" "$RC"

# ---------- the debt's own time (A-orch-85): a debt line whose at= is no <ISO-UTC>, never covered ----------
cp "$TMPROOT/s64-approved" "$P64"
s64_debt_reset; s64_debt widget.test.sh approval:release sometime
s64_proof floor 2099-01-01T00:00:00Z record/wave-01-fixture/floor-late.log
s57_state "$P64" "$S64_H"
expect_regex "64i a debt whose at= is no <ISO-UTC> is never covered: absent, the judge naming the missing time" \
  '^absent	.*at=<ISO-UTC>' "$(s57_of "$S64_DEBT")"
s64_debt_reset; s64_debt widget.test.sh approval:release 2026-10-04T11:00:00Z

# ---------- an ext: debt (A-orch-85): the slug gone from every ## Tasks cell, and a green run after the red landing ----------
S64_EXT="$(printf 'debt\twidget.test.sh\text:vendor-key')"
s64_ext_plan() {  # <slug still in T2's deps cell: yes|no> -> P64 clean, the record holding one ext: debt in place of the approval one
  cp "$TMPROOT/s64-clean" "$P64"
  s64_debt_reset; s64_debt widget.test.sh ext:vendor-key 2026-10-05T04:00:00Z
  awk -v keep="$1" '
    keep == "yes" && /^\| T2 \|/ { sub(/\| — \| 30 \|/, "| ext:vendor-key | 30 |") }
    { print }' "$P64" > "$P64.tmp" && mv "$P64.tmp" "$P64"
}
s64_ext_plan yes
expect_eq "64j0 precondition: the slug sits in T2's deps cell" "1" "$(/usr/bin/grep -c '^| T2 |.*ext:vendor-key' "$P64")"
s64_proof floor 2026-10-05T05:00:00Z record/wave-01-fixture/floor-05.log
s57_state "$P64" "$S64_H"
expect_eq "64j the slug still in a cell, a floor proof at 05:00Z after the 04:00Z red landing: absent" "absent" "$(s57_of "$S64_EXT")"
s64_ext_plan no
s64_proof floor 2026-10-05T05:00:00Z record/wave-01-fixture/floor-05.log
s57_state "$P64" "$S64_H"
expect_eq "64j2 the slug removed from every cell, the same floor proof: covered" "covered" "$(s57_of "$S64_EXT")"
s64_ext_plan no
s64_proof floor 2026-10-05T03:00:00Z record/wave-01-fixture/floor-03.log
s57_state "$P64" "$S64_H"
expect_eq "64j3 the slug removed and the only green proof dated 03:00Z, before the red landing: absent" "absent" "$(s57_of "$S64_EXT")"
POKE_BOUND="$S64_BOUND_WAS"
# ============================================================
section "Section 65 §DECLINE-VERB §DECLINE-LOG §BUDGET-USER: a wall is never answered on the console (wave-27 T34; REQ-15 AC-15.1, AC-15.4, AC-15.5; D24)"
# ============================================================
#
# THE DEFECT (design ledger Δ9, Δ10). The turn-end fill wall was answered by a `fill-declined:`
# line in the orchestrator's reply, which the user read on every turn and which said nothing to a
# person. `decline <id>[,<id>] '<reason>'` records the decline as one line in the run's fill
# ledger, the line a reply-form turn leaves there, so the tick and the wall read it by the rule
# they already apply (`fill_standing_decline`): it answers the rows it names and stands until a
# row it did not name is ready. A user's cap on writers is no decline at all: `budget
# writers=<n> '<reply>'` writes it into the plan header every reader of the ceiling reads.
S65_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R65="$(make_repo s65-decline)"; new_roster "$R65"
P65="$(s31_task_plan "$R65" T1)"
bind_marker "$R65" "$P65"
add_row "$R65" name=T1 deliverable=t1.md duration="4 hours" launched_at="$(iso_ago 60)"
s65_led() { cat "$1/.bionic/docs/record/${2:-task-01-fixture}/fill-ledger.log" 2>/dev/null; }
s65_field() {  # <ledger line> <key>
  printf '%s\n' "$1" | awk -F'|' -v k="$2" '{ for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) print substr($i, length(k) + 2) }'
}
s65_count() { s65_led "$@" | /usr/bin/grep -c '^fill-ledger/v1|' | tr -d ' '; }
require_helpers s65_led s65_field s65_count
poke_pressure "$R65" 8192 1.0 tick
expect_contains "65a precondition: the tick fills the two ready rows" "poker: FILL T2 T3" "$OUT"
poke "$R65" decline T2,T3 'the machine is saturated'
expect_eq "65b §DECLINE-VERB the verb records the decline (exit 0)" "0" "$RC"
S65_LINE="$(s65_led "$R65" | tail -1)"
expect_eq "65b2 §DECLINE-LOG AC-15.5 the run's fill ledger gains one line naming its ids" "T2,T3" "$(s65_field "$S65_LINE" named)"
expect_eq "65b3 …its reason" "the machine is saturated" "$(s65_field "$S65_LINE" declined)"
S65_AT="$(s65_field "$S65_LINE" at)"
expect_regex "65b4 …and its time" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$S65_AT"
poke_pressure "$R65" 8192 1.0 tick
expect_contains "65c AC-15.1 the next tick prints the standing decline, its time and its reason, in the reply form's words" \
  "poker: fill-declined standing since ${S65_AT} — the machine is saturated" "$OUT"
expect_absent "65c2 …and no FILL for the rows it named" "poker: FILL" "$OUT"
printf '| T4 | bugfix | standard | a unit nobody declined | pending | — |\n' >> "$P65"
poke_pressure "$R65" 8192 1.0 tick
expect_eq "65d a row the decline did not name is ready: the tick fills it alone" "poker: FILL T4" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -m1 '^poker: FILL T')"
S65_TR="$(s31_transcript "$R65" "carry on")"
s31_stop "$R65" "$S65_TR"
expect_eq "65e …and the wall refuses the silent turn" "block" "$(s31_decision)"
expect_contains "65e2 …naming T4 in the verb it prints" "session-poker.sh decline T4 'why they wait'" "$(s31_reason)"
expect_absent "65e3 …and asking for no line in the reply" 'write "fill-declined:' "$(s31_reason)"
S65_N="$(s65_count "$R65")"
poke "$R65" decline T9 'no such row'
expect_eq "65f an id that is no plan row is refused (exit 1)" "1" "$RC"
expect_contains "65f2 …saying which" "T9" "$OUT"
poke "$R65" decline T1 'it is running'
expect_eq "65g a row that is not ready is refused (exit 1)" "1" "$RC"
expect_contains "65g2 …saying which" "T1" "$OUT"
poke "$R65" decline T4 ''
expect_eq "65h an empty reason is refused (exit 2)" "2" "$RC"
poke "$R65" decline
expect_eq "65i no ids is refused: there is no decline-everything form (exit 2)" "2" "$RC"
expect_eq "65j …and no refusal wrote a ledger line" "$S65_N" "$(s65_count "$R65")"
expect_ne "65j2 precondition: the count is of real lines" "0" "$S65_N"
poke "$R65" decline T4 'T4 waits for the same machine'
expect_eq "65k §DECLINE-LOG each decline is one more line" "$((S65_N + 1))" "$(s65_count "$R65")"
poke_pressure "$R65" 8192 1.0 tick
expect_absent "65k2 …and the rows the first decline named stay answered beside the second's" "poker: FILL" "$OUT"
expect_contains "65k3 …the newer reason standing" "— T4 waits for the same machine" "$OUT"

# ---------- §BUDGET-USER (AC-15.4): the user's cap is written into the header ----------
R65B="$(make_repo s65-budget)"; ( cd "$R65B" && git commit -q --allow-empty -m init )
git -C "$R65B" config user.name "Dana Fixture"
P65B="$(s42_plan "$R65B" 4)"
awk '{ print } /^\| T5 \| 5 \| verify \|/ { print "| T6 | 4 | build | a ready build | implementor | — | 30 | REQ-1 | c.sh | — | — | pending |" }' \
  "$P65B" > "$P65B.tmp" && mv "$P65B.tmp" "$P65B"
s42_snap "$R65B" "$P65B"
s34_gate "$R65B"
expect_eq "65m0 precondition: the fixture with a ready build row is admitted by the real commit gate" "0" "$GATE_RC"
new_roster "$R65B"
for s65w in w-a w-b w-c; do
  add_row "$R65B" name="$s65w" deliverable="$s65w.md" duration="4 hours" launched_at="$(iso_ago 60)"
done
poke_pressure "$R65B" 8192 1.0 tick
expect_contains "65m control: the probe's eight writers with three open offer the ready row" "poker: FILL T6" "$OUT"
poke "$R65B" budget writers=3 'keep it at three'
expect_eq "65n AC-15.4 budget writers=3 exits 0" "0" "$RC"
expect_eq "65n2 …the header's writers value is the user's, with source=user" \
  "parallel-budget: writers=3 suites=4 worktrees=32 test_jobs=8 source=user" "$(/usr/bin/grep '^parallel-budget:' "$P65B")"
expect_regex "65n3 …and the frontmatter carries budget-override: <user> <date> derived=<n> chosen=<n>" \
  '^budget-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} derived=8 chosen=3$' "$(/usr/bin/grep '^budget-override:' "$P65B")"
expect_eq "65n4 …inside the frontmatter, after the budget line" "parallel-budget" \
  "$(awk 'NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f && /^budget-override:/ { print prev; exit } f { split($0, a, ":"); prev = a[1] }' "$P65B")"
# The gate is asked with the three writers' roster set aside: the plan is what is judged here.
mv "$(roster_of "$R65B")" "$TMPROOT/s65-roster"
s34_gate "$R65B"
mv "$TMPROOT/s65-roster" "$(roster_of "$R65B")"
expect_eq "65n5 …and the commit gate admits the plan" "0" "$GATE_RC"
S65B_LINES="$(s65_count "$R65B" wave-01-fixture)"
poke_pressure "$R65B" 8192 1.0 tick
expect_absent "65o with the user's cap reached the tick offers no writer row" "poker: FILL" "$OUT"
expect_contains "65o2 …saying the cap is reached at the user's three" "the cap writers=3 is reached" "$OUT"
S65B_TR="$(s31_transcript "$R65B" "carry on")"
s31_stop "$R65B" "$S65B_TR"
expect_eq "65p …and the turn-end wall asks for nothing" "" "$(s31_decision)"
expect_eq "65p2 …with no decline recorded" "" "$(s65_field "$(s65_led "$R65B" wave-01-fixture | tail -1)" declined)"
expect_eq "65p3 precondition: the wall wrote its turn's line" "$((S65B_LINES + 1))" "$(s65_count "$R65B" wave-01-fixture)"
s42_snap "$R65B" "$P65B"
poke "$R65B" budget writers=0 'stop everything'
s42_unchanged "65q writers=0" 1 "$P65B"
expect_contains "65q2 …saying a cap of none is no budget" "writers=0" "$OUT"
poke "$R65B" budget writers=six 'six'
s42_unchanged "65q3 a value that is not a number" 1 "$P65B"
poke "$R65B" budget suites=3 'three suites'
s42_unchanged "65q4 a field other than writers" 2 "$P65B"
poke "$R65B" budget writers=3
s42_unchanged "65q5 no reply" 2 "$P65B"
# 65r re-pinned by wave-27 T37 (review pass 42 N2, A-orch-112): the verb only lowers; a value above
# the derived ceiling is refused (section 67 §BUDGET-LOWERS), so 65r reads the refusal.
poke "$R65B" budget writers=12 'go wide'
s42_unchanged "65r a value above the probe's derived ceiling is refused: budget only lowers" 1 "$P65B"
expect_contains "65r2 …the header still reads the user's three" "parallel-budget: writers=3 suites=4" "$(cat "$P65B")"
expect_regex "65r3 …and derived= is still the probe's eight" \
  '^budget-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} derived=8 chosen=3$' "$(/usr/bin/grep '^budget-override:' "$P65B")"
expect_eq "65r4 …one override line" "1" "$(/usr/bin/grep -c '^budget-override:' "$P65B" | tr -d ' ')"
# §CAP-USER, THE VERB'S HALF (wave-28 T9; D15, REQ-2 AC-2.10). No plan owes the line, so `budget` on
# a plan with none no longer refuses ("Step 0 writes it"): it writes `parallel-budget: writers=<n>
# source=user` below the opening `---`, and an override line with no `derived=`, as nothing was
# derived. On a 1.12.0 plan carrying the probe's line the cap in force is a person's (`budget_cap`),
# which a probe line is not, so a number above the probe's is recorded, the probe's kept as
# `derived=`. fails-when: the no-line plan is refused or left without a line; the probe's 8 refuses 12.
R65N="$(make_repo s65-budget-noline)"; ( cd "$R65N" && git commit -q --allow-empty -m init )
git -C "$R65N" config user.name "Dana Fixture"
P65N="$(s42_plan "$R65N" 4)"
/usr/bin/grep -v '^parallel-budget:' "$P65N" > "$P65N.tmp" && mv "$P65N.tmp" "$P65N"
s42_snap "$R65N" "$P65N"
expect_absent "65s0 meta: the plan carries no parallel-budget: line" "parallel-budget" "$(cat "$P65N")"
poke "$R65N" budget writers=3 'three at most'
expect_eq "65s §CAP-USER budget writers=3 on a plan with no line exits 0" "0" "$RC"
expect_eq "65s2 …and writes the line, a person's" "parallel-budget: writers=3 source=user" \
  "$(/usr/bin/grep '^parallel-budget:' "$P65N")"
expect_regex "65s3 …with the override line, no derived= (nothing was derived)" \
  '^budget-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} chosen=3$' "$(/usr/bin/grep '^budget-override:' "$P65N")"
expect_eq "65s4 …inside the leading frontmatter, first" "parallel-budget: writers=3 source=user" "$(sed -n 2p "$P65N")"
R65Q="$(make_repo s65-budget-probe)"; ( cd "$R65Q" && git commit -q --allow-empty -m init )
git -C "$R65Q" config user.name "Dana Fixture"
P65Q="$(s42_plan "$R65Q" 4)"
sed 's/^\(parallel-budget: .*\)source=user/\1source=probe/' "$P65Q" > "$P65Q.tmp" && mv "$P65Q.tmp" "$P65Q"
s42_snap "$R65Q" "$P65Q"
expect_contains "65t0 meta: the plan carries the probe's eight" "parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe" "$(cat "$P65Q")"
poke "$R65Q" budget writers=12 'twelve'
expect_eq "65t §CAP-USER the probe's 8 is no cap: writers=12 is recorded (exit 0)" "0" "$RC"
expect_eq "65t2 …the line is the person's now" "parallel-budget: writers=12 suites=4 worktrees=32 test_jobs=8 source=user" \
  "$(/usr/bin/grep '^parallel-budget:' "$P65Q")"
expect_regex "65t3 …and derived= keeps the probe's eight" \
  '^budget-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} derived=8 chosen=12$' "$(/usr/bin/grep '^budget-override:' "$P65Q")"
POKE_BOUND="$S65_BOUND_WAS"


# ============================================================
section "Section 66 §AMEND-ID §UNCHECKED: amend records a set for an agent its start did not place, and the tick says a reader started without its checks (wave-27 T38; review pass 8 F3, pass 31 F2)"
# ============================================================
#
# THE DEFECT (review pass 8 F3). An agent the recorder's start join cannot place (two launches of
# its type, or a type that is not a bionic: role) has no roster row until its launch call returns,
# and a foreground call returns when it has finished, so the budget wall refused every suite it
# named for its whole life. The refusal's remedy named an act no verb performed, and `amend` on
# an id-less row exited 0 whether or not anything would ever read what it wrote. Now the refusal
# prints `amend <agent id>`; `amend` reads its target as a name, then as an agent id: an id a named
# row carries amends that row, and an id no row carries that ran as an agent of this session
# gets a row of its own (`status=unplaced`, the suite set alone, no contract). Anything else is
# refused saying why, and nothing is written.
#
# AND REVIEW PASS 31 F2. A reader whose start could not be placed among candidates carrying
# different `questions=` started with no checks, and only stderr said so. The recorder now appends
# `start-unchecked/v1|event=start|…`; the tick prints it ONCE, as a NOTIFY line, and writes
# `event=told` beside it.
#
# FIXTURE FIDELITY: launch rows through `roster_row_fixture` → `roster_row`, the dispatch wall's
# shape, launched now; the agent's start through the real hooks/execution-recorder.sh; the agent's
# transcript where the harness writes it, `<config>/projects/<dir>/<session>/subagents/agent-<id>.jsonl`
# (record/epic-15-kill-interception-experiment.md §2.5). The start-unchecked line is the one the
# recorder writes, its shape pinned in tests/execution-recorder.test.sh CK-h.
#
# fails-when: an id-less row's amend says nothing of an agent already running unplaced; an id no row
# carries is refused although it ran here, or recorded although it did not; an amend that changes
# nothing exits 0; the NOTIFY line is missing, or printed twice.
S66_CFG="$TMPROOT/s66-config"
S66_TR="$S66_CFG/projects/-s66/$SID.jsonl"
mkdir -p "$S66_CFG/projects/-s66/$SID/subagents"; : > "$S66_TR"
export CLAUDE_CONFIG_DIR="$S66_CFG"
S66_REC="$(dirname "$POKER")/execution-recorder.sh"
s66_launch() {  # <repo> <name> <tool_use_id> <subagent_type> [key=value...] — the dispatch wall's launch row
  local repo="$1" name="$2" tu="$3" ty="$4"; shift 4
  roster_row_fixture status=intended "session=$SID" "name=$name" agent_id= \
    "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "subagent_type=$ty" "tool_use_id=$tu" \
    files= suites_allowed=a.test.sh suites_source=declared "$@" >> "$(roster_of "$repo")"
}
s66_start() {  # <repo> <agent type> <agent id> — the agent's own start, through the recorder
  jq -n --arg s "$SID" --arg t "$S66_TR" --arg c "$1" --arg at "$2" --arg a "$3" \
    '{session_id:$s, transcript_path:$t, cwd:$c, agent_id:$a, agent_type:$at, hook_event_name:"SubagentStart"}' \
    | ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$S66_REC" >/dev/null 2>&1 )
}
s66_ran() { : > "$S66_CFG/projects/-s66/$SID/subagents/agent-$1.jsonl"; }  # <agent id> — its transcript, on disk
s66_pick() { roster_row_for_id "$(roster_of "$1")" "$2" 2>/dev/null; }

# ---------- 66a: an id-less row by name records the set, and the identification carries it ----------
R66A="$(make_repo s66-idless)"; new_roster "$R66A"
s66_launch "$R66A" w66 toolu_w66 bionic:implementor
poke "$R66A" amend w66 --suites+ tests/b.test.sh --reason 'before it starts'
expect_eq "66a1 amend on an id-less row exits 0: the set is recorded on its successor" "0" "$RC"
expect_contains "66a2 …and says when the walls read it: at its start or its launch call's return" \
  "once w66 is identified, at its start or its launch call's return" "$OUT"
expect_contains "66a3 …and how an agent already running unplaced is amended: by its agent id" \
  "amended by the agent id its refusal prints" "$OUT"
s66_start "$R66A" bionic:implementor aw66-6600000000000001
expect_eq "66a4 the start's identified row carries the amended set (the identification copied it)" "a.test.sh b.test.sh" \
  "$(s30_field "$(s66_pick "$R66A" aw66-6600000000000001)" suites_allowed)"

# ---------- 66b: an agent by id that no row carries, whose transcript is on disk ----------
# Two launches of one type and a nameless start: the start is placed on neither.
R66B="$(make_repo s66-byid)"; new_roster "$R66B"
s66_launch "$R66B" u1 toolu_u1 bionic:test-runner
s66_launch "$R66B" u2 toolu_u2 bionic:test-runner
S66B_ID="au66-6600000000000002"
s66_start "$R66B" bionic:test-runner "$S66B_ID"
expect_empty "66b0 precondition: no row carries the unplaced agent's id" "$(s66_pick "$R66B" "$S66B_ID")"
expect_contains "66b0 precondition: …while both launches are on the roster" "|name=u2|" "$(cat "$(roster_of "$R66B")")"
s66_ran "$S66B_ID"
poke "$R66B" amend "$S66B_ID" --suites+ tests/c.test.sh --reason 'its refusal asked'
expect_eq "66b1 amend <agent id> for an agent no row carries exits 0" "0" "$RC"
expect_contains "66b2 …saying it recorded the set for that id" "poker: amended — $S66B_ID, an agent its start did not place: suites=c.test.sh" "$OUT"
S66B_ROW="$(s66_pick "$R66B" "$S66B_ID")"
expect_eq "66b3 the budget wall's pick for the id is the row amend wrote" "unplaced" "$(s30_field "$S66B_ROW" status)"
expect_eq "66b4 …carrying the set" "c.test.sh" "$(s30_field "$S66B_ROW" suites_allowed)"
expect_eq "66b5 …named by the id, so it shadows no other name" "$S66B_ID" "$(s30_field "$S66B_ROW" name)"
expect_nonempty "66b6 …and waived: it holds no contract a verdict would judge" "$(s30_field "$S66B_ROW" waiver)"
expect_contains "66b7 …and says why it was written" "its refusal asked" "$(s30_field "$S66B_ROW" amended)"
poke "$R66B" amend "$S66B_ID" --suites+ tests/d.test.sh --reason 'one more'
expect_eq "66b8 a second amend by the same id exits 0" "0" "$RC"
expect_eq "66b9 …and widens the set it recorded, old members first" "c.test.sh d.test.sh" \
  "$(s30_field "$(s66_pick "$R66B" "$S66B_ID")" suites_allowed)"

# ---------- 66c: a no-op is refused, and nothing is written ----------
S66C_SUM="$(cksum < "$(roster_of "$R66B")")"
poke "$R66B" amend "$S66B_ID" --suites+ tests/d.test.sh --reason 'again'
expect_eq "66c1 an amend by id that adds nothing it lacks is refused (exit 1)" "1" "$RC"
expect_contains "66c2 …saying it changes nothing" "this amend changes nothing" "$OUT"
expect_eq "66c3 …and the roster is unchanged" "$S66C_SUM" "$(cksum < "$(roster_of "$R66B")")"
poke "$R66B" amend aw66-nosuchagent0000 --suites+ tests/c.test.sh --reason 'a typo'
expect_eq "66c4 an id that no row carries and that never ran here is refused (exit 1)" "1" "$RC"
expect_contains "66c5 …saying why: no agent of that id ran in this session" "no agent aw66-nosuchagent0000 ran in this session" "$OUT"
expect_eq "66c6 …and nothing is written" "$S66C_SUM" "$(cksum < "$(roster_of "$R66B")")"
poke "$R66B" amend "$S66B_ID" --files+ hooks/a.sh --reason 'files'
expect_eq "66c7 --files+ for an agent its start did not place is refused (exit 1)" "1" "$RC"
expect_contains "66c8 …saying a Files: contract belongs to its dispatched row" "a Files: contract belongs to its dispatched row" "$OUT"
expect_eq "66c9 …and nothing is written" "$S66C_SUM" "$(cksum < "$(roster_of "$R66B")")"

# ---------- 66d: an id a named row carries amends that row ----------
R66D="$(make_repo s66-namedid)"; new_roster "$R66D"; s30_row "$R66D"
poke "$R66D" amend aw1-3000000000000001 --suites+ tests/e.test.sh --reason 'by its id'
expect_eq "66d1 amend <agent id> for an id a named row carries exits 0" "0" "$RC"
expect_contains "66d2 …and amends that row, by its name" "poker: amended — w1:" "$OUT"
expect_eq "66d3 …whose set the wall now reads" "a.test.sh e.test.sh" \
  "$(s30_field "$(s66_pick "$R66D" aw1-3000000000000001)" suites_allowed)"

# ---------- 66e: the tick says a reader started without its checks, once ----------
R66E="$(make_repo s66-unchecked)"; new_roster "$R66E"
add_row "$R66E" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
printf 'start-unchecked/v1|event=start|at=%s|session=%s|agent_id=%s|role=%s|candidates=%s\n' \
  "$(iso_ago 30)" "$SID" ac66-6600000000000005 bionic:critic H1,H2 >> "$(roster_of "$R66E")"
plant_answer "$S66_TR" none
poke_pressure "$R66E" 8192 1.0 tick
expect_contains "66e1 the tick names the reader that started without its checks, and its candidates" \
  "poker: NOTIFY — a bionic:critic started without its checks: candidates H1, H2" "$OUT"
expect_contains "66e2 …and writes that it told" "start-unchecked/v1|event=told|" "$(cat "$(roster_of "$R66E")")"
poke_pressure "$R66E" 8192 1.0 tick
expect_absent "66e3 the next tick does not say it again" "started without its checks" "$OUT"
expect_contains "66e4 …while it still reads the roster (the positive on the same tick)" "poker:" "$OUT"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 67 §RECON-WHY §NOTIFY-WHOLE §AMEND-PLACED §AMEND-CAP §BUDGET-LOWERS §DECLINE-SLOT: T37 (review passes 8 F2, 36 S1 N2, 42 N1 N2; T49's open cap; A-orch-38, 96, 100, 112)"
# ============================================================
#
# §RECON-WHY (review pass 8 F2). When the reconcile is owed because the plan MOVED, the RECONCILE
# line said a status or the ready set changed, which is untrue there, and never asked for the
# rebuild steps/3.md wants. It now says which move it was and names the rebuild, and the digest
# carries the cause as `reconcile=` for the turn-end wall's refusal. RPb2 (section 55) pins the
# Step-4 reason; the grown table and the status control are here. The grown table waits on the
# world as section 55 does, so the tick is QUIET and the plan move alone prints the line.
# fails-when: a grown table prints the status-changed reason, or a status change prints a move.
R67="$(make_repo s67-recon-grew)"
s67_rd() { sed -n 's/^reconcile=//p' "$(digest_of "$1")" 2>/dev/null; }
require_helpers s67_rd
poke "$R67" arm
sp_plan_at_step "$R67" 4 "$SRP_ROW1" >/dev/null
poke_pressure "$R67" 8192 1.0 tick
expect_absent "67a0 precondition: the first tick, current 4 and one row, asks no reconcile" "poker: RECONCILE" "$OUT"
sp_plan_at_step "$R67" 4 "$SRP_ROW1" "$SRP_ROW2" >/dev/null
poke_pressure "$R67" 8192 1.0 tick
expect_contains "67a1 §RECON-WHY a grown table: the line says the table grew and names the rebuild" \
  "poker: RECONCILE — the ## Tasks table grew since the last tick: TaskList, and rebuild the task list in execution order (delete the pending entries after the new row and recreate them)" "$OUT"
expect_eq "67a2 …once" "1" "$(count_lines_matching 'poker: RECONCILE' "$OUT")"
expect_eq "67a3 …and the digest carries the cause for the turn-end wall" "grew" "$(s67_rd "$R67")"
R67S="$(make_repo s67-recon-step4)"
poke "$R67S" arm
sp_plan_at_step "$R67S" 3 "$SRP_ROW1" >/dev/null
poke_pressure "$R67S" 8192 1.0 tick
sp_plan_at_step "$R67S" 4 "$SRP_ROW1" >/dev/null
poke_pressure "$R67S" 8192 1.0 tick
expect_contains "67a4 precondition: current: 3 to 4 prints the Step-4 reason (RPb2's)" "the plan moved from approval into Step 4" "$OUT"
expect_eq "67a5 …and the digest carries its cause" "step4" "$(s67_rd "$R67S")"
sp_plan_at_step "$R67S" 5 "$SRP_ROW1" >/dev/null
poke_pressure "$R67S" 8192 1.0 tick
expect_eq "67a6 a tick over no move writes no cause (4 to 5)" "" "$(s67_rd "$R67S")"
expect_contains "67a6b …while that digest is read (the positive on the same file)" "plan_current=5" "$(cat "$(digest_of "$R67S")")"
R67C="$(make_repo s67-recon-status)"; new_roster "$R67C"
S67C_ROW1="| T1 | 4 | build | one ready build | implementor | — | 15m | REQ-x | a.sh | pending |"
S67C_ROW2="| T2 | 4 | build | another ready build | implementor | — | 15m | REQ-x | b.sh | pending |"
poke "$R67C" arm
sp_plan_at_step "$R67C" 4 "$S67C_ROW1" "$S67C_ROW2" >/dev/null
poke_pressure "$R67C" 8192 1.0 tick
expect_contains "67b0 precondition: the control's first tick fills both rows" "poker: FILL T1 T2" "$OUT"
sp_plan_at_step "$R67C" 4 "$S67C_ROW1" "${S67C_ROW2/| pending |/| dropped |}" >/dev/null
poke_pressure "$R67C" 8192 1.0 tick
expect_contains "67b1 control: a status change alone prints the status-changed reason, byte for byte" \
  "poker: RECONCILE — a ## Tasks status or the ready set changed since the last tick: TaskList, and bring the task list in line with the plan" "$OUT"
expect_absent "67b2 …and no move" "rebuild the task list" "$OUT"
expect_eq "67b3 …and the digest carries no cause" "" "$(s67_rd "$R67C")"
expect_contains "67b4 …while the digest owes the duty (the positive on the same file)" "duty=owed" "$(cat "$(digest_of "$R67C")")"

# §NOTIFY-WHOLE (review pass 36 S1). Every `started without its checks` line hashed as the same
# text (`NOTIFY — a`), so a second reader's line on a later tick left the hash unchanged: the tick
# printed `unchanged`, dropped the line, and still wrote `event=told` for it. The line now enters
# the hash whole, with the agent id beside it (two readers of one role and one candidate set print
# the same words), and `event=told` is written only when the tick's buffer is printed. The lines
# are the recorder's shape (66e). fails-when: the second or third reader is never named, or is
# named twice.
export CLAUDE_CONFIG_DIR="$S66_CFG"
R67N="$(make_repo s67-notify)"; new_roster "$R67N"
add_row "$R67N" name=live-writer deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
s67_unchecked() {  # <repo> <agent id> <role> <candidates>
  printf 'start-unchecked/v1|event=start|at=%s|session=%s|agent_id=%s|role=%s|candidates=%s\n' \
    "$(iso_ago 30)" "$SID" "$2" "$3" "$4" >> "$(roster_of "$1")"
}
s67_told() { /usr/bin/grep -c "^start-unchecked/v1|event=told|.*|agent_id=$2\$" "$(roster_of "$1")" | tr -d ' '; }
require_helpers s67_unchecked s67_told
plant_answer "$S66_TR" none
s67_unchecked "$R67N" ac67-6700000000000001 bionic:critic H1,H2
poke_pressure "$R67N" 8192 1.0 tick
expect_contains "67c0 precondition: the first reader is named" \
  "poker: NOTIFY — a bionic:critic started without its checks: candidates H1, H2" "$OUT"
s67_unchecked "$R67N" ar67-6700000000000002 bionic:auditor H3,H4
poke_pressure "$R67N" 8192 1.0 tick
expect_contains "67c1 §NOTIFY-WHOLE a second reader on a later tick is named" \
  "poker: NOTIFY — a bionic:auditor started without its checks: candidates H3, H4" "$OUT"
expect_eq "67c2 …once, and the first is not named again" "1" "$(count_lines_matching 'started without its checks' "$OUT")"
expect_eq "67c3 …and it is marked told once, by the tick that printed it" "1" "$(s67_told "$R67N" ar67-6700000000000002)"
s67_unchecked "$R67N" ac67-6700000000000003 bionic:critic H1,H2
poke_pressure "$R67N" 8192 1.0 tick
expect_contains "67c4 a third reader whose line reads as the first one's is named too" \
  "poker: NOTIFY — a bionic:critic started without its checks: candidates H1, H2" "$OUT"
expect_eq "67c5 …and told once" "1" "$(s67_told "$R67N" ac67-6700000000000003)"
poke_pressure "$R67N" 8192 1.0 tick
expect_absent "67c6 the next tick names none of them" "started without its checks" "$OUT"
expect_contains "67c7 …while it still prints (the positive on the same tick)" "poker:" "$OUT"
expect_eq "67c8 …and each start is told exactly once" "1 1 1" \
  "$(s67_told "$R67N" ac67-6700000000000001) $(s67_told "$R67N" ar67-6700000000000002) $(s67_told "$R67N" ac67-6700000000000003)"

# §AMEND-PLACED (review pass 36 N2). An agent amended by its id while unplaced, then placed (its
# launch call's return writes the row that carries its id: SYNTHESIZED here through
# `roster_row_fixture`, the dispatch wall's shape, status=confirmed), then amended by its id again:
# the amend goes to the placed row, which holds the unplaced set and the new one, and no second
# unplaced row is written to shadow it. fails-when: the wall's pick for the id is an unplaced row.
R67P="$(make_repo s67-amend-placed)"; new_roster "$R67P"
s66_launch "$R67P" p1 toolu_p1 bionic:test-runner
s66_launch "$R67P" p2 toolu_p2 bionic:test-runner
S67P_ID="ap67-6700000000000004"
s66_start "$R67P" bionic:test-runner "$S67P_ID"
s66_ran "$S67P_ID"
poke "$R67P" amend "$S67P_ID" --suites+ tests/c.test.sh --reason 'its refusal asked'
expect_eq "67d0 precondition: the unplaced agent's set is recorded on its own row" "unplaced|c.test.sh" \
  "$(s30_field "$(s66_pick "$R67P" "$S67P_ID")" status)|$(s30_field "$(s66_pick "$R67P" "$S67P_ID")" suites_allowed)"
roster_row_fixture status=confirmed "session=$SID" name=p1 "agent_id=$S67P_ID" \
  "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" subagent_type=bionic:test-runner tool_use_id=toolu_p1 \
  files= suites_allowed=a.test.sh suites_source=declared >> "$(roster_of "$R67P")"
expect_eq "67d1 precondition: once placed, the wall's pick for the id is the placed row" "p1" \
  "$(s30_field "$(s66_pick "$R67P" "$S67P_ID")" name)"
poke "$R67P" amend "$S67P_ID" --suites+ tests/d.test.sh --reason 'one more'
expect_eq "67d2 §AMEND-PLACED an amend by id after the placing exits 0" "0" "$RC"
expect_contains "67d3 …and amends the placed row, by its name" "poker: amended — p1:" "$OUT"
S67P_PICK="$(s66_pick "$R67P" "$S67P_ID")"
expect_eq "67d4 …which the wall still picks for the id" "p1|confirmed" "$(s30_field "$S67P_PICK" name)|$(s30_field "$S67P_PICK" status)"
expect_eq "67d5 …holding its own set, the unplaced set and the new one" "a.test.sh c.test.sh d.test.sh" \
  "$(s30_field "$S67P_PICK" suites_allowed | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "67d6 …and no second unplaced row was written" "1" \
  "$(/usr/bin/grep -c "|status=unplaced|.*|name=$S67P_ID|" "$(roster_of "$R67P")" | tr -d ' ')"
unset CLAUDE_CONFIG_DIR

# §AMEND-CAP (left open by T49; A-orch-96). The amend door counted the added runs with no
# `Questions:` line, so a critic holding `evidence` got the writer's cap of 200. An
# amend on a row whose `questions=` holds `evidence` is now held to the dispatch wall's cap of
# three, counted over the row's runs after the amend, housekeeping excepted, and a fourth is
# refused naming the cap. The rows are the dispatch wall's shape (`roster_row_fixture`). The
# fourth hidden as `rm -rf x & pytest` reads T57's construction through lib/brief.sh: until T57
# is on this head that row is red for that reason alone.
# fails-when: a fourth run is recorded on an evidence reader's row, or a reader not dealt
# `evidence`, or a writer, is refused a fourth.
R67Q="$(make_repo s67-amend-cap)"; new_roster "$R67Q"
s67_reader() {  # <repo> <name> <type> <questions or ""> — a live row with two runs declared
  roster_row_fixture status=identified "session=$SID" "name=$2" "agent_id=a67-$2-0000000000001" \
    "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "subagent_type=$3" "tool_use_id=toolu_$2" \
    files= suites_allowed=none suites_source=declared 're_executes=`pytest tests/a` `pytest tests/b`' \
    ${4:+"questions=$4"} >> "$(roster_of "$1")"
}
s67_runs() {  # <repo> <name> -> the marked runs on the name's last row that are not housekeeping
  s30_field "$(grep -F "|name=$2|" "$(roster_of "$1")" | tail -1)" re_executes \
    | awk -F'`' '{ for (i = 2; i <= NF; i += 2) if ($i != "" && $i !~ /^(rm|rmdir|mkdir|touch|cp|mv) /) n++ } END { print n + 0 }'
}
s67_sum() { cksum < "$(roster_of "$1")"; }
require_helpers s67_reader s67_runs s67_sum
s67_reader "$R67Q" crit bionic:critic evidence
s67_reader "$R67Q" rev bionic:critic adversarial
s67_reader "$R67Q" wri bionic:implementor ""
expect_eq "67e0 precondition: each row declares two counted runs" "2 2 2" \
  "$(s67_runs "$R67Q" crit) $(s67_runs "$R67Q" rev) $(s67_runs "$R67Q" wri)"
poke "$R67Q" amend crit --reexec+ 'pytest tests/c' --reason 'a third'
expect_eq "67e1 §AMEND-CAP a single critic dealt evidence amended to a third run: admitted (exit 0)" "0" "$RC"
expect_eq "67e2 …and the row holds three" "3" "$(s67_runs "$R67Q" crit)"
S67Q_SUM="$(s67_sum "$R67Q")"
poke "$R67Q" amend crit --reexec+ 'pytest tests/d' --reason 'a fourth'
expect_eq "67e3 …a fourth is refused (exit 1)" "1" "$RC"
expect_contains "67e4 …naming the cap" "three" "$OUT"
expect_eq "67e5 …and nothing is written" "$S67Q_SUM" "$(s67_sum "$R67Q")"
poke "$R67Q" amend crit --reexec+ 'rm -rf build' --reason 'a cleanup'
expect_eq "67e6 a housekeeping command beside the three is free (exit 0)" "0" "$RC"
S67Q_SUM="$(s67_sum "$R67Q")"
poke "$R67Q" amend crit --reexec+ 'rm -rf x & pytest' --reason 'a run behind &'
expect_eq "67e7 a fourth hidden as rm -rf x & pytest is refused (exit 1; T57's construction)" "1" "$RC"
expect_eq "67e8 …and nothing is written" "$S67Q_SUM" "$(s67_sum "$R67Q")"
# A fourth by --suites+ on a critic dealt evidence that holds three suites and no run: the
# wall's own cap counts suites and runs together once T57 is on the head (A-orch-123), and the
# door refuses what it refuses. Red until then, for that reason alone.
roster_row_fixture status=identified "session=$SID" name=crs "agent_id=a67-crs-0000000000001" \
  "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" subagent_type=bionic:critic tool_use_id=toolu_crs \
  files= "suites_allowed=a.test.sh b.test.sh c.test.sh" suites_source=declared questions=evidence \
  >> "$(roster_of "$R67Q")"
S67Q_SUM="$(s67_sum "$R67Q")"
poke "$R67Q" amend crs --suites+ tests/d.test.sh --reason 'a fourth suite'
expect_eq "67e13 a fourth by --suites+ beside three suites is refused (exit 1; T57's count of suites and runs)" "1" "$RC"
expect_eq "67e14 …and nothing is written" "$S67Q_SUM" "$(s67_sum "$R67Q")"
poke "$R67Q" amend rev --reexec+ 'pytest tests/c' --reexec+ 'pytest tests/d' --reason 'two more'
expect_eq "67e9 a critic not dealt evidence takes a fourth, as today (exit 0)" "0" "$RC"
expect_eq "67e10 …and holds four" "4" "$(s67_runs "$R67Q" rev)"
poke "$R67Q" amend wri --reexec+ 'pytest tests/c' --reexec+ 'pytest tests/d' --reason 'two more'
expect_eq "67e11 a writer's row takes a fourth, as today (exit 0)" "0" "$RC"
expect_eq "67e12 …and holds four" "4" "$(s67_runs "$R67Q" wri)"

# §BUDGET-LOWERS (review pass 42 N2; A-orch-112). `budget` took a reply nothing verifies and
# raised the cap as readily as it lowered it, so a model could raise its own ceiling. It now
# records a cap at or below the ceiling the machine derives; a number above it is refused, saying
# that raising the ceiling is the user's own edit of the plan's `parallel-budget:` line. The
# fixture is 65's (the probe's eight). fails-when: writers=99 is recorded, or 8 or 3 is refused.
R67B="$(make_repo s67-budget)"; ( cd "$R67B" && git commit -q --allow-empty -m init )
git -C "$R67B" config user.name "Dana Fixture"
P67B="$(s42_plan "$R67B" 4)"
s42_snap "$R67B" "$P67B"
poke "$R67B" budget writers=99 'go wide'
s42_unchanged "67f1 §BUDGET-LOWERS writers=99 over a derived 8" 1 "$P67B"
expect_contains "67f2 …the refusal says the verb only lowers" "only lowers" "$OUT"
expect_contains "67f3 …and that raising it is the user's own edit of the parallel-budget: line" \
  "Raising it is the user's own edit of the plan's parallel-budget: line" "$OUT"
poke "$R67B" budget writers=8 'the derived width'
expect_eq "67f4 writers=8, the derived ceiling itself, is recorded (exit 0)" "0" "$RC"
expect_contains "67f5 …the header reads it" "parallel-budget: writers=8 " "$(cat "$P67B")"
poke "$R67B" budget writers=3 'keep it at three'
expect_eq "67f6 writers=3 is recorded (exit 0)" "0" "$RC"
expect_regex "67f7 …and derived= is still the probe's eight" \
  '^budget-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} derived=8 chosen=3$' "$(/usr/bin/grep '^budget-override:' "$P67B")"
s42_snap "$R67B" "$P67B"
poke "$R67B" budget writers=9 'one over'
s42_unchanged "67f8 writers=9, one over the derived 8 (the user's cap of 3 stands)" 1 "$P67B"

# §DECLINE-SLOT (review pass 42 N1; A-orch-112). The wall's refusal prints `decline <ids> 'why
# they wait'`, and that command run exactly as printed recorded the placeholder as the reason. It
# is refused now, saying to put the reason in its place; the same command with a real reason is
# recorded. The fixture is 65's: the tick fills, the wall refuses the silent turn, and its line is
# taken from the refusal and run as printed. fails-when: the printed line writes a ledger line.
S67D_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R67D="$(make_repo s67-decline-slot)"; new_roster "$R67D"
P67D="$(s31_task_plan "$R67D" T1)"
bind_marker "$R67D" "$P67D"
add_row "$R67D" name=T1 deliverable=t1.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R67D" 8192 1.0 tick
expect_contains "67g0 precondition: the tick fills the two ready rows" "poker: FILL T2 T3" "$OUT"
s31_stop "$R67D" "$(s31_transcript "$R67D" "carry on")"
S67D_LINE="$(s31_reason | /usr/bin/grep -o "bash [^ ]*session-poker.sh'\{0,1\} decline [A-Za-z0-9_.,-]* 'why they wait'" | head -1)"
expect_contains "67g1 precondition: the wall's refusal prints the decline line with its placeholder" \
  "decline T2,T3 'why they wait'" "$S67D_LINE"
S67D_N="$(s65_count "$R67D")"
S67D_OUT="$( cd "$R67D" && CLAUDE_CODE_SESSION_ID="$SID" bash -c "$S67D_LINE" 2>&1 )"; S67D_RC=$?
expect_eq "67g2 §DECLINE-SLOT the printed command run verbatim is refused (exit 1)" "1" "$S67D_RC"
expect_contains "67g3 …saying the placeholder is no reason, and to put the reason in its place" \
  "put the reason in its place" "$S67D_OUT"
expect_eq "67g4 …and no ledger line is written" "$S67D_N" "$(s65_count "$R67D")"
S67D_REAL="$(printf '%s' "$S67D_LINE" | sed "s/'why they wait'\$/'the machine is saturated'/")"
S67D_OUT="$( cd "$R67D" && CLAUDE_CODE_SESSION_ID="$SID" bash -c "$S67D_REAL" 2>&1 )"; S67D_RC=$?
expect_eq "67g5 the same command with a real reason is recorded (exit 0)" "0" "$S67D_RC"
expect_eq "67g6 …one ledger line, carrying that reason" "$((S67D_N + 1))|the machine is saturated" \
  "$(s65_count "$R67D")|$(s65_field "$(s65_led "$R67D" | tail -1)" declined)"
POKE_BOUND="$S67D_BOUND_WAS"

# §AMEND-UNPLACED-READER (wave-27 T74; review pass 53 B1). `amend <agent id>` for an agent its start
# did not place validated the additions with no role, so a reader there got the writer's cap and
# the Bash wall's own printed remedy, followed four times, left an unplaced critic with four
# suites. The door now reads the agent's role from the start it recorded (the `role=` of the id's
# `start-unchecked/v1|event=start|` line, the line the NOTIFY is built from) and holds a reader to
# three in total, suites and runs together, by the dispatch wall's own function in brief.sh, on
# the strict side whatever its candidates were dealt; a fourth is refused naming the cap and
# saying to dispatch it again. A writer's unplaced row is as before. The starts go through the
# real recorder; two launches of one type with different `questions=` leave it unplaced.
# fails-when: a fourth suite or run is recorded for an unplaced reader, or a writer is refused one.
export CLAUDE_CONFIG_DIR="$S66_CFG"
s74_total() {  # <repo> <agent id> -> suites plus counted runs on the row the budget wall picks for the id
  local p sa n=0
  p="$(s66_pick "$1" "$2")"; sa="$(s30_field "$p" suites_allowed)"
  case "$sa" in ''|none) : ;; *) n=$(printf '%s\n' $sa | wc -l | tr -d ' ') ;; esac
  printf '%s' "$(( n + $(s30_field "$p" re_executes \
    | awk -F'`' '{ for (i = 2; i <= NF; i += 2) if ($i != "" && $i !~ /^(rm|rmdir|mkdir|touch|cp|mv) /) n++ } END { print n + 0 }') ))"
}
s74_unplaced() {  # <repo> <type> <tag> <questions of one launch> <questions of the other> — two launches, then starts
  s66_launch "$1" "$3-a" "toolu_$3a" "$2" ${4:+"questions=$4"} suites_allowed=none
  s66_launch "$1" "$3-b" "toolu_$3b" "$2" ${5:+"questions=$5"} suites_allowed=none
}
s74_start() { s66_start "$1" "$2" "$3"; s66_ran "$3"; }  # <repo> <type> <agent id>
s74_line() { /usr/bin/grep -F "start-unchecked/v1|event=start|" "$(roster_of "$1")" | /usr/bin/grep -F "|agent_id=$2|"; }
require_helpers s74_total s74_unplaced s74_start s74_line
for s74_role in critic auditor critic-noev; do
  s74_type="${s74_role%-noev}"
  case "$s74_role" in
    critic)   s74_q1=evidence,adversarial,structure; s74_q2=adversarial ;;
    auditor)  s74_q1=evidence; s74_q2=evidence,structure ;;
    critic-noev) s74_q1=structure; s74_q2=adversarial ;;   # a critic dealt no evidence: the strict side holds it all the same
  esac
  R74="$(make_repo "s74-$s74_role")"; new_roster "$R74"
  s74_unplaced "$R74" "bionic:$s74_type" "u$s74_role" "$s74_q1" "$s74_q2"
  S74_ID="a74-${s74_role}-000000000001"
  s74_start "$R74" "bionic:$s74_type" "$S74_ID"
  expect_contains "74a0 ($s74_role) precondition: the start is recorded unplaced, with its role" \
    "|role=bionic:$s74_type|" "$(s74_line "$R74" "$S74_ID")"
  expect_empty "74a0b ($s74_role) precondition: …and no row carries its id" "$(s66_pick "$R74" "$S74_ID")"
  S74_RCS=""
  for s74_n in n1 n2 n3; do
    poke "$R74" amend "$S74_ID" --suites+ "tests/$s74_n.test.sh" --reason 'its refusal asked'
    S74_RCS="$S74_RCS$RC"
  done
  expect_eq "74a1 ($s74_role) §AMEND-UNPLACED-READER three suites, one amend each, are recorded" "000" "$S74_RCS"
  expect_eq "74a2 ($s74_role) …and the row holds three" "3" "$(s74_total "$R74" "$S74_ID")"
  S74_SUM="$(cksum < "$(roster_of "$R74")")"
  poke "$R74" amend "$S74_ID" --suites+ tests/n4.test.sh --reason 'its refusal asked'
  expect_eq "74a3 ($s74_role) a fourth is refused (exit 1)" "1" "$RC"
  expect_contains "74a4 ($s74_role) …naming the total and the cap, in the dispatch wall's words" \
    "the total of 4 runs exceeds the 3-run cap" "$OUT"
  expect_contains "74a5 ($s74_role) …and saying it should be dispatched again" "dispatch it again" "$OUT"
  expect_eq "74a6 ($s74_role) …and nothing is written" "$S74_SUM" "$(cksum < "$(roster_of "$R74")")"
  poke "$R74" amend "$S74_ID" --reexec+ 'rm -rf x & pytest' --reason 'a run behind &'
  expect_eq "74a7 ($s74_role) a fourth hidden as rm -rf x & pytest is refused (exit 1)" "1" "$RC"
  expect_eq "74a8 ($s74_role) …and the row still holds three" "3" "$(s74_total "$R74" "$S74_ID")"
  S74_ID2="a74-${s74_role}-000000000002"
  s74_start "$R74" "bionic:$s74_type" "$S74_ID2"
  expect_contains "74b0 ($s74_role) precondition: a second unplaced start is recorded with its role" \
    "|role=bionic:$s74_type|" "$(s74_line "$R74" "$S74_ID2")"
  S74_SUM="$(cksum < "$(roster_of "$R74")")"
  poke "$R74" amend "$S74_ID2" --suites+ tests/n1.test.sh --suites+ tests/n2.test.sh \
    --suites+ tests/n3.test.sh --suites+ tests/n4.test.sh --reason 'four at once'
  expect_eq "74b1 ($s74_role) one call adding four suites is refused whole (exit 1)" "1" "$RC"
  poke "$R74" amend "$S74_ID2" --suites+ tests/n1.test.sh --suites+ tests/n2.test.sh \
    --reexec+ 'pytest tests/x' --reexec+ 'pytest tests/y' --reason 'two and two'
  expect_eq "74b2 ($s74_role) …and so is one adding two suites and two runs (exit 1)" "1" "$RC"
  expect_eq "74b3 ($s74_role) …and neither wrote anything" "$S74_SUM" "$(cksum < "$(roster_of "$R74")")"
  poke "$R74" amend "$S74_ID2" --suites+ tests/n1.test.sh --suites+ tests/n2.test.sh \
    --reexec+ 'pytest tests/x' --reason 'two and one'
  expect_eq "74b4 ($s74_role) two suites and one run in one call are recorded (exit 0)" "0" "$RC"
  expect_eq "74b5 ($s74_role) …the row holding three" "3" "$(s74_total "$R74" "$S74_ID2")"
done
# THE NAMED LIMIT (A-orch-154, ruled at the writer's stop). The recorder writes the start-unchecked
# line only when the candidates were dealt DIFFERENT questions, so in review pass 53's own drive
# `a5` (three critic launches all dealt the same questions) no line names the agent and the door
# has no role to read: the unplaced row is as before, four suites recorded, until T68 places the
# agent at its launch call's return. This row pins that state; a recorder that records the role
# for every unplaced start would turn it, and the ruling is what changes then.
R74S="$(make_repo s74-same)"; new_roster "$R74S"
for s74_c in sa sb sc; do
  s66_launch "$R74S" "$s74_c" "toolu_$s74_c" bionic:critic questions=evidence,adversarial,structure suites_allowed=none
done
S74S_ID="a74-same-00000000000001"
s74_start "$R74S" bionic:critic "$S74S_ID"
expect_empty "74f0 precondition: candidates dealt the same questions leave no start-unchecked line for the id" \
  "$(s74_line "$R74S" "$S74S_ID")"
expect_empty "74f0b precondition: …and no row carries its id" "$(s66_pick "$R74S" "$S74S_ID")"
S74_RCS=""
for s74_n in n1 n2 n3 n4; do
  poke "$R74S" amend "$S74S_ID" --suites+ "tests/$s74_n.test.sh" --reason 'its refusal asked'
  S74_RCS="$S74_RCS$RC"
done
expect_eq "74f1 the limit A-orch-154 names: an unplaced critic with no recorded role takes a fourth, as before" "0000" "$S74_RCS"
expect_eq "74f2 …and its row holds four" "4" "$(s74_total "$R74S" "$S74S_ID")"
R74W="$(make_repo s74-writer)"; new_roster "$R74W"
s74_unplaced "$R74W" bionic:implementor uwri "" ""
S74W_ID="a74-writer-0000000000001"
s74_start "$R74W" bionic:implementor "$S74W_ID"
expect_empty "74c0 precondition: no row carries the unplaced writer's id" "$(s66_pick "$R74W" "$S74W_ID")"
S74_RCS=""
for s74_n in n1 n2 n3 n4; do
  poke "$R74W" amend "$S74W_ID" --suites+ "tests/$s74_n.test.sh" --reason 'its refusal asked'
  S74_RCS="$S74_RCS$RC"
done
expect_eq "74c1 a writer its start did not place takes a fourth suite, as before" "0000" "$S74_RCS"
expect_eq "74c2 …and its row holds four" "4" "$(s74_total "$R74W" "$S74W_ID")"
unset CLAUDE_CONFIG_DIR

# §BUDGET-IN-FORCE (wave-27 T74; review pass 53 N4 ruled, N5, S2). The verb recorded any value at or
# below the ceiling the machine derived, so after the user lowered the cap to 3 a reply nothing
# verifies raised it to 5, then 8. It now records n only at or below the cap IN FORCE, the plan's
# own `parallel-budget: writers=` (which the verb's override writes, and a user's hand edit sets):
# a raise by any amount is the user's own edit of that line, and the refusal says so; a hand raise
# is in force. A `writers=` or `derived=` in the plan that is not one to four digits refuses the
# verb, naming the line, and nothing is recorded. After two writes the frontmatter holds ONE
# override line (the verb rewrites it; S2: a copy without the rewrite holds two).
# fails-when: a raise over the cap in force is recorded, a lowering under a hand raise is refused,
# a ceiling that is not a number compares as "not greater", or the override line is doubled.
R74B="$(make_repo s74-budget)"; ( cd "$R74B" && git commit -q --allow-empty -m init )
git -C "$R74B" config user.name "Dana Fixture"
P74B="$(s42_plan "$R74B" 4)"
s74_hdr() { /usr/bin/grep '^parallel-budget:' "$1"; }
s74_ovr() { /usr/bin/grep -c '^budget-override:' "$1" | tr -d ' '; }
s74_set() {  # <plan> <line key> <field> <value> — a hand edit of one field of one frontmatter line
  S74_K="$2" S74_F="$3" S74_V="$4" awk '
    NR == 1 && $0 == "---" { f = 1; print; next }
    f && $0 == "---" { f = 0 }
    f && index($0, ENVIRON["S74_K"] ":") == 1 {
      n = split($0, w, " "); out = w[1]
      for (i = 2; i <= n; i++) { if (index(w[i], ENVIRON["S74_F"] "=") == 1) w[i] = ENVIRON["S74_F"] "=" ENVIRON["S74_V"]; out = out " " w[i] }
      $0 = out
    }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
require_helpers s74_hdr s74_ovr s74_set
expect_contains "74d0 precondition: the probe's header, eight writers" "parallel-budget: writers=8 " "$(s74_hdr "$P74B")"
poke "$R74B" budget writers=3 'keep it at three'
expect_eq "74d1 §BUDGET-IN-FORCE writers=3 under the eight in force is recorded (exit 0)" "0" "$RC"
s42_snap "$R74B" "$P74B"
poke "$R74B" budget writers=5 'back to five'
s42_unchanged "74d2 writers=5 over the user's 3 in force, under the derived 8" 1 "$P74B"
expect_contains "74d3 …saying the cap in force is 3 and the verb only lowers it" \
  "writers=5 is above the cap in force (3): budget only lowers it" "$OUT"
expect_contains "74d4 …and that raising it is the user's own edit of the parallel-budget: line" \
  "Raising it is the user's own edit of the plan's parallel-budget: line" "$OUT"
poke "$R74B" budget writers=2 'two'
expect_eq "74d5 writers=2 is recorded (exit 0)" "0" "$RC"
expect_contains "74d6 …the header reads it" "parallel-budget: writers=2 " "$(s74_hdr "$P74B")"
expect_eq "74d7 §OVERRIDE-ONE after two successful writes the frontmatter holds exactly one override line" \
  "1" "$(s74_ovr "$P74B")"
expect_regex "74d7b …the second write's" '^budget-override: Dana Fixture [0-9-]{10} derived=8 chosen=2$' \
  "$(/usr/bin/grep '^budget-override:' "$P74B")"
s74_set "$P74B" parallel-budget writers 12
expect_contains "74d8 precondition: the user's hand raise to 12" "parallel-budget: writers=12 " "$(s74_hdr "$P74B")"
s42_snap "$R74B" "$P74B"
poke "$R74B" budget writers=10 'ten'
expect_eq "74d9 writers=10 under the user's hand-raised 12 is recorded (exit 0): the hand edit is in force" "0" "$RC"
expect_contains "74d10 …the header reads it" "parallel-budget: writers=10 " "$(s74_hdr "$P74B")"
poke "$R74B" budget writers=10 'ten again'
expect_eq "74d11 writers=10 at the 10 in force is a no-op (exit 0)" "0" "$RC"
expect_contains "74d12 …that says so" "the plan already reads so; nothing was written" "$OUT"
expect_eq "74d13 …and the override is still one line" "1" "$(s74_ovr "$P74B")"
s42_snap "$R74B" "$P74B"
cp "$P74B" "$TMPROOT/s74-good"
for s74_case in "budget-override derived 99999999999999999999" "budget-override derived abc" \
                "budget-override derived -3" "budget-override derived ''" \
                "parallel-budget writers 99999999999999999999" "parallel-budget writers abc" \
                "parallel-budget writers -3" "parallel-budget writers ''"; do
  read -r s74_k s74_f s74_v <<< "$s74_case"; [ "$s74_v" = "''" ] && s74_v=""
  cp "$TMPROOT/s74-good" "$P74B"; s74_set "$P74B" "$s74_k" "$s74_f" "$s74_v"
  S74_E="$s74_k $s74_f=$s74_v"
  expect_contains "74e0 ($S74_E) precondition: the edit is in the plan" " $s74_f=$s74_v" \
    "$(/usr/bin/grep "^$s74_k:" "$P74B") "
  s42_snap "$R74B" "$P74B"
  poke "$R74B" budget writers=1 'one'
  s42_unchanged "74e1 ($S74_E) §N5 a ceiling that is not one to four digits" 1 "$P74B"
  expect_contains "74e2 ($S74_E) …naming the line" "the plan's $s74_k: line" "$OUT"
  expect_contains "74e3 ($S74_E) …and saying why" "$s74_f= that is not one to four digits" "$OUT"
done
cp "$TMPROOT/s74-good" "$P74B"; s42_snap "$R74B" "$P74B"
poke "$R74B" budget writers=1 'one'
expect_eq "74e4 control: the same call on the plan restored is recorded (exit 0)" "0" "$RC"

# ============================================================
section "Section 68 §DEBT-OWED: a debt is owed because land wrote it, and covered only by a green run after the red landing (wave-27 T67; review pass 46 B1, B2, B3, N5, S3; REQ-14 AC-14.3; D23 as amended, A-orch-120)"
# ============================================================
#
# The judge reads debts from the run's landing record (`landing-proofs.log`), every `debt:` line no
# `void:` line names, and never from a `landed red:` plan line, which may stay as a note and changes
# nothing. Either kind of debt is covered only by a green floor or task proof dated strictly after the
# red landing; an `approval:` debt also after the approval. Two red landings on one suite and token
# are two debts, both covered only after the later. An `ext:` slug is held while any `## Tasks` cell
# holds it as a whole token, whatever punctuation stands around it.
#
# FIXTURE FIDELITY. §64's repository, bound plan, head and proof placer (`proof_add_line`); each debt
# written by `land`'s own writer (`_wt_debt_write`) and each void by `_wt_debt_void`; an `approved:`
# line in the shape the approve verb writes, at a time the row chooses.
S68_AP="$(printf 'debt\twidget.test.sh\tapproval:design')"
S68_EXT="$(printf 'debt\twidget.test.sh\text:vendor-key')"
s68_plan() { cp "$TMPROOT/s64-clean" "$P64"; s64_debt_reset; }
s68_approve() { s64_add "approved: $1 by Dana Fixture $2 \"ok\""; }
s68_owed() { bash -c '. "$1" && facts_owed double wave "$2" "$3"' _ "$S61_LIB" "$R64" "$P64" | /usr/bin/grep '^debt'; }
s68_cell() {  # <the T2 deps cell> -> P64's T2 row holding it
  S68_C="$1" awk '/^\| T2 \|/ { sub(/\| — \| 30 \|/, "| " ENVIRON["S68_C"] " | 30 |") } { print }' "$P64" > "$P64.tmp" && mv "$P64.tmp" "$P64"
}

# ---------- B3: the record makes the debt, the plan line does not ----------
s68_plan; s64_debt widget.test.sh ext:vendor-key 2026-10-05T04:00:00Z
expect_eq "68a B3 a debt land wrote is dealt with no landed red: line anywhere in the plan" "$S68_EXT" "$(s68_owed)"
s57_state "$P64" "$S64_H"
expect_eq "68a1 …and the judge says it absent (no green run after 04:00Z)" "absent" "$(s57_of "$S68_EXT")"
for s68v in "landed red: widget.test.sh until ext:vendor-key" \
            "landed red: widget.test.sh until ext:vendor-key at 2026-10-04T00:00:00Z" \
            "landed red: other.test.sh until ext:vendor-key at 2026-10-05T04:00:00Z"; do
  cp "$TMPROOT/s64-clean" "$P64"
  awk -v l="- T9: landed at record/T9.md, $s68v" '{ print } /^- T1: landed at record\/T1.md/ { print l }' "$P64" > "$P64.tmp" && mv "$P64.tmp" "$P64"
  s57_state "$P64" "$S64_H"
  expect_eq "68a2 a hand-edited plan line ($s68v) changes nothing: the one debt, absent" "$S68_EXT|absent" "$(s68_owed)|$(s57_of "$S68_EXT")"
done
s64_debt_reset
expect_eq "68a3 …and with no debt in the record, the same plan line owes nothing" "" "$(s68_owed)"
expect_contains "68a4 …while the plan still carries it (the line is a note)" "landed red: other.test.sh" "$(cat "$P64")"

# ---------- B1: approval, green, red; the same second; one second after ----------
s68_plan; s68_approve design 2026-10-05T01:00:00Z
s64_proof floor 2026-10-05T01:30:00Z record/wave-01-fixture/floor-0130.log
s64_debt widget.test.sh approval:design 2026-10-05T02:00:00Z
s57_state "$P64" "$S64_H"
expect_eq "68b B1 approval 01:00, green floor 01:30, red landing 02:00: absent" "absent" "$(s57_of "$S68_AP")"
s64_proof floor 2026-10-05T02:00:00Z record/wave-01-fixture/floor-0200.log
s57_state "$P64" "$S64_H"
expect_eq "68b2 …a green floor at 02:00:00, the landing's own second: absent" "absent" "$(s57_of "$S68_AP")"
s64_proof floor 2026-10-05T02:00:01Z record/wave-01-fixture/floor-020001.log
s57_state "$P64" "$S64_H"
expect_eq "68b3 …at 02:00:01: covered" "covered" "$(s57_of "$S68_AP")"
s68_plan; s64_debt widget.test.sh approval:design 2026-10-05T02:00:00Z
s64_proof floor 2026-10-05T02:30:00Z record/wave-01-fixture/floor-0230.log
s68_approve design 2026-10-05T03:00:00Z
s57_state "$P64" "$S64_H"
expect_eq "68b4 red 02:00, green 02:30, approval 03:00: absent (the green is before the approval)" "absent" "$(s57_of "$S68_AP")"
s64_proof task 2026-10-05T03:00:01Z record/wave-01-fixture/widget-green.log
s57_state "$P64" "$S64_H"
expect_eq "68b5 …a task proof showing widget green at 03:00:01: covered" "covered" "$(s57_of "$S68_AP")"
s68_plan; s64_debt widget.test.sh ext:vendor-key 2026-10-05T02:00:00Z
s64_proof floor 2026-10-05T02:00:00Z record/wave-01-fixture/floor-0200.log
s57_state "$P64" "$S64_H"
expect_eq "68b6 an ext: debt and a green floor at the landing's own second: absent" "absent" "$(s57_of "$S68_EXT")"

# ---------- B2: red, green, red ----------
s68_plan; s64_debt widget.test.sh ext:vendor-key 2026-10-05T02:00:00Z
s64_proof floor 2026-10-05T02:30:00Z record/wave-01-fixture/floor-0230.log
s57_state "$P64" "$S64_H"
expect_eq "68c0 control: one red landing at 02:00, a green floor at 02:30: covered" "covered" "$(s57_of "$S68_EXT")"
s64_debt widget.test.sh ext:vendor-key 2026-10-05T03:00:00Z
s57_state "$P64" "$S64_H"
expect_eq "68c B2 a second red landing on the same suite and token at 03:00: absent" "absent" "$(s57_of "$S68_EXT")"
expect_eq "68c2 …the two debt lines dealt as one owed line" "$S68_EXT" "$(s68_owed)"
s64_proof floor 2026-10-05T03:30:00Z record/wave-01-fixture/floor-0330.log
s57_state "$P64" "$S64_H"
expect_eq "68c3 …a green floor after the later one: covered" "covered" "$(s57_of "$S68_EXT")"

# ---------- a merge that failed: its debt is voided ----------
s68_plan; s64_debt widget.test.sh ext:vendor-key 2026-10-05T02:00:00Z d68void
expect_eq "68d0 control: the debt before its void is dealt" "$S68_EXT" "$(s68_owed)"
bash -c '. "$1" && _wt_debt_void "$2" d68void wt/27-T9 merge-failed' _ "$S64_WTLIB" "$S64_LOG"
expect_eq "68d a debt whose id a void line names is owed by nothing" "" "$(s68_owed)"
s64_debt widget.test.sh ext:vendor-key 2026-10-05T02:10:00Z
expect_eq "68d2 …and a later debt on the same suite is owed by itself" "$S68_EXT" "$(s68_owed)"

# ---------- N5: the slug in a cell whatever stands around it ----------
for s68c in '`ext:vendor-key`' '(ext:vendor-key)' 'ext:vendor-key.' 'ext:vendor-key, T1'; do
  s68_plan; s64_debt widget.test.sh ext:vendor-key 2026-10-05T02:00:00Z
  s64_proof floor 2026-10-05T03:00:00Z record/wave-01-fixture/floor-0300.log
  s68_cell "$s68c"
  s57_state "$P64" "$S64_H"
  expect_eq "68e N5 the slug in a cell as $s68c is still owed: absent" "absent" "$(s57_of "$S68_EXT")"
done
s68_plan; s64_debt widget.test.sh ext:vendor-key 2026-10-05T02:00:00Z
s64_proof floor 2026-10-05T03:00:00Z record/wave-01-fixture/floor-0300.log
s68_cell 'ext:vendor-key-2'
s57_state "$P64" "$S64_H"
expect_eq "68e2 …ext:vendor-key-2 in a cell does not keep ext:vendor-key owed: covered" "covered" "$(s57_of "$S68_EXT")"

# ---------- N7: the release-check verb looks again at the head and the tree after the command ----------
# §62's repository, plan and working checkout; the declared command is a script this row writes, which
# commits, or writes a tracked file, or does nothing, as a mode file says.
S68_MODE="$TMPROOT/s68-rc-mode"; S68_CHK="$TMPROOT/s68-check.sh"
cat > "$S68_CHK" <<'S68_EOF'
#!/bin/bash
case "$(cat "$1")" in
  commit) git commit -q --allow-empty -m 'the check committed' ;;
  dirty) echo dirt >> lib/a.sh ;;
esac
exit 0
S68_EOF
printf 'release-check: bash %s %s\n' "$S68_CHK" "$S68_MODE" > "$R62/.bionic/config.yaml"
S68_H0="$(git -C "$S62_WT" rev-parse HEAD)"
echo none > "$S68_MODE"
poke "$R62" release-check
expect_eq "68f0 control: a declared check that changes nothing passes (exit 0)" "0" "$RC"
for s68m in commit dirty; do
  echo "$s68m" > "$S68_MODE"
  poke "$R62" release-check
  expect_eq "68f-${s68m} N7 a declared check that ${s68m}s is refused as land refuses it (exit 1)" "1" "$RC"
  expect_contains "68f-${s68m}b …naming what it left" "check-dirtied" "$OUT"
  expect_regex "68f-${s68m}c …and a result=fail check fact is written at the head it ran on" \
    "^proved: kind=check head=${S68_H0} .*result=fail" "$(/usr/bin/grep '^proved: kind=check' "$P62" | tail -1)"
  git -C "$S62_WT" reset -q --hard "$S68_H0"
done
rm -f "$R62/.bionic/config.yaml"

# ============================================================
section "Section 69 §DRY-DEBT: a dry commit is judged on the plan it was copied from (wave-27 T76; review pass 60 P0-1; REQ-14 AC-14.3, D23; A-orch-170, A-orch-171, A-orch-172)"
# ============================================================
#
# A plan verb proves its change by a dry commit of a COPY, `<plan>.<verb>-dry.<pid>`, bound to a
# throwaway session. The commit gate's debt arm reads the landing record `land` wrote, and names it
# from the bound plan; the copy's name names no record, so a dry commit was handed no debts and
# `current 6` closed Step 5 with a declared red owed. Rule: a dry commit and a real commit of the
# same plan text at the same step get the same answer from the debt arm; the verb's marker names
# the plan the copy was made from (`dry_of=`). And the `current` arm's copy is the same shape as
# every other verb's: its dry MODE is a variable of its own, so no file named `as-is` or `judged`
# in the caller's working directory is written or removed.
#
# FIXTURE FIDELITY. The review's probe (r59 `cur6-probe.sh`): a project on a feature branch, an
# double wave plan bound to this session that the real gate admits at Steps 6 and 7 bar its debts,
# every reading in the production writer's shape, each debt written by `land`'s own writer
# (lib/worktree.sh `_wt_debt_write`) and each void by `_wt_debt_void`, into the record `land` names
# for this plan. Every move is the real verb; every real commit is the real hook (§34's `s34_gate`).
S69_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S69_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
R69="$(make_repo s69-dry-debt)"
git -C "$R69" config user.email t@example.com; git -C "$R69" config user.name "Dana Fixture"
printf '.bionic\n' > "$R69/.gitignore"; printf 'seed\n' > "$R69/README.md"
mkdir -p "$R69/tests" "$R69/.bionic/docs/plans" "$R69/.bionic/docs/record/w27"
printf '#!/bin/bash\n' > "$R69/tests/a.test.sh"
( cd "$R69" && git add README.md .gitignore tests && git commit -qm seed && git checkout -q -b feature/t23 ) >/dev/null 2>&1
printf 'generic fixture proof\n' > "$R69/.bionic/docs/record/generic-evidence.md"
S69_H="$(git -C "$R69" rev-parse HEAD)"
P69="$R69/.bionic/docs/plans/wave-x.plan.md"
S69_REC="$R69/.bionic/docs/record/wave-x/landing-proofs.log"
s69_line() { bash -c '. "$1/proof.sh" && shift && proof_line "$@"' _ "$S69_LIB" "$@"; }
S69_ALL="$(s69_line review "$S69_H" 2026-10-04T12:00:00Z record/w27/evidence.md evidence w-read pass piece)
$(s69_line review "$S69_H" 2026-10-04T12:00:00Z record/w27/adversarial.md adversarial w-read flag piece)
$(s69_line review "$S69_H" 2026-10-04T12:00:00Z record/w27/structure.md structure w-read pass piece)"
s69_plan() {  # <current> <extra lines> [<step lines through>] -> P69, bound to this session
  local through="${3:-$1}"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n'
    printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\nworking-branch: feature/t23\n---\n# plan\n\n## SDLC State\n\n'
    printf 'current: %s\napproved-by: fixture 2026-09-22T00:00Z approved\n' "$1"
    printf -- '- Step 4: dispatched, record/w27/dispatch.md\n  worktree: .\n  base-sha: %s\n  branch: feature/t23\n' "$S69_H"
    printf -- '- Step 5: floor green, record/w27/floor.log\n'
    [ "$through" -ge 6 ] && printf -- '- Step 6: review at record/w27/review.md\n'
    [ "$through" -ge 7 ] && printf -- '- Step 7: documented at record/w27/docs.md\n  n/a: no decision this run\n'
    printf '%s\n' "$S69_ALL"; [ -n "$2" ] && printf '%s\n' "$2"
    printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
    printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
    printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
    printf '  tier-run: bash tests/x.test.sh\n  readback: the line it wrote\n'
  } > "$P69"
  bind_marker "$R69" "$P69"
}
s69_debt() {  # <id> <suite> <token> <at>
  mkdir -p "${S69_REC%/*}"
  bash -c '. "$1/worktree.sh" && _wt_debt_write "$2" "$3" T9 wt/27-T9 "$4" "$5" "$6" "$7"' _ "$S69_LIB" "$S69_REC" "$1" "$S69_H" "$2" "$3" "$4"
}
s69_void() { bash -c '. "$1/worktree.sh" && _wt_debt_void "$2" "$3" wt/27-T9 merge-failed' _ "$S69_LIB" "$S69_REC" "$1"; }
s69_floor() { s69_line floor "$S69_H" "$1" record/w27/floor-late.log; }
s69_state() {  # <none|open|covered|voided|two> -> the record, and the plan's extra lines in S69_X
  rm -f "$S69_REC"; S69_X=""
  case "$1" in
    open) s69_debt d1 widget.test.sh ext:vendor-key 2026-10-04T11:00:00Z ;;
    covered) s69_debt d1 widget.test.sh ext:vendor-key 2026-10-04T11:00:00Z; S69_X="$(s69_floor 2026-10-04T11:30:00Z)" ;;
    voided) s69_debt d1 widget.test.sh ext:vendor-key 2026-10-04T11:00:00Z; s69_void d1 ;;
    two) s69_debt d1 widget.test.sh ext:vendor-key 2026-10-04T11:00:00Z
         s69_debt d2 gadget.test.sh ext:other-key 2026-10-04T13:00:00Z
         S69_X="$(s69_floor 2026-10-04T12:30:00Z)" ;;
  esac
}
s69_verdict() {  # <rc> <words> -> admitted | debt | other
  if [ "$1" -eq 0 ]; then printf 'admitted'
  else case "$2" in *'a declared red is still owed'*) printf 'debt' ;; *) printf 'other' ;; esac; fi
}
s69_real() {  # <step> <state> -> the gate's answer to a real bound commit of the plan at <step>
  s69_state "$2"; s69_plan "$1" "$S69_X"
  s34_gate "$R69"; s69_verdict "$GATE_RC" "$GATE_ERR"
}
s69_move() {  # <step> <state> -> `current <step>` from the step before it: the answer, and the current: line after
  s69_state "$2"; s69_plan "$(($1 - 1))" "$S69_X" "$1"
  poke "$R69" current "$1"
  printf '%s %s' "$(s69_verdict "$RC" "$OUT")" "$(/usr/bin/grep -m1 '^current:' "$P69")"
}

# ---------- the worked answers, through the verb ----------
s69_real 6 none >/dev/null
expect_eq "69a0 control: the fixture's real commit at current: 6 with no debt is admitted" "0" "$GATE_RC"
s69_state open; s69_plan 5 "" 6; cp "$P69" "$TMPROOT/s69-before"
poke "$R69" current 6
expect_eq "69a P0-1 a debt open: current 6 is refused (exit 1)" "1" "$RC"
expect_contains "69a2 …with the gate's own words for it" "a declared red is still owed" "$OUT"
expect_contains "69a3 …naming the suite and its token" "- widget.test.sh: landed red until ext:vendor-key" "$OUT"
expect_true "69a4 …and the plan is byte-identical, current: 5 kept (cmp)" cmp -s "$TMPROOT/s69-before" "$P69"
expect_eq "69a5 …and current 7 from 6 the same" "debt current: 6" "$(s69_move 7 open)"
expect_eq "69b the debt covered by a floor proof dated after the red landing: current 6 admitted" "admitted current: 6" "$(s69_move 6 covered)"
expect_eq "69c the debt voided: admitted" "admitted current: 6" "$(s69_move 6 voided)"
expect_eq "69d no landing record at all: admitted" "admitted current: 6" "$(s69_move 6 none)"
expect_true "69d2 …and there is none (the state that row names)" test ! -e "$S69_REC"

# ---------- proof-add of the covering floor proof, at a step the debt arm binds ----------
# Every writer verb dry-commits its copy at `current: 4` past Step 4 (plan_verb_dry; A-orch-172),
# and the debt arm binds from Step 6, so this row pins the writer rule, not the debt arm: with the
# debt open, the real commit is refused and the proof that covers it is still recorded.
expect_eq "69e0 control: at current: 6 with the debt open a real commit is refused" "debt" "$(s69_real 6 open)"
poke "$R69" step-line T9 'landed red on widget.test.sh, owed'
expect_eq "69e00 a writer verb at current: 6 with the debt open (step-line): admitted, its copy judged at current: 4" "0" "$RC"
expect_contains "69e00b …and its line is written" "- T9: landed red on widget.test.sh, owed" "$(cat "$P69")"
printf 'floor log\nenv: os=fixture\nhead=%s dirty=0\nall suites passed\nGating: 1 passed, 0 failed\n' "$S69_H" \
  > "$R69/.bionic/docs/record/w27/floor-late.log"
poke "$R69" proof-add floor record/w27/floor-late.log
expect_eq "69e proof-add floor of the covering proof at current: 6, the debt open: admitted (exit 0)" "0" "$RC"
expect_regex "69e2 …and the floor proof line is written at the fixture's head" "^proved: kind=floor head=${S69_H} " \
  "$(/usr/bin/grep '^proved: kind=floor' "$P69" | tail -1)"
s34_gate "$R69"
expect_eq "69e3 …after which the real commit is admitted: the line covers the debt" "admitted" "$(s69_verdict "$GATE_RC" "$GATE_ERR")"
# Each writer verb hands plan_verb_swap the `writer` mode, so its copy is judged at `current: 4`;
# `current` alone dry-commits at the step it judges, and `regression-runs` (wave-30 T12, eee53f90)
# writes the plan header, not a row, so it hands `judged`. A verb that changes its mode turns this red.
S69_SWAPS="$(/usr/bin/grep -E '^[[:space:]]*plan_verb_swap ' "$POKER" | awk '{ print $2 }' | sort -u | tr '\n' ' ')"
S69_MODES="$(/usr/bin/grep -E '^[[:space:]]*plan_verb_swap ' "$POKER" | awk '$2 != "current" { print ($2 == "regression-runs" ? $2 "=" $NF : $NF) }' | sort -u | tr '\n' ' ')"
expect_eq "69e4 the verbs that dry-commit through plan_verb_swap (read from the script)" \
  '"$VERB" approve budget current discharge finding-check finding-move finding-stated handoff launch-sync matrix-render proof-add regression-runs release-check row-landed step-field step-line task-add task-split waive ' "$S69_SWAPS"
expect_eq "69e5 …and every one but current and regression-runs names the writer mode; regression-runs names judged" "regression-runs=judged writer " "$S69_MODES"

# ---------- the invariant: a real commit and a dry commit of the same text at the same step ----------
for s69n in 6 7; do
  for s69s in none open covered voided two; do
    s69r="$(s69_real "$s69n" "$s69s")"; s69d="$(s69_move "$s69n" "$s69s")"
    expect_eq "69f-${s69n}-${s69s} the invariant at Step ${s69n}, ${s69s}: the dry commit of current ${s69n} answers as the real commit" \
      "$s69r" "${s69d%% *}"
  done
done
expect_eq "69f2 …and the table holds both answers (two debts, one covered, at Step 7)" "debt" "$(s69_real 7 two)"

# ---------- the current verb's copy is its own file (A-orch-171) ----------
# The caller's working directory holds the user's own files named `as-is` and `judged`; a move that
# dry-commits and a current 8 (refused here by the judge) leave both byte for byte, and a directory
# holding neither is left holding neither.
S69_CWD="$R69/work"; S69_EMPTY="$R69/empty"; mkdir -p "$S69_CWD" "$S69_EMPTY"
printf 'mine, as-is\n' > "$S69_CWD/as-is"; printf 'mine, judged\n' > "$S69_CWD/judged"
cp "$S69_CWD/as-is" "$TMPROOT/s69-as-is"; cp "$S69_CWD/judged" "$TMPROOT/s69-judged"
s69_cur() {  # <cwd> <step> -> RC, OUT of `current <step>` run from <cwd>
  OUT="$( cd "$1" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" current "$2" 2>&1 )"; RC=$?
}
s69_state none; s69_plan 5 "" 6
s69_cur "$S69_CWD" 6
expect_eq "69g0 control: current 6 run from that directory is admitted" "0|current: 6" "$RC|$(/usr/bin/grep -m1 '^current:' "$P69")"
expect_true "69g A-orch-171 …and the user's as-is file is byte for byte as it was" cmp -s "$TMPROOT/s69-as-is" "$S69_CWD/as-is"
expect_true "69g2 …and so is judged" cmp -s "$TMPROOT/s69-judged" "$S69_CWD/judged"
# current 8 both ways: refused by the judge (the mode still as-is when it refuses), then admitted
# once every fact the run owes holds at the head (the mode then judged).
s69_state none; s69_plan 7 "" 7
s69_cur "$S69_CWD" 8
expect_eq "69g3 control: current 8 run from there with no floor proof is refused by the judge (exit 1)" "1" "$RC"
expect_contains "69g3b …in the judge's words" "current: 8 is admitted" "$OUT"
expect_true "69g4 …and as-is is still byte for byte as it was" cmp -s "$TMPROOT/s69-as-is" "$S69_CWD/as-is"
expect_true "69g5 …and judged" cmp -s "$TMPROOT/s69-judged" "$S69_CWD/judged"
s69_plan 7 "$(s69_floor 2026-10-04T12:00:00Z)
$(s69_line review "$S69_H" 2026-10-04T12:00:00Z record/w27/adversarial-whole.md adversarial w-read pass whole)
$(s69_line review "$S69_H" 2026-10-04T12:00:00Z record/w27/structure-whole.md structure w-read pass whole)" 7
s69_cur "$S69_CWD" 8
expect_eq "69g5b control: with every owed fact at the head, current 8 from there is admitted" "0|current: 8" "$RC|$(/usr/bin/grep -m1 '^current:' "$P69")"
expect_true "69g5c …and as-is is byte for byte as it was" cmp -s "$TMPROOT/s69-as-is" "$S69_CWD/as-is"
expect_true "69g5d …and judged" cmp -s "$TMPROOT/s69-judged" "$S69_CWD/judged"
s69_state none; s69_plan 5 "" 6
s69_cur "$S69_EMPTY" 6
expect_eq "69g6 control: current 6 from a directory holding neither name is admitted" "0" "$RC"
expect_eq "69g7 …and leaves it holding nothing" "" "$(ls -A "$S69_EMPTY")"
expect_eq "69g8 …while the plan's own directory holds no copy left behind" "wave-x.plan.md" "$(ls -A "${P69%/*}")"
POKE_BOUND="$S69_BOUND_WAS"

# ============================================================
section "Section 70 §RIGOR: a plan at single or double advances on the set it is dealt, and one carrying a word before 1.14.0 is not dealt at all (wave-28 T44; wave-30 T11: REQ-1 AC-1.4, D1)"
# ============================================================
# The judge reads the rigor word through lib/run.sh `rigor_level` (proof.sh `facts_owed`): a plan
# at a level is dealt its readers, `current 8` is refused on the missing fact and admitted on the
# set; a plan still carrying one of the six words before 1.14.0 names no level, so the judge cannot
# deal it and `current 8` is refused saying so, the fact or no fact. §61's fixture, unchanged, with
# only its `rigor:` line set to each word of a pair.
S70_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S70_H="$(git -C "$S61_WT" rev-parse HEAD 2>/dev/null)"
expect_regex "70a0 precondition: §61's working branch still has a head" '^[0-9a-f]{40}$' "$S70_H"
s70_deal() {  # <rigor> -> facts_owed's review lines at wave scale, one per line
  bash -c '. "$1" && facts_owed "$2" wave' _ "$S61_LIB" "$1" 2>/dev/null | /usr/bin/grep '^review'
}
for s70p in double:high double:medium single:low; do
  s70l="${s70p%%:*}"; s70o="${s70p#*:}"
  expect_nonempty "70a $s70l is dealt readings (the extractor reads real output)" "$(s70_deal "$s70l")"
  expect_eq "70b $s70o, a word before 1.14.0, is dealt nothing" "" "$(s70_deal "$s70o")"
  s61_reset; s61_rigor "$s70l"; s61_owed "$S70_H" structure
  s42_snap "$R61" "$P61"
  poke "$R61" current 8
  s42_unchanged "70c at $s70l, current 8 with no structure fact" 1 "$P61"
  expect_contains "70c2 …at $s70l, naming the structure question's holder absent" \
    "$(printf 'review\tstructure\t%s\tpiece\tabsent' "$(s70_deal "$s70l" | awk -F'\t' '$2 == "structure" { print $3; exit }')")" "$OUT"
  s61_fact structure "$S70_H" pass piece; s61_fact structure "$S70_H" pass whole
  poke "$R61" current 8
  expect_eq "70d …at $s70l, the same plan with it advances (exit 0)" "0" "$RC"
  expect_eq "70d2 …and reads current: 8" "8" "$(s61_cur)"
  s61_reset; s61_rigor "$s70o"; s61_owed "$S70_H" structure
  s42_snap "$R61" "$P61"
  poke "$R61" current 8
  s42_unchanged "70x at $s70o, current 8 is refused: the judge cannot deal the plan" 1 "$P61"
  expect_contains "70x2 …saying the plan's rigor is no level the dealing knows" \
    "declares no rigor and scale the dealing knows (rigor: $s70o, scale: wave)" "$OUT"
  s61_fact structure "$S70_H" pass piece; s61_fact structure "$S70_H" pass whole
  poke "$R61" current 8
  expect_eq "70y …at $s70o, the same plan with every fact is still refused (exit 1)" "1" "$RC"
  expect_eq "70y2 …and still reads current: 7" "7" "$(s61_cur)"
done
s61_reset
POKE_BOUND="$S70_BOUND_WAS"

# ============================================================
section "Section 71 §FACTS-DOCS: a docs-only landing owes no reading (wave-30 T6; REQ-2 AC-2.4; design-ledger Δ12, D12; A-orch-309)"
# ============================================================
#
# `facts_state` asked piece coverage of every commit past a reading, so a landing of three
# CHANGELOG bullets cost two readers (wave-28). A commit whose whole diff lies in the docs set
# (CHANGELOG.md, README.md, CLAUDE.md, anything under .bionic/ or .claude/rules/) is covered by
# the reading that covered its parent. The set is `_proof_docs_path`'s one list. Never `skills/`
# or `agents/` prose, which agents execute, and never a `payload/` file; a commit that mixes a
# docs file with any other file is not docs-only. Each arm commits atop the same read head H0 in
# a worktree of its own repository and asks the judge about the new head, reading only the
# review lines (the floor is proof_state's, and is no part of this rule).
S71_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R71="$(make_repo s71-docs)"; ( cd "$R71" && git commit -q --allow-empty -m init )
git -C "$R71" config user.name "Dana Fixture"
S71_B="$(git -C "$R71" rev-parse HEAD)"
P71="$(s42_plan "$R71" 4 "  worktree: .worktrees/71-fixture
  base-sha: ${S71_B:0:8}
  branch: wave/71-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/71-fixture"; d = 1 }' "$P71" > "$P71.tmp" && mv "$P71.tmp" "$P71"
( cd "$R71" && git add -f "$P71" && git commit -qm wb \
  && git worktree add -q -b wave/71-fixture "$R71/.worktrees/71-fixture" "$S71_B" ) >/dev/null 2>&1
S71_WT="$R71/.worktrees/71-fixture"
S71_H0="$(s57_commit "$S71_WT" lib/a.sh H0)"
expect_regex "71a0 precondition: the read head H0 is a 40-hex commit" '^[0-9a-f]{40}$' "$S71_H0"
for s71q in evidence adversarial structure; do s57_fact "$s71q" "$S71_H0" pass piece "$P71"; done
cp "$P71" "$TMPROOT/s71-clean"
# s71_arm <label> <path>... -> S71_HEAD: one commit atop H0 touching every path given; the judge
# is asked about it and its answer for the evidence question is S71_EVI.
s71_arm() {
  local p
  shift
  git -C "$S71_WT" reset -q --hard "$S71_H0"
  for p in "$@"; do mkdir -p "$S71_WT/$(dirname "$p")"; printf 'x\n' >> "$S71_WT/$p"; done
  ( cd "$S71_WT" && git add -f -- "$@" && git commit -qm "$*" ) >/dev/null 2>&1
  S71_HEAD="$(git -C "$S71_WT" rev-parse HEAD)"
  cp "$TMPROOT/s71-clean" "$P71"
  s57_state "$P71" "$S71_HEAD"
  S71_EVI="$(s57_of "$S57_EV")"
}
s71_arm a CHANGELOG.md
expect_regex "71a0b precondition: arm (a) committed a head past H0" '^[0-9a-f]{40}$' "$S71_HEAD"
expect_eq "71a0c precondition: …touching CHANGELOG.md alone" "CHANGELOG.md" "$(git -C "$S71_WT" show --name-only --format= "$S71_HEAD")"
expect_eq "71a a docs-only commit (CHANGELOG.md) atop a read head owes no reading: covered" "covered" "$S71_EVI"
expect_eq "71a2 …for every piece question" "covered covered" \
  "$(s57_of "$S57_AD") $(s57_of "$S57_ST")"
s71_arm b CHANGELOG.md payload/scripts/x.sh
expect_eq "71b a commit touching CHANGELOG.md and a payload file is not docs-only: uncovered, naming the range" \
  "uncovered	${S71_H0}..${S71_HEAD}" "$S71_EVI"
s71_arm c skills/canonical-sdlc/SKILL.md
expect_eq "71c a commit touching only a skill's prose is not docs (agents execute it): uncovered" \
  "uncovered	${S71_H0}..${S71_HEAD}" "$S71_EVI"
s71_arm c2 agents/implementor.md
expect_eq "71c2 …nor is an agent role file" "uncovered	${S71_H0}..${S71_HEAD}" "$S71_EVI"
s71_arm c3 payload/README.md
expect_eq "71c3 …nor a README under payload/ (only the root README.md is in the set)" \
  "uncovered	${S71_H0}..${S71_HEAD}" "$S71_EVI"
s71_arm d .bionic/docs/record/wave-01-fixture/note.md
expect_eq "71d a commit under .bionic/docs/record/ alone: covered" "covered" "$S71_EVI"
s71_arm d2 .bionic/notes/plan.md
expect_eq "71d2 a commit under .bionic/ outside the docs root: covered (the set is .bionic/**)" "covered" "$S71_EVI"
s71_arm e README.md CLAUDE.md
expect_eq "71e README.md and CLAUDE.md together: covered" "covered" "$S71_EVI"
s71_arm f .claude/rules/hook-authoring.md
expect_eq "71f a commit under .claude/rules/: covered" "covered" "$S71_EVI"
s71_arm g .claude/settings.json
expect_eq "71g …but .claude/ outside rules/ is not docs: uncovered" "uncovered	${S71_H0}..${S71_HEAD}" "$S71_EVI"
# a docs commit and then a code commit: the range holds code, so it is uncovered (the earlier docs
# commit does not launder the later code)
s71_arm h CHANGELOG.md
S71_HD="$S71_HEAD"
S71_HEAD="$(s57_commit "$S71_WT" lib/b.sh code)"
s57_state "$P71" "$S71_HEAD"
expect_eq "71h a docs commit followed by a code commit is uncovered from H0" "uncovered	${S71_H0}..${S71_HEAD}" "$(s57_of "$S57_EV")"
# a code commit then a docs commit: still uncovered from H0
git -C "$S71_WT" reset -q --hard "$S71_H0"
s57_commit "$S71_WT" lib/b.sh code >/dev/null
S71_HEAD="$(s57_commit "$S71_WT" CHANGELOG.md bullets)"
s57_state "$P71" "$S71_HEAD"
expect_eq "71i a code commit then a docs commit is uncovered from H0" "uncovered	${S71_H0}..${S71_HEAD}" "$(s57_of "$S57_EV")"
cp "$TMPROOT/s71-clean" "$P71"
POKE_BOUND="$S71_BOUND_WAS"


# ============================================================
section "Section 72 §PROOF-ANCESTOR: proof-add floor accepts a run at an ancestor head when the change since is bounded and proved (wave-30 T13; REQ-4 AC-4.4; D7, design-ledger Δ6b, Δ6c; A-orch-16)"
# ============================================================
#
# Through 1.13.0 every floor path held the run's head equal to the working head, so a bounded
# landing between the full run and `proof-add floor` cost a second full run. Now a run whose head F
# is an ancestor of the working head H is accepted when proof_state's bounded rule holds for F..H
# and each suite the map names has its proof at H: a `booked.sh` stamp in the working checkout's
# git dir, rc 0 on a clean tree; or, for an attestation, a `later-changes:` line per suite. The
# proof line names F, the head the run read; the judge reads F..H as it reads any later landing.
# A change the map cannot bound still owes a full run on H, and the refusal says why.
#
# FIXTURE FIDELITY. A real repository: its working branch in a linked worktree, real commits, a map
# stub that answers lib/one.sh with a and b, lib/two.sh with c and lib/every.sh with all four
# suites. The stamps are written by the real shim (`payload/scripts/booked.sh`), run in the working
# checkout, so their shape is the one `_wt_stale_proof` reads. The floor logs are hand-written in
# the runner's, `floor-run`'s and the attestation's shapes, as §46 and §FLOOR-DECLARED write them.
S72_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S72_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
S72_BOOKED="${BIONIC_HOOKS_DIR}/../payload/scripts/booked.sh"
S72_MAP="$TMPROOT/s72-map.sh"
{
  printf '#!/bin/bash\n'
  printf 'for f in "$@"; do\n'
  printf '  case "$f" in\n'
  printf '    lib/one.sh)   for s in a b; do printf "%%s.test.sh\\tdir-ref:%%s\\n" "$s" "$f"; done ;;\n'
  printf '    lib/two.sh)   printf "c.test.sh\\tdir-ref:%%s\\n" "$f" ;;\n'
  printf '    lib/every.sh) for s in a b c d; do printf "%%s.test.sh\\tdir-ref:%%s\\n" "$s" "$f"; done ;;\n'
  printf '  esac\n'
  printf 'done\n'
} > "$S72_MAP"
# s72_world <label> [<current>] -> S72R, S72P, S72WT, S72REC, S72F: a repository whose working branch
# wave/72-fixture is checked out in a linked worktree, four suites, the map configured, and F, the
# first commit past the cut, the head the floor ran at.
s72_world() {
  local b s
  S72R="$(make_repo "s72-$1")"; ( cd "$S72R" && git commit -q --allow-empty -m init )
  git -C "$S72R" config user.name "Dana Fixture"
  b="$(git -C "$S72R" rev-parse HEAD)"
  S72P="$(s42_plan "$S72R" "${2:-4}" "  worktree: .worktrees/72-fixture
  base-sha: ${b:0:8}
  branch: wave/72-fixture")"
  awk '{ print } /^current: / && !d { print "working-branch: wave/72-fixture"; d = 1 }' "$S72P" > "$S72P.tmp" && mv "$S72P.tmp" "$S72P"
  mkdir -p "$S72R/tests" "$S72R/lib"
  for s in a b c d; do printf '#!/bin/bash\nexit 0\n' > "$S72R/tests/$s.test.sh"; done
  printf 'one\n' > "$S72R/lib/one.sh"; printf 'two\n' > "$S72R/lib/two.sh"; printf 'every\n' > "$S72R/lib/every.sh"
  ( cd "$S72R" && git add -f "$S72P" tests lib && git commit -qm wb \
    && git worktree add -q -b wave/72-fixture "$S72R/.worktrees/72-fixture" ) >/dev/null 2>&1
  s72_config ""
  S72WT="$S72R/.worktrees/72-fixture"
  S72REC="$S72R/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S72REC"
  S72F="$(s57_commit "$S72WT" lib/one.sh F)"
}
s72_config() {  # <extra config line or empty> -> the project's config: the map, and the line
  { printf 'impact-command: bash %s\n' "$S72_MAP"; [ -z "$1" ] || printf '%s\n' "$1"; } > "$S72R/.bionic/config.yaml"
}
s72_run() {  # <suite> <command> -> the real shim runs <command> in the working checkout, naming <suite>
  ( cd "$S72WT" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_GATE_POLL=0.1 \
      bash "$S72_BOOKED" --suites "$1" -- "$2" ) >/dev/null 2>&1
}
s72_stamp() { tail -n 1 "$(git -C "$S72WT" rev-parse --absolute-git-dir)/bionic-stamps" 2>/dev/null; }
s72_add() {  # <evidence relative to the record> -> poke proof-add floor, the plan snapshotted first
  s42_snap "$S72R" "$S72P"
  poke "$S72R" proof-add floor "record/wave-01-fixture/$1"
}

s72_world pa
printf 'floor log\nhead=%s dirty=0\nGating: 4 passed, 0 failed\n' "$S72F" > "$S72REC/floor-F.txt"
S72H1="$(s57_commit "$S72WT" lib/one.sh H1)"
expect_regex "72a0 precondition: the floor head F and the working head H1 are 40-hex commits" \
  '^[0-9a-f]{40} [0-9a-f]{40}$' "$S72F $S72H1"
expect_true "72a0b precondition: F is an ancestor of H1 on the working branch" \
  git -C "$S72WT" merge-base --is-ancestor "$S72F" "$S72H1"
expect_eq "72a0c precondition: the map answers the change F..H1 with a and b" "a.test.sh b.test.sh" \
  "$(cd "$S72WT" && bash "$S72_MAP" lib/one.sh | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

# ---------- the runner's log at F: bounded, and each named suite must be green at H1 ----------
s72_add floor-F.txt
s42_unchanged "72a an ancestor floor, a bounded change, no green run at H1" 1 "$S72P"
expect_contains "72a2 …naming the commits since, the suites the map names, and the ones with no green run" \
  "read head ${S72F:0:12}, and 1 commit landed since, to the working head ${S72H1:0:12}; the map bounds the change to a.test.sh b.test.sh, and no green run at ${S72H1:0:12} is recorded for: a.test.sh b.test.sh. Run each of those suites on ${S72H1:0:12}, then proof-add floor again" "$OUT"
expect_absent "72a3 …and never 'run it again' (beside 72a2 on the same output)" "run it again" "$OUT"
s72_run a.test.sh "bash tests/a.test.sh"
expect_match "72b0 precondition: the real shim stamped a green, clean run of a at H1 in the working checkout's git dir" \
  "stamp/v1|head=${S72H1}|dirty=0|rc=0|at=*|suites=a.test.sh|cmd=bash tests/a.test.sh" "$(s72_stamp)"
s72_add floor-F.txt
s42_unchanged "72b a stamp for a alone" 1 "$S72P"
expect_contains "72b2 …names b, the suite still owed" "is recorded for: b.test.sh. Run each" "$OUT"
s72_run b.test.sh "false"
expect_match "72c0 precondition: the shim stamped b red at H1" "stamp/v1|head=${S72H1}|dirty=0|rc=1|at=*|suites=b.test.sh|cmd=false" "$(s72_stamp)"
s72_add floor-F.txt
s42_unchanged "72c a red run of b at H1" 1 "$S72P"
expect_contains "72c2 …names b" "is recorded for: b.test.sh. Run each" "$OUT"
s72_run b.test.sh "bash tests/b.test.sh"
s72_add floor-F.txt
expect_eq "72d AC-4.4 F an ancestor, F..H1 bounded, a and b green at H1: proof-add floor exits 0" "0" "$RC"
expect_eq "72d2 …and the proof names F, the head the run read" "$S72F" "$(s46_last "$S72P" floor)"
expect_contains "72d3 …and the verb says so" "proof-add — kind=floor head=$S72F" "$OUT"

# ---------- the attestation (floor-attestation: user): the later-changes: block, or the stamps ----------
S72H2="$(s57_commit "$S72WT" lib/one.sh H2)"
s72_config "floor-attestation: user"
s72_attest() {  # <file> <block lines...> -> an attestation of F, with a later-changes: block when lines are given
  local f="$S72REC/$1"; shift
  { printf 'head=%s dirty=0\nfloor-attested-by: Dana Fixture 2026-10-08 the full suite on F\n' "$S72F"
    if [ "$#" -gt 0 ]; then printf 'later-changes:\n'; printf '  - %s\n' "$@"; fi; } > "$f"
}
s72_attest att-none.md
s72_add att-none.md
s42_unchanged "72e an attestation of F with no block, and no stamp at H2" 1 "$S72P"
expect_contains "72e2 …the stamps are the proof: names both suites, and the two commits since" \
  "read head ${S72F:0:12}, and 2 commits landed since, to the working head ${S72H2:0:12}; the map bounds the change to a.test.sh b.test.sh, and no green run at ${S72H2:0:12} is recorded for: a.test.sh b.test.sh." "$OUT"
S72_BL="log=record/wave-01-fixture/later.log cmd=bash tests/run.sh --only"
s72_attest att-b.md "b.test.sh head=$S72H2 pass=4/4 $S72_BL b.test.sh"
s72_add att-b.md
s42_unchanged "72f a block naming b alone" 1 "$S72P"
expect_contains "72f2 …names a, the suite the block does not prove" \
  "the later-changes: block names no passing run at ${S72H2:0:12} for: a.test.sh. Run each of those suites on ${S72H2:0:12} and add its line to the block" "$OUT"
s72_attest att-oldhead.md "a.test.sh head=$S72H1 pass=4/4 $S72_BL a.test.sh" "b.test.sh head=$S72H2 pass=4/4 $S72_BL b.test.sh"
s72_add att-oldhead.md
s42_unchanged "72g a block whose a line ran at H1, not H2" 1 "$S72P"
expect_contains "72g2 …names a" "names no passing run at ${S72H2:0:12} for: a.test.sh." "$OUT"
s72_attest att-short.md "a.test.sh head=$S72H2 pass=3/4 $S72_BL a.test.sh" "b.test.sh head=$S72H2 pass=4/4 $S72_BL b.test.sh"
s72_add att-short.md
s42_unchanged "72h a block whose a line passed 3 of 4" 1 "$S72P"
expect_contains "72h2 …names a" "names no passing run at ${S72H2:0:12} for: a.test.sh." "$OUT"
s72_attest att-ok.md "a.test.sh head=$S72H2 pass=4/4 $S72_BL a.test.sh" "b.test.sh head=$S72H2 pass=4/4 $S72_BL b.test.sh"
s72_add att-ok.md
expect_eq "72i a block proving a and b at H2: the attestation of F is accepted (exit 0)" "0" "$RC"
expect_eq "72i2 …and the proof names F" "$S72F" "$(s46_last "$S72P" floor)"

# ---------- the declared floor: command's log at F ----------
s72_config "floor: true"
printf 'head=%s dirty=0 rc=0\ncommand: true\n' "$S72F" > "$S72REC/floor-run-F.log"
s72_add floor-run-F.log
s42_unchanged "72j a declared floor's log at F, no stamp at H2" 1 "$S72P"
expect_contains "72j2 …names both suites" "no green run at ${S72H2:0:12} is recorded for: a.test.sh b.test.sh." "$OUT"
s72_run a.test.sh "bash tests/a.test.sh"; s72_run b.test.sh "bash tests/b.test.sh"
s72_add floor-run-F.log
expect_eq "72k …with a and b green at H2, it is accepted (exit 0)" "0" "$RC"
expect_eq "72k2 …naming F" "$S72F" "$(s46_last "$S72P" floor)"

# ---------- what cannot be bounded still owes a full run on the working head, and says why ----------
s72_config ""
S72H3="$(s57_commit "$S72WT" lib/every.sh H3)"
s72_add floor-F.txt
s42_unchanged "72l a change the map answers with every suite" 1 "$S72P"
expect_contains "72l2 …owes the full run on H3, naming the commits since and the reason" \
  "run it again on ${S72H3:0:12} and cite that log: 3 commits landed since ${S72F:0:12}, and the change cannot be bounded (the map answers the change with every suite (4 of 4))" "$OUT"
S72X="$(s57_commit "$S72R" lib/side.sh X)"
printf 'floor log\nhead=%s dirty=0\nGating: 4 passed, 0 failed\n' "$S72X" > "$S72REC/floor-X.txt"
s72_add floor-X.txt
s42_unchanged "72m a run at a commit off the working branch" 1 "$S72P"
expect_contains "72m2 …says it is not in the working branch's history" \
  "run it again on ${S72H3:0:12} and cite that log: ${S72X:0:12} is not in the history of the working branch, so the change since it cannot be bounded" "$OUT"
POKE_BOUND="$S72_BOUND_WAS"

# ============================================================
section "Section 73 §BOUNDED-STAMPS: the judge reads a bounded change as covered only with a green stamp at the head for every suite the map names (wave-30 T13; REQ-4 AC-4.4; D7, design-ledger Δ6c)"
# ============================================================
#
# `facts_state` took proof_state's `bounded` as covered on no evidence: a change the map bounded
# held the floor whether or not any suite had run on it. The floor line is now covered only when
# every suite the map names has, at the working head, a newest stamp that is green on a clean tree
# (lib/worktree.sh `_wt_stale_proof`, the reader the landing uses); otherwise
# `floor<TAB>uncovered<TAB><suite>…`, the suites with no green run there. A change the map cannot
# bound keeps its range. The head moving owes the named suites again, never a second full run:
# proof_state, which the dispatch wall reads, still answers bounded. `current 8`, the gate that
# asks the judge, says which suites lack a green run.
#
# FIXTURE FIDELITY. §72's world builder; the floor line is the production writer's (proof_line,
# placed by proof_add_line) and the stamps are the real shim's.
S73_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s72_world bs 7
s57_floor "$S72F" "$S72P"
S73H1="$(s57_commit "$S72WT" lib/one.sh H1)"
s73_floor() {  # <head> -> what facts_state says of the floor line at <head>
  s57_state "$S72P" "$1"; s57_of floor
}
expect_eq "73a0 precondition: the plan's floor proof names F" "$S72F" "$(s46_last "$S72P" floor)"
expect_eq "73a0b precondition: proof_state reads F..H1 as bounded by a and b" "$(printf 'bounded\ta.test.sh b.test.sh')" \
  "$(bash -c '. "$1" && proof_state "$2" "$3"' _ "$S72_LIB" "$S72P" "$S72R" 2>/dev/null)"
expect_eq "73a no stamp file at all: the floor is uncovered, naming both suites" "$(printf 'uncovered\ta.test.sh b.test.sh')" "$(s73_floor "$S73H1")"
s72_run a.test.sh "bash tests/a.test.sh"
expect_eq "73b a green at H1: uncovered, naming b" "$(printf 'uncovered\tb.test.sh')" "$(s73_floor "$S73H1")"
s72_run b.test.sh "false"
expect_eq "73c b red at H1: uncovered, naming b" "$(printf 'uncovered\tb.test.sh')" "$(s73_floor "$S73H1")"
s72_run b.test.sh "bash tests/b.test.sh"
expect_eq "73d AC-4.4 a and b green at H1: covered" "covered" "$(s73_floor "$S73H1")"
printf 'x\n' > "$S72WT/untracked.txt"
s72_run a.test.sh "bash tests/a.test.sh"
expect_match "73e0 precondition: the shim stamped a on a dirty tree" "stamp/v1|head=${S73H1}|dirty=1|rc=0|*" "$(s72_stamp)"
expect_eq "73e a's newest run read a dirty tree: uncovered, naming a" "$(printf 'uncovered\ta.test.sh')" "$(s73_floor "$S73H1")"
rm -f "$S72WT/untracked.txt"
s72_run a.test.sh "bash tests/a.test.sh"
expect_eq "73e2 …a clean green run of a again: covered" "covered" "$(s73_floor "$S73H1")"
# THE HEAD MOVES: the stamps at H1 prove nothing at H2; the named suites are owed again, and the
# map still bounds the change, so no full run is.
S73H2="$(s57_commit "$S72WT" lib/two.sh H2)"
expect_eq "73f the head moved to H2 (lib/two.sh): uncovered, naming a, b and c" "$(printf 'uncovered\ta.test.sh b.test.sh c.test.sh')" "$(s73_floor "$S73H2")"
expect_eq "73f2 …while proof_state, which the dispatch wall reads, still says bounded: no second full run is owed" \
  "$(printf 'bounded\ta.test.sh b.test.sh c.test.sh')" "$(bash -c '. "$1" && proof_state "$2" "$3"' _ "$S72_LIB" "$S72P" "$S72R" 2>/dev/null)"
# THE GATE'S WORDS: current 8 asks the judge and names the suites with no green run at the head.
for s73q in evidence adversarial structure; do s57_fact "$s73q" "$S73H2" pass piece "$S72P"; done
for s73q in adversarial structure; do s57_fact "$s73q" "$S73H2" pass whole "$S72P"; done
s42_snap "$S72R" "$S72P"
poke "$S72R" current 8
s42_unchanged "73g current 8 with every reading at H2 and the bounded floor unstamped" 1 "$S72P"
expect_contains "73g2 …prints the judge's floor line" "$(printf 'floor\tuncovered\ta.test.sh b.test.sh c.test.sh')" "$OUT"
expect_contains "73g3 …and says which suites lack a green run at the head" \
  "regression: no green run at ${S73H2:0:12} for a.test.sh b.test.sh c.test.sh" "$OUT"
for s73s in a b c; do s72_run "$s73s.test.sh" "bash tests/$s73s.test.sh"; done
poke "$S72R" current 8
expect_eq "73h …with a, b and c green at H2, current 8 is admitted" "0" "$RC"
# A CHANGE THE MAP CANNOT BOUND keeps the range: a full run is owed, as before.
S73H3="$(s57_commit "$S72WT" lib/every.sh H3)"
expect_eq "73i an unbounded change: uncovered from F, the range, as before" "$(printf 'uncovered\t%s..%s' "$S72F" "$S73H3")" "$(s73_floor "$S73H3")"
POKE_BOUND="$S73_BOUND_WAS"


# ============================================================
section "Section 74 §TASK-SPLIT: task-split rewrites one pending row as its children in one validated transaction (wave-30 T17; REQ-12 AC-12.6; D14d-3, design-ledger Δ11)"
# ============================================================
#
# `task-split <id> -- <child spec>…`, each spec `<id>:<task>:<size>:<Files>` (the task may hold a
# colon; the id is before the first, the Files after the last). On a copy of the bound plan, through
# `units_split_row` and judged by `units_validate` and a dry commit through the real gate, as task-add
# is: the parent `dropped` with ` · split-into: <ids>`, the children added with the parent's step,
# kind, deps, serves and reads, every row that waited on the parent waiting on a child, and
# `- <parent>: split into <ids> at <instant>` under ## SDLC State. Refused, the plan byte-identical, on
# a parent that is not pending, on child Files that are not a cover of the parent's, and on a result
# the validator refuses. FIXTURE FIDELITY: §34's gate-admitted plan; the rows to split and their
# dependents added by the production verb, task-add. Two plans, because a reads table carries no task
# id in deps: the reader by its read is pinned on the reads table, the reader by deps on §42's.
S74_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S74_UNITS="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/units.sh"
S74_IFACE=".bionic/docs/record/wave-01-fixture/T6-iface.md"
s74_reads_plan() {  # <repo> -> the plan path; s34_plan's, with a reads column (§51's widening)
  local p; p="$(s34_plan "$1" 4)"
  awk '/^## Tasks/ { t = 1 } /^## Verification/ { t = 0 }
       t && /^\| id / { print $0 " reads |"; next }
       t && /^\|---/ { print $0 "---|"; next }
       t && /^\| T/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " — |"; next }
       { print }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  printf '%s' "$p"
}
s74_edges() { bash -c '. "$1" && units_edges "$2"' _ "$S74_UNITS" "$1" 2>/dev/null; }  # <plan>
s74_valid() { bash -c '. "$1" && units_validate "$2"' _ "$S74_UNITS" "$1" 2>&1; printf 'rc=%s' "$?"; }  # <plan>

# ---------- the reads table: a reader of the interface and the floor ----------
R74="$(make_repo s74-split-reads)"; ( cd "$R74" && git commit -q --allow-empty -m init )
P74="$(s74_reads_plan "$R74")"
poke "$R74" task-add T6 4 build 'the big one' w01-T6 '—' 90 REQ-5 "lib/c.sh, lib/d.sh, $S74_IFACE" 'approval:plan'
expect_eq "74a0 precondition: task-add of the row to split (exit 0)" "0" "$RC"
poke "$R74" task-add T7 4 build 'reads the interface' implementor '—' 30 REQ-5 'lib/e.sh' "$S74_IFACE"
expect_eq "74a0b precondition: task-add of its reader (exit 0)" "0" "$RC"
expect_contains "74a0c precondition: T7 waits on T6 for the interface" "$(printf 'T6\tT7\t%s' "$S74_IFACE")" "$(s74_edges "$P74")"
s34_gate "$R74"
expect_eq "74a0d precondition: the real commit gate admits the plan" "0" "$GATE_RC"
poke "$R74" task-split T6 -- "T8:the interface: its shape:20:$S74_IFACE, lib/c.sh" 'T9:the rest:70:lib/d.sh'
expect_eq "74a AC-12.6 task-split of a pending row exits 0" "0" "$RC"
expect_contains "74a2 …and says what it did, in one line" \
  "poker: task-split — T6 → T8, T9; 2 dependent(s) re-pointed; written to $(cd "${P74%/*}" && pwd -P)/${P74##*/}, dry-committed first." "$OUT"
expect_contains "74b the parent is dropped, its task naming the children" \
  "| T6 | 4 | build | the big one · split-into: T8, T9 | w01-T6 | — | 90 | REQ-5 | lib/c.sh, lib/d.sh, $S74_IFACE | — | — | dropped | approval:plan |" "$(cat "$P74")"
expect_contains "74c the first child carries the parent's step, kind, serves and reads; its task keeps its colon" \
  "| T8 | 4 | build | the interface: its shape | w01-T8 | — | 20 | REQ-5 | $S74_IFACE, lib/c.sh | — | — | pending | approval:plan |" "$(cat "$P74")"
expect_contains "74c2 …and the second its share of the Files" \
  "| T9 | 4 | build | the rest | w01-T9 | — | 70 | REQ-5 | lib/d.sh | — | — | pending | approval:plan |" "$(cat "$P74")"
S74_EDGES="$(s74_edges "$P74")"
expect_contains "74d the reader of the interface waits on the child that writes it" "$(printf 'T8\tT7\t%s' "$S74_IFACE")" "$S74_EDGES"
expect_contains "74d2 …and the floor on both children, by head" "$(printf 'T9\tT5\thead')" "$S74_EDGES"
expect_absent "74d3 …and nothing waits on the dropped parent" "$(printf 'T6\t')" "$S74_EDGES"
expect_regex "74e the ledger line under ## SDLC State" '^- T6: split into T8, T9 at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' \
  "$(/usr/bin/grep '^- T6:' "$P74")"
expect_regex "74e2 …and each child's line" '^- T8: pending dispatch — split from T6 at ' "$(/usr/bin/grep '^- T8:' "$P74")"
expect_eq "74f the plan passes its own validator" "rc=0" "$(s74_valid "$P74")"
s34_gate "$R74"
expect_eq "74f2 …and the real commit gate admits it" "0" "$GATE_RC"

# ---------- the table without reads: a reader by deps; the refusals ----------
R74N="$(make_repo s74-split-deps)"; ( cd "$R74N" && git commit -q --allow-empty -m init )
P74N="$(s42_plan "$R74N" 4)"
poke "$R74N" task-add T6 4 build 'the big one' bionic:implementor '—' 90 REQ-5 'lib/c.sh, lib/d.sh'
expect_eq "74g0 precondition: task-add of the row to split (exit 0)" "0" "$RC"
poke "$R74N" task-add T7 4 build 'after the big one' bionic:implementor 'T6' 30 REQ-5 'lib/e.sh'
expect_eq "74g0b precondition: task-add of a row whose deps name it (exit 0)" "0" "$RC"
expect_contains "74g0c precondition: task-add threaded both into the floor's deps" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2, T6, T7 |" "$(cat "$P74N")"
s42_snap "$R74N" "$P74N"
poke "$R74N" task-split T2 -- 'T8:a:10:b.sh' 'T9:b:10:b.sh'
s42_unchanged "74h AC-12.6 an active parent" 1 "$P74N"
expect_contains "74h2 …naming its status" "T2 is active" "$OUT"
poke "$R74N" task-split T1 -- 'T8:a:10:a.sh' 'T9:b:10:a.sh'
s42_unchanged "74h3 a landed parent" 1 "$P74N"
expect_contains "74h4 …naming its status" "T1 is landed" "$OUT"
poke "$R74N" task-split T6 -- 'T8:a:10:lib/c.sh' 'T9:b:10:lib/d.sh, lib/x.sh'
s42_unchanged "74i a child's Files outside the parent's" 1 "$P74N"
expect_contains "74i2 …naming the child and the path" "T9: Files entry lib/x.sh is not one of T6's Files" "$OUT"
poke "$R74N" task-split T6 -- 'T8:a:10:lib/c.sh' 'T9:b:10:lib/c.sh'
s42_unchanged "74j a partition that leaves a parent path out" 1 "$P74N"
expect_contains "74j2 …naming the path" "T6: Files entry lib/d.sh is in no child's Files" "$OUT"
poke "$R74N" task-split T6 -- 'T8a:a:10:lib/c.sh' 'T9:b:10:lib/d.sh'
s42_unchanged "74k a result the validator refuses (a child id off ^T[0-9]+\$)" 1 "$P74N"
expect_contains "74k2 …in the validator's words" "T8a: id does not match" "$OUT"
poke "$R74N" task-split T6 'T8:a:10:lib/c.sh' 'T9:b:10:lib/d.sh'
s42_unchanged "74l no -- is the usage error" 2 "$P74N"
poke "$R74N" task-split T6 -- 'T8:a:10:lib/c.sh, lib/d.sh'
s42_unchanged "74l2 one child is the usage error" 2 "$P74N"
poke "$R74N" task-split T6 -- 'T8:a:lib/c.sh' 'T9:b:10:lib/d.sh'
s42_unchanged "74l3 a spec short of <id>:<task>:<size>:<Files> is the usage error" 2 "$P74N"
poke "$R74N" task-split T6 -- 'T8:the half that is first:30:lib/c.sh' 'T9:the second half:60:lib/d.sh'
expect_eq "74m the split of the pending row exits 0" "0" "$RC"
expect_contains "74m2 …two rows waited on it, by deps" "2 dependent(s) re-pointed" "$OUT"
expect_contains "74n the reader by deps waits on every child in its place" \
  "| T7 | 4 | build | after the big one | bionic:implementor | T8, T9 |" "$(cat "$P74N")"
expect_contains "74n2 …the floor too, the token replaced where it stood, nothing threaded twice" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2, T8, T9, T7 |" "$(cat "$P74N")"
expect_contains "74n3 …the children carry the parent's deps and its agent" \
  "| T8 | 4 | build | the half that is first | bionic:implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending |" "$(cat "$P74N")"
expect_eq "74o0 precondition: before the split the same reader finds two deps cells naming T6" "2" \
  "$(awk -F'|' '/^\| T[0-9]+ \|/ && $7 ~ /(^|[ ,])T6([ ,]|$)/' "$TMPROOT/s42-before" | /usr/bin/grep -c .)"
expect_eq "74o no deps cell names the dropped parent" "0" \
  "$(awk -F'|' '/^\| T[0-9]+ \|/ && $7 ~ /(^|[ ,])T6([ ,]|$)/' "$P74N" | /usr/bin/grep -c .)"
expect_eq "74o2 …and the plan passes its own validator" "rc=0" "$(s74_valid "$P74N")"
s34_gate "$R74N"
expect_eq "74o3 …and the real commit gate admits it" "0" "$GATE_RC"
POKE_BOUND="$S74_BOUND_WAS"

finish
