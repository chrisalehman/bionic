#!/bin/bash
# Tests for hooks/session-poker.sh — shard 4 of 4: §SEV to the end.
#
# THE SUITE IS FOUR SHARDS (wave-30 T2; design-ledger Δ7, D8). Its governing design, its
# hermetic posture and its clock discipline are written once, in tests/session-poker.test.sh's
# header; the sandbox, the pins and the shared fixture builders are
# tests/session-poker.prelude.sh, sourced below after the framework and the POKER seam.
#
# SPLIT WHERE NO FIXTURE CROSSES. §SEV builds the repository nine later sections read:
# §RC-DEFER, §CHECK, §MOVE, §REPORT-RTL, §REPORT-KEY, §PASS-KEY, §PASS-MOVED, §MOVE-PASTED and
# §STEP-FIELD (writers). The sections between them export the config and home directories the
# next ones run under, so this shard keeps them all, in order, to the end.
#
# Usage: bash tests/session-poker-4.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

# THE SEAM, exactly as tests/session-poker.test.sh offers it, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker-4.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

# THE FILES THIS SHARD'S HOISTED HELPERS READ, NAMED HERE. tests/lib/impact.sh maps a suite
# from its own lines and never follows it into the prelude, so a path a prelude helper
# reads is named by every shard that calls that helper.
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

# ============================================================
section "§SEV §FACT-rate §FACT-table §FACT-derive §FACT-shown §FACT-old §CUR8-sev: a reading pushed the severity scale carries each finding's severity and reach, and the tool derives the priority and the verdict (wave-28 T15; REQ-8 AC-8.1, AC-8.3, AC-8.4, AC-8.5, AC-8.6, AC-8.8; D19)"
# ============================================================
#
# When the reader's roster row carries `severity` in `pushed=` (the context files the recorder
# pushed at start), `proof-add review <record> --question <q> --reader <name>` requires the
# record's `findings: <n>`, that many `finding: <n> <S1-S4> <on|off> <path>:<line>|- <title>`
# lines, and for each finding the table sends to fix a `<path>:<line>` with a `shown: <n> <command>`
# line or an `unsure: <n> <what>` line. The result is derived (a finding to fix gives fail, any
# other finding flag, none pass) and a `result:` that differs is refused, as is a written
# `priority:` the table does not give. Registration writes `deferred:` for each finding the table
# defers and `check:` for each unsure one inside `## SDLC State`, after the proof line. A reader
# with no `severity` push registers as 1.12.0 did.
#
# FIXTURE FIDELITY. §56's shape: a plan bound to this session, its working branch checked out in a
# linked worktree, real commits, and roster rows from the production writer (`roster_row_fixture`)
# with `questions=` and `pushed=` appended by hand. `pushed=` is the Interfaces table's key, which
# row T16 teaches the recorder to write; the verb reads it off the line by key, as it reads
# `questions=` (A-orch-9).
SEV_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
SEV_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
RSEV="$(make_repo sev-fact)"; ( cd "$RSEV" && git commit -q --allow-empty -m init )
git -C "$RSEV" config user.name "Dana Fixture"
SEV_B="$(git -C "$RSEV" rev-parse HEAD)"
PSEV="$(s42_plan "$RSEV" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${SEV_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PSEV" > "$PSEV.tmp" && mv "$PSEV.tmp" "$PSEV"
s42_builds_landed "$PSEV"
( cd "$RSEV" && git add -f "$PSEV" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RSEV/.worktrees/01-fixture" "$SEV_B" ) >/dev/null 2>&1
SEV_WT="$RSEV/.worktrees/01-fixture"
SEV_C1="$(s57_commit "$SEV_WT" lib/a.sh C1)"
SEV_DIR="$RSEV/.bionic/docs/record/wave-01-fixture"; mkdir -p "$SEV_DIR"
SEV_RECS="r-ok r-nosev r-noreach r-s5 r-maybe r-count r-none r-twice r-where r-pri-bad r-pri-ok
t-S1-on t-S1-off t-S2-on t-S2-off t-S3-on t-S3-off t-S4-on t-S4-off
d-fix-flag d-defer-fail d-none-flag d-none-pass sh-dash sh-noshown sh-unsure sh-defer-unsure c-fix c-later"
SEV_OLDRECS="o-fail o-findings o-nopush"
sev_files() { local o="" n; for n in $1; do o="${o:+$o,}.bionic/docs/record/wave-01-fixture/$n.md"; done; printf '%s' "$o"; }
SEV_RS="$(roster_of "$RSEV")"; new_roster "$RSEV"
roster_row_fixture session="$SID" name=implementor agent_id=a-implementor subagent_type=implementor >> "$SEV_RS"
printf '%s|questions=adversarial|pushed=checks-adversarial,severity\n' \
  "$(roster_row_fixture session="$SID" name=sev-crit agent_id=a-sev-crit subagent_type=bionic:critic files="$(sev_files "$SEV_RECS")")" >> "$SEV_RS"
printf '%s|questions=adversarial\n' \
  "$(roster_row_fixture session="$SID" name=old-crit agent_id=a-old-crit subagent_type=bionic:critic files="$(sev_files "o-fail o-findings")")" >> "$SEV_RS"
printf '%s|questions=adversarial|pushed=checks-adversarial\n' \
  "$(roster_row_fixture session="$SID" name=nosev-crit agent_id=a-nosev-crit subagent_type=bionic:critic files="$(sev_files "o-nopush")")" >> "$SEV_RS"
# sev_rec <file> <result> [<line>...] -> an adversarial piece reading over base..C1 with these lines
sev_rec() {
  local f="$SEV_DIR/$1.md" r="$2" l; shift 2
  { printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: %s\nscope: piece\n' "${SEV_B:0:10}" "$SEV_C1" "$r"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\nwhat the reader found\n'; } > "$f"
}
sev_add() {  # <file> [<reader>] -> registers it through the verb
  poke "$RSEV" proof-add review "record/wave-01-fixture/$1.md" --question adversarial --reader "${2:-sev-crit}"
}
sev_last() { s46_proved "$PSEV" | tail -1; }
sev_lines() { /usr/bin/grep -E '^(deferred|check): ' "$PSEV"; }  # the plan's finding lines
expect_regex "SEV-0 precondition: the working branch's head is C1, a 40-hex commit" '^[0-9a-f]{40}$' "$SEV_C1"
expect_eq "SEV-0b precondition: the reader's row carries the pushed key, read by key" "checks-adversarial,severity" \
  "$(/usr/bin/grep -F '|name=sev-crit|' "$SEV_RS" | tr '|' '\n' | sed -n 's/^pushed=//p')"
s34_gate "$RSEV"
expect_eq "SEV-0c precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- the push is read off the row by key, as questions= is (unit rows) ----------
sev_pushed() {  # <pushed value> -> proof_pushed_severity's rc
  bash -c '. "$1"; proof_pushed_severity "$2"; echo "$?"' _ "$SEV_LIB" "$1" 2>/dev/null
}
expect_eq "SEV-push1 a list naming severity: pushed" "0" "$(sev_pushed checks-adversarial,severity)"
expect_eq "SEV-push1b …the three-entry list the recorder writes for a reader of both code questions: pushed" "0" \
  "$(sev_pushed checks-adversarial,checks-structure,severity)"
expect_eq "SEV-push2 …a list without severity (an evidence reader's): not pushed" "1" "$(sev_pushed checks-evidence)"
expect_eq "SEV-push3 …no key on the row (1.12.0's): not pushed" "1" "$(sev_pushed '')"
expect_eq "SEV-push5 …a name that only contains the word is not it" "1" "$(sev_pushed severity-old)"

# ---------- an amended, extended or held reader row keeps pushed= (row_copy_args; A-orch-9) ----------
# The copy hands the key to `roster_row`, which writes it once row T16 teaches it the key; on a
# tree without T16 the copy leaves it out rather than fail the verb, and these rows are red there.
RSEVA="$(make_repo sev-amend)"; new_roster "$RSEVA"
s30_row "$RSEVA" subagent_type=bionic:critic suites_allowed=none questions=adversarial
awk -v k='|pushed=checks-adversarial,severity' '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) print l[i] (i == NR ? k : "") }' \
  "$(roster_of "$RSEVA")" > "$TMPROOT/sev-amend-roster" && cat "$TMPROOT/sev-amend-roster" > "$(roster_of "$RSEVA")"
expect_eq "SEV-copy0 precondition: the reader's row carries pushed=, read by key" "checks-adversarial,severity" \
  "$(s30_field "$(s30_last "$RSEVA")" pushed)"
poke "$RSEVA" amend w1 --files+ lib/z.sh --reason 'one more file'
expect_eq "SEV-copy the amended reader row carries pushed= from the row it copied (exit 0)" "0|checks-adversarial,severity" \
  "$RC|$(s30_field "$(s30_last "$RSEVA")" pushed)"
expect_eq "SEV-copy2 …beside its questions= (the copy the AMEND-Q rows pin)" "adversarial" "$(s30_field "$(s30_last "$RSEVA")" questions)"
poke "$RSEVA" extend w1 'more to read'
expect_eq "SEV-copy3 extend's row carries pushed= too (exit 0)" "0|checks-adversarial,severity" \
  "$RC|$(s30_field "$(s30_last "$RSEVA")" pushed)"

# ---------- the table: one definition, eight cells (unit rows on the library) ----------
sev_pri() { bash -c '. "$1"; proof_priority "$2" "$3"; echo " rc=$?"' _ "$SEV_LIB" "$1" "$2" 2>/dev/null; }
SEV_CELLS="S1:on:fix S1:off:fix S2:on:fix S2:off:defer S3:on:defer S3:off:note S4:on:note S4:off:note"
for c in $SEV_CELLS; do
  IFS=: read -r s r p <<EOF
$c
EOF
  expect_eq "SEV-pri $s $r gives $p" "$p rc=0" "$(sev_pri "$s" "$r")"
done
expect_eq "SEV-pri-x a severity outside the set has no cell (exit 1)" " rc=1" "$(sev_pri S5 on)"
expect_eq "SEV-pri-y …nor a reach outside the set" " rc=1" "$(sev_pri S2 maybe)"

# ---------- §FACT-rate (AC-8.1): a severity and a reach from the two sets, and the count ----------
sev_rec r-ok flag "findings: 1" "finding: 1 S3 off lib/a.sh:3 a message misnames the flag"
s42_snap "$RSEV" "$PSEV"; sev_add r-ok
expect_eq "SEV-rate0 §FACT-rate a pushed reader's record with one rated finding registers (exit 0)" "0" "$RC"
expect_regex "SEV-rate0b …its proof line carries the result the finding derives" "evidence=record/wave-01-fixture/r-ok.md question=adversarial reader=sev-crit result=flag scope=piece$" "$(sev_last)"
sev_rec r-nosev flag "findings: 1" "finding: 1 off lib/a.sh:3 no severity"
sev_rec r-noreach flag "findings: 1" "finding: 1 S3 lib/a.sh:3 no reach"
sev_rec r-s5 flag "findings: 1" "finding: 1 S5 off lib/a.sh:3 a fifth severity"
sev_rec r-maybe flag "findings: 1" "finding: 1 S3 maybe lib/a.sh:3 a third reach"
sev_rec r-count flag "findings: 2" "finding: 1 S3 off lib/a.sh:3 one of two"
sev_rec r-none fail
sev_rec r-twice flag "findings: 2" "finding: 1 S3 off lib/a.sh:3 one" "finding: 1 S4 off - again"
sev_rec r-where flag "findings: 1" "finding: 1 S3 off lib/a.sh a path with no line"
# Each case is <file>@<what it lacks>@<what the refusal says>.
for c in "r-nosev@no severity@rates finding 1 'off'" "r-noreach@no reach@the reach 'lib/a.sh:3'" \
         "r-s5@a severity outside S1 to S4@rates finding 1 'S5'" "r-maybe@a reach outside on and off@the reach 'maybe'" \
         "r-count@a count that differs from its lines@says findings: 2 but holds 1 finding: lines" \
         "r-none@no findings: line at all@carries no findings: <n> line" "r-twice@a finding numbered twice@gives finding 1 twice" \
         "r-where@a location that is neither path:line nor -@names 'lib/a.sh' where finding 1 takes"; do
  f="${c%%@*}"; rest="${c#*@}"; why="${rest%%@*}"; want="${rest#*@}"
  s42_snap "$RSEV" "$PSEV"; sev_add "$f"
  s42_unchanged "SEV-rate §FACT-rate AC-8.1 a pushed reader's record with $why ($f)" 1 "$PSEV"
  expect_contains "SEV-rate …$f says why" "$want" "$OUT"
done

# ---------- §FACT-table (AC-8.3): each of the eight cells registers with its one outcome ----------
for c in $SEV_CELLS; do
  IFS=: read -r s r p <<EOF
$c
EOF
  case "$p" in
    fix)   sev_rec "t-$s-$r" fail "findings: 1" "finding: 1 $s $r lib/a.sh:7 the $s $r cell" "shown: 1 bash lib/a.sh --cell" ; want=fail ;;
    *)     sev_rec "t-$s-$r" flag "findings: 1" "finding: 1 $s $r - the $s $r cell" ; want=flag ;;
  esac
  sev_add "t-$s-$r"
  expect_eq "SEV-table §FACT-table AC-8.3 $s $r registers (exit 0)" "0" "$RC"
  expect_regex "SEV-table …$s $r: the proof line says result=$want" "evidence=record/wave-01-fixture/t-$s-$r.md .* result=$want scope=piece$" "$(sev_last)"
  sevd="$(/usr/bin/grep -c "^deferred: record/wave-01-fixture/t-$s-$r.md#1 " "$PSEV")"
  case "$p" in
    defer) expect_eq "SEV-table …$s $r: one deferred: line, read back whole" \
             "deferred: record/wave-01-fixture/t-$s-$r.md#1 $s $r \"the $s $r cell\"" \
             "$(/usr/bin/grep "^deferred: record/wave-01-fixture/t-$s-$r.md#1 " "$PSEV")" ;;
    *)     expect_eq "SEV-table …$s $r ($p): no deferred: line (beside the S2 off and S3 on rows that write one)" "0" "$sevd" ;;
  esac
  expect_eq "SEV-table …$s $r: no check: line, for nothing is unsure" "0" "$(/usr/bin/grep -c "^check: record/wave-01-fixture/t-$s-$r.md#" "$PSEV")"
done
expect_eq "SEV-table2 …the deferred: lines sit inside ## SDLC State, after their proof lines" "2" \
  "$(awk '/^## /{ s = ($0 ~ /^## SDLC State/) } s && /^deferred: /{ n++ } END { print n + 0 }' "$PSEV")"
sev_rec r-pri-bad flag "findings: 1" "finding: 1 S2 off - written as fix" "priority: 1 fix"
s42_snap "$RSEV" "$PSEV"; sev_add r-pri-bad
s42_unchanged "SEV-table3 §FACT-table AC-8.3 a record that writes a priority the table does not give (S2 off as fix)" 1 "$PSEV"
expect_contains "SEV-table3b …naming the table's" "writes priority fix for finding 1, but the table gives S2 off defer" "$OUT"
sev_rec r-pri-ok flag "findings: 1" "finding: 1 S2 off - written as the table writes it" "priority: 1 defer"
sev_add r-pri-ok
expect_eq "SEV-table4 …and one that writes the table's own priority registers (exit 0)" "0" "$RC"

# ---------- §FACT-derive (AC-8.4): the verdict follows from the priorities ----------
sev_rec d-fix-flag flag "findings: 1" "finding: 1 S1 on lib/a.sh:2 data lost" "shown: 1 bash lib/a.sh --lose"
sev_rec d-defer-fail fail "findings: 1" "finding: 1 S2 off - a side path broken"
sev_rec d-none-flag flag "findings: 0"
for c in "d-fix-flag@a finding to fix beside result: flag@its findings give fail" \
         "d-defer-fail@no finding to fix beside result: fail@its findings give flag" \
         "d-none-flag@no finding at all beside result: flag@its findings give pass"; do
  f="${c%%@*}"; rest="${c#*@}"; why="${rest%%@*}"; want="${rest#*@}"
  s42_snap "$RSEV" "$PSEV"; sev_add "$f"
  s42_unchanged "SEV-derive §FACT-derive AC-8.4 $why ($f)" 1 "$PSEV"
  expect_contains "SEV-derive …$f names the derived result" "$want" "$OUT"
done
sev_rec d-none-pass pass "findings: 0"
sev_add d-none-pass
expect_eq "SEV-derive2 …findings: 0 beside result: pass registers (exit 0)" "0" "$RC"
expect_regex "SEV-derive3 …and the derived result is the one on the proof line" "evidence=record/wave-01-fixture/d-none-pass.md .* result=pass scope=piece$" "$(sev_last)"

# ---------- the mutation arms: one cell flipped, and the result refusal taken out ----------
# Each mutant is a COPY of the library in a directory of its own; each is shown to run (a positive
# read through it) before its difference is read.
sev_read() {  # <lib> <record> -> proof_reading's answer and exit, the scale pushed
  bash -c '. "$1"; proof_reading "$2" adversarial "" 1; echo " rc=$?"' _ "$1" "$2" 2>/dev/null
}
SEV_MUT="$(mktemp -d "$TMPROOT/sev-mut.XXXXXX")"
sed 's/S2:off=defer/S2:off=fix/' "$SEV_LIB" > "$SEV_MUT/cell.sh"
sed 's/\[ "\$rr" = "\$worst" \]/true/' "$SEV_LIB" > "$SEV_MUT/result.sh"
expect_eq "SEV-mut0 the cell mutant differs from the library in one line" "1" "$(diff "$SEV_LIB" "$SEV_MUT/cell.sh" | /usr/bin/grep -c '^>')"
expect_eq "SEV-mut0b the result mutant differs in one line" "1" "$(diff "$SEV_LIB" "$SEV_MUT/result.sh" | /usr/bin/grep -c '^>')"
expect_regex "SEV-mut1 the library reads the S2 off record as flag" "^flag piece [0-9a-f]+ rc=0$" "$(sev_read "$SEV_LIB" "$SEV_DIR/t-S2-off.md")"
expect_regex "SEV-mut1b the cell mutant runs: it reads the S3 on record as flag too" "^flag piece [0-9a-f]+ rc=0$" "$(sev_read "$SEV_MUT/cell.sh" "$SEV_DIR/t-S3-on.md")"
expect_contains "SEV-mut1c …and with S2 off flipped to fix, the S2 off record is refused as a fix shown nowhere, so §FACT-table goes red on the flip" \
  "sends finding 1 (S2 off) to fix" "$(sev_read "$SEV_MUT/cell.sh" "$SEV_DIR/t-S2-off.md")"
expect_contains "SEV-mut2 the library refuses a finding to fix beside result: flag" "its findings give fail" "$(sev_read "$SEV_LIB" "$SEV_DIR/d-fix-flag.md")"
expect_regex "SEV-mut2b the result mutant runs, and admits that record as flag: §FACT-derive goes red without the refusal" \
  "^flag piece [0-9a-f]+ rc=0$" "$(sev_read "$SEV_MUT/result.sh" "$SEV_DIR/d-fix-flag.md")"

# ---------- a structure reading's two derivations agree (A-orch-34) ----------
# F6 holds a structure result to its worst check; the table holds it to the findings. A FAIL check
# beside no finding to fix, or a finding to fix beside no FAIL check, is refused in one line naming
# both. Read through the library against the SHIPPED checks file, the one `proof-add` resolves.
SEV_CK="${BIONIC_HOOKS_DIR}/../payload/context/checks-structure.md"
SEV_IDS="$(awk '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s); print s }' "$SEV_CK" 2>/dev/null)"
expect_nonempty "SEV-st0 precondition: the shipped structure checks file names its check ids" "$SEV_IDS"
sev_st() {  # <file> <result> <answer for the first id> <line>... -> a structure reading, every other check PASS
  local f="$SEV_DIR/$1.md" r="$2" a="$3" i n=0 l; shift 3
  { printf '# reading\n\nreviewed: %s..%s\nquestion: structure\nresult: %s\nscope: piece\n' "${SEV_B:0:10}" "$SEV_C1" "$r"
    for i in $SEV_IDS; do n=$((n + 1)); if [ "$n" = 1 ]; then printf 'check: %s %s the reason\n' "$i" "$a"; else printf 'check: %s PASS nothing\n' "$i"; fi; done
    for l in "$@"; do printf '%s\n' "$l"; done; } > "$f"
}
sev_stread() { bash -c '. "$1"; proof_reading "$2" structure "$3" 1; echo " rc=$?"' _ "$SEV_LIB" "$SEV_DIR/$1.md" "$SEV_CK" 2>/dev/null; }
SEV_ID1="$(printf '%s\n' "$SEV_IDS" | head -1)"
sev_st st-agree fail FAIL "findings: 1" "finding: 1 S2 on lib/a.sh:5 the core path is wrong" "shown: 1 bash lib/a.sh"
expect_regex "SEV-st1 a FAIL check beside a finding to fix agrees: the reading reads as fail" "^fail piece [0-9a-f]+ rc=0$" "$(sev_stread st-agree)"
sev_st st-failcheck fail FAIL "findings: 1" "finding: 1 S3 on - only a side path"
SEV_OUT="$(sev_stread st-failcheck)"
expect_contains "SEV-st2 a FAIL check beside no finding to fix is refused, naming the check" \
  "gives check: $SEV_ID1 FAIL beside no finding to fix" "$SEV_OUT"
expect_eq "SEV-st2b …in one line" "1" "$(printf '%s\n' "$SEV_OUT" | wc -l | tr -d ' ')"
sev_st st-fixflag fail FLAG "findings: 1" "finding: 1 S1 off lib/a.sh:6 data lost" "shown: 1 bash lib/a.sh --lose"
expect_contains "SEV-st3 a finding to fix beside no FAIL check is refused, naming the finding" \
  "gives finding 1 (S1 off) to fix beside no FAIL check" "$(sev_stread st-fixflag)"
sev_st st-flagagree flag FLAG "findings: 1" "finding: 1 S3 on - only a side path"
expect_regex "SEV-st4 control: a FLAG check beside a deferral reads as flag" "^flag piece [0-9a-f]+ rc=0$" "$(sev_stread st-flagagree)"

# ---------- §FACT-shown (AC-8.6, the record half): a fix is shown, or owes a check ----------
sev_rec sh-dash fail "findings: 1" "finding: 1 S2 on - no place named" "shown: 1 bash lib/a.sh"
sev_rec sh-noshown fail "findings: 1" "finding: 1 S2 on lib/a.sh:4 no command"
for f in sh-dash sh-noshown; do
  s42_snap "$RSEV" "$PSEV"; sev_add "$f"
  s42_unchanged "SEV-shown §FACT-shown AC-8.6 a finding to fix with neither a file, line and command nor an unsure: line ($f)" 1 "$PSEV"
  expect_contains "SEV-shown …$f says what to write" "sends finding 1 (S2 on) to fix, but shows it nowhere" "$OUT"
done
sev_rec sh-unsure fail "findings: 1" "finding: 1 S1 off - cannot run it here" "unsure: 1 the race needs two machines"
sev_add sh-unsure
expect_eq "SEV-shown2 …a finding to fix carrying an unsure: line registers (exit 0)" "0" "$RC"
expect_eq "SEV-shown3 …and writes its check: line" 'check: record/wave-01-fixture/sh-unsure.md#1 S1 off "cannot run it here"' \
  "$(/usr/bin/grep '^check: record/wave-01-fixture/sh-unsure.md#' "$PSEV")"
expect_contains "SEV-shown3b …which the success output names" 'proof-add — check: record/wave-01-fixture/sh-unsure.md#1 S1 off' "$OUT"
sev_rec sh-defer-unsure flag "findings: 2" 'finding: 1 S3 on - a "quoted" word wrong' "unsure: 1 which platforms" "finding: 2 S4 on - a typo"
sev_add sh-defer-unsure
expect_eq "SEV-shown4 an unsure finding the table defers writes both lines, the deferral first; a note writes none" \
  "deferred: record/wave-01-fixture/sh-defer-unsure.md#1 S3 on \"a 'quoted' word wrong\"|check: record/wave-01-fixture/sh-defer-unsure.md#1 S3 on \"a 'quoted' word wrong\"" \
  "$(/usr/bin/grep -E '^(deferred|check): record/wave-01-fixture/sh-defer-unsure.md#' "$PSEV" | paste -sd'|' -)"
expect_eq "SEV-shown5 …and the two lines follow the proof line they belong to (proof_add_line)" \
  "check: record/wave-01-fixture/sh-defer-unsure.md#1" \
  "$(awk '/^proved: .*sh-defer-unsure/ { getline; getline; print $1 " " $2 }' "$PSEV")"

# ---------- the priority a record never states: library, release-check and the tick ----------
SEV_OWED="$(bash -c '. "$1"; proof_findings_owed "$2"' _ "$SEV_LIB" "$PSEV" 2>/dev/null)"
expect_contains "SEV-owed proof_findings_owed prints a deferral with the table's priority" \
  'record/wave-01-fixture/t-S2-off.md#1 S2 off defer "the S2 off cell"' "$SEV_OWED"
# An open check is printed as what it is, a check, not the priority it would take (wave-28 T41; D33, AC-8.6).
expect_contains "SEV-owed2 …and an unsure S1 as the check it owes" 'record/wave-01-fixture/sh-unsure.md#1 S1 off check "cannot run it here"' "$SEV_OWED"
expect_eq "SEV-owed3 …each finding once, though it has a deferred: and a check: line" "1" \
  "$(printf '%s\n' "$SEV_OWED" | /usr/bin/grep -c 'sh-defer-unsure.md#1 ')"

# ---------- §FACT-old (AC-8.8): a reader not pushed the scale registers as 1.12.0 did ----------
sev_rec o-fail fail
sev_add o-fail old-crit
expect_eq "SEV-old §FACT-old AC-8.8 a record with a result and no findings, from a reader with no pushed= key, registers (exit 0)" "0" "$RC"
expect_regex "SEV-old2 …with its result as written" "evidence=record/wave-01-fixture/o-fail.md question=adversarial reader=old-crit result=fail scope=piece$" "$(sev_last)"
expect_regex "SEV-old2b …placed after the last reading's finding lines, not between a proof and its own" "^proved: .*evidence=record/wave-01-fixture/o-fail.md " \
  "$(awk '/^check: record\/wave-01-fixture\/sh-defer-unsure.md#1 / { getline; print; exit }' "$PSEV")"
SEV_N="$(sev_lines | wc -l | tr -d ' ')"
sev_rec o-findings fail "findings: 1" "finding: 1 S4 off - finding lines the old reading ignores"
sev_add o-findings old-crit
expect_eq "SEV-old3 …finding lines in such a record are ignored: it registers (exit 0)" "0" "$RC"
expect_regex "SEV-old4 …with result: fail as written, though S4 off alone would derive flag" "o-findings.md .* result=fail scope=piece$" "$(sev_last)"
expect_eq "SEV-old5 …and writes no plan line (the count stands at $SEV_N, beside the lines SEV-table wrote)" "$SEV_N" "$(sev_lines | wc -l | tr -d ' ')"
sev_rec o-nopush fail
sev_add o-nopush nosev-crit
expect_eq "SEV-old6 a reader whose pushed= names other files, not severity, registers the old form too (exit 0)" "0" "$RC"

# ---------- release-check prints the derived priority ----------
printf '#!/bin/bash\necho "scan: entries=0 hits=0"\nexit 0\n' > "$TMPROOT/sev-check.sh"
cp "$RSEV/.bionic/config.yaml" "$TMPROOT/sev-config" 2>/dev/null || : > "$TMPROOT/sev-config"
printf 'release-check: bash %s\n' "$TMPROOT/sev-check.sh" >> "$RSEV/.bionic/config.yaml"
poke "$RSEV" release-check
expect_eq "SEV-rc release-check over a plan with rated findings exits 0" "0" "$RC"
expect_contains "SEV-rc2 …and prints each owed finding with the table's priority" \
  'release-check — finding record/wave-01-fixture/t-S3-on.md#1 S3 on defer "the S3 on cell"' "$OUT"
cp "$TMPROOT/sev-config" "$RSEV/.bionic/config.yaml"

# ---------- the tick prints the derived priority ----------
RSEVT="$(make_repo sev-tick)"; new_roster "$RSEVT"
PSEVT="$(s47_plan "$RSEVT" 2 \
  "| T1 | 4 | build | ready | implementor | — | 30 | REQ-x | payload/x.sh | pending | |")"
awk '{ print } /^current: / && !d { print "deferred: record/w/rev.md#2 S2 off \"a side path\""; print "check: record/w/rev.md#3 S1 on \"unsure of it\""; d = 1 }' \
  "$PSEVT" > "$PSEVT.tmp" && mv "$PSEVT.tmp" "$PSEVT"
poke_pressure "$RSEVT" 8192 1.0 tick
expect_contains "SEV-tick the tick fills the ready row (the path it prints FINDING on)" "poker: FILL T1" "$OUT"
expect_contains "SEV-tick2 …and prints a deferred finding with its priority" 'poker: FINDING record/w/rev.md#2 S2 off defer "a side path"' "$OUT"
expect_contains "SEV-tick3 …and a finding that owes a check as the check it owes (wave-28 T41)" 'poker: FINDING record/w/rev.md#3 S1 on check "unsure of it"' "$OUT"

# ---------- (wave-28 T41; D33) the two checks §FACT-shown owes are settled before the step is judged ----------
# An open check holds `current 8` (§CHECK, at the end of this file), so §CUR8-sev, which judges the
# verdict alone, starts with none open: the S1 is refuted and the deferral settled at its own rating,
# by a check record whose header names a third agent (`written-by:`), neither the reviewer nor a writer.
chk_rec() {  # <name> <writer, or - for none> -> a check record under the record directory
  { printf '# check\n\n'; [ "$2" = - ] || printf 'written-by: %s\n' "$2"; printf '\nwhat the check ran and saw\n'; } > "$SEV_DIR/$1.md"
}
chk_rec chk-pre chk-agent
poke "$RSEV" finding-check record/wave-01-fixture/sh-unsure.md#1 refuted record/wave-01-fixture/chk-pre.md
expect_eq "CHECK-pre the unsure S1 is refuted by a third agent's check record (exit 0)" "0" "$RC"
poke "$RSEV" finding-check record/wave-01-fixture/sh-defer-unsure.md#1 unsettled record/wave-01-fixture/chk-pre.md
expect_eq "CHECK-pre2 …and the unsure deferral settled at its own rating, so it is an open deferral (exit 0)" "0" "$RC"

# ---------- §CUR8-sev (AC-8.5): the step into integration follows the derived verdict ----------
# The plan moves to current: 7 and every other fact it owes is planted at C1 by the production
# placer (§61's way); the adversarial piece fact is then a reading registered through the verb, so
# what the judge reads is the result the findings derived.
sev_put() { bash -c '. "$1" && proof_add_line "$2" "$3"' _ "$SEV_LIB" "$PSEV" "$1" > "$PSEV.new" && mv "$PSEV.new" "$PSEV"; }
sev_fact() {  # <kind> <question> <scope>
  sev_put "$(bash -c '. "$1" && proof_line "$2" "$3" 2026-10-06T12:00:00Z "$4" "$5" w-read pass "$6"' \
    _ "$SEV_LIB" "$1" "$SEV_C1" "record/wave-01-fixture/planted-$2-$3.md" "$2" "$3")"
}
sev_cur() { sed "s/^current: .*/current: $1/" "$PSEV" > "$PSEV.tmp" && mv "$PSEV.tmp" "$PSEV"; }
sev_put "$(bash -c '. "$1" && proof_line floor "$2" 2026-10-06T12:00:00Z record/wave-01-fixture/floor.log' _ "$SEV_LIB" "$SEV_C1")"
sev_fact review evidence piece; sev_fact review structure piece; sev_fact review structure whole; sev_fact review adversarial whole
sev_rec c-fix fail "findings: 2" "finding: 1 S2 on lib/a.sh:9 the core path gives a wrong answer" "shown: 1 bash lib/a.sh --core" \
  "finding: 2 S4 off - a comment misstates it"
sev_add c-fix
expect_eq "SEV-cur0 a reading with a finding to fix registers, result=fail derived (exit 0)" "0|fail" \
  "$RC|$(sev_last | sed -n 's/.* result=\([a-z]*\) .*/\1/p')"
sev_cur 7; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" current 8
s42_unchanged "SEV-cur §CUR8-sev AC-8.5 the newest adversarial fact holds a finding to fix: current 8" 1 "$PSEV"
expect_contains "SEV-cur2 …naming that reading failing" \
  "$(printf 'review\tadversarial\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/c-fix.md')" "$OUT"
sev_cur 4
sev_rec c-later flag "findings: 2" "finding: 1 S2 off - a side path still wrong" "finding: 2 S4 off - a comment misstates it"
sev_add c-later
expect_eq "SEV-cur3 a later pass over the fix, holding only a deferral and a note, registers as flag (exit 0)" "0|flag" \
  "$RC|$(sev_last | sed -n 's/.* result=\([a-z]*\) .*/\1/p')"
sev_cur 7
poke "$RSEV" current 8
expect_eq "SEV-cur4 §CUR8-sev …and current 8 is admitted on it: deferrals and notes do not hold the step" "0|8" \
  "$RC|$(sed -n 's/^current: //p' "$PSEV")"
POKE_BOUND="$SEV_BOUND_WAS"

# ============================================================
section "§DEBT-PARSE §DEBT-LEDGER §DEBT-ADVISORY (the verb half): a debt: line is a flag-class finding the reader names by kind and concept, and the run's ledger holds one line per item (wave-30 T22; REQ-11 AC-11.1, AC-11.2, AC-11.3; D2, P2; A-orch-8)"
# ============================================================
#
# severity.md (T4) writes the line `debt: <kind> <concept> <path>:<line>[, <path>:<line>…]`, flush
# left, beside the `finding:` lines and not counted in `findings:`. lib/proof.sh `proof_findings` reads
# it as a row of its own, `debt<TAB><kind><TAB><concept><TAB><sites><TAB>burn`, which the derived result
# reads as flag-class; a debt line carrying a severity or a reach word, or a kind outside the debt
# table, is refused, naming the line. `session-poker.sh debt` keeps `record/<run>/debt.md`: a header,
# then `concept | kind | sites | raised-by <record> | touches N | <burned <row>|—>` per item.
#
# FIXTURE FIDELITY. The parser rows run the library §SEV runs (`SEV_LIB`) against the shipped
# structure checks file (`SEV_CK`); the ledger rows run the real verb in §SEV's bound repository and
# read the ledger file it wrote.
dbt_read() {  # <lib> <record> -> proof_reading's answer and exit, the scale pushed (adversarial)
  bash -c '. "$1"; proof_reading "$2" adversarial "" 1; echo " rc=$?"' _ "$1" "$2" 2>/dev/null
}
dbt_rows() { bash -c '. "$1"; o="$(proof_findings "$2")"; r=$?; printf "%s rc=%s\n" "$o" "$r"' _ "$SEV_LIB" "$SEV_DIR/$1.md" 2>/dev/null; }
sev_rec dbt-only flag "findings: 0" "debt: one-case-abstraction log_shim lib/a.sh:4"
expect_regex "DEBT-P1 §DEBT-PARSE a pass whose one finding is a debt: line reads as flag (A-orch-8)" "^flag piece [0-9a-f]+ rc=0$" \
  "$(dbt_read "$SEV_LIB" "$SEV_DIR/dbt-only.md")"
sev_rec dbt-pass pass "findings: 0" "debt: one-case-abstraction log_shim lib/a.sh:4"
expect_contains "DEBT-P1b …and the same pass beside result: pass is refused, its findings giving flag" "its findings give flag" \
  "$(dbt_read "$SEV_LIB" "$SEV_DIR/dbt-pass.md")"
expect_eq "DEBT-P2 proof_findings exposes the debt line as a row: debt, kind, concept, sites, burn" \
  "$(printf 'debt\tone-case-abstraction\tlog_shim\tlib/a.sh:4\tburn') rc=0" "$(dbt_rows dbt-only)"
sev_rec dbt-mixed flag "findings: 1" "finding: 1 S3 on lib/a.sh:3 a message misnames the flag" \
  "debt: duplicate tree_count lib/b.sh:2,lib/c.sh:5"
DBT_MIX="$(dbt_rows dbt-mixed)"
expect_eq "DEBT-P2b a pass with a finding and a debt line: the finding row, then the debt row, its sites joined by ', '" \
  "$(printf '1\tS3\ton\tlib/a.sh:3\tdefer\t0\t0\ta message misnames the flag\ndebt\tduplicate\ttree_count\tlib/b.sh:2, lib/c.sh:5\tburn') rc=0" "$DBT_MIX"
expect_eq "DEBT-P2c …and registration writes the finding's deferred: line and none for the debt row" \
  'deferred: record/wave-01-fixture/dbt-mixed.md#1 S3 on "a message misnames the flag"' \
  "$(bash -c '. "$1"; proof_finding_lines record/wave-01-fixture/dbt-mixed.md "$(proof_findings "$2")"' _ "$SEV_LIB" "$SEV_DIR/dbt-mixed.md" 2>/dev/null)"
# AC-11.1's fails-when on the record: a debt line carrying a severity or a reach, or a kind outside the table.
for c in "dbt-sev@debt: duplicate tree_count S2 lib/b.sh:2@rates its debt line (debt: duplicate tree_count S2 lib/b.sh:2) with 'S2'" \
         "dbt-reach@debt: duplicate tree_count on lib/b.sh:2@rates its debt line (debt: duplicate tree_count on lib/b.sh:2) with 'on'" \
         "dbt-kind@debt: smell tree_count lib/b.sh:2@has a debt line (debt: smell tree_count lib/b.sh:2) whose kind 'smell' is not one of duplicate, unpinned-pair or one-case-abstraction" \
         "dbt-site@debt: duplicate tree_count lib/b.sh@has a debt line (debt: duplicate tree_count lib/b.sh) naming 'lib/b.sh' where a site takes <path>:<line>" \
         "dbt-bare@debt: duplicate tree_count@has a debt line (debt: duplicate tree_count) with no site"; do
  f="${c%%@*}"; rest="${c#*@}"; line="${rest%%@*}"; want="${rest#*@}"
  sev_rec "$f" flag "findings: 0" "$line"
  DBT_OUT="$(dbt_read "$SEV_LIB" "$SEV_DIR/$f.md")"
  expect_contains "DEBT-P3 §DEBT-PARSE AC-11.1 the reading is refused, naming the line ($f)" "$want" "$DBT_OUT"
  expect_contains "DEBT-P3 …$f exits 1" " rc=1" "$DBT_OUT"
done
# A structure reading that FLAGs a must-answer check and declares the debt (the case A-orch-8 names).
sev_st dbt-st flag FLAG "findings: 0" "debt: duplicate tree_count lib/b.sh:2, lib/c.sh:5"
expect_regex "DEBT-P4 a structure reading with a FLAG check and a debt: line beside findings: 0 reads as flag" "^flag piece [0-9a-f]+ rc=0$" \
  "$(sev_stread dbt-st)"
sev_st dbt-st-pass flag FLAG "findings: 0"
expect_contains "DEBT-P4b …and without the debt line the same pass is refused: its findings give pass" "its findings give pass" \
  "$(sev_stread dbt-st-pass)"
