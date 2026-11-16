#!/bin/bash
# Tests for hooks/session-poker.sh — shard 4 of 4: §SEV to the end.
#
# THE SUITE IS FOUR SHARDS. Its governing design, hermetic posture and clock discipline are written once, in
# tests/session-poker.test.sh's header; the sandbox, the pins and the shared fixture builders are
# tests/session-poker.prelude.sh, sourced below after the framework and the POKER seam.
#
# SPLIT WHERE NO FIXTURE CROSSES. §SEV builds the repository eight later sections read (§CHECK-GONE, §MOVE,
# §REPORT-RTL, §REPORT-KEY, §PASS-KEY, §PASS-MOVED, §MOVE-PASTED, §FINAL-RATING); the sections between export the
# config and home directories the next run under, so this shard keeps them all, in order.
#
# Usage: bash tests/session-poker-4.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

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
# With `severity` in the reader row's `pushed=`, `proof-add review <record> --question <q> --reader <name>` requires
# `findings: <n>`, that many `finding: <n> <S1-S4> <on|off> <path>:<line>|- <title>` lines, and a `<path>:<line>` with
# a `shown: <n> <command>` line for each finding the table sends to fix. A READER'S RATING IS FINAL: an `unsure:` line
# is read by nothing. The result is derived (a fix gives fail, any other finding flag, none pass); a differing
# `result:` or a `priority:` the table does not give is refused. Registration appends one deferral event per deferred
# finding to the run's log, and no `check:` line. A reader with no `severity` push registers as 1.12.0 did.
#
# FIXTURE FIDELITY. §56's shape: a bound plan, its working branch in a linked worktree, real commits, roster rows from
# the production writer with `questions=` and `pushed=` appended, read off the line by key.
SEV_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
SEV_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
RSEV="$(make_repo sev-fact)"; ( cd "$RSEV" && git commit -q --allow-empty -m init )
git -C "$RSEV" config user.name "Dana Fixture"
SEV_B="$(git -C "$RSEV" rev-parse HEAD)"
PSEV="$(s42_plan "$RSEV" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${SEV_B:0:8}
  branch: wave/01-fixture")"
s42_builds_landed "$PSEV"
git -C "$RSEV" worktree add -q -b wave/01-fixture "$RSEV/.worktrees/01-fixture" "$SEV_B" >/dev/null 2>&1
SEV_WT="$RSEV/.worktrees/01-fixture"
SEV_C1="$(s57_commit "$SEV_WT" lib/a.sh C1)"
SEV_DIR="$RSEV/.bionic/docs/record/wave-01-fixture"
SEV_RECS="r-ok r-nosev r-noreach r-s5 r-maybe r-count r-none r-twice r-where r-pri-bad r-pri-ok
t-S1-on t-S1-off t-S2-on t-S2-off t-S3-on t-S3-off t-S4-on t-S4-off
d-fix-flag d-defer-fail d-none-flag d-none-pass sh-dash sh-noshown sh-unsure sh-defer-unsure c-fix c-later"
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
sev_lines() { bash -c '. "$1"; proof_findings_owed "$2"' _ "$SEV_LIB" "$PSEV" 2>/dev/null; }  # the run's deferrals, rated
expect_regex "SEV-0 precondition: the working branch's head is C1, a 40-hex commit" '^[0-9a-f]{40}$' "$SEV_C1"
expect_eq "SEV-0b precondition: the reader's row carries the pushed key, read by key" "checks-adversarial,severity" \
  "$(/usr/bin/grep -F '|name=sev-crit|' "$SEV_RS" | tr '|' '\n' | sed -n 's/^pushed=//p')"
s34_gate "$RSEV"
expect_eq "SEV-0c precondition: the fixture's run at 15 is admitted by the real commit gate" "0" "$GATE_RC"
[ "$GATE_RC" = 0 ] || printf '      the gate said: %s\n' "$GATE_ERR" | head -6

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
# The copy hands the key to `roster_row`, which writes it.
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
  sevd="$(sev_lines | /usr/bin/grep "^record/wave-01-fixture/t-$s-$r.md#1 ")"
  case "$p" in
    defer) expect_eq "SEV-table …$s $r: one deferral, read back whole" \
             "record/wave-01-fixture/t-$s-$r.md#1 $s $r defer \"the $s $r cell\"" "$sevd" ;;
    *)     expect_eq "SEV-table …$s $r ($p): no deferral (beside the S2 off and S3 on rows that append one)" "" "$sevd" ;;
  esac
done
sev_rec r-pri-bad flag "findings: 1" "finding: 1 S2 off - written as fix" "priority: 1 fix"
s42_snap "$RSEV" "$PSEV"; sev_add r-pri-bad
s42_unchanged "SEV-table3 §FACT-table AC-8.3 a record that writes a priority the table does not give (S2 off as fix)" 1 "$PSEV"
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
sev_st() {  # <file> <result> <answer for the first id> <line>... -> a structure reading, every other check PASS
  local f="$SEV_DIR/$1.md" r="$2" a="$3" i n=0 l; shift 3
  { printf '# reading\n\nreviewed: %s..%s\nquestion: structure\nresult: %s\nscope: piece\n' "${SEV_B:0:10}" "$SEV_C1" "$r"
    for i in $SEV_IDS; do n=$((n + 1)); if [ "$n" = 1 ]; then printf 'check: %s %s the reason\n' "$i" "$a"; else printf 'check: %s PASS nothing\n' "$i"; fi; done
    for l in "$@"; do printf '%s\n' "$l"; done; } > "$f"
}
sev_stread() { bash -c '. "$1"; proof_reading "$2" structure "$3" 1; echo " rc=$?"' _ "$SEV_LIB" "$SEV_DIR/$1.md" "$SEV_CK" 2>/dev/null; }
sev_st st-agree fail FAIL "findings: 1" "finding: 1 S2 on lib/a.sh:5 the core path is wrong" "shown: 1 bash lib/a.sh"
expect_regex "SEV-st1 a FAIL check beside a finding to fix agrees: the reading reads as fail" "^fail piece [0-9a-f]+ rc=0$" "$(sev_stread st-agree)"
sev_st st-failcheck fail FAIL "findings: 1" "finding: 1 S3 on - only a side path"
SEV_OUT="$(sev_stread st-failcheck)"
expect_eq "SEV-st2b …in one line" "1" "$(printf '%s\n' "$SEV_OUT" | wc -l | tr -d ' ')"
sev_st st-fixflag fail FLAG "findings: 1" "finding: 1 S1 off lib/a.sh:6 data lost" "shown: 1 bash lib/a.sh --lose"
sev_st st-flagagree flag FLAG "findings: 1" "finding: 1 S3 on - only a side path"
expect_regex "SEV-st4 control: a FLAG check beside a deferral reads as flag" "^flag piece [0-9a-f]+ rc=0$" "$(sev_stread st-flagagree)"

# ---------- §FACT-shown (AC-8.6, the record half): a fix is shown; an unsure: line owes nothing (T32) ----------
sev_rec sh-dash fail "findings: 1" "finding: 1 S2 on - no place named" "shown: 1 bash lib/a.sh"
sev_rec sh-noshown fail "findings: 1" "finding: 1 S2 on lib/a.sh:4 no command"
for f in sh-dash sh-noshown; do
  s42_snap "$RSEV" "$PSEV"; sev_add "$f"
  s42_unchanged "SEV-shown §FACT-shown AC-8.6 a finding to fix with no file, line and command ($f)" 1 "$PSEV"
done
# AN unsure: LINE SHOWS NOTHING (wave-31 T32; D6, AC-6.3): a finding to fix it stood in for is shown nowhere.
sev_rec sh-unsure fail "findings: 1" "finding: 1 S1 off - cannot run it here" "unsure: 1 the race needs two machines"
s42_snap "$RSEV" "$PSEV"; sev_add sh-unsure
s42_unchanged "SEV-shown2 §FINAL-RATING a finding to fix carrying only an unsure: line (sh-unsure)" 1 "$PSEV"
expect_contains "SEV-shown3 …is refused as a fix shown nowhere, naming the line to write" "write its <path>:<line> and shown: 1 <command>" "$OUT"
expect_absent "SEV-shown3b …and the refusal offers no unsure: line" "unsure:" "$OUT"
sev_rec sh-defer-unsure flag "findings: 2" 'finding: 1 S3 on - a "quoted" word wrong' "unsure: 1 which platforms" "finding: 2 S4 on - a typo"
sev_add sh-defer-unsure
expect_eq "SEV-shown4 a finding the table defers, beside an unsure: line, appends its deferral alone; a note appends none" \
  "record/wave-01-fixture/sh-defer-unsure.md#1 S3 on defer \"a 'quoted' word wrong\"" \
  "$(sev_lines | /usr/bin/grep -F 'record/wave-01-fixture/sh-defer-unsure.md#' | paste -sd'|' -)"
expect_eq "SEV-shown6 …and no check: line names it" "0" "$(/usr/bin/grep -c '^check: record/wave-01-fixture/sh-defer-unsure.md#' "$PSEV")"

# ---------- the priority a record never states: library, release-check and the tick ----------
SEV_OWED="$(bash -c '. "$1"; proof_findings_owed "$2"' _ "$SEV_LIB" "$PSEV" 2>/dev/null)"
expect_contains "SEV-owed proof_findings_owed prints a deferral with the table's priority" \
  'record/wave-01-fixture/t-S2-off.md#1 S2 off defer "the S2 off cell"' "$SEV_OWED"
# The rating is final (wave-31 T32): the finding beside the unsure: line is owed at the table's priority.
expect_contains "SEV-owed2 …and the deferral beside an unsure: line at the table's priority, never as a check" \
  "record/wave-01-fixture/sh-defer-unsure.md#1 S3 on defer \"a 'quoted' word wrong\"" "$SEV_OWED"
expect_eq "SEV-owed3 …each finding once" "1" \
  "$(printf '%s\n' "$SEV_OWED" | /usr/bin/grep -c 'sh-defer-unsure.md#1 ')"

# ---------- §FACT-old (AC-8.8): a reader not pushed the scale registers as 1.12.0 did ----------
sev_rec o-fail fail
sev_add o-fail old-crit
expect_eq "SEV-old §FACT-old AC-8.8 a record with a result and no findings, from a reader with no pushed= key, registers (exit 0)" "0" "$RC"
expect_regex "SEV-old2 …with its result as written" "evidence=record/wave-01-fixture/o-fail.md question=adversarial reader=old-crit result=fail scope=piece$" "$(sev_last)"
SEV_N="$(sev_lines | wc -l | tr -d ' ')"
sev_rec o-findings fail "findings: 1" "finding: 1 S4 off - finding lines the old reading ignores"
sev_add o-findings old-crit
expect_eq "SEV-old3 …finding lines in such a record are ignored: it registers (exit 0)" "0" "$RC"
expect_regex "SEV-old4 …with result: fail as written, though S4 off alone would derive flag" "o-findings.md .* result=fail scope=piece$" "$(sev_last)"
expect_eq "SEV-old5 …and appends no deferral (the count stands at $SEV_N, beside the deferrals SEV-table appended)" "$SEV_N" "$(sev_lines | wc -l | tr -d ' ')"
sev_rec o-nopush fail
sev_add o-nopush nosev-crit
expect_eq "SEV-old6 a reader whose pushed= names other files, not severity, registers the old form too (exit 0)" "0" "$RC"

# ---------- release-check prints the derived priority ----------
printf '#!/bin/bash\necho "scan: entries=0 hits=0"\nexit 0\n' > "$TMPROOT/sev-check.sh"
cp "$RSEV/.bionic/config.yaml" "$TMPROOT/sev-config" 2>/dev/null || : > "$TMPROOT/sev-config"
printf 'release-check: bash %s\n' "$TMPROOT/sev-check.sh" >> "$RSEV/.bionic/config.yaml"
poke "$RSEV" release-check
expect_eq "SEV-rc release-check over a plan with rated findings exits 0" "0" "$RC"
cp "$TMPROOT/sev-config" "$RSEV/.bionic/config.yaml"

# ---------- the tick prints the derived priority ----------
RSEVT="$(make_repo sev-tick)"; new_roster "$RSEVT"
PSEVT="$(s47_plan "$RSEVT" 2 \
  "| T1 | 4 | build | ready | implementor | — | 30 | REQ-x | payload/x.sh | pending | |")"
printf 'run/v1|ev=finding|ref=record/w/rev.md#2|severity=S2|reach=off|to=deferred|title=a side path|at=2026-10-04T00:30:00Z\n' >> "$(plan_fixture_log "$PSEVT")"
poke_pressure "$RSEVT" 8192 1.0 tick
expect_contains "SEV-tick the tick fills the ready row (the path it prints FINDING on)" "poker: FILL T1" "$OUT"

