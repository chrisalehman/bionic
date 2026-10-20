#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. One shard of four, in two parts: part 1 of 2, S10h … §LR.
#
# The suite's header (what it governs, how it stays hermetic) is in tests/dispatch-preflight.test.sh; the
# fixtures and their fidelity notes are in tests/dispatch-preflight.prelude.sh; what the two parts of this shard
# share, and why it is two, is in tests/dispatch-preflight-4.prelude.sh.
#
# THIS SHARD IS TWO PARTS (wave-39 T37; D1, D13, REQ-3 AC-3.3). One dispatch-preflight-4.test.sh promised more
# than a landing window holds, so it runs as two suites cut at a section boundary:
#
#   dispatch-preflight-4a.test.sh   S10h … §LR
#   dispatch-preflight-4b.test.sh   §T72 … §FILES
#
# Each is a gating suite by location and each passes alone.
#
# Usage: bash tests/run.sh --only dispatch-preflight-4a.test.sh


set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
# THE NARROWING (wave-39 T44; D6, AC-2.4, A-orch-22). The verbs of hooks/session-poker.sh this suite reaches,
# directly or through the hooks and scripts it runs: adopt, debt, interval, interval-default, proof-add, row-
# landed, window. Each line below is that closure: the library (every run executes it), the arm of each verb,
# the sections defining the globals they read, and each helper outside those.
reads hooks/session-poker.sh section "the library"
reads hooks/session-poker.sh section "whose run is this?"
reads hooks/session-poker.sh section "the plan transaction"
reads hooks/session-poker.sh fn clean
reads hooks/session-poker.sh fn clean_whole
reads hooks/session-poker.sh fn epoch_iso
reads hooks/session-poker.sh fn file_birth
reads hooks/session-poker.sh fn file_mtime
reads hooks/session-poker.sh fn iso_epoch
reads hooks/session-poker.sh fn iso_now
reads hooks/session-poker.sh fn line_field
reads hooks/session-poker.sh fn note
reads hooks/session-poker.sh fn now_epoch
reads hooks/session-poker.sh fn parse_seconds
reads hooks/session-poker.sh fn patrol_stamp_file
reads hooks/session-poker.sh fn poker_interval_seconds
reads hooks/session-poker.sh fn roster_window
reads hooks/session-poker.sh fn row_has_key
reads hooks/session-poker.sh fn session_transcript
reads hooks/session-poker.sh fn tmp_dir_ok
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

. "$(dirname "$0")/dispatch-preflight-4.prelude.sh"

section "S10h — a symlinked roster path is never written through, and the dispatch is refused (§8; wave-28 T70)"
#
# A hostile repo controls its own .bionic/ contents. It must not gain an arbitrary-file append,
# and since T70 it must not gain a silent admission either. (The DIRECTORY-level variants are
# already refused upstream by the attestation check — S8 drives them — so the file level is the
# only one reachable here.)

REPO=$(make_repo r10h yes)
write_attestation "$REPO" "$SID_A"
# DECOY_ROSTER: hoisted to tests/dispatch-preflight-4.prelude.sh (§RECORDER, in part b, reads the file this section plants)
ln -s "$DECOY_ROSTER" "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "a symlinked roster path REFUSES the dispatch" "deny" "$GATE_VERDICT"
expect_contains "…on one line, in the dispatch wall's shape" \
  "bionic: dispatch refused — the roster path is a symbolic link (remove the link)" "$GATE_ERR"
expect_contains "…the detail names the link" "roster-${SID_A}.state" "$GATE_VERR"
expect_status "the symlink target is not appended to" "untouched" "$(cat "$DECOY_ROSTER")"

section "§Q — a reader's brief names its questions, held to the dealing (wave-27 T15; REQ-5 AC-5.1, REQ-1 AC-1.3, D5)"
# ============================================================================
#
# A READER IS DISPATCHED FOR ITS QUESTIONS. `bionic:auditor` and `bionic:critic` (the structure
# reader `bionic:reviewer` is retired, wave-30 T20, and is refused at §RET) carry a `Questions: <q>[, <q>]` line; the wall refuses a reader brief without one, refuses a set
# that is not exactly what `facts_owed <rigor> <scale>` (lib/proof.sh) deals that role at the bound
# plan's rigor, refuses a word outside the three questions, and records the set on the row as
# `questions=` in the order evidence, adversarial, structure. With no bound plan the line is still
# required and the dealing is not checked. Every other role is untouched.
#
# THE TWO EVIDENCE RULES FOLLOW THE QUESTION (review pass 15, F4). The three-run cap and the
# refusal of a brief that names no suite and no run used to key on the auditor; `single` deals
# `evidence` to the critic, which escaped both. And the cap counts every declared run but file
# housekeeping (wave-27 T49): a cleanup beside three runs is recorded and does not count.
#
# FIXTURES: make_repo's plan is `rigor: double`, `scale: wave`, approved and bound; `q_rigor`
# rewrites its rigor line. The briefs are SYNTHESIZED and write their own `Questions:` line.
#
# fails-when: a reader brief with no line, a wrong set or an unknown word is admitted; an admitted
# reader's row lacks `questions=` or holds it unordered; a writer's brief meets the label at all; a
# critic holding `evidence` escapes the cap or the no-suite refusal; a housekeeping run counts; an
# unknown runner escapes the cap; a Questions: comment, repeat or fenced example is misread.
# q_rigor, q_brief, q_row, q_gate: hoisted to tests/dispatch-preflight-4.prelude.sh (parts a and b both call them)

REPO=$(make_repo rq0 yes)
q_rigor "$REPO" single
expect_eq "Q0 precondition: q_rigor rewrites the bound plan's rigor line" "rigor: single" \
  "$(grep '^rigor:' "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md")"