# The mutation arm: the debt arm read as no line at all. The mutant runs (a finding record reads), then
# reads the debt-only pass as findings-free.
sed 's/^    \/\^debt:\/ {$/    \/^nodebt:\/ {/' "$SEV_LIB" > "$SEV_MUT/debt.sh"
expect_eq "DEBT-mut0 the debt mutant differs from the library in one line" "1" "$(diff "$SEV_LIB" "$SEV_MUT/debt.sh" | /usr/bin/grep -c '^>')"
expect_regex "DEBT-mut1 the debt mutant runs: it reads the S2 off record as flag" "^flag piece [0-9a-f]+ rc=0$" "$(dbt_read "$SEV_MUT/debt.sh" "$SEV_DIR/t-S2-off.md")"
expect_contains "DEBT-mut2 …and with the arm gone the debt-only pass is refused as one finding nothing, so DEBT-P1 goes red" \
  "its findings give pass" "$(dbt_read "$SEV_MUT/debt.sh" "$SEV_DIR/dbt-only.md")"

# ---------- §DEBT-LEDGER (AC-11.2): the verb writes the ledger from a reading's debt lines ----------
DBT_SLUG="${PSEV##*/}"; DBT_SLUG="${DBT_SLUG%.plan.md}"
DBT_LEDGER="$RSEV/.bionic/docs/record/$DBT_SLUG/debt.md"
sev_rec dbt-rec flag "findings: 1" "finding: 1 S3 off lib/a.sh:3 a message misnames the flag" \
  "debt: one-case-abstraction log_shim lib/a.sh:4" "debt: duplicate tree_count lib/b.sh:2, lib/c.sh:5"
DBT_HEAD='# debt ledger: concept | kind | sites | raised-by <record> | touches N | burned <row> | —'
DBT_L1='log_shim | one-case-abstraction | lib/a.sh:4 | raised-by record/wave-01-fixture/dbt-rec.md | touches 0 | —'
DBT_L2='tree_count | duplicate | lib/b.sh:2, lib/c.sh:5 | raised-by record/wave-01-fixture/dbt-rec.md | touches 0 | —'
expect_false "DEBT-L0 precondition: the run has no ledger yet" test -e "$DBT_LEDGER"
poke "$RSEV" debt add record/wave-01-fixture/dbt-rec.md
expect_eq "DEBT-L1 §DEBT-LEDGER debt add over the session's bound run exits 0" "0" "$RC"
expect_eq "DEBT-L1b …and writes the header and one line per debt line of the record, in its order" \
  "$DBT_HEAD|$DBT_L1|$DBT_L2" "$(paste -sd'|' - < "$DBT_LEDGER" 2>/dev/null)"
expect_contains "DEBT-L1c …naming each item it added" "poker: debt add — log_shim one-case-abstraction lib/a.sh:4" "$OUT"
expect_contains "DEBT-L1d …and the count and the ledger" "poker: debt add — 2 added, 0 already there: record/$DBT_SLUG/debt.md" "$OUT"
# AC-11.2's fails-when: a debt finding in the record with no ledger line.
DBT_WANT="$(dbt_rows dbt-rec | awk -F'\t' '$1 == "debt" { print $3 " | " $2 " | " $4 }')"
expect_nonempty "DEBT-L2 precondition: the record's debt rows read back" "$DBT_WANT"
expect_eq "DEBT-L2b every debt row of the record has its ledger line (concept, kind, sites)" "2" \
  "$(printf '%s\n' "$DBT_WANT" | while IFS= read -r w; do /usr/bin/grep -cF "$w | raised-by record/wave-01-fixture/dbt-rec.md" "$DBT_LEDGER"; done | awk '{ n += $1 } END { print n + 0 }')"
poke "$RSEV" debt add record/wave-01-fixture/dbt-rec.md "$PSEV"
expect_eq "DEBT-L3 a second add of the same record, the plan named, exits 0" "0" "$RC"
expect_eq "DEBT-L3b …and adds nothing: concept and kind already there" "$DBT_HEAD|$DBT_L1|$DBT_L2" "$(paste -sd'|' - < "$DBT_LEDGER")"
expect_contains "DEBT-L3c …saying so" "poker: debt add — 0 added, 2 already there" "$OUT"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt add record/wave-01-fixture/dbt-sev.md "$PSEV"
expect_eq "DEBT-L4 debt add on a record whose debt line carries a severity is refused (exit 1)" "1" "$RC"
expect_contains "DEBT-L4b …naming the line" "rates its debt line (debt: duplicate tree_count S2 lib/b.sh:2)" "$OUT"
expect_true "DEBT-L4c …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt add record/wave-01-fixture/r-ok.md "$PSEV"
expect_eq "DEBT-L5 debt add on a reading with no debt line exits 0" "0" "$RC"
expect_contains "DEBT-L5b …and says it added nothing" "carries no debt: line; nothing added" "$OUT"
expect_true "DEBT-L5c …the ledger byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt touched tree_count "$PSEV"
expect_eq "DEBT-L6 debt touched exits 0 and prints the item with its new count" \
  "0|poker: debt touched — tree_count duplicate touches 1" "$RC|$OUT"
expect_eq "DEBT-L6b …and the ledger line reads touches 1, the other line untouched" \
  "$DBT_HEAD|$DBT_L1|${DBT_L2% | touches 0 | —} | touches 1 | —" "$(paste -sd'|' - < "$DBT_LEDGER")"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt touched no_such_concept "$PSEV"
expect_eq "DEBT-L6c debt touched on a concept the ledger does not hold is refused (exit 1)" "1" "$RC"
expect_true "DEBT-L6d …the ledger byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt burn log_shim T9 "$PSEV"
expect_eq "DEBT-L7 debt burn exits 0 and prints the item burned" "0|poker: debt burn — log_shim one-case-abstraction burned T9" "$RC|$OUT"
expect_eq "DEBT-L7b …and the item's last cell reads burned T9" "${DBT_L1% | —} | burned T9" "$(/usr/bin/grep '^log_shim ' "$DBT_LEDGER")"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt burn log_shim T10 "$PSEV"
expect_eq "DEBT-L7c a second burn of a burned item is refused (exit 1), the ledger unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER" && echo same)"
poke "$RSEV" debt touched log_shim "$PSEV"
expect_eq "DEBT-L7d …and a burned item is touched no more (exit 1, unchanged)" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER" && echo same)"
poke "$RSEV" debt list "$PSEV"
expect_eq "DEBT-L8 debt list prints each item line as the ledger holds it" "0|$(/usr/bin/grep -v '^#' "$DBT_LEDGER" | paste -sd'|' -)" \
  "$RC|$(printf '%s\n' "$OUT" | paste -sd'|' -)"
poke "$RSEV" debt
expect_eq "DEBT-L9 debt with no subcommand is a usage error (exit 2)" "2" "$RC"
poke "$RSEV" debt touched
expect_eq "DEBT-L9b debt touched with no concept is a usage error (exit 2)" "2" "$RC"
rm -f "$DBT_LEDGER"

# ---------- §DEBT-ADOPT (AC-11.2's read-back, wave-30 T32): the next run's ledger takes the carried debt lines ----------
# Close-out wrote `debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave>` under the
# continuation's `## Deferrals`; `debt adopt <continuation>` writes each into the bound run's ledger, its
# touches and raised-by kept, its last cell open, idempotent on concept and kind as `add` is (A-T22.5).
DBT_CONT="$TMPROOT/dbt-cont.md"
DBT_CL1='debt: tree_count duplicate "lib/b.sh:2, lib/c.sh:5" touches=4 raised-by=record/wave-00-prior/critic-structure.md from=wave-00-prior'
DBT_CL2='debt: log_shim one-case-abstraction "lib/a.sh:4" touches=2 raised-by=record/wave-00-prior/dbt-rec.md from=wave-00-prior'
printf '%s\n' "# continuation — wave-00-prior" "" "## Deferrals" "" \
  'deferred: record/wave-00-prior/rev.md#1 S3 on "a deferral" stated="-" from=wave-00-prior' "$DBT_CL1" "$DBT_CL2" "" \
  "## Resume instruction" "" 'debt: not_in_section duplicate "x.sh:1" touches=9 raised-by=record/x.md from=wave-00-prior' > "$DBT_CONT"
DBT_AL1='tree_count | duplicate | lib/b.sh:2, lib/c.sh:5 | raised-by record/wave-00-prior/critic-structure.md | touches 4 | —'
DBT_AL2='log_shim | one-case-abstraction | lib/a.sh:4 | raised-by record/wave-00-prior/dbt-rec.md | touches 2 | —'
expect_false "DEBT-A0 precondition: the run has no ledger yet" test -e "$DBT_LEDGER"
poke "$RSEV" debt adopt "$DBT_CONT"
expect_eq "DEBT-A1 §DEBT-ADOPT debt adopt over the session's bound run exits 0, saying what it adopted" \
  "0|poker: debt adopt — 2 adopted, 0 already there: record/$DBT_SLUG/debt.md" "$RC|$OUT"
expect_eq "DEBT-A1b …the ledger holds the header and the two carried items, touches and raised-by kept, none burned, the line outside ## Deferrals left out" \
  "$DBT_HEAD|$DBT_AL1|$DBT_AL2" "$(paste -sd'|' - < "$DBT_LEDGER" 2>/dev/null)"
expect_eq "DEBT-A1c …and debt list reads both back" "0|$DBT_AL1|$DBT_AL2" "$(poke "$RSEV" debt list "$PSEV"; printf '%s|%s' "$RC" "$(printf '%s\n' "$OUT" | paste -sd'|' -)")"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt adopt "$DBT_CONT" "$PSEV"
expect_eq "DEBT-A2 a second adopt, the plan named: 0 adopted, 2 already there" \
  "0|poker: debt adopt — 0 adopted, 2 already there: record/$DBT_SLUG/debt.md" "$RC|$OUT"
expect_true "DEBT-A2b …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt touched tree_count "$PSEV"
poke "$RSEV" debt adopt "$DBT_CONT" "$PSEV"
expect_eq "DEBT-A3 an item the run has already worked keeps its own touches when the continuation is adopted again" \
  "$DBT_HEAD|${DBT_AL1% | touches 4 | —} | touches 5 | —|$DBT_AL2" "$(paste -sd'|' - < "$DBT_LEDGER")"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt adopt "$TMPROOT/no-such-continuation.md" "$PSEV"
expect_eq "DEBT-A4 a path that is no file is refused (exit 2)" "2" "$RC"
expect_contains "DEBT-A4b …naming the path" "$TMPROOT/no-such-continuation.md" "$OUT"
poke "$RSEV" debt adopt "$TMPROOT" "$PSEV"
expect_eq "DEBT-A4c a directory is refused as well (exit 2)" "2" "$RC"
expect_contains "DEBT-A4c2 …naming it" "no readable continuation at $TMPROOT" "$OUT"
expect_true "DEBT-A4d …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
printf '%s\n' "## Deferrals" "" "$DBT_CL1" 'debt: widget_parse duplicate "lib/w.sh:1" touches=3 from=wave-00-prior' > "$TMPROOT/dbt-cont-bad.md"
poke "$RSEV" debt adopt "$TMPROOT/dbt-cont-bad.md" "$PSEV"
expect_eq "DEBT-A5 a debt: line that does not parse is refused (exit 1)" "1" "$RC"
expect_contains "DEBT-A5a …naming the line" 'debt: widget_parse duplicate "lib/w.sh:1" touches=3 from=wave-00-prior' "$OUT"
expect_true "DEBT-A5b …and the ledger is byte-identical, the good line before it not adopted either" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
printf '%s\n' "## Deferrals" "" 'deferred: record/wave-00-prior/rev.md#1 S3 on "a deferral" stated="-" from=wave-00-prior' > "$TMPROOT/dbt-cont-none.md"
poke "$RSEV" debt adopt "$TMPROOT/dbt-cont-none.md" "$PSEV"
expect_eq "DEBT-A6 a continuation with no debt: line adopts nothing and exits 0" "0" "$RC"
expect_contains "DEBT-A6b …and says so" "carries no debt: line; nothing adopted" "$OUT"
expect_true "DEBT-A6c …the ledger byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt adopt
expect_eq "DEBT-A7 debt adopt with no continuation is a usage error (exit 2)" "2" "$RC"
rm -f "$DBT_LEDGER"

# ============================================================
section "§LINE-TELL: the tick tells each standing red and each stalled entry once, with its logs (wave-28 T5; REQ-9 AC-9.2, AC-9.3; D8)"
# ============================================================
#
# `ready` appends `standing` when a red also fails at the accepted head (the branch's, not a row's)
# and `stalled` when an entry's runs twice gave no verdict. The tick reads both off the bound plan's
# landing record and prints each as a note, once: a second tick over the same record says nothing of
# them, and a new event is told by the next tick.
# FIXTURE FIDELITY: §60's repository and bound plan (s60_world); the events are PLANTED in the
# Interfaces table's `line/v1` shape, which lib/line.sh writes.
LT_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s60_world lt-tell @A whole
LT_H1="$(printf 'a%.0s' $(seq 40))"; LT_H2="$(printf 'b%.0s' $(seq 40))"
printf 'line/v1|ev=standing|head=%s|suite=a.test.sh|lines=3|log=/rec/line/T1-a-%s.log|at=2026-10-06T10:00:00Z\n' "$LT_H1" "${LT_H1:0:12}" >> "$S60_REC"
printf 'line/v1|ev=stalled|row=T7|logs=/rec/line/T7-b-1.log,/rec/line/T7-b-1-2.log|at=2026-10-06T10:01:00Z\n' >> "$S60_REC"
lt_lines() { printf '%s\n' "$OUT" | /usr/bin/grep -E '^poker: note: (standing|stalled) ' | tr '\n' '|' | sed 's/|$//'; }
s60_tick
expect_eq "LT1 the tick tells the standing red: suite, head, its failing lines and the head's log" \
  "poker: note: standing a.test.sh at ${LT_H1:0:12} — 3 failing line(s) fail at the accepted head too: a red the branch carries, not one a row added; log /rec/line/T1-a-${LT_H1:0:12}.log" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: note: standing ')"
expect_eq "LT2 …and the stalled entry, with both its logs" \
  "poker: note: stalled T7 — two runs ended with no verdict and no third starts; logs /rec/line/T7-b-1.log,/rec/line/T7-b-1-2.log" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: note: stalled ')"
s60_tick
expect_nonempty "LT3-pre the second tick printed (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: ')"
expect_eq "LT3 a second tick over the same record tells neither again" "" "$(lt_lines)"
printf 'line/v1|ev=standing|head=%s|suite=a.test.sh|lines=1|log=/rec/line/T2-a-%s.log|at=2026-10-06T10:02:00Z\n' "$LT_H2" "${LT_H2:0:12}" >> "$S60_REC"
s60_tick
expect_eq "LT4 a new standing event, on a new head, is told by the next tick, alone" \
  "poker: note: standing a.test.sh at ${LT_H2:0:12} — 1 failing line(s) fail at the accepted head too: a red the branch carries, not one a row added; log /rec/line/T2-a-${LT_H2:0:12}.log" \
  "$(lt_lines)"
POKE_BOUND="$LT_BOUND_WAS"

# ============================================================
section "§RC-DEFER §RC-STATED §RC-PARSE: a deferral is held to its debts, the stated sentence and the release check's list of them (wave-28 T17; REQ-8 AC-8.7; D21)"
# ============================================================
#
# `finding-stated <record>#<n> '<sentence>'` stores a deferred finding's one changelog sentence on its
# `deferred:` line, as ` stated="<sentence>"`, the last field, through the plan transaction. `release-check`
# prints `deferral <record>#<n>: stated` when the working head's CHANGELOG.md holds the sentence (white
# space folded, so a wrapped line matches), else `unstated`, and its exit is the check's own. The rows
# run on §SEV's fixture, whose plan holds deferrals the real verb registered, in its working branch's
# worktree, which is where release-check reads the changelog. One deferral's sentence is made of the
# words the plan's own parsers read, and every row after it runs with that line in the plan (§RC-PARSE).
RD_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RD_ID1="record/wave-01-fixture/t-S2-off.md#1"
RD_ID2="record/wave-01-fixture/t-S3-on.md#1"
RD_ID3="record/wave-01-fixture/sh-defer-unsure.md#1"
RD_ID4="record/wave-01-fixture/r-pri-ok.md#1"
RD_ID5="record/wave-01-fixture/c-later.md#1"
RD_CHK="record/wave-01-fixture/sh-unsure.md#1"
RD_SA="The install record now lists what setup placed"
RD_SQ='Said "go" \ now | here'
RD_HAZ='done; delivered: now - Step 9: delivered: x current: 9 approved-by: me proved: kind=floor head=abc'
rd_line() { /usr/bin/grep -F "deferred: $1 " "$PSEV"; }  # the plan's deferred: line for a finding
rd_state() {  # <id> -> stated|unstated, from the last release-check's output; nothing when it printed no line
  local l
  l="$(printf '%s\n' "$OUT" | /usr/bin/grep -F "release-check — deferral $1: ")" || return 0
  printf '%s' "${l##*: }"
}
printf '#!/bin/bash\necho "scan: entries=0 hits=0"\nexit 0\n' > "$TMPROOT/rd-check.sh"
cp "$RSEV/.bionic/config.yaml" "$TMPROOT/rd-config" 2>/dev/null || : > "$TMPROOT/rd-config"
printf 'release-check: bash %s\n' "$TMPROOT/rd-check.sh" >> "$RSEV/.bionic/config.yaml"
for _rd in "$RD_ID1" "$RD_ID2" "$RD_ID3" "$RD_ID4" "$RD_ID5"; do
  expect_eq "RD-0 precondition: $_rd has one deferred: line with no sentence yet" "1|0" \
    "$(rd_line "$_rd" | wc -l | tr -d ' ')|$(rd_line "$_rd" | /usr/bin/grep -c ' stated=')"
done
expect_eq "RD-0b precondition: $RD_CHK is a check owed with no deferred: line, and the working head has no CHANGELOG.md" "0|no" \
  "$(rd_line "$RD_CHK" | wc -l | tr -d ' ')|$([ -e "$SEV_WT/CHANGELOG.md" ] && echo yes || echo no)"

# ---------- §RC-DEFER: a deferral reads unstated until its sentence is in the changelog ----------
poke "$RSEV" release-check
expect_eq "RD-1 release-check over a plan holding deferrals none of which is stated exits 0 (it refuses nothing)" "0" "$RC"
expect_eq "RD-1b …and prints each deferral unstated: $RD_ID1" "unstated" "$(rd_state "$RD_ID1")"
expect_eq "RD-1c …and $RD_ID2" "unstated" "$(rd_state "$RD_ID2")"
expect_eq "RD-1d …one line per deferred: line the plan holds, and no line for a check owed" "$(/usr/bin/grep -c '^deferred: ' "$PSEV" | tr -d ' ')|0" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: release-check — deferral ')|$(printf '%s\n' "$OUT" | /usr/bin/grep -cF "deferral $RD_CHK")"
expect_eq "RD-1e …and the finding lines it already printed keep their form" "1" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -cx "poker: release-check — finding $RD_ID1 S2 off defer \"the S2 off cell\"")"
poke "$RSEV" finding-stated "$RD_ID1" "$RD_SA"
expect_eq "RD-2 finding-stated on a deferral exits 0" "0" "$RC"
expect_eq "RD-2b …and appends the sentence to that deferred: line, the last field" \
  "deferred: $RD_ID1 S2 off \"the S2 off cell\" stated=\"$RD_SA\"" "$(rd_line "$RD_ID1")"
expect_eq "RD-2c …and to no other deferred: line" "1" "$(/usr/bin/grep -c '^deferred: .* stated=' "$PSEV" | tr -d ' ')"
poke "$RSEV" release-check
expect_eq "RD-3 a stated deferral whose sentence is not in the changelog is still unstated (exit 0)" "0|unstated" "$RC|$(rd_state "$RD_ID1")"

# ---------- §RC-PARSE: a deferred: line whose sentence carries the plan's own words passes its parsers ----------
poke "$RSEV" finding-stated "$RD_ID4" "$RD_HAZ"
expect_eq "RD-4 finding-stated with a sentence made of the words the plan's parsers read exits 0 (the dry commit passed the gate)" "0" "$RC"
expect_eq "RD-4b …and the line carries it whole" "deferred: $RD_ID4 S2 off \"written as the table writes it\" stated=\"$RD_HAZ\"" "$(rd_line "$RD_ID4")"
sev_cur 4
s34_gate "$RSEV"
expect_eq "RD-4c the real commit gate admits the plan carrying it (at the step a writer's dry commit judges)" "0" "$GATE_RC"
cp "$PSEV" "$TMPROOT/rd-plan-keep"; sed '/^approved-by:/d' "$TMPROOT/rd-plan-keep" > "$PSEV"
s34_gate "$RSEV"
expect_eq "RD-4c2 …and the same gate refuses it with the approval line taken out, so the row above reads the plan" "2" "$GATE_RC"
cp "$TMPROOT/rd-plan-keep" "$PSEV"
sev_cur 7
poke "$RSEV" current 8
expect_eq "RD-4d current 8 is admitted over the plan (the judge reads the facts past the deferred: lines)" "0|8" "$RC|$(sed -n 's/^current: //p' "$PSEV")"
expect_eq "RD-4e …and the run still reads open (run_open: 0), the sentence's delivered: taken for no step line" "0" \
  "$(bash -c '. "$1/run.sh" || exit 9; run_open "$2" >/dev/null 2>&1; echo $?' _ "$BIONIC_HOOKS_DIR/../payload/scripts/lib" "$PSEV")"
poke "$RSEV" release-check
expect_eq "RD-4f release-check still prints that deferral's line, as a sentence (exit 0)" "0|unstated" "$RC|$(rd_state "$RD_ID4")"

# the tick prints a stated deferral by its title, not its sentence
RSEVT2="$(make_repo rd-tick)"; new_roster "$RSEVT2"
PSEVT2="$(s47_plan "$RSEVT2" 2 \
  "| T1 | 4 | build | ready | implementor | — | 30 | REQ-x | payload/x.sh | pending | |")"
awk '{ print } /^current: / && !d { print "deferred: record/w/rev.md#2 S2 off \"a side path\" stated=\"said \\\"x\\\" | y\""; d = 1 }' \
  "$PSEVT2" > "$PSEVT2.tmp" && mv "$PSEVT2.tmp" "$PSEVT2"
poke_pressure "$RSEVT2" 8192 1.0 tick
expect_contains "RD-5 the tick fills the ready row (the path it prints FINDING on)" "poker: FILL T1" "$OUT"
expect_eq "RD-5b …and prints the stated deferral by its title alone" "1" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -cx 'poker: FINDING record/w/rev.md#2 S2 off defer "a side path"')"

# ---------- §RC-STATED: the sentence in the changelog makes a deferral stated ----------
RD_CL="## 1.13.0 — fixture
- The install record now lists
  what setup placed, and remove acts only on it."
s57_commit "$SEV_WT" CHANGELOG.md "$RD_CL" >/dev/null
poke "$RSEV" release-check
expect_eq "RD-6 with the sentence in the head's CHANGELOG.md, wrapped across two lines, the deferral reads stated (exit 0)" "0|stated" "$RC|$(rd_state "$RD_ID1")"
expect_eq "RD-6b …while a deferral with no sentence still reads unstated" "unstated" "$(rd_state "$RD_ID2")"
poke "$RSEV" finding-stated "$RD_ID1" "a sentence the changelog does not hold"
expect_eq "RD-7 stating again replaces the sentence: one stated= on the line, and it is the new one" "1|deferred: $RD_ID1 S2 off \"the S2 off cell\" stated=\"a sentence the changelog does not hold\"" \
  "$(rd_line "$RD_ID1" | /usr/bin/grep -o ' stated=' | wc -l | tr -d ' ')|$(rd_line "$RD_ID1")"
poke "$RSEV" release-check
expect_eq "RD-7b …and the deferral reads unstated again" "unstated" "$(rd_state "$RD_ID1")"
poke "$RSEV" finding-stated "$RD_ID1" "$RD_SA"
poke "$RSEV" release-check
expect_eq "RD-7c …and stated again once the changelog's sentence is put back" "stated" "$(rd_state "$RD_ID1")"
poke "$RSEV" finding-stated "$RD_ID1" "$RD_SA"
expect_eq "RD-7d stating the same sentence twice writes nothing (exit 0)" "0" "$RC"
expect_contains "RD-7e …and says so" "nothing was written" "$OUT"
poke "$RSEV" finding-stated "$RD_ID2" "$RD_SQ"
expect_eq "RD-8 a sentence with a quote, a backslash and a pipe is stored escaped, the field still one quoted string" \
  "0|deferred: $RD_ID2 S3 on \"the S3 on cell\" stated=\"Said \\\"go\\\" \\\\ now | here\"" "$RC|$(rd_line "$RD_ID2")"
s57_commit "$SEV_WT" CHANGELOG.md "- Said \"go\" \\ now | here" >/dev/null
poke "$RSEV" release-check
expect_eq "RD-8b …and matches the changelog's own text verbatim: stated" "stated" "$(rd_state "$RD_ID2")"
poke "$RSEV" finding-stated "$RD_ID3" "The install  record
now lists	what setup placed."
expect_eq "RD-9 a sentence with a line break, a tab and a double space is stored folded to single spaces" \
  "0|deferred: $RD_ID3 S3 on \"a 'quoted' word wrong\" stated=\"The install record now lists what setup placed.\"" "$RC|$(rd_line "$RD_ID3")"
s57_commit "$SEV_WT" CHANGELOG.md "- The install record now lists what setup placed." >/dev/null
poke "$RSEV" release-check
expect_eq "RD-9b …and that folded sentence is read against the changelog: stated" "stated" "$(rd_state "$RD_ID3")"
expect_eq "RD-9c …the other deferrals' states unchanged by it (ID2 stated, ID5 unstated)" "stated|unstated" "$(rd_state "$RD_ID2")|$(rd_state "$RD_ID5")"

# ---------- refusals: byte-identical plan ----------
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-stated "$RD_CHK" "a sentence"
s42_unchanged "RD-10 a finding that is a check owed, with no deferred: line, is not stated" 1 "$PSEV"
expect_contains "RD-10b …naming why" "carries no deferred: line for $RD_CHK" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-stated "record/wave-01-fixture/nowhere.md#9" "a sentence"
s42_unchanged "RD-10c a finding the plan does not hold" 1 "$PSEV"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-stated "$RD_ID5" "-"
s42_unchanged "RD-10d the sentence - (what the continuation writes for none)" 1 "$PSEV"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-stated "$RD_ID5" "   "
s42_unchanged "RD-10e a blank sentence is the usage error" 2 "$PSEV"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-stated "$RD_ID5"
s42_unchanged "RD-10f one operand is the usage error" 2 "$PSEV"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-stated "no-hash-here" "a sentence"
s42_unchanged "RD-10g a finding that is not <record>#<n> is the usage error" 2 "$PSEV"
poke "$RSEV" finding-stated "$RD_ID5" "a sentence for the last deferral"
expect_eq "RD-10h control: the same call on a deferral exits 0, so the refusals above are the verb's own" "0" "$RC"
expect_eq "RD-10i …and writes the sentence" "1" "$(rd_line "$RD_ID5" | /usr/bin/grep -c 'stated="a sentence for the last deferral"')"

# ---------- the arm: a subagent may not state a deferral ----------
rd_wall() {  # <command> -> the real wall's exit and refusal for a rostered subagent's call
  local input
  input="$(jq -n --arg s "$SID" --arg cwd "$RSEV" --arg cmd "$1" '{session_id: $s, cwd: $cwd,
    hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd},
    tool_use_id: "toolu_rd", agent_id: "a-implementor", agent_type: "implementor"}')"
  GATE_ERR="$( cd "$RSEV" && CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 \
    bash "${BIONIC_HOOKS_DIR}/bash-walls.sh" <<< "$input" 2>&1 >/dev/null )"
  GATE_RC=$?
}
rd_wall "bash $POKER finding-stated '$RD_ID5' 'a sentence'"
expect_eq "RD-11 a subagent's finding-stated is refused by the existing arm (exit 2)" "2" "$GATE_RC"
expect_contains "RD-11b …naming the rule" "a subagent may not change a contract or the plan" "$GATE_ERR"
rd_wall "bash $POKER tick"
expect_eq "RD-11c control: a read-only verb of the same agent is admitted" "0" "$GATE_RC"

