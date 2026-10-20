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

finish