# ---------- §CUR8-sev (AC-8.5): the step into integration follows the derived verdict ----------
# The plan moves to current: 7 and every other fact it owes is planted at C1 by the production
# placer (§61's way); the adversarial piece fact is then a reading registered through the verb, so
# what the judge reads is the result the findings derived.
sev_put() { sp_fact "$PSEV" "$1"; }
sev_fact() {  # <kind> <question> <scope>
  sev_put "$(bash -c '. "$1" && proof_line "$2" "$3" 2026-10-06T12:00:00Z "$4" "$5" w-read pass "$6"' \
    _ "$SEV_LIB" "$1" "$SEV_C1" "record/wave-01-fixture/planted-$2-$3.md" "$2" "$3")"
}
sev_cur() { bash -c '. "$1" && proof_step_event "$2" "$3"' _ "$SEV_LIB" "$PSEV" "$1"; }
# The advance to 8 asks a ruling of every matrix row; the fixture's rows carry none, so the steps that expect it admitted
# rule them first, by the auditor's CONFIRMED in each cell (a waiver or an attributed confirmation also rule a row).
sp4_rule_rows() {  # <plan> [<head>] -> every criterion confirmed by the auditor: at 15 its evidence review passing at <head>, else each matrix cell
  if /usr/bin/grep -q '^canonical_sdlc_version: 15$' "$1"; then
    bash -c '. "$1" && proof_event "$2" kind=review "head=$3" evidence=record/wave-01-fixture/audit.md question=evidence reader=w-aud result=pass scope=piece' \
      _ "$S46_LIB" "$1" "$2"; return
  fi
  sed -E '/^\| AC-/ s/[|][^|]*[|]$/| CONFIRMED |/' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
sev_put "$(bash -c '. "$1" && proof_line regression "$2" 2026-10-06T12:00:00Z record/wave-01-fixture/floor.log' _ "$SEV_LIB" "$SEV_C1")"
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
# ---------- §ASK-WAIVE: a failing question is the person's to waive, and opens one item ----------
# A failing reading's registration opens `waive:<question>`, the key the waive verb closes. A refusal keeps its one open
# round and a second opens nothing; the waive verb closes it; a refusal after the waiver is taken back opens a new round;
# once a passing reading holds the question, current 8 closes what is left. The sections above left closed rounds.
sev_owed() { ( cd "$RSEV" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && owed_list' _ "${SEV_LIB%/*}" ) 2>/dev/null; }
sev_store() { ( cd "$RSEV" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && owed_lines' _ "${SEV_LIB%/*}" ) 2>/dev/null; }
SEV_WKEYS="$(sev_owed | cut -f1)"
expect_contains "AW-1 T35 AC-2.2 the refusal on a failing question opens waive:<question>, the waive verb's key" \
  "waive:adversarial" "$SEV_WKEYS"
expect_absent "AW-1a …and none for the questions that hold (same reader)" "waive:evidence" "$SEV_WKEYS"
expect_contains "AW-1b …the item the first failing reading's registration opened, which the refusal keeps" \
  "proof-add: the adversarial review record/wave-01-fixture/" "$(sev_owed | awk -F'\t' '$1 == "waive:adversarial" { print $4 }')"
SEV_AW="$(sev_store | /usr/bin/grep "|key=waive:adversarial|")"; poke "$RSEV" current 8
expect_eq "AW-2 a second refusal on the same failing question opens nothing new: one open round, the key's rounds unchanged" "1|1|same" \
  "$RC|$(sev_store | /usr/bin/grep -c '|key=waive:adversarial|state=open|')|$([ "$(sev_store | /usr/bin/grep '|key=waive:adversarial|')" = "$SEV_AW" ] && echo same)"
said_as typed "$RSEV" 'I waive the adversarial reading for now'; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RSEV" waive adversarial 'I waive the adversarial reading for now'
expect_eq "AW-3 the waive verb records the user's reply (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "AW-3a …and closes the item it answers" "|key=waive:adversarial|state=closed|by=waive|" "$(sev_store)"
# The waiver taken back where it stands: no verb takes one back, so its event comes out of the run's log by hand.
AW_LOG="$(bash -c '. "$1/reader.sh" && reader_log "$2"' _ "${SEV_LIB%/*}" "$PSEV")"
/usr/bin/grep -v '^run/v1|ev=waiver|question=adversarial|' "$AW_LOG" > "$TMPROOT/aw-log"; cat "$TMPROOT/aw-log" > "$AW_LOG"
# The opener doctored to open nothing, in a plugin copy whose loader finds its own library, turns AW-4 red.
AWM="$TMPROOT/aw-mutant"; mkdir -p "$AWM/hooks"
cp -R "$BIONIC_HOOKS_DIR/." "$AWM/hooks/"; cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$AWM/scripts"
awk 'index($0, "owed_open \"waive:$q\"") { sub(/owed_open /, ": "); n++ } { print } END { print n + 0 > "/dev/stderr" }' \
  "$BIONIC_HOOKS_DIR/poker/judge.sh" > "$AWM/hooks/poker/judge.sh" 2> "$TMPROOT/aw-mutant.n"   # the opener is the judge's
expect_eq "AW-M the doctored opener is one line, and the copy parses and differs" "1 0 differs" \
  "$(cat "$TMPROOT/aw-mutant.n") $(bash -n "$AWM/hooks/poker/judge.sh" >/dev/null 2>&1; echo "$?") $(cmp -s "$AWM/hooks/poker/judge.sh" "$BIONIC_HOOKS_DIR/poker/judge.sh" && echo same || echo differs)"
AW_POKER_KEEP="$POKER"; POKER="$AWM/hooks/session-poker.sh"
poke "$RSEV" current 8
POKER="$AW_POKER_KEEP"
expect_eq "AW-Ma AC-4.5 the mutant still refuses current 8 (exit 1), and AW-4 goes red: no item opens" "1|" \
  "$RC|$(sev_owed | cut -f1 | /usr/bin/grep '^waive:')"
poke "$RSEV" current 8
expect_eq "AW-4 the waiver taken back out of the run's log, the refusal is a new need: the item opens again" "1|waive:adversarial" \
  "$RC|$(sev_owed | cut -f1 | /usr/bin/grep '^waive:')"
sev_cur 4
sev_rec c-later flag "findings: 2" "finding: 1 S2 off - a side path still wrong" "finding: 2 S4 off - a comment misstates it"
sev_add c-later
expect_eq "SEV-cur3 a later pass over the fix, holding only a deferral and a note, registers as flag (exit 0)" "0|flag" \
  "$RC|$(sev_last | sed -n 's/.* result=\([a-z]*\) .*/\1/p')"
sev_cur 7
sp4_rule_rows "$PSEV" "$SEV_C1"
poke "$RSEV" current 8
expect_eq "SEV-cur4 §CUR8-sev …and current 8 is admitted on it: deferrals and notes do not hold the step" "0|n=8" \
  "$RC|$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$PSEV" step | head -1)"
expect_contains "AW-5 T35 once the question holds again, current 8 closes its waiver item" \
  "|key=waive:adversarial|state=closed|by=no longer failing|" "$(sev_store)"
expect_eq "AW-5a …and no waiver item is left open" "" "$(sev_owed | cut -f1 | /usr/bin/grep '^waive:')"
# ---------- §ASK-RULING: a ruling shown closes its ruling: item wherever the run keeps it ----------
# The tick's backstop opens `ruling:<id>` for a ruling a writer ended unread; showing the ruling closes it at once.
# This fixture's session is bound to a plan, so the item lives in the run's register, not in the session's file; the
# positive read of the open item comes first, through the extractor that then reads its absence.
SEV_ROSTER="$(roster_of "$RSEV" "$SID")"
SEV_RL="${S46_LIB%/*}"
SEV_RID="$( ( . "$SEV_RL/roster.sh" && { [ -f "$SEV_ROSTER" ] || roster_header > "$SEV_ROSTER"; } && ruling_record "$SEV_ROSTER" w-ruled 'hold the line' ) )"
( cd "$RSEV" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && owed_open "ruling:$2" "ruling unread: $2" "poker: ruling unread"' _ "$SEV_RL" "$SEV_RID" ) >/dev/null 2>&1
expect_contains "RPC-1 the unread ruling's item is open on the session's ledger, in the run's register" "ruling:$SEV_RID" "$(sev_owed | cut -f1)"
( . "$SEV_RL/roster.sh" && ruling_stamp "$SEV_ROSTER" "$SEV_RID" w-ruled shown=1 by=ack ) >/dev/null 2>&1
expect_eq "RPC-2 …showing the ruling closes it at once: nothing left open for it" "" "$(sev_owed | cut -f1 | /usr/bin/grep "^ruling:$SEV_RID")"
expect_contains "RPC-3 …and the register keeps the item, closed" "|key=ruling:$SEV_RID|state=closed|by=ruling read|" "$(sev_store)"
POKE_BOUND="$SEV_BOUND_WAS"

# ============================================================
section "§DEBT-PARSE §DEBT-LEDGER §DEBT-ADVISORY (the verb half): a debt: line is a flag-class finding the reader names by kind and concept, and the run's ledger holds one line per item (wave-30 T22; REQ-11 AC-11.1, AC-11.2, AC-11.3; D2, P2; A-orch-8)"
# ============================================================
#
# severity.md writes `debt: <kind> <concept> <path>:<line>[, <path>:<line>…]` flush left beside the `finding:` lines,
# uncounted in `findings:`. lib/proof.sh `proof_findings` reads it as `debt<TAB><kind><TAB><concept><TAB><sites>
# <TAB>burn`, flag-class; one carrying a severity or reach word, or a kind outside the debt table, is refused, naming
# the line. `session-poker.sh debt` appends each debt to the run's log; `debt list` prints them as the reader holds them.
#
# FIXTURE FIDELITY. The parser rows run §SEV's library (`SEV_LIB`) on the shipped structure checks file (`SEV_CK`); the
# ledger rows run the real verb in §SEV's bound repository and read the log it wrote.
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
DBT_LOG="$RSEV/.bionic/docs/record/$DBT_SLUG/run.log"
sev_rec dbt-rec flag "findings: 1" "finding: 1 S3 off lib/a.sh:3 a message misnames the flag" \
  "debt: one-case-abstraction log_shim lib/a.sh:4" "debt: duplicate tree_count lib/b.sh:2, lib/c.sh:5"
rm -f "$DBT_LOG"
poke "$RSEV" debt add record/wave-01-fixture/dbt-rec.md
expect_eq "DEBT-L1 §DEBT-LEDGER debt add over the session's bound run exits 0" "0" "$RC"
expect_contains "DEBT-L1c …naming each item it added" "poker: debt add — log_shim one-case-abstraction lib/a.sh:4" "$OUT"
# AC-11.2's fails-when: a debt finding in the record with no ledger line.
DBT_WANT="$(dbt_rows dbt-rec | awk -F'\t' '$1 == "debt" { print $3 " | " $2 " | " $4 }')"
expect_nonempty "DEBT-L2 precondition: the record's debt rows read back" "$DBT_WANT"
poke "$RSEV" debt add record/wave-01-fixture/dbt-rec.md "$PSEV"
expect_eq "DEBT-L3 a second add of the same record, the plan named, exits 0" "0" "$RC"
cp "$DBT_LOG" "$TMPROOT/dbt-before"
poke "$RSEV" debt add record/wave-01-fixture/dbt-sev.md "$PSEV"
expect_eq "DEBT-L4 debt add on a record whose debt line carries a severity is refused (exit 1)" "1" "$RC"
expect_true "DEBT-L4c …and the log is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
poke "$RSEV" debt add record/wave-01-fixture/r-ok.md "$PSEV"
expect_eq "DEBT-L5 debt add on a reading with no debt line exits 0" "0" "$RC"
expect_true "DEBT-L5c …the log byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
poke "$RSEV" debt touched tree_count "$PSEV"
expect_eq "DEBT-L6 debt touched exits 0 and prints the item with its new count" \
  "0|poker: debt touched — tree_count duplicate touches 1" "$RC|$OUT"
cp "$DBT_LOG" "$TMPROOT/dbt-before"
poke "$RSEV" debt touched no_such_concept "$PSEV"
expect_eq "DEBT-L6c debt touched on a concept the ledger does not hold is refused (exit 1)" "1" "$RC"
expect_true "DEBT-L6d …the log byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
# The dispatch wall's one call names every concept a brief touches, blank-separated in one operand.
poke "$RSEV" debt touched "tree_count no_such_concept" "$PSEV"
expect_eq "DEBT-L6e several concepts, one the ledger does not hold: refused (exit 1) naming that one alone, the log byte-identical" \
  "1|names no_such_concept;|same" "$RC|$(printf '%s' "$OUT" | /usr/bin/grep -o 'names [a-z_ ]*;')|$(cmp -s "$TMPROOT/dbt-before" "$DBT_LOG" && echo same)"
poke "$RSEV" debt touched "tree_count log_shim" "$PSEV"
expect_eq "DEBT-L6f several concepts in one call: each item touched once, its new count printed" \
  "0|poker: debt touched — log_shim one-case-abstraction touches 1|poker: debt touched — tree_count duplicate touches 2" \
  "$RC|$(printf '%s\n' "$OUT" | sort | paste -sd'|' -)"
poke "$RSEV" debt burn log_shim T9 "$PSEV"
expect_eq "DEBT-L7 debt burn exits 0 and prints the item burned" "0|poker: debt burn — log_shim one-case-abstraction burned T9" "$RC|$OUT"
cp "$DBT_LOG" "$TMPROOT/dbt-before"
poke "$RSEV" debt burn log_shim T10 "$PSEV"
expect_eq "DEBT-L7c a second burn of a burned item is refused (exit 1), the ledger unchanged" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/dbt-before" "$DBT_LOG" && echo same)"
poke "$RSEV" debt touched log_shim "$PSEV"
expect_eq "DEBT-L7d …and a burned item is touched no more (exit 1, unchanged)" "1|same" \
  "$RC|$(cmp -s "$TMPROOT/dbt-before" "$DBT_LOG" && echo same)"
poke "$RSEV" debt list "$PSEV"
expect_eq "DEBT-L8 debt list prints each debt as the reader holds it, the touch and the burn read from the log" \
  '0|tree_count duplicate "lib/b.sh:2, lib/c.sh:5" touches=2 raised-by=record/wave-01-fixture/dbt-rec.md|log_shim one-case-abstraction "lib/a.sh:4" touches=1 raised-by=record/wave-01-fixture/dbt-rec.md burned=T9' "$RC|$(printf '%s\n' "$OUT" | paste -sd'|' -)"
poke "$RSEV" debt
expect_eq "DEBT-L9 debt with no subcommand is a usage error (exit 2)" "2" "$RC"
poke "$RSEV" debt touched
expect_eq "DEBT-L9b debt touched with no concept is a usage error (exit 2)" "2" "$RC"
rm -f "$DBT_LOG"

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
DBT_AL="$(printf '%s\n' "$DBT_CL1" "$DBT_CL2" | sed -e 's/^debt: //' -e 's/ from=wave-00-prior$//' | paste -sd'|' -)"
poke "$RSEV" debt adopt "$DBT_CONT"
expect_eq "DEBT-A1 §DEBT-ADOPT debt adopt over the session's bound run exits 0, saying what it adopted" \
  "0|poker: debt adopt — 2 adopted, 0 already there: record/$DBT_SLUG/run.log" "$RC|$OUT"
expect_eq "DEBT-A1c …and debt list reads both back" "0|$DBT_AL" "$(poke "$RSEV" debt list "$PSEV"; printf '%s|%s' "$RC" "$(printf '%s\n' "$OUT" | paste -sd'|' -)")"
cp "$DBT_LOG" "$TMPROOT/dbt-before"
poke "$RSEV" debt adopt "$DBT_CONT" "$PSEV"
expect_eq "DEBT-A2 a second adopt, the plan named: 0 adopted, 2 already there" \
  "0|poker: debt adopt — 0 adopted, 2 already there: record/$DBT_SLUG/run.log" "$RC|$OUT"
expect_true "DEBT-A2b …and the log is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
cp "$DBT_LOG" "$TMPROOT/dbt-before"
poke "$RSEV" debt adopt "$TMPROOT/no-such-continuation.md" "$PSEV"
expect_eq "DEBT-A4 a path that is no file is refused (exit 2)" "2" "$RC"
expect_contains "DEBT-A4b …naming the path" "$TMPROOT/no-such-continuation.md" "$OUT"
poke "$RSEV" debt adopt "$TMPROOT" "$PSEV"
expect_eq "DEBT-A4c a directory is refused as well (exit 2)" "2" "$RC"
expect_contains "DEBT-A4c2 …naming it" "no readable continuation at $TMPROOT" "$OUT"
expect_true "DEBT-A4d …and the log is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
printf '%s\n' "## Deferrals" "" "$DBT_CL1" 'debt: widget_parse duplicate "lib/w.sh:1" touches=3 from=wave-00-prior' > "$TMPROOT/dbt-cont-bad.md"
poke "$RSEV" debt adopt "$TMPROOT/dbt-cont-bad.md" "$PSEV"
expect_eq "DEBT-A5 a debt: line that does not parse is refused (exit 1)" "1" "$RC"
expect_contains "DEBT-A5a …naming the line" 'debt: widget_parse duplicate "lib/w.sh:1" touches=3 from=wave-00-prior' "$OUT"
expect_true "DEBT-A5b …and the log is byte-identical, the good line before it not adopted either" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
printf '%s\n' "## Deferrals" "" 'deferred: record/wave-00-prior/rev.md#1 S3 on "a deferral" stated="-" from=wave-00-prior' > "$TMPROOT/dbt-cont-none.md"
poke "$RSEV" debt adopt "$TMPROOT/dbt-cont-none.md" "$PSEV"
expect_eq "DEBT-A6 a continuation with no debt: line adopts nothing and exits 0" "0" "$RC"
expect_true "DEBT-A6c …the log byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
poke "$RSEV" debt adopt
expect_eq "DEBT-A7 debt adopt with no continuation is a usage error (exit 2)" "2" "$RC"
rm -f "$DBT_LOG"

# ---------- §DEBT (wave-36 T13; D13, REQ-7 AC-7.2, AC-7.3, AC-7.8; C24, C25, A-orch-1, A-orch-2) ----------
# `debt add` reads any record carrying grammar-true `debt:` lines, no `reviewed:` line required, so an `assumptions.md`
# hole line reaches debt.md by verb, never by hand; each line is held to lib/debt.sh `debt_line_ok` before any write.
# `debt adopt` with no plan named or bound refuses naming `bind` and writes nothing, never taking the newest by mtime.
# fails-when: a hole line never reaches debt.md; the unbound adopt writes the predecessor's ledger.
DBT_ASM="$SEV_DIR/assumptions.md"
printf '%s\n' "# assumptions — wave-01-fixture" "" \
  "- A-orch-1 (by hand): adopt carries open rows only, so the readers of a re-keyed session are orphaned." \
  'debt: hole adopt-orphans hooks/session-poker.sh:2846, payload/scripts/lib/units.sh:2112' \
  "- A-orch-2: a second assumption, prose only." > "$DBT_ASM"
expect_false "DEBT-H0 precondition: the run has no ledger yet, and the record carries no reviewed: line" \
  test -e "$DBT_LOG" -o -n "$(/usr/bin/grep '^reviewed:' "$DBT_ASM")"
poke "$RSEV" debt add record/wave-01-fixture/assumptions.md "$PSEV"
expect_eq "DEBT-H1 §DEBT debt add takes an assumptions.md hole line with no reviewed: line (exit 0)" "0" "$RC"
expect_absent "DEBT-H1d …and the reading's refusal is gone (C24)" "carries no reviewed:" "$OUT"
cp "$DBT_LOG" "$TMPROOT/dbt-before"
printf '%s\n' "# assumptions" "" 'debt: hole born-marker hooks/session-poker.sh born (the born marker is lost)' > "$SEV_DIR/asm-free.md"
poke "$RSEV" debt add record/wave-01-fixture/asm-free.md "$PSEV"
expect_eq "DEBT-H2 a hole line whose site is prose, not <path>:<line>, is refused (exit 1)" "1" "$RC"
expect_true "DEBT-H2c …and the log is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
mkdir -p "$SEV_DIR/two words"
printf '%s\n' 'debt: hole spaced-source lib/s.sh:1' > "$SEV_DIR/two words/assumptions.md"
poke "$RSEV" debt add "record/wave-01-fixture/two words/assumptions.md" "$PSEV"
expect_eq "DEBT-H3 a record whose path holds a space would write raised-by with a space (A-orch-1's shape): refused (exit 1)" "1" "$RC"
expect_true "DEBT-H3c …and the log is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LOG"
rm -rf "$SEV_DIR/two words" "$SEV_DIR/asm-free.md" "$DBT_ASM"
rm -f "$DBT_LOG"

# The unbound adopt (C25, A-orch-2): an engaged session bound to no plan, in a root whose only plan is a
# CLOSED predecessor that keeps its own ledger. `resolve_run`'s `none` arm hands the tick the newest plan
# by mtime so it can DISARM; the debt verb is a writer and takes no plan it was not given or bound to. The predecessor is a
# run at 15: its page, and its log holding its delivered step 9 and its one debt.
RDU="$(make_repo dbt-unbound)"; ( cd "$RDU" && git commit -q --allow-empty -m init )
DBU_PLAN="$RDU/.bionic/docs/plans/epic-99-fixture/wave-00-prior.plan.md"; mkdir -p "${DBU_PLAN%/*}"
printf '%s\n' "---" "canonical_sdlc_version: 15" "---" "" "# prior wave" > "$DBU_PLAN"
DBU_LED="$RDU/.bionic/docs/record/wave-00-prior/run.log"; mkdir -p "${DBU_LED%/*}"
printf 'run/v1|ev=%s\n' 'step|n=9|delivered=wave-00-prior|at=2026-10-01T00:00:00Z' \
  'debt|concept=log_shim|kind=one-case-abstraction|sites=lib/a.sh:4|raised-by=record/wave-00-prior/dbt-rec.md|touches=2|at=2026-10-01T00:00:01Z' > "$DBU_LED"
DBU_SHA="$(shasum "$DBU_LED" | awk '{ print $1 }')"
expect_eq "DEBT-U0 precondition: the root's newest plan is the closed predecessor, which active_plan hands an unbound session" \
  "$DBU_PLAN|closed" "$(bash -c '. "$1/run.sh"; p="$(active_plan "$2")"; printf "%s|" "$p"; run_open "$p" >/dev/null 2>&1 && echo open || echo closed' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$RDU" 2>/dev/null)"
expect_eq "DEBT-U0b precondition: the session's marker binds no plan" "" "$(cat "$RDU/.bionic/tmp/engaged-$SID.state")"
poke "$RDU" debt adopt "$DBT_CONT"
expect_eq "DEBT-U1 §DEBT debt adopt with no plan named and none bound is refused (exit 2)" "2" "$RC"
expect_contains "DEBT-U1b …naming bind" "bind" "$OUT"
expect_absent "DEBT-U1c …and it adopted nothing" "adopted" "$OUT"
expect_eq "DEBT-U1d …the predecessor's ledger, its run's log, is unchanged (sha)" "$DBU_SHA" "$(shasum "$DBU_LED" | awk '{ print $1 }')"
poke "$RDU" debt adopt "$DBT_CONT" "$DBU_PLAN"
expect_eq "DEBT-U2 control: the same adopt naming the plan writes that plan's ledger (exit 0)" \
  "0|poker: debt adopt — 1 adopted, 1 already there: record/wave-00-prior/run.log" "$RC|$OUT"

# ============================================================
section "§LINE-TELL: the tick tells each standing red and each stalled entry once, with its logs (wave-28 T5; REQ-9 AC-9.2, AC-9.3; D8)"
# ============================================================
#
# `ready` appends `standing` when a red also fails at the accepted head (the branch's, not a row's) and `stalled` when
# an entry's runs twice gave no verdict. The tick prints each off the bound plan's landing record as a note, once; a
# new event is told by the next tick. FIXTURE FIDELITY: §60's repository and bound plan (s60_world); the events are
# PLANTED in the run's log in the `run/v1` shape lib/line.sh writes.
LT_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
s60_world lt-tell @A whole
LT_H1="$(printf 'a%.0s' $(seq 40))"; LT_H2="$(printf 'b%.0s' $(seq 40))"
printf 'run/v1|ev=standing|head=%s|suite=a.test.sh|lines=3|log=/rec/line/T1-a-%s.log|at=2026-10-06T10:00:00Z\n' "$LT_H1" "${LT_H1:0:12}" >> "$S60_REC"
printf 'run/v1|ev=stalled|row=T7|logs=/rec/line/T7-b-1.log,/rec/line/T7-b-1-2.log|at=2026-10-06T10:01:00Z\n' >> "$S60_REC"
lt_lines() { printf '%s\n' "$OUT" | /usr/bin/grep -E '^poker: note: (standing|stalled) ' | tr '\n' '|' | sed 's/|$//'; }
s60_tick
s60_tick
expect_nonempty "LT3-pre the second tick printed (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: ')"
expect_eq "LT3 a second tick over the same record tells neither again" "" "$(lt_lines)"
printf 'run/v1|ev=standing|head=%s|suite=a.test.sh|lines=1|log=/rec/line/T2-a-%s.log|at=2026-10-06T10:02:00Z\n' "$LT_H2" "${LT_H2:0:12}" >> "$S60_REC"
s60_tick
POKE_BOUND="$LT_BOUND_WAS"

# ============================================================
section "§COPIED-LOG §REVIEW-RANGE §CUR7-COVERED: what a run's close wrote by hand, a verb writes or reads"
# ============================================================
# FIXTURE FIDELITY. §SEV's shape, built fresh: a plan bound to this session at Step 5, its working branch in a
# linked worktree, real commits, a reader row from the production writer, and the run line through the product's
# writer (regression_fixture). Every write goes through the real verb.
VG_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RVG="$(make_repo verb-gaps)"; ( cd "$RVG" && git commit -q --allow-empty -m init )
git -C "$RVG" config user.name "Dana Fixture"
VG_B="$(git -C "$RVG" rev-parse HEAD)"
PVG="$(s42_plan "$RVG" 5 "  worktree: .worktrees/01-fixture
  base-sha: ${VG_B:0:8}
  branch: wave/01-fixture")"
s42_builds_landed "$PVG"
git -C "$RVG" worktree add -q -b wave/01-fixture "$RVG/.worktrees/01-fixture" "$VG_B" >/dev/null 2>&1
VG_WT="$RVG/.worktrees/01-fixture"; VG_DIR="$RVG/.bionic/docs/record/wave-01-fixture"
VG_A="$(s57_commit "$VG_WT" lib/a.sh A)"
new_roster "$RVG"
printf '%s|questions=adversarial\n' "$(roster_row_fixture session="$SID" name=vg-crit agent_id=a-vg-crit \
  subagent_type=bionic:critic files=.bionic/docs/record/wave-01-fixture/past-waiver.md)" >> "$(roster_of "$RVG")"


# ---------- §COPIED-LOG: a recorded run's log, copied under record/, is that run ----------
# The run's log is written outside record/ (where a detached run keeps it), its run line naming that path; the
# copy matches the line by its sha256. An edited copy matches no run.
VG_RUN="$RVG/.bionic/tmp/runs/w-whole.log"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture --pre 'whole run' "$PVG" "$VG_RUN" "$VG_A" 0 0
cp "$VG_RUN" "$VG_DIR/whole-copy.log"; sed 's/^whole run$/whole run, edited/' "$VG_RUN" > "$VG_DIR/whole-edited.log"
s42_snap "$RVG" "$PVG"
poke "$RVG" proof-add regression record/wave-01-fixture/whole-edited.log
s42_unchanged "VG-3 control: an edited copy matches no recorded run" 1 "$PVG"
poke "$RVG" proof-add regression record/wave-01-fixture/whole-copy.log
expect_eq "VG-3c AC-20.3 a byte copy of the recorded run's log registers (exit 0), naming the run it is" "0|1" \
  "$RC|$(s46_proved "$PVG" | /usr/bin/grep -c "^proved: kind=regression head=$VG_A .* evidence=record/wave-01-fixture/whole-copy.log run=[^ ]* head=$VG_A rc=0$")"

# ---------- §REVIEW-RANGE: the user's waiver of a question is where its next reading starts ----------
vg_waivers() { /usr/bin/grep -c "^run/v1|ev=waiver|question=[a-z]*|head=$1|" "$(bash -c '. "$1/reader.sh" && reader_log "$2"' _ "${S46_LIB%/*}" "$PVG")"; }
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RVG" waive all 'I waive the readings at A'
expect_eq "VG-2a a question's waiver on words no prompt the person typed holds: refused (exit 1), no waiver written" "1|0" "$RC|$(vg_waivers "$VG_A")"
said_as typed "$RVG" 'I waive the readings at A' 'I waive the readings at C2' 'ship C2' 'ship C3'; CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RVG" waive all 'I waive the readings at A'
expect_eq "VG-2 the user's waiver of every question at A (exit 0)" "0|3" "$RC|$(vg_waivers "$VG_A")"
VG_C="$(s57_commit "$VG_WT" lib/a.sh C)"
printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: pass\nscope: piece\n' "$VG_A" "$VG_C" > "$VG_DIR/past-waiver.md"
poke "$RVG" proof-add review record/wave-01-fixture/past-waiver.md --question adversarial --reader vg-crit
expect_eq "VG-2b AC-20.2 a reading of A..C registers on the waiver at A, with no reading before it (exit 0)" "0|1" \
  "$RC|$(s46_proved "$PVG" | /usr/bin/grep -c "^proved: kind=review head=$VG_C .* evidence=record/wave-01-fixture/past-waiver.md question=adversarial ")"

# ---------- §CUR7-COVERED: prose landed past the whole run is green, code landed past it is unproved ----------
# The plan holds a whole-run row, a release row and an open integrate row reading the release; the user approves the
# release at C2 and waives there, then two prose commits land: green, admitted with no word. A code commit after them
# is unproved until the person's word at that head. fails-when: prose past the run reads unproved; code past it reads
# green; a word at another head admits it.
VG_C2="$(s57_commit "$VG_WT" lib/b.sh C2)"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture "$PVG" "$VG_DIR/whole-c2.log" "$VG_C2" 0 0
poke "$RVG" proof-add regression record/wave-01-fixture/whole-c2.log
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RVG" waive all 'I waive the readings at C2'
awk '{ print } /^\| T5 \| 5 \| verify / {
  print "| T6 | 5 | test | the whole run | — | 30 | REQ-1 | — | — |"
  print "| T7 | 7 | doc | the release | — | 30 | REQ-1 | CHANGELOG.md | — |"
  print "| T8 | 8 | integrate | the merge | — | 30 | REQ-1 | — | — |" }' "$PVG" > "$PVG.tmp" && mv "$PVG.tmp" "$PVG"
printf 'run/v1|ev=%s|at=2026-10-04T00:4%s:00Z\n' 'dispatch|row=T6|name=test-runner' 0 'published|row=T6' 1 'dispatch|row=T7|name=implementor' 2 \
  'published|row=T7' 3 >> "$VG_DIR/run.log"
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RVG" approve release 'ship C2'
expect_eq "VG-5 the plan is in the order, and the user approves the release at C2 (exit 0)" "0|T6|$VG_C2" \
  "$RC|$(bash -c '. "$1/units.sh" && units_order "$2"' _ "${S46_LIB%/*}" "$PVG")|$(bash -c '. "$1" && proof_approved_head "$2" release' _ "$S46_LIB" "$PVG")"
s57_commit "$VG_WT" .bionic/docs/record/wave-01-fixture/notes.md P1 >/dev/null
s57_commit "$VG_WT" README.md P2 >/dev/null
# The fixture models no whole matrix, so the judge is asked at Step 7 through `current 8 --check`, at the working head.
bash -c '. "$1" && proof_step_event "$2" 7' _ "$S46_LIB" "$PVG"
sp4_rule_rows "$PVG" "$(git -C "$VG_WT" rev-parse HEAD)"
poke "$RVG" current 8 --check
expect_eq "VG-5b AC-20.5 the approval and the waivers at C2, two prose commits after: green by content, admitted with no word (exit 0, no merge-unproved approval)" "0|yes|0" "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -q 'would advance' && echo yes)|$(/usr/bin/grep -c '|ev=approval|key=merge-unproved|' "$VG_DIR/run.log")"
expect_absent "VG-5b2 …and the judge reads no regression unproved there" "unproved" "$OUT"
vg_mu() {  # [<head>] -> the person's merge-unproved word at <head> the run's one such approval; none without a head
  /usr/bin/grep -v '|ev=approval|key=merge-unproved|' "$VG_DIR/run.log" > "$VG_DIR/run.log.n"; mv "$VG_DIR/run.log.n" "$VG_DIR/run.log"
  [ -z "$1" ] || printf 'run/v1|ev=approval|key=merge-unproved|by=chris|head=%s|said=merge|at=2026-10-26T00:00:00Z\n' "$1" >> "$VG_DIR/run.log"
}
vg_unproved() { printf '%s\n' "$OUT" | /usr/bin/grep -c 'regression.*unproved'; }
# C3, code, lands green on its suite; the release is approved again at C3, as code past an approval is refused by it.
VG_C3="$(s57_commit "$VG_WT" lib/b.sh C3)"
{ printf 'run/v1|ev=ready|row=T10|suites=a.test.sh|at=2026-10-04T14:00:00Z\n'; printf 'run/v1|ev=verdict|row=T10|commit=%s|suite=a.test.sh|result=green|log=/fixture/T10.log|at=2026-10-04T14:05:00Z\n' "$VG_C3"
  printf 'run/v1|ev=published|row=T10|commit=%s|kind=land|by=w-T10|why=landed|at=2026-10-04T14:10:00Z\n' "$VG_C3"; } >> "$VG_DIR/run.log"
CLAUDE_CONFIG_DIR="$SAID_CFG" poke "$RVG" approve release 'ship C3'
expect_eq "VG-5c precondition: the user approves the release at the code head C3 (exit 0)" "0|$VG_C3" "$RC|$(bash -c '. "$1" && proof_approved_head "$2" release' _ "$S46_LIB" "$PVG")"
poke "$RVG" current 8 --check
expect_eq "VG-5c a code commit C3 past them, landed green on its own suite: covered, not green, refused as regression unproved, naming the reply" "1|1|1" "$RC|$(vg_unproved)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'reply .* on the release card')"
vg_mu "$VG_C2"; poke "$RVG" current 8 --check
expect_eq "VG-5d …the person's word at C2's head, not the working head, leaves the regression unproved" "1|1" "$RC|$(vg_unproved)"
vg_mu "$(git -C "$VG_WT" rev-parse HEAD)"; poke "$RVG" current 8 --check
expect_eq "VG-5e …and the word at the working head holds it: no regression line unproved (VG-5d read the same extractor)" "0" "$(vg_unproved)"
vg_mu ""; /usr/bin/grep -v '|row=T10|' "$VG_DIR/run.log" > "$VG_DIR/run.log.n" && mv "$VG_DIR/run.log.n" "$VG_DIR/run.log"
poke "$RVG" current 8 --check

POKE_BOUND="$VG_BOUND_WAS"


# ============================================================
section "§REPLY-SEQ: one reply orders the release approval card's decisions in sequence, each applied in order and recorded"
# ============================================================
# FIXTURE FIDELITY. §COPIED-LOG's plan at its working head, its reading's record given one S3 finding; the page's
# record carries the replay table in its writer's row shape (release-approval.test.sh §SHAPE pins that row). Decision
# 1's default names a row the plan lacks, so taking it refuses; 2 waives the plan's one matrix row; 3 moves the
# finding. The user's words stand in a transcript of this session under a config dir of this section's own.
RS_H="$(git -C "$RVG" rev-parse wave/01-fixture)"; RS_F="record/wave-01-fixture/past-waiver.md#1"; RS_P="$VG_DIR/release-approval-${RS_H:0:8}.md"
printf 'findings: 1\nfinding: 1 S3 off lib/a.sh:1 a side path\n' >> "$VG_DIR/past-waiver.md"
rs_page() {  # <dec fields>... -> the page's record at the working head, one replay row each, numbered from 1
  local n=0 l; printf 'Release approval\n\n## Replay\n\nrelease-approval/v1|plan=%s|head=%s|at=2026-10-20T00:00:00Z|decisions=%s\n' "$PVG" "$RS_H" "$#" > "$RS_P"
  for l in "$@"; do n=$((n + 1)); printf 'release-approval/v1|dec=%s|%s\n' "$n" "$l" >> "$RS_P"; done
}
rs_done() { /usr/bin/grep -E '^(applied|withheld): ' "$RS_P" | paste -sd'|' -; }  # what the reply recorded, in order
RS_TX="$TMPROOT/rs-cfg/projects/$(bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ "${S46_LIB%/*}" "$RVG")/$SID.jsonl"
mkdir -p "${RS_TX%/*}"; export CLAUDE_CONFIG_DIR="$TMPROOT/rs-cfg"; RS_FX="${BIONIC_SCRIPTS_DIR}/tests/fixtures/transcript-move"
printf 'root=%s\nstarted=2026-10-14T00:00:00Z\ncwd=%s\n' "${BIONIC_HOOKS_DIR%/*}" "$RVG" > "$RVG/.bionic/tmp/loaded-$SID.state"
{ cat "$RS_FX/frame.jsonl"; for l in '1 run, 3 fix, rest default' 'all recommended' '1 run, 4 fix, rest default' '1 fix, rest default'; do
  jq -c --arg t "$l" '.message.content = $t' "$RS_FX/typed.jsonl"; done; } > "$RS_TX"
RS_ROW='other=-|pick=default|choices=waive/run|why=not run on this release'
RS_FIND="key=finding:$RS_F|default=-|other=finding-move $RS_F fix|pick=other|choices=carry/fix|why=fixed instead of carried"
rs_page "key=row:AC-9.1|default=waive AC-9.1|$RS_ROW" "key=row:AC-1.1|default=waive AC-1.1|$RS_ROW" "$RS_FIND"
s42_snap "$RVG" "$PVG"
poke "$RVG" reply '1 run, 4 fix, rest default'
s42_unchanged "RS-1 an item naming a decision the page does not hold refuses the whole reply" 1 "$PVG"
expect_eq "RS-1b …naming the item, nothing recorded on the page" "1|" "$(printf '%s' "$OUT" | /usr/bin/grep -c '"4 fix"')|$(rs_done)"
poke "$RVG" reply '1 fix, rest default'
s42_unchanged "RS-2 an item naming a choice its decision does not offer refuses the whole reply" 1 "$PVG"
expect_eq "RS-2b …naming the item and the two it offers, nothing recorded" "1|" "$(printf '%s' "$OUT" | /usr/bin/grep -c '"1 fix".*waive.*run')|$(rs_done)"
poke "$RVG" reply '1 run, 3 fix, rest default'
expect_eq "RS-3 AC-13.3 '1 run, 3 fix, rest default': 1 run, 2 its default, 3 fixed, recorded in that order (exit 0)" \
  "0|withheld: row:AC-9.1|applied: row:AC-1.1 waive rc=0|applied: finding:$RS_F finding-move rc=0" "$RC|$(rs_done)"
expect_eq "RS-3b …AC-1.1 waived and the finding moved to fix, each on the user's words" "waiver|to=fix|by=Dana Fixture|words=1 run, 3 fix, rest default|" \
  "$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$PVG" cell AC-1.1 | sed -n 's/^by=//p')|$(bash -c '. "$1"; proof_move_line "$2" "$3"' _ "$S46_LIB" "$PVG" "$RS_F" | /usr/bin/grep -oE '\|to=fix\|by=[^|]*\|words=[^|]*\|' | cut -c2-)"
rs_page "key=row:AC-9.1|default=waive AC-9.1|${RS_ROW/pick=default/pick=other}" "${RS_FIND/pick=other/pick=default}"
poke "$RVG" reply 'all recommended'
expect_eq "RS-4 AC-13.3 'all recommended' takes the orchestrator's choice on each, in order (exit 0)" \
  "0|withheld: row:AC-9.1|applied: finding:$RS_F carried" "$RC|$(rs_done)"
export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"

# ============================================================
section "§BRIEF-PINS: a suite declares the files it pins with one header line, and the brief names them on Files, each marked"
# ============================================================
# A row's Suites name the suites a writer runs; each suite's `# pins: <path> [<path>…]` header line names the files
# whose changes it holds, so a brief carries them on Files and the writer is not left waiting on an amend. The reader
# is the suite's own header, never a search of its text. Fixture: scratch suites under a scratch repository, one
# declaring two pins, one declaring nothing (the control), one repeating a pin the first declares.
BP="$(make_repo brief-pins)"; ( cd "$BP" && git commit -q --allow-empty -m init ) >/dev/null 2>&1
git -C "$BP" config user.name "Dana Fixture"
mkdir -p "$BP/tests"
printf '#!/bin/bash\n# a scratch suite that pins two files\n# pins: tests/fixtures/x tests/fixtures/y\nset -u\n# pins: tests/fixtures/body-only\n' > "$BP/tests/pinned.test.sh"
printf '#!/bin/bash\n# a scratch suite that declares no pins\nset -u\n' > "$BP/tests/plain.test.sh"
printf '#!/bin/bash\n# pins: tests/fixtures/x\nset -u\n' > "$BP/tests/shared.test.sh"
BP_PLAN="$(s47_plan "$BP" 4 \
  '| T1 | 4 | build | the pinned build | implementor | — | 30 | REQ-12 | lib/a.sh, tests/pinned.test.sh | pending |' \
  '| T2 | 4 | build | the control build | implementor | — | 30 | REQ-12 | lib/b.sh, tests/plain.test.sh | pending |' \
  '| T3 | 4 | build | a pin the Files already hold | implementor | — | 30 | REQ-12 | lib/c.sh, tests/fixtures/x, tests/pinned.test.sh | pending |' \
  '| T4 | 4 | build | one pin, two suites | implementor | — | 30 | REQ-12 | lib/d.sh, tests/pinned.test.sh, tests/shared.test.sh | pending |')"
bind_marker "$BP" "$BP_PLAN"
BP_REC="$BP/.bionic/docs/record/wave-01-fixture/briefs"
bp_files() {  # <row> -> the brief's Files field: its line and the continuation lines under it
  awk '/^Files:/ { f = 1; print; next } f && (/^$/ || /^[A-Za-z][A-Za-z -]*: /) { exit } f { print }' "$BP_REC/$1.md"
}
bp_brief() { poke "$BP" brief "$1"; }
bp_brief T1
expect_eq "BP-0 setup: the brief verb wrote T1's brief (exit 0)" "0" "$RC"
expect_eq "BP-1 AC-12.1 a suite in the row's Suites declaring # pins: tests/fixtures/x puts that path on the brief's Files, marked" \
  "Files: lib/a.sh, tests/pinned.test.sh
tests/fixtures/x  # (pinned by pinned.test.sh)
tests/fixtures/y  # (pinned by pinned.test.sh)" "$(bp_files T1)"
expect_absent "BP-1b …and a pins line below the header block is not a declaration" "body-only" "$(bp_files T1)"
bp_brief T2
expect_eq "BP-2 control: a suite with no header adds nothing, the Files line is the row's cell (exit 0)" \
  "0|Files: lib/b.sh, tests/plain.test.sh" "$RC|$(bp_files T2)"
bp_brief T3
expect_eq "BP-3 a pin the row's Files already name is not written twice" \
  "Files: lib/c.sh, tests/fixtures/x, tests/pinned.test.sh
tests/fixtures/y  # (pinned by pinned.test.sh)" "$(bp_files T3)"
bp_brief T4
expect_eq "BP-4 a path two suites pin is one entry, marked by both" \
  "Files: lib/d.sh, tests/pinned.test.sh, tests/shared.test.sh
tests/fixtures/x  # (pinned by pinned.test.sh, shared.test.sh)
tests/fixtures/y  # (pinned by pinned.test.sh)" "$(bp_files T4)"
BP_LIFT="$(bash -c '. "$1" && brief_contract "$2"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh" "$(cat "$BP_REC/T1.md")" 2>&1)"
expect_contains "BP-5 the dispatch wall's reader lifts the pins as paths of the brief, no marker read as one" \
  "files=lib/a.sh,tests/pinned.test.sh,tests/fixtures/x,tests/fixtures/y" "$(printf '%s\n' "$BP_LIFT" | /usr/bin/grep '^files=')"
expect_absent "BP-5b …and refuses no entry of the Files span" "files_bad" "$BP_LIFT"
# THE PINS ARE READ AT THE WORKING HEAD: a suite committed on the plan's working branch and absent from the checkout.
( cd "$BP" && git checkout -q -b wave/01-fixture && git add -f tests && git commit -qm suites && git checkout -q - ) >/dev/null 2>&1
rm -rf "$BP/tests"
awk 'NR == 1 { print; print "working-branch: wave/01-fixture"; next } { print }' "$BP_PLAN" > "$BP_PLAN.tmp" && mv "$BP_PLAN.tmp" "$BP_PLAN"
bp_brief T1
expect_eq "BP-6 with a working branch, the pins come from the suite at its tip, not the checkout (exit 0)" \
  "0|Files: lib/a.sh, tests/pinned.test.sh
tests/fixtures/x  # (pinned by pinned.test.sh)
tests/fixtures/y  # (pinned by pinned.test.sh)" "$RC|$(bp_files T1)"
# THE SUITES THAT DECLARE THEIR PINS, read as shipped: each real header reaches the brief of a row that runs it, and every
# path declared is a file of this repository (a stale pin names a file a writer is then told it may write). The plan
# names no working branch here, so the headers are read from the copies under the scratch checkout.
sed '/^working-branch: /d' "$BP_PLAN" > "$BP_PLAN.tmp" && mv "$BP_PLAN.tmp" "$BP_PLAN"
printf '%s\n' '| T5 | 4 | build | the declaring suites | — | 30 | REQ-12 | lib/e.sh, tests/words.test.sh, tests/sitrep-card.test.sh, tests/door-landing.test.sh, tests/release-check.test.sh, tests/shell-lint.test.sh | — |' >> "$BP_PLAN"
mkdir -p "$BP/tests"
for BP_S in words sitrep-card door-landing release-check shell-lint; do cp "$(dirname "$0")/$BP_S.test.sh" "$BP/tests/$BP_S.test.sh"; done
bp_brief T5
BP_F5="$(bp_files T5)"
expect_contains "BP-8 words.test.sh declares the files its allow list names" "agents-src/blocks/implementor-mechanics.md  # (pinned by words.test.sh)" "$BP_F5"
expect_contains "BP-8b sitrep-card.test.sh declares the verb whose sheet its fixtures copy" "hooks/poker/sitrep.sh  # (pinned by sitrep-card.test.sh)" "$BP_F5"
expect_contains "BP-8c door-landing.test.sh declares the fixture it sources" "tests/lib/door.sh  # (pinned by door-landing.test.sh)" "$BP_F5"
expect_contains "BP-8d door-landing.test.sh and release-check.test.sh both declare the check" "tests/lib/release-check.sh  # (pinned by door-landing.test.sh, release-check.test.sh)" "$BP_F5"
expect_contains "BP-8e shell-lint.test.sh declares the census" "tests/CENSUS.md  # (pinned by shell-lint.test.sh)" "$BP_F5"
expect_contains "BP-8f …and every suite" "tests/*.test.sh  # (pinned by shell-lint.test.sh)" "$BP_F5"
BP_PATHS="$(printf '%s\n' "$BP_F5" | sed -n 's/^\([^ ]*\)  # (pinned by .*/\1/p')"
expect_nonempty "BP-9 setup: the declared paths are read off the brief" "$BP_PATHS"
BP_MISSING=""
while IFS= read -r BP_P; do
  [ -n "$BP_P" ] || continue
  [ -n "$(cd "${BIONIC_SCRIPTS_DIR}" && ls -d $BP_P 2>/dev/null)" ] || BP_MISSING="$BP_MISSING $BP_P"
done <<BP_EOF
$BP_PATHS
BP_EOF
expect_eq "BP-9b every path a suite declares it pins is a file of this repository" "" "$BP_MISSING"
# THE DEAD INDEX IS GONE: the verb calls no function the tree does not hold. Beside the positive on the same search.
expect_nonempty "BP-7 setup: the search finds the pins reader in hooks/" "$(/usr/bin/grep -rn "poker_brief_pins" "$BIONIC_HOOKS_DIR")"
expect_eq "BP-7b AC-12.2 /usr/bin/grep -rn 'reads_suites\\|poker_brief_index_suites' hooks/ prints nothing" "" \
  "$(/usr/bin/grep -rn "reads_suites\|poker_brief_index_suites" "$BIONIC_HOOKS_DIR")"

# ============================================================
section "§AMEND-NARROW: amend --suites= narrows a live contract's suites and its lands_on= with them; the collector hands the wall the suites that exist"
# ============================================================
# `amend` was a union, old members first, never a narrowing. `--suites=<a,b>` sets the row's suite set to exactly those,
# each of which the row already holds (a name it does not hold widens, and `--suites+` is the verb for that), and
# `lands_on=` keeps only the suites still in the set: a row that lands on a suite it may not run is a contract the
# dispatch wall refuses. A narrowing that would leave the row landing on nothing is refused, and `--suites=` with
# `--suites+` is two instructions on one set. The wall's membership arm is handed the suites under tests/ here too.
AN="$(make_repo amend-narrow)"; new_roster "$AN"
s30_row "$AN" suites_allowed="a.test.sh b.test.sh c.test.sh" lands_on=a.test.sh,b.test.sh
poke "$AN" amend w1 --suites=a.test.sh,b.test.sh --reason 'c is not run by this row'
expect_eq "AN-1 narrowing to a subset exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "AN-1b …the successor row holds exactly the narrower set" "a.test.sh b.test.sh" "$(s30_field "$(s30_last "$AN")" suites_allowed)"
expect_eq "AN-1c …and lands_on= is the same, both its suites still in the set" "a.test.sh,b.test.sh" "$(s30_field "$(s30_last "$AN")" lands_on)"
poke "$AN" amend w1 --suites=a.test.sh --reason 'b is not run either'
expect_eq "AN-2 narrowing again exits 0, with the set and lands_on= both cut to a" "0|a.test.sh|a.test.sh" \
  "$RC|$(s30_field "$(s30_last "$AN")" suites_allowed)|$(s30_field "$(s30_last "$AN")" lands_on)"
AN_ROWS="$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN")")"
poke "$AN" amend w1 --suites=d.test.sh --reason 'a name the row never held'
expect_eq "AN-3 a --suites= naming a suite the row does not hold is refused (exit 1) and writes nothing" "1|$AN_ROWS" \
  "$RC|$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN")")"
expect_contains "AN-3b …naming it and the verb that widens" "d.test.sh" "$OUT"
expect_contains "AN-3c …and --suites+" "--suites+" "$OUT"
poke "$AN" amend w1 --suites=a.test.sh --suites+ b.test.sh --reason 'both at once'
expect_eq "AN-4 --suites= beside --suites+ is a usage error (exit 2) and writes nothing" "2|$AN_ROWS" \
  "$RC|$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN")")"
poke "$AN" amend w1 --suites+ b.test.sh --reason 'b again'
expect_eq "AN-5 a widening still works (exit 0), the set old members first" "0|a.test.sh b.test.sh" \
  "$RC|$(s30_field "$(s30_last "$AN")" suites_allowed)"
expect_eq "AN-5b …and lands_on= is not widened with it" "a.test.sh" "$(s30_field "$(s30_last "$AN")" lands_on)"
AN2="$(make_repo amend-narrow-lands)"; new_roster "$AN2"
s30_row "$AN2" suites_allowed="a.test.sh b.test.sh" lands_on=b.test.sh
AN2_ROWS="$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN2")")"
poke "$AN2" amend w1 --suites=a.test.sh --reason 'drop b'
expect_eq "AN-6 a narrowing that drops every suite the row lands on is refused (exit 1) and writes nothing" "1|$AN2_ROWS" \
  "$RC|$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN2")")"
expect_contains "AN-6b …naming the suite it would orphan" "b.test.sh" "$OUT"
poke "$AN2" amend w1 --suites=a.test.sh,b.test.sh --reason 'the same set'
expect_eq "AN-7 a --suites= that names the set the row already holds changes nothing, and is refused (exit 1)" "1|$AN2_ROWS" \
  "$RC|$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN2")")"
# THE COLLECTOR: amend hands the wall the suites under tests/, so an added name with no file is refused here as at a dispatch.
AN3="$(make_repo amend-exists)"; new_roster "$AN3"
mkdir -p "$AN3/tests"; printf '#!/bin/bash\nexit 0\n' > "$AN3/tests/real.test.sh"
s30_row "$AN3" suites_allowed="a.test.sh"
poke "$AN3" amend w1 --suites+ real.test.sh --reason 'a suite that exists'
expect_eq "AN-8 --suites+ naming a file under tests/ is admitted (exit 0)" "0|a.test.sh real.test.sh" \
  "$RC|$(s30_field "$(s30_last "$AN3")" suites_allowed)"
AN3_ROWS="$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN3")")"
poke "$AN3" amend w1 --suites+ nosuch.test.sh --reason 'a suite with no file'
expect_eq "AN-8b --suites+ naming no file under tests/ is refused (exit 1) and writes nothing" "1|$AN3_ROWS" \
  "$RC|$(/usr/bin/grep -c '|name=w1|' "$(roster_of "$AN3")")"