# ---------- the mutation arms: a doctored copy of the poker per fix ----------
RD_MUT="$(mktemp -d "${TMPDIR:-/tmp}/poker-rd-mut.XXXXXX")"
rd_mutant() {  # <name> <sed script> -> $RD_MUT/<name>/hooks/session-poker.sh, siblings and lib linked in
  local d="$RD_MUT/$1" _sib
  mkdir -p "$d/hooks" "$d/scripts"
  ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$d/scripts/lib"
  for _sib in "$(dirname "$POKER")"/*; do
    [ "$(basename "$_sib")" = session-poker.sh ] && continue
    ln -s "$_sib" "$d/hooks/$(basename "$_sib")"
  done
  sed "$2" "$POKER" > "$d/hooks/session-poker.sh"
}
rd_mutant nowrite 's/^    FS_TAIL=" stated=.*$/    FS_TAIL=""/'
rd_mutant inverted 's/^    \[ -n "\$DS_ST" \] && case .*$/    [ -n "$DS_ST" ] \&\& case "$DS_CL" in *"$DS_ST"*) : ;; *) DS_ANS=stated ;; esac/'
expect_eq "RD-mut0 each doctored poker differs from the real one in exactly one line (the doctors took)" "1|1" \
  "$(diff "$POKER" "$RD_MUT/nowrite/hooks/session-poker.sh" | /usr/bin/grep -c '^>')|$(diff "$POKER" "$RD_MUT/inverted/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
RD_REAL_POKER="$POKER"
POKER="$RD_MUT/nowrite/hooks/session-poker.sh"
poke "$RSEV" finding-stated "$RD_ID5" "a sentence for the doctored verb"
POKER="$RD_REAL_POKER"
expect_eq "RD-mut1 the verb with its write removed still runs (exit 0)" "0" "$RC"
expect_eq "RD-mut1b …and writes no sentence, where the real verb writes it (RD-2b, RD-10i go red on it)" "0" \
  "$(rd_line "$RD_ID5" | /usr/bin/grep -c 'a sentence for the doctored verb')"
poke "$RSEV" finding-stated "$RD_ID5" "a sentence for the doctored verb"
expect_eq "RD-mut1c …control: the real verb, given the same call, writes it" "0|1" \
  "$RC|$(rd_line "$RD_ID5" | /usr/bin/grep -c 'a sentence for the doctored verb')"
POKER="$RD_MUT/inverted/hooks/session-poker.sh"
poke "$RSEV" release-check
POKER="$RD_REAL_POKER"
expect_eq "RD-mut2 the release check with its match inverted still runs and prints its deferrals (exit 0)" "0|yes" \
  "$RC|$([ -n "$(rd_state "$RD_ID2")" ] && echo yes || echo no)"
expect_eq "RD-mut2b …and reads the stated deferral unstated, which RD-6 and RD-8b read stated (they go red on it)" "unstated" "$(rd_state "$RD_ID1")"
rm -rf "$RD_MUT"

cp "$TMPROOT/rd-config" "$RSEV/.bionic/config.yaml"
POKE_BOUND="$RD_BOUND_WAS"

# ============================================================
section "§SHARE-VERB: session-poker.sh share prints the machine's share and share <n> sets it (wave-28 T10; REQ-2 AC-2.1 surfaces; D16)"
# ============================================================
#
# `share` prints what `gate_share` prints; `share <n>` writes one integer, 1 to 100, to
# `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share` (the path expression gate_share reads) and refuses anything
# else with one line. Main thread only: `share` joins the existing contract-verb arm's list. EVERY drive here names
# its own CLAUDE_CONFIG_DIR (and a HOME of its own where it unsets it), so no row can write this machine's file.
SV_CCD_WAS="${CLAUDE_CONFIG_DIR-__unset__}"; SV_HOME_WAS="$HOME"
SV_ROOT="$(mktemp -d "$TMPROOT/share-verb.XXXXXX")"
SV_R="$(make_repo share-verb)"
new_roster "$SV_R"
roster_row_fixture session="$SID" name=implementor agent_id=a-implementor subagent_type=implementor >> "$(roster_of "$SV_R")"
SV_CCD="$SV_ROOT/ccd"; SV_FILE="$SV_CCD/bionic/share"; mkdir -p "$SV_CCD"
sv_poke() {  # <args...> -> the verb under CLAUDE_CONFIG_DIR=$SV_CCD, from the engaged fixture repo
  export CLAUDE_CONFIG_DIR="$SV_CCD"
  poke "$SV_R" "$@"
}
sv_read() { { read -r SV_V < "$SV_FILE"; } 2>/dev/null; printf '%s' "${SV_V:-}"; SV_V=""; }
sv_gate_read() {  # <ccd> [<env assignment>...] -> what gate_share prints under that config directory
  local ccd="$1"; shift
  env "$@" CLAUDE_CONFIG_DIR="$ccd" HOME="$SV_ROOT/nohome" bash -c '. "$1" 2>/dev/null; gate_share' _ \
    "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)/gate.sh"
}

sv_poke share
expect_eq "SV-1 with no share file the verb prints 80 (exit 0)" "0|80" "$RC|$OUT"
expect_eq "SV-1b …and writes nothing: reading made no file" "no" "$([ -e "$SV_FILE" ] && echo yes || echo no)"
sv_poke share 70
expect_eq "SV-2 share 70 exits 0" "0" "$RC"
expect_eq "SV-2b …writes the file: one integer on one line" "70" "$(sv_read)"
expect_eq "SV-2c …the file is that line and nothing else" "1" "$(wc -l < "$SV_FILE" | tr -d ' ')"
expect_eq "SV-2d …and says so on one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_contains "SV-2e …naming the value" "70" "$OUT"
sv_poke share
expect_eq "SV-3 share prints 70 now (exit 0)" "0|70" "$RC|$OUT"
expect_eq "SV-3b …and gate_share, read under the same config directory, prints what the verb printed" "70" "$(sv_gate_read "$SV_CCD")"

# the edges, then the refusals — each beside a set that wrote, so an unchanged file is read as unchanged
sv_poke share 1
expect_eq "SV-4 share 1 is the lowest value taken" "0|1" "$RC|$(sv_read)"
sv_poke share 100
expect_eq "SV-4b share 100 is the highest" "0|100" "$RC|$(sv_read)"
sv_poke share 070
expect_eq "SV-4c share 070 is read as the integer 70 and written as 70" "0|70" "$RC|$(sv_read)"
for SV_BAD in 0 101 abc -5 5.5 "" " 7" 7x 1000 +5 0x10 99999999999999999999; do
  sv_poke share 70
  sv_poke share "$SV_BAD"
  expect_eq "SV-5 share '$SV_BAD' is refused (exit 1) with one line" "1|1" "$RC|$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  expect_contains "SV-5b …that begins REFUSED and names the range" "poker: REFUSED — " "$OUT"
  expect_eq "SV-5c …and the share is as it was (70)" "70" "$(sv_read)"
done
sv_poke share 70
sv_poke share 50 60
expect_eq "SV-6 two operands are the usage error (exit 2)" "2|70" "$RC|$(sv_read)"
expect_eq "SV-6b …and the file is as it was, a set beside it having written (70)" "70" "$(sv_read)"

# a share that cannot be written is refused, one line
SV_BLOCK="$SV_ROOT/blocked"; : > "$SV_BLOCK"
CLAUDE_CONFIG_DIR_SAVE="$SV_CCD"; SV_CCD="$SV_BLOCK/under-a-file"
sv_poke share 40
expect_eq "SV-7 a config directory that cannot hold the file is refused (exit 1) with one line" "1|1" \
  "$RC|$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_contains "SV-7b …saying the share is unchanged" "unchanged" "$OUT"
SV_CCD="$CLAUDE_CONFIG_DIR_SAVE"

# no CLAUDE_CONFIG_DIR: the file is under $HOME/.claude, as the gate reads it
SV_HOME="$SV_ROOT/home"; mkdir -p "$SV_HOME"
unset CLAUDE_CONFIG_DIR; export HOME="$SV_HOME"
poke "$SV_R" share 60
SV_RC_H="$RC"
poke "$SV_R" share
SV_OUT_H="$OUT"
export HOME="$SV_HOME_WAS"
expect_eq "SV-8 with CLAUDE_CONFIG_DIR unset the verb writes \$HOME/.claude/bionic/share and reads it back" "0|60" "$SV_RC_H|$SV_OUT_H"
expect_eq "SV-8b …and gate_share under that HOME reads the same" "60" \
  "$(env -u CLAUDE_CONFIG_DIR HOME="$SV_HOME" bash -c '. "$1" 2>/dev/null; gate_share' _ \
      "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)/gate.sh")"

# BIONIC_CLAUDE_HOME moves the claude home for most readers; the gate's share file ignores it, so the verb's write must
# meet the gate's read there too (T2's path choice stands; read-structure-p6 #3)
SV_BCH="$SV_ROOT/bch"; mkdir -p "$SV_BCH/bionic"
printf '33\n' > "$SV_BCH/bionic/share"
export BIONIC_CLAUDE_HOME="$SV_BCH"
sv_poke share 45
SV_RC_B="$RC"
unset BIONIC_CLAUDE_HOME
expect_eq "SV-9 with BIONIC_CLAUDE_HOME set the verb writes the CLAUDE_CONFIG_DIR file (exit 0, 45)" "0|45" "$SV_RC_B|$(sv_read)"
expect_eq "SV-9b …gate_share under the same two variables reads that write" "45" \
  "$(sv_gate_read "$SV_CCD" BIONIC_CLAUDE_HOME="$SV_BCH")"
expect_eq "SV-9c …and the other claude home's file was not touched (33)" "33" "$(head -1 "$SV_BCH/bionic/share")"

# the share is the machine's, not a run's: a directory no run engaged answers the same
SV_PLAIN="$SV_ROOT/plain"; mkdir -p "$SV_PLAIN"
export CLAUDE_CONFIG_DIR="$SV_CCD"
poke "$SV_PLAIN" share 55
expect_eq "SV-10 from a directory that is no engaged run the verb still sets the share (exit 0, 55)" "0|55" "$RC|$(sv_read)"
poke "$SV_PLAIN" share
expect_eq "SV-10b …and prints it" "0|55" "$RC|$OUT"

# usage lists it
poke "$SV_R"
expect_contains "SV-11 the usage names the share verb" "session-poker.sh share" "$OUT"

# the arm: a subagent may call neither form
sv_wall() {  # <command> -> the real wall's exit and refusal for a rostered subagent's call
  local input
  input="$(jq -n --arg s "$SID" --arg cwd "$SV_R" --arg cmd "$1" '{session_id: $s, cwd: $cwd,
    hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd},
    tool_use_id: "toolu_sv", agent_id: "a-implementor", agent_type: "implementor"}')"
  GATE_ERR="$( cd "$SV_R" && CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WALL_VERBOSE=1 \
    bash "${BIONIC_HOOKS_DIR}/bash-walls.sh" <<< "$input" 2>&1 >/dev/null )"
  GATE_RC=$?
}
sv_wall "bash $POKER share 90"
expect_eq "SV-12 a subagent's share <n> is refused by the existing arm (exit 2)" "2" "$GATE_RC"
expect_contains "SV-12b …naming the rule" "a subagent may not change a contract or the plan" "$GATE_ERR"
sv_wall "bash $POKER share"
expect_eq "SV-12c …and its bare share, the arm's list being by verb (exit 2)" "2" "$GATE_RC"
sv_wall "bash $POKER tick"
expect_eq "SV-12d control: a read-only verb of the same agent is admitted" "0" "$GATE_RC"
expect_eq "SV-12e …and none of those calls wrote the share (still 55)" "55" "$(sv_read)"

# mutation: a poker that writes to BIONIC_CLAUDE_HOME's directory, as claude_home would, and the meet row reads it
SV_MUT="$(mktemp -d "${TMPDIR:-/tmp}/poker-sv-mut.XXXXXX")"
mkdir -p "$SV_MUT/hooks" "$SV_MUT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$SV_MUT/scripts/lib"
for SV_SIB in "$(dirname "$POKER")"/*; do
  [ "$(basename "$SV_SIB")" = session-poker.sh ] && continue
  ln -s "$SV_SIB" "$SV_MUT/hooks/$(basename "$SV_SIB")"
done
sed 's|SH_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share"|SH_FILE="${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/bionic/share"|' "$POKER" > "$SV_MUT/hooks/session-poker.sh"
expect_eq "SV-mut0 the doctored poker differs from the real one in exactly one line (the doctor took)" "1" \
  "$(diff "$POKER" "$SV_MUT/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
SV_REAL_POKER="$POKER"; POKER="$SV_MUT/hooks/session-poker.sh"
export BIONIC_CLAUDE_HOME="$SV_BCH"
sv_poke share 11
SV_RC_M="$RC"
unset BIONIC_CLAUDE_HOME
POKER="$SV_REAL_POKER"
expect_eq "SV-mut1 the doctored verb still runs (exit 0)" "0" "$SV_RC_M"
expect_eq "SV-mut1b …and writes the other home's file, where the real verb wrote the gate's (SV-9, SV-9c go red on it)" "11" \
  "$(head -1 "$SV_BCH/bionic/share")"
expect_ne "SV-mut1c …so gate_share under the two variables no longer reads the write" "11" \
  "$(sv_gate_read "$SV_CCD" BIONIC_CLAUDE_HOME="$SV_BCH")"
rm -rf "$SV_MUT" "$SV_ROOT"
if [ "$SV_CCD_WAS" = "__unset__" ]; then unset CLAUDE_CONFIG_DIR; else export CLAUDE_CONFIG_DIR="$SV_CCD_WAS"; fi
export HOME="$SV_HOME_WAS"

# ============================================================
section "§ROW-LABEL: the launch record binds a launch by its row= first, the name after (wave-28 T7; REQ-3 AC-3.4, D17)"
# ============================================================
# A brief's `Row: <id>` is written on the launch row as `row=<id>` (hooks/dispatch-preflight.sh).
# `launch-sync` reads it before the name match: an agent named `w-T24` briefed `Row: T23` sets T23
# active, never T24, whose id its name carries (AC-3.4's `w-A2` case, made stricter: a plan id is `T<n>`). The name match stays the fallback (Section 49's
# w-T6, which carries no row=). FIXTURE: Section 49's plan shape, rows T23 and T24 pending, a real
# linked tree recorded for the name. fails-when: T23 stays pending, or T24 is set active.
SRL_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RRL="$(make_repo s-t7-row)"; ( cd "$RRL" && git commit -q --allow-empty -m init )
PRL="$(s34_plan "$RRL" 4)"
sed -e 's/^| T2 | 4 | build | the second build | implementor |/| T2 | 4 | build | the second build | w-T2 |/' \
    "$PRL" > "$PRL.tmp" && mv "$PRL.tmp" "$PRL"
awk '{ print } /^- T5: pending dispatch/ { print "- T23: pending dispatch"; print "- T24: pending dispatch" }
  /^\| T2 \| 4 \| build/ {
  print "| T23 | 4 | build | the labelled build | — | — | 30 | REQ-1 | h.sh | — | — | pending |"
  print "| T24 | 4 | build | the named build | — | — | 30 | REQ-1 | i.sh | — | — | pending |" }' "$PRL" > "$PRL.tmp" && mv "$PRL.tmp" "$PRL"
new_roster "$RRL"
add_row "$RRL" name=w-T2 agent_id=a-w-T2 launched_at="$(iso_ago 600)"
printf '%s|row=T23|lands_on=a.test.sh\n' "$(mkrow name=w-T24 agent_id=a-w-T24 launched_at="$(iso_ago 60)" deliverable=a2.md \
  duration="45 minutes" subagent_type=bionic:implementor)" >> "$(roster_of "$RRL")"
TRL_TREE="$(cd "$RRL" && pwd -P)/.worktrees/01-T23"; git -C "$RRL" worktree add -q -b wt/01-T23 "$TRL_TREE" >/dev/null 2>&1
printf 'workspace/v1|session=%s|name=w-T24|path=%s|branch=wt/01-T23|base=0123456789abcdef0123456789abcdef01234567|plan=%s|at=2026-10-07T01:00:00Z\n' \
  "$SID" "$TRL_TREE" "$PRL" >> "$RRL/.bionic/tmp/workspaces-$SID.state"
expect_contains "RL precondition: the roster row carries row=T23" "|row=T23" "$(grep 'name=w-T24' "$(roster_of "$RRL")")"
expect_contains "RL precondition: T23 is in the table, pending" "| h.sh | — | — | pending |" "$(grep '^| T23 |' "$PRL")"
s34_gate "$RRL"
expect_eq "RL precondition: the fixture is admitted by the real commit gate" "0" "$GATE_RC"
poke_pressure "$RRL" 8192 1.0 tick
expect_contains "RL1 the tick records w-T24 under its Row: label, T23, and says so" "poker: LAUNCHED T23 w-T24" "$OUT"
expect_contains "RL1b …row T23 is active in its tree, its agent w-T24" \
  "| w-T24 | — | 30 | REQ-1 | h.sh | .worktrees/01-T23 | 01234567 | active |" "$(grep '^| T23 |' "$PRL")"
expect_contains "RL1c …and T24, which the name alone would have matched, stays pending" "| i.sh | — | — | pending |" \
  "$(grep '^| T24 |' "$PRL")"
POKE_BOUND="$SRL_BOUND_WAS"

# ============================================================
section "§CHECK: a finding the reviewer cannot settle owes a check — the settle verb, the effective rating at every read, and the step held while a check is open (wave-28 T41; REQ-8 AC-8.6; D33)"
# ============================================================
#
# An `unsure:` finding writes `check: <record>#<n> <S> <reach> "<title>"` at registration (§SEV), and
# the finding is neither a fix nor a deferral until a check settles it:
#
#   finding-check <record>#<n> settled <S> <reach> <check record>   ` settled=<S>:<reach> by=<check record>`
#   finding-check <record>#<n> refuted <check record>               ` refuted by=<check record>`
#   finding-check <record>#<n> unsettled <check record>             ` settled=<its own S>:<reach> by=…`
#
# appended to the check: line in place, through the plan transaction; a settlement the table defers
# writes the finding's `deferred:` line too. Every read of a registered record applies the effective
# rating (lib/proof.sh `proof_finding_rating`): the owed reader, the tick, and the judge, which derives
# a reading's result again from its findings. `current 8` is refused while a check: line carries
# neither ` settled=` nor ` refuted`, naming each. The check record is a file under the record
# directory whose `written-by: <name>` line names an agent that is neither the reviewer on the
# finding's proof line nor the agent of a `## Tasks` row whose Files hold the finding's file.
# FIXTURE FIDELITY: §SEV's repository, plan and roster; each reading is registered by the real verb.
CHK_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
printf '%s|questions=adversarial|pushed=checks-adversarial,severity\n' \
  "$(roster_row_fixture session="$SID" name=chk-crit agent_id=a-chk-crit subagent_type=bionic:critic \
     files="$(sev_files "k-base k-open k-fixto k-defer k-note k-ref k-uns k-w")")" >> "$SEV_RS"
chk_id() { printf 'record/wave-01-fixture/%s.md#1' "$1"; }
chk_line() { /usr/bin/grep -F "check: $(chk_id "$1") " "$PSEV"; }
chk_owed() { bash -c '. "$1"; proof_findings_owed "$2"' _ "$SEV_LIB" "$PSEV" 2>/dev/null | /usr/bin/grep -F "$(chk_id "$1") "; }
chk_cur() { sed -n 's/^current: //p' "$PSEV"; }
CHK_A=record/wave-01-fixture/chk-a.md
chk_rec chk-a chk-agent; chk_rec chk-rev chk-crit; chk_rec chk-writer implementor; chk_rec chk-anon -
mkdir -p "$RSEV/notes"; printf 'written-by: chk-agent\n' > "$RSEV/notes/chk-out.md"
expect_contains "CHECK-0 precondition: the Tasks row whose Files hold b.sh names implementor as its agent" \
  "| implementor | — | 30 | REQ-1 | b.sh |" "$(/usr/bin/grep '^| T2 |' "$PSEV")"
# The working head moved past C1 after §CUR8-sev (§RC-STATED commits the changelog), so the facts the
# judge reads are planted again at it (§CUR8-sev's way), and each reading below reads to it.
SEV_C1="$(git -C "$SEV_WT" rev-parse HEAD)"
sev_put "$(bash -c '. "$1" && proof_line floor "$2" 2026-10-07T12:00:00Z record/wave-01-fixture/floor.log' _ "$SEV_LIB" "$SEV_C1")"
sev_fact review evidence piece; sev_fact review structure piece; sev_fact review structure whole; sev_fact review adversarial whole
sev_rec k-base flag "findings: 1" "finding: 1 S4 off - a word the reader rated" 
sev_cur 4; sev_add k-base chk-crit; sev_cur 7
poke "$RSEV" current 8
expect_eq "CHECK-0b precondition: with every fact at the working head and no check open, current 8 is admitted" "0|8" "$RC|$(chk_cur)"

# ---------- an open check holds the step ----------
sev_cur 4
sev_rec k-open flag "findings: 1" "finding: 1 S3 off - a message the reader could not rate" "unsure: 1 which shells print it"
sev_add k-open chk-crit
expect_eq "CHECK-1 §CHECK AC-8.6 an unsure finding registers and writes its check: line (exit 0)" \
  "0|check: $(chk_id k-open) S3 off \"a message the reader could not rate\"" "$RC|$(chk_line k-open)"
expect_eq "CHECK-2 …the owed reader prints it as what it is, a check, not a priority" \
  "$(chk_id k-open) S3 off check \"a message the reader could not rate\"" "$(chk_owed k-open)"
sev_cur 7; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" current 8
s42_unchanged "CHECK-3 §CHECK current 8 while a check: line carries neither settled= nor refuted" 1 "$PSEV"
expect_contains "CHECK-3b …naming the open check" "$(chk_id k-open) S3 off \"a message the reader could not rate\"" "$OUT"
expect_contains "CHECK-3c …and the verb that settles it" "finding-check <record>#<n>" "$OUT"
# unsettled: the line's own rating stands, and with no check open the step is admitted.
sev_cur 4
poke "$RSEV" finding-check "$(chk_id k-open)" unsettled "$CHK_A"
expect_eq "CHECK-4 unsettled settles at the line's own rating (exit 0)" \
  "0|check: $(chk_id k-open) S3 off \"a message the reader could not rate\" settled=S3:off by=$CHK_A" "$RC|$(chk_line k-open)"
expect_eq "CHECK-4b …and every read takes the table's priority for it again" \
  "$(chk_id k-open) S3 off note \"a message the reader could not rate\"" "$(chk_owed k-open)"
sev_cur 7; poke "$RSEV" current 8
expect_eq "CHECK-4c …and current 8 is admitted once no check is open" "0|8" "$RC|$(chk_cur)"
sev_cur 4; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-check "$(chk_id k-open)" settled S1 on "$CHK_A"
s42_unchanged "CHECK-5 a second settlement of a settled check: line" 1 "$PSEV"
expect_contains "CHECK-5b …naming the settlement it already carries" "settled=S3:off" "$OUT"

# ---------- settled to fix: the reading's result is derived again ----------
sev_rec k-fixto flag "findings: 1" "finding: 1 S3 off - a path the reader could not run" "unsure: 1 needs a second machine"
sev_add k-fixto chk-crit
poke "$RSEV" finding-check "$(chk_id k-fixto)" settled S1 on "$CHK_A"
expect_eq "CHECK-6 settled <S> <reach> appends settled=<S>:<reach> by=<check record> (exit 0)" \
  "0|check: $(chk_id k-fixto) S3 off \"a path the reader could not run\" settled=S1:on by=$CHK_A" "$RC|$(chk_line k-fixto)"
expect_eq "CHECK-6b …and the owed reader rates it as settled, to fix" \
  "$(chk_id k-fixto) S1 on fix \"a path the reader could not run\"" "$(chk_owed k-fixto)"
sev_cur 7; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" current 8
s42_unchanged "CHECK-6c …and current 8 is refused on a reading written result=flag: its result is derived through the settled rating" 1 "$PSEV"
expect_contains "CHECK-6d …naming that reading failing" \
  "$(printf 'review\tadversarial\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/k-fixto.md')" "$OUT"
sev_cur 4

# ---------- settled to defer: the deferred: line is written ----------
sev_rec k-defer flag "findings: 1" "finding: 1 S4 off - wording the reader could not judge" "unsure: 1 the audience is unknown"
sev_add k-defer chk-crit
expect_eq "CHECK-7-pre precondition: an unsure note writes no deferred: line" "0" "$(/usr/bin/grep -c "^deferred: $(chk_id k-defer) " "$PSEV")"
poke "$RSEV" finding-check "$(chk_id k-defer)" settled S2 off "$CHK_A"
expect_eq "CHECK-7 a settlement the table defers writes the finding's deferred: line (exit 0)" \
  "0|deferred: $(chk_id k-defer) S2 off \"wording the reader could not judge\"" "$RC|$(/usr/bin/grep "^deferred: $(chk_id k-defer) " "$PSEV")"
expect_eq "CHECK-7b …and the owed reader gives it defer" "$(chk_id k-defer) S2 off defer \"wording the reader could not judge\"" "$(chk_owed k-defer)"
sev_cur 7; poke "$RSEV" current 8
expect_eq "CHECK-7c …and a deferral does not hold the step: current 8 is admitted" "0|8" "$RC|$(chk_cur)"
sev_cur 4

# ---------- settled to a note: a reading written result=fail is admitted ----------
sev_rec k-note fail "findings: 1" "finding: 1 S1 on - a crash the reader could not reproduce" "unsure: 1 no core file"
sev_add k-note chk-crit
poke "$RSEV" finding-check "$(chk_id k-note)" settled S4 on "$CHK_A"
expect_eq "CHECK-8 settled to a note (exit 0), and the owed reader gives it note" \
  "0|$(chk_id k-note) S4 on note \"a crash the reader could not reproduce\"" "$RC|$(chk_owed k-note)"
sev_cur 7; poke "$RSEV" current 8
expect_eq "CHECK-8b …and current 8 is admitted though the proof line says result=fail: the judge derives it through the settled rating" \
  "0|8" "$RC|$(chk_cur)"
sev_cur 4

# ---------- refuted: the finding is dropped ----------
sev_rec k-ref fail "findings: 1" "finding: 1 S2 on - a leak the reader could not show" "unsure: 1 the tool is not here"
sev_add k-ref chk-crit
poke "$RSEV" finding-check "$(chk_id k-ref)" refuted "$CHK_A"
expect_eq "CHECK-9 refuted appends refuted by=<check record> (exit 0)" \
  "0|check: $(chk_id k-ref) S2 on \"a leak the reader could not show\" refuted by=$CHK_A" "$RC|$(chk_line k-ref)"
expect_eq "CHECK-9b …and every read drops it: the owed reader prints nothing for it" "" "$(chk_owed k-ref)"
sev_cur 7; poke "$RSEV" current 8
expect_eq "CHECK-9c …and current 8 is admitted on the reading written result=fail" "0|8" "$RC|$(chk_cur)"
sev_cur 4

# ---------- unsettled keeps the line's own rating, the higher one ----------
sev_rec k-uns fail "findings: 1" "finding: 1 S1 off - a race the reader could not time" "unsure: 1 needs load"
sev_add k-uns chk-crit
poke "$RSEV" finding-check "$(chk_id k-uns)" unsettled "$CHK_A"
expect_eq "CHECK-10 unsettled keeps S1 off: the owed reader gives it fix (exit 0)" \
  "0|$(chk_id k-uns) S1 off fix \"a race the reader could not time\"" "$RC|$(chk_owed k-uns)"
sev_cur 7; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" current 8
s42_unchanged "CHECK-10b …and current 8 is refused, the reading failing at the rating the record wrote" 1 "$PSEV"
expect_contains "CHECK-10c …naming that reading failing" \
  "$(printf 'review\tadversarial\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/k-uns.md')" "$OUT"
sev_cur 4

# ---------- who may write a check record, and where ----------
sev_rec k-w flag "findings: 1" "finding: 1 S3 off b.sh:3 a call the reader could not trace" "unsure: 1 the caller is generated"
sev_add k-w chk-crit
expect_eq "CHECK-11-pre precondition: k-w registers with its check: line (exit 0)" "0|1" "$RC|$(chk_line k-w | wc -l | tr -d ' ')"
for c in "chk-rev@by the finding's reviewer@chk-crit" "chk-writer@by the writer of the code the finding names@implementor" \
         "chk-anon@that does not say who wrote it@written-by:" "chk-missing@that does not exist@does not exist"; do
  f="${c%%@*}"; rest="${c#*@}"; why="${rest%%@*}"; want="${rest#*@}"
  s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check "$(chk_id k-w)" refuted "record/wave-01-fixture/$f.md"
  s42_unchanged "CHECK-11 a check record $why ($f)" 1 "$PSEV"
  expect_contains "CHECK-11 …$f says why" "$want" "$OUT"
done
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check "$(chk_id k-w)" refuted "$RSEV/notes/chk-out.md"
s42_unchanged "CHECK-12 a check record outside the record directory" 1 "$PSEV"
expect_contains "CHECK-12b …naming the record directory" "is not under record/" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check record/wave-01-fixture/nowhere.md#3 refuted "$CHK_A"
s42_unchanged "CHECK-13 a <record>#<n> with no check: line" 1 "$PSEV"
expect_contains "CHECK-13b …naming why" "carries no check: line for record/wave-01-fixture/nowhere.md#3" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check "$(chk_id k-w)" settled S5 on "$CHK_A"
s42_unchanged "CHECK-14 a settlement at a rating outside the scale" 1 "$PSEV"
poke "$RSEV" finding-check "$(chk_id k-w)" settled S3 on "$CHK_A"
expect_eq "CHECK-15 the same finding settled on a third agent's record is admitted (the refusals above were the writer's)" \
  "0|check: $(chk_id k-w) S3 off \"a call the reader could not trace\" settled=S3:on by=$CHK_A" "$RC|$(chk_line k-w)"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check "$(chk_id k-w)" confirmed "$CHK_A"
s42_unchanged "CHECK-16 usage: a fourth form" 2 "$PSEV"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check "$(chk_id k-w)" settled S1 "$CHK_A"
s42_unchanged "CHECK-16b usage: a settlement with no reach" 2 "$PSEV"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check record/wave-01-fixture/k-w.md refuted "$CHK_A"
s42_unchanged "CHECK-16c usage: a finding that is not <record>#<n>" 2 "$PSEV"

# ---------- the tick prints each open check once ----------
awk '{ print } /^current: / && !d { print "deferred: record/w/rev.md#4 S2 off \"both lines\""; print "check: record/w/rev.md#4 S2 off \"both lines\""; d = 1 }' \
  "$PSEVT" > "$PSEVT.tmp" && mv "$PSEVT.tmp" "$PSEVT"
poke_pressure "$RSEVT" 8192 1.0 tick
expect_nonempty "CHECK-17-pre the tick printed FINDING lines (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FINDING ')"
expect_eq "CHECK-17 the tick prints a finding with a deferred: and an open check: line once, as the check it owes" \
  'poker: FINDING record/w/rev.md#4 S2 off check "both lines"' "$(printf '%s\n' "$OUT" | /usr/bin/grep -F 'poker: FINDING record/w/rev.md#4 ')"

# ---------- the mutation arm: the seam returning the line's own rating for a settled line ----------
CHK_MUT="$(mktemp -d "$TMPROOT/chk-mut.XXXXXX")"
CHK_NEEDLE='settled=*:*) s="${st#settled=}"; r="${s#*:}"; s="${s%%:*}" ;;'
anchor "$SEV_LIB" "$CHK_NEEDLE" 1
CHK_N="$CHK_NEEDLE" awk 'BEGIN { n = ENVIRON["CHK_N"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) "settled=*:*) : ;;" substr($0, i + length(n)); print }' \
  "$SEV_LIB" > "$CHK_MUT/proof.sh"
chk_rate() { bash -c '. "$1"; proof_finding_rating "$2" "$3" "$4" "$5"' _ "$1" "$PSEV" "$2" "$3" "$4" 2>/dev/null; }
expect_eq "CHECK-mut0 the mutant differs from the library in one line" "1" "$(diff "$SEV_LIB" "$CHK_MUT/proof.sh" | /usr/bin/grep -c '^>')"
expect_eq "CHECK-mut1 the library rates the finding settled to fix at its settlement" "S1 on fix" "$(chk_rate "$SEV_LIB" "$(chk_id k-fixto)" S3 off)"
expect_eq "CHECK-mut2 the mutant runs: it drops the refuted finding as the library does" "" "$(chk_rate "$CHK_MUT/proof.sh" "$(chk_id k-ref)" S2 on)"
expect_eq "CHECK-mut2b …and rates a finding with no check: line at its own rating" "S2 off defer" \
  "$(chk_rate "$CHK_MUT/proof.sh" record/wave-01-fixture/t-S2-off.md#1 S2 off)"
expect_ne "CHECK-mut3 …and returns the line's own rating for the settled line, so CHECK-6b goes red" \
  "S1 on fix" "$(chk_rate "$CHK_MUT/proof.sh" "$(chk_id k-fixto)" S3 off)"
POKE_BOUND="$CHK_BOUND_WAS"

# ============================================================
section "§MOVE: a finding crosses the line only on words the user typed in this session, written with who, when and why, and never an S1 to defer (wave-28 T42; REQ-8 AC-8.9; D34)"
# ============================================================
#
#   finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>'
#
# lib/said.sh `user_said <text>` answers 0 when the text, its runs of white space folded, stands inside
# a prompt the user typed in this session's transcript; 1 when it stands in none; 2 when the transcript
# cannot be found or read. A tool's result, a teammate's message, another session's message, a hook's
# added context, the orchestrator's own text, a compaction summary, a pasted block and a dispatched
# agent's prompt never count. On rc 0 the verb writes, in place after the finding's own line,
# `moved: <record>#<n> to=<defer|fix> by=<git user.name> at=<ISO-UTC> words="<words>" why="<why>"`,
# and a `deferred:` line when the move is to defer; every read of the record then takes the priority
# it was moved to (lib/proof.sh `proof_finding_rating`).
#
# FIXTURE FIDELITY. The transcript is assembled from tests/fixtures/transcript-move/, one file per kind
# of entry, its key sets measured on CLI 2.1.291 transcripts and every word invented (that directory's
# README). It sits where the CLI writes one, `<CLAUDE_CONFIG_DIR>/projects/<slug>/<session id>.jsonl`,
# under a CLAUDE_CONFIG_DIR of this section's own, so no row reads this machine's transcripts. Every
# decoy carries the words the typed prompt carries (MOVE-<kind>-pre), so a reader that counted it would
# find them. The findings are registered by the real verb on §SEV's repository and plan.
MV_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
MV_CCD_WAS="${CLAUDE_CONFIG_DIR-__unset__}"
MV_CFG="$TMPROOT/mv-cfg"; MV_PROJ="$MV_CFG/projects/-work-project"; mkdir -p "$MV_PROJ"
export CLAUDE_CONFIG_DIR="$MV_CFG"
MV_TX="$MV_PROJ/$SID.jsonl"
MV_FX="${BIONIC_SCRIPTS_DIR}/tests/fixtures/transcript-move"
SAID_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/said.sh"
MV_P='defer the flag wording until the next wave, it can wait'
MV_Q='and move the third one to fix now'
MV_F='start the review of the parser'
mv_tx() { local f; cat "$MV_FX/frame.jsonl" > "$MV_TX"; for f in "$@"; do cat "$MV_FX/$f.jsonl" >> "$MV_TX"; done; }
mv_said() {  # <text> [<said.sh>] -> user_said's rc, in this session under this section's config
  # the library finds session.sh beside itself; a mutant copy in another directory has none, so it is
  # given the session function first (the library itself is run as the verb meets it, alone)
  env CLAUDE_CODE_SESSION_ID="$SID" bash -c '[ -z "$3" ] || . "$3"; . "$1" 2>/dev/null; user_said "$2"; echo "$?"' _ "${2:-$SAID_LIB}" "$1" "${2:+${SAID_LIB%/*}/session.sh}" 2>/dev/null
}
mv_id() { printf 'record/wave-01-fixture/%s.md#%s' "$1" "${2:-1}"; }
mv_owed() { bash -c '. "$1"; proof_findings_owed "$2"' _ "$SEV_LIB" "$PSEV" 2>/dev/null | /usr/bin/grep -F "$(mv_id "$1") "; }
mv_moved() { /usr/bin/grep -F "moved: $(mv_id "$1") " "$PSEV"; }

# ---------- user_said, on the library (unit rows) ----------
mv_tx typed
expect_eq "MOVE-said1 §MOVE the words of a typed prompt, its runs of white space folded: found (rc 0)" "0" "$(mv_said "$MV_P")"
expect_eq "MOVE-said2 …the words given with runs of their own, a line break and a tab: found" "0" \
  "$(mv_said "$(printf 'defer  the flag\nwording until the next wave,\tit can wait')")"
expect_eq "MOVE-said3 …words the transcript does not carry: not found (rc 1)" "1" "$(mv_said 'defer every finding at once')"
expect_eq "MOVE-said4 …white space alone says nothing (rc 1)" "1" "$(mv_said '   ')"
mv_tx queued
expect_eq "MOVE-said5 a prompt the user typed while a turn ran (a queued command): found" "0" "$(mv_said "$MV_Q")"
for c in "tool-result@a tool's result" "teammate@a teammate's message" "peer@another session's message" \
         "peer-queued@another session's message delivered mid-turn" "hook-context@a hook's added context" \
         "orchestrator@the orchestrator's own text" "compact@a compaction summary" \
         "pasted@a block the user pasted into a prompt" "sidechain@a dispatched agent's prompt"; do
  k="${c%%@*}"; d="${c#*@}"
  expect_contains "MOVE-$k-pre precondition: the $k fixture carries the words, as a raw read of the file finds them" \
    "$MV_P" "$(cat "$MV_FX/$k.jsonl")"
  mv_tx "$k"
  expect_eq "MOVE-said-$k §MOVE the same words only in $d: not found (rc 1)" "1" "$(mv_said "$MV_P")"
  expect_eq "MOVE-said-$k-pos …while the typed prompt beside it in the same transcript is found" "0" "$(mv_said "$MV_F")"
done
mv_tx typed; printf '{"type":"user","message":{"role":"us' >> "$MV_TX"
expect_eq "MOVE-said6 a transcript whose last line is torn mid-write is still read: found" "0" "$(mv_said "$MV_P")"
rm -f "$MV_TX"
expect_eq "MOVE-said-none no transcript for the session: rc 2" "2" "$(mv_said "$MV_P")"
mv_tx typed
expect_eq "MOVE-said-nosid …no session key: rc 2" "2" \
  "$(env -u CLAUDE_CODE_SESSION_ID bash -c '. "$1" 2>/dev/null; user_said "$2"; echo "$?"' _ "$SAID_LIB" "$MV_P" 2>/dev/null)"
chmod 000 "$MV_TX"
expect_eq "MOVE-said-unread …a transcript that cannot be read: rc 2" "2" "$(mv_said "$MV_P")"
chmod 600 "$MV_TX"; mv "$MV_TX" "$TMPROOT/mv-real.jsonl"; ln -s "$TMPROOT/mv-real.jsonl" "$MV_TX"
expect_eq "MOVE-said-link …a transcript that is a symbolic link is not this session's: rc 2" "2" "$(mv_said "$MV_P")"
rm -f "$MV_TX"; mv_tx typed
expect_eq "MOVE-said-back …and the same transcript, a regular file again, is found" "0" "$(mv_said "$MV_P")"

# ---------- whole words, and enough of them (wave-28 T66; REQ-8 AC-8.9; D34; A-orch-190) ----------
#
# user_said's two rules beside the fold. A WORD CHARACTER is a letter or digit (any script), `_`, `-` or
# `'`; a quote stands in a prompt only where the character before it and the one after it are not word
# characters (a prompt's own start and end count as neither), and the match is case-sensitive. A quote of
# fewer than THREE words (the folded text split on single spaces) answers rc 3, unless the folded quote is
# a whole typed prompt, which answers 0. rc 1 is the quote no prompt holds as whole words, however short.
mv_prompts() {  # <prompt>... -> a transcript: the frame, then one typed prompt each (the typed fixture's keys)
  local p; cat "$MV_FX/frame.jsonl" > "$MV_TX"
  for p in "$@"; do jq -c --arg p "$p" '.message.content = $p' "$MV_FX/typed.jsonl" >> "$MV_TX"; done
}
mv_prompts 'do not defer it, fix it now' 'press e, then 2 to pick' 'do not defer it at all'
expect_eq "MOVE-said-w1 §MOVE a quote of one word that stands whole in a prompt is too short (rc 3): '2'" "3" "$(mv_said '2')"
expect_eq "MOVE-said-w2 …'e'" "3" "$(mv_said 'e')"
expect_eq "MOVE-said-w3 …'it'" "3" "$(mv_said 'it')"
expect_eq "MOVE-said-w4 …'defer it' inside 'do not defer it, fix it now': it passes the boundary rule (not rc 1) and is refused as short (rc 3)" \
  "3" "$(mv_said 'defer it')"
expect_eq "MOVE-said-w5 …positive, the same transcript: the whole prompt 'do not defer it, fix it now' is found" "0" \
  "$(mv_said 'do not defer it, fix it now')"
expect_eq "MOVE-said-w6 …and three of its words, 'fix it now', are found" "0" "$(mv_said 'fix it now')"
expect_eq "MOVE-said-w7 …THE LIMIT OF MECHANICAL PROOF: 'defer it at all' out of 'do not defer it at all' passes both rules (negation is the reader's to judge from words=)" \
  "0" "$(mv_said 'defer it at all')"
mv_prompts 'defer it'
expect_eq "MOVE-said-w8 a prompt typed as 'defer it' alone: the quote 'defer it' is the user's whole word (rc 0)" "0" "$(mv_said 'defer it')"
expect_eq "MOVE-said-w9 …with the prompt's runs of white space and the quote's folded the same way: found" "0" \
  "$(mv_said "$(printf 'defer \t it')")"
expect_eq "MOVE-said-w10 …but one word of it, 'defer', is a quote of one word and not the prompt (rc 3)" "3" "$(mv_said 'defer')"
mv_prompts 'please defer it now'
expect_eq "MOVE-said-w11 'please defer it now' quoted as 'defer it now': three words, found (rc 0)" "0" "$(mv_said 'defer it now')"
expect_eq "MOVE-said-w12 …the quote's runs of white space and a line break folded: found" "0" "$(mv_said "$(printf 'defer   it\nnow')")"
expect_eq "MOVE-said-w13 …a control character between its words folds as white space does: found (one fold, in said.sh)" "0" \
  "$(mv_said "$(printf 'defer it\001now')")"
expect_eq "MOVE-said-w14 …the start cut inside a word, 'lease defer it now': not found (rc 1)" "1" "$(mv_said 'lease defer it now')"
expect_eq "MOVE-said-w15 …the end cut inside a word, 'please defer it no': not found (rc 1)" "1" "$(mv_said 'please defer it no')"
expect_eq "MOVE-said-w16 …a letter in another case, 'Defer it now': not found (rc 1)" "1" "$(mv_said 'Defer it now')"
expect_eq "MOVE-said-w17 …'defer it' inside it: two words, found as whole words and refused as short (rc 3)" "3" "$(mv_said 'defer it')"
mv_prompts 'undefer items now' 'prefix the name'
expect_eq "MOVE-said-w18 'undefer items' quoted as 'defer it': a word boundary at neither end, not found (rc 1)" "1" "$(mv_said 'defer it')"
expect_eq "MOVE-said-w19 …'fix' quoted against 'prefix': not found (rc 1)" "1" "$(mv_said 'fix')"
expect_eq "MOVE-said-w20 …positive, the same transcript: the whole prompt 'undefer items now' is found" "0" "$(mv_said 'undefer items now')"
mv_prompts "never pre-defer it now" "o'defer it now" 'step_defer it now' 'v2defer it now' 'édefer it now'
expect_eq "MOVE-said-w21 a word character joins what it touches: 'defer it now' after a hyphen, an apostrophe, an underscore, a digit and a letter of another script: not found (rc 1)" \
  "1" "$(mv_said 'defer it now')"
expect_eq "MOVE-said-w22 …positive, the same transcript: 'never pre-defer it' is found" "0" "$(mv_said 'never pre-defer it')"
mv_tx slash-args
expect_eq "MOVE-said-slash1 a slash command typed WITH arguments carries origin human: its arguments are found (rc 0)" "0" "$(mv_said 'tighten the second finding')"
expect_eq "MOVE-said-slash2 …and the CLI's wrapper text around them counts as typed: found" "0" \
  "$(mv_said 'review</command-name> <command-args>tighten the second')"
mv_tx slash-bare
expect_eq "MOVE-said-slash3 a slash command typed WITHOUT arguments carries no origin: its words are not found (rc 1)" "1" "$(mv_said "$MV_P")"
expect_eq "MOVE-said-slash4 …while the typed prompt beside it in the same transcript is found" "0" "$(mv_said "$MV_F")"
mv_tx typed

# ---------- the mutation arm: user_said counting a tool's result ----------
MV_MUT="$(mktemp -d "$TMPROOT/mv-mut.XXXXXX")"
MV_NEEDLE='if .type == "user" and .isMeta != true and .isSidechain != true and (.origin.kind? // "") == "human" then .message.content | words'
anchor "$SAID_LIB" "$MV_NEEDLE" 1
MV_N="$MV_NEEDLE" awk 'BEGIN { n = ENVIRON["MV_N"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) "if .type == \"user\" then .message.content | tostring" substr($0, i + length(n)); print }' \
  "$SAID_LIB" > "$MV_MUT/said.sh"
expect_eq "MOVE-mut0 the mutant differs from the library in one line" "1" "$(diff "$SAID_LIB" "$MV_MUT/said.sh" | /usr/bin/grep -c '^>')"
mv_tx tool-result
expect_eq "MOVE-mut1 the mutant runs: it finds the typed prompt as the library does" "0" "$(mv_said "$MV_F" "$MV_MUT/said.sh")"
expect_eq "MOVE-mut2 …and counts the tool's result, so MOVE-said-tool-result goes red under it" "0" "$(mv_said "$MV_P" "$MV_MUT/said.sh")"

# ---------- the mutation arms of the two rules (T66): each rule's line replaced, on a copy ----------
MV_BNEEDLE='def bounded($w; $p):'
MV_LNEEDLE='def enough($w; $p):'
anchor "$SAID_LIB" "$MV_BNEEDLE" 1
anchor "$SAID_LIB" "$MV_LNEEDLE" 1
mv_mutline() {  # <needle> <replacement line> <out> -> the library with the one line holding <needle> replaced
  MV_N="$1" MV_R="$2" awk 'BEGIN { n = ENVIRON["MV_N"] } index($0, n) { print ENVIRON["MV_R"]; next } { print }' "$SAID_LIB" > "$3"
}
mkdir -p "$MV_MUT/b" "$MV_MUT/l"
mv_mutline "$MV_BNEEDLE" 'def bounded($w; $p): $p | contains($w);' "$MV_MUT/b/said.sh"
mv_mutline "$MV_LNEEDLE" 'def enough($w; $p): true;' "$MV_MUT/l/said.sh"
expect_eq "MOVE-mutB0 the boundary mutant differs from the library in one line" "1" "$(diff "$SAID_LIB" "$MV_MUT/b/said.sh" | /usr/bin/grep -c '^>')"
expect_eq "MOVE-mutL0 the length mutant differs from the library in one line" "1" "$(diff "$SAID_LIB" "$MV_MUT/l/said.sh" | /usr/bin/grep -c '^>')"
mv_prompts 'undefer items now' 'prefix the name'
expect_eq "MOVE-mutB1 the boundary mutant runs: it finds a whole prompt as the library does" "0" "$(mv_said 'undefer items now' "$MV_MUT/b/said.sh")"
expect_eq "MOVE-mutB2 …and finds 'defer it' inside 'undefer items' (rc 3 for a short quote, not 1), so MOVE-said-w18 goes red under it" "3" \
  "$(mv_said 'defer it' "$MV_MUT/b/said.sh")"
expect_eq "MOVE-mutB3 …and finds 'fix' inside 'prefix', so MOVE-said-w19 goes red under it" "3" "$(mv_said 'fix' "$MV_MUT/b/said.sh")"
mv_prompts 'do not defer it, fix it now' 'press e, then 2 to pick'
expect_eq "MOVE-mutL1 the length mutant runs: it finds a whole prompt as the library does" "0" "$(mv_said 'do not defer it, fix it now' "$MV_MUT/l/said.sh")"
expect_eq "MOVE-mutL2 …and accepts 'it' (rc 0, not 3), so MOVE-said-w3 goes red under it" "0" "$(mv_said 'it' "$MV_MUT/l/said.sh")"
expect_eq "MOVE-mutL3 …and accepts 'defer it' inside a longer prompt, so MOVE-said-w4 goes red under it" "0" "$(mv_said 'defer it' "$MV_MUT/l/said.sh")"
mv_tx slash-bare
expect_eq "MOVE-mut3 the origin mutant counts a slash command typed without arguments, so MOVE-said-slash3 goes red under it" "0" \
  "$(mv_said "$MV_P" "$MV_MUT/said.sh")"
mv_tx typed

# ---------- the seam: a moved: line re-rates at every read (unit rows on a planted plan) ----------
MV_SP="$TMPROOT/mv-seam.plan.md"
mv_seam() {  # <moved: lines...> -> the plan holding them under ## SDLC State
  { printf '# plan\n\n## SDLC State\n\ncurrent: 4\n'; for l in "$@"; do printf '%s\n' "$l"; done; printf '\n## Tasks\n'; } > "$MV_SP"
}
mv_rate() { bash -c '. "$1"; proof_finding_rating "$2" "$3" "$4" "$5"' _ "$SEV_LIB" "$MV_SP" "$1" "$2" "$3" 2>/dev/null; }
MV_WHO='by=Dana Fixture at=2026-10-07T12:00:00Z words="later" why="the docs pass"'
mv_seam "moved: record/x.md#1 to=defer $MV_WHO"
expect_eq "MOVE-seam1 a finding to fix moved to defer takes defer at the read" "S2 on defer" "$(mv_rate record/x.md#1 S2 on)"
expect_eq "MOVE-seam1b …and a finding the line does not name keeps the table's priority" "S2 on fix" "$(mv_rate record/x.md#2 S2 on)"
mv_seam "moved: record/x.md#1 to=fix $MV_WHO"
expect_eq "MOVE-seam2 a deferral moved to fix takes fix at the read" "S2 off fix" "$(mv_rate record/x.md#1 S2 off)"
mv_seam "moved: record/x.md#1 to=fix $MV_WHO" "moved: record/x.md#1 to=defer $MV_WHO"
expect_eq "MOVE-seam3 two moves: the later one is the user's last word" "S2 on defer" "$(mv_rate record/x.md#1 S2 on)"
mv_seam "moved: record/x.md#1 to=defer $MV_WHO"
expect_eq "MOVE-seam4 a moved: line deferring an S1, written by hand, is not honoured: an S1 is never deferred" "S1 on fix" "$(mv_rate record/x.md#1 S1 on)"
mv_seam "moved: record/x.md#1 to=defer by=Dana Fixture at=2026-10-07T12:00:00Z words=\"later\""
expect_eq "MOVE-seam5 a moved: line that lacks why is not honoured" "S2 on fix" "$(mv_rate record/x.md#1 S2 on)"
mv_seam '```' "moved: record/x.md#1 to=defer $MV_WHO" '```'
expect_eq "MOVE-seam6 a moved: line inside a fence is not read" "S2 on fix" "$(mv_rate record/x.md#1 S2 on)"
mv_seam "check: record/x.md#1 S2 on \"t\"" "moved: record/x.md#1 to=defer $MV_WHO"
expect_eq "MOVE-seam7 a move keeps an open check open: the fourth word stays" "S2 on defer open" "$(mv_rate record/x.md#1 S2 on)"
mv_seam "check: record/x.md#1 S2 on \"t\" refuted by=record/c.md" "moved: record/x.md#1 to=fix $MV_WHO"
expect_eq "MOVE-seam8 a move does not bring back a refuted finding" "" "$(mv_rate record/x.md#1 S2 on)"
expect_eq "MOVE-seam8b …positive on the same plan: another finding is rated" "S3 off note" "$(mv_rate record/x.md#2 S3 off)"

# ---------- the verb, on §SEV's repository and plan ----------
printf '%s|questions=adversarial|pushed=checks-adversarial,severity\n' \
  "$(roster_row_fixture session="$SID" name=mv-crit agent_id=a-mv-crit subagent_type=bionic:critic \
     files="$(sev_files "mv-s1 mv-def mv-fix mv-later")")" >> "$SEV_RS"
sev_cur 4
sev_rec mv-s1 fail "findings: 1" "finding: 1 S1 on lib/a.sh:5 a write that loses the last line" "shown: 1 bash lib/a.sh --write"
sev_add mv-s1 mv-crit
expect_eq "MOVE-0 precondition: an S1 to fix registers (exit 0)" "0" "$RC"
sev_rec mv-def fail "findings: 1" "finding: 1 S2 on lib/a.sh:3 a flag the help text misnames" "shown: 1 bash lib/a.sh --help"
sev_add mv-def mv-crit
expect_eq "MOVE-0b precondition: an S2 to fix registers, and writes no deferred: line (exit 0)" "0|0" \
  "$RC|$(/usr/bin/grep -c "^deferred: $(mv_id mv-def) " "$PSEV")"
sev_cur 7; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" current 8
s42_unchanged "MOVE-0c precondition: the newest adversarial reading holds a finding to fix: current 8" 1 "$PSEV"
sev_cur 4

mv_tx typed
s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-move "$(mv_id mv-def)" defer "$(printf 'defer the flag  wording\nuntil the next wave, it can wait')" 'the wording waits for the docs pass'
expect_eq "MOVE-1 §MOVE AC-8.9 words that stand in a typed prompt move the finding (exit 0)" "0" "$RC"
expect_regex "MOVE-1b …the moved: line carries who, when, the words folded and why" \
  "^moved: $(mv_id mv-def) to=defer by=Dana Fixture at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z words=\"$MV_P\" why=\"the wording waits for the docs pass\"\$" \
  "$(mv_moved mv-def)"
expect_eq "MOVE-1c …a move to defer writes the finding's deferred: line" \
  "deferred: $(mv_id mv-def) S2 on \"a flag the help text misnames\"" "$(/usr/bin/grep "^deferred: $(mv_id mv-def) " "$PSEV")"
expect_eq "MOVE-1d …and the moved: line stands in place after the finding's own line" "moved: $(mv_id mv-def)" \
  "$(/usr/bin/grep -A1 "^deferred: $(mv_id mv-def) " "$PSEV" | tail -1 | awk '{ print $1, $2 }')"
expect_eq "MOVE-1e …the owed reader gives it the priority it was moved to" \
  "$(mv_id mv-def) S2 on defer \"a flag the help text misnames\"" "$(mv_owed mv-def)"
sev_cur 7; poke "$RSEV" current 8
expect_eq "MOVE-1f …and a finding moved to defer no longer holds the step: current 8 is admitted on a reading written result=fail" \
  "0|8" "$RC|$(sed -n 's/^current: //p' "$PSEV")"
sev_cur 4

# The same words in every other kind of entry, never in a typed prompt: each refused, the plan unchanged.
sev_rec mv-fix flag "findings: 1" "finding: 1 S2 off - a message the log prints twice"
sev_add mv-fix mv-crit
expect_eq "MOVE-2-pre precondition: a deferral registers with its deferred: line (exit 0)" \
  "0|deferred: $(mv_id mv-fix) S2 off \"a message the log prints twice\"" "$RC|$(/usr/bin/grep "^deferred: $(mv_id mv-fix) " "$PSEV")"
for k in tool-result teammate peer peer-queued hook-context orchestrator compact pasted sidechain; do
  mv_tx "$k"; s42_snap "$RSEV" "$PSEV"
  poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$MV_P" 'the user asked'
  s42_unchanged "MOVE-2-$k §MOVE AC-8.9 the words stand only in the $k entry" 1 "$PSEV"
  expect_contains "MOVE-2-$k …saying they stand in no prompt the user typed" "in no prompt the user typed" "$OUT"
done
rm -f "$MV_TX"; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$MV_P" 'the user asked'
s42_unchanged "MOVE-3 §MOVE no transcript for the session" 1 "$PSEV"
expect_contains "MOVE-3b …naming the transcript as what cannot be found or read" "transcript cannot be found or read" "$OUT"
mv_tx typed; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-move "$(mv_id mv-s1)" defer "$MV_P" 'the user asked'
s42_unchanged "MOVE-4 §MOVE AC-8.9 an S1 to defer, on words the user typed" 1 "$PSEV"
expect_contains "MOVE-4b …naming the rule" "an S1 is never deferred" "$OUT"
poke "$RSEV" finding-move "$(mv_id mv-s1)" fix "$MV_P" 'it stays a fix'
expect_eq "MOVE-4c …while the same S1 moved to fix on the same words is written (exit 0)" "0|1" "$RC|$(mv_moved mv-s1 | wc -l | tr -d ' ')"

# A deferral moved to fix holds the step until a later passing review covers the fix.
sev_cur 7; poke "$RSEV" current 8
expect_eq "MOVE-5-pre precondition: the deferral alone does not hold the step" "0|8" "$RC|$(sed -n 's/^current: //p' "$PSEV")"
sev_cur 4
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$MV_P" 'the log is read by the next tool'
expect_eq "MOVE-5 a deferral moved to fix on typed words (exit 0), and the owed reader gives it fix" \
  "0|$(mv_id mv-fix) S2 off fix \"a message the log prints twice\"" "$RC|$(mv_owed mv-fix)"
sev_cur 7; s42_snap "$RSEV" "$PSEV"
poke "$RSEV" current 8
s42_unchanged "MOVE-5b …and current 8 is refused on the reading written result=flag: its result is derived through the move" 1 "$PSEV"
expect_contains "MOVE-5c …naming that reading failing" \
  "$(printf 'review\tadversarial\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/mv-fix.md')" "$OUT"
sev_cur 4
sev_rec mv-later pass "findings: 0"
sev_add mv-later mv-crit
sev_cur 7; poke "$RSEV" current 8
expect_eq "MOVE-5d …until a later passing review covers the fix: current 8 is admitted" "0|8" "$RC|$(sed -n 's/^current: //p' "$PSEV")"
sev_cur 4

# Who, the finding, and the operands.
s42_snap "$RSEV" "$PSEV"
git -C "$RSEV" config --unset user.name
printf '' > "$TMPROOT/mv-nogit"
GIT_CONFIG_GLOBAL="$TMPROOT/mv-nogit" GIT_CONFIG_NOSYSTEM=1 poke "$RSEV" finding-move "$(mv_id mv-fix)" defer "$MV_P" 'the user asked'
git -C "$RSEV" config user.name "Dana Fixture"
s42_unchanged "MOVE-6 §MOVE AC-8.9 no git user.name to say who moved it" 1 "$PSEV"
expect_contains "MOVE-6b …naming what is missing" "user.name" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-move record/wave-01-fixture/nowhere.md#1 fix "$MV_P" 'the user asked'
s42_unchanged "MOVE-7 a record no proof line registers" 1 "$PSEV"
expect_contains "MOVE-7b …naming why" "registered" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-move "$(mv_id mv-def 3)" fix "$MV_P" 'the user asked'
s42_unchanged "MOVE-8 a finding number its record does not hold" 1 "$PSEV"
expect_contains "MOVE-8b …naming it" "holds no finding 3" "$OUT"
for c in "MOVE-9@a third form@$(mv_id mv-fix)@later@$MV_P@why" "MOVE-9b@no why@$(mv_id mv-fix)@fix@$MV_P@ " \
         "MOVE-9c@no words@$(mv_id mv-fix)@fix@ @why" "MOVE-9d@a finding that is not <record>#<n>@record/wave-01-fixture/mv-fix.md@fix@$MV_P@why"; do
  IFS=@ read -r lbl why1 id to w y <<EOF
$c
EOF
  s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-move "$id" "$to" "$w" "$y"
  s42_unchanged "$lbl usage: $why1" 2 "$PSEV"
done
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$MV_P"
s42_unchanged "MOVE-9e usage: three operands" 2 "$PSEV"
expect_contains "MOVE-9f …the usage names the verb's operands" "finding-move takes" "$OUT"

# ---------- the verb, on the two rules (T66) ----------
mv_prompts 'do not defer it, fix it now'
s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix 'it' 'the user said it'
s42_unchanged "MOVE-10 §MOVE a quote of one word is refused as too short" 1 "$PSEV"
MV_MIN="$(bash -c '. "$1" 2>/dev/null; printf "%s" "$SAID_MIN_WORDS"' _ "$SAID_LIB")"
MV_SHORT_LINE="poker: REFUSED — the words \"it\" are too short to be the user's decision; quote at least ${MV_MIN} of their words, or their whole prompt. The plan is unchanged."
expect_eq "MOVE-10b …with the refusal as measured" "$MV_SHORT_LINE" "$OUT"
s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix 'fix it' 'the user said it'
s42_unchanged "MOVE-10c 'fix it' inside a longer prompt is refused as too short as well" 1 "$PSEV"
expect_contains "MOVE-10d …naming the rule" "too short to be the user's decision" "$OUT"
s42_snap "$RSEV" "$PSEV"
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix 'zzz yyy' 'the user said it'
s42_unchanged "MOVE-10e two words no prompt holds are refused as standing in no prompt (not as short)" 1 "$PSEV"
expect_contains "MOVE-10f …naming that rule" "in no prompt the user typed" "$OUT"
MV_NMOVES="$(/usr/bin/grep -c "^moved: $(mv_id mv-fix) " "$PSEV")"
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix 'fix it now' 'three words are enough'
expect_eq "MOVE-10g positive, the same transcript: three of the user's words move the finding (exit 0, one more moved: line)" \
  "0|$((MV_NMOVES + 1))" "$RC|$(/usr/bin/grep -c "^moved: $(mv_id mv-fix) " "$PSEV")"
mv_prompts 'fix it'
MV_NMOVES="$(/usr/bin/grep -c "^moved: $(mv_id mv-fix) " "$PSEV")"
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$(printf 'fix \t it')" 'the whole prompt is the word'
expect_eq "MOVE-11 a quote of two words that is the user's whole prompt moves the finding (exit 0, one more moved: line)" \
  "0|$((MV_NMOVES + 1))" "$RC|$(/usr/bin/grep -c "^moved: $(mv_id mv-fix) " "$PSEV")"
expect_regex "MOVE-11b …its words= folded once, by the one rule" "words=\"fix it\" why=\"the whole prompt is the word\"\$" \
  "$(/usr/bin/grep "^moved: $(mv_id mv-fix) " "$PSEV" | tail -1)"
mv_prompts 'please defer it now'
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$(printf 'defer it\001now')" 'a control character is white space'
expect_regex "MOVE-12 a control character in the words is folded as white space, in the check and in the line (exit 0)" \
  "^0\|moved: .* words=\"defer it now\" why=\"a control character is white space\"\$" \
  "$RC|$(/usr/bin/grep "^moved: $(mv_id mv-fix) " "$PSEV" | tail -1)"
mv_tx typed

# ---------- the fixtures' key sets against this session's own transcript (read-only; key names only) ----------
# A CLI that renames a key the fixtures carry would make user_said refuse every real move without a word;
# this turns that into a red row. The transcript is the one the suite itself runs under, read where the CLI
# keeps it; a machine with none readable skips with its reason.
MV_REAL_SID="${CLAUDE_CODE_SESSION_ID:-}"
MV_REAL_CFG="$MV_CCD_WAS"; [ "$MV_REAL_CFG" != "__unset__" ] || MV_REAL_CFG="$HOME/.claude"
MV_REAL_TX=""
if [ -n "$MV_REAL_SID" ]; then
  for d in "$MV_REAL_CFG"/projects/*/; do
    [ -f "${d}${MV_REAL_SID}.jsonl" ] && [ -r "${d}${MV_REAL_SID}.jsonl" ] && [ ! -L "${d}${MV_REAL_SID}.jsonl" ] && { MV_REAL_TX="${d}${MV_REAL_SID}.jsonl"; break; }
  done
fi
# THE KEYS user_said READS, and only those (wave-28 T74; A-orch-221): a key the CLI drops or renames that the library
# never looks at must not redden the suite, and one it reads must. A typed prompt: type, origin.kind, message.content
# and isSidechain; a prompt typed while a turn ran: the attachment's type, origin.kind and prompt.
mv_keys() {  # <fixture file> <jq select of the real entries> <paths read, dotted, space-separated> [<transcript>] -> "n=<real entries> missing=<paths read that the fixture or every real entry lacks>"
  jq -nRr --slurpfile fx "$1" --arg paths "$3" '
    [inputs | fromjson? | objects | select('"$2"')] as $r
    | ($paths | split(" ") | map(split("."))) as $ps
    | "n=\($r | length) missing=\([$ps[] | select(. as $p | ($fx[0] | getpath($p)) == null or ([$r[] | getpath($p) | values] | length) == 0) | join(".")] | join(","))"' \
    "${4:-$MV_REAL_TX}" 2>/dev/null
}
MV_KEY_TYPED='.type == "user" and (.origin.kind? // "") == "human" and (.message.content | type) == "string"'
MV_READ_TYPED='type origin.kind message.content isSidechain'
MV_KEY_QUEUED='.type == "attachment" and .attachment.type? == "queued_command" and (.attachment.origin.kind? // "") == "human"'
MV_READ_QUEUED='type attachment.type attachment.origin.kind attachment.prompt'
MV_KEY_SLASH='.type == "user" and (.origin.kind? // "") == "human" and ((.message.content | type) == "string") and (.message.content | contains("<command-args>"))'
MV_READ_SLASH='type origin.kind message.content isSidechain'
MV_KEY_ROWS="typed@$MV_KEY_TYPED@$MV_READ_TYPED
queued@$MV_KEY_QUEUED@$MV_READ_QUEUED
slash-args@$MV_KEY_SLASH@$MV_READ_SLASH"
if [ -z "$MV_REAL_TX" ]; then
  ok "MOVE-keys §MOVE skipped: this session's own transcript is not readable here (no CLAUDE_CODE_SESSION_ID, or none under ${MV_REAL_CFG}/projects)"
else
  while IFS='@' read -r k sel rd; do
    MV_KR="$(mv_keys "$MV_FX/$k.jsonl" "$sel" "$rd")"
    case "$MV_KR" in
      n=0\ *) ok "MOVE-keys-$k skipped: this session's transcript holds no entry of that kind yet" ;;
      *) expect_regex "MOVE-keys-$k the keys user_said reads from a $k entry all appear in the fixture and in this session's own entries of that kind (a CLI rename turns this red)" \
           '^n=[1-9][0-9]* missing=$' "$MV_KR" ;;
    esac
  done <<EOF2