# ---- the worked answers on a double plan ----
REPO=$(make_repo rq1 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q1 bionic:auditor "$(q_brief q1 'Questions: evidence')"
expect_eq "Q1 double: an auditor with Questions: evidence is admitted" "allow" "$GATE_VERDICT"
expect_eq "Q1 …and its row carries questions=evidence" "evidence" "$(roster_field "$(q_row "$REPO")" questions)"

REPO=$(make_repo rq2 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q2 bionic:auditor "$(q_brief q2 'Questions: evidence, structure')"
expect_eq "Q2 double: an auditor with Questions: evidence, structure is refused" "deny" "$GATE_VERDICT"
expect_contains "Q2 …the line names the rigor, the role and the set it deals" \
  "double rigor deals auditor: evidence" "$GATE_ERR"
expect_contains "Q2 …the detail names the set the brief gave" "evidence, structure" "$GATE_VERR"
expect_contains "Q2 …and the line to write" "    Questions: evidence" "$GATE_VERR"

REPO=$(make_repo rq3 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q3 bionic:auditor "$(q_brief q3)"
expect_eq "Q3 double: an auditor brief with no Questions: line is refused" "deny" "$GATE_VERDICT"
expect_contains "Q3 …the line names the role and the missing label" \
  "bionic:auditor names no Questions: line" "$GATE_ERR"
expect_contains "Q3 …the detail names the line to add, the dealt set filled in" \
  "    Questions: evidence" "$GATE_VERR"

# ---- a set: order and spacing do not matter; the row is written in the table's order ----
REPO=$(make_repo rq4 yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" double
q_gate "$REPO" q4 bionic:critic "$(q_brief q4 'Questions: structure, adversarial')"
expect_eq "Q4 double: a critic with Questions: structure, adversarial is admitted" "allow" "$GATE_VERDICT"
expect_eq "Q4 …its row carries questions=adversarial,structure" "adversarial,structure" \
  "$(roster_field "$(q_row "$REPO")" questions)"
REPO=$(make_repo rq4b yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" double
q_gate "$REPO" q4b bionic:critic "$(q_brief q4b 'Questions:adversarial,structure')"
expect_eq "Q4b …and so is the same set written with no spaces" "adversarial,structure" \
  "$(roster_field "$(q_row "$REPO")" questions)"

# ---- single deals the auditor nothing ----
REPO=$(make_repo rq5 yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" single
q_gate "$REPO" q5 bionic:auditor "$(q_brief q5 'Questions: evidence')"
expect_eq "Q5 single: an auditor with Questions: evidence is refused" "deny" "$GATE_VERDICT"
expect_contains "Q5 …the line says that rigor deals the auditor nothing" \
  "single rigor deals auditor: nothing" "$GATE_ERR"
expect_contains "Q5 …and the detail names the role that holds the question" \
  "evidence is dealt to bionic:critic" "$GATE_VERR"

# ---- a word outside the three questions ----
REPO=$(make_repo rq6 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q6 bionic:auditor "$(q_brief q6 'Questions: evidence, style')"
expect_eq "Q6 a word outside the three questions is refused" "deny" "$GATE_VERDICT"
expect_contains "Q6 …naming it" "unknown question: style" "$GATE_ERR"

# ---- no bound plan: the label is required, the dealing is not checked ----
# q_unbound: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part calls it)
REPO=$(q_unbound rq7)
q_gate "$REPO" q7 bionic:auditor "$(q_brief q7 'Questions: structure')"
expect_eq "Q7 no bound plan: a reader brief with a well-formed line is admitted" "allow" "$GATE_VERDICT"
expect_eq "Q7 …and its set recorded, with no dealing to hold it to" "structure" \
  "$(roster_field "$(q_row "$REPO")" questions)"
REPO=$(q_unbound rq7b)
q_gate "$REPO" q7b bionic:auditor "$(q_brief q7b)"
expect_eq "Q7b no bound plan: a reader brief without the line is refused" "deny" "$GATE_VERDICT"
expect_contains "Q7b …naming the missing label" "bionic:auditor names no Questions: line" "$GATE_ERR"

# ---- the three legal deals, from REQ-1's table (wave-30 T11, D1); a role dealt nothing is refused ----
for _q_deal in "single bionic:critic evidence,adversarial,structure" \
               "double bionic:auditor evidence" "double bionic:critic adversarial,structure"; do
  set -- $_q_deal
  REPO=$(make_repo "rq8-$1-${2#bionic:}" yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" "$1"
  q_gate "$REPO" "q8-$1-${2#bionic:}" "$2" "$(q_brief q8 "Questions: ${3//,/, }")"
  expect_eq "Q8 $1 deals $2 $3: admitted" "allow" "$GATE_VERDICT"
  expect_eq "Q8 …recorded as dealt" "$3" "$(roster_field "$(q_row "$REPO")" questions)"
done
# The retired reviewer is refused as retired, not as dealt nothing: §RET holds it, both levels.
for _q_none in "single bionic:auditor evidence"; do
  set -- $_q_none
  REPO=$(make_repo "rq8n-$1-${2#bionic:}" yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" "$1"
  q_gate "$REPO" "q8n-$1-${2#bionic:}" "$2" "$(q_brief q8n "Questions: $3")"
  expect_eq "Q8n $1 deals $2 nothing: refused" "deny" "$GATE_VERDICT"
  # The line names the level by its new word and the role by its short name (wave-28 T44, A-orch-17).
  expect_contains "Q8n …saying so" "$(bash -c '. "$1" && rigor_level "$2"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/run.sh" "$1") rigor deals ${2#bionic:}: nothing" "$GATE_ERR"
done
set --
# A part of a dealt set is not the set: at double the critic holds adversarial AND structure.
REPO=$(make_repo rq8p yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" double
q_gate "$REPO" q8p bionic:critic "$(q_brief q8p 'Questions: adversarial')"
expect_eq "Q8p double deals the critic adversarial and structure: adversarial alone is refused" "deny" "$GATE_VERDICT"
expect_contains "Q8p …naming the set it deals" "double rigor deals critic: adversarial,structure" "$GATE_ERR"

# ---- every other role is untouched ----
REPO=$(make_repo rq9 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q9 bionic:implementor "$(q_brief q9 'Questions: evidence, bogus')"
expect_eq "Q9 a writer brief carrying a Questions: line is not judged by it" "allow" "$GATE_VERDICT"
expect_eq "Q9 …its row is written (the positive on this extractor)" "wq-q9" "$(roster_field "$(q_row "$REPO")" name)"
expect_absent "Q9 …and carries no questions=" "questions=" "$(q_row "$REPO")"
REPO=$(make_repo rq9b yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q9b bionic:test-runner "$(q_brief q9b)"
expect_eq "Q9b a test-runner brief needs no Questions: line" "allow" "$GATE_VERDICT"

# ---- F4: the evidence rules follow the question, whichever reader holds it ----
Q_FOUR="Re-executes: ${RL_JEST}
Re-executes: ${RL_PYTEST}
Re-executes: ${RL_GO}
Re-executes: ${RL_NPM}"
REPO=$(make_repo rq10 yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" single
q_gate "$REPO" q10 bionic:critic "Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-q10.md
Expected duration: ~30 minutes.
Questions: evidence, adversarial, structure
Files: .bionic/docs/record/wq-q10.md, .bionic/docs/record/wq-q10-2.md, .bionic/docs/record/wq-q10-3.md
${Q_FOUR}"
expect_eq "Q10 single: a critic holding evidence with four suite runs is refused" "deny" "$GATE_VERDICT"
expect_contains "Q10 …on the cap of three, as an auditor's is" "exceeds the 3-run cap" "$GATE_ERR"

REPO=$(make_repo rq11 yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" single
q_gate "$REPO" q11 bionic:critic "Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-q11.md
Expected duration: ~30 minutes.
Questions: evidence, adversarial, structure
Files: .bionic/docs/record/wq-q11.md, .bionic/docs/record/wq-q11-2.md, .bionic/docs/record/wq-q11-3.md
Suites: none"
expect_eq "Q11 single: the same critic waiving every suite with no run is refused" "deny" "$GATE_VERDICT"
expect_contains "Q11 …as an auditor's is: it declares nothing to re-execute" "declares nothing to re-execute" "$GATE_ERR"

REPO=$(make_repo rq12 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q12 bionic:critic "Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-q12.md
Expected duration: ~30 minutes.
Questions: adversarial, structure
Files: .bionic/docs/record/wq-q12.md, .bionic/docs/record/wq-q12-2.md
Suites: none"
expect_eq "Q12 double: a critic with Questions: adversarial, structure and Suites: none is admitted" "allow" "$GATE_VERDICT"

# ---- the cap counts every run but housekeeping; a cleanup is recorded and does not count ----
REPO=$(make_repo rq13 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q13 bionic:auditor "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/wq-q13.md
Expected duration: ~30 minutes.
Questions: evidence
Re-executes: ${RL_JEST}
Re-executes: ${RL_PYTEST}
Re-executes: ${RL_GO}
Re-executes: ${RL_BT}rm -rf dist/cache${RL_BT}"
expect_eq "Q13 three suite runs and one rm -rf dist/cache are admitted" "allow" "$GATE_VERDICT"
expect_eq "Q13 …with all four recorded, in order" \
  "${RL_JEST} ${RL_PYTEST} ${RL_GO} ${RL_BT}rm -rf dist/cache${RL_BT}" \
  "$(roster_field "$(q_row "$REPO")" re_executes)"
REPO=$(make_repo rq14 yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" q14 bionic:auditor "Your task: re-run the evidence.
Expected artifact: .bionic/docs/record/wq-q14.md
Expected duration: ~30 minutes.
Questions: evidence
${Q_FOUR}"
expect_eq "Q14 four suite runs are refused, as today" "deny" "$GATE_VERDICT"
expect_contains "Q14 …on the 3-run cap" "exceeds the 3-run cap" "$GATE_ERR"

# THE AMEND DOOR READS THE SAME COUNT: `session-poker.sh amend --reexec+` lifts the span
# `poker_brief_span` builds — one `Re-executes:` line of marked runs — with the row's role, through
# the same two library calls driven here.
Q_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh"
q_lib_verdict() {  # <role> <span> -> one `finding: <fact>` per sink call, then rc=
  bash -c '. "$1" || exit 9
    sink() { [ "$1" = finding ] && printf "finding: %s\n" "$2"; return 0; }
    rc=0; brief_validate_fields "$(lift_contract_fields "$3" "$2")" "$2" "$4" sink || rc=$?
    printf "rc=%s\n" "$rc"' _ "$Q_LIB" "$1" "$2" "$SANDBOX" 2>&1
}
Q_SPAN="Suites: none
Re-executes: ${RL_BT}go test ./a${RL_BT} ${RL_BT}go test ./b${RL_BT} ${RL_BT}go test ./c${RL_BT} ${RL_BT}rm -rf dist/cache${RL_BT}"
Q15=$(q_lib_verdict bionic:auditor "$Q_SPAN")
expect_contains "Q15 the amend span: three suite runs and a cleanup pass the auditor's cap" "rc=0" "$Q15"
expect_absent "Q15 …with no finding" "finding:" "$Q15"
Q15B=$(q_lib_verdict bionic:auditor "$Q_SPAN ${RL_BT}cargo test${RL_BT}")
expect_contains "Q15b …and a fourth suite run is refused there as at dispatch" \
  "finding: the total of 4 runs exceeds the 3-run cap" "$Q15B"

# ---- T49 (review passes 19 and 24): the cap counts EVERY declared run but file housekeeping ----
# The classifier does not know `python -m pytest`, so under "suite runs only" six of them were
# admitted beside an auditor's cap of three. The cap now counts every declared command except one
# with no `;`, `&&`, `|`, backquote or `$(` whose first WORD is rm, rmdir, mkdir, touch, cp or mv
# (`dp_housekeeping_words`, beside the cap). Identical runs are one run (the union), so the six
# below differ in their argument.
# q_span <questions> <suites> <run>... -> a brief span: the Questions: and Suites: lines, then one
# Re-executes: line per run, each run marked with backticks.
q_span() {
  local q="$1" s="$2" r; shift 2
  printf 'Questions: %s\nSuites: %s' "$q" "$s"
  for r in "$@"; do printf '\nRe-executes: %s%s%s' "$RL_BT" "$r" "$RL_BT"; done
}
q_lift() {  # <role> <span> <field> -> that field of the lift, as the row stores it
  bash -c '. "$1" || exit 9; brief_field "$(lift_contract_fields "$3" "$2")" "$4"' _ "$Q_LIB" "$1" "$2" "$3" 2>&1
}
Q49_PY=(); for _q49 in a b c d e f; do Q49_PY+=("python -m pytest tests/$_q49"); done
for Q49_ROLE in bionic:auditor bionic:critic; do
  V=$(q_lib_verdict "$Q49_ROLE" "$(q_span evidence none "${Q49_PY[@]}")")
  expect_contains "T49-Q1 $Q49_ROLE: six python -m pytest runs are refused on the cap of three" \
    "finding: the total of 6 runs exceeds the 3-run cap" "$V"
  V=$(q_lib_verdict "$Q49_ROLE" "$(q_span evidence none "${Q49_PY[@]:0:3}")")
  expect_contains "T49-Q1 …while three of them are admitted (the positive beside it)" "rc=0" "$V"
  expect_absent "T49-Q1 …with no finding" "finding:" "$V"
done
V=$(q_lib_verdict implementor "$(q_span evidence none "${Q49_PY[@]}")")
expect_contains "T49-Q1 a writer holding no cap declares the six" "rc=0" "$V"

V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'bash tests/x.test.sh' 'bash tests/y.test.sh' 'bash tests/z.test.sh' 'rm -rf dist/cache')")
expect_contains "T49-Q2 three runs and one rm -rf dist/cache are admitted" "rc=0" "$V"
expect_eq "T49-Q2 …with four recorded" \
  "${RL_BT}bash tests/x.test.sh${RL_BT} ${RL_BT}bash tests/y.test.sh${RL_BT} ${RL_BT}bash tests/z.test.sh${RL_BT} ${RL_BT}rm -rf dist/cache${RL_BT}" \
  "$(q_lift bionic:auditor "$(q_span evidence none 'bash tests/x.test.sh' 'bash tests/y.test.sh' 'bash tests/z.test.sh' 'rm -rf dist/cache')" re_executes)"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'bash tests/x.test.sh' 'bash tests/y.test.sh' 'bash tests/z.test.sh' 'rm -rf dist && bash tests/w.test.sh')")
expect_contains "T49-Q3 three runs and rm -rf dist && bash tests/w.test.sh: the && makes it a run, four" \
  "finding: the total of 4 runs exceeds the 3-run cap" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'bash tests/x.test.sh' 'bash tests/y.test.sh' 'bash tests/z.test.sh' 'mkdir -p out' 'cp a b' 'touch f' 'mv a b' 'rmdir d')")
expect_contains "T49-Q4 mkdir, cp, touch, mv and rmdir do not count" "rc=0" "$V"
for Q49_RUN in 'rmx -rf dist' './rm -rf dist' 'rm -rf dist; true' 'rm -rf $(pwd)/dist'; do
  V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'bash tests/x.test.sh' 'bash tests/y.test.sh' 'bash tests/z.test.sh' "$Q49_RUN")")
  expect_contains "T49-Q5 '$Q49_RUN' is a fourth run, not housekeeping: refused on the cap" \
    "finding: the total of 4 runs exceeds the 3-run cap" "$V"
done
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf dist')")
expect_contains "T49-Q6 a reader with Suites: none and only rm -rf dist is refused" "finding: the auditor declares nothing to re-execute" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf dist' 'mkdir out')")
expect_contains "T49-Q6 …two housekeeping commands are no run either" "finding: the auditor declares nothing to re-execute" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf dist' 'bash tests/x.test.sh')")
expect_contains "T49-Q6 …while one run beside the housekeeping admits it (the positive)" "rc=0" "$V"
V=$(q_lib_verdict bionic:critic "$(q_span evidence none 'rm -rf dist')")
expect_contains "T49-Q6 …and a critic holding evidence is held the same" "finding: the critic declares nothing to re-execute" "$V"

# ---- T49: the Questions: label is read as the other labels are ----
# q_hits <brief> <role> -> the row's questions=, or `deny:<first refusal line>`.
q49_gate() {  # <tag> <role> <rigor> <brief>
  local repo; repo=$(make_repo "rq49-$1" yes); write_attestation "$repo" "$SID_A"; q_rigor "$repo" "$3"
  REPO="$repo"; q_gate "$repo" "q49-$1" "$2" "$4"
  if [ "$GATE_VERDICT" = allow ]; then R="allow:$(roster_field "$(q_row "$repo")" questions)"
  else R="deny:$(printf "%s\n" "$GATE_ERR" | /usr/bin/grep -m1 "bionic: dispatch refused")"; fi
}
Q49_HEAD='Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-q49.md
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh'
q49_gate c1 bionic:auditor double "$Q49_HEAD
Questions: evidence  # the auditor's"
expect_eq "T49-Q7 a trailing comment is stripped: Questions: evidence  # the auditor's is evidence" "allow:evidence" "$R"
q49_gate c2 bionic:critic double "$Q49_HEAD
Questions: structure, adversarial # both
Files: .bionic/docs/record/wq-q49.md, .bionic/docs/record/wq-q49-2.md"
expect_eq "T49-Q7 …a comment after a set, too" "allow:adversarial,structure" "$R"
q49_gate c3 bionic:auditor double "$Q49_HEAD
Questions: evidence
Questions: evidence"
expect_contains "T49-Q8 two Questions: lines, even with the same set, are refused" "deny:" "$R"
expect_contains "T49-Q8 …the first line naming the count" "bionic:auditor has 2 Questions: lines" "$R"
Q49_REFUSAL=$(printf '%s\n' "$GATE_VERR")
expect_contains "T49-Q8 …and the detail naming both lines by number" "lines 5 and 6" "$Q49_REFUSAL"
q49_gate c4 bionic:auditor double "$Q49_HEAD
Questions: evidence
Questions: structure"
expect_contains "T49-Q8 …two different sets are refused the same" "has 2 Questions: lines" "$R"
for Q49_C in "bionic:auditor double evidence" "bionic:critic single evidence,adversarial,structure"; do
  set -- $Q49_C
  q49_gate "c5-${1#bionic:}" "$1" "$2" "$Q49_HEAD
Questions: ${3//,/, }
Questions: ${3//,/, }"
  Q49_LINE="${R#deny:}"
  expect_contains "T49-Q8 $1 at $2 with $3 given twice is refused" "has 2 Questions: lines" "$R"
  expect_eq "T49-Q8 …its first line fits the 100-column budget" "ok" "$([ "$(bionic_cols "$Q49_LINE")" -le 100 ] && echo ok || echo "wide:$(bionic_cols "$Q49_LINE")")"
done
set --
q49_gate c6 bionic:auditor double "Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-q49.md
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh
${RL_BT}${RL_BT}${RL_BT}
Questions: structure, adversarial
${RL_BT}${RL_BT}${RL_BT}
Questions: evidence"
expect_eq "T49-Q9 a Questions: line inside a fenced block is an example: the real line below it is the label" "allow:evidence" "$R"
q49_gate c7 bionic:auditor double "Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-q49.md
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh
${RL_BT}${RL_BT}${RL_BT}
Questions: evidence
${RL_BT}${RL_BT}${RL_BT}"
expect_contains "T49-Q9 a brief whose only Questions: line is inside a fence has no label: refused" "bionic:auditor names no Questions: line" "$R"

# ============================================================================

section "§scaffold-walk — a reader filled from the shipped scaffold is admitted and every record it writes registers (wave-27 T53; review pass 28 B1, B2, B3)"
# ============================================================================
#
# THE WALK A READER TAKES, END TO END. The scaffold is read out of the shipped dispatch.md
# (never retyped) and filled as the text around it says for a reader: one record per question
# dealt, every record on `Files:`, `Expected artifact:` naming one of them, the `Questions:` line
# filled WITH its trailing comment kept, every other comment kept too, and `Suites:` naming a
# suite only for the reader dealt `evidence`. That brief drives the REAL dispatch wall; the real
# execution recorder starts the agent; the records are written in the checks files' form; and
# each is registered with the REAL `session-poker.sh proof-add review`, which takes a record only
# from the reader's own roster row. Section §Q holds the dealing itself; this holds the text.
#
# FIXTURES: make_repo's bound plan, its rigor rewritten (q_rigor), given the frontmatter
# `base-sha:` and `working-branch:` a reading needs, and one commit past the base for the range.
#
# fails-when: the shipped scaffold, filled as the text says, is refused; a record it lists is
# refused at registration; or a `single` critic brief that declares no run is admitted.
walk_fill() {  # <questions> <records, ", "-joined> <suites value|none> -> a reader brief
  local qs="$1" recs="$2" suites="$3" line value
  printf 'Your task: read T3 for the questions below.\n'
  while IFS= read -r line; do
    case "${line%%:*}" in
      "Done marker"|"Subprocess claim"|"Deliverable-waiver"|"Re-executes") continue ;;
      "Expected duration") value="30" ;;
      "Expected artifact") value="${recs%%,*}" ;;
      "Progress artifact") value=".bionic/docs/record/wave-01-test/T3-read.progress" ;;
      "Cadence")           value="15" ;;
      "Files")             value="$recs" ;;
      # `<q>[, <q>]` holds a `>` before its `]`, so the span is cut at the `]`, comment kept.
      "Questions") line="Questions: ${qs}${line#*\]}"; value="" ;;
      "Suites") [ "$suites" = none ] || line="Suites: ${suites}${line#Suites: none}"; value="" ;;
      *) value="" ;;
    esac
    case "$line" in *"<"*">"*) line="${line%%<*}${value}${line##*>}" ;; esac
    printf '%s\n' "$line"
  done < <(scaffold_block "$DISPATCH_FILE")
}
# walk_repo, walk_start: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part calls them)
WALK_OUT=""; WALK_RC=0
# A reader dealt a code question is pushed the severity scale (T16), so its records carry the
# finding lines (T15): `findings: 0`, the walk planting none. The one reader the walk deals
# `evidence` alone is not pushed it, and its record stays in the 1.12.0 form: pass `old` as the
# fifth argument.
walk_register() {  # <repo> <record path> <question> <reader> [old] -> writes the record, then proof-add
  local repo="$1" rec="$2" q="$3" form="${5:-scaled}" base head id
  base="$(git -C "$repo" rev-list --max-parents=0 HEAD)"; head="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$(dirname "$repo/$rec")"
  { printf 'reviewed: %s..%s\nquestion: %s\nresult: pass\nscope: piece\n' "$base" "$head" "$q"
    [ "$form" = old ] || printf 'findings: 0\n'
    if [ "$q" = structure ]; then
      for id in reuse one-site single-job open-closed substitution narrow-interface dependency-direction; do
        printf 'check: %s PASS nothing found\n' "$id"; done
    fi
    printf '\nwhat the reader found\n'; } > "$repo/$rec"
  WALK_OUT=$(cd "$repo" && env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$SID_A" \
    bash "${BIONIC_HOOKS_DIR}/session-poker.sh" proof-add review "${rec#.bionic/docs/}" \
      --question "$q" --reader "$4" 2>&1); WALK_RC=$?
}
WALK_REC=".bionic/docs/record/wave-01-test"

# ---- double: the critic dealt adversarial and structure ----
WALK_PR="$(walk_fill "adversarial, structure" "$WALK_REC/T3-adversarial.md, $WALK_REC/T3-structure.md" none)"
expect_contains "§scaffold-walk precondition: the filled Questions: line keeps the shipped comment" \
  "Questions: adversarial, structure  # reader roles only" "$WALK_PR"
expect_contains "§scaffold-walk precondition: …and Files: lists both records" \
  "Files: $WALK_REC/T3-adversarial.md, $WALK_REC/T3-structure.md" "$WALK_PR"
expect_absent "§scaffold-walk precondition: …and no placeholder is left" "<" "$WALK_PR"
REPO=$(walk_repo rwalk1 double)
q_gate "$REPO" walk1 bionic:critic "$WALK_PR"
expect_eq "§scaffold-walk double: the critic's brief, filled from the shipped scaffold, is ADMITTED" \
  "allow" "$GATE_VERDICT"
expect_eq "§scaffold-walk …its row carries both records" \
  "$WALK_REC/T3-adversarial.md,$WALK_REC/T3-structure.md" "$(roster_field "$(q_row "$REPO")" files)"
expect_eq "§scaffold-walk …and its dealt set" "adversarial,structure" "$(roster_field "$(q_row "$REPO")" questions)"
walk_start "$REPO" wq-walk1
walk_register "$REPO" "$WALK_REC/T3-adversarial.md" adversarial wq-walk1
expect_eq "§scaffold-walk …the adversarial record registers with the real proof-add" "0" "$WALK_RC"
expect_contains "§scaffold-walk …as a reading of that question by that reader" \
  "question=adversarial reader=wq-walk1 result=pass" "$WALK_OUT"
walk_register "$REPO" "$WALK_REC/T3-structure.md" structure wq-walk1
expect_eq "§scaffold-walk …and so does the structure record" "0" "$WALK_RC"
expect_contains "§scaffold-walk …as a reading of structure" "question=structure reader=wq-walk1 result=pass" "$WALK_OUT"

# ---- the discriminator: the brief as the old text had it, one artifact and no Files: ----
# Either the wall refuses it (T49: fewer paths than questions) or its second record is refused
# at registration; the walk never completes. The first record's acceptance is the positive.
REPO=$(walk_repo rwalk2 double)
q_gate "$REPO" walk2 bionic:critic "$(printf '%s\n' "$WALK_PR" | /usr/bin/grep -v '^Files:')"
WALK_OLD="refused-at-dispatch"
if [ "$GATE_VERDICT" = allow ]; then
  walk_start "$REPO" wq-walk2
  walk_register "$REPO" "$WALK_REC/T3-adversarial.md" adversarial wq-walk2
  expect_eq "§scaffold-walk …the old shape's one named record registers (the positive)" "0" "$WALK_RC"
  walk_register "$REPO" "$WALK_REC/T3-structure.md" structure wq-walk2
  WALK_OLD="registered rc=$WALK_RC"
  [ "$WALK_RC" -ne 0 ] && WALK_OLD="refused-at-registration"
fi
expect_ne "§scaffold-walk …a brief with one artifact and no Files: never gets both records registered" \
  "registered rc=0" "$WALK_OLD"

# ---- single: the critic holds all three questions, evidence among them ----
WALK_T="$(walk_fill "evidence, adversarial, structure" \
  "$WALK_REC/T3-evidence.md, $WALK_REC/T3-adversarial.md, $WALK_REC/T3-structure.md" tests/widget.test.sh)"
expect_contains "§scaffold-walk precondition: the single brief names its suite, the comment kept" \
  "Suites: tests/widget.test.sh  # " "$WALK_T"
REPO=$(walk_repo rwalk3 single)
q_gate "$REPO" walk3 bionic:critic "$WALK_T"
expect_eq "§scaffold-walk single: the critic dealt evidence, naming its run, is ADMITTED" "allow" "$GATE_VERDICT"
expect_eq "§scaffold-walk …its row carries the three records" \
  "$WALK_REC/T3-evidence.md,$WALK_REC/T3-adversarial.md,$WALK_REC/T3-structure.md" \
  "$(roster_field "$(q_row "$REPO")" files)"
walk_start "$REPO" wq-walk3
for _wq in evidence adversarial structure; do
  walk_register "$REPO" "$WALK_REC/T3-${_wq}.md" "$_wq" wq-walk3
  expect_eq "§scaffold-walk …the ${_wq} record registers" "0" "$WALK_RC"
done
REPO=$(walk_repo rwalk4 single)
q_gate "$REPO" walk4 bionic:critic "$(walk_fill "evidence, adversarial, structure" \
  "$WALK_REC/T3-evidence.md, $WALK_REC/T3-adversarial.md, $WALK_REC/T3-structure.md" none)"
expect_eq "§scaffold-walk …the SAME brief with Suites: none and no Re-executes: is refused" "deny" "$GATE_VERDICT"
# The user stream leads with the first fault; the model's wire names every one (several faults
# before T49 strips the Questions: comment, one after), so the two are read together.
expect_contains "§scaffold-walk …because the evidence reader declares nothing to re-execute (T57's words)" \
  "the critic declares nothing to re-execute" "$GATE_ERR $GATE_REASON"

# ---- an evidence reader whose runner is not a shell suite (wave-27 T60; review pass 38 B1) ----
# The text says one thing whatever the runner: suites under `Suites:`, any other runner under
# `Re-executes:`, one to three in all, and `Suites: none` beside a `Re-executes:` that names a
# run is right. So a pytest reader fills the scaffold's own `Re-executes:` line and EITHER keeps
# `Suites: none` (shape A) OR drops the `Suites:` line (shape B), where pass 38 found the reader
# refused. Shape B is admitted only with T57's wall half (a reader's `Files:` names no suite) on
# the head.
WALK_RUN='pytest tests/'
walk_fill_re() {  # <questions> <records> <A|B> -> walk_fill's brief with the scaffold's Re-executes: filled
  local re
  re="$(scaffold_raw_line "$DISPATCH_FILE" Re-executes)"
  re="${re%%<*}${WALK_RUN}${re##*>}"
  walk_fill "$1" "$2" none | /usr/bin/awk -v re="$re" -v shape="$3" '
    /^Suites:/ { if (shape == "A") print; print re; next } { print }'
}
WALK_ER="$(walk_fill_re evidence "$WALK_REC/T3-evidence.md" A)"
expect_contains "§scaffold-walk precondition: the scaffold's Re-executes: line is filled with the run" \
  "Re-executes: \`$WALK_RUN\`" "$WALK_ER"
expect_contains "§scaffold-walk precondition: …shape A keeps Suites: none, its comment kept" \
  "Suites: none  # " "$WALK_ER"
expect_contains "§scaffold-walk precondition: …and Files: lists the record" "Files: $WALK_REC/T3-evidence.md" "$WALK_ER"
expect_absent "§scaffold-walk precondition: …and no placeholder is left" "<" "$WALK_ER"
WALK_ERB="$(walk_fill_re evidence "$WALK_REC/T3-evidence.md" B)"
expect_contains "§scaffold-walk precondition: shape B carries the same run" "Re-executes: \`$WALK_RUN\`" "$WALK_ERB"
# NO `Suites:` LINE means no line that BEGINS with the label: the scaffold's `Lands-on:` comment names the
# word ("within Suites:") since wave-28 T7, so a substring read is red on a brief that has no such line
# (wave-28 T58). The positive beside it: shape A, on the same reader, has exactly one.
expect_eq "§scaffold-walk precondition: …shape A, read by the same line reader, carries one Suites: line" "1" \
  "$(printf '%s\n' "$WALK_ER" | /usr/bin/grep -c '^Suites:')"
expect_eq "§scaffold-walk precondition: …and shape B carries no line that begins Suites:" "0" \
  "$(printf '%s\n' "$WALK_ERB" | /usr/bin/grep -c '^Suites:')"
# What that negative can miss (T76): shape B still carries the word, in the Lands-on: comment, so a read
# of the word anywhere in the brief counts it and this row, which reads line starts, does not.
expect_contains "§scaffold-walk precondition: …while shape B still carries the word in a comment (what the negative can miss)" \
  "within Suites:" "$WALK_ERB"
REPO=$(walk_repo rwalk5 double)
expect_nonempty "§scaffold-walk precondition: the walk repo's .bionic holds its bound plan" \
  "$(/usr/bin/grep -rls '^rigor: double' "$REPO/.bionic")"
q_gate "$REPO" walk5 bionic:auditor "$WALK_ER"
expect_eq "§scaffold-walk double: the auditor, Suites: none beside its pytest run, is ADMITTED" "allow" "$GATE_VERDICT"
expect_eq "§scaffold-walk …its row carries the run" "\`$WALK_RUN\`" "$(roster_field "$(q_row "$REPO")" re_executes)"
expect_eq "§scaffold-walk …and its record" "$WALK_REC/T3-evidence.md" "$(roster_field "$(q_row "$REPO")" files)"
walk_start "$REPO" wq-walk5
walk_register "$REPO" "$WALK_REC/T3-evidence.md" evidence wq-walk5 old
expect_eq "§scaffold-walk …and the evidence record registers" "0" "$WALK_RC"
REPO=$(walk_repo rwalk6 double)
# walk_verdict -> the gate's verdict, and on a refusal its reason, so a red row says why.
walk_verdict() { [ "$GATE_VERDICT" = allow ] && printf allow || printf '%s: %s' "$GATE_VERDICT" "${GATE_REASON:0:240}"; }
q_gate "$REPO" walk6 bionic:auditor "$WALK_ERB"
expect_eq "§scaffold-walk double: the auditor with no Suites: line and its pytest run is ADMITTED (needs T57)" \
  "allow" "$(walk_verdict)"
expect_eq "§scaffold-walk …its row carries the run" "\`$WALK_RUN\`" "$(roster_field "$(q_row "$REPO")" re_executes)"
WALK_TRECS="$WALK_REC/T3-evidence.md, $WALK_REC/T3-adversarial.md, $WALK_REC/T3-structure.md"
REPO=$(walk_repo rwalk7 single)
q_gate "$REPO" walk7 bionic:critic "$(walk_fill_re "evidence, adversarial, structure" "$WALK_TRECS" A)"
expect_eq "§scaffold-walk single: the critic, Suites: none beside its pytest run, is ADMITTED" "allow" "$GATE_VERDICT"
expect_eq "§scaffold-walk …its row carries the run" "\`$WALK_RUN\`" "$(roster_field "$(q_row "$REPO")" re_executes)"
walk_start "$REPO" wq-walk7
for _wq in evidence adversarial structure; do
  walk_register "$REPO" "$WALK_REC/T3-${_wq}.md" "$_wq" wq-walk7
  expect_eq "§scaffold-walk …the ${_wq} record registers" "0" "$WALK_RC"
done
REPO=$(walk_repo rwalk8 single)
q_gate "$REPO" walk8 bionic:critic "$(walk_fill_re "evidence, adversarial, structure" "$WALK_TRECS" B)"
expect_eq "§scaffold-walk single: the critic with no Suites: line and its pytest run is ADMITTED (needs T57)" \
  "allow" "$(walk_verdict)"
expect_eq "§scaffold-walk …its row carries the run" "\`$WALK_RUN\`" "$(roster_field "$(q_row "$REPO")" re_executes)"

section "AC-E1.3/E1.5 — every refusal this gate makes is one line, in the shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`.
#
# WHY A WRAPPER AND NOT ONE ROW PER SITE. This gate has sixteen refusal sites behind
# three frames, and every one of them is already driven somewhere above. `run_gate` is
# wrapped here so that EVERY refusal the rest of this suite produced was checked as it
# happened — shape, line count and column budget — and the counter proves the sweep saw
# real refusals rather than counting over air.


expect_eq "E1.3 the gate refused at least ten times in this run (not counting over air)" "yes" \
  "$([ "${DP_E1_SEEN:-0}" -ge 10 ] && echo yes || echo no)"
expect_eq "E1.3 every refusal matched the criterion's shape" "" "${DP_E1_BAD_SHAPE:-}"
expect_eq "E1.3 every refusal was exactly one line" "" "${DP_E1_BAD_LINES:-}"
expect_eq "E1.3 every refusal fitted the 100-column budget" "" "${DP_E1_BAD_COLS:-}"
# THE UNCOVERED SITE, named rather than silently tolerated: `live-agents:` has no row in
# the task-12 wording table, so it still speaks in its own voice. Any OTHER refusal that
# renders no line fails here.
expect_eq "E1.3 the only refusals with no rendered line are the uncovered live-agents site" \
  "" "${DP_E1_UNNAMED:-}"

# THE TABLE'S EXACT WORDING at three sites, one per frame: the environment frame, the
# Patrol frame, and a direct arm.
REPO=$(make_repo re13b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "w-e13b")"
expect_eq "E1.3 row 48 (no deliverable) is the table's line" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"

# AC-E1.5, the pair: the user stream LEADS with the verdict line, and the knob carries the
# frame's Fix block.
#
# RE-AUTHORED FROM A LINE COUNT TO THE LINE (REQ-2, D2/ADR-030; A-orch-13/A-orch-14). This
# assertion used to read "the Fix block is NOT on the user stream", which was the 1.8.2
# reading of AC-E1.5: an `exit2` refusal rendered its one line and nothing else, so the
# absence of any detail text WAS the criterion. D2 reverses that by Chris's own call — an
# `exit2` refusal now prints its bounded violation detail under the verdict — and an absence
# pin would red at the wave head for the change it was never about. What AC-E1.5 has always
# been about is that the READER GETS THE VERDICT: one line, in the table's words, first.
# That claim holds on both sides of the flip, and it is what is pinned here.
# THE FIRST `bionic: ` LINE, not the first line and not the only line. The user stream can
# carry an advisory above the verdict — this very fixture draws `dispatch-preflight: run
# resolved by newest-plan fallback` — and under D2 it carries bounded detail below it, so
# both edges of the refusal are lines this assertion must not count.
expect_eq "E1.5 the verdict reaches the USER stream, in the table's words" \
  "bionic: dispatch refused — this brief names no deliverable (add an Expected artifact: line)" \
  "$(printf '%s\n' "$GATE_ERR" | awk '/^bionic: / { print; exit }')"
expect_contains "E1.5 …and BIONIC_WALL_VERBOSE=1 puts it back" \
  "Then retry the dispatch" "$GATE_VERR"
expect_contains "E1.5 …with the one line still in it" \
  "bionic: dispatch refused — this brief names no deliverable" "$GATE_VERR"

# ============================================================

section "§brief-lib — the contract grammar is one library (wave-20 T6; REQ-4, D4, Δ10)"
# ============================================================
#
# A VALID CONTRACT IS DEFINED ONCE (Δ10). The lift, its caps, and every check the lifted
# Files:/Suites:/Re-executes: fields feed live in payload/scripts/lib/brief.sh, so `amend` (T9)
# and `task-add` hold an amended or added contract to exactly a fresh dispatch's standard.
# Every row above this section drives the hook and is the refactor's proof that nothing moved
# in behaviour; the rows here drive the library ALONE, with no hook around it, which is how
# its other two callers will meet it. tests/cross-gate-agreement.test.sh §S13c asks the two
# doors for one verdict on the same fields.
# BRIEF_LIB, BRIEF_NOCONF: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part reads them)
BRIEF_CONF="$SANDBOX/brief-conf"; mkdir -p "$BRIEF_CONF/.bionic"
printf 'impact-command: bash stub-impact.sh\n' > "$BRIEF_CONF/.bionic/config.yaml"
BT='`'
# brief_verdict: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part calls it)

expect_eq "brief-lib the library sources alone and carries the grammar, its caps and the checker" \
  "ok 200 3" "$(bash -c '. "$1" || exit 9
    for f in sanitize lift_contract_fields dp_runs_cap dp_runs_cap_words brief_field brief_validate_fields; do
      declare -F "$f" >/dev/null || { echo "missing $f"; exit 0; }
    done
    echo "ok $DP_SUITES_MAX $DP_AUDITOR_RUNS_MAX"' _ "$BRIEF_LIB" 2>&1)"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Suites: tests/one.test.sh, tests/two.test.sh")
expect_contains "brief-lib a declared set passes clean (rc=0)" "rc=0" "$BV"
expect_absent   "brief-lib …with no finding" "finding:" "$BV"
expect_contains "brief-lib …and IS the suite set, recorded as declared" "source=declared" "$BV"
expect_contains "brief-lib …holding the declared basenames" "one.test.sh" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" 'Suites: tests/$X.test.sh')
expect_contains "brief-lib an unexpanded suite name is refused" "finding: a declared suite is not a literal name" "$BV"
expect_contains "brief-lib …and a finding answers rc=1" "rc=1" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Suites: tests/unit/foo.spec.ts")
expect_contains "brief-lib a suite the shell runner cannot run is refused" \
  "finding: Suites: names a file the shell runner cannot run" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Re-executes: ${BT}npx jest x | tee log${BT}")
expect_contains "brief-lib a run with an unquoted pipe is refused" "finding: a declared run is not a literal command" "$BV"

BV_FOUR="Re-executes: ${BT}go test ./a${BT}, ${BT}go test ./b${BT}, ${BT}go test ./c${BT}, ${BT}go test ./d${BT}"
BV=$(brief_verdict bionic:auditor "$BRIEF_NOCONF" "$BV_FOUR")
expect_contains "brief-lib an auditor's fourth run passes the auditor's cap of three" \
  "finding: the total of 4 runs exceeds the 3-run cap" "$BV"
BV=$(brief_verdict implementor "$BRIEF_NOCONF" "$BV_FOUR")
expect_contains "brief-lib …while the same four runs pass clean for a writer" "rc=0" "$BV"

BV=$(brief_verdict bionic:auditor "$BRIEF_NOCONF" "Suites: none")
expect_contains "brief-lib an auditor that waives every suite is refused" "finding: the auditor declares nothing to re-execute" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Expected duration: ~5 minutes.")
expect_contains "brief-lib a brief with no instrument is refused" \
  "finding: this brief declares no Files: and no Suites:" "$BV"

BV=$(brief_verdict implementor "$BRIEF_NOCONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib Files: alone is refused" \
  "finding: Files: alone names no suite" "$BV"

# brief_detail: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part calls it)
BV_THREE="Re-executes: ${BT}go test ./a${BT}
Re-executes: ${BT}go test ./b${BT}
Re-executes: ${BT}go test ./c${BT}"
expect_contains "brief-lib three one-command Re-executes: lines all lift (AC-2.1)" \
  "re_executes=${BT}go test ./a${BT} ${BT}go test ./b${BT} ${BT}go test ./c${BT}" \
  "$(bash -c '. "$1" || exit 9; lift_contract_fields "$3" "$2"' _ "$BRIEF_LIB" "$BRIEF_NOCONF" "$BV_THREE")"
REPO=$(make_repo r22t3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: run three things.
Expected artifact: .bionic/docs/record/w22t3.md
${BV_THREE}" "w22t3-three")"
expect_status "brief-lib …and a full dispatch admits the brief with three runs (AC-2.1)" "0" "$GATE_ST"
expect_status "brief-lib …no refusal verdict on either channel" "allow" "$GATE_VERDICT"
expect_eq "brief-lib …the roster row carries all three runs" \
  "${BT}go test ./a${BT} ${BT}go test ./b${BT} ${BT}go test ./c${BT}" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" re_executes)"
BV_FOURL="${BV_THREE}
Re-executes: ${BT}go test ./d${BT}"
BV=$(brief_verdict bionic:auditor "$BRIEF_NOCONF" "$BV_FOURL")
expect_contains "brief-lib four one-command lines meet the cap over the union (AC-2.2)" \
  "finding: the total of 4 runs exceeds the 3-run cap" "$BV"
expect_contains "brief-lib …naming the fourth run" "${BT}go test ./d${BT}" \
  "$(brief_detail bionic:auditor "$BRIEF_NOCONF" "$BV_FOURL")"
BV_CAPD="$(brief_detail bionic:auditor "$BRIEF_NOCONF" "$BV_FOURL")"
expect_contains "brief-lib …the refusal speaks of the Re-executes: lines (the union), not a span" \
  "The Re-executes: lines name more runs than the 3-run cap" "$BV_CAPD"
expect_absent "brief-lib …never 'one line' (four one-run lines are the case it refuses)" "one line" "$BV_CAPD"
expect_absent "brief-lib …nor the old singular 'span named'" "span named" "$BV_CAPD"
BV=$(brief_verdict bionic:auditor "$BRIEF_NOCONF" "Re-executes: ${BT}go test ./a${BT}
Re-executes: ${BT}go test ./a${BT}, ${BT}go test ./b${BT}")
expect_absent "brief-lib …a run repeated across lines counts once" "finding:" "$BV"
# wave-22 T10 (review 1 / critic C2): a `Re-executes:` line inside a ``` fence, or indented four
# spaces (a Markdown code block), is an EXAMPLE, not a declaration — it never joins the union.
lift_runs() { bash -c '. "$1" || exit 9; lift_contract_fields "$3" "$2" | grep "^re_executes="' _ "$BRIEF_LIB" "${2:-implementor}" "$1"; }
FENCE3='```'
expect_eq "brief-lib a fenced Re-executes: example after the real line lifts only the real run (C2 case A)" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "Re-executes: ${BT}npm test -- a${BT}

For reference, a brief looks like:
${FENCE3}
Re-executes: ${BT}rm -rf build && npm run e2e${BT}
${FENCE3}
")"
expect_eq "brief-lib …a fenced example BEFORE the real line is not the lift either" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "${FENCE3}
Re-executes: ${BT}rm -rf build${BT}
${FENCE3}
Re-executes: ${BT}npm test -- a${BT}")"
expect_eq "brief-lib …an indented (four-space) example lifts only the real run" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "Re-executes: ${BT}npm test -- a${BT}

An example:

    Re-executes: ${BT}rm -rf build${BT}
")"
expect_eq "brief-lib …a mid-sentence quote stays un-lifted (C2 case B)" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "Re-executes: ${BT}npm test -- a${BT}
Note: never write Re-executes: ${BT}npm test${BT} without a path.")"
expect_eq "brief-lib …a real second line after a closed fence still unions" \
  "re_executes=${BT}go test ./a${BT} ${BT}go test ./b${BT}" \
  "$(lift_runs "Re-executes: ${BT}go test ./a${BT}
${FENCE3}
Re-executes: ${BT}rm -rf x${BT}
${FENCE3}
Re-executes: ${BT}go test ./b${BT}")"
# wave-22 T13 (critic-3598752 I2, I2b): a `~~~` fence is a fence too, and a label whose EVERY hit
# sits in a code block falls back to its first hit — an indented, tabbed or after-unbalanced-fence
# real line is still the declaration, as it was before the union (cases D, E, H).
FENCE4='~~~'
expect_eq "brief-lib a ~~~-fenced Re-executes: example after the real line lifts only the real run (I2b case B)" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "Re-executes: ${BT}npm test -- a${BT}

${FENCE4}
Re-executes: ${BT}rm -rf build${BT}
${FENCE4}")"
expect_eq "brief-lib …a ${FENCE3} line inside a ~~~ fence does not close it" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "Re-executes: ${BT}npm test -- a${BT}

${FENCE4}
${FENCE3}
Re-executes: ${BT}rm -rf build${BT}
${FENCE4}")"
expect_eq "brief-lib an unbalanced ${FENCE3} line before the only real line still lifts it (I2 case D)" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "${FENCE3}
some example
Re-executes: ${BT}npm test -- a${BT}")"
expect_eq "brief-lib a contract indented four spaces still lifts its only Re-executes: line (I2 case E)" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "Task:
    Files: hooks/a.sh
    Suites: a.test.sh
    Re-executes: ${BT}npm test -- a${BT}")"
expect_eq "brief-lib a tab-indented only Re-executes: line still lifts (I2 case H)" \
  "re_executes=${BT}npm test -- a${BT}" \
  "$(lift_runs "	Re-executes: ${BT}npm test -- a${BT}")"
# wave-22 T15 (critic-f9c2c8d N1; auditor finding; ruling A-orch-13): a label whose every hit sits
# in a code block, or a brief whose fences end unbalanced, lifts the UNION of ALL its hits. A
# first-hit fallback silently dropped every run after the first. Accepted: a fenced example lifts
# beside the real runs in those malformed shapes (visible on the roster row; a dropped run is not).
expect_eq "brief-lib N1 case M: unbalanced ${FENCE3}, real line, fenced example — the real run is never dropped" \
  "re_executes=${BT}npm test -- a${BT} ${BT}npm test -- example${BT}" \
  "$(lift_runs "${FENCE3}
Re-executes: ${BT}npm test -- a${BT}

${FENCE3}
Re-executes: ${BT}npm test -- example${BT}
${FENCE3}")"
expect_eq "brief-lib P1: an indented two-run contract lifts both runs" \
  "re_executes=${BT}go test ./a${BT} ${BT}go test ./b${BT}" \
  "$(lift_runs "Task:
    Re-executes: ${BT}go test ./a${BT}
    Re-executes: ${BT}go test ./b${BT}")"
expect_eq "brief-lib P2: an unclosed ${FENCE3} then two real lines lifts both runs" \
  "re_executes=${BT}go test ./a${BT} ${BT}go test ./b${BT}" \
  "$(lift_runs "${FENCE3}
Re-executes: ${BT}go test ./a${BT}
Re-executes: ${BT}go test ./b${BT}")"
expect_eq "brief-lib P3: real line, an unclosed ${FENCE3}, real line lifts both runs" \
  "re_executes=${BT}go test ./a${BT} ${BT}go test ./b${BT}" \
  "$(lift_runs "Re-executes: ${BT}go test ./a${BT}
${FENCE3}
Re-executes: ${BT}go test ./b${BT}")"
_p5=$(bash -c '. "$1" || exit 9; lift_contract_fields "$3" "$2"' _ "$BRIEF_LIB" auditor "Task:
    Re-executes: ${BT}go test ./a${BT}
    Re-executes: ${BT}go test ./b${BT}
    Re-executes: ${BT}go test ./c${BT}
    Re-executes: ${BT}go test ./d${BT}")
expect_contains "brief-lib P5: a four-run indented auditor contract keeps three runs" \
  "re_executes=${BT}go test ./a${BT} ${BT}go test ./b${BT} ${BT}go test ./c${BT}" "$_p5"
expect_contains "brief-lib …and the cap finding fires, naming ./d as dropped" "go test ./d" "$(printf '%s\n' "$_p5" | grep '^re_executes_dropped=')"
# PINS of the accepted trade (A-T15.2), not goals: both read as they did at 12574e2.
expect_eq "brief-lib PIN (case K): a brief whose only Re-executes: line is a balanced fenced example lifts it" \
  "re_executes=${BT}npm test -- example${BT}" \
  "$(lift_runs "${FENCE3}
Re-executes: ${BT}npm test -- example${BT}
${FENCE3}")"
expect_eq "brief-lib PIN (case L): a fenced example before a wholly indented real contract lifts both, the real run is not dropped" \
  "re_executes=${BT}npm test -- example${BT} ${BT}npm test -- a${BT}" \
  "$(lift_runs "${FENCE3}
Re-executes: ${BT}npm test -- example${BT}
${FENCE3}
    Re-executes: ${BT}npm test -- a${BT}")"
BV=$(brief_detail implementor "$BRIEF_NOCONF" "Files: payload/scripts/lib/widget.sh
Re-executes: ${BT}go test ./a${BT}")
expect_contains "brief-lib Files: + Re-executes: and no Suites: is still refused (AC-3.1)" "rc=1" "$BV"
FIRSTFIX=$(printf '%s\n' "$BV" | awk '/^Fix:/{f=1} f{print} /^$/{if(f)exit}')
expect_contains "brief-lib …the first Fix: block names Suites: none" "Suites: none" "$FIRSTFIX"
expect_contains "brief-lib …beside the brief's Re-executes:" "Re-executes:" "$FIRSTFIX"
expect_contains "brief-lib …the closed-set remedy follows" "Suites: tests/one.test.sh, tests/two.test.sh" "$BV"
expect_absent "brief-lib …and no config key to set" "impact-command" "$BV"
expect_contains "brief-lib …and the SHORT fix names Suites: none beside Re-executes: (C3)" \
  "fix: Suites: none beside Re-executes:" "$BV"
BV=$(brief_detail implementor "$BRIEF_NOCONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib …no runs declared: the short fix names the two labels" \
  "fix: add Suites: or Re-executes:" "$BV"
IFS= read -r -d '' BV_PIN <<'PIN_EOF' || true
finding: Files: alone names no suite
fix: add Suites: or Re-executes:
`Files:` names the paths this task will touch, not the suites it may run; the brief
names those itself.

Fix: name the closed set in the brief —
    Suites: tests/one.test.sh, tests/two.test.sh

Where the tests are not shell suites, name the commands under Re-executes: and waive
the suite set beside them —
    Suites: none

Then retry the dispatch.
rc=1
PIN_EOF
BV_PIN=${BV_PIN%$'\n'}
expect_eq "brief-lib the Files-alone refusal, verbatim (AC-3.2; wave-31 T2)" "$BV_PIN" "$BV"
# wave-22 T10 (critic C3): on a several-fault brief the detail block is dropped and only the
# short fix reaches the author — so the short fix must be the one that applies.
REPO=$(make_repo r22t10c3 yes)
write_attestation "$REPO" "$SID_A"
rm -f "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Files: payload/scripts/lib/widget.sh
Re-executes: ${BT}npx jest --testPathPatterns alpha${BT}" "w22t10c3")"
expect_eq "brief-lib a missing deliverable AND Files: alone is refused (C3)" "deny" "$GATE_VERDICT"
expect_contains "brief-lib …the Files-alone finding's short fix names Suites: none beside Re-executes:" \
  "Files: alone names no suite (Suites: none beside Re-executes:)" "$GATE_REASON"
expect_absent "brief-lib …and not the short fix for a brief with no runs" \
  "(add Suites: or Re-executes:)" "$GATE_REASON"
# wave-22 T13 (critic-3598752 I1): the ONE-FAULT path. With runs declared and nothing else wrong,
# the Files-alone finding is the capped user line itself, so its short fix must fit: at 3598752 the
# line was 102 columns and refuse.sh refused its own call (exit 2) instead of the brief.
REPO=$(make_repo r22t13one yes)
write_attestation "$REPO" "$SID_A"
rm -f "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: $REPO/out.md
Expected duration: ~15 minutes.
Progress artifact: .bionic/tmp/p.md
Cadence: 15 min
Files: payload/scripts/lib/widget.sh
Re-executes: ${BT}npx jest --testPathPatterns alpha${BT}" "w22t13one")"
expect_eq "brief-lib a one-fault Files: + Re-executes: brief is DENIED, not a self-refusal (I1)" \
  "deny" "$GATE_VERDICT"
expect_eq "brief-lib …its user line is the Files-alone refusal, short fix and all" \
  "bionic: dispatch refused — Files: alone names no suite (Suites: none beside Re-executes:)" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep '^bionic: ')"
expect_true "brief-lib …within 100 columns" \
  test "$(bionic_cols "bionic: dispatch refused — Files: alone names no suite (Suites: none beside Re-executes:)")" -le 100
# THE DRIVER SWEEP SEES IT TOO. The AC-E1.3 readout runs before this section, so the sweep's
# self-refusal flag (run_gate) is read here for every drive up to this one.
expect_absent "brief-lib …and the driver sweep flagged no refuse.sh self-refusal" \
  "refuse-call refused" "${DP_E1_BAD_SHAPE:-}"
# wave-22 T13 (critic-3598752 I2, dp3.sh/armind.sh): the REAL gate on a brief whose whole contract is
# indented four spaces. The gate admits it, the row it journals carries the declared run, and the
# budget arm admits that run once the recorder identifies the agent. At 3598752 the row carried
# `re_executes=` empty and the arm refused the run the brief declared.
REPO=$(make_repo r22t13ind yes)
write_attestation "$REPO" "$SID_A"
rm -f "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it. The contract:

    Expected artifact: $REPO/out.md
    Expected duration: ~15 minutes.
    Progress artifact: .bionic/tmp/p.md
    Cadence: 15 min
    Files: payload/scripts/lib/widget.sh
    Suites: none
    Re-executes: ${BT}npx jest --testPathPatterns alpha${BT}" "w22t13ind")"
expect_eq "brief-lib an indented contract with Suites: none is admitted (I2 real gate)" "allow" "$GATE_VERDICT"
T13_ROW=$(grep -F '|name=w22t13ind|' "$(roster_path "$REPO" "$SID_A")" | tail -1)
expect_eq "brief-lib …its roster row carries the declared run" \
  "${BT}npx jest --testPathPatterns alpha${BT}" "$(roster_field "$T13_ROW" re_executes)"
T13_ID="aw13-4000000000000001"
printf '{}\n' > "$REPO/t13-transcript.jsonl"
jq -n --arg s "$SID_A" --arg c "$REPO" --arg a "$T13_ID" \
  '{session_id:$s, transcript_path:($c+"/t13-transcript.jsonl"), cwd:$c, agent_id:$a,
    agent_type:"w22t13ind", hook_event_name:"SubagentStart"}' \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "${BIONIC_HOOKS_DIR}/execution-recorder.sh" >/dev/null 2>&1
expect_contains "brief-lib …the recorder identifies it, carrying the run forward" \
  "${BT}npx jest --testPathPatterns alpha${BT}" \
  "$(roster_field "$(grep -F "|agent_id=$T13_ID|" "$(roster_path "$REPO" "$SID_A")" | tail -1)" re_executes)"
t13_arm() {  # <command> -> the budget arm's exit status for the identified agent
  jq -n --arg s "$SID_A" --arg c "$REPO" --arg m "$1" --arg a "$T13_ID" \
    '{session_id:$s, transcript_path:($c+"/t13-transcript.jsonl"), cwd:$c,
      permission_mode:"bypassPermissions", hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$m}, tool_use_id:"toolu_t13", agent_id:$a, agent_type:"bionic:implementor"}' \
    | env -u CLAUDE_PROJECT_DIR HOME="$REPO" CLAUDE_CODE_SESSION_ID="$SID_A" \
        bash "${BIONIC_HOOKS_DIR}/bash-walls.sh" >/dev/null 2>&1
  echo "$?"
}
expect_eq "brief-lib …and the budget arm ADMITS the declared run" "0" "$(t13_arm 'npx jest --testPathPatterns alpha')"
expect_eq "brief-lib …while still refusing an undeclared one (the arm is live)" "2" \
  "$(t13_arm 'npx jest --testPathPatterns undeclared')"

# A STALE impact-command: LINE DERIVES NOTHING (wave-31 T2, REQ-4 AC-4.2). BRIEF_CONF still
# carries the pre-1.14.1 key, naming a stub that would answer two suites and leaves a mark when
# it runs. The library reads the brief alone: Files: is refused as it is with no config, and a
# declared set is the set.
printf '#!/bin/bash\n: > "$(dirname "$0")/stub-ran"\nprintf "beta.test.sh\\tpath-ref\\n"\n' > "$BRIEF_CONF/stub-impact.sh"
( cd "$BRIEF_CONF" && bash stub-impact.sh >/dev/null )
expect_status "brief-lib precondition: the stale stub leaves its mark when run" "0" \
  "$([ -f "$BRIEF_CONF/stub-ran" ] && echo 0 || echo 1)"
rm -f "$BRIEF_CONF/stub-ran"
BV=$(brief_verdict implementor "$BRIEF_CONF" "Files: payload/scripts/lib/widget.sh")
expect_contains "brief-lib Files: beside a stale impact-command: line is refused all the same" \
  "finding: Files: alone names no suite" "$BV"
expect_contains "brief-lib …with no suite set" "suites=
" "$BV"
expect_status "brief-lib …and the stale command never ran" "1" \
  "$([ -f "$BRIEF_CONF/stub-ran" ] && echo 0 || echo 1)"
BV=$(brief_verdict implementor "$BRIEF_CONF" "Files: payload/scripts/lib/widget.sh
Suites: tests/one.test.sh")
expect_contains "brief-lib …while a declared set beside it is the set" "suites=one.test.sh" "$BV"
expect_contains "brief-lib …recorded as declared" "source=declared" "$BV"
expect_contains "brief-lib …and passes clean" "rc=0" "$BV"

expect_eq "brief-lib brief_field hands back the Files: set as the row stores it" \
  "payload/a.sh,payload/b.sh" \
  "$(bash -c '. "$1" || exit 9; brief_field "$(lift_contract_fields "Files: payload/a.sh, payload/b.sh")" files' _ "$BRIEF_LIB" 2>&1)"

# ============================================================================

section "§ADV — the brief body is read for a run or a write the contract never declared (wave-24 T14; REQ-8, D13)"
# ============================================================================
#
# Nothing used to read the body: `lift_contract_fields` takes labelled lines only, so a brief
# that says "run bash tests/foo.test.sh" under `Suites: tests/widget.test.sh` was admitted and
# the agent was refused at its first command, minutes later. D13 makes the dispatch say so
# while the author is still holding the brief — an ADVISORY (a WARN on the pass path, with the
# `amend` line that would declare the run), never a refusal: the research corpus had 0 true
# positives in 202 briefs, so the exit code is not the advisory's to change (AC-8.4).
#
# fails-when: the undeclared run is not named with its declaring line, or the advisory changes
# the verdict, or the declared suite beside it is advised about as well.

# adv_brief: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part calls it)

# adv_ctx: hoisted to tests/dispatch-preflight-4.prelude.sh (a later part calls it)
adv_objects() { printf '%s' "$GATE_OUT" | jq -s 'length' 2>/dev/null; }

REPO=$(make_repo advbase yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Scope constraint: touch only payload/scripts/lib/widget.sh.')" "w99-adv")"
ADV_BASE_VERDICT="$GATE_VERDICT"; ADV_BASE_ST="$GATE_ST"; ADV_BASE_OUT="$GATE_OUT"
expect_eq "ADV the brief with no body run is admitted" "allow" "$ADV_BASE_VERDICT"
expect_empty "ADV …and prints nothing on stdout" "$GATE_OUT"
expect_absent "ADV …nor on stderr" "the brief body" "$GATE_ERR"

REPO=$(make_repo advrun yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'When the seam is in, run `bash tests/foo.test.sh` and report the count.
Then `bash tests/widget.test.sh` for the paired suite.
bash tests/bar.test.sh
cd /x/tree && bash tests/baz.test.sh')" "w99-adv")"
expect_eq "ADV an undeclared body run is still ADMITTED (AC-8.4)" "$ADV_BASE_VERDICT" "$GATE_VERDICT"
expect_eq "ADV …with the exit status the no-advisory brief had (AC-8.4)" "$ADV_BASE_ST" "$GATE_ST"
expect_eq "ADV …stdout is ONE parseable JSON object" "1" "$(adv_objects)"
expect_eq "ADV …on the model's channel, a PreToolUse additionalContext" "PreToolUse" \
  "$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)"
expect_eq "ADV …that carries no verdict (no permissionDecision)" "" \
  "$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)"
expect_absent "ADV …and the advisory is not also on stderr" "the brief body" "$GATE_ERR"
ADV_CTX=$(adv_ctx)
expect_contains "ADV the advisory names the undeclared suite (AC-8.1)" "foo.test.sh" "$ADV_CTX"
expect_contains "ADV …and the declaring line" 'run `bash tests/foo.test.sh` and report the count' "$ADV_CTX"
expect_contains "ADV …as the amend line that declares it" "amend w99-adv --suites+ foo.test.sh" "$ADV_CTX"
expect_contains "ADV …a bare command line is read the same way" "amend w99-adv --suites+ bar.test.sh" "$ADV_CTX"
expect_contains "ADV …and one behind a cd prefix" "amend w99-adv --suites+ baz.test.sh" "$ADV_CTX"
expect_absent "ADV …while the declared suite is not advised about" "--suites+ widget.test.sh" "$ADV_CTX"
expect_status "ADV …and the launch was journalled as usual" \
  "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ============================================================================

section "§ADV-quiet — the same text in an excluded region is not an advisory (AC-8.2)"
# ============================================================================
# One brief, one positive control: `pos.test.sh` sits on a plain line and MUST be advised, so an
# empty stderr cannot be a dead reader; every other name sits in a region the predicate skips.
REPO=$(make_repo advquiet yes)
write_attestation "$REPO" "$SID_A"
ADVQ_BODY='Read first: run `bash tests/rf.test.sh` to see the baseline
  and `bash tests/rf2.test.sh` on the line after it.
Never run `bash tests/nev.test.sh` here.
Please do not run bash tests/dn.test.sh either.
Example only, e.g. `bash tests/eg.test.sh`.

```
bash tests/fence.test.sh
```

    bash tests/ind.test.sh

Run `bash tests/pos.test.sh` last.'
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief "$ADVQ_BODY")" "w99-advq")"
ADV_CTX=$(adv_ctx)
expect_eq "ADV-quiet the brief is admitted" "allow" "$GATE_VERDICT"
expect_eq "ADV-quiet …with one parseable object on stdout" "1" "$(adv_objects)"
expect_contains "ADV-quiet the control line IS advised (the reader works)" "--suites+ pos.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet Read first: is not advised" "rf.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet …nor its continuation line" "rf2.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet a never-line is not advised" "nev.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet a do-not line is not advised" "dn.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet an e.g. line is not advised" "eg.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet a fenced block is not advised" "fence.test.sh" "$ADV_CTX"
expect_absent "ADV-quiet a 4-space-indented block is not advised" "ind.test.sh" "$ADV_CTX"

# ============================================================================

section "§ADV-files — an imperative edit of a path outside Files: is advised (AC-8.3)"
# ============================================================================
# Same shape: `other.sh` is the positive control, everything else is a shape the strict
# predicate leaves alone (declared, record file, no path object, a never-line, a mention).
REPO=$(make_repo advfiles yes)
write_attestation "$REPO" "$SID_A"
ADVF_BODY='Edit payload/scripts/lib/other.sh to add the seam.
Update payload/scripts/lib/widget.sh with the new field.
Update .bionic/docs/record/w99/notes.md when you finish.
Fix the failing assertion in the paired suite.
Never edit payload/scripts/lib/nev.sh from here.
The old shape lives in payload/scripts/lib/mention.sh and stays as it is.
Rewrite the `payload/scripts/lib/quoted.sh` helper if it blocks you.

```
Modify payload/scripts/lib/fence.sh
```'
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief "$ADVF_BODY")" "w99-advf")"
ADV_CTX=$(adv_ctx)
expect_eq "ADV-files the brief is admitted" "allow" "$GATE_VERDICT"
expect_eq "ADV-files …with ONE parseable object on stdout, the advisory inside its additionalContext" "1" "$(adv_objects)"
expect_eq "ADV-files …with exit 0 (AC-8.4)" "0" "$GATE_ST"
expect_contains "ADV-files an edit outside Files: is advised, with its amend line" \
  "amend w99-advf --files+ payload/scripts/lib/other.sh" "$ADV_CTX"
expect_contains "ADV-files …naming the declaring line" "Edit payload/scripts/lib/other.sh to add the seam" "$ADV_CTX"
expect_contains "ADV-files a backticked object is read" "--files+ payload/scripts/lib/quoted.sh" "$ADV_CTX"
expect_absent "ADV-files a path inside Files: is not advised" "--files+ payload/scripts/lib/widget.sh" "$ADV_CTX"
expect_absent "ADV-files a record path is not advised" "notes.md" "$ADV_CTX"
expect_absent "ADV-files a never-line is not advised" "nev.sh" "$ADV_CTX"
expect_absent "ADV-files a plain mention is not advised" "mention.sh" "$ADV_CTX"
expect_absent "ADV-files a fenced block is not advised" "fence.sh" "$ADV_CTX"
expect_absent "ADV-files an edit with no path object is not advised" "failing assertion" "$ADV_CTX"

# A BRACKET IN A Files: ENTRY IS A PLAIN CHARACTER (wave-26 T5; review 7 F4). The advisory
# program built its glob with `[` unescaped, so `tests/[ab*.sh` aborted awk ("nonterminated
# character class") and every advisory for the brief was dropped in silence.
REPO=$(make_repo advbracket yes)
write_attestation "$REPO" "$SID_A"
ADVB_BRIEF="$(adv_brief 'Edit payload/scripts/lib/other.sh to add the seam.' \
  | sed 's|^Files: payload/scripts/lib/widget.sh$|Files: tests/[ab*.sh, payload/scripts/lib/widget.sh|')"
expect_contains "ADV-files bracket precondition: the brief declares the bracketed entry" \
  "Files: tests/[ab*.sh, payload/scripts/lib/widget.sh" "$ADVB_BRIEF"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$ADVB_BRIEF" "w99-advb")"
expect_eq "ADV-files a brief whose Files: entry holds a bracket is admitted" "allow" "$GATE_VERDICT"
expect_contains "ADV-files …and its edit outside Files: is still advised" \
  "amend w99-advb --files+ payload/scripts/lib/other.sh" "$(adv_ctx)"

# ================================== §RO / §TR: THE ROLE DECIDES WHAT A ROW COSTS
# (wave-24 T10; REQ-7 AC-7.1, AC-7.2; D11, research R4 §1)
#
# A read-only role writes nothing, so it holds no WRITER slot, and an incoming read-only
# dispatch asks for none (no +1). A `bionic:test-runner` used to hold a SUITE slot, claim or
# no claim; wave-26 T8 (D8) removed the hand-out suites ceiling, and §TR and §READONLY-FREE
# below prove that.

section "§RO — a read-only role leaves the writer count and asks for no slot (AC-7.1)"

ro_budget_repo() {  # <name> <budget line> -> repo with a plan, an attestation and that budget
  local r; r=$(make_repo "$1" yes)
  write_attestation "$r" "$SID_A"
  s22_set_budget "$r" "$2"
  printf '%s' "$r"
}
RO_NONE="$SANDBOX/.ro-none.jsonl"
mk_transcript "$RO_NONE" none

# ro1 — a read-only dispatch at open == writers is ADMITTED; the paired control is a writer.
REPO=$(ro_budget_repo ro1 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro1-r" "claude-sonnet-5" "$RO_NONE" "bionic:researcher")"
expect_eq "ro1 one writer open against writers=1 → a researcher dispatch is ADMITTED (no +1)" "allow" "$GATE_VERDICT"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro1-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "ro1c …and the same roster REFUSES a writer (the control)" "deny" "$GATE_VERDICT"
expect_contains "ro1c …at the writer count" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# ro2 — a read-only ROW holds no writer slot: a writer is admitted past it, on a dark panel and
# on a fresh one that lists it.
REPO=$(ro_budget_repo ro2 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "R-ONE" "" "bionic:researcher"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro2-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "ro2 one researcher open against writers=1, dark panel → a writer is ADMITTED" "allow" "$GATE_VERDICT"
RO_LIVE="$SANDBOX/.ro-live.jsonl"
mk_transcript "$RO_LIVE" fresh R-ONE
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro2-w2" "claude-sonnet-5" "$RO_LIVE" "implementor")"
expect_eq "ro2b …and with the researcher LISTED on a fresh panel" "allow" "$GATE_VERDICT"

# ro3 — the exclusion is per row: a researcher and a writer open, writers=1, a writer is
# refused and the count it names is the writer's alone.
REPO=$(ro_budget_repo ro3 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "R-ONE" "" "bionic:researcher"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro3-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "ro3 researcher + writer open against writers=1 → a writer is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "ro3 …open counts the writer and not the researcher" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# ro4 — the exclusion does not leak: a bare `researcher`, an unknown type and an empty type are
# writers (role_is_readonly is an allow-list), so each holds the slot.
_ro=0
for _t in researcher acme:helper general-purpose ""; do
  _ro=$((_ro + 1))
  REPO=$(ro_budget_repo "ro4-$_ro" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
  s22_roster_row "$REPO" "$SID_A" "X-ONE" "" "$_t"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro4-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
  expect_eq "ro4 an open row of type '${_t:-<empty>}' still holds a writer slot → a writer is REFUSED" "deny" "$GATE_VERDICT"
  expect_contains "ro4 …counted open=1" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"
done

# ro5 — a read-only row that declared a claim holds nothing at hand-out. Until wave-26 T8 (D8)
# it held a SUITE slot and a writer behind it was refused on `suites:`.
REPO=$(ro_budget_repo ro5 "writers=9 suites=1 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "R-ONE" "bash tests/run.sh" "bionic:researcher"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro5-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "ro5 a claim-declaring researcher open against suites=1 → a writer is ADMITTED" "allow" "$GATE_VERDICT"

# ro6 — a read-only row CLOSED by an ack on a dark panel gives nothing back it never held:
# the writer count stays what the open writers say.
REPO=$(ro_budget_repo ro6 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "R-ONE" "" "bionic:researcher"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_ack "$REPO" "$SID_A" "R-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "ro6-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "ro6 an acked researcher and an open writer against writers=1 → a writer is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "ro6 …open=1, not 0 (the ack did not subtract a slot the researcher never held)" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

section "§TR — a test-runner row holds no slot at hand-out (AC-7.2, superseded by wave-26 D8)"

# Until wave-26 a `bionic:test-runner` row held a SUITE slot, claim or no claim (wave-24 T10,
# AC-7.2), for the hand-out suites ceiling. That ceiling is gone — a suite run books a
# machine-wide place as it starts — so the old refusal's fixture is admitted now.
REPO=$(ro_budget_repo tr1 "writers=9 suites=2 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "T-ONE" "" "bionic:test-runner"
s22_roster_row "$REPO" "$SID_A" "T-TWO" "bash tests/run.sh" "bionic:test-runner"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "tr1-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "tr1 two test-runners open against suites=2 → a writer is ADMITTED" "allow" "$GATE_VERDICT"

section "§READONLY-FREE — hand-out counts no suites; a read-only dispatch asks for no worktree (wave-26 T8, AC-6.3)"
# fails-when: the suites arm still adds one per dispatch, or the worktrees arm adds one for a
# read-only role (the spec's Eval design row for AC-6.3).

# rf1 — as many claimed rows open as the old suite budget, as many trees standing as the tree
# budget, and a researcher dispatches. The writer ceiling still binds: on the same roster a
# writer past it is refused, and that refusal names the writers and no suite count.
REPO=$(ro_budget_repo rf1 "writers=2 suites=2 worktrees=2 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "W-ONE" "bash tests/widget.test.sh"
s22_roster_row "$REPO" "$SID_A" "W-TWO" "bash tests/gadget.test.sh"
s22_fake_tree "$REPO" "one"
s22_fake_tree "$REPO" "two"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "rf1-r" "claude-sonnet-5" "$RO_NONE" "bionic:researcher")"
expect_eq "rf1 two claimed rows open at suites=2 and two trees at worktrees=2 → a researcher is ADMITTED" \
  "allow" "$GATE_VERDICT"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "rf1-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "rf1w …and the same roster still REFUSES a writer past the writer ceiling" "deny" "$GATE_VERDICT"
expect_contains "rf1w …naming the writer count" "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_absent "rf1w …and no suite count" "suites:" "$GATE_VERR"

# rf2 — a writer at the old suite ceiling: one claimed row open against suites=1.
REPO=$(ro_budget_repo rf2 "writers=9 suites=1 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "W-ONE" "bash tests/run.sh"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "rf2-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "rf2 one claimed row open against suites=1 → a writer is ADMITTED" "allow" "$GATE_VERDICT"

# rf3 — the tree budget full: a read-only dispatch is handed no tree, so it passes. A writer
# passes too since wave-28 T9 (D15) removed the worktrees ceiling: free disk is asked where a tree
# is made (spawn-worktree.sh create), not counted here.
REPO=$(ro_budget_repo rf3 "writers=9 suites=9 worktrees=1 test_jobs=4 source=user")
s22_fake_tree "$REPO" "one"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "rf3-r" "claude-sonnet-5" "$RO_NONE" "bionic:researcher")"
expect_eq "rf3 one tree standing at worktrees=1 → a researcher is ADMITTED" "allow" "$GATE_VERDICT"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "rf3-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "rf3w …and a writer on the same line is ADMITTED: no worktrees ceiling (wave-28 T9)" "allow" "$GATE_VERDICT"

# ================================== §WHY: A REFUSAL SAYS HOW TO GET PAST IT
# (wave-24 T13; REQ-6 AC-6.7; D10. Chris 2026-10-03: "Why can't it be obvious from the outset
# how to invoke them properly?")
#
# fails-when: the writer-budget refusal names no open row, or a complete brief is shown the
# blank scaffold.

section "§WHY — the writer budget names its rows, a complete brief sees no scaffold (AC-6.7)"

# why1 — the writer-budget refusal lists the open rows it COUNTED, each with the command that
# closes it. The count is `budget_open_writers`, so a read-only row it did not count is not
# listed: the positive and the negative read the same reason.
REPO=$(ro_budget_repo why1 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "R-ONE" "" "bionic:researcher"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "why1-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "why1 one writer and one researcher open against writers=1 → REFUSED" "deny" "$GATE_VERDICT"
WHY1_LINE="$(printf '%s\n' "$GATE_REASON" | /usr/bin/grep -F 'W-ONE' | /usr/bin/grep -m1 -F 'session-sweeper.sh ack' || true)"
expect_true "why1 …the reason lists the open writer row with the command that closes it" test -n "$WHY1_LINE"
expect_contains "why1 …the command is the ack verb on that name" "session-sweeper.sh ack 'W-ONE'" "$WHY1_LINE"
WHY1_ROOT="$(printf '%s\n' "$WHY1_LINE" | sed -n 's/.*bash \(.*\)\/session-sweeper\.sh ack .*/\1/p')"
expect_true "why1 …rooted at the real hooks directory" test -f "$WHY1_ROOT/session-sweeper.sh"
expect_absent "why1 …and never the read-only row it did not count" "R-ONE" "$GATE_REASON"
expect_absent "why1 …and no placeholder root anywhere in the reason" "<plugin-root>" "$GATE_REASON"

# why4 — AT TASK SCALE THE CAP IS THE PROFILE'S (wave-38 T16; D25, AC-5.1). A task-scale plan
# with no person's `parallel-budget:` line holds three writers, the task row's writers cell
# (payload/scripts/lib/scale.sh): the fourth is refused by the same wall, which lists the rows it
# counted and says whose cap it is. Its own Patrol stamp is removed, since a task-scale run arms
# none; a person's line still overrides the cell.
REPO=$(make_repo why4 yes)
write_attestation "$REPO" "$SID_A"
sed 's/^scale: wave$/scale: task/' "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" > "$REPO/.why4.tmp" \
  && mv "$REPO/.why4.tmp" "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
rm -f "$REPO/.bionic/tmp/patrol-$SID_A.state"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
s22_roster_row "$REPO" "$SID_A" "W-THREE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "why4-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "why4 three writers open on a task-scale plan with no cap line → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "why4 …at the task row's cap" "writers: budget=3 open=3 with-this-dispatch=4" "$GATE_VERR"
expect_contains "why4 …naming the profile as the cap's source" "the task scale's writer cap" "$GATE_VERR"
expect_contains "why4 …and listing a row it counted with its closing command" "session-sweeper.sh ack 'W-THREE'" "$GATE_REASON"
s22_set_budget "$REPO" "writers=4 source=user"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "why4-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "why4o …a person's writers=4 line overrides the cell → ADMITTED" "allow" "$GATE_VERDICT"

# why3 — a several-fault refusal whose brief already carries every scaffold line shows no
# scaffold: it would tell the author to add nothing. Two faults on a complete brief: the writer
# budget and the name in flight. The control is the same two faults on a brief missing one
# line, which still carries the marked scaffold.
REPO=$(ro_budget_repo why3 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "W-ONE" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "why3 two faults on a complete brief → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "why3 …the reason carries the second fault's line" "that name is in flight" "$GATE_REASON"
expect_absent "why3 …and no blank scaffold line" "Expected duration: <N> minutes" "$GATE_REASON"
expect_absent "why3 …and no <ADD> mark" "<ADD>" "$GATE_REASON"
WHY3_PARTIAL="$(printf '%s\n' "$BRIEF_FULL" | /usr/bin/grep -v '^Expected duration:')"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$WHY3_PARTIAL" "W-ONE" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "why3c the same faults on a brief missing a line → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "why3c …and the scaffold marks the line it lacks" "Expected duration: <N> minutes <ADD>" "$GATE_REASON"


# ============================================================================

section "§DONE-lift — the brief's Done marker is lifted to the roster as done= (wave-24 T9; REQ-4 AC-4.8, D3)"
# ============================================================================
#
# The landing verdict reads `done=` as one of the completion signals (hooks/session-sweeper.sh
# `row_said`). The lift carries `Done marker:` at line start; a slot or a prose mention declares
# nothing.
# fails-when: the label does not lift, or a scaffold slot or a mid-line mention lifts as a marker.
lift_done() { bash -c '. "$1" || exit 9; lift_contract_fields "$2" | grep "^done="' _ "$BRIEF_LIB" "$1"; }
expect_eq "DL1 a Done marker line lifts as done=" "done=.bionic/docs/record/w99.done" \
  "$(lift_done 'Expected artifact: .bionic/docs/record/w99.md
Done marker: .bionic/docs/record/w99.done
Files: payload/scripts/lib/widget.sh')"
expect_eq "DL2 …the scaffold slot, pasted unfilled, lifts none" "" \
  "$(lift_done 'Expected artifact: .bionic/docs/record/w99.md
Done marker: <path>   # optional
Files: payload/scripts/lib/widget.sh')"
expect_eq "DL3 …nor does a mention that is not at the start of its line" "" \
  "$(lift_done 'Expected artifact: .bionic/docs/record/w99.md

Note: touch the done marker: .bionic/tmp/w99.done when finished.
Files: payload/scripts/lib/widget.sh')"

# THROUGH THE WALL: the lifted marker is on the launch row the verdict reads, and a brief that
# names none writes a row with no `done=` key at all (byte-identical to the rows before T9).
REPO=$(make_repo dldone yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Done marker: .bionic/tmp/w99-widget.done')" "w99-done")"
DL_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "DL4 a brief naming a Done marker is admitted" "allow" "$GATE_VERDICT"
expect_eq "DL4b …and its launch row carries it as done=" ".bionic/tmp/w99-widget.done" "$(roster_field "$DL_ROW" done)"
REPO=$(make_repo dlnodone yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Scope constraint: touch only payload/scripts/lib/widget.sh.')" "w99-nodone")"
DL_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "DL5 a brief naming no Done marker writes its launch row" "status=intended" "$DL_ROW"
expect_absent "DL5b …with no done= key on it" "|done=" "$DL_ROW"

# ============================================================================

section "§ROOT — a printed fix line under a plugin root with a space pastes as one argument per word (wave-24 T29; critic I2; AC-6.5)"
# ============================================================================
#
# The writer-budget refusal's ack line and the advisory's amend line printed the hooks path
# bare, so a plugin root with a space (a `--plugin-dir` checkout under `~/My Projects/`, a
# config dir with a space) split into two words when pasted. The gate here runs from a COPY of
# the payload under `<sandbox>/my plugin/`, the layout an installed plugin has, so the root the
# lines print is one with a space in it. Each line is parsed the way a pasting shell reads it
# (`eval set --`, nothing executed) and the script path must come back as ONE argument.
# fails-when: the printed script path splits at the space.
root_args() { eval "set -- $1"; printf '%s\n' "$@"; }  # <command text> -> its words, one per line
ROOT_SP="$SANDBOX/my plugin"
cp -RL "${BIONIC_SCRIPTS_DIR}/payload" "$ROOT_SP"
ROOT_GATE_SAVED="$GATE"; GATE="$ROOT_SP/hooks/dispatch-preflight.sh"
expect_true "root0 the gate under test is the copy under a root with a space" test -f "$GATE"

REPO=$(ro_budget_repo root1 "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "root1-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "root1 one open writer against writers=1 → REFUSED" "deny" "$GATE_VERDICT"
ROOT1_LINE="$(printf '%s\n' "$GATE_REASON" | /usr/bin/grep -F 'W-ONE' | /usr/bin/grep -m1 -F 'session-sweeper.sh' || true)"
expect_true "root1 …the reason carries the ack line" test -n "$ROOT1_LINE"
ROOT1_ARGS="$(root_args "${ROOT1_LINE#*close it: }")"
expect_eq "root1 …which parses as bash, the script, ack and the name" "4" "$(printf '%s\n' "$ROOT1_ARGS" | /usr/bin/grep -c '')"
expect_contains "root1 …its script path is one argument, space and all" "my plugin/hooks/session-sweeper.sh" "$(printf '%s\n' "$ROOT1_ARGS" | sed -n 2p)"
expect_true "root1 …naming the real file" test -f "$(printf '%s\n' "$ROOT1_ARGS" | sed -n 2p)"

REPO=$(make_repo rootadv yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'When the seam is in, run `bash tests/foo.test.sh` and report the count.')" "w99-adv")"
ROOT2_LINE="$(adv_ctx | /usr/bin/grep -m1 -F -- '--suites+ foo.test.sh' || true)"
expect_true "root2 the advisory prints the amend line" test -n "$ROOT2_LINE"
ROOT2_ARGS="$(root_args "${ROOT2_LINE#*to declare it: }")"
expect_eq "root2 …which parses as bash, the script, amend, the name, the flag, the suite, --reason, why" "8" "$(printf '%s\n' "$ROOT2_ARGS" | /usr/bin/grep -c '')"
expect_contains "root2 …its script path is one argument, space and all" "my plugin/hooks/session-poker.sh" "$(printf '%s\n' "$ROOT2_ARGS" | sed -n 2p)"
expect_true "root2 …naming the real file" test -f "$(printf '%s\n' "$ROOT2_ARGS" | sed -n 2p)"
GATE="$ROOT_GATE_SAVED"

# ===========================================================================

section "§GATES — only human gates hold: nothing writes before approved-by:, a release waits for approved: release, a doc row is not held by its step (wave-26 T13; REQ-6 AC-6.2; D3)"
# A dispatch named for a row (`w-T1`, `w-T9`) binds it, so its writer brief names the suites it lands
# on (wave-28 T7, ruling A-orch-73); the line changes nothing else these rows read.
GATES_BRIEF="$BRIEF_FULL
Lands-on: widget"
# ===========================================================================
#
# AN APPROVAL IS AN INPUT ONLY THE USER'S ACT WRITES (D3). `approval:plan` is the `approved-by:`
# line; any other name is an `approved: <name> …` line, written by `session-poker.sh approve`.
# Two readers must agree on both: the dispatch wall, which refuses the dispatch, and the ready
# set (lib/fill.sh), which never offers the row. Each row below asks both over one plan.
#
# The plan is a reads table (D1) bound to the session: T1 a build, T8 a Step-7 doc row reading
# only the plan approval, T9 the release reading `approval:release`. current: 4 throughout.
GATES_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/fill.sh"
expect_true "GATES0 the ready-set library is where this section expects it" test -f "$GATES_LIB"
gates_plan() {  # <repo> <SDLC lines, newline-joined, may be empty>
  local f="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf -- 'intent: build\nrigor: double\nscale: wave\n---\n\n'
    printf -- '# Test wave plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: 4\n'
    [ -n "$2" ] && printf -- '%s\n' "$2"
    printf -- '\n- Step 4: tasks in flight\n\n## Tasks\n\n'
    printf -- '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
    printf -- '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf -- '| T1 | 4 | build | a build | implementor | — | 30 | REQ-x | a.sh | pending | |\n'
    printf -- '| T8 | 7 | doc | the notes | implementor | — | 20 | REQ-x | .bionic/docs/record/notes.md | pending | approval:plan |\n'
    printf -- '| T9 | 7 | doc | the release | implementor | — | 20 | REQ-x | CHANGELOG.md | pending | approval:release |\n'
  } > "$f"
  printf '%s' "$f"
}
gates_ready() {  # <plan> -> the ready set, space-joined, as the tick and the wall ask it
  ( . "$GATES_LIB" >/dev/null 2>&1; fill_ready_set "$1" 8 0 | tr '\n' ' ' )
}
GATES_APPROVED='approved-by: dana 2026-10-04T03:33:32Z "Approved"'
GATES_RELEASE='approved: release by dana 2026-10-04T05:00:00Z "Ship it."'

# --- GATES1: before approved-by: nothing writes, on either reader ---
REPO=$(make_repo rgates1 yes)
write_attestation "$REPO" "$SID_A"
GATES_P="$(gates_plan "$REPO" "")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T1" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "GATES1 AC-6.2 a writer for T1 before approved-by: is refused" "deny" "$GATE_VERDICT"
expect_eq "GATES1b …and the ready set offers nothing before approved-by:" "" "$(gates_ready "$GATES_P")"
GATES_P="$(gates_plan "$REPO" "$GATES_APPROVED")"
expect_contains "GATES1c the control: with approved-by: written, the ready set offers T1" "T1 " "$(gates_ready "$GATES_P")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T1" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "GATES1d …and the dispatch wall admits the writer for T1" "0" "$GATE_ST"
# THE LAUNCH NOW HOLDS ITS ROW (wave-35 T28; AC-5.5): w-T1 is open on this session's roster, so the same
# set no longer offers T1 (GATES1c is the positive, same extractor). GATES1e/1f therefore ask on a repo of
# their own, where no launch holds T1.
expect_absent "GATES1g AC-5.5 …and once w-T1 is launched for T1, the ready set no longer offers T1" "T1 " "$(gates_ready "$GATES_P")"
REPO=$(make_repo rgates1l yes)
# A TABLE WITHOUT `reads` applies no kind default, so nothing in the table itself waits for the
# approval: the ready set's own gate is all that holds it. Keyed on `current: >= 4`, it would
# offer T1 here.
gates_legacy() {  # <repo> <SDLC lines> -> the plan; no reads column, current: 4
  local f="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n---\n\n'
    printf -- '# Test wave plan\n\n## SDLC State\n\ncurrent: 4\n'
    [ -n "$2" ] && printf -- '%s\n' "$2"
    printf -- '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
    printf -- '|---|---|---|---|---|---|---|---|---|---|\n'
    printf -- '| T1 | 4 | build | a build | implementor | — | 30 | REQ-x | a.sh | pending |\n'
  } > "$f"
  printf '%s' "$f"
}
expect_eq "GATES1e a table without reads at current: 4 and no approved-by: offers nothing" \
  "" "$(gates_ready "$(gates_legacy "$REPO" "")")"
expect_contains "GATES1f …and offers T1 once approved-by: is written" \
  "T1 " "$(gates_ready "$(gates_legacy "$REPO" "$GATES_APPROVED")")"

# --- GATES2: the release waits for approved: release, on either reader ---
REPO=$(make_repo rgates2 yes)
write_attestation "$REPO" "$SID_A"
GATES_P="$(gates_plan "$REPO" "$GATES_APPROVED")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T9" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "GATES2 AC-6.2 a dispatch for the release row before approved: release is refused" "deny" "$GATE_VERDICT"
expect_contains "GATES2b …naming the approval it waits for" "approval:release" "$GATE_VERR"
expect_contains "GATES2c …and the verb that records it" "session-poker.sh approve release" "$GATE_VERR"
GATES_READY="$(gates_ready "$GATES_P")"
expect_contains "GATES2d the ready set on the same plan offers T1 (the extractor reads a real set)" "T1 " "$GATES_READY"
expect_absent "GATES2e …and not the release" "T9" "$GATES_READY"
GATES_P="$(gates_plan "$REPO" "$GATES_APPROVED
$GATES_RELEASE")"
# The ready set is read before the release's launch: once w-T9 is on the roster it holds T9 (GATES2h).
GATES_READY="$(gates_ready "$GATES_P")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T9" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "GATES2f with approved: release written, the release dispatch is admitted" "0" "$GATE_ST"
expect_contains "GATES2g …and the ready set offers it" "T9" "$GATES_READY"
expect_absent "GATES2h AC-5.5 …until its launch: with w-T9 open on the roster, the set no longer offers T9 (GATES2g is the positive)" \
  "T9" "$(gates_ready "$GATES_P")"

# --- GATES3: a doc row is not held by its step ---
expect_contains "GATES3 AC-6.2 at current: 4 the Step-7 doc row whose reads exist is ready" \
  "T8" "$(gates_ready "$GATES_P")"

# --- GATES4: one approved-by: reader (wave-26 T5; review 10 F2) ---
# A bulleted `- approved-by:` approves on both readers; one only inside a fence approves on
# neither. Through T13 the wall read it fence-blind and refused the bullet, so the tick FILLed a
# row the wall then refused, and a fenced example let writers in on an unapproved plan.
REPO=$(make_repo rgates4 yes)
write_attestation "$REPO" "$SID_A"
GATES_P="$(gates_plan "$REPO" "- $GATES_APPROVED")"
expect_contains "GATES4 precondition: the plan carries the bulleted line" "- approved-by: dana" "$(cat "$GATES_P")"
expect_contains "GATES4 the ready set offers T1 on a bulleted approved-by:" "T1 " "$(gates_ready "$GATES_P")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T1" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "GATES4b …and the dispatch wall admits its writer" "allow" "$GATE_VERDICT"
REPO=$(make_repo rgates4f yes)
write_attestation "$REPO" "$SID_A"
GATES_P="$(gates_plan "$REPO" '```
approved-by: example 2026-01-01T00:00Z "approved"
```')"
expect_contains "GATES4c precondition: the plan carries approved-by: only inside a fence" \
  'approved-by: example' "$(cat "$GATES_P")"
expect_eq "GATES4c the ready set offers nothing on a fenced approved-by:" "" "$(gates_ready "$GATES_P")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T1" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "GATES4d …and the dispatch wall refuses its writer" "deny" "$GATE_VERDICT"
expect_contains "GATES4d …as unapproved" "unapproved" "$GATE_ERR"

# --- GATES5: a live read of an approval is still an approval read (review 10 F5) ---
REPO=$(make_repo rgates5 yes)
write_attestation "$REPO" "$SID_A"
GATES_P="$(gates_plan "$REPO" "$GATES_APPROVED")"
sed 's/| approval:release |$/| live:approval:release |/' "$GATES_P" > "$GATES_P.tmp" && mv "$GATES_P.tmp" "$GATES_P"
expect_contains "GATES5 precondition: T9 reads live:approval:release" "| live:approval:release |" "$(cat "$GATES_P")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$GATES_BRIEF" "w-T9" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "GATES5 a dispatch for a row reading live:approval:release before approved: release is refused" \
  "deny" "$GATE_VERDICT"
expect_contains "GATES5b …naming the approval it waits for" "approval:release" "$GATE_VERR"



# --- FILES-ROOT: a root file on a Files: line is recorded (wave-27 T29; REQ-12 AC-12.1, D21) ---
# THE DEFECT, from a real run: `Files: CONTEXT.md, a/b.ts` recorded only `a/b.ts`, because the
# grammar read an entry as a path only when it carried a `/`. The writer then edited the file
# its brief named and its stop was refused for it. One reader in brief.sh now reads every entry:
# a path carries a `/`, or an extension (wave-27 T42 dropped the third arm, "names a file that
# exists at the project root": no wall lists the root).
REPO=$(make_repo rfilesroot yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfr.md
Files: CONTEXT.md, a/b.ts
Suites: tests/one.test.sh' "w-filesroot")"
expect_eq "FILES-ROOT a brief naming a root file beside a nested one is admitted" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "FILES-ROOT precondition: the dispatch wrote its row" "|name=w-filesroot|" "$ROW"
expect_eq "FILES-ROOT AC-12.1 files= holds the root file and the nested one, as written" \
  "CONTEXT.md,a/b.ts" "$(roster_field "$ROW" files)"
# A BARE NAME IS REFUSED EVEN WHEN A FILE OF THAT NAME IS AT THE ROOT (wave-27 T42, A-orch-46):
# T29's third arm admitted it by listing the root, the fetch the hook-authoring freeze forbids.
# This fixture plants a Makefile, so the old arm would have admitted it; `./Makefile` is the
# spelling, and it needs no listing. Worked answer: `Files: Makefile, src/a.c` refuses, first
# line naming `Makefile` and `./Makefile`; `Files: ./Makefile, src/a.c` records both.
REPO=$(make_repo rfilesroot2 yes)
write_attestation "$REPO" "$SID_A"
echo x > "$REPO/Makefile"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfr2.md
Files: Makefile, src/a.c
Suites: tests/one.test.sh' "w-filesroot2")"
expect_eq "FILES-ROOT2 a bare name refuses though a file of that name is at the root" "deny" "$GATE_VERDICT"
FR2_LINE=$(printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused')
expect_contains "FILES-ROOT2 precondition: the refusal line is read" "bionic: dispatch refused" "$FR2_LINE"
expect_contains "FILES-ROOT2 …its first line names the word and the spelling ./Makefile" \
  "Files: names Makefile, not a path" "$FR2_LINE"
expect_contains "FILES-ROOT2 …and the accepted spelling" "./Makefile" "$FR2_LINE"
expect_eq "FILES-ROOT2 …and no row was written" "" "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfr2.md
Files: ./Makefile, src/a.c
Suites: tests/one.test.sh' "w-filesroot2")"
expect_eq "FILES-ROOT3 ./Makefile is admitted" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "FILES-ROOT3 …and both are stored as written" "./Makefile,src/a.c" "$(roster_field "$ROW" files)"

# --- FILES-DROP: an entry the reader does not read as a path refuses (REQ-12 AC-12.2, D21) ---
REPO=$(make_repo rfilesdrop yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfd.md
Files: Widgetfile, a/b.ts
Suites: tests/one.test.sh' "w-filesdrop")"
expect_eq "FILES-DROP AC-12.2 an entry with no slash, no extension and no file at the root refuses" \
  "deny" "$GATE_VERDICT"
FD_LINE=$(printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused')
expect_contains "FILES-DROP precondition: the refusal line is read" "bionic: dispatch refused" "$FD_LINE"
expect_contains "FILES-DROP …its first line names the entry" "Widgetfile" "$FD_LINE"
expect_contains "FILES-DROP …and the accepted spelling" "./Widgetfile" "$FD_LINE"
expect_eq "FILES-DROP …and no row was written" "" "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"
# The spelling the refusal names is one the wall admits, in the same repo.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfd.md
Files: ./Widgetfile, a/b.ts
Suites: tests/one.test.sh' "w-filesdrop")"
expect_eq "FILES-DROP2 the spelling it names is admitted" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "FILES-DROP2 …and recorded" "./Widgetfile,a/b.ts" "$(roster_field "$ROW" files)"
# A ONE-TOKEN SLOT IS GUIDANCE, NOT AN ENTRY: `<paths>` is skipped. This row does NOT test the
# scaffold line as shipped (wave-27 T42, review pass 11 F2): the shipped slot holds white space,
# and FILES-LIST below reads that line out of dispatch.md and shows it refused once, as prose.
REPO=$(make_repo rfilesslot yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfs.md
Files: <paths>, a/b.ts
Suites: tests/one.test.sh' "w-filesslot")"
expect_eq "FILES-DROP3 an unfilled <slot> on a Files: line is not an entry, and admits" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "FILES-DROP3 …and the row holds the real path alone" "a/b.ts" "$(roster_field "$ROW" files)"


# --- FILES-LIST: a Files: span is a comma-separated list of paths (wave-27 T42; REQ-12, D21 as
# amended by A-orch-46; review pass 11 F1, F3, F6) ---
# The span is split on commas (and line ends, for a list one item per line); a trailing ` # …`
# comment is stripped, as on `Subprocess claim:`; a leading `- `, `* ` or `1. ` and surrounding
# backticks come off an item; `none` alone is no files. An item holding white space is prose,
# refused once with no spelling advice. An item is a path when it carries a `/`, or an extension
# (a final dot, then a letter-led run of letters and digits, on a stem holding a letter). Any
# other word is refused naming `./<word>`; an item ending in `.` or holding no letter or digit
# is refused with no advice, since no spelling of it is read as a path.
#
# fl_read <brief text> -> `files=<lifted>`, one `finding: <fact> | <fix>` per refusal, `rc=`.
# Every brief carries a Suites: line, so no finding here is the Files-alone arm's.
fl_read() {
  bash -c '
    . "$1" || exit 9
    sink() { [ "$1" = finding ] && printf "finding: %s | %s\n" "$2" "$3"; return 0; }
    l=$(lift_contract_fields "$2" implementor)
    printf "files=%s\n" "$(brief_field "$l" files)"
    rc=0; brief_validate_fields "$l" implementor "$3" sink || rc=$?
    printf "rc=%s\n" "$rc"
  ' _ "$BRIEF_LIB" "$1
Suites: tests/one.test.sh" "$BRIEF_NOCONF" 2>&1
}
fl_findings() { printf '%s\n' "$1" | /usr/bin/grep -c '^finding: '; }

# THE SCAFFOLD LINE, read out of the shipped dispatch.md, never retyped.
FL_SCAFFOLD="$(scaffold_raw_line "$DISPATCH_FILE" "Files")"
# RE-POINTED (wave-27 T53, review pass 28 B1): the comment now opens "a reader lists its records".
expect_contains "FILES-LIST meta: the shipped scaffold's Files: line was read, comment and all" \
  "  # a reader lists" "$FL_SCAFFOLD"
FL_SLOT="$(printf '%s' "$FL_SCAFFOLD" | sed -e 's/^Files: //' -e 's/  #.*$//')"
expect_contains "FILES-LIST meta: …and its slot is one item holding white space" "<every path" "$FL_SLOT"

# Pasted as shipped: the slot is one item holding white space, prose, refused ONCE, naming the
# item, with no ./ advice, and nothing recorded. A-T29.3 claimed this refused nothing.
FL=$(fl_read "$FL_SCAFFOLD")
expect_contains "FILES-LIST1 the scaffold line as shipped is refused" "rc=1" "$FL"
expect_eq "FILES-LIST1 …once" "1" "$(fl_findings "$FL")"
expect_contains "FILES-LIST1 …naming the slot item whole" "finding: Files: ${FL_SLOT} is not a path" "$FL"
expect_absent "FILES-LIST1 …with no ./ advice" "./" "$(printf '%s\n' "$FL" | grep '^finding: ')"
expect_contains "FILES-LIST1 …and nothing recorded" "files=
" "$FL
"
# Filled as a real brief fills it, comment kept byte for byte: exactly the two paths, no finding.
FL_FILLED="$(printf '%s' "$FL_SCAFFOLD" | sed 's|<every path the task may create or edit>|src/a.c, tests/a.test.sh|')"
expect_contains "FILES-LIST2 meta: the filled line keeps the shipped comment" "tests/a.test.sh  # a reader lists" "$FL_FILLED"
FL=$(fl_read "$FL_FILLED")
expect_contains "FILES-LIST2 the filled scaffold line records exactly its two paths" "files=src/a.c,tests/a.test.sh
" "$FL
"
expect_contains "FILES-LIST2 …and admits (rc=0)" "rc=0" "$FL"
expect_eq "FILES-LIST2 …with no finding" "0" "$(fl_findings "$FL")"

FL=$(fl_read "Files: CONTEXT.md, a/b.ts")
expect_contains "FILES-LIST3 CONTEXT.md and a/b.ts are both recorded (T29's defect stays fixed)" "files=CONTEXT.md,a/b.ts" "$FL"
expect_contains "FILES-LIST3 …rc=0" "rc=0" "$FL"
FL=$(fl_read "Files: Makefile, src/a.c")
expect_contains "FILES-LIST4 Makefile refuses" "rc=1" "$FL"
expect_eq "FILES-LIST4 …once" "1" "$(fl_findings "$FL")"
expect_contains "FILES-LIST4 …naming it and ./Makefile" "finding: Files: names Makefile, not a path | spell it ./Makefile" "$FL"
FL=$(fl_read "Files: ./Makefile, src/a.c")
expect_contains "FILES-LIST5 ./Makefile records both" "files=./Makefile,src/a.c" "$FL"
expect_contains "FILES-LIST5 …rc=0" "rc=0" "$FL"

FL=$(fl_read "Files: none")
expect_contains "FILES-LIST6 Files: none admits (rc=0)" "rc=0" "$FL"
expect_eq "FILES-LIST6 …with no finding" "0" "$(fl_findings "$FL")"
expect_contains "FILES-LIST6 …and records nothing" "files=
" "$FL
"

FL=$(fl_read "Files: src/a.c (new), and b.md")
expect_eq "FILES-LIST7 a prose item refuses once per item: two" "2" "$(fl_findings "$FL")"
expect_contains "FILES-LIST7 …naming src/a.c (new)" "finding: Files: src/a.c (new) is not a path" "$FL"
expect_contains "FILES-LIST7 …and and b.md" "finding: Files: and b.md is not a path" "$FL"
expect_absent "FILES-LIST7 …with no ./ advice" "./" "$(printf '%s\n' "$FL" | grep '^finding: ')"
FL=$(fl_read "Files: see e.g. the docs")
expect_eq "FILES-LIST8 'see e.g. the docs' refuses once" "1" "$(fl_findings "$FL")"
expect_contains "FILES-LIST8 …naming the item whole" "finding: Files: see e.g. the docs is not a path" "$FL"
expect_contains "FILES-LIST8 …and recording nothing" "files=
" "$FL
"
FL=$(fl_read "Files: hooks/a.sh, fixed in v1.2 and 1.11.0")
expect_eq "FILES-LIST9 v1.2 and 1.11.0 inside prose: the item refuses once" "1" "$(fl_findings "$FL")"
expect_contains "FILES-LIST9 …and only the path is recorded" "files=hooks/a.sh
" "$FL
"
for FL_W in v1.2 1.11.0 Fig.3; do
  FL=$(fl_read "Files: hooks/a.sh, $FL_W")
  expect_contains "FILES-LIST10 $FL_W alone is not a path: refused" "finding: Files: names $FL_W, not a path" "$FL"
  expect_contains "FILES-LIST10 …$FL_W is not recorded" "files=hooks/a.sh
" "$FL
"
done
for FL_W in e.g. README. —; do
  FL=$(fl_read "Files: hooks/a.sh, $FL_W")
  expect_contains "FILES-LIST11 '$FL_W' (ends in . or holds no letter or digit) is refused" \
    "finding: Files: $FL_W is not a path" "$FL"
  expect_absent "FILES-LIST11 …with no ./ advice" "./" "$(printf '%s\n' "$FL" | grep '^finding: ')"
  expect_contains "FILES-LIST11 …and is not recorded" "files=hooks/a.sh
" "$FL
"
done

FL=$(fl_read "Files:
1. hooks/a.sh
2. tests/b.test.sh")
expect_contains "FILES-LIST12 a numbered list records its paths" "files=hooks/a.sh,tests/b.test.sh" "$FL"
expect_contains "FILES-LIST12 …rc=0" "rc=0" "$FL"
FL=$(fl_read "Files:
- hooks/a.sh
* tests/b.test.sh")
expect_contains "FILES-LIST13 a bulleted list records its paths" "files=hooks/a.sh,tests/b.test.sh" "$FL"
expect_contains "FILES-LIST13 …rc=0" "rc=0" "$FL"
FL=$(fl_read "Files: ${BT}hooks/a.sh${BT}, ${BT}tests/b.test.sh${BT}")
expect_contains "FILES-LIST14 backticked items record without their backticks" "files=hooks/a.sh,tests/b.test.sh
" "$FL
"
FL=$(fl_read "Files: ${BT}hooks/a.sh${BT}, ${BT}Makefile${BT}")
expect_contains "FILES-LIST14 …and a backticked bare word is named bare" \
  "finding: Files: names Makefile, not a path | spell it ./Makefile" "$FL"

# THE VERDICT (F6): `brief_files_entry` answers 0 only when the reader recorded the entry itself,
# 1 with the `./` spelling when that is recorded, and 2 when no spelling is.
fe() { bash -c '. "$1" || exit 9; brief_files_entry "$2"; echo " rc=$?"' _ "$BRIEF_LIB" "$1" 2>&1; }
expect_eq "FILES-ENTRY a path answers 0, as written" "a/b.c rc=0" "$(fe a/b.c)"
expect_eq "FILES-ENTRY a bare word answers 1, as ./<word>" "./Makefile rc=1" "$(fe Makefile)"
expect_eq "FILES-ENTRY a dotfile answers 1, as ./<name>" "./.gitignore rc=1" "$(fe .gitignore)"
expect_eq "FILES-ENTRY a name ending in . answers 2" "README. rc=2" "$(fe README.)"
expect_eq "FILES-ENTRY a name with no letter or digit answers 2" "* rc=2" "$(fe '*')"
expect_eq "FILES-ENTRY a name holding white space answers 2" "my notes.md rc=2" "$(fe 'my notes.md')"
expect_eq "FILES-ENTRY a name holding a comma answers 2" "a,b.md rc=2" "$(fe 'a,b.md')"

# Through the hook: the scaffold line as shipped refuses once, naming the item, and writes no row.
REPO=$(make_repo rfileslist yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/wfl.md
$FL_SCAFFOLD
Suites: tests/one.test.sh" "w-fileslist")"
expect_eq "FILES-LIST15 the hook refuses the scaffold line as shipped" "deny" "$GATE_VERDICT"
FL_LINE=$(printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused')
expect_contains "FILES-LIST15 …its first line naming the slot item" "Files: ${FL_SLOT} is not a path" "$FL_LINE"
expect_absent "FILES-LIST15 …with no ./ advice" "./" "$FL_LINE"
expect_eq "FILES-LIST15 …and no row was written" "" "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/wfl.md
$FL_FILLED
Suites: tests/one.test.sh" "w-fileslist")"
expect_eq "FILES-LIST16 the hook admits the filled scaffold line" "allow" "$GATE_VERDICT"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "FILES-LIST16 …and records exactly its two paths" "src/a.c,tests/a.test.sh" "$(roster_field "$ROW" files)"
# A LONG WORD AND A LONG PROSE ITEM still draw a refusal line: refuse.sh holds a fix to six words
# and 40 columns and a line to 100, and an item named in full past that made the wall refuse its
# own call and exit 2 with no refusal line at all.
REPO=$(make_repo rfileslong yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfl2.md
Files: docker-compose-override, src/a.c
Suites: tests/one.test.sh' "w-fileslong")"
expect_eq "FILES-LIST17 a bare word of 23 characters is refused by a deny" "deny" "$GATE_VERDICT"
FL_LINE=$(printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused')
expect_contains "FILES-LIST17 …whose first line names it, cut" "Files: names docker-compose-…, not a path" "$FL_LINE"
expect_contains "FILES-LIST17 …and tells the prefix" "spell it with a leading ./" "$FL_LINE"
expect_contains "FILES-LIST17 …and whose detail spells it whole" "Files: ./docker-compose-override" "$GATE_REASON"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wfl2.md
Files: src/a.c, this list covers every file the task may create or edit
Suites: tests/one.test.sh' "w-fileslong")"
expect_eq "FILES-LIST18 a prose item of 55 characters is refused by a deny" "deny" "$GATE_VERDICT"
FL_LINE=$(printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused')
expect_contains "FILES-LIST18 …whose first line names it, cut" "Files: this list covers every file the task may … is not a path (drop it)" "$FL_LINE"

# ============================================================================

section "§LR — a declared debt is recorded at dispatch, and only a well-formed one (wave-27 T31; REQ-14 AC-14.1, AC-14.2, D23)"
# ============================================================================
#
# A brief may carry `Lands-red: <suite> until <ext:slug | approval:name>` and `Red-evidence: <path
# under record/>`, each on a line of its own. The wall records both on the launch row as
# `lands_red=` and `red_evidence=`, and refuses a Lands-red: with no Red-evidence:, a suite outside
# the row's suite set, and a token of any other shape. It is the keys' one writer: `land` honours
# only what a row carried from its launch.
# FIXTURES: adv_brief's writer contract (Suites: tests/widget.test.sh, so the row's set is
# widget.test.sh), on make_repo's approved, bound plan. SYNTHESIZED.
# fails-when: a well-formed declaration is refused or not recorded; one of the three faults is
# admitted; a brief with no declaration, or the scaffold's unfilled slots, records a key.
# (wave-27 T67) The bound plan carries a `## Tasks` table with a reads column: a Step-4 row reads
# approval:design and the integrate row approval:release, so an approval: token is judged against
# the names the approve verb accepts (S4). SYNTHESIZED, in units.sh's twelve-column shape plus reads.
lr_gate() {  # <repo tag> <body lines> [<brief>] -> GATE_*, LR_ROW
  REPO=$(make_repo "$1" yes); write_attestation "$REPO" "$SID_A"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T3 | 4 | build | the design | implementor | — | 30 | REQ-1 | a.sh | — | — | pending | approval:design |\n| T8 | 8 | integrate | integrate | implementor | T3 | 30 | REQ-1 | — | — | — | pending | approval:release |\n' \
    >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  local lr_b="${3:-$(adv_brief "$2")}"; lr_b="${lr_b//@ROOT@/$(cd "$REPO" && pwd -P)}"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$lr_b" "w99-$1")"
  LR_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
}
lr_gate lr1 'Lands-red: widget.test.sh until approval:design
Red-evidence: .bionic/docs/record/wave-01-test/T9-red.md'
expect_eq "LR1 a Lands-red: on the row's own suite, with its evidence and an approval: token a Step-4 row reads, is admitted" "allow" "$GATE_VERDICT"
expect_eq "LR1b …the row carries lands_red=<suite> until <token>" "widget.test.sh until approval:design" \
  "$(roster_field "$LR_ROW" lands_red)"
expect_eq "LR1c …and red_evidence=<path>" ".bionic/docs/record/wave-01-test/T9-red.md" "$(roster_field "$LR_ROW" red_evidence)"
lr_gate lr1x 'Lands-red: tests/widget.test.sh until ext:vendor-fix
Red-evidence: .bionic/docs/record/wave-01-test/T9-red.md'
expect_eq "LR1x an ext:<slug> token is admitted too, the suite recorded by its basename" "allow widget.test.sh until ext:vendor-fix" \
  "$GATE_VERDICT $(roster_field "$LR_ROW" lands_red)"

lr_gate lr2 'Lands-red: widget.test.sh until approval:design'
expect_eq "LR2 a Lands-red: with no Red-evidence: is refused" "deny" "$GATE_VERDICT"
expect_contains "LR2b …the line names the missing label" "Lands-red: with no Red-evidence: line" "$GATE_ERR"
expect_contains "LR2c …and the detail the line to add" "    Red-evidence: <path under record/>" "$GATE_VERR"
expect_eq "LR2d …and no row is written" "" "$LR_ROW"

lr_gate lr3 'Lands-red: other.test.sh until approval:design
Red-evidence: .bionic/docs/record/wave-01-test/T9-red.md'
expect_eq "LR3 a Lands-red: on a suite outside the row's suite set is refused" "deny" "$GATE_VERDICT"
expect_contains "LR3b …naming the suite" "Lands-red: other.test.sh is outside Suites:" "$GATE_ERR"
expect_contains "LR3c …and the set it may name from" "Suites: widget.test.sh" "$GATE_VERR"

lr_gate lr4 'Lands-red: widget.test.sh until someday
Red-evidence: .bionic/docs/record/wave-01-test/T9-red.md'
expect_eq "LR4 a token that is neither ext:<slug> nor approval:<name> is refused" "deny" "$GATE_VERDICT"
expect_contains "LR4b …the line says so" "Lands-red: names no blocker token" "$GATE_ERR"
expect_contains "LR4c …and the detail names the two forms" "ext:<slug>" "$GATE_VERR"
expect_contains "LR4d …both of them" "approval:<name>" "$GATE_VERR"

lr_gate lr5 'Scope constraint: touch only payload/scripts/lib/widget.sh.'
expect_eq "LR5 a brief that declares no debt is admitted" "allow" "$GATE_VERDICT"
expect_contains "LR5b …its row is written (the extractor reads a real row)" "status=intended" "$LR_ROW"
expect_absent "LR5c …with no lands_red= on it" "lands_red=" "$LR_ROW"
expect_absent "LR5d …nor red_evidence=" "red_evidence=" "$LR_ROW"
lr_gate lr6 'Lands-red: <suite> until <ext:slug | approval:name>
Red-evidence: <path under record/>'
expect_eq "LR6 the scaffold's two slots pasted unfilled declare nothing: admitted" "allow" "$GATE_VERDICT"
expect_contains "LR6b …its row is written" "status=intended" "$LR_ROW"
expect_absent "LR6c …with no lands_red= on it" "lands_red=" "$LR_ROW"
lr_gate lr7 'Lands-red: widget.test.sh until approval:design  # optional
Red-evidence: .bionic/docs/record/wave-01-test/T9-red.md  # with Lands-red:'
expect_eq "LR7 the two lines filled with the scaffold's comments kept: admitted, the comments off the values" \
  "allow|widget.test.sh until approval:design|.bionic/docs/record/wave-01-test/T9-red.md" \
  "$GATE_VERDICT|$(roster_field "$LR_ROW" lands_red)|$(roster_field "$LR_ROW" red_evidence)"

# --- wave-27 T67 (review pass 46 B4, S1, S4, N1, N2, N3): what the wall refuses besides.
LR_EV_OK='Red-evidence: .bionic/docs/record/wave-01-test/T9-red.md'
lr_first() { printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused'; }
# B4: the full-suite runner is never a declared red, however it is spelled.
lr_k=0
for lr_sp in 'run.sh' 'tests/run.sh' './tests/run.sh' 'bash tests/run.sh'; do
  lr_k=$((lr_k + 1))
  lr_gate "lr8-$lr_k" "Lands-red: ${lr_sp} until ext:x
${LR_EV_OK}" "$(adv_brief "Lands-red: ${lr_sp} until ext:x
${LR_EV_OK}" | sed 's#^Suites: tests/widget.test.sh$#Suites: tests/run.sh#')"
  expect_eq "LR8 B4 Suites: tests/run.sh with Lands-red: ${lr_sp} until ext:x is refused" "deny" "$GATE_VERDICT"
  expect_contains "LR8b …the line naming the runner (${lr_sp})" "Lands-red: names the full-suite runner" "$(lr_first)"
  expect_contains "LR8c …the detail saying it is never a declared red (${lr_sp})" "the full-suite runner is never a declared red" "$GATE_VERR"
  expect_eq "LR8d …and no row is written (${lr_sp})" "" "$LR_ROW"
done
lr_gate lr8e "Lands-red: widget.sh until ext:x
${LR_EV_OK}"
expect_contains "LR8e a Lands-red: naming no <name>.test.sh file is refused, saying so" "Lands-red: names no <name>.test.sh" "$(lr_first)"
# S4, N1: an approval: token is one a row reads, and not one the integrate row waits on.
lr_gate lr9 "Lands-red: widget.test.sh until approval:release
${LR_EV_OK}"
expect_eq "LR9 S4 until approval:release, the approval the integrate row reads, is refused" "deny" "$GATE_VERDICT"
expect_contains "LR9b …the line naming the approval" "approval:release is read at integration" "$(lr_first)"
expect_contains "LR9c …the detail saying it comes after the step a debt must clear before" "comes after the step a debt must clear before" "$GATE_VERR"
lr_gate lr9n "Lands-red: widget.test.sh until approval:nobody
${LR_EV_OK}"
expect_eq "LR9n until approval:nobody, a name no row reads, is refused" "deny" "$GATE_VERDICT"
expect_contains "LR9n2 …the line saying no row reads it" "approval:nobody is read by no row" "$(lr_first)"
expect_contains "LR9n3 …the detail naming the names the rows read" "design" "$GATE_VERR"
# N2: one declaration.
lr_gate lr10 "Lands-red: widget.test.sh until ext:x
Lands-red: widget.test.sh until ext:y
${LR_EV_OK}"
expect_eq "LR10 N2 a brief with two Lands-red: lines is refused" "deny" "$GATE_VERDICT"
expect_contains "LR10b …the line counting them" "the brief has 2 Lands-red: lines" "$(lr_first)"
expect_eq "LR10c …and no row is written" "" "$LR_ROW"
# N3: the evidence is a file under the run's record root.
lr_k=0
for lr_ev in /tmp/x.md ../x.md .bionic/tmp/scratch/w99/x.md .bionic/docs/record/../tmp/x.md; do
  lr_k=$((lr_k + 1))
  lr_gate "lr11-$lr_k" "Lands-red: widget.test.sh until ext:x
Red-evidence: ${lr_ev}"
  expect_eq "LR11 N3 Red-evidence: ${lr_ev} is refused" "deny" "$GATE_VERDICT"
  expect_contains "LR11b …the line saying where it must be (${lr_ev})" "Red-evidence: is not under record/" "$(lr_first)"
done
lr_gate lr11r "Lands-red: widget.test.sh until ext:x
Red-evidence: record/wave-01-test/T9-red.md"
expect_eq "LR11r a record/… path, read from the docs root as the fact verb reads one, is admitted" \
  "allow|record/wave-01-test/T9-red.md" "$GATE_VERDICT|$(roster_field "$LR_ROW" red_evidence)"
lr_gate lr11a "Lands-red: widget.test.sh until ext:x
Red-evidence: @ROOT@/.bionic/docs/record/wave-01-test/T9-red.md"
expect_eq "LR11a …an absolute path under the record root, its directories read physically, is admitted" \
  "allow" "$GATE_VERDICT"
# S1: a long suite name outside Suites: is cut in the fact, and the line keeps its fix.
LR12_S="a-suite-name-of-sixty-characters-long-enough-to-wrap.test.sh"
lr_gate lr12 "Lands-red: ${LR12_S} until ext:x
${LR_EV_OK}"
expect_eq "LR12 precondition: the name is sixty characters" "60" "${#LR12_S}"
expect_eq "LR12a S1 a sixty-character suite outside Suites: is refused by a deny" "deny" "$GATE_VERDICT"
expect_eq "LR12b …its first line at most 100 columns" "ok" "$([ "$(bionic_cols "$(lr_first)")" -le 100 ] && echo ok || echo "wide:$(bionic_cols "$(lr_first)")")"
expect_contains "LR12c …naming the suite, cut by the library" "Lands-red: a-suite-name" "$(lr_first)"
expect_contains "LR12d …with its fix" "(name a suite the row runs)" "$(lr_first)"
# --- FILES-LIST19..: one pair of punctuation around a path, and a trailing `;` (wave-27 T49; review
# pass 19 should-fix 1). The reader strips from an item ONE surrounding pair of double quotes, single
# quotes, parentheses, square brackets or backticks, and a trailing `;`; what is left is judged as any
# item. An unmatched mark is no pair and stays on the item.
FL=$(fl_read 'Files: "lib/a.sh", (lib/b.sh), [lib/c.sh], '"'lib/d.sh'"', lib/e.sh;')
expect_contains "FILES-LIST19 five wrapped or terminated paths record the five bare paths" \
  "files=lib/a.sh,lib/b.sh,lib/c.sh,lib/d.sh,lib/e.sh
" "$FL
"
expect_contains "FILES-LIST19 …rc=0" "rc=0" "$FL"
expect_eq "FILES-LIST19 …with no finding" "0" "$(fl_findings "$FL")"
FL=$(fl_read 'Files: "lib/a.sh')
expect_contains "FILES-LIST20 an unmatched mark is no pair: the item keeps its quote and, with a /, is still a path (as before)" \
  'files="lib/a.sh
' "$FL
"
FL=$(fl_read 'Files: (("lib/a.sh"))')
expect_contains "FILES-LIST21 only ONE pair is stripped: the outer parentheses go, the rest is judged" \
  'files=("lib/a.sh")
' "$FL
"
FL=$(fl_read 'Files: (the usual files)')
expect_eq "FILES-LIST22 a pair around prose is stripped and the prose is still refused, once" "1" "$(fl_findings "$FL")"
expect_contains "FILES-LIST22 …naming the prose bare" "finding: Files: the usual files is not a path" "$FL"
FL=$(fl_read 'Files: "Makefile", (README)')
expect_contains "FILES-LIST23 a wrapped bare word is named bare, with its ./ spelling" \
  "finding: Files: names Makefile, not a path | spell it ./Makefile" "$FL"
FL=$(fl_read 'Files: lib/a.sh;  # one file')
expect_contains "FILES-LIST24 a trailing ; before a comment is stripped too" "files=lib/a.sh
" "$FL
"
FL=$(fl_read 'Files: `"lib/a.sh"`')
expect_contains "FILES-LIST25 a backtick pair is the one pair: what is inside it is judged as it stands" 'files="lib/a.sh"
' "$FL
"
expect_eq "FILES-ENTRY a quoted path answers 0, as the reader records it" "lib/a.sh rc=0" "$(fe '"lib/a.sh"')"
expect_eq "FILES-ENTRY …and a path with a trailing ; likewise" "lib/a.sh rc=0" "$(fe 'lib/a.sh;')"

# --- T49-B1: a reader writes one record per question, so its brief names a record for each (wave-27
# T49, A-orch-83; review pass 28 B1). `proof-add review` takes a record only if it is the reader's
# own row deliverable= or one of its files=, so the wall counts the DISTINCT paths of the Expected
# artifact: and the Files: line (a quoted path as its stripped form, a leading ./ aside) against the
# questions the Questions: line names, and refuses fewer.
B1_DIR=.bionic/docs/record/w
B1_ADV="$B1_DIR/crit-adversarial.md"; B1_STR="$B1_DIR/crit-structure.md"; B1_EVI="$B1_DIR/crit-evidence.md"
b1_brief() {  # <artifact> <questions> [<files line>] -> a read-only reader brief
  printf 'Your task: read the wave-99 change.\nExpected artifact: %s\nExpected duration: ~30 minutes.\nSuites: %s\nQuestions: %s' "$1" "${B1_SUITES:-tests/widget.test.sh}" "$2"
  [ -n "${3:-}" ] && printf '\n%s' "$3"
  return 0
}
q49_gate b1a bionic:auditor double "$(b1_brief "$B1_EVI" evidence)"
expect_eq "T49-B1 double: an auditor with one question and one Expected artifact, no Files:, is admitted" "allow:evidence" "$R"
q49_gate b1b bionic:critic double "$(b1_brief "$B1_ADV" 'adversarial, structure')"
expect_contains "T49-B1 double: a critic dealt two questions with one record and no Files: is refused" "deny:" "$R"
expect_contains "T49-B1 …the first line says it is dealt 2 questions and names 1 record" "dealt 2 questions, names 1 record" "$R"
expect_contains "T49-B1 …and its fix lists one record per question under Files:" "one Files: record per question" "$R"
B1_DETAIL="$GATE_VERR"
expect_contains "T49-B1 …the detail says a reader writes one record per question" "one record per question" "$B1_DETAIL"
expect_contains "T49-B1 …and that the fact verb takes a record only from the reader's own row" "proof-add" "$B1_DETAIL"
q49_gate b1c bionic:critic double "$(b1_brief "$B1_ADV" 'adversarial, structure' "Files: $B1_ADV, $B1_STR")"
expect_eq "T49-B1 …the same with Files: naming both records (the artifact repeated counts once) is admitted" "allow:adversarial,structure" "$R"
expect_eq "T49-B1 …and the row records deliverable= and files= as today" "$B1_ADV|$B1_ADV,$B1_STR" \
  "$(roster_field "$(q_row "$REPO")" deliverable)|$(roster_field "$(q_row "$REPO")" files)"
q49_gate b1d bionic:critic single "$(b1_brief "$B1_ADV" 'evidence, adversarial, structure' "Files: $B1_ADV, $B1_STR, $B1_EVI")"
expect_eq "T49-B1 single: three questions and three distinct record paths are admitted" "allow:evidence,adversarial,structure" "$R"
q49_gate b1e bionic:critic single "$(b1_brief "$B1_ADV" 'evidence, adversarial, structure' "Files: $B1_ADV, $B1_STR")"
expect_contains "T49-B1 …two of three is refused" "dealt 3 questions, names 2 records" "$R"
q49_gate b1f bionic:critic double "$(b1_brief "$B1_ADV" 'adversarial, structure' "Files: \"$B1_ADV\", [$B1_STR]")"
expect_eq "T49-B1 a quoted and a bracketed path count as their stripped forms" "allow:adversarial,structure" "$R"
expect_eq "T49-B1 …and the row holds the stripped paths" "$B1_ADV,$B1_STR" "$(roster_field "$(q_row "$REPO")" files)"
q49_gate b1g bionic:critic double "$(b1_brief "$B1_ADV" 'adversarial, structure' "Files: ./$B1_ADV")"
expect_contains "T49-B1 the artifact repeated with a leading ./ is the same path: refused" "dealt 2 questions, names 1 record" "$R"
# no bound plan: the label is required and the set is not checked, but the count needs no dealing
REPO=$(q_unbound rb1h)
q_gate "$REPO" b1h bionic:critic "$(b1_brief "$B1_ADV" 'adversarial, structure')"
expect_eq "T49-B1 no bound plan: two questions and one record are refused too" "deny" "$GATE_VERDICT"
expect_contains "T49-B1 …saying so" "dealt 2 questions, names 1 record" "$GATE_ERR"
REPO=$(q_unbound rb1i)
q_gate "$REPO" b1i bionic:critic "$(b1_brief "$B1_ADV" 'adversarial, structure' "Files: $B1_STR")"
expect_eq "T49-B1 …and with a Files: record for the second it is admitted" "allow" "$GATE_VERDICT"
# the longest role and three questions: the first line fits the budget (the auditor, since the reviewer is retired)
REPO=$(q_unbound rb1j)
q_gate "$REPO" b1j bionic:auditor "$(b1_brief "$B1_ADV" 'evidence, adversarial, structure')"
B1_LINE=$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')
expect_contains "T49-B1 bionic:auditor with three questions and one record is refused" "dealt 3 questions, names 1 record" "$B1_LINE"
expect_eq "T49-B1 …its first line fits 100 columns" "ok" "$([ "$(bionic_cols "$B1_LINE")" -le 100 ] && echo ok || echo "wide:$(bionic_cols "$B1_LINE")")"
# every other role is untouched
REPO=$(make_repo rb1k yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" b1k bionic:implementor "$(b1_brief "$B1_ADV" 'adversarial, structure')"
expect_eq "T49-B1 a writer carrying two questions and one record is not judged by the count" "allow" "$GATE_VERDICT"
# a Files: line on a read-only role changes nothing else: no writer slot, no worktree demand, no derivation
REPO=$(ro_budget_repo rb1l "writers=1 suites=9 worktrees=9 test_jobs=4 source=user")
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(B1_SUITES=none b1_brief "$B1_ADV" 'adversarial, structure' "Files: $B1_ADV, $B1_STR")" "b1l-r" "claude-sonnet-5" "$RO_NONE" "bionic:critic")"
expect_eq "T49-B1 a critic with a Files: line is admitted" "allow" "$GATE_VERDICT"
B1_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_eq "T49-B1 …its row holds both records in files=" "$B1_ADV,$B1_STR" "$(roster_field "$B1_ROW" files)"
expect_eq "T49-B1 …and a waived budget, nothing derived from Files:" "none" "$(roster_field "$B1_ROW" suites_allowed)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "b1l-w" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "T49-B1 …it holds no writer slot: a writer is admitted beside it at writers=1" "allow" "$GATE_VERDICT"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "b1l-w2" "claude-sonnet-5" "$RO_NONE" "implementor")"
expect_eq "T49-B1 …and a second writer is refused (the control: the slot is the writer's)" "deny" "$GATE_VERDICT"

# --- T57 (review pass 35, A-orch-97): the reader's run cap has no way round ----------------------
# B1: housekeeping is a command holding none of `;`, `&`, `|`, backquote, `$(`, `<(`, `>(` or a line
# break whose first word is on the list; anything else is a run, so a lone `&` no longer hides one.
# N4: for a reader dealt evidence the cap of three is on the TOTAL, suites under Suites: plus counted
# runs. N7: such a reader that declares nothing to re-execute is refused with its own reason. N1: a
# reader's records are counted only among paths under the record root, in resolved form.
t57_counts() {  # <run> -> 0 when the cap counts it, 1 when it is housekeeping (dp_run_counts)
  bash -c '. "$1" || exit 9; dp_run_counts "$2"; echo $?' _ "$Q_LIB" "$1" 2>&1
}
expect_eq "T57-B1 rm -rf dist is housekeeping (the positive beside the rows below)" "1" "$(t57_counts 'rm -rf dist')"
expect_eq "T57-B1 rm -rf dist & pytest is a run" "0" "$(t57_counts 'rm -rf dist & pytest')"
expect_eq "T57-B1 a trailing & alone makes rm -rf dist & a run (the rule is the character)" "0" "$(t57_counts 'rm -rf dist &')"
expect_eq "T57-B1 rm x <(pytest) is a run" "0" "$(t57_counts 'rm x <(pytest)')"
expect_eq "T57-B1 rm x >(pytest) is a run" "0" "$(t57_counts 'rm x >(pytest)')"
expect_eq "T57-B1 a command holding a line break is a run" "0" "$(t57_counts 'mv a b
pytest')"
T57_R3=('bash tests/a.test.sh' 'bash tests/b.test.sh' 'bash tests/c.test.sh')
for T57_HIDE in 'rm -rf dist & pytest' 'mkdir -p x & bash tests/run.sh' 'cp a b & npm test' 'rm -rf dist &'; do
  V=$(q_lib_verdict bionic:auditor "$(q_span evidence none "${T57_R3[@]}" "$T57_HIDE")")
  expect_contains "T57-B1 three runs and '$T57_HIDE' are four: refused on the cap" "exceeds the 3-run cap" "$V"
  expect_contains "T57-B1 …the first line naming the total" "the total of 4 runs" "$V"
done
V=$(q_lib_verdict bionic:critic "$(q_span 'evidence, adversarial, structure' none "${T57_R3[@]}" 'cp a b & npm test')")
expect_contains "T57-B1 a critic holding evidence: cp a b & npm test as a fourth is refused on the cap" "the total of 4 runs exceeds the 3-run cap" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf dist & pytest')")
expect_contains "T57-B1 rm -rf dist & pytest alone is one run: admitted" "rc=0" "$V"
expect_absent "T57-B1 …with no finding" "finding:" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf a & pytest t1' 'rm -rf b & pytest t2' 'rm -rf c & pytest t3' 'rm -rf d & pytest t4' 'rm -rf e & pytest t5' 'rm -rf f & pytest t6')")
expect_contains "T57-B1 six runs each behind & are refused on the cap" "the total of 6 runs exceeds the 3-run cap" "$V"
expect_absent "T57-B1 …never as a reader with nothing to re-execute" "nothing to re-execute" "$V"
expect_absent "T57-B1 …nor in the old words" "names no suites" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf dist' 'mkdir -p out' 'cp a b' 'bash tests/a.test.sh' 'bash tests/b.test.sh' 'bash tests/c.test.sh')")
expect_contains "T57-B1 housekeeping without & stays free: three runs and three cleanups are admitted" "rc=0" "$V"

# the review's p8.sh briefs, end to end at the wall
t57_brief() {  # <questions> <fourth run> [<extra line>]
  printf 'Your task: re-run the evidence.\nExpected artifact: .bionic/docs/record/w/e.md\nExpected duration: ~30 minutes.\nQuestions: %s\nSuites: none\nRe-executes: %sbash tests/a.test.sh%s, %sbash tests/b.test.sh%s, %sbash tests/c.test.sh%s, %s%s%s' \
    "$1" "$RL_BT" "$RL_BT" "$RL_BT" "$RL_BT" "$RL_BT" "$RL_BT" "$RL_BT" "$2" "$RL_BT"
  [ -n "${3:-}" ] && printf '\n%s' "$3"
  return 0
}
q49_gate t57a bionic:auditor double "$(t57_brief evidence 'rm -rf dist & pytest')"
expect_contains "T57-B1 double auditor, fourth run rm -rf dist & pytest: refused at the wall" "deny:" "$R"
expect_contains "T57-B1 …on the cap, naming the total" "the total of 4 runs exceeds the 3-run cap" "$R"
q49_gate t57b bionic:auditor double "$(t57_brief evidence 'mkdir -p x & bash tests/run.sh')"
expect_contains "T57-B1 double auditor, fourth run mkdir -p x & bash tests/run.sh: refused on the cap" "exceeds the 3-run cap" "$R"
q49_gate t57c bionic:critic single "$(t57_brief 'evidence, adversarial, structure' 'cp a b & npm test' 'Files: .bionic/docs/record/w/e.md, .bionic/docs/record/w/f.md, .bionic/docs/record/w/g.md')"
expect_contains "T57-B1 single critic holding evidence, fourth run cp a b & npm test: refused on the cap" "exceeds the 3-run cap" "$R"
q49_gate t57d bionic:auditor double "$(t57_brief evidence 'pytest')"
expect_contains "T57-B1 …the control: a plain fourth run is refused the same way" "the total of 4 runs exceeds the 3-run cap" "$R"

# N4: the total. Suites: names count toward the three.
V=$(q_lib_verdict bionic:auditor "$(q_span evidence 'tests/a.test.sh, tests/b.test.sh, tests/c.test.sh, tests/d.test.sh')")
expect_contains "T57-N4 four suites and no Re-executes: are refused: the total is four" "the total of 4 runs exceeds the 3-run cap" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence 'tests/a.test.sh, tests/b.test.sh, tests/c.test.sh' 'pytest x')")
expect_contains "T57-N4 three suites and one run are refused" "the total of 4 runs exceeds the 3-run cap" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence 'tests/a.test.sh, tests/b.test.sh, tests/c.test.sh' 'pytest x' 'pytest y' 'pytest z')")
expect_contains "T57-N4 three suites and three runs name the total of six" "the total of 6 runs exceeds the 3-run cap" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence 'tests/a.test.sh, tests/b.test.sh' 'pytest x')")
expect_contains "T57-N4 two suites and one run, three in total, are admitted" "rc=0" "$V"
expect_absent "T57-N4 …with no finding" "finding:" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'pytest x' 'pytest y' 'pytest z')")
expect_contains "T57-N4 three runs and Suites: none are admitted" "rc=0" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence 'tests/a.test.sh, tests/b.test.sh, tests/c.test.sh' 'rm -rf dist')")
expect_contains "T57-N4 three suites and a housekeeping command are admitted: housekeeping is free" "rc=0" "$V"
V=$(q_lib_verdict bionic:critic "$(q_span adversarial 'tests/a.test.sh, tests/b.test.sh, tests/c.test.sh, tests/d.test.sh' 'pytest x')")
expect_contains "T57-N4 a critic not dealt evidence is not held to three" "rc=0" "$V"
V=$(q_lib_verdict implementor "$(q_span evidence 'tests/a.test.sh, tests/b.test.sh, tests/c.test.sh, tests/d.test.sh' 'pytest x' 'pytest y' 'pytest z' 'rm -rf d & pytest')")
expect_contains "T57 a writer is untouched by every rule here: four suites and four runs are admitted" "rc=0" "$V"
expect_absent "T57 …with no finding" "finding:" "$V"
REPO=$(q_unbound rt57w)
q_gate "$REPO" t57w bionic:auditor "Your task: re-run.
Expected artifact: .bionic/docs/record/w/e.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: tests/a.test.sh, tests/b.test.sh, tests/c.test.sh, tests/d.test.sh"
T57_LINE=$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')
expect_contains "T57-N4 at the wall: an auditor reading evidence with four suites is refused on the total" "the total of 4 runs exceeds the 3-run cap" "$T57_LINE"
# each further digit of the total is one column: 94 at one digit leaves room for a total of seven
expect_eq "T57-N4 …its first line fits with room for six more digits" "ok" "$([ "$(bionic_cols "$T57_LINE")" -le 94 ] && echo ok || echo "wide:$(bionic_cols "$T57_LINE")")"

# N7: a reader dealt evidence that declares nothing to re-execute
V=$(q_lib_verdict bionic:auditor "Questions: evidence
Re-executes: ${RL_BT}rm -rf dist${RL_BT}")
expect_contains "T57-N7 an auditor with no Suites: line and only rm -rf dist is refused" "finding: the auditor declares nothing to re-execute" "$V"
expect_absent "T57-N7 …not in the old words" "names no suites" "$V"
V=$(q_lib_verdict bionic:auditor "$(q_span evidence none 'rm -rf dist')")
expect_contains "T57-N7 the same brief with Suites: none: the same refusal" "finding: the auditor declares nothing to re-execute" "$V"
V=$(q_lib_verdict bionic:critic "$(q_span 'evidence, adversarial, structure' none 'rm -rf dist')")
expect_contains "T57-N7 a critic holding evidence is held the same" "finding: the critic declares nothing to re-execute" "$V"
V=$(q_lib_verdict bionic:auditor "Questions: evidence
Re-executes: ${RL_BT}pytest${RL_BT}")
expect_contains "T57-N7 …while one run and no Suites: line admit it (the positive)" "rc=0" "$V"
V=$(q_lib_verdict bionic:critic "$(q_span structure none)")
expect_contains "T57-N7 a reader not dealt evidence with Suites: none and no runs is untouched" "rc=0" "$V"
expect_absent "T57-N7 …with no finding" "finding:" "$V"
V=$(q_lib_verdict implementor "$(q_span evidence none 'rm -rf dist')")
expect_contains "T57-N7 a writer with Suites: none and only housekeeping is untouched" "rc=0" "$V"
REPO=$(make_repo rt57n yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" t57n bionic:auditor "Your task: re-run.
Expected artifact: .bionic/docs/record/w/e.md
Expected duration: ~30 minutes.
Questions: evidence
Re-executes: ${RL_BT}rm -rf dist${RL_BT}"
expect_eq "T57-N7 at the wall: the auditor with no Suites: line and only rm -rf dist is refused" "deny" "$GATE_VERDICT"
expect_contains "T57-N7 …saying it declares nothing to re-execute" "the auditor declares nothing to re-execute" "$GATE_ERR"
REPO=$(q_unbound rt57m)
q_gate "$REPO" t57m bionic:auditor "Your task: re-run.
Expected artifact: .bionic/docs/record/w/e.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: none"
T57_LINE=$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')
expect_contains "T57-N7 the longest role: an auditor reading evidence with nothing to re-execute" "the auditor declares nothing to re-execute" "$T57_LINE"
expect_eq "T57-N7 …its first line fits 100 columns" "ok" "$([ "$(bionic_cols "$T57_LINE")" -le 100 ] && echo ok || echo "wide:$(bionic_cols "$T57_LINE")")"
REPO=$(make_repo rt57r yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" t57r bionic:critic "Your task: read.
Expected artifact: .bionic/docs/record/w/e.md
Expected duration: ~30 minutes.
Questions: adversarial, structure
Files: .bionic/docs/record/w/e.md, .bionic/docs/record/w/f.md
Suites: none"
expect_eq "T57-N7 at the wall: a critic at double (not dealt evidence) with Suites: none is admitted" "allow" "$GATE_VERDICT"

# N1: a record is a path under the record root, in resolved form
T57_D=.bionic/docs/record/w
for T57_F in .bionic/tmp/scratch/x/progress.md hooks/a.sh "$T57_D/" ../elsewhere/b.md /tmp/b.md "$T57_D/x/../a.md" .bionic//docs/record/w/a.md; do
  q49_gate "t57-n1-$(printf '%s' "$T57_F" | tr -c 'a-z0-9' '_')" bionic:critic double "$(b1_brief "$T57_D/a.md" 'adversarial, structure' "Files: $T57_F")"
  expect_contains "T57-N1 Files: $T57_F beside the artifact leaves one record: refused" "dealt 2 questions, names 1 record" "$R"
done
q49_gate t57-n1-real bionic:critic double "$(b1_brief "$T57_D/a.md" 'adversarial, structure' "Files: $T57_D/b.md")"
expect_eq "T57-N1 Files: naming a second record under the root: two, admitted" "allow:adversarial,structure" "$R"
q49_gate t57-n1-scr bionic:critic double "$(b1_brief "$T57_D/a.md" 'adversarial, structure' "Files: $T57_D/b.md, .bionic/tmp/scratch/x/progress.md")"
expect_eq "T57-N1 a scratch file beside two real records is admitted" "allow:adversarial,structure" "$R"
expect_eq "T57-N1 …and stays on the row's files=" "$T57_D/b.md,.bionic/tmp/scratch/x/progress.md" "$(roster_field "$(q_row "$REPO")" files)"
q49_gate t57-n1-one bionic:auditor double "$(b1_brief hooks/out.md evidence)"
expect_contains "T57-N1 an artifact outside the record root is no record: one question, none named" "dealt 1 question, names 0 records" "$R"

# S1, S2: two rows that could not fail
q49_gate t57-s1 bionic:critic double "$(b1_brief "$B1_ADV" 'adversarial, structure' "Files: \"$B1_ADV\"")"
expect_contains "T57-S1 the artifact repeated in quotes as the only Files: entry is one record: refused" "dealt 2 questions, names 1 record" "$R"
q49_gate t57-s2 bionic:auditor double "Your task: read the wave-99 change.
Expected artifact: .bionic/docs/record/wq-s2.md
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh

    Questions: evidence"
expect_eq "T57-S2 an indented Questions: line after a blank line is the label" "allow:evidence" "$R"
q49_gate t57-s2b bionic:auditor double "    Your task: read the wave-99 change.
    Expected artifact: .bionic/docs/record/wq-s2b.md
    Expected duration: ~30 minutes.
    Suites: tests/widget.test.sh
    Questions: evidence"
expect_eq "T57-S2 …and so is one in a brief indented whole" "allow:evidence" "$R"

# N2: twelve Questions: lines
T57_DUP="Your task: read.
Expected artifact: .bionic/docs/record/w/e.md
Expected duration: ~30 minutes."
for _t57 in $(seq 1 100); do T57_DUP="$T57_DUP
filler line $_t57"; done
T57_DUP="$T57_DUP
Suites: none"
for _t57 in $(seq 1 12); do T57_DUP="$T57_DUP
Questions: structure"; done
REPO=$(q_unbound rt57q)
q_gate "$REPO" t57q bionic:critic "$T57_DUP"
T57_LINE=$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')
expect_contains "T57-N2 twelve Questions: lines: the first line says twelve" "bionic:critic has 12 Questions: lines" "$T57_LINE"
T57_NUMS=$(printf '%s\n' "$GATE_VERR" | /usr/bin/grep -m1 'on lines ' | sed 's/.*on lines //; s/:$//')
expect_contains "T57-N2 …the detail lists the line numbers from the first" "105, 106" "$T57_NUMS"
T57_BAD=""
expect_contains "T57-N2 …and says how many more the cut list left out" "114 and 2 more" "$T57_NUMS"
for _t57 in $(printf '%s' "$T57_NUMS" | sed 's/ and [0-9]* more$//' | tr ',' ' ' | sed 's/ and / /g'); do
  case "$_t57" in [0-9]*) [ "$_t57" -ge 105 ] && [ "$_t57" -le 116 ] || T57_BAD="$T57_BAD $_t57" ;; *) : ;; esac
done
expect_eq "T57-N2 …and every number it prints is a whole line number of a Questions: line" "" "$T57_BAD"

# N6: the fixture guard (beside make_repo). Driven in a subshell, so its lost state stays there.
T57_G=$(make_repo() { return 1; }
  X=$(make_repo rt57lost yes)
  run_gate "$(mk_agent_payload "$SID_A" "$X")"
  printf '%s|%s|%s' "$X" "$FIXTURE_LOST" "$GATE_VERDICT")
expect_eq "T57-N6 a make_repo that made nothing hands its taker a path inside the sandbox, and the wall is not run" \
  "$SANDBOX/.lost/X-1|X=\$(make_repo rt57lost yes)|fixture-lost" "$T57_G"
T57_G=$(make_repo() { :; }
  X=$(make_repo rt57empty yes)
  run_gate "$(mk_agent_payload "$SID_A" "$X")"
  printf '%s|%s|%s' "$X" "$FIXTURE_LOST" "$GATE_VERDICT")
expect_eq "T57-N6 …and an empty answer that exits 0 is caught at the take, into the sandbox, too" \
  "$SANDBOX/.lost/X-1|X=\$(make_repo rt57empty yes)|fixture-lost" "$T57_G"
T57_G=$(FIXTURE_LOST="X=\$(make_repo gone yes)"; ok "a row after a lost fixture")
expect_contains "T57-N6 …while a fixture is lost, a row that would pass fails by its own name" "FAIL: a row after a lost fixture" "$T57_G"
REPO=$(make_repo rt57made yes)
expect_eq "T57-N6 a made fixture leaves nothing lost (the positive)" "|ok" "$FIXTURE_LOST|$(git -C "$REPO" rev-parse -q --verify HEAD >/dev/null && echo ok)"

# N1 (A-orch-101): an ABSOLUTE path is resolved as proof-add resolves it, its longest existing
# directory physically and the rest in the text. The sandbox is spelt as the shell spells it (on
# macOS /var/…), while the project root the wall reads is the physical one (/private/var/…).
t57_abs_gate() {  # <tag> <role> <rigor> <artifact> [<files line>] -> R, as q49_gate's
  local repo; repo=$(make_repo "rt57-$1" yes); write_attestation "$repo" "$SID_A"; q_rigor "$repo" "$3"
  mkdir -p "$repo/.bionic/docs/record/w/real" "$SANDBOX/rt57-$1-elsewhere"
  ln -s "$SANDBOX/rt57-$1-elsewhere" "$repo/.bionic/docs/record/w/out"
  local brief="Your task: read.
Expected artifact: ${4//@R@/$repo}
Expected duration: ~30 minutes.
Suites: tests/widget.test.sh
Questions: ${T57_QS:-evidence}"
  [ -n "${5:-}" ] && brief="$brief
${5//@R@/$repo}"
  REPO="$repo"; q_gate "$repo" "t57-$1" "$2" "$brief"
  if [ "$GATE_VERDICT" = allow ]; then R="allow:$(roster_field "$(q_row "$repo")" questions)"
  else R="deny:$(printf "%s\n" "$GATE_ERR" | /usr/bin/grep -m1 "bionic: dispatch refused")"; fi
}
t57_abs_gate abs1 bionic:auditor double "@R@/.bionic/docs/record/w/a.md"
expect_eq "T57-N1 the exam's shape: a record by its absolute path as the shell spells the project is counted" "allow:evidence" "$R"
T57_QS='adversarial, structure' t57_abs_gate abs2 bionic:critic double "@R@/.bionic/docs/record/w/a.md" "Files: @R@/.bionic/docs/record/w/b.md"
expect_eq "T57-N1 …and two such records are two" "allow:adversarial,structure" "$R"
T57_QS='adversarial, structure' t57_abs_gate abs3 bionic:critic double "@R@/.bionic/docs/record/w/a.md" "Files: @R@/.bionic/docs/record/w/out/b.md"
expect_contains "T57-N1 an absolute path through a symlinked directory that lands outside the record root is no record" "dealt 2 questions, names 1 record" "$R"
T57_QS='adversarial, structure' t57_abs_gate abs4 bionic:critic double "@R@/.bionic/docs/record/w/a.md" "Files: @R@/.bionic/docs/record/new/deep/b.md"
expect_eq "T57-N1 a path whose directories do not exist yet under a real record root is counted" "allow:adversarial,structure" "$R"
expect_eq "T57-N1 …and the fixture really has no such directory" "absent" "$([ -e "$REPO/.bionic/docs/record/new" ] && echo present || echo absent)"
# one rule for every path (A-T57.11 ruling): a RELATIVE path is anchored at the project root and
# then placed as an absolute one is, so the wall never counts a record the fact verb would refuse
T57_QS='adversarial, structure' t57_abs_gate rel1 bionic:critic double ".bionic/docs/record/w/a.md" "Files: .bionic/docs/record/w/out/b.md"
expect_contains "T57-N1 a relative path through a symlinked directory that lands outside the record root is no record" "dealt 2 questions, names 1 record" "$R"
T57_QS='adversarial, structure' t57_abs_gate rel2 bionic:critic double ".bionic/docs/record/w/a.md" "Files: .bionic/docs/record/w/real/b.md"
expect_eq "T57-N1 …while the same path through a real directory is counted (the control)" "allow:adversarial,structure" "$R"

# a reader's Files: names no suite (review pass 38 B1, A-orch-105).
T57_REC=.bionic/docs/record/w
t57_rd() {  # <questions> <files line> [<suites line>] [<runs line>] -> a reader brief
  printf 'Your task: re-run the evidence.\nExpected artifact: %s/e.md\nExpected duration: ~30 minutes.\nQuestions: %s\n%s' "$T57_REC" "$1" "$2"
  [ -n "${3:-}" ] && printf '\n%s' "$3"
  [ -n "${4:-}" ] && printf '\n%s' "$4"
  return 0
}
T57_PY="Re-executes: ${RL_BT}pytest tests/${RL_BT}"
q49_gate t57-d1 bionic:auditor double "$(t57_rd evidence "Files: $T57_REC/e.md" '' "$T57_PY")"
expect_eq "T57-D an auditor with Files: naming its record, no Suites: line and a pytest run is admitted" "allow:evidence" "$R"
expect_eq "T57-D …its row reads the waiver: suites_allowed=none" "none" "$(roster_field "$(q_row "$REPO")" suites_allowed)"
q49_gate t57-d2 bionic:critic single "$(t57_rd 'evidence, adversarial, structure' "Files: $T57_REC/e.md, $T57_REC/f.md, $T57_REC/g.md" '' "$T57_PY")"
expect_eq "T57-D a single critic with its three records on Files: and a pytest run is admitted" "allow:evidence,adversarial,structure" "$R"
q49_gate t57-d3 bionic:auditor double "$(t57_rd evidence "Files: $T57_REC/e.md" 'Suites: none' "$T57_PY")"
expect_eq "T57-D …the same with Suites: none beside the run, as today" "allow:evidence" "$R"
q49_gate t57-d4 bionic:auditor double "$(t57_rd evidence "Files: $T57_REC/e.md")"
expect_contains "T57-D an auditor with Files: and no Suites: line and no run is refused: nothing to re-execute" "the auditor declares nothing to re-execute" "$R"
expect_absent "T57-D …never the Files-alone refusal" "names no suite" "$R"
q49_gate t57-d5 bionic:critic double "$(t57_rd 'adversarial, structure' "Files: $T57_REC/e.md, $T57_REC/f.md")"
expect_eq "T57-D a critic not dealt evidence with its records on Files: and no Suites: line is admitted" "allow:adversarial,structure" "$R"
REPO=$(make_repo rt57d6 yes); write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: write it.
Expected artifact: $T57_REC/w.md
Expected duration: ~30 minutes.
Files: lib/a.sh" "t57-d6" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "implementor")"
expect_eq "T57-D a writer with Files: and no Suites: line is refused as today (the control)" "deny" "$GATE_VERDICT"
expect_contains "T57-D …on the Files-alone refusal" "Files: alone names no suite" "$GATE_ERR"
T57_IMP="$SANDBOX/t57-impact"; mkdir -p "$T57_IMP/.bionic"
printf 'printf "x.test.sh\\tlib/a.sh\\n"\n' > "$T57_IMP/impact-stub.sh"
printf 'impact-command: bash %s/impact-stub.sh\n' "$T57_IMP" > "$T57_IMP/.bionic/config.yaml"
BV=$(brief_verdict implementor "$T57_IMP" "Files: lib/a.sh")
expect_contains "T57-D beside a stale impact-command: line, a writer's Files: is refused all the same" "finding: Files: alone names no suite" "$BV"
BV=$(brief_verdict bionic:auditor "$T57_IMP" "Questions: evidence
Files: $T57_REC/e.md
$T57_PY")
expect_contains "T57-D …while an auditor's records derive nothing: its set is the waiver" "suites=none" "$BV"
expect_contains "T57-D …and it is admitted" "rc=0" "$BV"



finish