expect_contains "AN-8c …naming the entry" "nosuch.test.sh" "$OUT"

# ============================================================
section "§REVIEW-FILES §FILES-UNHELD: each verb a close meets writes its cell, or names the edit that does"
# ============================================================
# A close met verbs that sent it in a circle: a review row's Files held one record for three questions; amend sent a closed
# contract to a new dispatch. FIXTURE FIDELITY: a task-scale plan at single rigor with a
# reads table carrying an artifact cell and no ledger, bound to this session, its working branch the repository's
# main, here brought to the run at 15 it stands for (`vc_15`); roster rows and acks in their writers' shapes (roster_row_fixture, s20_ack). Every write goes through the
# real verb; the one planted line is a review proof in proof_line's shape, as a review reading's fixture plants one.
vc_plan() {  # <repo> <row>... -> the plan path; bound and committed
  local repo="$1" f row; shift
  f="$repo/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")" "$repo/.bionic/docs/specs/epic-99-fixture" "$repo/.bionic/docs/record/wave-01-fixture"
  printf '# requirements\n' > "$repo/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
  printf '# spec\n' > "$repo/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
    printf 'rigor: single\nscale: task\nmulti_agent: true\nuse_worktree: true\nhas_ui: false\n'
    printf 'walk: exempt\ndeploy_target: n/a\n'
    printf 'parallel-budget: writers=3 suites=2 worktrees=8 test_jobs=8 source=user\n---\n\n'
    printf '# fixture task\n\n## SDLC State\n\ncurrent: 4\nworking-branch: main\n%s\n\n' "$SP_APPROVED_LINE"
    printf -- '- Step 1: requirements: specs/epic-99-fixture/wave-01-fixture.requirements.md\n'
    printf -- '- Step 2: spec: specs/epic-99-fixture/wave-01-fixture.spec.md\n'
    printf -- '- Step 3: plan: plans/epic-99-fixture/wave-01-fixture.plan.md\n'
    printf -- '- Step 4: opened\n  worktree: .worktrees/01-fixture\n  base-sha: abc1234\n  branch: main\n'
    printf -- '- T1: landed at record/T1.md\n- T2: dispatched to w-T2\n- T3: landed at record/T3.md\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    for row in "$@"; do printf '%s\n' "$row"; done
    printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
  } > "$f"
  bind_marker "$repo" "$f"
  ( cd "$repo" && git add -f "$f" && git commit -qm plan ) >/dev/null 2>&1
  printf '%s' "$f"
}
vc_15() { sp_at15 "$2"; ( cd "$1" && git add -f "$2" && git commit -qm at15 ) >/dev/null 2>&1; }  # <repo> <plan> -> the run at 15, committed
vc_cell() { s48_row "$VC_P" "$1" | cut -d'|' -f"$2"; }  # <row> <4 task | 8 Files | 9 artifact>
VC="$(make_repo verb-cells)"; ( cd "$VC" && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
git -C "$VC" config user.name "Dana Fixture"
VC_REC=".bionic/docs/record/wave-01-fixture"
VC_P="$(vc_plan "$VC" \
  '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | lib/a.sh | landed | — | — |' \
  '| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | lib/b.sh | active | — | — |' \
  '| T3 | 4 | build | the third build | implementor | — | 30 | REQ-1 | lib/c.sh | landed | — | — |')"
vc_15 "$VC" "$VC_P"; new_roster "$VC"
printf '%s\n' "$(roster_row_fixture session="$SID" name=w-T2 agent_id=a-w-T2 launched_at=2026-10-22T10:00:00Z row=T2 plan="$VC_P" files=lib/b.sh suites_allowed=b.test.sh suites_source=declared)" >> "$(roster_of "$VC")"
printf '%s\n' "$(roster_row_fixture session="$SID" name=w-T3 agent_id=a-w-T3 launched_at=2026-10-22T10:00:00Z row=T3 plan="$VC_P" files=lib/c.sh suites_allowed=c.test.sh suites_source=declared)" >> "$(roster_of "$VC")"
s20_ack "$VC" w-T3 2026-10-22T11:00:00Z

# ---------- §REVIEW-FILES: a review row's Files are its questions' records, its artifact the first ----------
VC_THREE="$VC_REC/critic-evidence.md, $VC_REC/critic-adversarial.md, $VC_REC/critic-structure.md"
TA_PASTE=1 ta_add "$VC" T6 6 review "the critic's review. The critic reads the run once." critic — 30 REQ-1 — head
expect_eq "RF-0 setup: task-add of a review row on the single-rigor plan exits 0" "0" "$RC"
expect_eq "RF-1 AC-9.1 the row's Files hold one record per question the rigor deals, evidence, adversarial, structure" \
  "$VC_THREE" "$(vc_cell T6 8)"
expect_eq "RF-1b …and its artifact cell names the first, the record its landing takes" "$VC_REC/critic-evidence.md" "$(vc_cell T6 9)"
ta_add "$VC" T7 6 review "a review on one record. The critic writes one record." critic — 30 REQ-1 "$VC_REC/critic.md" head
s42_unchanged "RF-2 a review row written with one record for three questions" 1 "$VC_P"
expect_contains "RF-2b …and the refusal names the rendered list" "$VC_THREE" "$OUT"
TA_PASTE=1 ta_add "$VC" T7 6 review "a review on its three records. The critic writes three records." critic — 30 REQ-1 "$VC_THREE" head
expect_eq "RF-3 control: a review row whose Files name its three records goes in as written, its artifact the first" \
  "0|$VC_THREE|$VC_REC/critic-evidence.md" "$RC|$(vc_cell T7 8)|$(vc_cell T7 9)"
VC_OWN="$VC_REC/T10-evidence.md, $VC_REC/T10-adversarial.md, $VC_REC/T10-structure.md"
TA_PASTE=1 ta_add "$VC" T10 6 review "A review on its own records. The critic writes its own three records." critic — 30 REQ-1 "$VC_OWN" head
expect_eq "RF-3b a review row whose Files already name one record of its own per question keeps those names verbatim, its artifact the first" \
  "0|$VC_OWN|$VC_REC/T10-evidence.md" "$RC|$(vc_cell T10 8)|$(vc_cell T10 9)"
expect_absent "RF-3c …and no rendered critic-<q>.md name is added beside them" "critic-" "$(vc_cell T10 8)"
TA_PASTE=1 ta_add "$VC" T8 5 verify "the floor. The regression runs once." test-runner — 30 REQ-1 —
expect_eq "RF-4 control: a verify row keeps the reader-row rule, one record named for the row, and no artifact cell written" \
  "0|$VC_REC/T8.md|—" "$RC|$(vc_cell T8 8)|$(vc_cell T8 9)"

# ---------- §REVIEW-FILES, questions declared in the row's task cell (the records owed are the declared ones) ----------
# A re-read of fewer questions than the rigor deals declares them where the row is written. FIXTURE: the same plan at
# `rigor: double`, where the auditor holds `evidence` and the critic `adversarial` and `structure`; the one at single
# (VC) is the control that a critic holds all three. Every refusal leaves the plan byte-identical.
VD="$(make_repo verb-double)"; ( cd "$VD" && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
git -C "$VD" config user.name "Dana Fixture"
VD_P="$(vc_plan "$VD" '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | lib/a.sh | landed | — | — |')"; vc_15 "$VD" "$VD_P"
sed -e 's/^rigor: .*/rigor: double/' "$VD_P" > "$VD_P.tmp" && mv "$VD_P.tmp" "$VD_P"
( cd "$VD" && git add -f "$VD_P" && git commit -qm "rigor double" ) >/dev/null 2>&1
new_roster "$VD"
VD_REC=".bionic/docs/record/wave-01-fixture"
vd_cell() { s48_row "$VD_P" "$1" | cut -d'|' -f"$2"; }  # <row> <4 task | 8 Files | 9 artifact>
expect_eq "RF-5 setup: the double plan reads rigor: double" "rigor: double" "$(/usr/bin/grep -m1 '^rigor:' "$VD_P")"
TA_PASTE=1 ta_add "$VD" T9 6 review "the auditor's re-read. The auditor reads the evidence once." w01-audit — 30 REQ-1 "$VD_REC/auditor-evidence.md" --questions evidence
expect_eq "RF-5 AC-5.1 task-add --questions evidence at double with one record is admitted (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "RF-5b …and the task cell carries questions: evidence" " · questions: evidence" "$(vd_cell T9 4)"
expect_eq "RF-5c …its Files keep the one record, and its artifact cell names it" "$VD_REC/auditor-evidence.md|$VD_REC/auditor-evidence.md" \
  "$(vd_cell T9 8)|$(vd_cell T9 9)"
VD_UNITS="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh"
expect_eq "RF-5d the units reader lifts the declaration off the row's record" "evidence" \
  "$(bash -c '. "$1" && units_questions "$(units_rows "$2" | awk -F"\t" "\$1 == \"T9\"")"' _ "$VD_UNITS" "$VD_P")"
TA_PASTE=1 ta_add "$VD" T11 6 review "the auditor's re-read. The auditor reads the evidence once." w01-audit — 30 REQ-1 — --questions evidence
expect_eq "RF-5e a declared row whose Files name no record is given the one record it owes" "0|$VD_REC/critic-evidence.md" "$RC|$(vd_cell T11 8)"
expect_eq "RF-5f …and the units reader reads no declaration off a row that declares none (T1), beside the positive above" "evidence|" \
  "$(bash -c '. "$1" && units_questions "$(units_rows "$2" | awk -F"\t" "\$1 == \"T9\"")"; printf "|"; units_questions "$(units_rows "$2" | awk -F"\t" "\$1 == \"T1\"")"' _ "$VD_UNITS" "$VD_P")"

VD_TWO="$VD_REC/critic-adversarial.md, $VD_REC/critic-structure.md"
TA_PASTE=1 ta_add "$VD" T12 6 review "the critic's code read. The critic reads the code once." critic — 30 REQ-1 "$VD_TWO" --questions adversarial,structure
expect_eq "RF-6 AC-5.2 --questions adversarial,structure with two records is admitted, the cell carrying both" "0|1" \
  "$RC|$(printf '%s' "$(vd_cell T12 4)" | /usr/bin/grep -c ' · questions: adversarial,structure')"
ta_add "$VD" T13 6 review "the critic's code read. The critic reads the code once." critic — 30 REQ-1 "$VD_REC/critic.md" --questions adversarial,structure
s42_unchanged "RF-6b …with one record it is refused" 1 "$VD_P"
expect_contains "RF-6c …the refusal naming both questions' records" "$VD_TWO" "$OUT"
TA_PASTE=1 ta_add "$VD" T13 6 review "the critic's code read. The critic reads the code once." critic — 30 REQ-1 — --questions adversarial,structure
expect_eq "RF-6d control: the same row with no Files is given one record per declared question, no more" "0|$VD_TWO" "$RC|$(vd_cell T13 8)"
TA_PASTE=1 ta_add "$VD" T14 6 review "the critic's whole read. The critic reads the run once." critic — 30 REQ-1 —
VD_THREE="$VD_REC/critic-evidence.md, $VD_REC/critic-adversarial.md, $VD_REC/critic-structure.md"
expect_eq "RF-7 RF-1 holds: with no operand the rigor's full deal is owed, three records" "0|$VD_THREE" "$RC|$(vd_cell T14 8)"
expect_eq "RF-7b …and the cell carries no declaration" "0" "$(printf '%s' "$(vd_cell T14 4)" | /usr/bin/grep -c 'questions:')"

ta_add "$VD" T15 6 review "a mixed read. A reader reads it." critic — 30 REQ-1 "$VD_REC/critic-evidence.md, $VD_REC/critic-adversarial.md" --questions evidence,adversarial
s42_unchanged "RF-8 AC-5.2 --questions evidence,adversarial at double (the auditor's and the critic's) is refused as not dealt to one role" 1 "$VD_P"
expect_contains "RF-8b …naming the auditor's question" "evidence the auditor's" "$OUT"
expect_contains "RF-8c …and the critic's" "adversarial and structure the critic's" "$OUT"
ta_add "$VD" T15 6 review "the audit. The auditor reads it." w01-audit — 30 REQ-1 "$VD_REC/auditor-evidence.md, $VD_REC/auditor-adversarial.md" --questions evidence,adversarial
expect_eq "RF-8d …whichever agent the row names" "1" "$RC"

TA_PASTE=1 ta_add "$VC" T20 6 review "a single-rigor re-read. The critic reads one question." critic — 30 REQ-1 "$VC_REC/critic-adversarial.md" --questions adversarial
expect_eq "RF-9 at single the critic holds all three, so one declared question is admitted" "0|1" \
  "$RC|$(printf '%s' "$(vc_cell T20 4)" | /usr/bin/grep -c ' · questions: adversarial$')"
TA_PASTE=1 ta_add "$VC" T21 6 review "a single-rigor re-read. The critic reads two questions." critic — 30 REQ-1 — --questions structure,evidence
expect_eq "RF-9b …and a subset is declared in the dealing's order, evidence first" "0|$VC_REC/critic-evidence.md, $VC_REC/critic-structure.md" "$RC|$(vc_cell T21 8)"

ta_add "$VD" T16 5 verify "the floor. The regression runs once." test-runner — 30 REQ-1 — --questions evidence
s42_unchanged "RF-10 questions declared on a row that is not a review row are refused" 1 "$VD_P"
expect_contains "RF-10a …in the verb's own words, naming the row's kind" "T16 is a verify row" "$OUT"
ta_add "$VD" T16 6 review "the audit. The auditor reads it." w01-audit — 30 REQ-1 — --questions style
s42_unchanged "RF-10b a question outside the three is refused" 1 "$VD_P"
expect_contains "RF-10b2 …naming the words" "questions: style, which is no list of questions" "$OUT"
ta_add "$VD" T16 6 review "the audit. The auditor reads it." w01-audit — 30 REQ-1 — --questions evidence,evidence
s42_unchanged "RF-10c a question named twice is refused" 1 "$VD_P"
expect_contains "RF-10c2 …naming them" "questions: evidence,evidence, which is no list of questions" "$OUT"
ta_add "$VD" T16 6 review "the audit. The auditor reads it." w01-audit — 30 REQ-1 — --questions evidence --born 'review S3 off'
s42_unchanged "RF-10e a declared question and a born rating outside the plan's fix-policy: refused by the policy" 1 "$VD_P"
expect_contains "RF-10e2 …by the policy" "fix-policy" "$OUT"

# ---------- §FILES-UNHELD: a closed contract is not amended; its row's Files are the plan's cell ----------
s42_snap "$VC" "$VC_P"
poke "$VC" amend w-T3 --files+ lib/c3.sh --reason 'the closed contract'
VC_AREF="$OUT"
expect_eq "FU-4 amend on a closed contract is refused (exit 1)" "1" "$RC"
expect_contains "FU-4b …and names the edit of the Files cell of the row its contract held" "edit the Files cell of T3 in the plan" "$VC_AREF"
expect_absent "FU-4c …not a new dispatch" "dispatch the work again" "$VC_AREF"

# ============================================================
section "§TICK-LANDS: the tick lands a record row on the registration its kind owes, one published event, no cell"
# ============================================================
# A record row has no tree and no ready: the tick lands it (hooks/poker/line.sh `record_row_land`) once its checks
# pass, and nothing else does. A row nobody launched lands when it is ready; a row that owes a registration lands on it,
# never on its file: a review on its review registered, a regression row on the whole run's proof at the head, a walk
# row on the walk's proof naming its record. Each reason a row waits is told once. FIXTURE FIDELITY: the task-scale
# plan of §REVIEW-FILES at 15 (`vc_15`), bound, a build row landed by a code commit past the base, the record rows
# nobody launched (agent —, no tree), each review row its own question, the proofs in proof_line's shape seeded in the
# run's log (`sp_fact`).
# fails-when: a row lands on its file alone, a landing writes a cell or a step line, a reason is told at every tick,
# a refusal names no fix, or a row that waits on a landed row stays unready.
TL="$(make_repo tick-lands)"; ( cd "$TL" && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
git -C "$TL" config user.name "Dana Fixture"
TL_RD="record/wave-01-fixture"; TL_D=".bionic/docs/$TL_RD"
TL_P="$(vc_plan "$TL" \
  "| T20 | 4 | build | the build the record rows read | implementor | — | 30 | REQ-1 | lib/y.sh | landed | — | — |" \
  "| T21 | 6 | review | the evidence review · questions: evidence | — | — | 30 | REQ-1 | $TL_D/r21.md | pending | approval:plan | $TL_D/r21.md |" \
  "| T22 | 5 | test | the regression | — | — | 30 | REQ-1 | $TL_D/t22.md | pending | approval:plan | $TL_D/t22.md |" \
  "| T23 | 5 | verify | the walk | — | — | 30 | REQ-1 | $TL_D/walk.md | pending | approval:plan | $TL_D/walk.md |" \
  "| T24 | 5 | verify | a walk naming two records | — | — | 30 | REQ-1 | $TL_D/r24a.md, $TL_D/r24b.md | pending | approval:plan | — |" \
  "| T25 | 4 | build | the work after the regression | implementor | T22 | 30 | REQ-1 | $TL_D/z.md | pending | approval:plan | — |" \
  "| T26 | 6 | review | the review (a\\|b) · questions: structure | — | — | 30 | REQ-1 | $TL_D/none.md | pending | approval:plan | $TL_D/r26.md |")"
vc_15 "$TL" "$TL_P"; sed "s/^base-sha: abc1234$/base-sha: $(git -C "$TL" rev-parse main)/" "$TL_P" > "$TL_P.t" && mv "$TL_P.t" "$TL_P"
( cd "$TL" && git add -f "$TL_P" && git commit -qm base ) >/dev/null 2>&1; TL_H="$(s57_commit "$TL" lib/y.sh 'the build the record rows read')"; new_roster "$TL"
tl_state() { ( . "$(dirname "$S46_LIB")/units.sh" >/dev/null 2>&1; units_rows "$TL_P" ) | awk -F'\t' -v r="$1" '$1 == r { print $10 }'; }
tl_pub() { cat "$TL/$TL_D/run.log" 2>/dev/null | /usr/bin/grep -c "^run/v1|ev=published|row=$1|commit=$TL_H|kind=record|by=orchestrator|"; }
tl_plant() { sp_fact "$TL_P" "$1"; }
tl_said() { printf '%s\n' "$OUT" | /usr/bin/grep "NOT-LANDED $1 "; }
for f in r21 t22 walk r24a r24b r26; do printf 'question: evidence\nresult: pass\nscope: piece\nverdict: CONFIRMED\n' > "$TL/$TL_D/$f.md"; done
TL_ROWS0="$(/usr/bin/grep -E '^(\| T2[1-5] |- T2[1-5]:)' "$TL_P")"
poke "$TL" tick
expect_eq "TL-1 every record stands and nothing is registered: no row lands" "pending pending pending pending|0" \
  "$(tl_state T21) $(tl_state T22) $(tl_state T23) $(tl_state T24)|$(cat "$TL/$TL_D/run.log" 2>/dev/null | /usr/bin/grep -c '|ev=published|row=T2[1-6]|')"
expect_contains "TL-2 the review row waits on its registration, the tick says so naming the verb" "proof-add review" "$(tl_said T21)"
expect_contains "TL-3 the regression row waits on the whole run's proof at the head" "proof-add regression" "$(tl_said T22)"
expect_contains "TL-4 the walk row waits on the walk's proof naming its record" "proof-add walk $TL_RD/walk.md" "$(tl_said T23)"
expect_contains "TL-5 a record row naming two records and no artifact cell names the edit" "edit the artifact cell of T24 in the plan" "$(tl_said T24)"
expect_contains "TL-5b a task cell holding an escaped bar leaves the artifact cell its own: the record stands, the row is told" "proof-add review" "$(tl_said T26)"
expect_eq "TL-6 T25 waits on T22's landing: not ready" "" "$(cd "$TL" && bash -c '. "$1/fill.sh" >/dev/null 2>&1; fill_ready_set "$2" 99999 0' _ "$(dirname "$S46_LIB")" "$TL_P" 2>/dev/null | /usr/bin/grep -x T25)"
poke "$TL" tick
expect_eq "TL-7 a second tick tells no reason again" "0" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'NOT-LANDED T2')"
tl_plant "$(bash -c '. "$1" && proof_line review "$2" 2026-10-22T12:00:00Z "$3" evidence w-crit pass piece' _ "$S46_LIB" "$TL_H" "$TL_RD/r21.md")"
tl_plant "$(bash -c '. "$1" && proof_line regression "$2" 2026-10-22T12:00:00Z "$3"' _ "$S46_LIB" "$TL_H" "$TL_RD/t22.md")"
tl_plant "$(bash -c '. "$1" && proof_line walk "$2" 2026-10-22T12:00:00Z "$3"' _ "$S46_LIB" "$TL_H" "$TL_RD/walk.md")"
TL_ROWS1="$(/usr/bin/grep -E '^(\| T2[1-5] |- T2[1-5]:)' "$TL_P")"
poke "$TL" tick
expect_eq "TL-8 registered, each lands at the next tick: one published event of the record kind at the working head" "landed 1|landed 1" \
  "$(tl_state T22) $(tl_pub T22)|$(tl_state T23) $(tl_pub T23)"
expect_eq "TL-9 …and no row or step line of theirs is written" "$TL_ROWS1" "$(/usr/bin/grep -E '^(\| T2[1-5] |- T2[1-5]:)' "$TL_P")"
expect_eq "TL-9b …the rows read as they did before any tick" "$TL_ROWS0" "$TL_ROWS1"
expect_eq "TL-10 T22 landed, T25 is ready" "T25" "$(cd "$TL" && bash -c '. "$1/fill.sh" >/dev/null 2>&1; fill_ready_set "$2" 99999 0' _ "$(dirname "$S46_LIB")" "$TL_P" 2>/dev/null | /usr/bin/grep -x T25)"
poke "$TL" tick
expect_eq "TL-11 a landed row is not landed twice" "1 1" "$(tl_pub T22) $(tl_pub T23)"
# A live review row lands only once the judge reads every question it carries covered at the working head. T11 and T12,
# a run at 15 (`vc_15`) launched by its log, carry the questions adversarial and structure, their readings at the head
# seeded in the log; T12's writer ends only after a code commit past the readings.
LV="$(make_repo tick-live)"; ( cd "$LV" && git commit -q --allow-empty -m base && git branch -M main ) >/dev/null 2>&1
git -C "$LV" config user.name "Dana Fixture"
LV_BASE="$(git -C "$LV" rev-parse main)"; LV_RD="record/wave-01-fixture"; LV_D="$LV/.bionic/docs/$LV_RD"
LV_P="$(vc_plan "$LV" \
  "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | lib/a.sh | landed | — | — |" \
  "| T11 | 6 | review | the adversarial review · questions: adversarial | w-T11 | — | 30 | REQ-1 | .bionic/docs/$LV_RD/live-adversarial.md | active | — | .bionic/docs/$LV_RD/live-adversarial.md |" \
  "| T12 | 6 | review | the structure review · questions: structure | w-T12 | — | 30 | REQ-1 | .bionic/docs/$LV_RD/live-structure.md | active | — | .bionic/docs/$LV_RD/live-structure.md |")"
vc_15 "$LV" "$LV_P"; sed "s/^base-sha: abc1234$/base-sha: $LV_BASE/" "$LV_P" > "$LV_P.t" && mv "$LV_P.t" "$LV_P"
( cd "$LV" && git add -f "$LV_P" && git commit -qm base-sha ) >/dev/null 2>&1
LV_H="$(git -C "$LV" rev-parse main)"
for lv_q in evidence adversarial structure; do
  printf 'question: %s\nresult: pass\nscope: piece\nreviewed: %s..%s\nfindings: 0\n' "$lv_q" "${LV_BASE:0:10}" "${LV_H:0:10}" > "$LV_D/live-$lv_q.md"
  LV_PL="$(bash -c '. "$1" && proof_line review "$2" 2026-10-22T12:00:00Z "$3" "$4" w-crit pass piece' _ "$S46_LIB" "$LV_H" "$LV_RD/live-$lv_q.md" "$lv_q")"
  sp_fact "$LV_P" "$LV_PL"
done
new_roster "$LV"
add_row "$LV" name=w-T11 deliverable="$LV_D/live-adversarial.md" duration="1 minute" launched_at="$(iso_ago 600)"
add_row "$LV" name=w-T12 deliverable="$LV_D/T12-done.md" duration="1 minute" launched_at="$(iso_ago 600)"
lv_state() { ( . "$(dirname "$S46_LIB")/units.sh" >/dev/null 2>&1; units_rows "$LV_P" ) | awk -F'\t' -v r="$1" '$1 == r { print $10 }'; }
lv_pub() { cat "$LV_D/run.log" 2>/dev/null | /usr/bin/grep -c "^run/v1|ev=published|row=$1|.*|kind=record|"; }
poke "$LV" tick
expect_eq "TL-12 a launched live review row whose question the judge reads covered lands at the tick, one published event"   "landed 1" "$(lv_state T11) $(lv_pub T11)"
LV_X="$(s57_commit "$LV" lib/x.sh 'a code change past every reading')"; printf 'done
' > "$LV_D/T12-done.md"
poke "$LV" tick
expect_contains "TL-13 past a code commit its sibling's question is not covered: not landed, the tick says why, naming it"   "structure uncovered" "$(printf '%s
' "$OUT" | /usr/bin/grep '^poker: NOT-LANDED T12 ')"
poke "$LV" tick
expect_eq "TL-14 …said once, and the row stays active and unpublished" "0 active 0"   "$(printf '%s
' "$OUT" | /usr/bin/grep -c 'NOT-LANDED T12') $(lv_state T12) $(lv_pub T12)"

# A PAGE AT 15: the orchestrator's integrate row reads its reviews through the judgment the tick makes of the run's
# facts at the working head, so the tick lands it once those stand. FIXTURE FIDELITY: plan_fixture's page at 15 at
# step 8, the build row landed and the integrate row pending, its record under record/ its Files name; the floor and
# the reviews its rigor deals written as proof events at the working branch's head by the proof library's writer.
# fails-when: the tick never offers the integrate row, so it neither lands nor names it.
TI="$(make_repo tick-integrate15)"
( cd "$TI" && git commit -q --allow-empty -m base && git branch -M main && git branch wave/01-fixture ) >/dev/null 2>&1
TI_H="$(git -C "$TI" rev-parse wave/01-fixture)"; TI_RD="record/wave-01-fixture"
TI_P="$(plan_fixture --current 8 "$TI/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" task \
  "| T1 | 4 | build | the build | implementor | — | — | 30 | REQ-1 | lib/a.sh | — | — | landed |" \
  "| T5 | 8 | integrate | merge into main | — | — | — | 10 | REQ-1 | .bionic/docs/$TI_RD/T5-pr.md | — | — | pending |")"
sed -i '' "s/^base-sha: abc1234$/base-sha: $TI_H/" "$TI_P"
printf '# T5: the pull request\n' > "$TI/.bionic/docs/$TI_RD/T5-pr.md"
bash -c '. "$1" || exit 1; p="$2" h="$3" d="$4"
  LOG_AT=2026-10-04T12:00:00Z proof_event "$p" kind=regression "head=$h" "evidence=$d/floor.log" || exit 1
  for q in evidence adversarial structure; do
    LOG_AT=2026-10-04T12:00:00Z proof_event "$p" kind=review "head=$h" "evidence=$d/$q-piece.md" "question=$q" reader=w-read result=pass scope=piece || exit 1
  done' _ "$S46_LIB" "$TI_P" "$TI_H" "$TI_RD"
new_roster "$TI"
TI_PUB() { /usr/bin/grep -c "^run/v1|ev=published|row=T5|commit=$TI_H|kind=record|by=orchestrator|" "$(plan_fixture_log "$TI_P")"; }
expect_eq "TL-15 precondition: the page is at 15, its integrate row pending and unlanded, its four proofs at the head" "15|pending|0|4" \
  "$(sed -n 's/^canonical_sdlc_version: //p' "$TI_P")|$(bash "$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh" "$TI_P" status T5 | sed -n 's/^state=//p')|$(TI_PUB)|$(/usr/bin/grep -c "|ev=proof|kind=[a-z]*|head=$TI_H|" "$(plan_fixture_log "$TI_P")")"
poke "$TI" tick
expect_eq "TL-16 on a page at 15 the tick lands the orchestrator's integrate row whose reviews stand: one published event of the record kind" \
  "1|1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c "^poker: LANDED T5 — the orchestrator's integrate row")|$(TI_PUB)"

# ============================================================
section "§STACK: the regression's health is the judge's rendering, and no verb writes it into the plan"
# ============================================================
# `proof-add regression` registers the whole run's proof and leaves the plan's text as it was; lib/proof.sh
# `proof_health_line` renders the health the sheet and the card print: green only at a pass that left nothing owed.
# FIXTURE FIDELITY. §COPIED-LOG's shape at Step 5, a run at 15; run lines from regression_fixture; every later write goes
# through a real verb.
VT_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RVT="$(make_repo verdicts)"; ( cd "$RVT" && git commit -q --allow-empty -m init )
git -C "$RVT" config user.name "Dana Fixture"
VT_B="$(git -C "$RVT" rev-parse HEAD)"
PVT="$(s42_plan "$RVT" 5 "  worktree: .worktrees/01-fixture
  base-sha: ${VT_B:0:8}
  branch: wave/01-fixture")"
s42_builds_landed "$PVT"
vt_rigor() { sed "s/^rigor: .*/rigor: $1/" "$PVT" > "$PVT.tmp" && mv "$PVT.tmp" "$PVT"; }
git -C "$RVT" worktree add -q -b wave/01-fixture "$RVT/.worktrees/01-fixture" "$VT_B" >/dev/null 2>&1
VT_WT="$RVT/.worktrees/01-fixture"; VT_DIR="$RVT/.bionic/docs/record/wave-01-fixture"; mkdir -p "$VT_DIR"
VT_A="$(s57_commit "$VT_WT" lib/a.sh A)"
new_roster "$RVT"
vt_rigor single

# ---------- §STACK: the health line is the judge's rendering, written by one function ----------
# The grammar: `green head=<F>` only when the whole run at F left nothing owed; otherwise `red head=<F> … owed=<the
# suites still owed> [closed=<the suites later green landings closed>]`. A landing never turns the line green: green
# means the full pass ran green at that head, so a red pass whose suites were all closed still reads red, owed= empty.
vt_sh_line() {  # <green|red> <head> <pass> <total> <evidence> [<owed>] [<closed>] -> the line the function renders
  local o=""; [ "$1" = green ] || o=" owed=${6:-}${7:+ closed=$7}"
  printf 'stack-health: %s head=%s pass=%s total=%s%s evidence=%s' "$1" "$2" "$3" "$4" "$o" "$5"
}
vt_health() {  # -> lib/proof.sh proof_health_line on the fixture plan, as `stack-health: <value>`
  printf 'stack-health: %s' "$(bash -c '. "$1/roots.sh" >/dev/null 2>&1; . "$1/proof.sh" >/dev/null 2>&1 && proof_health_line "$2" "$3"' \
    _ "${S46_LIB%/*}" "$PVT" "$RVT")"
}
expect_eq "VT-12a §STACK AC-5.2 a plan with no regression proof renders pending" "stack-health: pending" "$(vt_health)"
VT_SH0="$(cksum < "$PVT")"
VT_C="$(s57_commit "$VT_WT" lib/b.sh C)"
printf 'Gating: 2 passed, 1 failed\nFailed:\n    - c.test.sh\n' | regression_fixture "$PVT" "$VT_DIR/whole-red.log" "$VT_C" 0 1
poke "$RVT" proof-add regression record/wave-01-fixture/whole-red.log
expect_eq "VT-12 §STACK AC-7.1 a red regression proof (exit 0) renders red, its pass having left c.test.sh owed, with its head, pass and total; the plan's bytes are unchanged" \
  "0|$(vt_sh_line red "$VT_C" 2 3 record/wave-01-fixture/whole-red.log c.test.sh)|$VT_SH0" "$RC|$(vt_health)|$(cksum < "$PVT")"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
VT_E="$(s57_commit "$VT_WT" lib/d.sh E)"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture "$PVT" "$VT_DIR/whole-na.log" "$VT_E" 0 0
poke "$RVT" proof-add regression record/wave-01-fixture/whole-na.log
expect_eq "VT-15 AC-5.2 the function renders green at the head of a pass that left nothing owed" \
  "$(vt_sh_line green "$VT_E" 3 3 record/wave-01-fixture/whole-na.log)" "$(vt_health)"
# A red pass at G owing c.test.sh, then a landing H whose run greens c.test.sh: the judge covers H, the line stays red.
VT_G="$(s57_commit "$VT_WT" lib/e.sh G)"
printf 'Gating: 2 passed, 1 failed\nFailed:\n    - c.test.sh\n' | regression_fixture "$PVT" "$VT_DIR/whole-red2.log" "$VT_G" 0 1
poke "$RVT" proof-add regression record/wave-01-fixture/whole-red2.log
expect_eq "VT-16 a red proof at G (exit 0): before any landing the function renders red, c.test.sh owed and nothing closed" \
  "0|$(vt_sh_line red "$VT_G" 2 3 record/wave-01-fixture/whole-red2.log c.test.sh)" "$RC|$(vt_health)"
VT_H="$(s57_commit "$VT_WT" lib/f.sh H)"
bash -c '. "$1/line.sh" >/dev/null 2>&1 && line_event "$2" verdict row=T2 "commit=$3" suite=c.test.sh result=green log=-' \
  _ "${S46_LIB%/*}" "$PVT" "$VT_H"
expect_eq "VT-17 precondition: the judge covers H, the landing's green having closed the suite G owed" "covered" \
  "$(bash -c '. "$1/roots.sh" >/dev/null 2>&1; . "$1/proof.sh" >/dev/null 2>&1 && proof_state "$2" "$3"' _ "${S46_LIB%/*}" "$PVT" "$RVT" | cut -f1)"
expect_eq "VT-17b AC-5.2 …and the function still renders red at G, owed= empty and closed= naming the suite the landing closed" \
  "$(vt_sh_line red "$VT_G" 2 3 record/wave-01-fixture/whole-red2.log "" c.test.sh)" "$(vt_health)"
POKE_BOUND="$VT_BOUND_WAS"

# ============================================================
section "§STARTER: the tick starts the whole run itself when nothing is ready, no writer is open and the head is past the last regression proof"
# ============================================================
# The tick starts `regression-run --starter tick` detached through booked.sh as roster object `regression@<h8>`, whose
# one suite is run.sh, never waiting; the proof lands through proof-add regression. A landing past it moves the head, so
# the next tick starts again. A live object guards against a second start; a run the gate did not admit (75) is told as
# waiting and started again.
# FIXTURE FIDELITY: §STACK's shape at Step 4, with a regression proof at an older head from proof-add over a run line
# from regression_fixture. The runner is the worktree's committed tests/run.sh stub: it holds while a hold file stands,
# exits 75 with no verdict while a full file stands, else reports a green whole run; it books nothing at the gate, so the
# open whole request beside it is the verb's own. Everything else is real, and the writer row is mkrow's, closed by the
# real ack.
# fails-when: the quiet condition inverted; the head compared to anything but the last regression proof's; proof-add
# dropped from the detached call; a live object not stopping a second start; a 75 not told and not started again; the
# verb filing no whole request for its run, with or without regression-command:, or not ending it.
ST_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RST="$(make_repo starter)"; ( cd "$RST" && git commit -q --allow-empty -m init )
git -C "$RST" config user.name "Dana Fixture"
ST_CTL="$TMPROOT/starter-ctl"; mkdir -p "$ST_CTL"
mkdir -p "$RST/tests"
cat > "$RST/tests/run.sh" <<RUNNER
#!/bin/bash
# The fixture's whole run: marks its start, holds while the hold file stands, exits 75 with no verdict while the full file stands.
: > "$ST_CTL/ran"; i=0; while [ -e "$ST_CTL/hold" ] && [ "\$i" -lt 600 ]; do i=\$((i + 1)); sleep 0.1; done
[ ! -e "$ST_CTL/full" ] || exit 75
printf 'Gating: 1 passed, 0 failed\n'
RUNNER
( cd "$RST" && git add tests/run.sh && git commit -qm runner ) >/dev/null 2>&1
ST_B="$(git -C "$RST" rev-parse HEAD)"
PST="$(s42_plan "$RST" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${ST_B:0:8}
  branch: wave/01-fixture")"
git -C "$RST" worktree add -q -b wave/01-fixture "$RST/.worktrees/01-fixture" "$ST_B" >/dev/null 2>&1
ST_WT="$RST/.worktrees/01-fixture"; ST_DIR="$RST/.bionic/docs/record/wave-01-fixture"; mkdir -p "$ST_DIR"
ST_H0="$(s57_commit "$ST_WT" lib/a.sh H0)"
printf 'Gating: 1 passed, 0 failed\n' | regression_fixture "$PST" "$ST_DIR/whole-h0.log" "$ST_H0" 0 0
poke "$RST" proof-add regression record/wave-01-fixture/whole-h0.log
expect_eq "ST-0 precondition: the plan holds a regression proof at H0 (proof-add exit 0)" "0|$ST_H0" "$RC|$(s46_last "$PST" regression)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
ST_H1="$(s57_commit "$ST_WT" lib/a.sh H1)"
new_roster "$RST"
add_row "$RST" name=w-T2 agent_id=a-w-T2 subagent_type=implementor launched_at="$(iso_ago 60)" deliverable="$RST/record/T2.md" duration=60m
st_started() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: regression-run started ' ; }
st_waiting() { printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: regression-run waiting — the gate has no room for a whole run$'; }
st_objects() { /usr/bin/grep -F "|name=regression@$1|" "$(roster_of "$RST")" 2>/dev/null; }
st_log() { printf '%s/.bionic/tmp/runs/regression_%s-run.sh%s.log' "$(cd "$RST" && pwd -P)" "$1" "${2:-}"; }   # <h8> [-<n>]
st_starts() { st_objects "$1" | tr '|' '\n' | /usr/bin/grep '^run_log=' | sort -u | awk 'END { print NR + 0 }'; }   # <h8> -> its distinct runs
st_until() {  # <seconds> <command>… -> rc 0 once the command holds, 1 when the time runs out
  local n=$(( $1 * 10 )); shift
  while [ "$n" -gt 0 ]; do "$@" && return 0; n=$((n - 1)); sleep 0.1; done
  return 1
}
st_ended() { [ -s "$1.rc" ]; }
st_rec() { bash -c '. "$1/payload/scripts/lib/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "$BIONIC_SCRIPTS_DIR" "$PST"; }
st_runline() { cat "$(st_rec)" 2>/dev/null | /usr/bin/grep -F "|ev=run|log=$1|" | tail -n 1; }   # <log from its root> -> its run line
: > "$ST_CTL/hold"

# Each tick below but one forgets the last digest, so it prints in full and a line it did not print is a
# line it did not say. The one that keeps it (ST-6) is the tick whose only news is the start itself.
# The control: T2 still writes (its row active, its writer open on the roster), so nothing starts.
forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-1-pre the control tick printed its decision line (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker-tick/v1|')"
expect_eq "ST-1 AC-6.1 control: with a writer row running, the tick starts nothing and the roster holds no object" "|" "$(st_started)|$(st_objects "${ST_H1:0:8}")"

# Quiet: every row landed, the writer closed by its ack, the head past the proof.
s42_builds_landed "$PST"; printf 'run/v1|ev=published|row=T5|at=2026-10-04T00:31:00Z\n' >> "$(plan_fixture_log "$PST")"
ack_rows "$RST" w-T2
# A whole run the orchestrator's verb started leaves no log and no object until it ends; the open whole request the verb
# itself files at the gate is the one fact of it, nothing planted. Its runner ends 75 here, so it leaves no log at H1 and
# the tick after it starts (ST-2). st_beside <h8> <label> runs the tick and a second verb beside the running one.
st_open() { bash -c '. "$1/payload/scripts/lib/gate.sh" && gate_whole_open "$2"' _ "$BIONIC_SCRIPTS_DIR" "$ST_WT"; }
st_beside() {
  rm -f "$ST_CTL/ran"; ( cd "$RST" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" regression-run ) > "$TMPROOT/st-rr.out" 2>&1 &
  ST_RR=$!
  expect_true "$2-pre the verb's command is running, held" st_until 30 test -e "$ST_CTL/ran"
  expect_true "$2a AC-19.1 …and the gate holds an open whole request for the checkout while it runs" st_open
  forget_digest "$RST"; poke "$RST" tick
  expect_nonempty "$2b-pre the tick beside it printed its decision line" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker-tick/v1|')"
  expect_eq "$2b AC-19.1 the tick beside the verb's running whole run starts no whole run and no object" "|" "$(st_started)|$(st_objects "$1")"
  poke "$RST" regression-run
  expect_eq "$2c AC-19.1 …and a second regression-run beside it is refused (exit 1), naming the open whole request" "1|yes" \
    "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -q 'open whole request' && echo yes)"
  rm -f "$ST_CTL/hold"; wait "$ST_RR"
  expect_false "$2d …and the verb ended its request when its command ended" st_open
  : > "$ST_CTL/hold"
}
: > "$ST_CTL/full"; st_beside "${ST_H1:0:8}" ST-1; rm -f "$ST_CTL/full"
forget_digest "$RST"; poke "$RST" tick
expect_contains "ST-2 AC-6.1 AC-19.2 nothing ready, no writer open, the head past the proof: the tick starts regression-run as regression@<h8>" \
  "poker: regression-run started regression@${ST_H1:0:8} (log $(st_log "${ST_H1:0:8}"))" "$(st_started)"
[ -n "$(st_started)" ] || printf '      the tick said: %s\n' "$OUT"
expect_contains "ST-2b …and the roster holds the object: a run row, its one suite run.sh, a read-only role, waived as no agent" "|status=run|" "$(st_objects "${ST_H1:0:8}" | head -n 1)"
expect_contains "ST-2c …whose budget is run.sh, so the gate's whole-run budget admits it" "|suites_allowed=run.sh|" "$(st_objects "${ST_H1:0:8}" | head -n 1)"
expect_true "ST-2d …and booked.sh marks the run on it (run_pid=)" st_until 20 eval 'st_objects "${ST_H1:0:8}" | /usr/bin/grep -q "|run_pid="'
expect_true "ST-2e …and the tick did not wait on it: the run is still held by the runner when the tick has returned" test ! -e "$(st_log "${ST_H1:0:8}").rc"

# The guard: a live object for this head means the next tick starts nothing beside it.
forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-3-pre the guard tick names the live run (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep "^poker: RUNNING regression@${ST_H1:0:8} run=")"
expect_eq "ST-3 a live regression@<h8> object: the next tick starts nothing, and the roster still names one run" "|1" "$(st_started)|$(st_starts "${ST_H1:0:8}")"
rm -f "$ST_CTL/hold"
expect_true "ST-4-pre the detached run ends once the runner is let go" st_until 60 st_ended "$(st_log "${ST_H1:0:8}")"
expect_eq "ST-4 AC-6.3 the started run leaves its proof in the plan through proof-add: proved: kind=regression head=<H1>" "1" \
  "$(s46_proved "$PST" | /usr/bin/grep -c "^proved: kind=regression head=$ST_H1 ")"
[ "$(s46_proved "$PST" | /usr/bin/grep -c "^proved: kind=regression head=$ST_H1 ")" = 1 ] || sed -n '1,40p' "$(st_log "${ST_H1:0:8}")"
expect_contains "ST-4b …from a run whose run line names the tick as its starter" "|starter=tick|" "$(st_runline "record/wave-01-fixture/regression-run-$ST_H1.log")"
expect_contains "ST-4c …and booked.sh's own run line for the detached run carries the command's --starter too" "|starter=tick|" "$(st_runline ".bionic/tmp/runs/regression_${ST_H1:0:8}-run.sh.log")"
forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-5-pre the tick at the proved head printed its decision line" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker-tick/v1|')"
expect_eq "ST-5 control: the head is the last proof's, so nothing starts" "" "$(st_started)"
# Green is content: a docs commit past the green whole run is the pass's head, so the tick starts nothing at it.
ST_HD="$(s57_commit "$ST_WT" README.md D1)"; forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-5b-pre the tick at the docs head printed its decision line" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker-tick/v1|')"
expect_eq "ST-5b AC-1.4 one docs commit past the green run: the printer reads green at it, and the tick starts no run and no object" \
  "green at ${ST_H1:0:8}, 1 landing since moved no code||" \
  "$(bash -c '. "$1/payload/scripts/lib/roots.sh" && . "$1/payload/scripts/lib/proof.sh" && proof_whole_text "$2" "$3"' _ "$BIONIC_SCRIPTS_DIR" "$PST" "$RST")|$(st_started)|$(st_objects "${ST_HD:0:8}")"

# A fix row lands code past the proof, the docs commit and all: the head reads red, so the next tick starts again
# there, which is what held the start above. The runner is full first, so the run ends 75 with no verdict, and the
# tick after it says so and starts it again.
: > "$ST_CTL/full"
ST_H2="$(s57_commit "$ST_WT" lib/b.sh H2)"
poke "$RST" tick
expect_contains "ST-6 AC-6.2 a landing past the proof: the next tick starts again at the new head" "poker: regression-run started regression@${ST_H2:0:8} " "$(st_started)"
expect_true "ST-6b …its run ends 75, the gate's word that nothing ran" st_until 60 st_ended "$(st_log "${ST_H2:0:8}")"
expect_eq "ST-6c …read off its log's end" "75" "$(cat "$(st_log "${ST_H2:0:8}").rc" 2>/dev/null)"
rm -f "$ST_CTL/full"
forget_digest "$RST"; poke "$RST" tick
expect_eq "ST-7 the tick after a 75 says the gate had no room, once" "1" "$(st_waiting)"
expect_contains "ST-7b …and starts the run again at the same head, as a second attempt" "poker: regression-run started regression@${ST_H2:0:8} (log $(st_log "${ST_H2:0:8}" -2))" "$(st_started)"
ST_LOG2="$(st_started | sed -n 's/^.*(log \(.*\))$/\1/p')"
expect_true "ST-7c …which ends" st_until 60 st_ended "${ST_LOG2:-$TMPROOT/none}"
expect_eq "ST-7d …with its proof at the new head" "1" "$(s46_proved "$PST" | /usr/bin/grep -c "^proved: kind=regression head=$ST_H2 ")"
# The same beside a configured command: regression-command: names the stub, and the verb books its run as for none.
ST_H3="$(s57_commit "$ST_WT" lib/c.sh H3)"; printf 'regression-command: bash tests/run.sh\n' > "$RST/.bionic/config.yaml"
: > "$ST_CTL/hold"; st_beside "${ST_H3:0:8}" ST-8; rm -f "$ST_CTL/hold" "$RST/.bionic/config.yaml"
POKE_BOUND="$ST_BOUND_WAS"


# ============================================================
section "§WALK: a walk's record discharges each criterion it confirms by one proof naming it, the plan unwritten"
# ============================================================
# The walk record carries the critic's shape, read by proof_verdicts. `proof-add walk <record>` appends one walk proof
# and, for each CONFIRMED row, one proof naming the criterion with the record as its evidence; the plan is not written.
# A run has one walk record and it only grows: a record that leaves out a criterion a standing walk confirms is refused,
# naming the rows left out. It appends one `ev=walk` line, so the hand-holds fold counts no status write.
# FIXTURE FIDELITY. §STACK's shape with `walk: required` and three pending criteria in its Eval design.
WK_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RWK="$(make_repo walk)"; ( cd "$RWK" && git commit -q --allow-empty -m init )
git -C "$RWK" config user.name "Dana Fixture"
WK_B="$(git -C "$RWK" rev-parse HEAD)"
PWK="$(s42_plan "$RWK" 5 "  worktree: .worktrees/01-fixture
  base-sha: ${WK_B:0:8}
  branch: wave/01-fixture")"
s42_builds_landed "$PWK"
printf '| REQ-1 | fixture | AC-1.%s | hermetic | `tests/%s.test.sh` | %s is wrong |\n' 2 b b 3 c c >> "$PWK"
sed -e 's/^rigor: .*/rigor: single/' -e 's/^walk: .*/walk: required/' "$PWK" > "$PWK.tmp" && mv "$PWK.tmp" "$PWK"
( cd "$RWK" && git add -f "$PWK" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RWK/.worktrees/01-fixture" "$WK_B" ) >/dev/null 2>&1
WK_WT="$RWK/.worktrees/01-fixture"; WK_DIR="$RWK/.bionic/docs/record/wave-01-fixture"; mkdir -p "$WK_DIR"
WK_A="$(s57_commit "$WK_WT" lib/a.sh A)"
WK_C="$(s57_commit "$WK_WT" lib/c.sh C)"
wk_cell() {  # <AC> -> `<state> <by> <evidence>` through the reader's one answer for every criterion
  bash -c '. "$1/reader.sh" && reader_cells "$2"' _ "${S46_LIB%/*}" "$PWK" 2>/dev/null | awk -F'\037' -v c="$1" '$1 == c { print $2 " " $3 " " $5 }'
}
wk_recfile() { bash -c '. "$1/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "${S46_LIB%/*}" "$PWK"; }
wk_ev() { cat "$(wk_recfile)" 2>/dev/null | /usr/bin/grep -F "|ev=$1|"; }   # <ev> -> its lines in the record, the run's log
wk_rec() {  # <name> <verdict: line or -> [<head: line or ->] [<table row>...] -> a walk record
  local f="$WK_DIR/$1.md" v="$2" h="$3" r; shift 3
  { printf '# walk\n\nwalker: wk-walker\n'; [ "$h" = - ] || printf '%s\n' "$h"
    printf '\n## 1. The cards\n\nIt printed whole with rc 0.\n\n## Verdicts\n\n'
    if [ "$#" -gt 0 ]; then printf '| AC | verdict | why |\n|---|---|---|\n'; for r in "$@"; do printf '%s\n' "$r"; done; fi
    [ "$v" = - ] || printf '\n%s\n' "$v"
    printf '\nwhat the walk found\n'; } > "$f"
}
wk_add() { poke "$RWK" proof-add walk "record/wave-01-fixture/$1.md"; }
WK_ROWS=('| AC-1.1 | CONFIRMED | the card printed whole |' '| AC-1.2 | CONFIRMED | the continuation read the judge |'
  '| AC-1.3 | REFUTED | the scorecard read the ledger |')

( cd "$RWK" && git add -f "$PWK" && git commit -qm settled ) >/dev/null 2>&1
expect_eq "WK-0 precondition: the three criteria read pending" "pending  |pending  |pending  " "$(wk_cell AC-1.1)|$(wk_cell AC-1.2)|$(wk_cell AC-1.3)"
WK_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; sleep 1

# ---------- the walk record is read by the critic's reader ----------
wk_rec walk-notable 'verdict: CONFIRMED — the cards read the judge' -
s42_snap "$RWK" "$PWK"; wk_add walk-notable
s42_unchanged "WK-1 §WALK AC-8.1 a walk record with no AC | verdict table (prose sections only, wave 45's shape)" 1 "$PWK"
expect_contains "WK-1b …refused naming the shape it needs" "the columns AC and verdict" "$OUT"
wk_rec walk-noverdict - - "${WK_ROWS[@]}"
wk_add walk-noverdict
s42_unchanged "WK-2 AC-8.1 a walk record with the table and no verdict: line" 1 "$PWK"
expect_contains "WK-2b …refused naming the verdict: line" "verdict:" "$OUT"

# ---------- one registration: the walk's proof and one proof per criterion it confirms, the plan unwritten ----------
wk_rec walk 'verdict: REFUTED — AC-1.3 is refuted' - "${WK_ROWS[@]}"
WK_SUM="$(cksum < "$PWK")"; wk_add walk
expect_eq "WK-3 §WALK AC-8.1 AC-8.2 the record with the table and one verdict: line registers (exit 0), the plan byte for byte as it was" "0|$WK_SUM" "$RC|$(cksum < "$PWK")"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "WK-4 AC-8.2 each CONFIRMED criterion reads discharged by a proof naming the walk record; the REFUTED one stays pending" \
  "discharged proof record/wave-01-fixture/walk.md|discharged proof record/wave-01-fixture/walk.md|pending  " \
  "$(wk_cell AC-1.1)|$(wk_cell AC-1.2)|$(wk_cell AC-1.3)"
expect_eq "WK-8 AC-8.2 one walk proof at the working head, naming the record" "1" \
  "$(s46_proved "$PWK" | /usr/bin/grep -c "^proved: kind=walk head=$WK_C at=[0-9TZ:-]* evidence=record/wave-01-fixture/walk.md$")"
expect_eq "WK-9 AC-8.2 the run's log gains one ev=walk line, naming the record and the two criteria it discharged" "1" \
  "$(wk_ev walk | /usr/bin/grep -c '|record=record/wave-01-fixture/walk.md|discharged=2|at=')"
poke "$RWK" landing-report --hand-holds --since "$WK_SINCE"
expect_contains "WK-10 AC-8.2 the hand-holds fold over the walk's window reads no hand-hold: registering the walk is the machine's act" "hand-holds: total=0 " "$OUT"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"

# A run has one walk record and it only grows: a second record, at another head, that leaves out a criterion the
# standing walk confirms is refused, nothing appended; the whole record registered again carries each proof to it.
wk_rec walk-again 'verdict: CONFIRMED — every card read the judge' "head: $WK_A" \
  '| AC-1.2 | CONFIRMED | again |' '| AC-1.3 | CONFIRMED | refixed |'
WK_LOG0="$(wc -l < "$WK_DIR/run.log" | tr -d ' ')"; wk_add walk-again
expect_eq "WK-11 a record that leaves out AC-1.1, which the standing walk confirms, is refused (exit 1), nothing appended" \
  "1|$WK_LOG0|discharged proof record/wave-01-fixture/walk.md" "$RC|$(wc -l < "$WK_DIR/run.log" | tr -d ' ')|$(wk_cell AC-1.1)"
expect_contains "WK-11b …naming the row left out and the fix" "leaves out AC-1.1, which the standing walk confirms" "$OUT"
wk_rec walk-again 'verdict: CONFIRMED — every card read the judge' "head: $WK_A" \
  '| AC-1.1 | CONFIRMED | again |' '| AC-1.2 | CONFIRMED | again |' '| AC-1.3 | CONFIRMED | refixed |'
wk_add walk-again
expect_eq "WK-11c the whole record registers at its head: line's head (exit 0), and every criterion's proof names it" \
  "0|1|discharged proof record/wave-01-fixture/walk-again.md|discharged proof record/wave-01-fixture/walk-again.md|discharged proof record/wave-01-fixture/walk-again.md" \
  "$RC|$(s46_proved "$PWK" | /usr/bin/grep -c "^proved: kind=walk head=$WK_A .* evidence=record/wave-01-fixture/walk-again.md$")|$(wk_cell AC-1.1)|$(wk_cell AC-1.2)|$(wk_cell AC-1.3)"
wk_rec walk-nohead 'verdict: CONFIRMED — fine' "head: 0123456789012345678901234567890123456789" '| AC-1.2 | CONFIRMED | — |'
s42_snap "$RWK" "$PWK"; wk_add walk-nohead
s42_unchanged "WK-12 a head: line naming no commit of the working branch" 1 "$PWK"
expect_contains "WK-12b …named in the refusal" "head: 0123456789012345678901234567890123456789" "$OUT"

POKE_BOUND="$WK_BOUND_WAS"

section "§BORN-RED: a floor-born marker is admitted on the red verdict a whole run recorded, and the refusal names the log to record"
# fails-when: the verdict backing is dropped (BR-1), a green or off-branch verdict backs it (BR-2), or the refusal misnames the log (BR-3 to BR-5).
# FIXTURE FIDELITY: §GONE-BORN's plan and branch with no proof line, verdict lines as proof_regression_fold writes them, logs as _proof_floor_log reads.
BR_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RBR="$(make_repo born-red)"; ( cd "$RBR" && git commit -q --allow-empty -m init ); BR_C1="$(git -C "$RBR" rev-parse HEAD)"
BR_TREE="$(git -C "$RBR" rev-parse "${BR_C1}^{tree}")"; BR_C2="$(git -C "$RBR" commit-tree "$BR_TREE" -p "$BR_C1" -m second)"
BR_OFF="$(git -C "$RBR" commit-tree "$BR_TREE" -m off-branch)"; git -C "$RBR" update-ref refs/heads/wave/01-fixture "$BR_C2"
PBR="$(s42_plan "$RBR" 4 $'  worktree: .worktrees/01-fixture\n  base-sha: abc1234\n  branch: wave/01-fixture\n  working-branch: wave/01-fixture')"
( cd "$RBR" && git add -f "$PBR" && git commit -qm plan ) >/dev/null 2>&1; BR_DIR="$RBR/.bionic/docs/record/wave-01-fixture"; mkdir -p "$BR_DIR"
br_verdict() { printf 'run/v1|ev=verdict|row=regression|commit=%s|suite=%s|result=%s|log=-|admitted=-|width=-|kind=regression|at=2026-11-04T10:00:00Z\n' "$1" "$2" "$3" >> "$BR_DIR/run.log"; }
br_log() { printf 'head=%s dirty=%s\nGating: 1 passed, 1 failed\nrc=%s\n' "$1" "$2" "$3" > "$BR_DIR/regression-run-$1.log"; touch -t "$4" "$BR_DIR/regression-run-$1.log"; }  # <sha> <dirty> <rc> <mtime>
br_add() { ta_add "$RBR" "$1" 4 build 'fix the red. The red suite turns green.' bionic:implementor '—' 30 REQ-5 "lib/$1.sh" --born "regression:$2"; }
br_verdict "$BR_C1" a.test.sh red; br_add T6 a.test.sh
expect_eq "BR-1 a red verdict at a branch commit and no proof line: task-add --born regression:a.test.sh exits 0, the born event reading the run" "0|1" \
  "$RC|$(/usr/bin/grep -c "|ev=born|row=T6|reason=regression a.test.sh|finding=run@${BR_C1:0:12}|" "$BR_DIR/run.log")"
br_verdict "$BR_C1" b.test.sh green; br_add T7 b.test.sh; BR_RC=$RC
br_verdict "$BR_OFF" c.test.sh red; br_add T7 c.test.sh
expect_eq "BR-2 a green verdict, and a red one at a commit off the branch, back nothing (exit 1 each)" "1|1" "$BR_RC|$RC"
br_log "$BR_C1" 0 0 202611040900; br_log "$BR_C2" 1 1 202611040910; br_log "$BR_OFF" 0 1 202611040920; br_add T7 d.test.sh
expect_eq "BR-3 no verdict and only a green, a dirty and an off-branch log: refused in today's words, naming no log" "1|1|0" \
  "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'it owes nothing')|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'proof-add regression record/')"
br_log "$BR_C1" 0 1 202611040930; br_add T7 d.test.sh
expect_contains "BR-4 a red log on the branch: the refusal names the proof-add line with it" \
  "proof-add the red run's log first: bash ${BIONIC_HOOKS_DIR}/session-poker.sh proof-add regression record/wave-01-fixture/regression-run-${BR_C1}.log" "$OUT"
br_log "$BR_C2" 0 2 202611041000; br_add T7 d.test.sh
expect_eq "BR-5 two red logs on the branch: the newer is named, the older not" "1|0" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c "regression-run-${BR_C2}.log")|$(printf '%s\n' "$OUT" | /usr/bin/grep -c "regression-run-${BR_C1}.log")"
POKE_BOUND="$BR_BOUND_WAS"

finish