$MV_KEY_ROWS
EOF2
fi

POKE_BOUND="$MV_BOUND_WAS"
if [ "$MV_CCD_WAS" = "__unset__" ]; then unset CLAUDE_CONFIG_DIR; else export CLAUDE_CONFIG_DIR="$MV_CCD_WAS"; fi

# ============================================================
section "§REPORT-RTL §REPORT-KINDS §REPORT-PRINT: the run's numbers folded from the landing record and the gate's requests (wave-28 T14; REQ-4 AC-4.1, AC-4.4, AC-4.5; D18)"
# ============================================================
#
# `landing-report [--rows]` folds the bound plan's landing record (`line/v1` events) and the gate's
# request files into one line, and with `--rows` one line per landed row. Ready-to-landed is a
# subtraction of two event times, from a row's FIRST `ready` to its `published`; a hand or a git landing
# prints `-`. Median and p75 are linear interpolation over the sorted minutes (wave-27's baseline rule):
# an even set's median is the mean of its middle two, a set of one is that one value. Requests count
# when their `tree=` is the project or below it and they were asked at or after the record's first
# `line/v1` event. FIXTURE FIDELITY: §60's repository and bound plan (s60_world); the events and the
# requests are PLANTED in the Interfaces table's shapes, which lib/line.sh and lib/gate.sh write.
RP_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RP_E0=1791280800   # 2026-10-06T10:00:00Z
RP_C1="$(printf 'c%.0s' $(seq 40))"; RP_C2="$(printf 'd%.0s' $(seq 40))"
rp_ev() { printf 'line/v1|%s\n' "$1" >> "$S60_REC"; }   # <fields after line/v1|> -> one event
rp_ready() {  # <row> <name> <at hh:mm:ss> [<commit>, default RP_C1]
  rp_ev "ev=ready|row=$1|name=$2|commit=${4:-$RP_C1}|branch=wt/01-$1|tree=$RP_ROOT/.worktrees/01-$1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T$3Z"
}
rp_cand() { rp_ev "ev=candidate|row=$1|base=${3:-$RP_C1}|commit=${4:-$RP_C2}|tree=$RP_ROOT/.bionic/tmp/landing/1|at=2026-10-06T$2Z"; }   # <row> <at> [<base>, default RP_C1] [<candidate>, default RP_C2]
rp_verdict() { rp_ev "ev=verdict|row=$1|commit=${5:-$RP_C2}|suite=$2|result=$3|log=/rec/$1-$2.log|at=2026-10-06T$4Z"; }   # <row> <suite> <result> <at> [<commit>, default RP_C2]
rp_pub() { rp_ev "ev=published|row=$1|commit=$RP_C2|kind=$2|by=-|why=-|at=2026-10-06T$3Z"; }
rp_req() {  # <id> <who agent> <tree> <asked> <admitted|-> [<extra line>...] -> one request file
  local id="$1" who="$2" tree="$3" asked="$4" adm="$5"; shift 5
  {
    printf 'key=a.test.sh\nkind=landing\nwho=%s:%s\ntree=%s\nasked=%s\nholder=%s\n' "$SID" "$who" "$tree" "$asked" "$RP_DEAD:x"
    [ "$adm" = - ] || printf 'admitted=%s\npromise=5:0.1:30\n' "$adm"
    for _l in "$@"; do printf '%s\n' "$_l"; done
  } > "$RP_GATE/requests/$id"
}
rp_world() {  # <label> -> §60's world, an empty record, an empty gate store
  s60_world "$1" @A whole
  RP_ROOT="$(cd "$R59W" && pwd -P)"
  RP_GATE="$TMPROOT/rp-gate-$1"; rm -rf "$RP_GATE"; mkdir -p "$RP_GATE/requests" "$RP_GATE/cost"
  poke_bind "$R59W"
}
rp_report() { BIONIC_GATE_DIR="$RP_GATE" poke "$R59W" landing-report "$@"; }
rp_line() { printf '%s\n' "$OUT" | /usr/bin/grep '^landings: '; }
rp_rows() { printf '%s\n' "$OUT" | /usr/bin/grep -E '^T[0-9]+ (queue|hand|git) ' | tr '\n' '|' | sed 's/|$//'; }
( : ) & RP_DEAD=$!; wait "$RP_DEAD" 2>/dev/null
sleep 300 & RP_LIVE=$!
RP_LIVE_START="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$RP_LIVE" | awk '{ $1 = $1; print }')"

# ---------- §REPORT-RTL: ready-to-landed is a subtraction, from the FIRST ready ----------
rp_world rp-rtl
rp_ready T1 w-T1 10:00:00; rp_cand T1 10:01:00; rp_verdict T1 a.test.sh green 10:05:00
rp_ready T1 w-T1 10:20:00; rp_pub T1 queue 10:30:00
rp_ready T2 w-T2 11:00:00; rp_ready T3 w-T3 11:00:00; rp_pub T2 queue 11:15:00
rp_pub T3 queue 12:00:00
rp_ready T4 - 12:10:00; rp_cand T4 12:10:10; rp_pub T4 hand 12:10:30
rp_pub T5 git 12:20:00
rp_req 1 w-T1 "$RP_ROOT" $((RP_E0 + 120)) $((RP_E0 + 210)) "ended=$((RP_E0 + 300))" rc=0
rp_req 2 w-T1 "$RP_ROOT" $((RP_E0 - 3600)) $((RP_E0 - 3500)) "ended=$((RP_E0 - 3400))" rc=0
rp_req 3 w-T2 "$RP_ROOT/.worktrees/01-T2" $((RP_E0 + 3900)) $((RP_E0 + 3930)) "ended=$((RP_E0 + 3990))" rc=0
rp_req 4 main "$RP_ROOT" $((RP_E0 + 4000)) $((RP_E0 + 4000)) "ended=$((RP_E0 + 4060))" rc=0
rp_req 5 w-T3 /elsewhere/project $((RP_E0 + 4000)) $((RP_E0 + 4500)) "ended=$((RP_E0 + 4600))" rc=0
rp_req 6 w-T3 "$RP_ROOT" $((RP_E0 + 4100)) -
RP_RTL_LINE="landings: queue=3 hand=1 git=1 · ready-to-landed median=30.0m p75=45.0m max=60.0m · runs: green=1 red=0 none=0 discarded=0 red-then-green=0 · waited median=30s · killed=0"
rp_report
expect_eq "RTL1 landing-report exits 0 and prints the one line: the queue landings' minutes from first ready, waits over the project's requests" \
  "0|$RP_RTL_LINE" "$RC|$(rp_line)"
rp_report --rows
expect_eq "RTL2 --rows prints the same line first" "$RP_RTL_LINE" "$(printf '%s\n' "$OUT" | head -1)"
expect_eq "RTL3 …then a line per landed row in the record's order: T1's minutes run from its FIRST ready (30.0, not 10.0), a hand and a git landing print -" \
  "T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=1 waited=90s|T2 queue ready=2026-10-06T11:00:00Z landed=2026-10-06T11:15:00Z minutes=15.0 runs=0 waited=30s|T3 queue ready=2026-10-06T11:00:00Z landed=2026-10-06T12:00:00Z minutes=60.0 runs=0 waited=0s|T4 hand ready=- landed=2026-10-06T12:10:30Z minutes=- runs=0 waited=0s|T5 git ready=- landed=2026-10-06T12:20:00Z minutes=- runs=0 waited=0s" \
  "$(rp_rows)"
# A-orch-12: a request may carry `peak=` and a line no reader knows; the fold reads only its own keys.
printf 'peak=62\ncolour=blue\n' >> "$RP_GATE/requests/4"; printf 'peak=71\n' >> "$RP_GATE/requests/1"
rp_report --rows
expect_eq "RTL4 a request carrying peak= and an unknown line folds to the same report" \
  "$RP_RTL_LINE|T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=1 waited=90s" \
  "$(rp_line)|$(rp_rows | cut -d'|' -f1)"
# THE PLAN OPERAND (A-orch-145): a named plan first, else the session's bound run (RTL1 to RTL4 read the
# bound run), else the verb's no-run refusal. The named plan is read from another project, unbound.
RP_NORUN="$(make_repo rp-norun)"; ( cd "$RP_NORUN" && git commit -q --allow-empty -m init )
BIONIC_GATE_DIR="$RP_GATE" poke "$RP_NORUN" landing-report "$P59W" --rows
expect_eq "RTL10 a named plan, from an unbound session in another project: exit 0, that plan's line and rows, its waits scoped to its own project" \
  "0|$RP_RTL_LINE|T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=1 waited=90s" \
  "$RC|$(rp_line)|$(rp_rows | cut -d'|' -f1)"
BIONIC_GATE_DIR="$RP_GATE" poke "$RP_NORUN" landing-report
expect_eq "RTL11 no plan named and no run bound: the verb's no-run refusal (2), and no line" \
  "2|poker: REFUSED — this session has no run to report on; bind its plan first.|" \
  "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep 'no run to report on')|$(rp_line)"
poke "$RP_NORUN" landing-report "$RP_NORUN/no/such.plan.md"
expect_eq "RTL12 a named plan that is no file is refused (2), naming it" \
  "2|poker: REFUSED — no plan file at $RP_NORUN/no/such.plan.md; name the plan whose landings to report." \
  "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep 'no plan file at')"
# The even set and the set of one: the rule, pinned.
rp_world rp-even
rp_ready T1 w-T1 10:00:00; rp_ready T2 w-T2 10:00:00; rp_pub T1 queue 10:10:00; rp_pub T2 queue 10:20:00
rp_report
expect_eq "RTL5 two landings of 10 and 20 minutes: median 15.0 (the middle two's mean), p75 17.5 (interpolated), max 20.0" \
  "landings: queue=2 hand=0 git=0 · ready-to-landed median=15.0m p75=17.5m max=20.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0" \
  "$(rp_line)"
rp_world rp-one
rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:07:30
rp_report
expect_eq "RTL6 one landing of 7.5 minutes: its median, p75 and max are 7.5" \
  "landings: queue=1 hand=0 git=0 · ready-to-landed median=7.5m p75=7.5m max=7.5m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0" \
  "$(rp_line)"
# Empty and absent records: the line with zeros, exit 0.
rp_world rp-empty
rp_report
RP_ZERO="landings: queue=0 hand=0 git=0 · ready-to-landed median=0.0m p75=0.0m max=0.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0"
expect_eq "RTL7 an empty record prints the line with zeros and exits 0" "0|$RP_ZERO" "$RC|$(rp_line)"
rm -f "$S60_REC"
rp_report --rows
expect_eq "RTL8 an absent record prints the same, and --rows adds no row" "0|$RP_ZERO|" "$RC|$(rp_line)|$(rp_rows)"
rp_report --bogus
expect_eq "RTL9 an unknown flag is the usage error (2)" "2" "$RC"
# THE MUTATION ARM: the first ready replaced by the last turns RTL3 red (T1 reads 10.0).
RD_MUT="$(mktemp -d "${TMPDIR:-/tmp}/poker-rp-mut.XXXXXX")"
rd_mutant lastready 's/if (!(rk in rdy)) rdy\[rk\] = e$/rdy[rk] = e/'
expect_eq "RTL-mut0 the doctored poker differs from the real one in exactly one line (the doctor took)" "1" \
  "$(diff "$POKER" "$RD_MUT/lastready/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
rp_world rp-mut
rp_ready T1 w-T1 10:00:00; rp_ready T1 w-T1 10:20:00; rp_pub T1 queue 10:30:00
RP_REAL_POKER="$POKER"; POKER="$RD_MUT/lastready/hooks/session-poker.sh"
rp_report --rows
POKER="$RP_REAL_POKER"
expect_eq "RTL-mut1 the last-ready mutant still runs (exit 0) and reads T1's minutes from its LAST ready, 10.0, where RTL3 reads 30.0" \
  "0|T1 queue ready=2026-10-06T10:20:00Z landed=2026-10-06T10:30:00Z minutes=10.0 runs=0 waited=0s" "$RC|$(rp_rows)"
rp_report --rows
expect_eq "RTL-mut1b …control: the real poker over the same record reads 30.0" \
  "T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=0 waited=0s" "$(rp_rows)"
rm -rf "$RD_MUT"

# ---------- §REPORT-KINDS: landings by kind, runs by outcome, killed runs ----------
rp_world rp-kinds
rp_ready T1 w-T1 10:00:00; rp_cand T1 10:01:00; rp_verdict T1 a.test.sh green 10:05:00; rp_pub T1 queue 10:10:00
rp_ready T2 - 10:20:00; rp_cand T2 10:20:05; rp_pub T2 hand 10:20:30
rp_pub T3 git 10:30:00
# T4 is red then green on an unchanged tree: two verdicts for one row commit, red first, no ready between.
rp_ready T4 w-T4 10:40:00; rp_cand T4 10:41:00; rp_verdict T4 a.test.sh red 10:45:00; rp_verdict T4 a.test.sh green 10:50:00
# T5 is red, then said ready again (a changed tree), then green: not red-then-green.
rp_ready T5 w-T5 11:00:00; rp_verdict T5 a.test.sh red 11:05:00; rp_ready T5 w-T5 11:10:00; rp_verdict T5 a.test.sh green 11:15:00
rp_verdict T6 a.test.sh none 11:20:00; rp_verdict T6 a.test.sh discarded 11:21:00
printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=2026-10-06T10:10:00Z\nstamp/v1|head=%s|dirty=0|rc=0|at=2026-10-06T10:09:00Z|suites=a.test.sh\n' \
  "$RP_C1" "$RP_C2" "$RP_C1" >> "$S60_REC"
# Killed: admitted with a dead holder and no end; ended by a signal (rc over 128). Not killed: a clean
# end, and an admitted run whose holder lives.
rp_req 1 w-T4 "$RP_ROOT" $((RP_E0 + 2460)) $((RP_E0 + 2460))
rp_req 2 w-T4 "$RP_ROOT" $((RP_E0 + 2460)) $((RP_E0 + 2460)) "ended=$((RP_E0 + 2700))" rc=137
rp_req 3 w-T4 "$RP_ROOT" $((RP_E0 + 2460)) $((RP_E0 + 2460)) "ended=$((RP_E0 + 2700))" rc=0
rp_req 4 w-T4 "$RP_ROOT" $((RP_E0 + 2460)) $((RP_E0 + 2460))
sed "s/^holder=.*/holder=$RP_LIVE:$RP_LIVE_START/" "$RP_GATE/requests/4" > "$RP_GATE/requests/4.t" && mv "$RP_GATE/requests/4.t" "$RP_GATE/requests/4"
expect_contains "RK0 precondition: request 4's holder is the live sleeper, by pid and start" "holder=$RP_LIVE:" "$(cat "$RP_GATE/requests/4")"
rp_report --rows
expect_eq "RK1 a queue, a hand and a git landing each count under their own kind; green, red, none, discarded and red-then-green each as planted; two runs killed" \
  "landings: queue=1 hand=1 git=1 · ready-to-landed median=10.0m p75=10.0m max=10.0m · runs: green=3 red=2 none=1 discarded=1 red-then-green=1 · waited median=0s · killed=2" \
  "$(rp_line)"
expect_eq "RK2 …the hand landing is not a queue landing: its row reads hand, ready - and minutes -" \
  "T2 hand ready=- landed=2026-10-06T10:20:30Z minutes=- runs=0 waited=0s" "$(rp_rows | tr '|' '\n' | /usr/bin/grep '^T2 ')"
expect_eq "RK3 …the git landing likewise" "T3 git ready=- landed=2026-10-06T10:30:00Z minutes=- runs=0 waited=0s" \
  "$(rp_rows | tr '|' '\n' | /usr/bin/grep '^T3 ')"
expect_eq "RK4 …and rows that never landed print no row" "T1|T2|T3" "$(rp_rows | tr '|' '\n' | awk '{ print $1 }' | tr '\n' '|' | sed 's/|$//')"
# A malformed line is skipped and counted, never fatal.
rp_ev "ev=published|row=T9|commit=$RP_C2|kind=bogus|by=-|why=-|at=2026-10-06T12:00:00Z"
rp_ev "ev=verdict|row=T9|commit=$RP_C2|suite=a.test.sh|at=2026-10-06T12:00:00Z"
rp_ev "ev=ready|row=T9|at=not-a-time"
rp_report
expect_eq "RK5 three malformed line/v1 lines: exit 0, the same line, and one line on stderr counting them" \
  "0|landings: queue=1 hand=1 git=1 · ready-to-landed median=10.0m p75=10.0m max=10.0m · runs: green=3 red=2 none=1 discarded=1 red-then-green=1 · waited median=0s · killed=2|poker: landing-report — 3 malformed line/v1 line(s) skipped in $RP_ROOT/${S60_REC#"$R59W"/}" \
  "$RC|$(rp_line)|$(printf '%s\n' "$OUT" | /usr/bin/grep 'malformed')"

# ---------- §REPORT-PRINT: the tick and release-check print it; a row that never lands moves no figure ----------
rp_world rp-print
rp_ready T1 w-T1 10:00:00
rp_tick() { poke_pressure "$R59W" 8192 1.0 tick; }
rp_tl() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: landings: '; }
rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; rp_tick
expect_nonempty "RP0 precondition: the tick printed (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: ')"
expect_eq "RP1 a record with no published event: the tick prints no landings line" "" "$(rp_tl)"
rp_pub T1 queue 10:30:00
rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; rp_tick
expect_eq "RP2 a record with a published event: the tick prints the report's first line" \
  "poker: landings: queue=1 hand=0 git=0 · ready-to-landed median=30.0m p75=30.0m max=30.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0" "$(rp_tl)"
rp_tick
expect_contains "RP3 precondition: a second tick over the same facts says unchanged" "poker: unchanged since " "$OUT"
expect_eq "RP3b …and prints no landings line: an unchanged tick is the one line the Patrol ends on, \"printed only unchanged: end it\" (wave-28 T62; T68 folded RK-T3 into this row)" "" "$(rp_tl)"
rp_ready T2 w-T2 10:40:00; rp_pub T2 queue 10:50:00
rp_tick
expect_contains "RP4 a new landing moves no decision: the next tick still says unchanged (nothing reads the numbers to decide)" "poker: unchanged since " "$OUT"
expect_eq "RP4b …and that unchanged tick prints no landings line; the next tick that prints in full carries the new figure (RK-T6; T68 folded RK-T5 into this row)" "" "$(rp_tl)"
# AC-4.5 corrected: a review row and a dropped row added to the plan change no figure.
rp_report --rows; RP_BEFORE="$OUT"
awk '{ print } /^\| T8 \| 4 \| build/ {
  print "| T9 | 6 | review | a later review | critic | — | 30 | REQ-1 | r9.md | — | — | pending |  |"
  print "| T10 | 4 | build | a dropped build | implementor | — | 30 | REQ-1 | d.sh | — | — | dropped |  |" }' "$P59W" > "$P59W.tmp" && mv "$P59W.tmp" "$P59W"
expect_eq "RP5 precondition: the plan now holds the review row and the dropped row" "2" "$(/usr/bin/grep -cE '^\| T(9|10) \|' "$P59W")"
rp_report --rows
expect_eq "RP5b …and the report, line and rows, is byte for byte what it was" "$RP_BEFORE" "$OUT"
# release-check prints it with each row, after the deferrals (§RC-DEFER's world, its check declared again).
RP_SEV_REC="$RSEV/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
[ -f "$RP_SEV_REC" ] && cp "$RP_SEV_REC" "$TMPROOT/rp-sev-rec"
mkdir -p "${RP_SEV_REC%/*}"; S60_REC="$RP_SEV_REC"; : > "$S60_REC"; RP_ROOT="$(cd "$RSEV" && pwd -P)"
rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:30:00; rp_pub T2 git 10:40:00
printf 'release-check: bash %s\n' "$TMPROOT/rd-check.sh" >> "$RSEV/.bionic/config.yaml"
BIONIC_GATE_DIR="$RP_GATE" poke "$RSEV" release-check
expect_eq "RP6 release-check, its check passing, exits 0" "0" "$RC"
expect_eq "RP6b …and prints the report's line and each landed row, after its other lines" \
  "poker: release-check — landings: queue=1 hand=0 git=1 · ready-to-landed median=30.0m p75=30.0m max=30.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0|poker: release-check — T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=0 waited=0s|poker: release-check — T2 git ready=- landed=2026-10-06T10:40:00Z minutes=- runs=0 waited=0s" \
  "$(printf '%s\n' "$OUT" | tail -3 | tr '\n' '|' | sed 's/|$//')"
cp "$TMPROOT/rd-config" "$RSEV/.bionic/config.yaml"
if [ -f "$TMPROOT/rp-sev-rec" ]; then cp "$TMPROOT/rp-sev-rec" "$RP_SEV_REC"; else rm -f "$RP_SEV_REC"; fi
kill "$RP_LIVE" 2>/dev/null; wait "$RP_LIVE" 2>/dev/null
POKE_BOUND="$RP_BOUND_WAS"

# ============================================================
section "§REPORT-KEY: the report counts a row's runs by the row's commit, prints on a changed tick, and says unmeasured (wave-28 T62; REQ-4 AC-4.1, AC-4.4, AC-4.6; D18)"
# ============================================================
#
# Pass 37 found three faults in T14's report. (1) The fold keyed red-then-green on row, span and suite and
# read no `commit=`, so the accepted HEAD's run that `_line_red_owner` records under the row id (after the
# candidate's red) printed a real regression as a flake and inflated the row's runs. D18 says "two
# verdicts for one row commit, red first, no ready between": the pair is keyed on the commit as well, and
# a verdict at a commit that is none of the row's own (T68: inclusion, by the row's ready and candidate commits
# since its last landing) is the head's run, shown nowhere. (2) Every unchanged tick printed the landings line, against the Patrol's
# literal "printed only `unchanged` -> end it". (3) A record of `landed:` lines with no `line/v1` event
# (a run open across the upgrade) read as zeros. FIXTURE FIDELITY: the events are planted in the shape
# lib/line.sh writes them: `candidate` carries `base=<head>` and `commit=<candidate>`, the row's verdicts
# carry the candidate, and the head's run carries `commit=<head>` under the same row id.
RK_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RK_H="$(printf 'e%.0s' $(seq 40))"; RK_H2="$(printf 'f%.0s' $(seq 40))"; RK_C3="$(printf '3%.0s' $(seq 40))"; RK_C4="$(printf '4%.0s' $(seq 40))"
RK_RUNS_RE='runs: green=[0-9]* red=[0-9]* none=[0-9]* discarded=[0-9]* red-then-green=[0-9]*'
rk_runs() { printf '%s\n' "$OUT" | /usr/bin/grep '^landings: ' | grep -o "$RK_RUNS_RE"; }

# ---------- (1) the row's run is the row's commit: a regression the head's green run hides is not a flake ----------
rp_world rk-key1
rp_ready T1 w-T1 10:00:00; rp_cand T1 10:00:30 "$RK_H" "$RP_C2"
rp_verdict T1 a.test.sh red 10:05:00 "$RP_C2"; rp_verdict T1 a.test.sh green 10:09:00 "$RK_H"
rp_ev "ev=returned|row=T1|why=red|detail=/rec/T1.log|at=2026-10-06T10:09:01Z"
rp_report
expect_eq "RK-K1 a row's red, then the accepted head's green run under the row id, then returned: red=1 green=0 red-then-green=0 (the head's run is not the row's)" \
  "0|runs: green=0 red=1 none=0 discarded=0 red-then-green=0" "$RC|$(rk_runs)"
rp_ready T1 w-T1 11:00:00; rp_verdict T1 a.test.sh green 11:05:00 "$RP_C2"; rp_pub T1 queue 11:06:00
rp_report --rows
expect_eq "RK-K2 …fixed, re-readied, green, landed: the row's runs=2 (its red and its green, not the head's), and the line reads green=1 red=1 red-then-green=0" \
  "runs: green=1 red=1 none=0 discarded=0 red-then-green=0|T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T11:06:00Z minutes=66.0 runs=2 waited=0s" "$(rk_runs)|$(rp_rows)"
# a true flake: two verdicts for one commit, red first, no ready between; the head's run sits between them
rp_world rk-key2
rp_ready T2 w-T2 10:00:00; rp_cand T2 10:00:30 "$RK_H" "$RK_C3"
rp_verdict T2 a.test.sh red 10:05:00 "$RK_C3"; rp_verdict T2 a.test.sh green 10:08:00 "$RK_H"; rp_verdict T2 a.test.sh green 10:12:00 "$RK_C3"; rp_pub T2 queue 10:13:00
rp_report --rows
expect_eq "RK-K3 a flake (a PLANTED shape: lib/line.sh never writes it, A-T68.4): red, the head's run between, green at the same commit and no ready between: red-then-green=1, green=1 red=1, runs=2" \
  "runs: green=1 red=1 none=0 discarded=0 red-then-green=1|T2 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:13:00Z minutes=13.0 runs=2 waited=0s" "$(rk_runs)|$(rp_rows)"
# a red, then a green at ANOTHER candidate of the same ready (the head moved): two commits, so not a flake
rp_world rk-key3
rp_ready T3 w-T3 10:00:00; rp_cand T3 10:00:30 "$RK_H" "$RK_C3"; rp_verdict T3 a.test.sh red 10:05:00 "$RK_C3"
rp_cand T3 10:07:00 "$RK_H2" "$RK_C4"; rp_verdict T3 a.test.sh green 10:12:00 "$RK_C4"; rp_pub T3 queue 10:13:00
rp_report
expect_eq "RK-K4 a red at one candidate and a green at the next (no ready between): two row commits, red-then-green=0" \
  "runs: green=1 red=1 none=0 discarded=0 red-then-green=0" "$(rk_runs)"

# ---------- (2) the landings line prints on a tick that is not unchanged ----------
rp_world rk-tick
rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:30:00
RK_LINE="poker: landings: queue=1 hand=0 git=0 · ready-to-landed median=30.0m p75=30.0m max=30.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0"
rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; rp_tick
expect_eq "RK-T1 a tick that prints in full (no digest yet) carries the landings line" "$RK_LINE" "$(rp_tl)"
rp_ready T2 w-T2 10:40:00; rp_pub T2 queue 10:50:00
rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; rp_tick
expect_eq "RK-T6 the next tick that prints in full carries the line with the new landing's figures" \
  "poker: landings: queue=2 hand=0 git=0 · ready-to-landed median=20.0m p75=25.0m max=30.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0" "$(rp_tl)"

# ---------- (3) a record with no line/v1 event is unmeasured, never zeros ----------
RK_UNM="landings: unmeasured — the landing record holds no line/v1 events"
rp_world rk-unm
printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=2026-10-06T10:10:00Z\nstamp/v1|head=%s|dirty=0|rc=0|at=2026-10-06T10:09:00Z|suites=a.test.sh\n' \
  "$RP_C1" "$RP_C2" "$RP_C1" >> "$S60_REC"
printf 'landed: row=T2 branch=wt/01-T2 head=%s merge=%s at=2026-10-06T10:20:00Z\n' "$RP_C1" "$RP_C2" >> "$S60_REC"
rp_report --rows
expect_eq "RK-U1 a record of landed lines and no line/v1 event: landing-report --rows exits 0 and prints the one unmeasured line and no row, not zeros" \
  "0|$RK_UNM" "$RC|$OUT"
rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; rp_tick
expect_eq "RK-U2 the tick, printing in full, carries the unmeasured line (the record holds no published event)" "poker: $RK_UNM" "$(rp_tl)"
# release-check prints it, and no per-row line (RP6's world, its check declared again)
RK_SEV_REC="$RSEV/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
[ -f "$RK_SEV_REC" ] && cp "$RK_SEV_REC" "$TMPROOT/rk-sev-rec"
mkdir -p "${RK_SEV_REC%/*}"; S60_REC="$RK_SEV_REC"; : > "$S60_REC"; RP_ROOT="$(cd "$RSEV" && pwd -P)"
printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=2026-10-06T10:10:00Z\n' "$RP_C1" "$RP_C2" >> "$S60_REC"
printf 'release-check: bash %s\n' "$TMPROOT/rd-check.sh" >> "$RSEV/.bionic/config.yaml"
BIONIC_GATE_DIR="$RP_GATE" poke "$RSEV" release-check
expect_eq "RK-U3 release-check over such a record exits 0 and prints the unmeasured line, last, with no landed-row line" \
  "0|poker: release-check — $RK_UNM|0" \
  "$RC|$(printf '%s\n' "$OUT" | tail -1)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: release-check — T[0-9]* ')"
cp "$TMPROOT/rd-config" "$RSEV/.bionic/config.yaml"
if [ -f "$TMPROOT/rk-sev-rec" ]; then cp "$TMPROOT/rk-sev-rec" "$RK_SEV_REC"; else rm -f "$RK_SEV_REC"; fi
# the longest form the line prints in is under 100 columns (the em dash is three bytes, one column)
RK_LONG="poker: release-check — $RK_UNM"
expect_eq "RK-U4 the longest printed form of the unmeasured line is at most 100 columns" "yes" \
  "$([ $(( $(printf '%s' "$RK_LONG" | wc -c | tr -d ' ') - 4 )) -le 100 ] && echo yes || echo no)"

# ---------- the mutation arms: each item's fix undone turns its rows red ----------
RD_MUT="$(mktemp -d "${TMPDIR:-/tmp}/poker-rk-mut.XXXXXX")"
rd_mutant nohead 's/^      if ((g in hasc) && .*$/      # mutant: the head run is counted/'
rd_mutant nokey 's/^      vk = rk SUBSEP span\[rk\] SUBSEP kv\["commit"\] SUBSEP kv\["suite"\]$/      vk = rk SUBSEP span[rk] SUBSEP kv["suite"]/'
rd_mutant noguard 's/^        say "unchanged since .*$/&; [ -z "$TICK_LANDINGS" ] || say "$TICK_LANDINGS"/'
rd_mutant nounm 's/^  if landing_unmeasured "\$rec"; then .*$/  :/'
expect_eq "RK-mut0 each doctored poker differs from the real one in exactly one line (the four doctors took)" "1|1|1|1" \
  "$(for _m in nohead nokey noguard nounm; do diff "$POKER" "$RD_MUT/$_m/hooks/session-poker.sh" | /usr/bin/grep -c '^>'; done | tr '\n' '|' | sed 's/|$//')"
RK_REAL_POKER="$POKER"
# commit ignored (the head's run counted): the probe's shape reads green=1 where RK-K1 reads 0
rp_world rk-mut1
rp_ready T1 w-T1 10:00:00; rp_cand T1 10:00:30 "$RK_H" "$RP_C2"
rp_verdict T1 a.test.sh red 10:05:00 "$RP_C2"; rp_verdict T1 a.test.sh green 10:09:00 "$RK_H"
POKER="$RD_MUT/nohead/hooks/session-poker.sh"; rp_report
expect_eq "RK-mut1 the head-run mutant still runs (exit 0) and counts the head's green: green=1 red=1 where RK-K1 reads green=0 red=1" \
  "0|runs: green=1 red=1 none=0 discarded=0 red-then-green=0" "$RC|$(rk_runs)"
POKER="$RK_REAL_POKER"; rp_report
expect_eq "RK-mut1b …control: the real poker over the same record reads green=0 red=1" "runs: green=0 red=1 none=0 discarded=0 red-then-green=0" "$(rk_runs)"
# the pair's key without the commit: RK-K4's red and green at two candidates read as a flake
rp_world rk-mut2
rp_ready T3 w-T3 10:00:00; rp_cand T3 10:00:30 "$RK_H" "$RK_C3"; rp_verdict T3 a.test.sh red 10:05:00 "$RK_C3"
rp_cand T3 10:07:00 "$RK_H2" "$RK_C4"; rp_verdict T3 a.test.sh green 10:12:00 "$RK_C4"
POKER="$RD_MUT/nokey/hooks/session-poker.sh"; rp_report
expect_eq "RK-mut2 the commit-less key mutant still runs and reads red-then-green=1 where RK-K4 reads 0" \
  "0|runs: green=1 red=1 none=0 discarded=0 red-then-green=1" "$RC|$(rk_runs)"
POKER="$RK_REAL_POKER"; rp_report
expect_eq "RK-mut2b …control: the real poker reads red-then-green=0" "runs: green=1 red=1 none=0 discarded=0 red-then-green=0" "$(rk_runs)"
# the unchanged guard removed: an unchanged tick prints the line again
rp_world rk-mut3
rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:30:00
rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"; rp_tick; rp_tick
POKER="$RD_MUT/noguard/hooks/session-poker.sh"; rp_tick
expect_eq "RK-mut3 the no-guard mutant's unchanged tick still says unchanged and prints the landings line RK-T3 forbids" \
  "unchanged|$RK_LINE" "$(printf '%s\n' "$OUT" | /usr/bin/grep -q '^poker: unchanged since ' && echo unchanged)|$(rp_tl)"
POKER="$RK_REAL_POKER"
# the unmeasured arm removed: zeros again
rp_world rk-mut4
printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=2026-10-06T10:10:00Z\n' "$RP_C1" "$RP_C2" >> "$S60_REC"
POKER="$RD_MUT/nounm/hooks/session-poker.sh"; rp_report --rows
expect_eq "RK-mut4 the no-arm mutant still runs and prints the zeros RK-U1 forbids" "0|landings: queue=0 hand=0 git=0 · ready-to-landed median=0.0m p75=0.0m max=0.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 · waited median=0s · killed=0" \
  "$RC|$OUT"
POKER="$RK_REAL_POKER"
rm -rf "$RD_MUT"
POKE_BOUND="$RK_BOUND_WAS"

# ============================================================
section "§PASS-KEY: one record path is one pass — proof-add refuses a path whose earlier pass stands at another head or is settled (wave-28 T60; REQ-8 AC-8.6, AC-8.7; D33; A-orch-160)"
# ============================================================
#
# A `check:` or `deferred:` line is keyed `<record>#<n>`, so a record path registered for a second
# pass lets pass 2's finding #n inherit pass 1's settlement: a refuted #1 makes a new S1 fix read as
# dropped and the judge derives `pass` for a `fail` reading. The key stays unique by construction when
# `proof-add` registers a reading's path for ONE pass: a path whose `proved:` line names another head
# is refused, and so is a path of the same head that a `check:` or `deferred:` line already names; a
# relaunched reader's re-registration of an unsettled record (same head, no such line) stays admitted.
# FIXTURE FIDELITY: §SEV's repository, plan and roster, each reading registered by the real verb; the
# second pass is a real commit on the working branch, its record written over the first as a reader
# relaunched would.
PK_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
printf '%s|questions=adversarial|pushed=checks-adversarial,severity\n' \
  "$(roster_row_fixture session="$SID" name=pk-crit agent_id=a-pk-crit subagent_type=bionic:critic \
     files="$(sev_files "pk-a pk-b pk-c pk-d pk-e")")" >> "$SEV_RS"
sev_cur 4
pk_rec() {  # <file> <head> <result> [<line>...] -> an adversarial piece reading over base..<head>
  local f="$SEV_DIR/$1.md" h="$2" r="$3" l; shift 3
  { printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: %s\nscope: piece\n' "${SEV_B:0:10}" "$h" "$r"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\nwhat the reader found\n'; } > "$f"
}
pk_add() { poke "$RSEV" proof-add review "record/wave-01-fixture/$1.md" --question adversarial --reader pk-crit; }
pk_ref() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: REFUSED'; }  # the refusal line, of the last poke
pk_n() { /usr/bin/grep -c "^proved: .* evidence=record/wave-01-fixture/$1.md " "$PSEV"; }
pk_derived() {  # <lib> <file> <written result> -> the result the judge derives for the reading
  bash -c '. "$1"; _proof_reading_result "$2" "$3" "$4" "$5"' _ "$1" "$PSEV" "$RSEV/.bionic/docs" "record/wave-01-fixture/$2.md" "$3" 2>/dev/null
}
PK_H1="$(git -C "$SEV_WT" rev-parse HEAD)"

# ---------- the probe's shape: pass 1 settled, pass 2 on the same path at another head ----------
pk_rec pk-a "$PK_H1" fail "findings: 1" "finding: 1 S1 on x.sh:9 - data lost on a second run" "unsure: 1 needs a second machine"
pk_add pk-a
expect_eq "PASS-1 precondition: pass 1 registers on its path, one proof line and its open check: line (exit 0)" \
  "0|1|1" "$RC|$(pk_n pk-a)|$(/usr/bin/grep -c "^check: $(chk_id pk-a) " "$PSEV")"
poke "$RSEV" finding-check "$(chk_id pk-a)" refuted "$CHK_A"
expect_eq "PASS-1b precondition: pass 1's #1 is refuted by a third agent's record (exit 0)" "0|1" \
  "$RC|$(/usr/bin/grep -c "^check: $(chk_id pk-a) .* refuted by=" "$PSEV")"
PK_H2="$(s57_commit "$SEV_WT" lib/a.sh T60-C2)"
expect_ne "PASS-1c precondition: the working branch moved to a head pass 1 did not read" "$PK_H1" "$PK_H2"
pk_rec pk-a "$PK_H2" fail "findings: 1" "finding: 1 S1 on b.sh:3 - a second finding, a fix" "shown: 1 bash b.sh --twice"
s42_snap "$RSEV" "$PSEV"
pk_add pk-a
s42_unchanged "PASS-2 §PASS-KEY a second pass on a path whose proof line names another head" 1 "$PSEV"
expect_nonempty "PASS-2a the refusal line is there to read (the extractor returns real output)" "$(pk_ref)"
expect_contains "PASS-2b …naming the path" "record/wave-01-fixture/pk-a.md" "$(pk_ref)"
expect_contains "PASS-2c …and the head the earlier pass stands at" "${PK_H1:0:12}" "$(pk_ref)"
expect_contains "PASS-2d …and the head it was offered at" "${PK_H2:0:12}" "$(pk_ref)"
expect_contains "PASS-2e …and the fix" "write the pass to a new record path" "$(pk_ref)"
expect_eq "PASS-2f …in one line" "1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c .)"
expect_regex "PASS-2h …and its first line is one the verb's own shape (REFUSED — …, the plan unchanged)" \
  '^poker: REFUSED — .*The plan is unchanged\.$' "$(pk_ref)"
expect_eq "PASS-2g …and still one proof line for the path" "1" "$(pk_n pk-a)"
# the same pass-2 reading on a path of its own is admitted: the fix the refusal names
cp "$SEV_DIR/pk-a.md" "$SEV_DIR/pk-b.md"
pk_add pk-b
expect_eq "PASS-3 the pass written to a new record path registers (exit 0), its #1 an open fix, not a refuted one" \
  "0|fail" "$RC|$(pk_derived "$SEV_LIB" pk-b fail)"

# ---------- the relaunch: the same head and no check:/deferred: line is admitted as before ----------
pk_rec pk-c "$PK_H2" pass "findings: 0"
pk_add pk-c
expect_eq "PASS-4 precondition: a reading with no finding registers once (exit 0)" "0|1" "$RC|$(pk_n pk-c)"
pk_add pk-c
expect_eq "PASS-4b a relaunched reader registers the same record at the same head again (exit 0), as before" "0|2" "$RC|$(pk_n pk-c)"
expect_eq "PASS-4c …and the later proof line is the one the plan's reader takes: its head is the one read" "$PK_H2" \
  "$(s46_proved "$PSEV" | /usr/bin/grep -F "evidence=record/wave-01-fixture/pk-c.md " | tail -1 | sed -n 's/.* head=\([0-9a-f]*\) .*/\1/p')"

# ---------- the same head with a check: or a deferred: line is a settled pass, not re-registered ----------
pk_rec pk-d "$PK_H2" flag "findings: 1" "finding: 1 S3 off b.sh:3 - a call the reader could not trace" "unsure: 1 the caller is generated"
pk_add pk-d
expect_eq "PASS-5 precondition: an unsure finding registers with its check: line (exit 0)" "0|1|1" \
  "$RC|$(pk_n pk-d)|$(/usr/bin/grep -c "^check: $(chk_id pk-d) " "$PSEV")"
s42_snap "$RSEV" "$PSEV"
pk_add pk-d
s42_unchanged "PASS-5b §PASS-KEY the same record at the same head, a check: line already naming it" 1 "$PSEV"
expect_nonempty "PASS-5c the refusal line is there to read" "$(pk_ref)"
expect_contains "PASS-5d …naming the path" "record/wave-01-fixture/pk-d.md" "$(pk_ref)"
expect_contains "PASS-5e …the head" "${PK_H2:0:12}" "$(pk_ref)"
expect_contains "PASS-5e2 …and the fix" "write the pass to a new record path" "$(pk_ref)"
poke "$RSEV" finding-check "$(chk_id pk-d)" settled S2 off "$CHK_A"
expect_eq "PASS-5f precondition: the settlement writes the finding's deferred: line (exit 0)" "0|1" \
  "$RC|$(/usr/bin/grep -c "^deferred: $(chk_id pk-d) " "$PSEV")"
s42_snap "$RSEV" "$PSEV"
pk_add pk-d
s42_unchanged "PASS-5g …and still refused once the pass is settled, a deferred: line naming it too" 1 "$PSEV"
# a deferred: line alone (a finding the table defers writes it with no check: line)
pk_rec pk-e "$PK_H2" flag "findings: 1" "finding: 1 S2 off b.sh:3 - a side path still wrong"
pk_add pk-e
expect_eq "PASS-6 precondition: a deferred finding registers with its deferred: line and no check: line (exit 0)" "0|1|0" \
  "$RC|$(/usr/bin/grep -c "^deferred: $(chk_id pk-e) " "$PSEV")|$(/usr/bin/grep -c "^check: $(chk_id pk-e) " "$PSEV")"
s42_snap "$RSEV" "$PSEV"
pk_add pk-e
s42_unchanged "PASS-6b §PASS-KEY the same head, a deferred: line alone naming the record" 1 "$PSEV"

# ---------- the mutation arms: the guard removed, and the guard refusing every second registration ----------
PK_ANCHOR='PF_PASS="$(proof_pass_conflict "$PV_PLAN" "$PF_REL" "$PF_HEAD")"'
anchor "$POKER" "$PK_ANCHOR" 1
PK_MUT="$TMPROOT/poker-pass-mut"; mkdir -p "$PK_MUT/hooks" "$PK_MUT/scripts" "$PK_MUT/b/hooks" "$PK_MUT/b/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$PK_MUT/scripts/lib"
for _pk_f in "$(dirname "$POKER")"/*; do  # the verb's siblings (the dry commit's wall among them), by link
  [ "${_pk_f##*/}" = session-poker.sh ] || { ln -s "$_pk_f" "$PK_MUT/hooks/${_pk_f##*/}"; ln -s "$_pk_f" "$PK_MUT/b/hooks/${_pk_f##*/}" 2>/dev/null; }
done
PK_N="$PK_ANCHOR" PK_R='PF_PASS=""' awk 'BEGIN { n = ENVIRON["PK_N"]; r = ENVIRON["PK_R"] }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$POKER" > "$PK_MUT/hooks/session-poker.sh"
expect_eq "PASS-mut0 the guard-removed copy differs from the verb in one line" "1" \
  "$(diff "$POKER" "$PK_MUT/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$PK_MUT/b/scripts/lib"
PK_N="$PK_ANCHOR" PK_R='PF_PASS="head x y"' awk 'BEGIN { n = ENVIRON["PK_N"]; r = ENVIRON["PK_R"] }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$POKER" > "$PK_MUT/b/hooks/session-poker.sh"
expect_eq "PASS-mut0b the always-refusing copy differs from the verb in one line" "1" \
  "$(diff "$POKER" "$PK_MUT/b/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
PK_POKER="$POKER"
cp "$PSEV" "$TMPROOT/pk-plan-keep"
POKER="$PK_MUT/hooks/session-poker.sh"; pk_rec pk-a "$PK_H2" fail "findings: 1" "finding: 1 S1 on b.sh:3 - a second finding, a fix" "shown: 1 bash b.sh --twice"
pk_add pk-a
POKER="$PK_POKER"
expect_eq "PASS-mut1 the mutant runs: pass 2 registers on the path pass 1 settled (exit 0, two proof lines)" "0|2" "$RC|$(pk_n pk-a)"
expect_eq "PASS-mut2 …and the judge derives pass for the reading its proof line writes as fail: the hole PASS-2 closes" \
  "pass" "$(pk_derived "$SEV_LIB" pk-a fail)"
cp "$TMPROOT/pk-plan-keep" "$PSEV"
POKER="$PK_MUT/b/hooks/session-poker.sh"; pk_add pk-c
POKER="$PK_POKER"
expect_eq "PASS-mut3 the always-refusing copy runs, and refuses the relaunch PASS-4b admits (exit 1, so PASS-4b goes red)" "1|2" \
  "$RC|$(pk_n pk-c)"
cp "$TMPROOT/pk-plan-keep" "$PSEV"
POKE_BOUND="$PK_BOUND_WAS"

section "§UPGRADE: a run open at upgrade continues — a 1.12.0 plan's bytes outside the row's own lines are unchanged after ready, a tick and a hand landing (wave-28 T21; D26, REQ-2 AC-2.11, REQ-7 AC-7.2)"
#
# The fixture is a plan AS 1.12.0 WROTE IT (tests/fixtures/upgrade-1.12.0): canonical_sdlc_version 14, the
# `parallel-budget:` line the probe wrote (`source=probe`), rows with no `Lands-on:` label, roster launch rows with
# `suites_allowed=` and neither `row=` nor `lands_on=`, and in T1's tree a stamp (1.12.0's bare form) saying RED.
# The run continues: `ready` lands T1 on a run of its own, a tick passes, a person lands T2 by hand, and the plan
# differs from what 1.12.0 wrote in the three lines of each landed row and nowhere else. The tool never edits the
# line itself.
UP_ENV_WAS="$(export -p | /usr/bin/grep -E '^(declare -x|export) (BIONIC_PROBE_|BIONIC_NOW_FILE|CLAUDE_CONFIG_DIR|BIONIC_GATE_DIR|BIONIC_VERB_LOG|WORLD_)')"
. "$(dirname "$0")/lib/world.sh"
. "$(dirname "$0")/fixtures/upgrade-1.12.0/install.sh"
export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
world_machine 8 8192 40 0.5
world_clock 1000
world_cost a.test.sh 5 0.5 5
UP_SPAWN="${BIONIC_SCRIPTS_DIR}/payload/scripts/spawn-worktree.sh"
UP_BUDGET='parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe'
up_plan() { printf '%s/.bionic/docs/plans/epic-x/wave-x.plan.md' "$1"; }
up_world() {  # [<T1 suites_allowed>] -> a world root holding the 1.12.0 fixture
  local r
  r="$(world_repo)" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  up_install "$r" "$@" || return 1
  printf '%s' "$r"
}
up_rows_out() {  # <plan> <id>... -> the plan with each named row's own lines (tasks, step line, ledger) left out
  local p="$1"; shift
  awk -v ids="$*" 'BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) w[a[i]] = 1 }
    { if (match($0, /^\| T[0-9]+ \|/)) { id = substr($0, 3, RLENGTH - 4); if (id in w) next }
      if (match($0, /^- T[0-9]+:/)) { id = substr($0, 3, RLENGTH - 3); if (id in w) next }
      print }' "$p"
}
up_changed() {  # <before> <after> -> how many lines of <after> are not in <before>
  diff "$1" "$2" | /usr/bin/grep -c '^>'
}
up_same() {  # <before> <after> <id>... -> `same` when only the named rows' own lines differ
  local a="$1" b="$2"; shift 2
  [ "$(up_rows_out "$a" "$@" | cksum)" = "$(up_rows_out "$b" "$@" | cksum)" ] && printf same || printf differ
}
up_ready() {  # <tree> -> UP_OUT, UP_RC
  UP_OUT="$( cd "$1" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2 bash "$UP_SPAWN" ready 2>&1 )"; UP_RC=$?
}
UPG="$(up_world)"
expect_nonempty "(fixture) the 1.12.0 world was made" "$UPG"
UPG_P="$(up_plan "$UPG")"
UPG_BEFORE="$UPG_P.before"; cp "$UPG_P" "$UPG_BEFORE"
UPG_STAMPS="$(git -C "$UPG/.worktrees/T1" rev-parse --absolute-git-dir)/bionic-stamps"
expect_contains "(up-pre) the planted stamp says RED (rc=1) at T1's head, as 1.12.0's land would read it" \
  "|head=$(git -C "$UPG/.worktrees/T1" rev-parse HEAD)|dirty=0|rc=1|" "$(cat "$UPG_STAMPS")"
expect_contains "(up-pre) the fixture plan carries the probe's budget line, and the version 14" "$UP_BUDGET" "$(cat "$UPG_P")"
expect_contains "(up-pre) …version 14" "canonical_sdlc_version: 14" "$(cat "$UPG_P")"
expect_eq "(up-pre) …and its rows carry no Lands-on label" "0" "$(/usr/bin/grep -ci 'lands-on' "$UPG_P" | tr -d ' ')"

# ---------- ready ----------
up_ready "$UPG/.worktrees/T1"
expect_eq "(up-a1) ready lands the 1.12.0 row beside a stamp that says RED (exit 0)" "0" "$UP_RC"
expect_match "(up-a1) …printing LANDED, then the owed line" "LANDED T1 *
landed T1 * — owed: complete task T1, then stop wx-T1" "$UP_OUT"
cp "$UPG_P" "$UPG_P.after-ready"
expect_eq "(up-a2) the row's own three lines changed (its status, its step line, its ledger cell)" "3" "$(up_changed "$UPG_BEFORE" "$UPG_P")"
expect_eq "(up-a2) …and every other byte of the plan is the one 1.12.0 wrote" "same" "$(up_same "$UPG_BEFORE" "$UPG_P" T1)"
expect_contains "(up-a3) …the probe's budget line among them, as written" "$UP_BUDGET" "$(cat "$UPG_P")"
expect_contains "(up-a3) …and the version still 14" "canonical_sdlc_version: 14" "$(cat "$UPG_P")"

# ---------- a tick ----------
( cd "$UPG" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$POKER" arm ) >/dev/null 2>&1
UP_TICK="$( cd "$UPG" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$POKER" tick 2>&1 )"
expect_contains "(up-b1) a tick ran on the fixture's run (its decision line was printed)" "poker-tick/v1|" "$UP_TICK"
expect_eq "(up-b1) …and left the plan byte for byte as ready left it" "same" "$(cmp -s "$UPG_P.after-ready" "$UPG_P" && echo same || echo differ)"

# ---------- a hand landing ----------
UP_HAND="$( cd "$UPG" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$UP_SPAWN" land "$UPG/.worktrees/T2" --by-hand --reason "fixture" 2>&1 )"; UP_HAND_RC=$?
expect_eq "(up-c1) a hand landing of T2 lands it (exit 0)" "0" "$UP_HAND_RC"
expect_contains "(up-c1) …printing the owed line" "landed T2 " "$UP_HAND"
expect_eq "(up-c2) the hand landing changed the three lines of T2 and no others" "3" "$(up_changed "$UPG_P.after-ready" "$UPG_P")"
expect_eq "(up-c2) …and, whole, the plan differs from 1.12.0's in T1's and T2's own lines alone" "same" "$(up_same "$UPG_BEFORE" "$UPG_P" T1 T2)"
expect_contains "(up-c3) …the budget line is as the probe wrote it" "$UP_BUDGET" "$(cat "$UPG_P")"

# ---------- the mutation arm: a tool that edits the line ----------
# A copy of the hooks whose `row-landed` also changes one byte of the budget line; it is run in a world of its own
# from a directory outside every checkout, and the tracked file is not touched.
UPM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/up-mutant.XXXXXX")"
cp -R "${BIONIC_HOOKS_DIR}" "$UPM_DIR/hooks" && ln -s "${BIONIC_SCRIPTS_DIR}/payload" "$UPM_DIR/payload"
awk '/^    plan_verb_swap row-landed "\$PV_ID landed at/ && !d { print "    sed \"s/^\\(parallel-budget: .*\\)source=probe/\\1source=probes/\" \"$PV_NEW\" > \"$PV_NEW.m\" && mv -f \"$PV_NEW.m\" \"$PV_NEW\""; d = 1 }
  { print }' "${BIONIC_HOOKS_DIR}/session-poker.sh" > "$UPM_DIR/hooks/session-poker.sh"
expect_eq "(up-m0) the mutant differs from the hook by the one line that edits the budget" "1" \
  "$(diff "${BIONIC_HOOKS_DIR}/session-poker.sh" "$UPM_DIR/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
UPM="$(up_world)"
UPM_P="$(up_plan "$UPM")"; cp "$UPM_P" "$UPM_P.before"
UPM_OUT="$( cd "$UPM" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$UPM_DIR/hooks/session-poker.sh" row-landed T1 0123456789abcdef0123456789abcdef01234567 2026-10-07T03:30:00Z 2>&1 )"; UPM_RC=$?
expect_eq "(up-m1) the mutant's verb ran and wrote the row (exit 0)" "0" "$UPM_RC"
expect_eq "(up-m1) …its three lines changed, as the real verb's do" "3" "$(( $(up_changed "$UPM_P.before" "$UPM_P") - 1 ))"
expect_eq "(up-m2) …and the bytes row goes red: the plan differs outside T1's own lines" "differ" "$(up_same "$UPM_P.before" "$UPM_P" T1)"
expect_eq "(up-m2) …because the budget line is no longer the one the probe wrote (the real runs above hold it once)" "0 1" \
  "$(/usr/bin/grep -cFx -- "$UP_BUDGET" "$UPM_P" | tr -d ' ') $(/usr/bin/grep -cFx -- "$UP_BUDGET" "$UPG_P" | tr -d ' ')"
rm -rf "$UPM_DIR"
for UP_V in $(compgen -e | /usr/bin/grep -E '^(BIONIC_PROBE_|BIONIC_NOW_FILE$|CLAUDE_CONFIG_DIR$|BIONIC_GATE_DIR$|BIONIC_VERB_LOG$)'); do unset "$UP_V"; done
eval "$UP_ENV_WAS"

# ============================================================
section "§REPORT-INCL: the report counts a row's runs by INCLUSION, prints its line above the decision line, and the adopted row keeps its landing keys (wave-28 T68; REQ-7, REQ-10 AC-10.4; D5, D18; A-orch-198, A-orch-179, A-orch-216)"
# ============================================================
#
# Pass 43 found T62's exclusion wrong on the line's normal flow. A row proved BEHIND another (D5) has its
# candidate built on the row ahead's CANDIDATE, so the accepted head's run `_line_red_owner` writes under the row
# id at `line_head` (lib/line.sh) is the `base=` of none of its candidates, and counted as the row's own
# (green=3, runs=3 where 2 and 2 are true); a row landing twice counted its first candidate as its own, too. The
# rule is INCLUSION: a verdict is a row's run only at one of the row's OWN commits (a `ready`'s or a `candidate`'s
# `commit=`) since its last landing; a row with no candidate since its last landing has no commit to include by,
# so every verdict under its id counts (T14's count, which §REPORT-KINDS' sparse rows prove). FIXTURE FIDELITY:
# the events are planted in the shape lib/line.sh writes them, P1 to P3 being the reader's probes of pass 43.
RI_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RI_A1="$(printf '1%.0s' $(seq 40))"; RI_A2="$(printf '2%.0s' $(seq 40))"; RI_A3="$(printf '5%.0s' $(seq 40))"

# ---------- P1: a row proved behind another; the accepted head's run under its id is not its own ----------
ri_p1() {  # <label> -> the record of pass 43's probe P1
  rp_world "$1"
  rp_ready T1 w-T1 10:00:00 "$RI_A1"; rp_cand T1 10:00:10 "$RK_H" "$RK_C3"
  rp_ready T2 w-T2 10:01:00 "$RI_A2"; rp_cand T2 10:01:10 "$RK_C3" "$RP_C2"
  rp_verdict T1 a.test.sh green 10:04:00 "$RK_C3"
  rp_verdict T2 a.test.sh red 10:05:00 "$RP_C2"
  rp_verdict T2 a.test.sh green 10:08:00 "$RK_H"
  rp_ev "ev=returned|row=T2|why=red|detail=/rec/T2.log|at=2026-10-06T10:08:01Z"
  rp_pub T1 queue 10:09:00
  rp_ready T2 w-T2 10:20:00 "$RI_A3"; rp_cand T2 10:20:10 "$RK_C3" "$RK_C4"; rp_verdict T2 a.test.sh green 10:25:00 "$RK_C4"; rp_pub T2 queue 10:26:00
}
ri_p1 ri-p1
rp_report --rows
expect_nonempty "RI-P1 precondition: the extractor reads the report's runs figure" "$(rk_runs)"
expect_nonempty "RI-P1 precondition: …and the row extractor reads both rows" "$(rp_rows | tr '|' '\n' | /usr/bin/grep '^T2 ')"
expect_eq "RI-P1a T2 behind T1, red, the head's run under T2's id at H, fixed and landed: green=2 red=1 (T1's green, T2's red and T2's green; the head's run counted nowhere)" \
  "0|runs: green=2 red=1 none=0 discarded=0 red-then-green=0" "$RC|$(rk_runs)"
expect_eq "RI-P1b …T1 runs=1 and T2 runs=2" \
  "T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:09:00Z minutes=9.0 runs=1 waited=0s|T2 queue ready=2026-10-06T10:01:00Z landed=2026-10-06T10:26:00Z minutes=25.0 runs=2 waited=0s" "$(rp_rows)"

# ---------- P2 (the control): the head run after the row ahead landed is excluded by either rule ----------
rp_world ri-p2
rp_ready T1 w-T1 10:00:00 "$RI_A1"; rp_cand T1 10:00:10 "$RK_H" "$RK_C3"; rp_verdict T1 a.test.sh green 10:04:00 "$RK_C3"; rp_pub T1 queue 10:09:00
rp_ready T2 w-T2 10:01:00 "$RI_A2"; rp_cand T2 10:10:10 "$RK_C3" "$RP_C2"; rp_verdict T2 a.test.sh red 10:12:00 "$RP_C2"
rp_verdict T2 a.test.sh green 10:14:00 "$RK_C3"
rp_ev "ev=returned|row=T2|why=red|detail=/rec/T2.log|at=2026-10-06T10:14:01Z"
rp_report --rows
expect_eq "RI-P2 the writer's case: T2's red at its own candidate and the head's green at T1's landed commit: green=1 red=1, and T1's row runs=1" \
  "runs: green=1 red=1 none=0 discarded=0 red-then-green=0|T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:09:00Z minutes=9.0 runs=1 waited=0s" "$(rk_runs)|$(rp_rows)"

# ---------- P3: a row landing twice; its first candidate is not its second landing's own ----------
ri_p3() {  # <label> -> the record of pass 43's probe P3
  rp_world "$1"
  rp_ready T1 w-T1 10:00:00 "$RI_A1"; rp_cand T1 10:00:10 "$RK_H" "$RK_C3"; rp_verdict T1 a.test.sh green 10:04:00 "$RK_C3"; rp_pub T1 queue 10:05:00
  rp_ready T1 w-T1 10:10:00 "$RI_A2"; rp_cand T1 10:10:10 "$RK_C3" "$RP_C2"; rp_verdict T1 a.test.sh red 10:12:00 "$RP_C2"; rp_verdict T1 a.test.sh green 10:14:00 "$RK_C3"
  rp_ev "ev=returned|row=T1|why=red|detail=/rec/T1.log|at=2026-10-06T10:14:01Z"
  rp_ready T1 w-T1 10:20:00 "$RI_A3"; rp_cand T1 10:20:10 "$RK_C3" "$RK_C4"; rp_verdict T1 a.test.sh green 10:22:00 "$RK_C4"; rp_pub T1 queue 10:23:00
}
ri_p3 ri-p3
rp_report --rows
expect_eq "RI-P3a a row landing twice: the line reads green=2 red=1 (its two landings' own runs; the head's run at its first candidate is not counted)" \
  "0|runs: green=2 red=1 none=0 discarded=0 red-then-green=0" "$RC|$(rk_runs)"
expect_eq "RI-P3b …the first landing runs=1 and the second runs=2" \
  "T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:05:00Z minutes=5.0 runs=1 waited=0s|T1 queue ready=2026-10-06T10:10:00Z landed=2026-10-06T10:23:00Z minutes=13.0 runs=2 waited=0s" "$(rp_rows)"

# ---------- a row with no candidate since its last landing keeps T14's count: every verdict under its id ----------
rp_world ri-nocand
rp_ready T4 w-T4 10:00:00 "$RI_A1"; rp_verdict T4 a.test.sh red 10:05:00 "$RP_C2"; rp_verdict T4 a.test.sh green 10:06:00 "$RK_H"; rp_pub T4 queue 10:10:00
rp_report --rows
expect_eq "RI-N a row with a ready and verdicts but no candidate counts both its verdicts (there is no commit of its own to include by)" \
  "runs: green=1 red=1 none=0 discarded=0 red-then-green=0|T4 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:10:00Z minutes=10.0 runs=2 waited=0s" "$(rk_runs)|$(rp_rows)"

# ---------- ruling (3): killed is decided once, through the gate's rule, and an exit over 128 is a kill (D18) ----------
# (A-orch-233, T72: "137 only" of A-orch-179/198 is withdrawn; the spec's figure is "admitted, no end, holder gone,
# or an exit over 128", and the gate's own callers write 128+signal)
rp_world ri-kill
rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:10:00
rp_req 1 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=137
rp_req 2 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=143
rp_req 3 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=130
rp_req 4 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=128
rp_req 5 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=0
rp_report
expect_eq "RI-K five admitted requests ended with rc 137, 143, 130, 128 and 0: killed=3 (an exit over 128 is a kill, 128 itself is an ended run)" \
  "0|killed=3" "$RC|$(rp_line | grep -o 'killed=[0-9]*')"

# ---------- ruling (2): the landings line is above the decision line, which is the tick's last line ----------
ri_tick() {  # <label> -> a landing planted, then one tick that prints in full, stdout alone in S27_OUT
  rp_world "$1"
  rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:30:00
  rm -f "$R59W/.bionic/tmp/tick-digest-$SID.state"
  BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 poke_split "$R59W" tick
}
ri_pos() {  # -> "<above|not-above>|<first 14 bytes of the tick's last line>"
  local nl nd
  nl="$(printf '%s\n' "$S27_OUT" | /usr/bin/grep -n '^poker: landings: ' | head -1 | cut -d: -f1)"
  nd="$(printf '%s\n' "$S27_OUT" | /usr/bin/grep -n '^poker-tick/v1|' | tail -1 | cut -d: -f1)"
  printf '%s|%s' "$([ -n "$nl" ] && [ -n "$nd" ] && [ "$nl" -lt "$nd" ] && echo above || echo not-above)" "$(last_line "$S27_OUT" | cut -c1-14)"
}
ri_tick ri-pos
RI_NL="$(printf '%s\n' "$S27_OUT" | /usr/bin/grep -n '^poker: landings: ' | head -1 | cut -d: -f1)"
RI_ND="$(printf '%s\n' "$S27_OUT" | /usr/bin/grep -n '^poker-tick/v1|' | tail -1 | cut -d: -f1)"
expect_nonempty "RI-POS0 precondition: the tick printed a landings line (the extractor reads real output)" "$RI_NL"
expect_nonempty "RI-POS0 precondition: …and a decision line" "$RI_ND"
expect_eq "RI-POS1 the landings line sits above the decision line, and the decision line is the tick's LAST line (AC-10.4)" \
  "above|poker-tick/v1|" "$(ri_pos)"

# ---------- A-orch-216: an adopted row carries the landing keys its predecessor's row carried ----------
RIA="$(make_repo ri-adopt)"; new_roster "$RIA"
RIA_PRED="68686868-aaaa-4bbb-8ccc-000000000068"
add_row_to "$RIA" "$RIA_PRED" name=ri-debt status=identified agent_id=ari-debt-6800000000000001 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" deliverable="$RIA/.bionic/docs/record/ri-debt.md" \
  files=hooks/a.sh suites_allowed=a.test.sh suites_source=declared \
  row=T7 lands_on=a.test.sh "lands_red=a.test.sh until fixit-T7" red_evidence=.bionic/docs/record/w/T7-red.log
add_row_to "$RIA" "$RIA_PRED" name=ri-plain status=identified agent_id=ari-plain-680000000000002 subagent_type=bionic:implementor \
  duration="45 minutes" cadence="10 minutes" deliverable="$RIA/.bionic/docs/record/ri-plain.md" \
  files=hooks/a.sh suites_allowed=a.test.sh suites_source=declared
poke "$RIA" adopt
RIA_DEBT="$(/usr/bin/grep -F '|name=ri-debt|' "$(roster_of "$RIA")" | tail -1)"
RIA_PLAIN="$(/usr/bin/grep -F '|name=ri-plain|' "$(roster_of "$RIA")" | tail -1)"
expect_contains "RI-AD0 precondition: both rows are adopted (not vacuous)" "|adopted_from=$RIA_PRED|" "$RIA_DEBT$RIA_PLAIN"
expect_eq "RI-AD1 the adopted row carries the row, the lands-on, the declared debt and its evidence the predecessor's row carried" \
  "T7|a.test.sh|a.test.sh until fixit-T7|.bionic/docs/record/w/T7-red.log" \
  "$(s30_field "$RIA_DEBT" row)|$(s30_field "$RIA_DEBT" lands_on)|$(s30_field "$RIA_DEBT" lands_red)|$(s30_field "$RIA_DEBT" red_evidence)"
expect_eq "RI-AD2 …and a row that carried none carries none (an adopted row is not given a debt it never declared)" \
  "0" "$(printf '%s' "$RIA_PLAIN" | tr '|' '\n' | /usr/bin/grep -cE '^(row|lands_on|lands_red|red_evidence)=')"

# ---------- the mutation arms: each rule undone turns its row red ----------
RD_MUT="$(mktemp -d "${TMPDIR:-/tmp}/poker-ri-mut.XXXXXX")"
rd_mutant noclear 's/^      gen\[rk\]++$/      # mutant: the own set is never cleared/'
rd_mutant excl 's/^      if (ev == "candidate") hasc\[g\] = 1$/      if (ev == "candidate" \&\& kv["base"] != "") headc[rk SUBSEP kv["base"]] = 1/
s/^      if ((ev == "candidate" || ev == "ready") && kv\["commit"\] != "") ownc\[g SUBSEP kv\["commit"\]\] = 1$/      if ((ev == "candidate" || ev == "ready") \&\& kv["commit"] != "") ownc[rk SUBSEP kv["commit"]] = 1/
s/^      if ((g in hasc) && .*$/      if ((rk SUBSEP kv["commit"]) in headc \&\& !((rk SUBSEP kv["commit"]) in ownc)) next/'
rd_mutant kill137 's/^      ended) case .*$/      ended) ;;/'
rd_mutant late 's/^        \[ -z "\$TICK_LANDINGS" \] || say "\$TICK_LANDINGS"$/        :/
s/^        cat "\$TICK_BUF" 2>\/dev\/null$/        cat "$TICK_BUF" 2>\/dev\/null; [ -z "$TICK_LANDINGS" ] || say "$TICK_LANDINGS"/'
# THE 137-ONLY MUTANT DOCTORS TWO COPIES (wave-28 T8; A-orch-250): since T76 `gate.sh` `_gate_open` itself states `killed` for
# an ended request over 128, so the poker's own arm above is redundant and doctoring it alone changes nothing. The mutant's
# lib directory is therefore a COPY of the library whose `_gate_open` is back to 137-only, planted where the hook's
# BIONIC_LIB finds it, beside the poker doctored as before (without its arm, only the gate's state can say killed).
RI_LIB="$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)"
RI_GNEEDLE='if _gate_num "$_R_rc" && [ "$_G_NUM" -gt 128 ]; then _R_state=killed; fi'
anchor "$RI_LIB/gate.sh" "$RI_GNEEDLE" 1
rm -f "$RD_MUT/kill137/scripts/lib"; cp -R "$RI_LIB" "$RD_MUT/kill137/scripts/lib"
RI_N="$RI_GNEEDLE" RI_R='if [ "$_R_rc" = 137 ]; then _R_state=killed; fi' awk 'BEGIN { n = ENVIRON["RI_N"]; r = ENVIRON["RI_R"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' \
  "$RI_LIB/gate.sh" > "$RD_MUT/kill137/scripts/lib/gate.sh"
expect_eq "RI-mut0b the doctored gate.sh copy differs from the library in one line (the doctor took)" "1" \
  "$(diff "$RI_LIB/gate.sh" "$RD_MUT/kill137/scripts/lib/gate.sh" | /usr/bin/grep -c '^>')"
expect_eq "RI-mut0 each doctored poker differs from the real one in the lines its doctor names: 1, 3, 1 and 2 (the four doctors took)" "1|3|1|2" \
  "$(for _m in noclear excl kill137 late; do diff "$POKER" "$RD_MUT/$_m/hooks/session-poker.sh" | /usr/bin/grep -c '^>'; done | tr '\n' '|' | sed 's/|$//')"
RI_REAL_POKER="$POKER"
# the own set never cleared: P3's second landing counts its first candidate's head run again (RI-P3a reads green=2)
ri_p3 ri-mut-p3
POKER="$RD_MUT/noclear/hooks/session-poker.sh"; rp_report --rows
expect_eq "RI-mut1 the never-cleared mutant still runs (exit 0) and reads P3's second landing runs=3 and green=3 where RI-P3a and RI-P3b read 2 and 2" \
  "0|runs: green=3 red=1 none=0 discarded=0 red-then-green=0|runs=3" "$RC|$(rk_runs)|$(rp_rows | tr '|' '\n' | tail -1 | grep -o 'runs=[0-9]*')"
POKER="$RI_REAL_POKER"; rp_report --rows
expect_eq "RI-mut1b …control: the real poker over the same record reads green=2 and the second landing runs=2" \
  "runs: green=2 red=1 none=0 discarded=0 red-then-green=0|runs=2" "$(rk_runs)|$(rp_rows | tr '|' '\n' | tail -1 | grep -o 'runs=[0-9]*')"
# the rule back to exclusion by base=: P1's head run is the base of none of T2's candidates, so it counts again
ri_p1 ri-mut-p1
POKER="$RD_MUT/excl/hooks/session-poker.sh"; rp_report --rows
expect_eq "RI-mut2 the exclusion mutant still runs (exit 0) and reads P1's green=3 and T2 runs=3 where RI-P1a and RI-P1b read 2 and 2" \
  "0|runs: green=3 red=1 none=0 discarded=0 red-then-green=0|runs=3" "$RC|$(rk_runs)|$(rp_rows | tr '|' '\n' | /usr/bin/grep '^T2 ' | grep -o 'runs=[0-9]*')"
POKER="$RI_REAL_POKER"; rp_report --rows
expect_eq "RI-mut2b …control: the real poker over the same record reads green=2 and T2 runs=2" \
  "runs: green=2 red=1 none=0 discarded=0 red-then-green=0|runs=2" "$(rk_runs)|$(rp_rows | tr '|' '\n' | /usr/bin/grep '^T2 ' | grep -o 'runs=[0-9]*')"
# "137 only" again (the arm for an exit over 128 dropped): RI-K's 143 and 130 do not count
rp_world ri-mut-kill
rp_ready T1 w-T1 10:00:00; rp_pub T1 queue 10:10:00
rp_req 1 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=137
rp_req 2 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=143
rp_req 3 w-T1 "$RP_ROOT" $((RP_E0 + 60)) $((RP_E0 + 60)) "ended=$((RP_E0 + 300))" rc=130
POKER="$RD_MUT/kill137/hooks/session-poker.sh"; rp_report
expect_eq "RI-mut3 the 137-only mutant still runs and reads killed=1 where RI-K reads killed=3 for the same shape" "0|killed=1" "$RC|$(rp_line | grep -o 'killed=[0-9]*')"
POKER="$RI_REAL_POKER"; rp_report
expect_eq "RI-mut3b …control: the real poker reads killed=3 over the same requests (143 and 130 are kills)" "killed=3" "$(rp_line | grep -o 'killed=[0-9]*')"
# the landings line after the buffer again: the decision line is no longer last
POKER="$RD_MUT/late/hooks/session-poker.sh"; ri_tick ri-mut-pos
expect_eq "RI-mut4 the late mutant still prints both lines and puts the landings line after the decision line: not-above, the tick's last line the landings line" \
  "not-above|poker: landing" "$(ri_pos)"
POKER="$RI_REAL_POKER"; ri_tick ri-mut-pos2
expect_eq "RI-mut4b …control: the real poker over the same fixture reads above|poker-tick/v1|" "above|poker-tick/v1|" "$(ri_pos)"
POKER="$RI_REAL_POKER"
rm -rf "$RD_MUT"

POKE_BOUND="$RI_BOUND_WAS"

section "§PASS-MOVED: a moved: line binds a record's pass as a check: or deferred: line does — one predicate for the lines that bind it, so proof-add refuses a second registration over a move (wave-28 T72; REQ-8 AC-8.6, AC-8.9; D33, D34; A-T60.5, A-orch-213)"
# ============================================================
#
# `proof_pass_conflict` (the registering verb's guard) read `check:`/`deferred:` lines as the ones that bind
# a record's pass, and `_proof_reading_result` (the judge's re-derivation) read `check:`/`moved:`: a record
# path with only a `moved:` line was admitted for a second pass at the same head, and the new pass's
# finding #n inherited the move (A-T60.5; probed: an S4 typo read as fix). The two callers now ask ONE
# predicate (lib/proof.sh `proof_bind_awk`), which names all three. A move is the user's word about one
# finding of one pass, keyed `<record>#<n>` as a check is, and it changes the priority a later reader of
# that path judges (T42's seam), so it binds. FIXTURE FIDELITY: §PASS-KEY's repository, plan, roster and
# verb; the move is a line planted in the producing verb's shape (the transcript the verb itself needs is
# §MOVE's).
PM_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
printf '%s|questions=adversarial|pushed=checks-adversarial,severity\n' \
  "$(roster_row_fixture session="$SID" name=pm-crit agent_id=a-pm-crit subagent_type=bionic:critic \
     files="$(sev_files "pm-a pm-b")")" >> "$SEV_RS"
sev_cur 4
pm_add() { poke "$RSEV" proof-add review "record/wave-01-fixture/$1.md" --question adversarial --reader pm-crit; }
pm_n() { /usr/bin/grep -c "^proved: .* evidence=record/wave-01-fixture/$1.md " "$PSEV"; }
pm_line() {  # <line> -> the plan with the line placed where the verb places a finding's line
  bash -c '. "$1"; proof_add_line "$2" "$3"' _ "$SEV_LIB" "$PSEV" "$1" > "$PSEV.new" && mv "$PSEV.new" "$PSEV"
}
PM_H="$(git -C "$SEV_WT" rev-parse HEAD)"

# ---------- the probe: a moved: line alone, then the same record again at the same head ----------
pk_rec pm-a "$PM_H" flag "findings: 1" "finding: 1 S4 off b.sh:3 - a typo in a comment"
pm_add pm-a
expect_eq "PASSM-1 precondition: the note registers (exit 0, one proof line) and no check:, deferred: or moved: line names it" "0|1|0" \
  "$RC|$(pm_n pm-a)|$(/usr/bin/grep -c -E "^(check|deferred|moved): record/wave-01-fixture/pm-a.md#" "$PSEV")"
pm_line "moved: $(chk_id pm-a) to=fix by=Dana Fixture at=2026-10-07T12:00:00Z words=\"fix that one\" why=\"the user ruled it\""
expect_eq "PASSM-2 precondition: the plan holds the move and the judge derives fail for the reading its proof line writes as flag" "1|fail" \
  "$(/usr/bin/grep -c "^moved: $(chk_id pm-a) " "$PSEV")|$(pk_derived "$SEV_LIB" pm-a flag)"
s42_snap "$RSEV" "$PSEV"
pm_add pm-a
s42_unchanged "PASSM-3 §PASS-MOVED the same record at the same head, a moved: line alone already naming it" 1 "$PSEV"
expect_nonempty "PASSM-3a the refusal line is there to read (the extractor returns real output)" "$(pk_ref)"
expect_contains "PASSM-3b …naming the path" "record/wave-01-fixture/pm-a.md" "$(pk_ref)"
expect_contains "PASSM-3c …the head" "${PM_H:0:12}" "$(pk_ref)"
expect_contains "PASSM-3d …the lines that hold the pass, the move among them" "already has a check:, deferred: or moved: line" "$(pk_ref)"
expect_contains "PASSM-3e …and the fix" "write the pass to a new record path" "$(pk_ref)"
expect_eq "PASSM-3f …in one line" "1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c .)"
expect_eq "PASSM-3g …and still one proof line for the path" "1" "$(pm_n pm-a)"
# a move on another record's finding does not bind this path: its relaunch is admitted as before
pk_rec pm-b "$PM_H" pass "findings: 0"
pm_add pm-b
pm_add pm-b
expect_eq "PASSM-4 a moved: line naming pm-a does not bind pm-b: its relaunch registers again (exit 0, two proof lines)" "0|2" "$RC|$(pm_n pm-b)"

# ---------- one predicate: the guard and the judge's re-derivation agree on every kind of line ----------
PM_R=record/wave-01-fixture/pm-c.md
pk_rec pm-c "$PM_H" pass "findings: 1" "finding: 1 S1 on x.sh:9 - data lost on a second run" "shown: 1 bash x.sh"
pm_agree() {  # <plan line> -> `<what proof_pass_conflict says>|<the result _proof_reading_result derives for a reading written pass>`
  printf '## SDLC State\n\ncurrent: 4\nproved: kind=review head=%s at=2026-10-07T00:00:00Z evidence=%s question=adversarial reader=r result=pass scope=piece\n%s\n\n## Tasks\n' \
    "$PM_H" "$PM_R" "$1" > "$TMPROOT/pm-agree.md"
  bash -c '. "$1"; c="$(proof_pass_conflict "$2" "$3" "$4")"; printf "%s|%s" "${c%% *}" "$(_proof_reading_result "$2" "$5" "$3" pass)"' \
    _ "$SEV_LIB" "$TMPROOT/pm-agree.md" "$PM_R" "$PM_H" "$RSEV/.bionic/docs" 2>/dev/null
}
expect_eq "PASSM-5 no line binds the pass: no conflict, and the written result stands" "|pass" "$(pm_agree "")"
expect_eq "PASSM-5a a check: line binds it: a conflict, and the finding is read at its rating (S1 on fix: fail)" "settled|fail" \
  "$(pm_agree "check: $PM_R#1 S1 on \"data lost\"")"
expect_eq "PASSM-5b a deferred: line binds it for the judge as it does for the guard (T72: the judge read check:/moved: only)" "settled|fail" \
  "$(pm_agree "deferred: $PM_R#1 S1 on \"data lost\"")"
expect_eq "PASSM-5c a moved: line binds it for the guard as it does for the judge (T72: the guard read check:/deferred: only)" "settled|fail" \
  "$(pm_agree "moved: $PM_R#1 to=fix by=Dana Fixture at=2026-10-07T12:00:00Z words=\"fix it\" why=\"ruled\"")"
expect_eq "PASSM-5d a check: line of another record binds neither" "|pass" "$(pm_agree "check: record/wave-01-fixture/other.md#1 S1 on \"x\"")"
expect_eq "PASSM-5e a check: line inside a fence binds neither" "|pass" "$(pm_agree '```
check: '"$PM_R"'#1 S1 on "x"
```')"

# ---------- the mutation arm: moved: left out of the predicate ----------
PM_NEEDLE='/^(check|deferred|moved):[ \t]/'
anchor "$SEV_LIB" "$PM_NEEDLE" 1
PM_MUT="$TMPROOT/poker-moved-mut"; rm -rf "$PM_MUT"; mkdir -p "$PM_MUT/hooks"
cp -R "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$PM_MUT/scripts-lib" && mkdir -p "$PM_MUT/scripts" && mv "$PM_MUT/scripts-lib" "$PM_MUT/scripts/lib"
for _pm_f in "$(dirname "$POKER")"/*; do [ "${_pm_f##*/}" = session-poker.sh ] || ln -s "$_pm_f" "$PM_MUT/hooks/${_pm_f##*/}"; done
cp "$POKER" "$PM_MUT/hooks/session-poker.sh"
PM_N="$PM_NEEDLE" PM_R='/^(check|deferred):[ \t]/' awk 'BEGIN { n = ENVIRON["PM_N"]; r = ENVIRON["PM_R"] }
  { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$SEV_LIB" > "$PM_MUT/scripts/lib/proof.sh"
expect_eq "PASSM-mut0 the moved:-left-out copy of the library differs from it in one line" "1" \
  "$(diff "$SEV_LIB" "$PM_MUT/scripts/lib/proof.sh" | /usr/bin/grep -c '^>')"
PM_POKER="$POKER"; cp "$PSEV" "$TMPROOT/pm-plan-keep"
POKER="$PM_MUT/hooks/session-poker.sh"; pm_add pm-a
POKER="$PM_POKER"
expect_eq "PASSM-mut1 the mutant runs and registers the second pass over the move (exit 0, two proof lines): PASSM-3 goes red" "0|2" "$RC|$(pm_n pm-a)"
cp "$TMPROOT/pm-plan-keep" "$PSEV"
POKE_BOUND="$PM_BOUND_WAS"

section "§MOVE-PASTED §MOVE-WORD §MOVE-FOLD §MOVE-SLASH §MOVE-MIN §MOVE-KEYS §FILL-BEHIND: user_said cuts a pasted block as the CLI writes it, one word class, one fold, the arguments of a slash command, one constant; the tick names the rows behind the gap (wave-28 T74; REQ-8 AC-8.9; D34; A-orch-221, A-orch-226)"
# ============================================================
#
# Pass 49 found that lib/said.sh cut `<pasted_content …>…</pasted_content>` out of a typed prompt, while the CLI
# closes the block WITH the id (`</pasted_content id="…">`): the cut matched nothing and pasted words counted as
# typed in every pasted prompt this project has (T42's fixture invented the bare close, so no row could catch it).
# The fixture pasted.jsonl is now the CLI's shape (tests/fixtures/transcript-move/README.md names the provenance).
# Beside it, in passing: ONE word-character class (`'` and U+2019 both) for the boundary test and the word count,
# ONE fold (the poker's deferral_fold is lib/said.sh's said_fold), the whole-prompt rule of a slash command taken
# on its arguments, session.sh found beside the library at source time, "three" one constant, and the key-set
# rows narrowed to the keys user_said reads. The §MOVE helpers (mv_tx, mv_prompts, mv_said, mv_mutline) and its
# repository (RSEV, PSEV) are the ones the rows above use.
#
# §FILL-BEHIND (A-orch-226) is first and runs under the suite's own CLAUDE_CONFIG_DIR: the tick's FILL sentence
# names the READY rows it parked for width, so one decline of a FILL row answers the set the stop wall counts.
MP_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180

# ---------- §FILL-BEHIND: the sentence names the rows behind the gap; the FILL line's own ids do not move ----------
s74_plan() {  # <repo> <extra rows>... -> writers=1; a landed build, a doc writer, a review, then the extra rows
  local repo="$1"; shift
  s47_plan "$repo" 1 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T2 | 7 | doc | the release notes draft | implementor | — | 20 | REQ-x | .bionic/docs/record/notes.md | pending | approval:plan, head |" \
    "| T3 | 6 | review | the review | critic | — | 30 | REQ-x | .bionic/docs/record/review.md | pending | |" "$@" >/dev/null
}
s74_fill() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL — '; }
R74B="$(make_repo s74-behind)"; new_roster "$R74B"
s74_plan "$R74B" "| T4 | 7 | doc | more notes | implementor | — | 20 | REQ-x | .bionic/docs/record/notes2.md | pending | approval:plan, head |"
add_row "$R74B" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R74B" 8192 1.0 tick
expect_eq "MP-fill1 §FILL-BEHIND with the writer gap closed the review is the only FILL row: the line keeps its ids (exit 0)" \
  "0|poker: FILL T3" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -x 'poker: FILL T3')"
expect_eq "MP-fill2 …both doc writers are on WAIT lines, parked for width" \
  "poker: WAIT T2 — ready; no writer slot free (gap 0)|poker: WAIT T4 — ready; no writer slot free (gap 0)" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: WAIT T[24] ' | paste -sd'|' -)"
expect_eq "MP-fill3 …and the FILL sentence names them: one decline of T3 answers the set the stop wall counts" \
  "poker: FILL — T3 named for dispatch; the decision line carries them · behind the gap: T2 T4 — a decline of a FILL row frees their slot; dispatch or decline them in the same turn." \
  "$(s74_fill)"
R74C="$(make_repo s74-none)"; new_roster "$R74C"; s74_plan "$R74C"
poke_pressure "$R74C" 8192 1.0 tick
expect_eq "MP-fill4 positive, the same extractor: with nothing parked the sentence is what it was, and says nothing of a gap" \
  "poker: FILL — T2 T3 named for dispatch; the decision line carries them." "$(s74_fill)"
# THE MUTANT: the parked ids dropped from the sentence (a doctored copy of the hook, its siblings and library linked in).
MP_HROOT="$(mktemp -d "$TMPROOT/mp-hook.XXXXXX")"; mkdir -p "$MP_HROOT/hooks" "$MP_HROOT/scripts"
ln -s "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$MP_HROOT/scripts/lib"
for _sib in "$(dirname "$POKER")"/*; do _sibn="$(basename "$_sib")"; [ "$_sibn" = "session-poker.sh" ] || ln -s "$_sib" "$MP_HROOT/hooks/$_sibn"; done
MP_HOOK_NEEDLE='SCHED_BEHIND="${SCHED_BEHIND}${SCHED_BEHIND:+ }${base%% *}"'
anchor "$POKER" "$MP_HOOK_NEEDLE" 1
MP_N="$MP_HOOK_NEEDLE" awk 'BEGIN { n = ENVIRON["MP_N"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) ":" substr($0, i + length(n)); print }' \
  "$POKER" > "$MP_HROOT/hooks/session-poker.sh"
expect_eq "MP-fillmut0 the hook mutant differs from the hook in one line" "1" "$(diff "$POKER" "$MP_HROOT/hooks/session-poker.sh" | /usr/bin/grep -c '^>')"
MP_POKER_WAS="$POKER"; POKER="$MP_HROOT/hooks/session-poker.sh"
forget_digest "$R74B"
poke_pressure "$R74B" 8192 1.0 tick
POKER="$MP_POKER_WAS"
expect_eq "MP-fillmut1 the mutant still runs and still prints the FILL line (exit 0)" "0|poker: FILL T3" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -x 'poker: FILL T3')"
expect_eq "MP-fillmut2 …and its sentence has no gap clause, so MP-fill3 goes red under it" \
  "poker: FILL — T3 named for dispatch; the decision line carries them." "$(s74_fill)"
rm -rf "$MP_HROOT"

# ---------- from here the rows read §MOVE's transcript under its own CLAUDE_CONFIG_DIR ----------
MP_CCD_WAS="${CLAUDE_CONFIG_DIR-__unset__}"; export CLAUDE_CONFIG_DIR="$MV_CFG"
MP_MUT="$(mktemp -d "$TMPROOT/mp-mut.XXXXXX")"
mp_sub() {  # <needle> <replacement> <out> -> the library with the needle (a substring, once) replaced
  MP_N="$1" MP_R="$2" awk 'BEGIN { n = ENVIRON["MP_N"]; r = ENVIRON["MP_R"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$SAID_LIB" > "$3"
}

# ---------- §MOVE-PASTED (ruling 1): a pasted block, closed as the CLI closes it, is cut ----------
expect_regex "MP-p0 precondition: the fixture's block closes as the CLI closes it, with the id" \
  '^</pasted_content id="[0-9a-f-]{36}">$' "$(jq -r '.message.content' "$MV_FX/pasted.jsonl" | /usr/bin/grep -o '</pasted_content[^>]*>')"
mv_tx pasted
expect_eq "MP-p1 §MOVE-PASTED AC-8.9 the words pasted inside a typed prompt are not the user's: not found (rc 1)" "1" "$(mv_said "$MV_P")"
expect_eq "MP-p2 …the words typed before the block are found (rc 0)" "0" "$(mv_said 'what do you make of this?')"
expect_eq "MP-p3 …and the words typed after it are found (rc 0)" "0" "$(mv_said 'and then tell me which you would pick')"
MP_CUT='</pasted_content\\b[^>]*>'
anchor "$SAID_LIB" "$MP_CUT" 1
mp_sub "$MP_CUT" '</pasted_content>' "$MP_MUT/said-bare.sh"
expect_eq "MP-pmut0 the bare-close mutant differs from the library in one line" "1" "$(diff "$SAID_LIB" "$MP_MUT/said-bare.sh" | /usr/bin/grep -c '^>')"
expect_eq "MP-pmut1 the mutant runs: it finds the words typed before the block" "0" "$(mv_said 'what do you make of this?' "$MP_MUT/said-bare.sh")"
expect_eq "MP-pmut2 …and counts the pasted words (rc 0, not 1), so MP-p1 goes red under it" "0" "$(mv_said "$MV_P" "$MP_MUT/said-bare.sh")"

# ---------- §MOVE-WORD (ruling 2a): one word-character class for the boundary and the count ----------
mv_prompts 'defer it - now'
expect_eq "MP-w1 §MOVE-WORD a hyphen is a word character in the count as in the boundary: 'defer it -' is three words, found (rc 0)" "0" "$(mv_said 'defer it -')"
expect_eq "MP-w2 …positive beside it, the same transcript: 'defer it' is two words and a short quote (rc 3)" "3" "$(mv_said 'defer it')"
mv_prompts 'do not defer it now' 'he said defer it’s fine now'
expect_eq "MP-w3 positive: with the ASCII apostrophe, 'defer it now' is found as whole words (rc 0)" "0" "$(mv_said 'defer it now')"
mv_prompts 'don’t defer it now'
expect_eq "MP-w4 the typographic apostrophe joins what it touches: 't defer it now' out of 'don’t defer it now' is not found (rc 1)" "1" "$(mv_said 't defer it now')"
expect_eq "MP-w5 …positive beside it, the same transcript: 'defer it now' is found (rc 0)" "0" "$(mv_said 'defer it now')"
mv_prompts 'he said defer it’s fine now'
expect_eq "MP-w6 …and after the quote: 'said defer it' out of 'said defer it’s fine' is not found (rc 1)" "1" "$(mv_said 'said defer it')"
expect_eq "MP-w7 …positive: 'he said defer' is found (rc 0)" "0" "$(mv_said 'he said defer')"
expect_eq "MP-w8 the class is spelled once in the library (it carries one \\x27)" "1" \
  "$(/usr/bin/grep -c 'x27' "$SAID_LIB" | tr -d ' ')"
MP_WC='def wc:'
anchor "$SAID_LIB" "$MP_WC" 1
mv_mutline "$MP_WC" 'def wc: "[\\w\\x27-]";' "$MP_MUT/said-ascii.sh"
expect_eq "MP-wmut0 the ASCII-only mutant differs from the library in one line" "1" "$(diff "$SAID_LIB" "$MP_MUT/said-ascii.sh" | /usr/bin/grep -c '^>')"
mv_prompts 'don’t defer it now'
expect_eq "MP-wmut1 the mutant runs: it finds the whole prompt" "0" "$(mv_said 'don’t defer it now' "$MP_MUT/said-ascii.sh")"
expect_eq "MP-wmut2 …and finds 't defer it now' inside 'don’t' (rc 0, not 1), so MP-w4 goes red under it" "0" \
  "$(mv_said 't defer it now' "$MP_MUT/said-ascii.sh")"

# ---------- §MOVE-SLASH (ruling 2c): a command's whole-prompt rule is its arguments ----------
mv_slash() {  # <arguments> -> a transcript: the frame, then a slash command typed with these arguments
  cat "$MV_FX/frame.jsonl" > "$MV_TX"
  jq -c --arg a "$1" '.message.content = "<command-message>review</command-message>\n<command-name>/review</command-name>\n<command-args>" + $a + "</command-args>"' \
    "$MV_FX/slash-args.jsonl" >> "$MV_TX"
}
mv_slash 'defer it'
expect_eq "MP-s1 §MOVE-SLASH a two-word decision typed as a command's arguments is the user's whole prompt: found (rc 0)" "0" "$(mv_said 'defer it')"
mv_slash 'defer it now please'
expect_eq "MP-s2 …positive beside it, longer arguments: a three-word piece is found (rc 0)" "0" "$(mv_said 'defer it now')"
expect_eq "MP-s3 …and two of its words are short, as in any longer prompt (rc 3)" "3" "$(mv_said 'defer it')"
mv_tx typed

# ---------- §MOVE-FOLD (ruling 2b): the words, the why and the author fold by one rule ----------
MP_NBSP="$(printf '\302\240')"; MP_LS="$(printf '\342\200\250')"; MP_NEL="$(printf '\302\205')"
mv_tx typed; sev_cur 4
poke "$RSEV" finding-move "$(mv_id mv-fix)" fix "$(printf 'defer the flag wording\302\240until the next wave, it can wait')" "the${MP_NBSP}docs${MP_LS}pass${MP_NEL}here"
expect_regex "MP-f1 §MOVE-FOLD a no-break space, a line separator and a next-line in the why fold as white space, as in the words (exit 0)" \
  "^0\|moved: .* words=\"$MV_P\" why=\"the docs pass here\"\$" "$RC|$(mv_moved mv-fix | tail -1)"

# ---------- §MOVE-SELF (ruling 2d): session.sh is found beside the library at source time ----------
MP_LIBDIR="${SAID_LIB%/*}"
expect_eq "MP-d1 §MOVE-SELF the library sourced by a relative path, the working directory then moved: found (rc 0)" "0" \
  "$(cd "$MP_LIBDIR" && env CLAUDE_CODE_SESSION_ID="$SID" bash -c '. ./said.sh; cd /; user_said "$1"; echo "$?"' _ "$MV_P" 2>/dev/null)"
expect_eq "MP-d2 …sourced by a bare name, the working directory then moved: found (rc 0)" "0" \
  "$(cd "$MP_LIBDIR" && env CLAUDE_CODE_SESSION_ID="$SID" bash -c '. said.sh; cd /; user_said "$1"; echo "$?"' _ "$MV_P" 2>/dev/null)"
expect_eq "MP-d3 …positive, the working directory kept: found (rc 0)" "0" \
  "$(cd "$MP_LIBDIR" && env CLAUDE_CODE_SESSION_ID="$SID" bash -c '. ./said.sh; user_said "$1"; echo "$?"' _ "$MV_P" 2>/dev/null)"

# ---------- §MOVE-MIN (ruling 2e): "three" is one constant ----------
MP_MIN="$(bash -c '. "$1" 2>/dev/null; printf "%s" "$SAID_MIN_WORDS"' _ "$SAID_LIB")"
expect_regex "MP-m1 §MOVE-MIN the library names its minimum once, as a number" '^[1-9][0-9]*$' "$MP_MIN"
expect_eq "MP-m2 …the verb's refusal text is made from that constant and spells no number of its own" "0|1" \
  "$(/usr/bin/grep -c 'at least three' "$POKER" | tr -d ' ')|$(/usr/bin/grep -c 'at least \$SAID_MIN_WORDS' "$POKER" | tr -d ' ')"
SAID_MIN_NEEDLE='SAID_MIN_WORDS='
anchor "$SAID_LIB" "$SAID_MIN_NEEDLE" 1
mv_mutline "$SAID_MIN_NEEDLE" 'SAID_MIN_WORDS=4' "$MP_MUT/said-four.sh"
mv_prompts 'please defer it now ok'
expect_eq "MP-m3 the library's rule is the constant: three words are enough at 3 (rc 0)" "0" "$(mv_said 'defer it now')"
expect_eq "MP-m4 …and at 4 the same three words are short (rc 3) while four are enough (rc 0)" "3|0" \
  "$(mv_said 'defer it now' "$MP_MUT/said-four.sh")|$(mv_said 'defer it now ok' "$MP_MUT/said-four.sh")"
mv_tx typed
rm -rf "$MP_MUT"

# ---------- §MOVE-KEYS (ruling 2f): the key-set rows read only the keys user_said reads ----------
# A planted transcript stands for the real one: the typed fixture's entries, then with an UNREAD key dropped
# (slug is not read) and with a READ key dropped (isSidechain is read).
MP_KTX="$TMPROOT/mp-keys.jsonl"
jq -c 'del(.turnPosition)' "$MV_FX/typed.jsonl" > "$MP_KTX"
expect_eq "MP-k1 §MOVE-KEYS a CLI that dropped a key user_said does not read (turnPosition) leaves the typed row green" \
  "n=1 missing=" "$(mv_keys "$MV_FX/typed.jsonl" "$MV_KEY_TYPED" "$MV_READ_TYPED" "$MP_KTX")"
jq -c 'del(.isSidechain)' "$MV_FX/typed.jsonl" > "$MP_KTX"
expect_eq "MP-k2 …and one that dropped a key it reads (isSidechain) turns it red, naming the key" \
  "n=1 missing=isSidechain" "$(mv_keys "$MV_FX/typed.jsonl" "$MV_KEY_TYPED" "$MV_READ_TYPED" "$MP_KTX")"
cp "$MV_FX/typed.jsonl" "$MP_KTX"
expect_eq "MP-k3 …positive, the entries as the fixture has them: nothing missing" \
  "n=1 missing=" "$(mv_keys "$MV_FX/typed.jsonl" "$MV_KEY_TYPED" "$MV_READ_TYPED" "$MP_KTX")"

if [ "$MP_CCD_WAS" = "__unset__" ]; then unset CLAUDE_CONFIG_DIR; else export CLAUDE_CONFIG_DIR="$MP_CCD_WAS"; fi
POKE_BOUND="$MP_BOUND_WAS"

# ============================================================
section "§STEP-FIELD: a verb writes or replaces one field of a step's block, in the grammar the gate reads (wave-28 T8; REQ-3 AC-3.5; D17)"
# ============================================================
#
#   step-field <N> <key>=<value>     N a step (0-9 and 4a-style), key one of head cmd pass total output merge
#                                    worktree-removed adr share; the two-space-indented `<key>: <value>` line
#                                    under `- Step N:` is written after the block's last line, or replaced
#                                    where it stands (lib/units.sh `units_step_fields --replace`)
#
# It takes the plan transaction every row verb takes (copy, dry commit through the real gate, checksum, swap).
# REFUSED, plan byte-identical: a value with a line break, a key outside the nine, a step with no line, a key
# the step line itself carries, and Step 9 (close-out's); a usage error (exit 2): not exactly `<N> <key>=<value>`,
# a step that is not N, an empty value. The verb's refusals are the verb family's (`die`), not refuse.sh's.
# FIXTURE FIDELITY: §42's repository and plan writer (a plan the real gate admits), the real verb; every row's
# evidence is the plan's own bytes (git diff --numstat, the line's place) and the gate's next verdict.
SF_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RSF="$(make_repo sf-field)"; ( cd "$RSF" && git commit -q --allow-empty -m init )
PSF="$(s42_plan "$RSF" 4)"
poke "$RSF" step-line 5 'floor run'
poke "$RSF" step-line 7 documenting
poke "$RSF" step-line 8 integrating
s42_snap "$RSF" "$PSF"
s34_gate "$RSF"
expect_eq "SF-0 precondition: the fixture plan at current: 4, Steps 5, 7 and 8 written, is admitted by the real gate" "0" "$GATE_RC"
sf_block() {  # <plan> <N> -> the step's own lines: the step line and the indented lines under it
  awk -v n="$2" '$0 ~ ("^- Step " n ":") { f = 1; print; next } f && /^  / { print; next } f { exit }' "$1"
}
sf_lineno() { awk -v k="$2" 'index($0, "  " k ": ") == 1 { print NR; exit }' "$1"; }
sf_first() { printf '%s\n' "$OUT" | sed -n 1p; }
SF_ROWS="4|share|55|60
5|cmd|bash tests/run.sh|bash tests/x.test.sh
5|pass|3|4
5|total|3|4
5|output|record/floor.log|record/floor-2.log
5|head|0123abc|4567def
7|adr|docs/adr-0001.md|docs/adr-0002.md
8|merge|0123456789abcdef0123456789abcdef01234567|89abcdef0123456789abcdef0123456789abcdef
8|worktree-removed|yes|done .worktrees/x"
while IFS='|' read -r sfn sfk sfv1 sfv2 <&3; do
  s42_snap "$RSF" "$PSF"
  poke "$RSF" step-field "$sfn" "$sfk=$sfv1"
  expect_eq "SF-1-$sfk step-field $sfn $sfk= of a key the block lacks exits 0" "0" "$RC"
  expect_eq "SF-1-$sfk …one line added, none removed (git diff --numstat)" "1 0;" "$(s42_numstat "$RSF")"
  expect_eq "SF-1-$sfk …it is the indented line under - Step $sfn:" "1" "$(sf_block "$PSF" "$sfn" | /usr/bin/grep -cxF -- "  $sfk: $sfv1")"
  expect_contains "SF-1-$sfk …and says what it did" "step-field — Step $sfn $sfk" "$OUT"
  SF_AT="$(sf_lineno "$PSF" "$sfk")"
  s42_snap "$RSF" "$PSF"
  poke "$RSF" step-field "$sfn" "$sfk=$sfv2"
  expect_eq "SF-2-$sfk the same key again exits 0" "0" "$RC"
  expect_eq "SF-2-$sfk …one line replaced, none added" "1 1;" "$(s42_numstat "$RSF")"
  expect_eq "SF-2-$sfk …the block holds one line of the key, the new value" "1" "$(sf_block "$PSF" "$sfn" | /usr/bin/grep -cxF -- "  $sfk: $sfv2")"
  expect_eq "SF-2-$sfk …and no other line of it, under any step" "1" "$(/usr/bin/grep -c "^  $sfk: " "$PSF")"
  expect_eq "SF-2-$sfk …on the line where it stood" "$SF_AT" "$(sf_lineno "$PSF" "$sfk")"
done 3<<< "$SF_ROWS"
s42_snap "$RSF" "$PSF"
s34_gate "$RSF"
expect_eq "SF-3 the plan with all nine fields written and replaced is admitted by the real gate" "0" "$GATE_RC"
expect_eq "SF-3b …and the Step-4 block still opens with its own three fields (the verb wrote after them)" "worktree|base-sha|branch|share" \
  "$(sf_block "$PSF" 4 | sed -n '2,$p' | sed 's/^  \([a-z-]*\):.*/\1/' | paste -sd'|' -)"

# ---------- the refusals: plan byte-identical, one first line each, at most 100 columns ----------
sf_refused() {  # <label> <want rc> <want first-line text> <args…>
  local label="$1" rc="$2" want="$3"; shift 3
  s42_snap "$RSF" "$PSF"; poke "$RSF" step-field "$@"
  s42_unchanged "$label" "$rc" "$PSF"
  expect_contains "$label …saying why" "$want" "$(sf_first)"
  SF_W="$(sf_first | wc -m | tr -d ' ')"
  expect_true "$label …in a first line of at most 100 columns (measured $SF_W)" test "$SF_W" -gt 1 -a "$SF_W" -le 101
}
sf_refused "SF-4 a value with a line break (§STEP-FIELD refusal 1)" 1 "has a line break" 5 $'cmd=bash a\nb'
sf_refused "SF-4b …a carriage return the same" 1 "has a line break" 5 $'cmd=bash a\rb'
sf_refused "SF-5 a key outside the nine (refusal 2)" 1 "is not a step field" 5 colour=red
sf_refused "SF-5b …a key near one (Pass)" 1 "is not a step field" 5 Pass=3
sf_refused "SF-5c …the longest key a person types, 80 characters" 1 "is not a step field" 5 "$(printf 'k%.0s' $(seq 1 80))=1"
expect_contains "SF-5d …the second line names the nine" "head, cmd, pass, total, output, merge, worktree-removed, adr, share" "$OUT"
sf_refused "SF-6 a step with no line (refusal 3)" 1 "no Step 6 line" 6 head=0123abc
sf_refused "SF-7 Step 9, close-out's" 1 "close-out's" 9 head=0123abc
poke "$RSF" step-line 6 'pass: 9'
s42_snap "$RSF" "$PSF"
sf_refused "SF-8 a key the step line itself carries" 1 "carries 'pass:'" 6 pass=4
sf_usage() {  # <label> <args…> -> exit 2, plan unchanged
  s42_snap "$RSF" "$PSF"; poke "$RSF" step-field "$@"
  s42_unchanged "$1" 2 "$PSF"
}
sf_usage "SF-9 usage: no operand" 
sf_usage "SF-9b usage: a step and no field" 5
sf_usage "SF-9c usage: an operand with no =" 5 head
sf_usage "SF-9d usage: an empty value" 5 head=
sf_usage "SF-9e usage: a task id, which has a line and no block" T2 head=0123abc
sf_usage "SF-9f usage: three operands" 5 head=0123abc pass=3
sf_usage "SF-9g usage: a step that is not one" 12 head=0123abc

# ---------- the mutation arm: replace mode appending a second line ----------
# A copy of the library whose --replace writes the new line after the old one, behind a copy of the hook that
# reads it: the same `step-field 5 pass=` writes a block with two pass: lines, so SF-2's one line goes red.
SFM_NEEDLE='if (replace && (i in at_line)) print "  " key[at_line[i]] ": " val[at_line[i]]'
SFM_UNITS="$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)/units.sh"
anchor "$SFM_UNITS" "$SFM_NEEDLE" 1
SFM_DIR="$TMPROOT/poker-sf-mut"; rm -rf "$SFM_DIR"; mkdir -p "$SFM_DIR/hooks" "$SFM_DIR/scripts"
cp -R "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$SFM_DIR/scripts/lib"
for _sf_f in "$(dirname "$POKER")"/*; do [ "${_sf_f##*/}" = session-poker.sh ] || ln -s "$_sf_f" "$SFM_DIR/hooks/${_sf_f##*/}"; done
cp "$POKER" "$SFM_DIR/hooks/session-poker.sh"
SFM_R='if (replace && (i in at_line)) { print L[i]; print "  " key[at_line[i]] ": " val[at_line[i]] }'
SF_N="$SFM_NEEDLE" SF_R="$SFM_R" awk 'BEGIN { n = ENVIRON["SF_N"]; r = ENVIRON["SF_R"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' \
  "$SFM_UNITS" > "$SFM_DIR/scripts/lib/units.sh"
expect_eq "SF-mut0 the append copy of the library differs from it in one line" "1" "$(diff "$SFM_UNITS" "$SFM_DIR/scripts/lib/units.sh" | /usr/bin/grep -c '^>')"
cp "$PSF" "$TMPROOT/sf-plan-keep"
SFM_POKER="$POKER"; POKER="$SFM_DIR/hooks/session-poker.sh"
poke "$RSF" step-field 5 pass=9
POKER="$SFM_POKER"
expect_eq "SF-mut1 the mutant runs and writes the plan (exit 0, the new value is there)" "0|1" "$RC|$(sf_block "$PSF" 5 | /usr/bin/grep -cxF -- '  pass: 9')"
expect_eq "SF-mut2 …but the block holds two pass: lines, where SF-2 found one" "2" "$(sf_block "$PSF" 5 | /usr/bin/grep -c '^  pass: ')"
cp "$TMPROOT/sf-plan-keep" "$PSF"
poke "$RSF" step-field 5 pass=9
expect_eq "SF-mut3 the verb itself, on the same plan: one pass: line" "0|1" "$RC|$(sf_block "$PSF" 5 | /usr/bin/grep -c '^  pass: ')"
cp "$TMPROOT/sf-plan-keep" "$PSF"

# ============================================================
section "§STEP-FIELD (share): current 4 at wave scale also writes the Step-4 plan fact share: <n> (wave-28 T8; A-orch-140; D16; AC-2.11)"
# ============================================================
#
# `current 4` fills the Step-4 block (worktree, base-sha, branch) from the plan's working-branch. At wave scale it
# also writes `share: <n>`, the value lib/gate.sh `gate_share` prints, through the same writer, so the gate reads it
# as a field; a block that already carries the line is not rewritten, and a task-scale plan gets none.
SH_CCD_WAS="${CLAUDE_CONFIG_DIR-__unset__}"
SH_CFG="$TMPROOT/sf-share-cfg"; mkdir -p "$SH_CFG/bionic"; export CLAUDE_CONFIG_DIR="$SH_CFG"
printf '55\n' > "$SH_CFG/bionic/share"
sf_wave() {  # <label> <block body> [<scale>] -> a repo and plan at current: 3 with working-branch, snapped
  local r p
  r="$(make_repo "$1")"
  ( cd "$r" && git commit -q --allow-empty -m init && git checkout -q -b wave/01-fixture )
  p="$(s42_plan "$r" 3 "$2")"
  awk '{ print } /^current: 3$/ { print "working-branch: wave/01-fixture" }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  if [ "${3:-wave}" != wave ]; then sed "s/^scale: wave$/scale: $3/" "$p" > "$p.tmp" && mv "$p.tmp" "$p"; fi
  s42_snap "$r" "$p"
  printf '%s\n%s' "$r" "$p"
}
SH_W="$(sf_wave sf-share-w '  note: the block owes its fields')"; RSW="${SH_W%%$'\n'*}"; PSW="${SH_W#*$'\n'}"
poke "$RSW" current 4
expect_eq "SF-10 current 4 on a wave plan exits 0" "0" "$RC"
expect_eq "SF-10b …the Step-4 block gains share: 55, the value gate_share prints" "1" "$(sf_block "$PSW" 4 | /usr/bin/grep -cxF -- '  share: 55')"
expect_eq "SF-10c …after the three fields the verb fills (worktree, base-sha, branch, share)" "worktree|base-sha|branch|share" \
  "$(sf_block "$PSW" 4 | sed -n '/^  note:/,$p' | sed -n '2,$p' | sed 's/^  \([a-z-]*\):.*/\1/' | paste -sd'|' -)"
expect_eq "SF-10d …current: plus four added lines and nothing else (git diff --numstat)" "5 1;" "$(s42_numstat "$RSW")"
expect_contains "SF-10e …and says the block gained it" "share=55" "$OUT"
s34_gate "$RSW"
expect_eq "SF-10f …and the first Step-4 commit is admitted with the line in the block" "0" "$GATE_RC"
rm -f "$SH_CFG/bionic/share"
SH_D="$(sf_wave sf-share-d '  note: the block owes its fields')"; RSD="${SH_D%%$'\n'*}"; PSD="${SH_D#*$'\n'}"
poke "$RSD" current 4
expect_eq "SF-11 with no share file, current 4 writes the gate's 80" "0|1" "$RC|$(sf_block "$PSD" 4 | /usr/bin/grep -cxF -- '  share: 80')"
printf '55\n' > "$SH_CFG/bionic/share"
SH_P="$(sf_wave sf-share-p '  share: 33
  note: the block carries a share already')"; RSP="${SH_P%%$'\n'*}"; PSP="${SH_P#*$'\n'}"
poke "$RSP" current 4
expect_eq "SF-12 a block already carrying share: 33 keeps it (AC-2.11: not rewritten), and gains the rest" "0|1|1|1" \
  "$RC|$(sf_block "$PSP" 4 | /usr/bin/grep -cxF -- '  share: 33')|$(sf_block "$PSP" 4 | /usr/bin/grep -c '^  share:')|$(sf_block "$PSP" 4 | /usr/bin/grep -cxF -- '  branch: wave/01-fixture')"
SH_T="$(sf_wave sf-share-t '  note: the block owes its fields' task)"; RST="${SH_T%%$'\n'*}"; PST="${SH_T#*$'\n'}"
expect_eq "SF-13-pre precondition: the plan is task scale" "1" "$(/usr/bin/grep -c '^scale: task$' "$PST")"
poke "$RST" current 4
expect_eq "SF-13 a task-scale plan: current 4 fills the three fields and writes no share:" "0|1|0" \
  "$RC|$(sf_block "$PST" 4 | /usr/bin/grep -cxF -- '  branch: wave/01-fixture')|$(/usr/bin/grep -c '^  share:' "$PST")"
if [ "$SH_CCD_WAS" = __unset__ ]; then unset CLAUDE_CONFIG_DIR; else export CLAUDE_CONFIG_DIR="$SH_CCD_WAS"; fi

# ============================================================
section "§STEP-FIELD (writers): finding-check's code writer is read by the Files matcher, and every agent the row carried (wave-28 T8; A-orch-159, A-orch-161)"
# ============================================================
#
# `finding-check` refuses a check record written by the finding's reader or by the code's writer. The writer was the
# CURRENT agent cell of each `## Tasks` row whose Files entry EQUALS the finding's path. Now the row is found by the
# matcher the dispatch grammar uses (lib/units.sh: an exact path, a directory, a glob, a path suffix), and the
# agents are every one the row has carried: its Tasks cell, the name in its dispatch-ledger agent cell
# (`<role> (<name>)`), and each roster row of the project labelled `row=<id>`.
# FIXTURE FIDELITY: §SEV's repository, plan and roster; the rows by the production verbs (task-add, task-set,
# ledger-add), the roster row by `roster_row_fixture` (the production writer, `row=` its own key).
SFW_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
printf '%s|questions=adversarial|pushed=checks-adversarial,severity\n' \
  "$(roster_row_fixture session="$SID" name=sfw-crit agent_id=a-sfw-crit subagent_type=bionic:critic files="$(sev_files "sfw-a")")" >> "$SEV_RS"
roster_row_fixture session="$SID" name=sfw-impl-x agent_id=a-sfw-impl-x subagent_type=bionic:implementor row=T7 >> "$SEV_RS"
sev_cur 4
poke "$RSEV" task-add T7 4 build 'the directory writer' sfw-impl-b '—' 30 REQ-1 'lib/'
poke "$RSEV" task-set T7 status=landed
poke "$RSEV" ledger-add T7 'agent=implementor (sfw-impl)'
expect_eq "SFW-0 precondition: a landed Tasks row T7 whose Files is the directory lib/, its agent sfw-impl-b, and a ledger row naming sfw-impl" "1|1|1" \
  "$(/usr/bin/grep -c '^| T7 | 4 | build | the directory writer | sfw-impl-b .* | lib/ | .* | landed |$' "$PSEV")|$(/usr/bin/grep -c '^| T7 | implementor (sfw-impl) |' "$PSEV")|$(/usr/bin/grep -c '^- T7:' "$PSEV")"
SFW_H="$(git -C "$SEV_WT" rev-parse HEAD)"
pk_rec sfw-a "$SFW_H" flag "findings: 4" \
  "finding: 1 S3 off lib/c.sh:4 - a path the Files entry lib/ covers" "unsure: 1 which caller" \
  "finding: 2 S3 off lib/c.sh:5 - a path the first instance wrote" "unsure: 2 which caller" \
  "finding: 3 S3 off lib/c.sh:6 - a path a roster successor wrote" "unsure: 3 which caller" \
  "finding: 4 S3 off lib/c.sh:7 - a path a third agent may check" "unsure: 4 which caller"
poke "$RSEV" proof-add review record/wave-01-fixture/sfw-a.md --question adversarial --reader sfw-crit
expect_eq "SFW-0b precondition: the reading registers with its four check: lines (exit 0)" "0|4" "$RC|$(/usr/bin/grep -c "^check: record/wave-01-fixture/sfw-a.md#" "$PSEV")"
sfw_chk() { chk_rec "$1" "$2"; }
sfw_chk sfw-by-cell sfw-impl-b; sfw_chk sfw-by-ledger sfw-impl; sfw_chk sfw-by-roster sfw-impl-x; sfw_chk sfw-by-third sfw-third
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check record/wave-01-fixture/sfw-a.md#1 refuted record/wave-01-fixture/sfw-by-cell.md
s42_unchanged "SFW-1 A-orch-159 a check written by the agent of a row whose Files is a DIRECTORY holding the finding's file" 1 "$PSEV"
expect_contains "SFW-1b …is refused as the code's writer, naming the path" "the agent of the ## Tasks row whose Files hold lib/c.sh" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check record/wave-01-fixture/sfw-a.md#2 refuted record/wave-01-fixture/sfw-by-ledger.md
s42_unchanged "SFW-2 A-orch-161 a check written by the FIRST instance of the row (the name in the dispatch ledger's agent cell)" 1 "$PSEV"
expect_contains "SFW-2b …is refused as the code's writer" "the agent of the ## Tasks row whose Files hold lib/c.sh" "$OUT"
s42_snap "$RSEV" "$PSEV"; poke "$RSEV" finding-check record/wave-01-fixture/sfw-a.md#3 refuted record/wave-01-fixture/sfw-by-roster.md
s42_unchanged "SFW-3 A-orch-161 a check written by an instance the roster labels row=T7" 1 "$PSEV"
expect_contains "SFW-3b …is refused as the code's writer" "the agent of the ## Tasks row whose Files hold lib/c.sh" "$OUT"
poke "$RSEV" finding-check record/wave-01-fixture/sfw-a.md#4 refuted record/wave-01-fixture/sfw-by-third.md
expect_eq "SFW-4 the same finding-check by a third agent is admitted (the refusals above were the writer's)" "0|1" \
  "$RC|$(/usr/bin/grep -c '^check: record/wave-01-fixture/sfw-a.md#4 .* refuted by=record/wave-01-fixture/sfw-by-third.md$' "$PSEV")"
POKE_BOUND="$SFW_BOUND_WAS"
POKE_BOUND="$SF_BOUND_WAS"

# ============================================================
section "§FLOOR-DECLARED: a project declares its floor; the tool checks the contract, not the runner (wave-28 T75; REQ-17 AC-17.1–17.3; D36)"
# ============================================================
#
# A project whose floor is not tests/run.sh has no tests/*.test.sh roster, so no run log could ever satisfy
# `proof_attested floor` and the run could never close. It declares its floor in `.bionic/config.yaml`:
# `floor: <command>`, which `floor-run` runs in the working checkout and logs under a first line
# `head=<40-hex> dirty=<n> rc=<n>`, or `floor-attestation: user`, whose evidence is the user's record of a
# `head=<40-hex> dirty=0` line and a `floor-attested-by: <who> <when> <what ran>` line. `proof-add floor`
# stays the one writer of the proof line and judges head, dirty and rc alone. With neither key §46's rows
# (the tests/run.sh rule, unchanged) are the control (AC-17.3), and FD-c1 below shows the arm is not entered.
#
# FIXTURE FIDELITY. The repository holds NO tests/ directory at its working head, the shape of the project
# the finding came from. The declared command is a script this section writes: it records its working
# directory and arguments in a file and does what a mode file says (pass, fail, or leave a stray file), so a
# row reads where it ran and what it left. The plan is s42_plan's, bound to this session, with
# `working-branch:` naming a linked worktree one commit ahead of the main checkout.
FD_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
FD_ROOTS="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/roots.sh"
RFD="$(make_repo s75-floor-declared)"; ( cd "$RFD" && git commit -q --allow-empty -m init )
PFD="$(s42_plan "$RFD" 4)"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PFD" > "$PFD.tmp" && mv "$PFD.tmp" "$PFD"
( cd "$RFD" && git add -f "$PFD" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RFD/.worktrees/01-fixture" \
  && git -C "$RFD/.worktrees/01-fixture" commit -q --allow-empty -m "wave work" ) >/dev/null 2>&1
FD_WT="$RFD/.worktrees/01-fixture"
FD_W="$(git -C "$FD_WT" rev-parse HEAD 2>/dev/null)"
FD_REC="$RFD/.bionic/docs/record/wave-01-fixture"; mkdir -p "$FD_REC"
FD_SEEN="$TMPROOT/fd-seen"; FD_MODE="$TMPROOT/fd-mode"; echo pass > "$FD_MODE"
FD_STUB="$TMPROOT/fd-floor.sh"
cat > "$FD_STUB" <<FD_EOF
#!/bin/bash
printf 'cwd=%s args=%s\n' "\$(pwd -P)" "\$*" >> "$FD_SEEN"
case "\$(cat "$FD_MODE")" in
  fail) echo 'floor: 3 passed, 1 failed'; exit 1 ;;
  stray) : > stray.txt; echo 'floor: 4 passed, 0 failed'; exit 0 ;;
  *) echo 'floor: 4 passed, 0 failed'; exit 0 ;;
esac
FD_EOF
fd_runs() { [ -f "$FD_SEEN" ] && awk 'END { print NR + 0 }' "$FD_SEEN" || echo 0; }
fd_config() { printf '%s\n' "$@" > "$RFD/.bionic/config.yaml"; }  # <line>... -> the project's config, exactly these lines
fd_proved() { /usr/bin/grep -E '^proved: kind=floor ' "$PFD" | tail -n 1; }
# fd_attest <lib> <evidence> -> "<exit>|<what proof_attested floor printed>", the roots library sourced first,
# the checkout the working tree and the project root RFD: the judge itself, for the mutants below.
fd_attest() {
  bash -c '. "$1" && . "$2" || exit 9; o="$(proof_attested floor "$3" "$4" "" "" "$5")"; r=$?; printf "%s|%s" "$r" "$o"' \
    _ "$FD_ROOTS" "$1" "$2" "$FD_WT" "$RFD" 2>/dev/null
}
expect_regex "FD-0 precondition: the working head is a 40-hex commit" '^[0-9a-f]{40}$' "$FD_W"
expect_eq "FD-0b precondition: …and holds no tests/*.test.sh roster" "0" \
  "$(git -C "$FD_WT" ls-tree --name-only "$FD_W" tests/ 2>/dev/null | /usr/bin/grep -c '\.test\.sh$' | tr -d ' ')"
expect_eq "FD-0c precondition: …and its checkout is clean" "" "$(git -C "$FD_WT" status --porcelain 2>/dev/null)"

# ---------- AC-17.1: no floor: key, nothing run ----------
s42_snap "$RFD" "$PFD"
poke "$RFD" floor-run
s42_unchanged "FD-n1 §FLOOR-DECLARED floor-run with no floor: key" 1 "$PFD"
expect_contains "FD-n2 …saying so, and that nothing was run" \
  "REFUSED — this project declares no floor: in .bionic/config.yaml; its regression is tests/run.sh, whose log proof-add floor reads. Nothing was run." "$OUT"
expect_eq "FD-n3 …and the declared command never ran (the stub's log is empty)" "0" "$(fd_runs)"
fd_config "floor-attestation: user"
poke "$RFD" floor-run
expect_eq "FD-n4 …nor with floor-attestation: user alone, which declares no command (exit 1, nothing run)" "1|0" "$RC|$(fd_runs)"

# ---------- AC-17.1: floor-run runs and logs; proof-add floor writes the line ----------
fd_config "floor: bash $FD_STUB --all"
poke "$RFD" floor-run
FD_LOG="$FD_REC/floor-run-$FD_W.log"
expect_eq "FD-a1 floor-run runs the declared command (exit 0, the command's own)" "0" "$RC"
expect_eq "FD-a2 …once, in the working branch's checkout, its words split on blanks" \
  "1|cwd=$(cd "$FD_WT" && pwd -P) args=--all" "$(fd_runs)|$(tail -n 1 "$FD_SEEN" 2>/dev/null)"
expect_eq "FD-a3 …its log opens head=<working head> dirty=0 rc=0, then command: <cmd>" \
  "head=$FD_W dirty=0 rc=0|command: bash $FD_STUB --all" "$(head -n 2 "$FD_LOG" 2>/dev/null | paste -sd'|' -)"
expect_contains "FD-a4 …and carries the command's output" "floor: 4 passed, 0 failed" "$(cat "$FD_LOG" 2>/dev/null)"
expect_contains "FD-a5 …and the verb prints the proof-add floor line to run" \
  "proof-add floor record/wave-01-fixture/floor-run-$FD_W.log" "$OUT"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor "record/wave-01-fixture/floor-run-$FD_W.log"
expect_eq "FD-a6 proof-add floor accepts the declared floor's log (exit 0)" "0" "$RC"
expect_regex "FD-a7 …and writes the proof line at the working head, naming that log" \
  "^proved: kind=floor head=${FD_W} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/floor-run-${FD_W}\.log$" "$(fd_proved)"
expect_eq "FD-a8 …which proof_last reads back as the floor at the working head, with no roster counted" "$FD_W" "$(s46_last "$PFD" floor)"

# ---------- AC-17.1: the same log at another head, dirty, red, or in the old shape is refused ----------
FD_OTHER="0123456789abcdef0123456789abcdef01234567"
{ printf 'head=%s dirty=0 rc=0\n' "$FD_OTHER"; tail -n +2 "$FD_LOG"; } > "$FD_REC/fd-other.log"
{ printf 'head=%s dirty=2 rc=0\n' "$FD_W"; tail -n +2 "$FD_LOG"; } > "$FD_REC/fd-dirty.log"
{ printf 'head=%s dirty=0 rc=1\n' "$FD_W"; tail -n +2 "$FD_LOG"; } > "$FD_REC/fd-red.log"
printf 'floor log\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' "$FD_W" > "$FD_REC/fd-runner.log"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-other.log
s42_unchanged "FD-r1 a declared floor's log that read another head" 1 "$PFD"
expect_contains "FD-r1b …with today's head sentence" \
  "read head ${FD_OTHER:0:12}, but the working branch is at ${FD_W:0:12}; run it again on ${FD_W:0:12}" "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-dirty.log
s42_unchanged "FD-r2 …that read a dirty tree" 1 "$PFD"
expect_contains "FD-r2b …with today's dirty sentence" "read a dirty tree (dirty=2); commit, run it again and cite that log" "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-red.log
s42_unchanged "FD-r3 …whose command exited 1" 1 "$PFD"
expect_regex "FD-r3b …saying the regression did not pass (wave-30 T23: the word)" \
  'the regression in [^ ]*fd-red\.log did not pass \(rc=1\); fix it, run floor-run again and cite that log' "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-runner.log
s42_unchanged "FD-r4 …and a log in the old tests/run.sh shape, green at the head" 1 "$PFD"
expect_contains "FD-r4b …saying what the first line must be" \
  "does not open with head=<40-hex> dirty=<n> rc=<n>, the line floor-run writes; run floor-run and cite its log" "$OUT"

# ---------- AC-17.1: a failing run, a stray file, a dirty tree ----------
echo fail > "$FD_MODE"
poke "$RFD" floor-run
expect_eq "FD-f1 a failing declared command: floor-run exits with its code (1)" "1" "$RC"
expect_contains "FD-f2 …prints its output" "floor: 3 passed, 1 failed" "$OUT"
expect_eq "FD-f3 …and writes a second log at the head, opening rc=1" "head=$FD_W dirty=0 rc=1" \
  "$(head -n 1 "$FD_REC/floor-run-$FD_W-2.log" 2>/dev/null)"
expect_true "FD-f3b …the first log standing" test -f "$FD_LOG"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor "record/wave-01-fixture/floor-run-$FD_W-2.log"
s42_unchanged "FD-f4 …whose log proof-add floor refuses" 1 "$PFD"
echo stray > "$FD_MODE"
poke "$RFD" floor-run
expect_eq "FD-s1 a command that leaves the tree dirtier than it found it is refused (exit 1)" "1" "$RC"
expect_regex "FD-s2 …naming the regression, the move and that no log was written (wave-30 T23: the word)" \
  'REFUSED — the regression \(.*\) moved the working checkout .* while it ran \(dirty=0 to dirty=1\); no log was written' "$OUT"
expect_false "FD-s3 …and no third log exists" test -e "$FD_REC/floor-run-$FD_W-3.log"
echo pass > "$FD_MODE"
poke "$RFD" floor-run
expect_eq "FD-d1 on a dirty tree the floor still runs (exit 0) and its log says so" "0|head=$FD_W dirty=1 rc=0" \
  "$RC|$(head -n 1 "$FD_REC/floor-run-$FD_W-3.log" 2>/dev/null)"
expect_contains "FD-d2 …and the verb says proof-add floor refuses it" "the tree was dirty (dirty=1), so proof-add floor refuses this log" "$OUT"
rm -f "$FD_WT/stray.txt"

# ---------- AC-17.2: the user's attestation, read by its two lines ----------
fd_config "floor-attestation: user"
printf '# floor\nhead=%s dirty=0\nfloor-attested-by: Dana 2026-10-07T10:00Z ran the bench rig by hand\n' "$FD_W" > "$FD_REC/fd-att.md"
printf '# floor\nfloor-attested-by: Dana 2026-10-07T10:00Z ran the bench rig by hand\n' > "$FD_REC/fd-att-nohead.md"
printf '# floor\nhead=%s dirty=0\nfloor-attested-by: Dana 2026-10-07T10:00Z ran the bench rig by hand\n' "$FD_OTHER" > "$FD_REC/fd-att-other.md"
printf '# floor\nhead=%s dirty=0\nall good\n' "$FD_W" > "$FD_REC/fd-att-noby.md"
printf '# floor\nhead=%s dirty=0\nfloor-attested-by: Dana yesterday\n' "$FD_W" > "$FD_REC/fd-att-short.md"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att-nohead.md
s42_unchanged "FD-t1 AC-17.2 an attestation lacking the head line" 1 "$PFD"
expect_contains "FD-t1b …naming the line" "carries no head=<40-hex> dirty=0 line naming the working head" "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att-other.md
s42_unchanged "FD-t2 …one naming another head" 1 "$PFD"
expect_contains "FD-t2b …with today's head sentence" "read head ${FD_OTHER:0:12}, but the working branch is at ${FD_W:0:12}" "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att-noby.md
s42_unchanged "FD-t3 …one lacking floor-attested-by:" 1 "$PFD"
expect_contains "FD-t3b …naming the line" "carries no floor-attested-by: <who> <when> <what ran> line" "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att-short.md
s42_unchanged "FD-t4 …and one whose floor-attested-by: says fewer than three words" 1 "$PFD"
poke "$RFD" proof-add floor "record/wave-01-fixture/floor-run-$FD_W.log"
s42_unchanged "FD-t5 …and with floor-attestation: user alone a floor-run log is no attestation" 1 "$PFD"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att.md
expect_eq "FD-t6 a record with both lines at the working head is written (exit 0)" "0" "$RC"
expect_regex "FD-t7 …the proof line naming the head and the record" \
  "^proved: kind=floor head=${FD_W} at=[^ ]+ evidence=record/wave-01-fixture/fd-att\.md$" "$(fd_proved)"
fd_config "floor-attestation: yes"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att.md
s42_unchanged "FD-t8 floor-attestation: yes is refused by value" 1 "$PFD"
expect_contains "FD-t8b …naming the value and the one it takes" \
  "the floor-attestation: in .bionic/config.yaml is yes, and the one value it takes is user" "$OUT"

# ---------- both keys: either shape; neither key: the arm is not entered (AC-17.3) ----------
fd_config "floor: bash $FD_STUB --all" "floor-attestation: user"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor "record/wave-01-fixture/floor-run-$FD_W.log"
expect_eq "FD-b1 with both keys the declared floor's log is accepted (exit 0)" "0" "$RC"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-att.md
expect_eq "FD-b2 …and so is the attestation (exit 0)" "0" "$RC"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-red.log
expect_eq "FD-b3 …while a red declared log is still refused as one, not read as an attestation" "1" "$RC"
expect_contains "FD-b3b …with the rc sentence" "did not pass (rc=1)" "$OUT"
fd_config "release-check: true"
s42_snap "$RFD" "$PFD"
poke "$RFD" proof-add floor "record/wave-01-fixture/floor-run-$FD_W.log"
s42_unchanged "FD-c1 AC-17.3 with neither key the declared floor's log is judged by the tests/run.sh rule" 1 "$PFD"
expect_contains "FD-c1b …in today's words: no head=<sha> dirty=<n> line" "carries no head=<sha> dirty=<n> line" "$OUT"
poke "$RFD" proof-add floor record/wave-01-fixture/fd-runner.log
s42_unchanged "FD-c2 …and the old runner's log, green at the head, still meets the roster rule (0 suites here)" 1 "$PFD"
expect_contains "FD-c2b …in today's words" "3 passed and 0 void of 0 suites" "$OUT"

# ---------- the mutants: doctored copies of the judge, never the tracked file ----------
FD_MUT="$(mktemp -d "$TMPROOT/fd-mut.XXXXXX")"
fd_config "floor: bash $FD_STUB --all" "floor-attestation: user"
expect_eq "FD-m0 the judge itself, positive: the green declared log attests the working head" "0|$FD_W" "$(fd_attest "$S46_LIB" "$FD_LOG")"
expect_eq "FD-m0b …a red one is refused" "1" "$(fd_attest "$S46_LIB" "$FD_REC/fd-red.log" | cut -d'|' -f1)"
expect_eq "FD-m0c …and an unattested record is refused" "1" "$(fd_attest "$S46_LIB" "$FD_REC/fd-att-noby.md" | cut -d'|' -f1)"
FD_M1='[ -z "$fl$fa" ] || { _proof_floor_declared'
FD_M2='[ "$rc" = 0 ] || { printf '"'"'the regression in'
FD_M3='[ -n "$who" ] || { printf'
anchor "$S46_LIB" "$FD_M1" 1; anchor "$S46_LIB" "$FD_M2" 1; anchor "$S46_LIB" "$FD_M3" 1
/usr/bin/grep -vF -- "$FD_M1" "$S46_LIB" > "$FD_MUT/no-arm.sh"
/usr/bin/grep -vF -- "$FD_M2" "$S46_LIB" > "$FD_MUT/no-rc.sh"
/usr/bin/grep -vF -- "$FD_M3" "$S46_LIB" > "$FD_MUT/no-by.sh"
for _fdm in no-arm no-rc no-by; do
  expect_eq "FD-m-$_fdm the mutant differs from the judge in one line and parses" "1|0" \
    "$(diff "$S46_LIB" "$FD_MUT/$_fdm.sh" | /usr/bin/grep -c '^<' | tr -d ' ')|$(bash -n "$FD_MUT/$_fdm.sh" 2>/dev/null; echo $?)"
done
_fdm1="$(fd_attest "$FD_MUT/no-arm.sh" "$FD_LOG")"
case "$_fdm1" in
  *'carries no head=<sha> dirty=<n> line'*) _fdm1_yes=yes ;;
  *) _fdm1_yes=no ;;
esac
expect_eq "FD-m1 the declared arm removed: the mutant runs (a tests/run.sh-shaped refusal) and refuses the green declared log, so FD-a6 goes red under it" \
  "1|yes" "${_fdm1%%|*}|$_fdm1_yes"
expect_eq "FD-m2 the rc test dropped: the mutant admits the rc=1 log, so FD-r3 goes red under it" "0|$FD_W" "$(fd_attest "$FD_MUT/no-rc.sh" "$FD_REC/fd-red.log")"
expect_eq "FD-m3 the floor-attested-by: test dropped: the mutant admits the unattested record, so FD-t3 goes red under it" \
  "0|$FD_W" "$(fd_attest "$FD_MUT/no-by.sh" "$FD_REC/fd-att-noby.md")"
rm -rf "$FD_MUT"
POKE_BOUND="$FD_BOUND_WAS"


# ============================================================
section "§MATRIX-RENDER: matrix-render writes, from ## Eval design, one AC block per criterion with the keys its tier owes set to pending, adds only what is missing, and never overwrites a value (wave-30 T14; REQ-6 AC-6.1; D9, Δ12a)"
# ============================================================
#
#   matrix-render      the bound plan's ## Verification Matrix gains, for each ## Eval design criterion, a block:
#                      provenance (the requirement's own provenance: line, else the row's Approach), fails-when and
#                      eval (`<tier> — <Eval>`) from the table, task (the one ## Tasks row serving it, else pending),
#                      then evidence and every other key walls.sh keys_for_tier names for the row's tier, each
#                      `pending`; and stack-health: pending (walk-artifact: pending too unless walk: exempt) where
#                      the matrix has none. It prints `matrix-render — <n> blocks written, <m> keys added, <k> unchanged`.
#
# It takes the plan transaction every row verb takes (copy, dry commit through the real gate, checksum, swap), so a
# render the gate would refuse is not written. REFUSED (1), plan byte-identical: no ## Eval design table, no matrix
# table, a criterion the matrix table has no row (no tier) for; an operand is the usage error (2).
# FIXTURE FIDELITY: §42's repository and plan writer (a plan the real gate admits) at current: 3, given a
# ## Requirements section, a four-row ## Eval design and four matrix rows of four tiers; the real verb; the evidence is
# the plan's own bytes and the real gate's verdict on them.
MR_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
mr_fixture() {  # <plan> -> T5 serves REQ-2; Requirements and Eval design ahead of the matrix; AC-1.2, 2.1, 2.2 rows
  awk '
    /^\| T5 \| 5 \| verify \|/ { sub(/\| REQ-1 \|/, "| REQ-2 |") }
    /^## Verification Matrix/ {
      print "## Requirements\n\n### REQ-1 — the first\n\nprovenance: spec §1 (fixture)\n\n### REQ-2 — the second\n\n- AC-2.1 the second criterion\n"
      print "## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|"
      print "| REQ-1 | first approach | AC-1.1 | hermetic | \140--only a.test.sh\140 (§A) | a is wrong |"
      print "| REQ-1 | second approach | AC-1.2 | static | docs-pins §B | b is wrong |"
      print "| REQ-2 | live approach | AC-2.1 | live | walk W1 → narrated | c is wrong |"
      print "| REQ-2 | user approach | AC-2.2 | live | the user confirms | d is wrong |\n"
    }
    /^\| AC-1\.1 \| T2 \|/ { print; print "| AC-1.2 | T0 | pending | — | — |\n| AC-2.1 | T3 | pending | — | — |\n| AC-2.2 | T4 | pending | — | — |"; next }
    { print }' "$1" > "$1.mr" && mv "$1.mr" "$1"
}
mr_block() {  # <plan> <AC> -> the block: its header line and the indented lines under it
  awk -v k="$2:" 'index($0, k) == 1 { f = 1; print; next } f && /^  / { print; next } f { exit }' "$1"
}
mr_heads() {  # <plan> -> the matrix-level stack-health/walk-artifact keys, in order, |-joined
  awk '/^## / { m = ($0 ~ /^## Verification Matrix/); next } m && /^(stack-health|walk-artifact):/ { sub(/:.*/, ""); print }' "$1" | paste -sd'|' -
}
mr_cell() {  # <plan> <AC> <field n> -> that cell of the matrix row, trimmed
  awk -F'|' -v a="$2" -v n="$3" '/^## / { m = ($0 ~ /^## Verification Matrix/); next }
    m && /^\|/ { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == a) { v = $n; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$1"
}
RMR="$(make_repo mr-render)"; ( cd "$RMR" && git commit -q --allow-empty -m init )
PMR="$(s42_plan "$RMR" 3)"
mr_fixture "$PMR"
s42_snap "$RMR" "$PMR"
s34_gate "$RMR"
expect_eq "MR-0 precondition: the fixture plan at current: 3, four criteria and one AC block, is admitted by the real gate" "0" "$GATE_RC"
expect_eq "MR-0b …the block extractor reads the one block the fixture carries (positive, before any render)" \
  "AC-1.1:|  provenance: fixture|  fails-when: the fixture is wrong" "$(mr_block "$PMR" AC-1.1 | paste -sd'|' -)"
expect_eq "MR-0c …the cell extractor reads a row's tier" "T3" "$(mr_cell "$PMR" AC-2.1 3)"
expect_eq "MR-0d …and the matrix carries no stack-health: line yet (the heads extractor, before; MR-4 is its positive)" "" "$(mr_heads "$PMR")"

poke "$RMR" matrix-render
expect_eq "MR-1 matrix-render exits 0" "0" "$RC"
expect_contains "MR-1b …and counts what it did: three new blocks, four keys added to the one block and the matrix head" \
  "matrix-render — 3 blocks written, 4 keys added, 0 unchanged" "$OUT"
MR_W12='AC-1.2:
  provenance: spec §1 (fixture)
  fails-when: b is wrong
  eval: T0 — docs-pins §B
  task: pending
  evidence: pending'
expect_eq "MR-2 a T0 criterion: provenance from its requirement, fails-when and eval from the table, task pending (T1 and T2 both serve REQ-1), then evidence and nothing more" \
  "$MR_W12" "$(mr_block "$PMR" AC-1.2)"
MR_W21='AC-2.1:
  provenance: live approach
  fails-when: c is wrong
  eval: T3 — walk W1 → narrated
  task: T5
  evidence: pending'
expect_eq "MR-3 a T3 criterion: no provenance: under REQ-2, so the Approach; task T5, the one row serving REQ-2; evidence and nothing more" \
  "$MR_W21" "$(mr_block "$PMR" AC-2.1)"
MR_W22='AC-2.2:
  provenance: user approach
  fails-when: d is wrong
  eval: T4 — the user confirms
  task: T5
  evidence: pending
  user-confirmed: pending'
expect_eq "MR-3b a T4 criterion: user-confirmed" "$MR_W22" "$(mr_block "$PMR" AC-2.2)"
MR_W11='AC-1.1:
  provenance: fixture
  fails-when: the fixture is wrong
  eval: T2 — `--only a.test.sh` (§A)
  task: pending
  evidence: pending'
expect_eq "MR-3c the existing T2 block keeps its two lines as written (the table's 'a is wrong' does not replace them) and gains the three it lacked, evidence the last" \
  "$MR_W11" "$(mr_block "$PMR" AC-1.1)"
# wave-31 T6 (REQ-5 AC-5.1): one pointer per matrix row. The positive first — the grep reads the rendered plan's bytes and
# finds the four evidence stubs, one per block — then the absence, on the same extractor over the same bytes.
expect_eq "MR-3d the rendered matrix carries one 'evidence: pending' per block (four blocks, four stubs)" "4" \
  "$(/usr/bin/grep -c '^  evidence: pending$' "$PMR")"
expect_eq "MR-3e …and no stub for a key the gate no longer owes (tier-run, readback, fixture-fidelity, fresh, cold-client, contact)" "0" \
  "$(/usr/bin/grep -c '^  \(tier-run\|readback\|fixture-fidelity\|fresh\|cold-client\|contact\): ' "$PMR" || true)"
expect_eq "MR-4 the matrix head gains stack-health: and no walk-artifact: line, the fixture being walk: exempt" "stack-health" "$(mr_heads "$PMR")"
expect_eq "MR-4b …and the stack-health: line reads pending" "1" "$(/usr/bin/grep -cx 'stack-health: pending' "$PMR")"
s34_gate "$RMR"
expect_eq "MR-5 the rendered plan, pending stubs and all, is admitted by the real gate at current: 3" "0" "$GATE_RC"
cp "$PMR" "$TMPROOT/mr-keep"
sed 's/^current: 3$/current: 4/' "$TMPROOT/mr-keep" > "$PMR"
s34_gate "$RMR"
expect_eq "MR-5b …and at current: 4" "0" "$GATE_RC"
cp "$TMPROOT/mr-keep" "$PMR"

s42_snap "$RMR" "$PMR"
poke "$RMR" matrix-render
expect_eq "MR-6 a second render exits 0" "0" "$RC"
expect_contains "MR-6b …writes nothing and says so in the same line" "matrix-render — 0 blocks written, 0 keys added, 4 unchanged" "$OUT"
expect_true "MR-6c …and the plan is byte-identical (cmp)" cmp -s "$TMPROOT/s42-before" "$PMR"

awk '/^AC-1\.1:/ { b = 1 } /^AC-1\.2:/ { b = 2 } /^AC-2\.1:/ { b = 0 }
     b == 1 && /^  evidence: / { print "  evidence: record/a.md"; next }
     b == 2 && /^  evidence: / { next } { print }' "$TMPROOT/mr-keep" > "$PMR"
s42_snap "$RMR" "$PMR"
poke "$RMR" matrix-render
expect_eq "MR-7 a render over a filled value and a dropped key exits 0" "0" "$RC"
expect_contains "MR-7b …adds the one missing key and leaves the other three blocks as they are" "matrix-render — 0 blocks written, 1 keys added, 3 unchanged" "$OUT"
expect_eq "MR-7c …the filled evidence: stands, nothing written over it" "1|0" \
  "$(mr_block "$PMR" AC-1.1 | /usr/bin/grep -cx '  evidence: record/a.md')|$(mr_block "$PMR" AC-1.1 | /usr/bin/grep -cx '  evidence: pending')"
expect_eq "MR-7d …and the dropped evidence: is back, as the block's last line" "  evidence: pending" "$(mr_block "$PMR" AC-1.2 | tail -1)"
expect_eq "MR-7e …one line added, none removed (git diff --numstat)" "1 0;" "$(s42_numstat "$RMR")"
cp "$TMPROOT/mr-keep" "$PMR"

# ---------- walk: required renders the walk-artifact: stub too ----------
RMRW="$(make_repo mr-walk)"; ( cd "$RMRW" && git commit -q --allow-empty -m init )
PMRW="$(s42_plan "$RMRW" 3)"
mr_fixture "$PMRW"
sed 's/^walk: exempt$/walk: required/' "$PMRW" > "$PMRW.w" && mv "$PMRW.w" "$PMRW"
s42_snap "$RMRW" "$PMRW"
poke "$RMRW" matrix-render
expect_eq "MR-8 on a walk: required plan the head gains stack-health: and walk-artifact:, both pending" "0|stack-health|walk-artifact|1" \
  "$RC|$(mr_heads "$PMRW")|$(/usr/bin/grep -cx 'walk-artifact: pending' "$PMRW")"
expect_contains "MR-8b …counted with the keys added" "matrix-render — 3 blocks written, 5 keys added, 0 unchanged" "$OUT"

# ---------- the refusals: plan byte-identical ----------
mr_refused() {  # <label> <want rc> <want text> <plan content file> [operands…]
  local label="$1" rc="$2" want="$3" src="$4"; shift 4
  cp "$src" "$PMR"; s42_snap "$RMR" "$PMR"; poke "$RMR" matrix-render "$@"
  s42_unchanged "$label" "$rc" "$PMR"
  expect_contains "$label …saying why" "$want" "$OUT"
}
awk '/^## Eval design/ { skip = 1; next } skip && /^## / { skip = 0 } !skip' "$TMPROOT/mr-keep" > "$TMPROOT/mr-noeval"
mr_refused "MR-9 a plan with no ## Eval design" 1 "no ## Eval design" "$TMPROOT/mr-noeval"
awk '/^## / { m = ($0 ~ /^## Verification Matrix/) } m && /^\|/ { next } { print }' "$TMPROOT/mr-keep" > "$TMPROOT/mr-notable"
mr_refused "MR-10 a matrix with no AC tier table" 1 "no AC tier table" "$TMPROOT/mr-notable"
awk '{ print } /^\| REQ-2 \| user approach/ { print "| REQ-3 | late approach | AC-3.1 | hermetic | x | e is wrong |" }' "$TMPROOT/mr-keep" > "$TMPROOT/mr-norow"
mr_refused "MR-11 a criterion the matrix table has no row for (its tier unknown)" 1 "AC-3.1" "$TMPROOT/mr-norow"
mr_refused "MR-12 an operand is the usage error" 2 "takes no argument" "$TMPROOT/mr-keep" "$PMR"
cp "$TMPROOT/mr-keep" "$PMR"

# ---------- the mutation arm: the key list taken from walls.sh, not typed twice ----------
# A copy of the library whose keys_for_tier drops user-confirmed from T4, behind a copy of the hook that reads it:
# the same render on the same plan writes AC-2.2 without the key, so MR-3b goes red under it.
MRM_NEEDLE='T4)          echo "user-confirmed evidence" ;;'
MRM_WALLS="$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)/walls.sh"
anchor "$MRM_WALLS" "$MRM_NEEDLE" 1
MRM_DIR="$TMPROOT/poker-mr-mut"; rm -rf "$MRM_DIR"; mkdir -p "$MRM_DIR/hooks" "$MRM_DIR/scripts"
cp -R "$(cd "$(dirname "$POKER")/../payload/scripts/lib" && pwd -P)" "$MRM_DIR/scripts/lib"
for _mr_f in "$(dirname "$POKER")"/*; do [ "${_mr_f##*/}" = session-poker.sh ] || ln -s "$_mr_f" "$MRM_DIR/hooks/${_mr_f##*/}"; done
cp "$POKER" "$MRM_DIR/hooks/session-poker.sh"
MR_N="$MRM_NEEDLE" awk 'BEGIN { n = ENVIRON["MR_N"] } index($0, n) { sub(/user-confirmed /, "") } { print }' "$MRM_WALLS" > "$MRM_DIR/scripts/lib/walls.sh"
expect_eq "MR-mut0 the copy of the library differs from it in one line" "1" "$(diff "$MRM_WALLS" "$MRM_DIR/scripts/lib/walls.sh" | /usr/bin/grep -c '^>')"
awk '/^## / { m = ($0 ~ /^## Verification Matrix/) } m && /^  (eval|task|evidence|user-confirmed): / { next } m && /^stack-health:/ { next } { print }' \
  "$TMPROOT/mr-keep" > "$PMR"
s42_snap "$RMR" "$PMR"
MRM_POKER="$POKER"; POKER="$MRM_DIR/hooks/session-poker.sh"
poke "$RMR" matrix-render
POKER="$MRM_POKER"
expect_eq "MR-mut1 the mutant runs and renders (exit 0, AC-1.1 gains its evidence:)" "0|1" "$RC|$(mr_block "$PMR" AC-1.1 | /usr/bin/grep -cx '  evidence: pending')"
expect_eq "MR-mut2 …but writes no user-confirmed:, where MR-3b found one" "0" "$(mr_block "$PMR" AC-2.2 | /usr/bin/grep -c '^  user-confirmed: ' || true)"
cp "$TMPROOT/mr-keep" "$PMR"
POKE_BOUND="$MR_BOUND_WAS"

# ============================================================
section "§DISCHARGE: discharge <AC> writes the matrix row's auditor cell as the bare token CONFIRMED, nothing after it (wave-30 T14; REQ-6 AC-6.2; D9)"
# ============================================================
#
#   discharge <AC-id>   the one writer of the auditor cell: the row's fifth cell becomes `CONFIRMED`, every other byte
#                       of the plan as it was. wave-28's scratch scripts wrote `CONFIRMED <date>`, which the gate refuses
#                       past Step 5 as not the bare token; this verb is why that cannot recur.
#
# The plan transaction again. REFUSED (1), plan byte-identical: an AC the table has no row for; a call that finds the
# cell already CONFIRMED writes nothing and says so (exit 0). Not exactly one operand is the usage error (2).
# FIXTURE FIDELITY: §MATRIX-RENDER's rendered plan, the real verb, the cell read back from the plan's bytes.
DC_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
cp "$TMPROOT/mr-keep" "$PMR"
s42_snap "$RMR" "$PMR"
expect_eq "DC-0 precondition: the auditor cell of AC-1.2 reads — (the extractor, positive on the fixture)" "—" "$(mr_cell "$PMR" AC-1.2 6)"
poke "$RMR" discharge AC-1.2
expect_eq "DC-1 discharge AC-1.2 exits 0" "0" "$RC"
expect_eq "DC-1b …the auditor cell is exactly CONFIRMED" "CONFIRMED" "$(mr_cell "$PMR" AC-1.2 6)"
expect_eq "DC-1c …the row is otherwise as it was" "1" "$(/usr/bin/grep -cxF '| AC-1.2 | T0 | pending | — | CONFIRMED |' "$PMR")"
expect_eq "DC-1d …one line replaced, none added (git diff --numstat)" "1 1;" "$(s42_numstat "$RMR")"
expect_contains "DC-1e …and it says what it did" "discharge — AC-1.2: auditor CONFIRMED" "$OUT"
s42_snap "$RMR" "$PMR"
poke "$RMR" discharge AC-1.2
expect_eq "DC-2 a second discharge of the same row exits 0" "0" "$RC"
expect_true "DC-2b …and writes nothing (cmp)" cmp -s "$TMPROOT/s42-before" "$PMR"
expect_contains "DC-2c …saying the plan already reads so" "already reads so" "$OUT"
sed 's/^| AC-2\.1 | T3 | pending | — | — |$/| AC-2.1 | T3 | pending | — | CONFIRMED 2026-10-01 |/' "$PMR" > "$PMR.dc" && mv "$PMR.dc" "$PMR"
s42_snap "$RMR" "$PMR"
expect_eq "DC-3 precondition: AC-2.1 carries wave-28's dated cell" "CONFIRMED 2026-10-01" "$(mr_cell "$PMR" AC-2.1 6)"
poke "$RMR" discharge AC-2.1
expect_eq "DC-3b discharge over it writes the bare token, the date gone" "0|CONFIRMED" "$RC|$(mr_cell "$PMR" AC-2.1 6)"
s34_gate "$RMR"
expect_eq "DC-4 the plan with discharged cells is admitted by the real gate" "0" "$GATE_RC"
dc_refused() {  # <label> <want rc> <want text> <operands…>
  local label="$1" rc="$2" want="$3"; shift 3
  s42_snap "$RMR" "$PMR"; poke "$RMR" discharge "$@"
  s42_unchanged "$label" "$rc" "$PMR"
  [ -z "$want" ] || expect_contains "$label …saying why" "$want" "$OUT"
}
dc_refused "DC-5 an AC the matrix table has no row for" 1 "no row AC-9.9" AC-9.9
dc_refused "DC-5b …a prefix of a real id is not that id" 1 "no row AC-1" AC-1
dc_refused "DC-6 usage: no operand" 2 ""
dc_refused "DC-6b usage: two operands" 2 "" AC-1.1 AC-1.2
cp "$TMPROOT/mr-keep" "$PMR"
POKE_BOUND="$DC_BOUND_WAS"

# ============================================================
section "§HANDOFF: handoff rewrites ## Handoff in place from the plan and the machine: heads, open rows, live agents, last proof and date -u; the human lines are carried (wave-30 T15; REQ-7 AC-7.2; D11)"
# ============================================================
#
#   handoff      the bound plan's `## Handoff` section is rewritten in place (created before `## Not Doing` when the
#                plan has none). `written: <date -u>` is its first line; then the five machine facts: the heads of the
#                working and integration branches; the open `## Tasks` rows (active, or pending with a worktree) and
#                the last landed row; the roster's open rows with the run state the tick prints; the newest proof line;
#                then five human lines carried verbatim from the old section, or a stub when it had none.
#
# It takes the plan transaction every plan verb takes (copy, dry commit through the real gate, checksum, swap). REFUSED
# (1), the plan byte-identical: a plan with no ## Tasks or no ## SDLC State. An operand is the usage error (2).
# FIXTURE FIDELITY: §42's repository and plan writer (a plan the real gate admits) at current: 4, given the frontmatter
# branch keys over real branches with real commits, a landed line and a proof line in ## SDLC State in the shapes
# their writers use, a second active row and a pending row with a worktree, and roster rows from the production writer
# (`roster_row_fixture`); the real verb; the evidence is the plan's own bytes read back by section.
HO_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
ho_body() {  # <plan> -> the lines of ## Handoff, the heading excluded
  awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/); next } h { print }' "$1"
}
ho_written() {  # <plan> -> the first non-blank line of ## Handoff
  ho_body "$1" | awk 'NF { print; exit }'
}
ho_epoch() {  # <ISO-UTC> -> epoch seconds
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s
}
RHO="$(make_repo ho-fix)"; ( cd "$RHO" && git commit -q --allow-empty -m init )
git -C "$RHO" config user.name "Dana Fixture"
git -C "$RHO" branch -f trunk HEAD
git -C "$RHO" commit -q --allow-empty -m "work"
git -C "$RHO" branch -f wave/01-fixture HEAD
HO_INT="$(git -C "$RHO" rev-parse trunk)"
HO_WORK="$(git -C "$RHO" rev-parse wave/01-fixture)"
PHO="$(s42_plan "$RHO" 4)"
HO_LANDED="1111111111111111111111111111111111111111"
HO_LANDED2="2222222222222222222222222222222222222222"
awk -v l1="$HO_LANDED" -v l2="$HO_LANDED2" -v w="$HO_WORK" '
  NR == 1 && $0 == "---" { print; print "working-branch: wave/01-fixture"; print "integration-branch: trunk"; next }
  /^approved-by:/ { print; print "proved: kind=floor head=" w " at=2026-10-08T11:00:00Z evidence=record/old-floor.log"
                    print "proved: kind=review head=" w " at=2026-10-08T12:30:00Z evidence=record/last-review.md"; next }
  /^- T5: pending dispatch/ { print "- T4: landed " l2 " 2026-10-08T10:30:00Z"; print "- T3: landed " l1 " 2026-10-08T09:00:00Z"; print; next }
  /^\| T2 \| 4 \| build \|/ { sub(/\| implementor \|/, "| w-T2 |"); print; print "| T3 | 4 | build | the third build | — | — | 30 | REQ-1 | c.sh | .worktrees/01-T3 | abc1234 | active |"
                             print "| T6 | 4 | build | the sixth build | — | — | 30 | REQ-1 | d.sh | .worktrees/01-T6 | abc1234 | pending |"; next }
  { print }
  END { print "\n## Not Doing\n\n- nothing, in this fixture" }' "$PHO" > "$PHO.ho" && mv "$PHO.ho" "$PHO"
HO_RD="$RHO/.bionic/tmp/runs"; mkdir -p "$HO_RD"; : > "$HO_RD/w-T2-x.test.sh.log"
roster_row_fixture session="$SID" name=w-T2 agent_id=a-w-T2 subagent_type=implementor \
  run_log="$HO_RD/w-T2-x.test.sh.log" run_cmd='tests/run.sh --only x.test.sh' run_rc=0 >> "$(roster_of "$RHO")"
s42_snap "$RHO" "$PHO"
s34_gate "$RHO"
expect_eq "HO-0 precondition: the fixture plan (branch keys, landed, proof, active and pending rows, no Handoff, a Not Doing) is admitted by the real gate" "0" "$GATE_RC"
expect_eq "HO-0b …the section extractor is empty before the first run (positive control: HO-1b reads it non-empty)" "" "$(ho_body "$PHO")"
expect_eq "HO-0c …both branch heads resolve and differ (the heads the section must carry)" "1" "$([ -n "$HO_INT" ] && [ -n "$HO_WORK" ] && [ "$HO_INT" != "$HO_WORK" ] && echo 1 || echo 0)"

HO_T0="$(date -u +%s)"
poke "$RHO" handoff
HO_T1="$(date -u +%s)"
expect_eq "HO-1 handoff exits 0" "0" "$RC"
HO_BODY="$(ho_body "$PHO")"
expect_true "HO-1b …a plan with no ## Handoff gains one (the extractor now reads it non-empty)" test -n "$HO_BODY"
expect_eq "HO-1c …placed immediately before ## Not Doing" "## Not Doing" "$(awk '/^## Handoff[ \t]*$/ { f = 1; next } f && /^## / { print; exit }' "$PHO")"
HO_FIRST="$(ho_written "$PHO")"
case "$HO_FIRST" in
  'written: '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) HO_AT="${HO_FIRST#written: }" ;;
  *) HO_AT="" ;;
esac
expect_true "HO-2 the section's first line is written: <ISO-UTC> ($HO_FIRST)" test -n "$HO_AT"
HO_E="$([ -n "$HO_AT" ] && ho_epoch "$HO_AT" || echo 0)"
expect_eq "HO-2b …and it is within 60 s of the clock around the run" "1" "$([ "$HO_E" -ge $((HO_T0 - 60)) ] && [ "$HO_E" -le $((HO_T1 + 60)) ] && echo 1 || echo 0)"
expect_contains "HO-3 the working branch and its head" "wave/01-fixture @ $HO_WORK" "$HO_BODY"
expect_contains "HO-3b …the integration branch and its head" "trunk @ $HO_INT" "$HO_BODY"
expect_contains "HO-4 the active row T2 with its agent, worktree and status" "T2 · w-T2 · 01-T2 · active" "$HO_BODY"
expect_contains "HO-4b …the second active row T3" "T3 · — · .worktrees/01-T3 · active" "$HO_BODY"
expect_contains "HO-4c …a pending row that has a worktree" "T6 · — · .worktrees/01-T6 · pending" "$HO_BODY"
expect_absent "HO-4d …but not a pending row with none (T5)" "T5 ·" "$HO_BODY"
expect_absent "HO-4e …nor a landed row (T1)" "T1 ·" "$HO_BODY"
expect_contains "HO-5 the last landed row and its commit (by its time, not its place)" "T4 $HO_LANDED2 2026-10-08T10:30:00Z" "$HO_BODY"
expect_contains "HO-6 the one live agent and the state the tick prints" "w-T2 · FINISHED rc=0 run=w-T2-x.test.sh" "$HO_BODY"
expect_contains "HO-7 the last proof line (the newest, any kind)" "kind=review head=$HO_WORK at=2026-10-08T12:30:00Z" "$HO_BODY"
expect_absent "HO-7b …and not the older one" "old-floor" "$HO_BODY"
expect_contains "HO-8 a stub for each human line the old section did not have" "- resume instruction: (to fill)" "$HO_BODY"
expect_eq "HO-8b …five of them" "5" "$(printf '%s\n' "$HO_BODY" | /usr/bin/grep -c -E '^- (decisions approved this session|tried and rejected|surprises|open blockers|resume instruction):')"
expect_contains "HO-9 it says what it did" "handoff — ## Handoff rewritten at $HO_AT (3 open rows, 1 live agents); written to $(cd "${PHO%/*}" && pwd -P)/${PHO##*/}, dry-committed first." "$OUT"
s34_gate "$RHO"
expect_eq "HO-9b the plan with the section is admitted by the real gate" "0" "$GATE_RC"

# A second run carries a human line edited by hand, refreshes written:, and does not grow the section.
sed 's/^- surprises: .*/- surprises: the fixture was edited by hand\n  and it runs over two lines/' "$PHO" > "$PHO.ed" && mv "$PHO.ed" "$PHO"
sed 's/^- resume instruction: .*/- resume instruction: run T6 next/' "$PHO" > "$PHO.ed" && mv "$PHO.ed" "$PHO"
s42_snap "$RHO" "$PHO"
HO_N1="$(ho_body "$PHO" | wc -l | tr -d ' ')"
sleep 2
poke "$RHO" handoff
expect_eq "HO-10 a second handoff exits 0" "0" "$RC"
HO_BODY2="$(ho_body "$PHO")"
expect_contains "HO-10b …keeps the hand-edited line" "- surprises: the fixture was edited by hand" "$HO_BODY2"
expect_contains "HO-10c …and its continuation line" "  and it runs over two lines" "$HO_BODY2"
expect_contains "HO-10d …and the other edited line" "- resume instruction: run T6 next" "$HO_BODY2"
expect_absent "HO-10e …the stub it replaced is gone" "- resume instruction: (to fill)" "$HO_BODY2"
HO_AT2="$(ho_written "$PHO")"; HO_AT2="${HO_AT2#written: }"
expect_eq "HO-10f …written: is refreshed (it differs from the first run's)" "1" "$([ -n "$HO_AT2" ] && [ "$HO_AT2" != "$HO_AT" ] && echo 1 || echo 0)"
expect_eq "HO-10g …the section is the size it was, continuation line included (rewritten, never appended)" "$HO_N1" "$(ho_body "$PHO" | wc -l | tr -d ' ')"
expect_eq "HO-10h …one ## Handoff heading in the plan" "1" "$(/usr/bin/grep -c '^## Handoff' "$PHO")"
expect_eq "HO-10i …and the rest of the plan is as it was (outside ## Handoff, cmp of the two reads)" \
  "$(awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/) } !h { print }' "$TMPROOT/s42-before")" \
  "$(awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/) } !h { print }' "$PHO")"

# The run state words: a LOST run (its pid is gone, it wrote no end) and a row that started none.
: > "$HO_RD/w-T3-y.test.sh.log"
roster_row_fixture session="$SID" name=w-T3 agent_id=a-w-T3 subagent_type=implementor \
  run_log="$HO_RD/w-T3-y.test.sh.log" run_pid=999999 run_cmd='tests/run.sh --only y.test.sh' >> "$(roster_of "$RHO")"
roster_row_fixture session="$SID" name=w-T6 agent_id=a-w-T6 subagent_type=implementor >> "$(roster_of "$RHO")"
poke "$RHO" handoff
HO_BODY3="$(ho_body "$PHO")"
expect_eq "HO-11 three live agents: handoff exits 0" "0" "$RC"
expect_contains "HO-11b …a run whose pid is gone and wrote no end reads LOST" "w-T3 · LOST last-written=" "$HO_BODY3"
expect_contains "HO-11c …a row with no run record reads no run" "w-T6 · no run" "$HO_BODY3"
expect_contains "HO-11d …and the verb counts them" "3 live agents" "$OUT"

# Refusals: the plan stays byte-identical.
sed 's/^## Tasks$/## Rows/' "$PHO" > "$PHO.ed" && mv "$PHO.ed" "$PHO"
s42_snap "$RHO" "$PHO"
poke "$RHO" handoff
s42_unchanged "HO-12 a plan with no ## Tasks" 1 "$PHO"
expect_contains "HO-12b …saying so" "no ## Tasks" "$OUT"
sed 's/^## Rows$/## Tasks/; s/^## SDLC State$/## State/' "$PHO" > "$PHO.ed" && mv "$PHO.ed" "$PHO"
s42_snap "$RHO" "$PHO"
poke "$RHO" handoff
s42_unchanged "HO-12c a plan with no ## SDLC State" 1 "$PHO"
expect_contains "HO-12d …saying so" "no ## SDLC State" "$OUT"
sed 's/^## State$/## SDLC State/' "$PHO" > "$PHO.ed" && mv "$PHO.ed" "$PHO"
s42_snap "$RHO" "$PHO"
poke "$RHO" handoff now
expect_eq "HO-13 an operand is the usage error" "2" "$RC"
expect_true "HO-13b …and the plan is untouched (cmp)" cmp -s "$TMPROOT/s42-before" "$PHO"
POKE_BOUND="$HO_BOUND_WAS"


# ============================================================
section "§BORN: task-add --born marks a review-made row on its ledger line and holds it to fix-policy:, fix-cap: and three fixes per component (wave-30 T21; REQ-10 AC-10.1, AC-10.2; D4, Δ3)"
# ============================================================
#
#   task-add <id> … <Files> [<reads>] --born 'review S<n> <on|off>'
#                the row's `- <id>:` line under ## SDLC State ends ` born: review S<n> <reach>` (the one place the
#                review-born count reads), and its task cell ends ` · born: review`. REFUSED (1), the plan
#                byte-identical: a rating outside the plan's fix-policy: (default S1,S2-on); a row that would be
#                review-born row cap+1 (fix-cap:, default 2 at single, 10% of the rows at double); a fourth review-born
#                row on one Files path outside the record. A malformed --born is the usage error (2).
# In-diff is the orchestrator's judgment and "never re-read" the proof's: neither is the verb's.
# FIXTURE FIDELITY: §42's repository and plan writer (a plan the real gate admits) at current: 4, the three header
# fields written as Step 0 writes them; the real verb; the evidence is the plan's own bytes.
BN_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
BN_REC=".bionic/docs/record/wave-01-fixture"
bn_hdr() {  # <plan> <header line>... -> the lines written after rigor:
  local p="$1"; shift
  BN_EXTRA="$(printf '%s\n' "$@")" awk '{ print } /^rigor: / && ENVIRON["BN_EXTRA"] != "" { print ENVIRON["BN_EXTRA"] }' "$p" > "$p.bn" && mv "$p.bn" "$p"
}
bn_line() { awk -v id="$2" '/^```/ { f = !f } !f && /^## / { s = ($0 ~ /^## SDLC State/) } s && index($0, "- " id ":") == 1 { print; exit }' "$1"; }
RBN="$(make_repo bn-fix)"; ( cd "$RBN" && git commit -q --allow-empty -m init )
PBN="$(s42_plan "$RBN" 4)"
bn_hdr "$PBN" 'review-cadence: once' 'fix-policy: S1,S2-on' 'fix-cap: 2'
s42_snap "$RBN" "$PBN"
s34_gate "$RBN"
expect_eq "BN-0 precondition: the fixture plan carrying the three header fields is admitted by the real gate" "0" "$GATE_RC"
expect_eq "BN-0b …the ledger-line extractor reads an existing line (positive control)" "- T1: landed at record/T1.md" "$(bn_line "$PBN" T1)"

poke "$RBN" task-add T6 4 build 'fix the c reader' implementor '—' 30 REQ-1 'c.sh' --born 'review S2 on'
expect_eq "BN-1 task-add --born 'review S2 on' inside fix-policy: S1,S2-on exits 0" "0" "$RC"
expect_regex "BN-1b …its ledger line carries born: review S2 on after the timestamp" \
  '^- T6: pending dispatch — added by task-add at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z born: review S2 on$' "$(bn_line "$PBN" T6)"
expect_eq "BN-1c …and its task cell ends · born: review" "fix the c reader · born: review" "$(s48_row "$PBN" T6 | cut -d'|' -f4)"
expect_contains "BN-1d …and the verb says what it marked" "task-add — T6 is review-born (review S2 on): review-born rows: 1 of cap 2" "$OUT"

poke "$RBN" task-add T7 4 build 'an ordinary row' implementor '—' 30 REQ-1 'd.sh'
expect_eq "BN-2 a row added without --born exits 0" "0" "$RC"
expect_regex "BN-2b …its ledger line ends at the timestamp: no born: marker (BN-1b read one through the same extractor)" \
  '^- T7: pending dispatch — added by task-add at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(bn_line "$PBN" T7)"
expect_eq "BN-2c …and its task cell is as typed" "an ordinary row" "$(s48_row "$PBN" T7 | cut -d'|' -f4)"

s42_snap "$RBN" "$PBN"
poke "$RBN" task-add T8 4 build 'a structure fix' implementor '—' 30 REQ-1 'e.sh' --born 'review S3 off'
s42_unchanged "BN-3 AC-10.1 a --born rating outside fix-policy: (S3 off)" 1 "$PBN"
expect_contains "BN-3b …naming the rating and the set" "task-add refused — born: review S3 off is outside fix-policy: S1,S2-on" "$OUT"
poke "$RBN" task-add T8 4 build 'a reach fix' implementor '—' 30 REQ-1 'e.sh' --born 'review S2 off'
s42_unchanged "BN-3c S2 off is outside S1,S2-on too (the table's defer cell)" 1 "$PBN"
expect_contains "BN-3d …naming it" "task-add refused — born: review S2 off is outside fix-policy: S1,S2-on" "$OUT"

poke "$RBN" task-add T8 4 build 'an S1 off fix' implementor '—' 30 REQ-1 'e.sh' --born 'review S1 off'
expect_eq "BN-4 S1 off is inside S1,S2-on (S1 names both reaches): exits 0, review-born row 2 of cap 2" "0" "$RC"
expect_regex "BN-4b …marked" '^- T8: pending dispatch — added by task-add at [0-9TZ:-]+ born: review S1 off$' "$(bn_line "$PBN" T8)"

s42_snap "$RBN" "$PBN"
poke "$RBN" task-add T9 4 build 'one fix too many' implementor '—' 30 REQ-1 'f.sh' --born 'review S1 on'
s42_unchanged "BN-5 AC-10.2 the third review-born row under fix-cap: 2" 1 "$PBN"
expect_contains "BN-5b …naming the count and the cap" "task-add refused — review-born rows: 2 of cap 2; this finding goes to the review findings disposition (AC-10.3)" "$OUT"

for bn_bad in 'review S5 on' 'review S2 maybe' 'S2 on' 'review S2-on'; do
  poke "$RBN" task-add T9 4 build 'a bad rating' implementor '—' 30 REQ-1 'f.sh' --born "$bn_bad"
  s42_unchanged "BN-6 --born '$bn_bad' is the usage error" 2 "$PBN"
done
poke "$RBN" task-add T9 4 build 'no rating' implementor '—' 30 REQ-1 'f.sh' --born
s42_unchanged "BN-6b --born with no value is the usage error" 2 "$PBN"

# THE FOURTH FIX ON ONE COMPONENT (AC-10.2). A component is a Files path outside the record; three review-born rows
# already carrying it refuse a fourth, naming the path and the three. A record path the rows share is not one.
RBF="$(make_repo bn-four)"; ( cd "$RBF" && git commit -q --allow-empty -m init )
PBF="$(s42_plan "$RBF" 4)"
bn_hdr "$PBF" 'fix-policy: S1,S2' 'fix-cap: 9'
s42_snap "$RBF" "$PBF"
for bn_id in T6 T7 T8; do
  poke "$RBF" task-add "$bn_id" 4 build "fix $bn_id" implementor '—' 30 REQ-1 "lib/x.sh, $BN_REC/assumptions.md" --born 'review S2 off'
  expect_eq "BN-7 fix $bn_id on lib/x.sh (fix-policy: S1,S2 covers S2 off) exits 0" "0" "$RC"
done
s42_snap "$RBF" "$PBF"
poke "$RBF" task-add T9 4 build 'the fourth fix' implementor '—' 30 REQ-1 "c.sh, lib/x.sh" --born 'review S1 on'
s42_unchanged "BN-8 AC-10.2 a fourth review-born row on lib/x.sh" 1 "$PBF"
expect_contains "BN-8b …naming the path and the three rows" \
  "task-add refused — a fourth fix on lib/x.sh: T6, T7, T8 already fix it; stop the run (AC-10.2)" "$OUT"
poke "$RBF" task-add T9 4 build 'a fix elsewhere' implementor '—' 30 REQ-1 "lib/y.sh, $BN_REC/assumptions.md" --born 'review S1 on'
expect_eq "BN-8c …while a fourth review-born row sharing only the record path with the three exits 0" "0" "$RC"

# THE DEFAULTS: a plan with rigor: double and none of the three fields reads S1,S2-on and 10% of its rows (3 → 1).
RBD="$(make_repo bn-default)"; ( cd "$RBD" && git commit -q --allow-empty -m init )
PBD="$(s42_plan "$RBD" 4)"
expect_eq "BN-9 precondition: the default fixture carries rigor: double and none of the three fields" "1|0" \
  "$(/usr/bin/grep -c '^rigor: double$' "$PBD")|$(/usr/bin/grep -cE '^(review-cadence|fix-policy|fix-cap):' "$PBD")"
s42_snap "$RBD" "$PBD"
poke "$RBD" task-add T6 4 build 'an S2 off fix' implementor '—' 30 REQ-1 'c.sh' --born 'review S2 off'
s42_unchanged "BN-9b with no fix-policy: the default S1,S2-on refuses S2 off" 1 "$PBD"
expect_contains "BN-9c …naming the default set" "task-add refused — born: review S2 off is outside fix-policy: S1,S2-on" "$OUT"
poke "$RBD" task-add T6 4 build 'an S1 fix' implementor '—' 30 REQ-1 'c.sh' --born 'review S1 on'
expect_eq "BN-9d …and admits S1 on, row 1 of the default cap" "0" "$RC"
s42_snap "$RBD" "$PBD"
poke "$RBD" task-add T7 4 build 'an S2 fix' implementor '—' 30 REQ-1 'd.sh' --born 'review S2 on'
s42_unchanged "BN-9e with no fix-cap: double renders 10% of 3 rows as 1, so a second review-born row" 1 "$PBD"
expect_contains "BN-9f …naming 1 of cap 1" "review-born rows: 1 of cap 1" "$OUT"
POKE_BOUND="$BN_BOUND_WAS"

# ============================================================
section "§REGRESSION-SET: regression <yes|no> '<reply>' writes the plan's regression: key and, against the scale default, one attributed regression-override: line (wave-31 T27; REQ-12 AC-12.1, AC-12.2; D4)"
# ============================================================
#
# fails-when: the verb writes no key, an override against the scale default is unattributed, a
# value at the default leaves an override behind, a second call doubles the override line, or a
# bad value, a missing reply or an unbound session changes the plan.
#
# THE SCALE DEFAULTS are task no, wave yes, epic no (REQ-12). The fixture is s42_plan's: a wave
# plan, so `no` is against the default and `yes` is the default. The override's grammar is
# budget-override:'s, `regression-override: <git user.name> <date> derived=<default> chosen=<v>`
# (§BUDGET-USER, session-poker-3 65n3), and like it the one line is rewritten, never doubled.
RRS="$(make_repo rs-set)"; ( cd "$RRS" && git commit -q --allow-empty -m init )
git -C "$RRS" config user.name "Dana Fixture"
PRS="$(s42_plan "$RRS" 4)"
rs_fm() {  # <plan> <key> -> the frontmatter lines of that key, in order
  awk -v k="$2" 'NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f && index($0, k ":") == 1' "$1"
}
expect_eq "RS-0 precondition: the fixture is a wave plan with no regression: key and no override" "1|0|0" \
  "$(/usr/bin/grep -c '^scale: wave$' "$PRS")|$(rs_fm "$PRS" regression | wc -l | tr -d ' ')|$(rs_fm "$PRS" regression-override | wc -l | tr -d ' ')"
s42_snap "$RRS" "$PRS"
poke "$RRS" regression no 'CI runs it on merge, not this run'
expect_eq "RS-1 regression no on a wave plan exits 0" "0" "$RC"
expect_eq "RS-1b …writing regression: no into the frontmatter" "regression: no" "$(rs_fm "$PRS" regression)"
expect_regex "RS-1c …and, against the wave default yes, one attributed override line" \
  '^regression-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} derived=yes chosen=no$' "$(rs_fm "$PRS" regression-override)"
expect_contains "RS-1d …saying what it wrote" "regression — regression: no" "$OUT"
s34_gate "$RRS"
expect_eq "RS-1e …and the commit gate admits the plan" "0" "$GATE_RC"
s42_snap "$RRS" "$PRS"
poke "$RRS" regression yes 'run it here after all'
expect_eq "RS-2 regression yes on the same plan exits 0" "0" "$RC"
expect_eq "RS-2b …the key reads yes, rewritten in place: one regression: line" "regression: yes" "$(rs_fm "$PRS" regression)"
expect_eq "RS-2c …and the override is gone: yes is the wave default (the key read above is the positive)" "0" \
  "$(rs_fm "$PRS" regression-override | wc -l | tr -d ' ')"
s42_snap "$RRS" "$PRS"
poke "$RRS" regression yes 'again'
expect_eq "RS-2d asked again, the plan already reads so: exit 0" "0" "$RC"
expect_contains "RS-2e …saying so" "already reads so" "$OUT"
expect_true "RS-2f …and the plan is byte-identical (cmp)" cmp -s "$TMPROOT/s42-before" "$PRS"

# THE ONE LINE IS REWRITTEN, NEVER DOUBLED: a stale override (another person, another date) and a
# key reading the other value are both replaced by the one pair.
awk 'NR == 1 { print; print "regression: yes"; print "regression-override: Old Name 2020-01-01 derived=yes chosen=no"; next } { print }' \
  "$PRS" > "$PRS.tmp" && mv "$PRS.tmp" "$PRS"
expect_eq "RS-3 precondition: the plan carries one key and one stale override" "1|1" \
  "$(rs_fm "$PRS" regression | wc -l | tr -d ' ')|$(rs_fm "$PRS" regression-override | wc -l | tr -d ' ')"
s42_snap "$RRS" "$PRS"
poke "$RRS" regression no 'CI again'
expect_eq "RS-3b regression no over a stale override exits 0" "0" "$RC"
expect_eq "RS-3c …one regression: line, reading no" "regression: no" "$(rs_fm "$PRS" regression)"
expect_regex "RS-3d …and one override line, the new one: rewritten, not added" \
  '^regression-override: Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2} derived=yes chosen=no$' "$(rs_fm "$PRS" regression-override)"
expect_eq "RS-3e …so the change is the pair rewritten: two lines out, two in, none added" "2 2;" "$(s42_numstat "$RRS")"

# REFUSALS, budget's: a value outside yes|no (1), no reply (2), no bound plan (1); the plan unchanged.
s42_snap "$RRS" "$PRS"
poke "$RRS" regression maybe 'not sure'
s42_unchanged "RS-4 a value outside yes|no" 1 "$PRS"
expect_contains "RS-4b …naming the two values" "is not yes or no" "$OUT"
poke "$RRS" regression NO 'shouting'
s42_unchanged "RS-4c a value in another case" 1 "$PRS"
poke "$RRS" regression no
s42_unchanged "RS-4d no reply" 2 "$PRS"
poke "$RRS" regression no '   '
s42_unchanged "RS-4e a reply of spaces" 2 "$PRS"
poke "$RRS" regression no 'two
lines'
s42_unchanged "RS-4f a reply with a line break" 1 "$PRS"
RRS2="$(make_repo rs-unbound)"; ( cd "$RRS2" && git commit -q --allow-empty -m init )
poke "$RRS2" regression no 'CI runs it'
expect_eq "RS-4g a session with no bound plan is refused (exit 1)" "1" "$RC"
expect_contains "RS-4h …saying it has no bound open run" "has no bound open run" "$OUT"

finish
