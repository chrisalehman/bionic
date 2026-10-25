#!/bin/bash
# Tests for hooks/session-poker.sh — shard 4 of 4: §SEV to the end.
#
# THE SUITE IS FOUR SHARDS (wave-30 T2; design-ledger Δ7, D8). Its governing design, its
# hermetic posture and its clock discipline are written once, in tests/session-poker.test.sh's
# header; the sandbox, the pins and the shared fixture builders are
# tests/session-poker.prelude.sh, sourced below after the framework and the POKER seam.
#
# SPLIT WHERE NO FIXTURE CROSSES. §SEV builds the repository nine later sections read:
# §RC-DEFER, §CHECK-GONE, §MOVE, §REPORT-RTL, §REPORT-KEY, §PASS-KEY, §PASS-MOVED, §MOVE-PASTED and
# §FINAL-RATING. The sections between them export the config and home directories the
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
. "$(dirname "$0")/lib/regression-fixture.sh"

# THE SEAM, exactly as tests/session-poker.test.sh offers it, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker-4.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

# THE CORE SCRIPT IS EIGHT FILES: the dispatcher and its seven parts under poker/ beside it. A doctored copy is the
# whole set, as files, each through the doctor; a count of the lines a doctor changed reads the whole set.
poker_text() {  # <dispatcher> -> its text, then each part's, in name order
  cat "$1" "$(dirname "$1")"/poker/*.sh
}
poker_doctored() {  # <dispatcher> <dest hooks dir> <filter> [<arg>...] -> the set under dest, each file through the filter
  local src="$1" dst="$2" f; shift 2
  rm -rf "$dst/poker"; mkdir -p "$dst/poker"
  "$@" < "$src" > "$dst/session-poker.sh"
  for f in "$(dirname "$src")"/poker/*.sh; do "$@" < "$f" > "$dst/poker/${f##*/}"; done
}

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
# line. A READER'S RATING IS FINAL (wave-31 T32; D6, REQ-6): an `unsure: <n> <what>` line is an
# ordinary line of the record, read by nothing, so it neither shows a fix nor owes a check. The
# result is derived (a finding to fix gives fail, any other finding flag, none pass) and a `result:`
# that differs is refused, as is a written `priority:` the table does not give. Registration writes
# `deferred:` for each finding the table defers inside `## SDLC State`, after the proof line, and no
# `check:` line. A reader with no `severity` push registers as 1.12.0 did.
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
done
expect_eq "SEV-table2 …the deferred: lines sit inside ## SDLC State, after their proof lines" "2" \
  "$(awk '/^## /{ s = ($0 ~ /^## SDLC State/) } s && /^deferred: /{ n++ } END { print n + 0 }' "$PSEV")"
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
SEV_ID1="$(printf '%s\n' "$SEV_IDS" | head -1)"
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
expect_eq "SEV-shown4 a finding the table defers, beside an unsure: line, writes its deferral alone; a note writes none" \
  "deferred: record/wave-01-fixture/sh-defer-unsure.md#1 S3 on \"a 'quoted' word wrong\"" \
  "$(/usr/bin/grep -E '^(deferred|check): record/wave-01-fixture/sh-defer-unsure.md#' "$PSEV" | paste -sd'|' -)"
expect_eq "SEV-shown5 …and the line follows the proof line it belongs to (proof_add_line)" \
  "deferred: record/wave-01-fixture/sh-defer-unsure.md#1" \
  "$(awk '/^proved: .*sh-defer-unsure/ { getline; print $1 " " $2 }' "$PSEV")"
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
expect_regex "SEV-old2b …placed after the last reading's finding lines, not between a proof and its own" "^proved: .*evidence=record/wave-01-fixture/o-fail.md " \
  "$(awk '/^deferred: record\/wave-01-fixture\/sh-defer-unsure.md#1 / { getline; print; exit }' "$PSEV")"
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
cp "$TMPROOT/sev-config" "$RSEV/.bionic/config.yaml"

# ---------- the tick prints the derived priority ----------
RSEVT="$(make_repo sev-tick)"; new_roster "$RSEVT"
PSEVT="$(s47_plan "$RSEVT" 2 \
  "| T1 | 4 | build | ready | implementor | — | 30 | REQ-x | payload/x.sh | pending | |")"
awk '{ print } /^current: / && !d { print "deferred: record/w/rev.md#2 S2 off \"a side path\""; print "check: record/w/rev.md#3 S1 on \"unsure of it\""; d = 1 }' \
  "$PSEVT" > "$PSEVT.tmp" && mv "$PSEVT.tmp" "$PSEVT"
poke_pressure "$RSEVT" 8192 1.0 tick
expect_contains "SEV-tick the tick fills the ready row (the path it prints FINDING on)" "poker: FILL T1" "$OUT"
expect_absent "SEV-tick3 …and an old check: line, read by nothing since wave-31 T32, prints no line" 'record/w/rev.md#3' "$OUT"

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
# The advance to 8 asks a ruling of every matrix row, and a row with no auditor verdict is unruled. A person rules it by
# the auditor's CONFIRMED in its cell (a waiver or a T4 row's attributed confirmation are the other two ways); the
# fixture's rows carry none, so the steps that expect the advance to be admitted rule them first.
sp4_rule_rows() {  # <plan> -> every matrix row's auditor cell reads CONFIRMED
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
# ---------- §ASK-WAIVE (T35; AC-2.2): a failing question is the person's to waive, and opens one item ----------
# A failing reading leaves the person the call: fix it or waive the question. Its registration opens
# `waive:<question>`, the key the waive verb closes (proof-add); a refusal on it keeps that one item; a
# second refusal opens nothing new; the waive verb closes it; a refusal after the waiver is taken back
# opens it again; and once the question holds again (a passing reading over the fix), current 8 closes
# what is left.
sev_owed() { ( cd "$RSEV" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && owed_list' _ "${SEV_LIB%/*}" ) 2>/dev/null; }
sev_store() { ( cd "$RSEV" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && cat "$(owed_file)"' _ "${SEV_LIB%/*}" ) 2>/dev/null; }
SEV_WKEYS="$(sev_owed | cut -f1)"
expect_contains "AW-1 T35 AC-2.2 the refusal on a failing question opens waive:<question>, the waive verb's key" \
  "waive:adversarial" "$SEV_WKEYS"
expect_absent "AW-1a …and none for the questions that hold (same reader)" "waive:evidence" "$SEV_WKEYS"
expect_contains "AW-1b …the item the first failing reading's registration opened, which the refusal keeps" \
  "proof-add: the adversarial review record/wave-01-fixture/" "$(sev_owed | awk -F'\t' '$1 == "waive:adversarial" { print $4 }')"
poke "$RSEV" current 8
expect_eq "AW-2 a second refusal on the same failing question opens nothing new" "1|1" \
  "$RC|$(sev_store | /usr/bin/grep -c '|key=waive:adversarial|')"
cp "$PSEV" "$TMPROOT/sev-before-waive.md"
poke "$RSEV" waive adversarial 'I waive the adversarial reading for now'
expect_eq "AW-3 the waive verb records the user's reply (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "AW-3a …and closes the item it answers" "|key=waive:adversarial|state=closed|by=waive|" "$(sev_store)"
# THE MUTANT (wave-34 T5; REQ-4 AC-4.5): the opener doctored to open nothing, in a copy of the plugin (hooks/ beside
# scripts/, so the copy's loader finds the copy's library), turns AW-4 red: the same refusal opens no item.
cp "$TMPROOT/sev-before-waive.md" "$PSEV"
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
cp "$TMPROOT/sev-before-waive.md" "$PSEV"
poke "$RSEV" current 8
expect_eq "AW-4 the waiver taken back out of the plan, the refusal is a new need: the item opens again" "1|waive:adversarial" \
  "$RC|$(sev_owed | cut -f1 | /usr/bin/grep '^waive:')"
sev_cur 4
sev_rec c-later flag "findings: 2" "finding: 1 S2 off - a side path still wrong" "finding: 2 S4 off - a comment misstates it"
sev_add c-later
expect_eq "SEV-cur3 a later pass over the fix, holding only a deferral and a note, registers as flag (exit 0)" "0|flag" \
  "$RC|$(sev_last | sed -n 's/.* result=\([a-z]*\) .*/\1/p')"
sev_cur 7
sp4_rule_rows "$PSEV"
poke "$RSEV" current 8
expect_eq "SEV-cur4 §CUR8-sev …and current 8 is admitted on it: deferrals and notes do not hold the step" "0|8" \
  "$RC|$(sed -n 's/^current: //p' "$PSEV")"
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
expect_contains "DEBT-L1c …naming each item it added" "poker: debt add — log_shim one-case-abstraction lib/a.sh:4" "$OUT"
# AC-11.2's fails-when: a debt finding in the record with no ledger line.
DBT_WANT="$(dbt_rows dbt-rec | awk -F'\t' '$1 == "debt" { print $3 " | " $2 " | " $4 }')"
expect_nonempty "DEBT-L2 precondition: the record's debt rows read back" "$DBT_WANT"
poke "$RSEV" debt add record/wave-01-fixture/dbt-rec.md "$PSEV"
expect_eq "DEBT-L3 a second add of the same record, the plan named, exits 0" "0" "$RC"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt add record/wave-01-fixture/dbt-sev.md "$PSEV"
expect_eq "DEBT-L4 debt add on a record whose debt line carries a severity is refused (exit 1)" "1" "$RC"
expect_true "DEBT-L4c …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt add record/wave-01-fixture/r-ok.md "$PSEV"
expect_eq "DEBT-L5 debt add on a reading with no debt line exits 0" "0" "$RC"
expect_true "DEBT-L5c …the ledger byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt touched tree_count "$PSEV"
expect_eq "DEBT-L6 debt touched exits 0 and prints the item with its new count" \
  "0|poker: debt touched — tree_count duplicate touches 1" "$RC|$OUT"
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
expect_eq "DEBT-A1c …and debt list reads both back" "0|$DBT_AL1|$DBT_AL2" "$(poke "$RSEV" debt list "$PSEV"; printf '%s|%s' "$RC" "$(printf '%s\n' "$OUT" | paste -sd'|' -)")"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
poke "$RSEV" debt adopt "$DBT_CONT" "$PSEV"
expect_eq "DEBT-A2 a second adopt, the plan named: 0 adopted, 2 already there" \
  "0|poker: debt adopt — 0 adopted, 2 already there: record/$DBT_SLUG/debt.md" "$RC|$OUT"
expect_true "DEBT-A2b …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt touched tree_count "$PSEV"
poke "$RSEV" debt adopt "$DBT_CONT" "$PSEV"
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
expect_true "DEBT-A6c …the ledger byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
poke "$RSEV" debt adopt
expect_eq "DEBT-A7 debt adopt with no continuation is a usage error (exit 2)" "2" "$RC"
rm -f "$DBT_LEDGER"

# ---------- §DEBT (wave-36 T13; D13, REQ-7 AC-7.2, AC-7.3, AC-7.8; C24, C25, A-orch-1, A-orch-2) ----------
# `debt add` reads any record carrying grammar-true `debt:` lines, a `reviewed:` line no longer required:
# a writer's or the orchestrator's `assumptions.md` hole line reaches debt.md by verb, never by hand
# (AC-7.2). Each line it would write is held to the one debt-line grammar, lib/debt.sh `debt_line_ok`,
# before anything is written. `debt adopt` with no plan named and no plan bound refuses naming `bind`
# and writes nothing: it never takes the newest plan by mtime, a closed predecessor's (AC-7.3).
# fails-when: a hole line never reaches debt.md; the unbound adopt writes the predecessor's ledger.
DBT_ASM="$SEV_DIR/assumptions.md"
printf '%s\n' "# assumptions — wave-01-fixture" "" \
  "- A-orch-1 (by hand): adopt carries open rows only, so the readers of a re-keyed session are orphaned." \
  'debt: hole adopt-orphans hooks/session-poker.sh:2846, payload/scripts/lib/units.sh:2112' \
  "- A-orch-2: a second assumption, prose only." > "$DBT_ASM"
DBT_HL='adopt-orphans | hole | hooks/session-poker.sh:2846, payload/scripts/lib/units.sh:2112 | raised-by record/wave-01-fixture/assumptions.md | touches 0 | —'
expect_false "DEBT-H0 precondition: the run has no ledger yet, and the record carries no reviewed: line" \
  test -e "$DBT_LEDGER" -o -n "$(/usr/bin/grep '^reviewed:' "$DBT_ASM")"
poke "$RSEV" debt add record/wave-01-fixture/assumptions.md "$PSEV"
expect_eq "DEBT-H1 §DEBT debt add takes an assumptions.md hole line with no reviewed: line (exit 0)" "0" "$RC"
expect_absent "DEBT-H1d …and the reading's refusal is gone (C24)" "carries no reviewed:" "$OUT"
cp "$DBT_LEDGER" "$TMPROOT/dbt-before"
printf '%s\n' "# assumptions" "" 'debt: hole step-line-born hooks/session-poker.sh step-line (the born marker is lost)' > "$SEV_DIR/asm-free.md"
poke "$RSEV" debt add record/wave-01-fixture/asm-free.md "$PSEV"
expect_eq "DEBT-H2 a hole line whose site is prose, not <path>:<line>, is refused (exit 1)" "1" "$RC"
expect_true "DEBT-H2c …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
mkdir -p "$SEV_DIR/two words"
printf '%s\n' 'debt: hole spaced-source lib/s.sh:1' > "$SEV_DIR/two words/assumptions.md"
poke "$RSEV" debt add "record/wave-01-fixture/two words/assumptions.md" "$PSEV"
expect_eq "DEBT-H3 a record whose path holds a space would write raised-by with a space (A-orch-1's shape): refused (exit 1)" "1" "$RC"
expect_true "DEBT-H3c …and the ledger is byte-identical" cmp -s "$TMPROOT/dbt-before" "$DBT_LEDGER"
rm -rf "$SEV_DIR/two words" "$SEV_DIR/asm-free.md" "$DBT_ASM"
rm -f "$DBT_LEDGER"

# The unbound adopt (C25, A-orch-2): an engaged session bound to no plan, in a root whose only plan is a
# CLOSED predecessor that keeps its own ledger. `resolve_run`'s `none` arm hands the tick the newest plan
# by mtime so it can DISARM; the debt verb is a writer and takes no plan it was not given or bound to.
RDU="$(make_repo dbt-unbound)"; ( cd "$RDU" && git commit -q --allow-empty -m init )
DBU_PLAN="$RDU/.bionic/docs/plans/epic-99-fixture/wave-00-prior.plan.md"; mkdir -p "${DBU_PLAN%/*}"
printf '%s\n' "# prior wave" "" "## SDLC State" "" "current: 9" "" \
  "- Step 9: delivered: 2026-10-01T00:00Z wave-00-prior" > "$DBU_PLAN"
DBU_LED="$RDU/.bionic/docs/record/wave-00-prior/debt.md"; mkdir -p "${DBU_LED%/*}"
printf '%s\n' "$DBT_HEAD" "$DBT_AL2" > "$DBU_LED"
DBU_SHA="$(shasum "$DBU_LED" | awk '{ print $1 }')"
expect_eq "DEBT-U0 precondition: the root's newest plan is the closed predecessor, which active_plan hands an unbound session" \
  "$DBU_PLAN|closed" "$(bash -c '. "$1/run.sh"; p="$(active_plan "$2")"; printf "%s|" "$p"; run_open "$p" >/dev/null 2>&1 && echo open || echo closed' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$RDU" 2>/dev/null)"
expect_eq "DEBT-U0b precondition: the session's marker binds no plan" "" "$(cat "$RDU/.bionic/tmp/engaged-$SID.state")"
poke "$RDU" debt adopt "$DBT_CONT"
expect_eq "DEBT-U1 §DEBT debt adopt with no plan named and none bound is refused (exit 2)" "2" "$RC"
expect_contains "DEBT-U1b …naming bind" "bind" "$OUT"
expect_absent "DEBT-U1c …and it adopted nothing" "adopted" "$OUT"
expect_eq "DEBT-U1d …the predecessor's debt.md is unchanged (sha)" "$DBU_SHA" "$(shasum "$DBU_LED" | awk '{ print $1 }')"
poke "$RDU" debt adopt "$DBT_CONT" "$DBU_PLAN"
expect_eq "DEBT-U2 control: the same adopt naming the plan writes that plan's ledger (exit 0)" \
  "0|poker: debt adopt — 1 adopted, 1 already there: record/wave-00-prior/debt.md" "$RC|$OUT"

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
s60_tick
expect_nonempty "LT3-pre the second tick printed (the extractor reads real output)" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: ')"
expect_eq "LT3 a second tick over the same record tells neither again" "" "$(lt_lines)"
printf 'line/v1|ev=standing|head=%s|suite=a.test.sh|lines=1|log=/rec/line/T2-a-%s.log|at=2026-10-06T10:02:00Z\n' "$LT_H2" "${LT_H2:0:12}" >> "$S60_REC"
s60_tick
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
RD_HAZ='done; delivered: now - Step 9: delivered: x current: 9 approved-by: me proved: kind=regression head=abc'
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

# ---------- §RC-DEFER: a deferral reads unstated until its sentence is in the changelog ----------
poke "$RSEV" release-check
expect_eq "RD-1 release-check over a plan holding deferrals none of which is stated exits 0 (it refuses nothing)" "0" "$RC"
expect_eq "RD-1b …and prints each deferral unstated: $RD_ID1" "unstated" "$(rd_state "$RD_ID1")"
expect_eq "RD-1c …and $RD_ID2" "unstated" "$(rd_state "$RD_ID2")"
expect_eq "RD-1d …one line per deferred: line the plan holds, and no line for a finding with none" "$(/usr/bin/grep -c '^deferred: ' "$PSEV" | tr -d ' ')|0" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: release-check — deferral ')|$(printf '%s\n' "$OUT" | /usr/bin/grep -cF "deferral $RD_CHK")"
poke "$RSEV" finding-stated "$RD_ID1" "$RD_SA"
expect_eq "RD-2 finding-stated on a deferral exits 0" "0" "$RC"
expect_eq "RD-2c …and to no other deferred: line" "1" "$(/usr/bin/grep -c '^deferred: .* stated=' "$PSEV" | tr -d ' ')"
poke "$RSEV" release-check
expect_eq "RD-3 a stated deferral whose sentence is not in the changelog is still unstated (exit 0)" "0|unstated" "$RC|$(rd_state "$RD_ID1")"

# ---------- §RC-PARSE: a deferred: line whose sentence carries the plan's own words passes its parsers ----------
poke "$RSEV" finding-stated "$RD_ID4" "$RD_HAZ"
expect_eq "RD-4 finding-stated with a sentence made of the words the plan's parsers read exits 0 (the dry commit passed the gate)" "0" "$RC"
sev_cur 4
s34_gate "$RSEV"
expect_eq "RD-4c the real commit gate admits the plan carrying it (at the step a writer's dry commit judges)" "0" "$GATE_RC"
cp "$PSEV" "$TMPROOT/rd-plan-keep"; sed '/^approved-by:/d' "$TMPROOT/rd-plan-keep" > "$PSEV"
s34_gate "$RSEV"
expect_eq "RD-4c2 …and the same gate refuses it with the approval line taken out, so the row above reads the plan" "2" "$GATE_RC"
cp "$TMPROOT/rd-plan-keep" "$PSEV"
sev_cur 7
sp4_rule_rows "$PSEV"
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

# ---------- §RC-STATED: the sentence in the changelog makes a deferral stated ----------
RD_CL="## 1.13.0 — fixture
- The install record now lists
  what setup placed, and remove acts only on it."
s57_commit "$SEV_WT" CHANGELOG.md "$RD_CL" >/dev/null
poke "$RSEV" release-check
expect_eq "RD-6 with the sentence in the head's CHANGELOG.md, wrapped across two lines, the deferral reads stated (exit 0)" "0|stated" "$RC|$(rd_state "$RD_ID1")"
expect_eq "RD-6b …while a deferral with no sentence still reads unstated" "unstated" "$(rd_state "$RD_ID2")"
poke "$RSEV" finding-stated "$RD_ID1" "a sentence the changelog does not hold"
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
    [ "$(basename "$_sib")" = poker ] && continue
    ln -s "$_sib" "$d/hooks/$(basename "$_sib")"
  done
  poker_doctored "$POKER" "$d/hooks" sed "$2"
}
rd_mutant nowrite 's/^    FS_TAIL=" stated=.*$/    FS_TAIL=""/'
rd_mutant inverted 's/^    \[ -n "\$DS_ST" \] && case .*$/    [ -n "$DS_ST" ] \&\& case "$DS_CL" in *"$DS_ST"*) : ;; *) DS_ANS=stated ;; esac/'
expect_eq "RD-mut0 each doctored poker differs from the real one in exactly one line (the doctors took)" "1|1" \
  "$(diff <(poker_text "$POKER") <(poker_text "$RD_MUT/nowrite/hooks/session-poker.sh") | /usr/bin/grep -c '^>')|$(diff <(poker_text "$POKER") <(poker_text "$RD_MUT/inverted/hooks/session-poker.sh") | /usr/bin/grep -c '^>')"
RD_REAL_POKER="$POKER"
POKER="$RD_MUT/nowrite/hooks/session-poker.sh"
poke "$RSEV" finding-stated "$RD_ID5" "a sentence for the doctored verb"
POKER="$RD_REAL_POKER"
expect_eq "RD-mut1 the verb with its write removed still runs (exit 0)" "0" "$RC"
poke "$RSEV" finding-stated "$RD_ID5" "a sentence for the doctored verb"
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
section "§STEP-FIELD §COPIED-LOG §REVIEW-RANGE §CUR7-COVERED: what a run's close wrote by hand, a verb writes or reads"
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
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PVG" > "$PVG.tmp" && mv "$PVG.tmp" "$PVG"
s42_builds_landed "$PVG"
( cd "$RVG" && git add -f "$PVG" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RVG/.worktrees/01-fixture" "$VG_B" ) >/dev/null 2>&1
VG_WT="$RVG/.worktrees/01-fixture"; VG_DIR="$RVG/.bionic/docs/record/wave-01-fixture"; mkdir -p "$VG_DIR"
VG_A="$(s57_commit "$VG_WT" lib/a.sh A)"
new_roster "$RVG"
printf '%s|questions=adversarial\n' "$(roster_row_fixture session="$SID" name=vg-crit agent_id=a-vg-crit \
  subagent_type=bionic:critic files=.bionic/docs/record/wave-01-fixture/past-waiver.md)" >> "$(roster_of "$RVG")"

# ---------- §STEP-FIELD: the Step-5 auditor: line is a field the verb writes ----------
s42_snap "$RVG" "$PVG"
poke "$RVG" step-field 5 "auditor=CONFIRMED 3 of 3, record/wave-01-fixture/auditor.md"
expect_eq "VG-1 AC-20.1 step-field 5 auditor= writes the line under the Step 5 line (exit 0)" \
  "0|  auditor: CONFIRMED 3 of 3, record/wave-01-fixture/auditor.md" "$RC|$(awk '/^- Step 5:/ { getline; print; exit }' "$PVG")"
s42_snap "$RVG" "$PVG"
poke "$RVG" step-field 4 "auditor=CONFIRMED"
s42_unchanged "VG-1b the auditor: line is read from the Step 5 block alone, so Step 4's is" 1 "$PVG"

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
poke "$RVG" waive all 'I waive the readings at A'
expect_eq "VG-2 the user's waiver of every question at A (exit 0)" "0|3" "$RC|$(/usr/bin/grep -c "^waived: question=[a-z]* head=$VG_A " "$PVG")"
VG_C="$(s57_commit "$VG_WT" lib/a.sh C)"
printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: pass\nscope: piece\n' "$VG_A" "$VG_C" > "$VG_DIR/past-waiver.md"
poke "$RVG" proof-add review record/wave-01-fixture/past-waiver.md --question adversarial --reader vg-crit
expect_eq "VG-2b AC-20.2 a reading of A..C registers on the waiver at A, with no reading before it (exit 0)" "0|1" \
  "$RC|$(s46_proved "$PVG" | /usr/bin/grep -c "^proved: kind=review head=$VG_C .* evidence=record/wave-01-fixture/past-waiver.md question=adversarial ")"

# ---------- §CUR7-COVERED: an approval and a waiver at an earlier head hold over the prose landed after them ----------
# The plan is put in the order (a whole-run row at Step 5, a release row at 7, an open integrate row reading the
# release); the user approves the release at C2 and waives the readings there, then two prose commits land.
VG_C2="$(s57_commit "$VG_WT" lib/b.sh C2)"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture "$PVG" "$VG_DIR/whole-c2.log" "$VG_C2" 0 0
poke "$RVG" proof-add regression record/wave-01-fixture/whole-c2.log
poke "$RVG" waive all 'I waive the readings at C2'
awk '{ print } /^- T5: / { print "- T6: landed at record/T6.md\n- T7: landed at record/T7.md" } /^\| T5 \| 5 \| verify / {
  print "| T6 | 5 | test | the whole run | test-runner | — | 30 | REQ-1 | — | — | — | landed |"
  print "| T7 | 7 | doc | the release | implementor | — | 30 | REQ-1 | CHANGELOG.md | — | — | landed |"
  print "| T8 | 8 | integrate | the merge | implementor | — | 30 | REQ-1 | — | — | — | pending |" }' "$PVG" > "$PVG.tmp" && mv "$PVG.tmp" "$PVG"
poke "$RVG" approve release 'ship C2'
expect_eq "VG-5 the plan is in the order, and the user approves the release at C2 (exit 0)" "0|T6|$VG_C2" \
  "$RC|$(bash -c '. "$1/units.sh" && units_order "$2"' _ "${S46_LIB%/*}" "$PVG")|$(bash -c '. "$1" && proof_approved_head "$2" release' _ "$S46_LIB" "$PVG")"
s57_commit "$VG_WT" .bionic/docs/record/wave-01-fixture/notes.md P1 >/dev/null
s57_commit "$VG_WT" README.md P2 >/dev/null
# The Step 7 gate asks for a whole matrix this fixture does not model, so the judge is asked at the plan's Step 7
# through `current 8 --check`, which asks the facts and the approved head at the working head.
sed 's/^current: .*/current: 7/' "$PVG" > "$PVG.tmp" && mv "$PVG.tmp" "$PVG"
sp4_rule_rows "$PVG"
poke "$RVG" current 8 --check
expect_eq "VG-5b AC-20.5 the approval and the waivers at C2, two prose commits after: current 8 is admitted" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
s57_commit "$VG_WT" lib/b.sh C3 >/dev/null
poke "$RVG" current 8 --check

# ---------- §DISPOSITION: a finding the whole run fixed says so, not that a landing did ----------
# A build row that landed on no suite owes no verdict, so a green whole run past its landing is what fixes its finding.
VG_FR="record/wave-01-fixture/adv-fix.md"
printf 'question: adversarial\nresult: fail\nscope: piece\nreviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/a.sh:1 data lost\nshown: 1 bash lib/a.sh\n' \
  "$VG_B" "$VG_A" > "$VG_DIR/adv-fix.md"
VG_PL="$(bash -c '. "$1" && proof_line review "$2" 2026-10-04T12:00:00Z "$3" adversarial vg-crit fail piece' _ "$S46_LIB" "$VG_A" "$VG_FR")"
VG_CX="$(s57_commit "$VG_WT" lib/a.sh landing-of-the-fix)"
VG_C4="$(s57_commit "$VG_WT" lib/b.sh after-it)"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture "$PVG" "$VG_DIR/whole-c4.log" "$VG_C4" 0 0
poke "$RVG" proof-add regression record/wave-01-fixture/whole-c4.log
VG_PL="$VG_PL" VG_CX="$VG_CX" VG_FR="$VG_FR" awk '{ print } /^current: / && !p { print ENVIRON["VG_PL"]; p = 1 }
  /^- T5: / { print "- T9: landed " ENVIRON["VG_CX"] " 2026-10-04T13:00:00Z born: review S2 on of=" ENVIRON["VG_FR"] "#1" }
  /^\| T5 \| 5 \| verify / { print "| T9 | 4 | build | fix the finding · born: review | implementor | — | 30 | REQ-1 | lib/a.sh | — | — | landed |" }' \
  "$PVG" > "$PVG.tmp" && mv "$PVG.tmp" "$PVG"
# The fix row landed by hand: `row-landed --by-hand` records it as the published event alone (hooks/poker/line.sh), no `landed:` header.
printf 'line/v1|ev=published|row=T9|commit=%s|kind=hand|by=Dana Fixture|why=landed on the report|at=2026-10-04T13:00:00Z\n' "$VG_CX" >> "$VG_DIR/landing-proofs.log"
poke "$RVG" disposition
expect_contains "VG-6 AC-10.1 AC-10.4 a finding a hand-landed row fixed, with a green whole run past it, reads fixed by the regression at its head" \
  "fixed by the regression at ${VG_C4:0:12}" "$(printf '%s\n' "$OUT" | /usr/bin/grep "finding $VG_FR#1 ")"
POKE_BOUND="$VG_BOUND_WAS"


# ============================================================
section "§REPLY-SEQ: one reply orders the release approval card's decisions in sequence, each applied in order and recorded"
# ============================================================
# FIXTURE FIDELITY. §STEP-FIELD's plan at its working head, its reading's record given one S3 finding; the page's
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
rs_page "key=row:AC-9.1|default=waive-row AC-9.1|$RS_ROW" "key=row:AC-1.1|default=waive-row AC-1.1|$RS_ROW" "$RS_FIND"
s42_snap "$RVG" "$PVG"
poke "$RVG" reply '1 run, 4 fix, rest default'
s42_unchanged "RS-1 an item naming a decision the page does not hold refuses the whole reply" 1 "$PVG"
expect_eq "RS-1b …naming the item, nothing recorded on the page" "1|" "$(printf '%s' "$OUT" | /usr/bin/grep -c '"4 fix"')|$(rs_done)"
poke "$RVG" reply '1 fix, rest default'
s42_unchanged "RS-2 an item naming a choice its decision does not offer refuses the whole reply" 1 "$PVG"
expect_eq "RS-2b …naming the item and the two it offers, nothing recorded" "1|" "$(printf '%s' "$OUT" | /usr/bin/grep -c '"1 fix".*waive.*run')|$(rs_done)"
poke "$RVG" reply '1 run, 3 fix, rest default'
expect_eq "RS-3 AC-13.3 '1 run, 3 fix, rest default': 1 run, 2 its default, 3 fixed, recorded in that order (exit 0)" \
  "0|withheld: row:AC-9.1|applied: row:AC-1.1 waive-row rc=0|applied: finding:$RS_F finding-move rc=0" "$RC|$(rs_done)"
expect_eq "RS-3b …AC-1.1 waived and the finding moved to fix, each on the user's words" "| waived |1" \
  "$(/usr/bin/grep -oE '^\| AC-1\.1 \| [^|]* \| [a-z]+ \|' "$PVG" | /usr/bin/grep -oE '\| [a-z]+ \|$')$(/usr/bin/grep -cF "moved: $RS_F to=fix by=Dana Fixture at=" "$PVG")"
rs_page "key=row:AC-9.1|default=waive-row AC-9.1|${RS_ROW/pick=default/pick=other}" "${RS_FIND/pick=other/pick=default}"
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
BP_LIFT="$(bash -c '. "$1" && lift_contract_fields "$2"' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh" "$(cat "$BP_REC/T1.md")" 2>&1)"
expect_contains "BP-5 the dispatch wall's reader lifts the pins as paths of the brief, no marker read as one" \
  "files=lib/a.sh,tests/pinned.test.sh,tests/fixtures/x,tests/fixtures/y" "$(printf '%s\n' "$BP_LIFT" | /usr/bin/grep '^files=')"
expect_absent "BP-5b …and refuses no entry of the Files span" "files_bad" "$BP_LIFT"
# THE PINS ARE READ AT THE WORKING HEAD: a suite committed on the plan's working branch and absent from the checkout.
( cd "$BP" && git checkout -q -b wave/01-fixture && git add -f tests && git commit -qm suites && git checkout -q - ) >/dev/null 2>&1
rm -rf "$BP/tests"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$BP_PLAN" > "$BP_PLAN.tmp" && mv "$BP_PLAN.tmp" "$BP_PLAN"
bp_brief T1
expect_eq "BP-6 with a working branch, the pins come from the suite at its tip, not the checkout (exit 0)" \
  "0|Files: lib/a.sh, tests/pinned.test.sh
tests/fixtures/x  # (pinned by pinned.test.sh)
tests/fixtures/y  # (pinned by pinned.test.sh)" "$RC|$(bp_files T1)"
# THE SUITES THAT DECLARE THEIR PINS, read as shipped: each real header reaches the brief of a row that runs it, and every
# path declared is a file of this repository (a stale pin names a file a writer is then told it may write). The plan
# names no working branch here, so the headers are read from the copies under the scratch checkout.
sed '/^working-branch: /d' "$BP_PLAN" > "$BP_PLAN.tmp" && mv "$BP_PLAN.tmp" "$BP_PLAN"
printf '%s\n' '| T5 | 4 | build | the declaring suites | implementor | — | 30 | REQ-12 | lib/e.sh, tests/words.test.sh, tests/sitrep-card.test.sh, tests/door-landing.test.sh, tests/release-check.test.sh, tests/shell-lint.test.sh | pending |' >> "$BP_PLAN"
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
section "§HAND-SUITES: a hand landing records the suites it names, and the judge proves the commit by them"
# ============================================================
# `row-landed <id> <commit> <at> --by-hand <who> <why> --suites <a,b> --green-at <commit> --log <path>` writes the row's
# `ready` event with its suites and one green verdict per suite at the commit they were green at, before the `published`
# line, through the writer `land --by-hand` uses (lib/line.sh `_line_hand_ready`, `_line_hand_verdicts`), so the floor's
# judge (`_proof_past_f`) proves the landing; without the three flags the record holds the `published` line alone and the
# judge finds no run of the row's suites. Fixture: a row's head R and the person's merge M of it onto the base F, two rows
# landed the same way (the control without the flags).
HS="$(make_repo hand-suites)"; ( cd "$HS" && git commit -q --allow-empty -m init ) >/dev/null 2>&1
git -C "$HS" config user.name "Dana Fixture"
HS_PLAN="$(s34_plan "$HS" 4)"
sed -e 's/^- T1: landed at record\/T1.md$/- T1: dispatched to w-T1/' -e 's/^\(| T1 | .*\) landed |$/\1 pending |/' \
  -e 's/^- T2: dispatched to w-T2$/- T2: dispatched to w-T2\
- T3: dispatched to w-T3/' \
  -e 's/^\(| T2 | .*\)$/\1\
| T3 | 4 | build | a row given two of the three flags | implementor | — | 30 | REQ-1 | c.sh | — | — | pending |/' \
  "$HS_PLAN" > "$HS_PLAN.tmp" && mv "$HS_PLAN.tmp" "$HS_PLAN"
HS_F="$(git -C "$HS" rev-parse HEAD)"
hs_merge() {  # <row> <path> -> sets HS_R (the row's head) and HS_M (the person's merge of it onto the base)
  git -C "$HS" checkout -q -b "wt/$1" "$HS_F" >/dev/null 2>&1
  HS_R="$(s57_commit "$HS" "$2" "the $1 row")"
  git -C "$HS" checkout -q - >/dev/null 2>&1
  ( cd "$HS" && git merge --no-ff -q -m "merge wt/$1" "wt/$1" ) >/dev/null 2>&1
  HS_M="$(git -C "$HS" rev-parse HEAD)"
  HS_F="$HS_M"
}
hs_rec() { cat "$HS/.bionic/docs/record/wave-01-fixture/landing-proofs.log" 2>/dev/null; }
hs_judge() {  # <base> <head> -> the floor judge's verdict on the commits after <base> to <head>: its exit code and words
  local o rc; o="$(bash -c '. "$1" && _proof_past_f "$2" "$3" "$4" "$5" ""' _ "$S46_LIB" "$HS_PLAN" "$HS" "$1" "$2" 2>&1)"; rc=$?
  printf '%s|%s' "$rc" "$o"
}
HS_AT="2026-10-20T10:00:00Z"
HS_BASE="$HS_F"
hs_merge T1 lib/a.sh; HS_R1="$HS_R"; HS_M1="$HS_M"
poke "$HS" row-landed T1 "$HS_M1" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --suites session-poker-4.test.sh,units.test.sh --green-at "$HS_R1" --log "$HS/.bionic/docs/record/wave-01-fixture/T1-green.log"
expect_eq "HS-1 AC-6.1 row-landed --by-hand with --suites, --green-at and --log exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "HS-1b …the record holds the row's ready event with its suites" \
  "line/v1|ev=ready|row=T1|name=-|commit=$HS_M1|" "$(hs_rec)"
expect_contains "HS-1c …naming both suites" "suites=session-poker-4.test.sh,units.test.sh|" "$(hs_rec | /usr/bin/grep '^line/v1|ev=ready|row=T1|')"
expect_eq "HS-1d …one green verdict per suite, at the commit they were green at, with the log" \
  "line/v1|ev=verdict|row=T1|commit=$HS_R1|suite=session-poker-4.test.sh|result=green|log=$HS/.bionic/docs/record/wave-01-fixture/T1-green.log
line/v1|ev=verdict|row=T1|commit=$HS_R1|suite=units.test.sh|result=green|log=$HS/.bionic/docs/record/wave-01-fixture/T1-green.log" \
  "$(hs_rec | /usr/bin/grep '^line/v1|ev=verdict|row=T1|' | sed 's/|admitted=.*//')"
expect_eq "HS-1e …in the order ready, verdicts, published" "ready verdict verdict published" \
  "$(hs_rec | /usr/bin/grep '|row=T1|' | sed 's/^line\/v1|ev=\([a-z]*\)|.*/\1/' | paste -sd' ' -)"
expect_contains "HS-1f …the published line is the hand landing's, field for field" \
  "line/v1|ev=published|row=T1|commit=$HS_M1|kind=hand|by=Dana Fixture|why=landed on the report|at=$HS_AT" "$(hs_rec)"
expect_eq "HS-2 AC-6.1 the floor's judge proves the commit by the verdicts the landing wrote (exit 0, nothing printed)" \
  "0|" "$(hs_judge "$HS_BASE" "$HS_M1")"
HS_BASE2="$HS_M1"
hs_merge T2 lib/b.sh; HS_M2="$HS_M"
poke "$HS" row-landed T2 "$HS_M2" "$HS_AT" --by-hand "Dana Fixture" "landed on the report"
expect_eq "HS-3 control: the same call without the three flags exits 0" "0" "$RC"
expect_eq "HS-3b …and writes the published line alone: no ready event, no verdict for T2" "0|1" \
  "$(hs_rec | /usr/bin/grep -c '^line/v1|ev=\(ready\|verdict\)|row=T2|')|$(hs_rec | /usr/bin/grep -c '^line/v1|ev=published|row=T2|commit='"$HS_M2"'|kind=hand|')"
expect_contains "HS-3c …and the judge finds no run of the row's suites at the commit" \
  "1|commit ${HS_M2:0:12} (row T2) is not proved: no run of its row's suites is recorded at it" "$(hs_judge "$HS_BASE2" "$HS_M2")"
# A RUN AGAIN OF THE SAME LANDING WRITES NOTHING MORE: the published line is the landing recorded.
poke "$HS" row-landed T1 "$HS_M1" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --suites session-poker-4.test.sh,units.test.sh --green-at "$HS_R1" --log "$HS/.bionic/docs/record/wave-01-fixture/T1-green.log"
expect_eq "HS-4 a run again of the landing exits 0 and the record's T1 lines are the four there were" "0|4" \
  "$RC|$(hs_rec | /usr/bin/grep -c '|row=T1|')"
# THE THREE FLAGS ARE ALL OR NONE, and the commit they name is one the landing holds.
hs_merge T3 lib/c.sh; HS_M3="$HS_M"; HS_BEFORE="$(hs_rec | wc -l | tr -d ' ')"
poke "$HS" row-landed T3 "$HS_M3" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --suites units.test.sh --green-at "$HS_R"
expect_eq "HS-5 two of the three flags is refused (exit 2, a usage error) and writes nothing" "2|$HS_BEFORE" "$RC|$(hs_rec | wc -l | tr -d ' ')"
HS_NOT="$(git -C "$HS" commit-tree -m "a commit no branch holds" "$(git -C "$HS" rev-parse "$HS_M3^{tree}")")"
poke "$HS" row-landed T3 "$HS_M3" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --suites units.test.sh --green-at "$HS_NOT" --log "$HS/x.log"
expect_eq "HS-5b a --green-at the landing does not hold is refused (exit 1) and writes nothing" "1|$HS_BEFORE" "$RC|$(hs_rec | wc -l | tr -d ' ')"
expect_contains "HS-5c …naming the commit" "${HS_NOT:0:12}" "$OUT"

# ============================================================
section "§EVENT: a hand landing's ready event carries the branch and the tree it is given, and reads - when it is given neither"
# ============================================================
# `row-landed --by-hand … --suites … --green-at … --log …` writes the row's `ready` event, which has fields for the
# branch and the tree the row was built on and wrote the literal `-` in both. `--branch <b>` and `--tree <t>` fill them.
# They describe the ready event, which only `--suites` writes, so they are refused without it; a value no record line
# can hold is refused too. This section lands the third row of §HAND-SUITES's fixture, which its HS-5 left unlanded.
HS_PRE="$(hs_rec | wc -l | tr -d ' ')"
poke "$HS" row-landed T3 "$HS_M3" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --branch wt/T3 --tree "$HS/.worktrees/T3"
expect_eq "EV-1 --branch and --tree without --suites are refused (exit 2, a usage error) and write nothing" "2|$HS_PRE" "$RC|$(hs_rec | wc -l | tr -d ' ')"
poke "$HS" row-landed T3 "$HS_M3" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --suites units.test.sh --green-at "$HS_R" --log "$HS/T3-green.log" --branch 'wt|T3' --tree "$HS/.worktrees/T3"
expect_eq "EV-1b a branch holding a | is refused (exit 1) and writes nothing" "1|$HS_PRE" "$RC|$(hs_rec | wc -l | tr -d ' ')"
poke "$HS" row-landed T3 "$HS_M3" "$HS_AT" --by-hand "Dana Fixture" "landed on the report" --suites units.test.sh --green-at "$HS_R" --log "$HS/T3-green.log" --branch wt/T3 --tree "$HS/.worktrees/T3"
expect_eq "EV-2 a hand landing given the suites, the branch and the tree exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "EV-2b …and its ready event carries both" "|commit=$HS_M3|branch=wt/T3|tree=$HS/.worktrees/T3|suites=units.test.sh|" \
  "$(hs_rec | /usr/bin/grep '^line/v1|ev=ready|row=T3|')"
expect_contains "EV-3 control: the landing given neither (T1, above) still reads - for both" "|commit=$HS_M1|branch=-|tree=-|suites=session-poker-4.test.sh,units.test.sh|" \
  "$(hs_rec | /usr/bin/grep '^line/v1|ev=ready|row=T1|')"

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
section "§REVIEW-FILES §DELIVER-CELL §FILES-UNHELD §STEP8-KEYS §NAMES-A-VERB: each verb a close meets writes its cell, or names the verb that does"
# ============================================================
# A close met four verbs that sent it in a circle: a review row's Files held one record for three questions, deliver
# read an artifact only from a ## Dispatch ledger a task-scale plan does not carry and named ledger-add, which refuses
# there; task-set sent a launched row's Files to amend, and amend sent a closed contract to a new dispatch; step-field
# refused the cleanup keys the gate's Step-8 block reads. FIXTURE FIDELITY: a task-scale plan at single rigor with a
# reads table carrying an artifact cell and no ledger, bound to this session, its working branch the repository's
# main; roster rows and acks in their writers' shapes (roster_row_fixture, s20_ack). Every write goes through the
# real verb; the one planted line is a review proof in proof_line's shape, as §DISPOSITION plants one.
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
vc_cell() { s48_row "$VC_P" "$1" | cut -d'|' -f"$2"; }  # <row> <9 Files | 10 status | 12 artifact>
VC_VERBS="task-set amend step-field step-line ledger-set ledger-add"
vc_named() {  # <refusal text> -> the first call of a verb that writes a cell, `<verb> <operands…>`, as the refusal prints it
  printf '%s\n' "$1" | /usr/bin/grep -oE 'session-poker\.sh [a-z][a-z-]*[^,;]*' | sed 's/^session-poker\.sh //; s/\. .*$//; s/\.$//' \
    | awk -v set=" $VC_VERBS " '{ if (index(set, " " $1 " ")) { print; exit } }'
}
VC="$(make_repo verb-cells)"; ( cd "$VC" && git commit -q --allow-empty -m init && git branch -M main ) >/dev/null 2>&1
git -C "$VC" config user.name "Dana Fixture"
VC_REC=".bionic/docs/record/wave-01-fixture"
VC_P="$(vc_plan "$VC" \
  '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | lib/a.sh | landed | — | — |' \
  '| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | lib/b.sh | active | — | — |' \
  '| T3 | 4 | build | the third build | implementor | — | 30 | REQ-1 | lib/c.sh | landed | — | — |')"
new_roster "$VC"
printf '%s\n' "$(roster_row_fixture session="$SID" name=w-T2 agent_id=a-w-T2 launched_at=2026-10-22T10:00:00Z row=T2 plan="$VC_P" files=lib/b.sh suites_allowed=b.test.sh suites_source=declared)" >> "$(roster_of "$VC")"
printf '%s\n' "$(roster_row_fixture session="$SID" name=w-T3 agent_id=a-w-T3 launched_at=2026-10-22T10:00:00Z row=T3 plan="$VC_P" files=lib/c.sh suites_allowed=c.test.sh suites_source=declared)" >> "$(roster_of "$VC")"
s20_ack "$VC" w-T3 2026-10-22T11:00:00Z

# ---------- §REVIEW-FILES: a review row's Files are its questions' records, its artifact the first ----------
VC_THREE="$VC_REC/critic-evidence.md, $VC_REC/critic-adversarial.md, $VC_REC/critic-structure.md"
poke "$VC" task-add T6 6 review "the critic's review. The critic reads the run once." critic — 30 REQ-1 — head
expect_eq "RF-0 setup: task-add of a review row on the single-rigor plan exits 0" "0" "$RC"
expect_eq "RF-1 AC-9.1 the row's Files hold one record per question the rigor deals, evidence, adversarial, structure" \
  "$VC_THREE" "$(vc_cell T6 9)"
expect_eq "RF-1b …and its artifact cell names the first, the record deliver takes" "$VC_REC/critic-evidence.md" "$(vc_cell T6 12)"
s42_snap "$VC" "$VC_P"
poke "$VC" task-add T7 6 review "a review on one record. The critic writes one record." critic — 30 REQ-1 "$VC_REC/critic.md" head
s42_unchanged "RF-2 a review row written with one record for three questions" 1 "$VC_P"
expect_contains "RF-2b …and the refusal names the rendered list" "$VC_THREE" "$OUT"
poke "$VC" task-add T7 6 review "a review on its three records. The critic writes three records." critic — 30 REQ-1 "$VC_THREE" head
expect_eq "RF-3 control: a review row whose Files name its three records goes in as written, its artifact the first" \
  "0|$VC_THREE|$VC_REC/critic-evidence.md" "$RC|$(vc_cell T7 9)|$(vc_cell T7 12)"
VC_OWN="$VC_REC/T10-evidence.md, $VC_REC/T10-adversarial.md, $VC_REC/T10-structure.md"
poke "$VC" task-add T10 6 review "A review on its own records. The critic writes its own three records." critic — 30 REQ-1 "$VC_OWN" head
expect_eq "RF-3b a review row whose Files already name one record of its own per question keeps those names verbatim, its artifact the first" \
  "0|$VC_OWN|$VC_REC/T10-evidence.md" "$RC|$(vc_cell T10 9)|$(vc_cell T10 12)"
expect_absent "RF-3c …and no rendered critic-<q>.md name is added beside them" "critic-" "$(vc_cell T10 9)"
poke "$VC" task-add T8 5 verify "the floor. The regression runs once." test-runner — 30 REQ-1 —
expect_eq "RF-4 control: a verify row keeps the reader-row rule, one record named for the row, and no artifact cell written" \
  "0|$VC_REC/T8.md|—" "$RC|$(vc_cell T8 9)|$(vc_cell T8 12)"

# ---------- §DELIVER-CELL: with no ledger, deliver lands the row its artifact cell names ----------
printf 'question: evidence\nresult: pass\nscope: piece\n' > "$VC/$VC_REC/critic-evidence.md"
VC_HEAD="$(git -C "$VC" rev-parse main)"
VC_PL="$(bash -c '. "$1" && proof_line review "$2" 2026-10-22T12:00:00Z "$3" evidence w-crit pass piece' _ "$S46_LIB" "$VC_HEAD" "record/wave-01-fixture/critic-evidence.md")"
VC_PL="$VC_PL" awk '{ print } /^current: / && !p { print ENVIRON["VC_PL"]; p = 1 }' "$VC_P" > "$VC_P.tmp" && mv "$VC_P.tmp" "$VC_P"
expect_eq "DC-0 setup: the plan carries no ## Dispatch ledger" "0" "$(/usr/bin/grep -c '^## Dispatch ledger' "$VC_P")"
poke "$VC" deliver T6
expect_eq "DC-1 AC-9.2 deliver lands the review row from its artifact cell (exit 0), the row landed" "0|landed" "$RC|$(vc_cell T6 10)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_contains "DC-1b …naming the artifact it read" "artifact $VC_REC/critic-evidence.md present" "$OUT"
poke "$VC" task-add T9 6 review "a second review. The critic reads the run again." critic — 30 REQ-1 — head
poke "$VC" task-set T9 artifact=—
s42_snap "$VC" "$VC_P"
poke "$VC" deliver T9
s42_unchanged "DC-2 control: a review row with three records and no artifact cell is refused" 2 "$VC_P"
VC_DREF="$OUT"
expect_contains "DC-2b …the refusal names the Tasks artifact cell's writer" "task-set T9 artifact=" "$VC_DREF"
expect_no_regex "DC-2c …and on a plan with no ledger it never names ledger-set or ledger-add" "ledger-(set|add)" "$VC_DREF"

# ---------- §FILES-UNHELD: task-set writes Files on a row no live contract holds ----------
poke "$VC" task-set T1 "Files=lib/a.sh, lib/a2.sh"
expect_eq "FU-1 AC-10.1 task-set Files= writes a landed row's cell (exit 0)" "0|lib/a.sh, lib/a2.sh" "$RC|$(vc_cell T1 9)"
poke "$VC" task-set T3 "Files=lib/c.sh, lib/c2.sh"
expect_eq "FU-2 …and a row whose roster row is closed by its ack (exit 0)" "0|lib/c.sh, lib/c2.sh" "$RC|$(vc_cell T3 9)"
s42_snap "$VC" "$VC_P"
poke "$VC" task-set T2 "Files=lib/b.sh, lib/b2.sh"
s42_unchanged "FU-3 control: a row a live roster row holds" 1 "$VC_P"
VC_TREF="$OUT"
expect_contains "FU-3b …and the refusal names amend on the live contract's name" "amend w-T2 --files+" "$VC_TREF"
s42_snap "$VC" "$VC_P"
poke "$VC" amend w-T3 --files+ lib/c3.sh --reason 'the closed contract'
VC_AREF="$OUT"
expect_eq "FU-4 amend on a closed contract is refused (exit 1)" "1" "$RC"
expect_contains "FU-4b AC-10.1 …and names task-set on the row its contract held" "task-set T3 Files=" "$VC_AREF"
expect_absent "FU-4c …not a new dispatch" "dispatch the work again" "$VC_AREF"

# ---------- §STEP8-KEYS: step-field 8 writes the cleanup keys the gate's Step-8 block reads ----------
poke "$VC" step-line 8 "integrated"
expect_eq "S8-0 setup: step-line writes the Step 8 line (exit 0)" "0" "$RC"
VC_S8=""
for VC_KV in merge=abc1234 worktree-removed=yes cleanup=done tmp-wiped=yes tasks-completed=yes; do
  poke "$VC" step-field 8 "$VC_KV"; VC_S8="$VC_S8 $RC"
  [ "$RC" = 0 ] || printf '      step-field 8 %s said: %s\n' "$VC_KV" "$OUT"
done
expect_eq "S8-1 AC-10.2 step-field 8 takes merge, worktree-removed, cleanup, tmp-wiped and tasks-completed (each exit 0)" " 0 0 0 0 0" "$VC_S8"
expect_eq "S8-1b …and writes the block the gate reads, under the Step 8 line" \
  "  merge: abc1234|  worktree-removed: yes|  cleanup: done|  tmp-wiped: yes|  tasks-completed: yes" \
  "$(awk '/^- Step 8:/ { f = 1; next } f && /^  [a-z-]+: / { printf "%s%s", (n++ ? "|" : ""), $0; next } f { exit }' "$VC_P")"
s42_snap "$VC" "$VC_P"
poke "$VC" step-field 5 cleanup=done
s42_unchanged "S8-2 control: cleanup is read from the Step 8 block alone, so Step 5's is" 1 "$VC_P"
VC_SREF="$OUT"

# ---------- §NAMES-A-VERB: each refusal names a verb that writes the cell, and that verb then does ----------
# The refusals planted above, plus a field on a step with no line. For each: the first call of a verb from the set it
# prints is run on the cell, with the refusal's own operands and a value for its slot, and exits 0.
s42_snap "$VC" "$VC_P"
poke "$VC" step-field 6 head=abc1234
s42_unchanged "NV-0 setup: a field on a step with no line" 1 "$VC_P"
VC_LREF="$OUT"
vc_follow() {  # <label> <refusal> <slot value> -> the named call, run with the slot filled
  local label="$1" q="'" call; call="$(vc_named "$2")"
  expect_nonempty "$label — the refusal names a verb from the set" "$call"
  [ -n "$call" ] || { printf '      the refusal: %s\n' "$2"; return; }
  call="${call//$q</<}"; call="${call//>$q/>}"
  call="${call//<path>/$q$3$q}"; call="${call//<list>/$q$3$q}"; call="${call//<value>/$q$3$q}"; call="${call//<text>/$q$3$q}"
  call="${call//<why>/${q}the cell the refusal named$q}"
  case "$call" in *'<'*'>'*) expect_eq "$label — …and the call it names fills every slot this test knows ($call)" "" "$call"; return ;; esac
  eval "set -- $call"
  poke "$VC" "$@"
  expect_eq "$label — …and that verb's call on the cell exits 0 ($call)" "0" "$RC"
  [ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
}
vc_follow "NV-1 deliver's refusal of an artifact" "$VC_DREF" "$VC_REC/critic-evidence.md"
vc_follow "NV-2 task-set's refusal of a held row's Files" "$VC_TREF" "lib/b2.sh"
vc_follow "NV-3 amend's refusal of a closed contract" "$VC_AREF" "lib/c.sh"
vc_follow "NV-4 step-field's refusal of a key at the wrong step" "$VC_SREF" "done"
vc_follow "NV-5 step-field's refusal of a step with no line" "$VC_LREF" "the regression"

# ---------- §TRIPLE: step-field 8 takes the integration's fields in one call; an unknown key names the verb that writes it ----------
# The Step 8 block above holds all five fields. One call carries merge, worktree-removed and cleanup, each replaced where
# it stands. A key the step blocks do not hold, but another verb writes, is refused naming that verb's call; a key no
# verb writes is refused saying so.
# fails-when: the triple needs three calls; one call writes fewer than three, or moves one; a bad pair beside good ones
# writes the good ones; a key another verb writes is refused without naming that verb; a key no verb writes names one;
# the usage line leaves out a field the verb takes.
vc_s8() { awk '/^- Step 8:/ { f = 1; next } f && /^  [a-z-]+: / { printf "%s%s", (n++ ? "|" : ""), $0; next } f { exit }' "$VC_P"; }
poke "$VC" step-field 8 merge=def5678 worktree-removed=no cleanup=partial
expect_eq "TR-1 step-field 8 takes merge, worktree-removed and cleanup in one call (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      step-field 8 said: %s\n' "$OUT"
expect_eq "TR-1b …and writes all three, each where it stood, the other two as they were" \
  "  merge: def5678|  worktree-removed: no|  cleanup: partial|  tmp-wiped: yes|  tasks-completed: yes" "$(vc_s8)"
s42_snap "$VC" "$VC_P"
poke "$VC" step-field 8 merge=0000000 foo=bar
s42_unchanged "TR-2 a call with one key no step block holds beside a good one is refused whole" 1 "$VC_P"
expect_contains "TR-2b …naming that key" "'foo' is not a step field" "$OUT"
expect_contains "TR-3 …and saying no verb writes it" "no verb writes 'foo'" "$OUT"
expect_absent "TR-3b …so it names no call" "next call:" "$OUT"
poke "$VC" step-field 8 approved=yes
s42_unchanged "TR-4 a key another verb writes (approved:) is refused" 1 "$VC_P"
expect_contains "TR-4b …naming the verb that writes it" "next call: bash " "$OUT"
expect_contains "TR-4c …approve, with its operands" "session-poker.sh approve '<name>' '<reply>'" "$OUT"
poke "$VC" step-field 4 base-sha=abc1234
s42_unchanged "TR-5 a Step 4 key current writes (base-sha:) is refused" 1 "$VC_P"
expect_contains "TR-5b …naming current 4" "session-poker.sh current 4" "$OUT"
poke "$VC" step-field 8 delivered=yes
s42_unchanged "TR-5c the Step 9 line's key (delivered:) is refused" 1 "$VC_P"
expect_contains "TR-5d …naming close-out, the script that writes it" "close-out writes it with current: 9 (scripts/close-out.sh)" "$OUT"
poke "$VC" step-field
expect_eq "TR-6 step-field with no operands prints its usage (exit 2)" "2" "$RC"
expect_contains "TR-6b …the usage names the fields it takes, the cleanup and the auditor among them" \
  "head, cmd, pass, total, output, merge, worktree-removed, adr, share; cleanup, tmp-wiped and tasks-completed (Step 8 only); auditor and walk-artifact (Step 5 only)" "$OUT"
expect_contains "TR-6c …and that it takes more than one" "step-field <N> <key>=<value>..." "$OUT"

# ---------- §LIVE: deliver on a live:head review row closes it when the judge reads its questions covered ----------
# FIXTURE FIDELITY: the single-rigor task plan above, its base-sha a commit of this repository so the judge deals it,
# the readings written by the proof writer (`proof_line`) at the working branch's head. T11 reads
# live:head:adversarial, T12 live:head:structure; a code commit past the readings leaves structure uncovered.
# fails-when: deliver refuses a live row whose every question is covered at the head, or lands one whose question
# a commit past its reading leaves uncovered, or refuses without naming that question.
LV="$(make_repo live-deliver)"; ( cd "$LV" && git commit -q --allow-empty -m base && git branch -M main ) >/dev/null 2>&1
git -C "$LV" config user.name "Dana Fixture"
LV_BASE="$(git -C "$LV" rev-parse main)"
LV_RD="record/wave-01-fixture"
LV_P="$(vc_plan "$LV" \
  "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | lib/a.sh | landed | — | — |" \
  "| T11 | 6 | review | the adversarial review | critic | — | 30 | REQ-1 | .bionic/docs/$LV_RD/live-adversarial.md | active | live:head:adversarial | .bionic/docs/$LV_RD/live-adversarial.md |" \
  "| T12 | 6 | review | the structure review | critic | — | 30 | REQ-1 | .bionic/docs/$LV_RD/live-structure.md | active | live:head:structure | .bionic/docs/$LV_RD/live-structure.md |")"
sed -i.bak "s/base-sha: abc1234/base-sha: $LV_BASE/" "$LV_P" && rm -f "$LV_P.bak"
( cd "$LV" && git add -f "$LV_P" && git commit -qm base-sha ) >/dev/null 2>&1
LV_H="$(git -C "$LV" rev-parse main)"
for lv_q in evidence adversarial structure; do
  printf 'question: %s\nresult: pass\nscope: piece\nreviewed: %s..%s\nfindings: 0\n' "$lv_q" "${LV_BASE:0:10}" "${LV_H:0:10}" > "$LV/.bionic/docs/$LV_RD/live-$lv_q.md"
  LV_PL="$(bash -c '. "$1" && proof_line review "$2" 2026-10-22T12:00:00Z "$3" "$4" w-crit pass piece' _ "$S46_LIB" "$LV_H" "$LV_RD/live-$lv_q.md" "$lv_q")"
  LV_PL="$LV_PL" awk '{ print } /^current: / && !p { print ENVIRON["LV_PL"]; p = 1 }' "$LV_P" > "$LV_P.tmp" && mv "$LV_P.tmp" "$LV_P"
done
lv_cell() { s48_row "$LV_P" "$1" | cut -d'|' -f10; }
expect_eq "LIVE-0 precondition: the judge deals the plan and reads every review question covered at the head" "covered" \
  "$(cd "$LV" && bash -c '. "$1/units.sh"; . "$1/proof.sh"; _units_readings_state "$2"' _ "$(dirname "$S46_LIB")" "$LV_P" 2>/dev/null)"
poke "$LV" deliver T11
expect_eq "LIVE-1 AC-14.1 deliver on the live:head:adversarial row, its question covered at the head: exit 0, the row landed" \
  "0|landed" "$RC|$(lv_cell T11)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
LV_X="$(s57_commit "$LV" lib/x.sh 'a code change past every reading')"
s42_snap "$LV" "$LV_P"
poke "$LV" deliver T12
s42_unchanged "LIVE-2 the control: a code commit past the structure reading, deliver on the live:head:structure row" 2 "$LV_P"
expect_contains "LIVE-2b …the refusal names the uncovered question" "structure" "$OUT"
expect_contains "LIVE-2c …and says it is not covered at the head" "uncovered" "$OUT"
expect_eq "LIVE-2d …and the row is still active" "active" "$(lv_cell T12)"

# ============================================================
section "§VERDICTS §DISCHARGE §STACK: the critic's verdicts and the regression's health reach the matrix by their verbs"
# ============================================================
# At single rigor the critic holds the evidence question, so its record is where the row verdicts and the wave verdict
# are learned. The record's grammar: a markdown table whose header names the columns AC and verdict (other columns
# allowed), one row per criterion, and one flush-left `verdict: <VERDICT>[ — <coverage finding>]` line for the wave.
# `proof-add review <record> --question evidence` on a `rigor: single` plan writes each named row's auditor cell
# (CONFIRMED as the bare token, any other verdict as written) and the matrix head's `auditor-wave:` line in the same
# plan write as its proof line. `discharge` refuses there, naming `proof-add review`; at double it writes as before.
# `proof-add regression` writes the head's `stack-health:` line through lib/proof.sh `proof_health_line`, the judge's
# fact rendered: green only at a pass that left nothing owed, red otherwise, and it leaves a declared `n/a:` as written.
#
# FIXTURE FIDELITY. §STEP-FIELD's shape built fresh: a plan bound to this session at Step 5, its working branch in a
# linked worktree, real commits, the reader's row from the production writer with `questions=` appended, run lines
# through the product's writer (regression_fixture). The matrix head's stub is the one matrix-render writes, rendered
# here by the verb from the plan's Eval design; every write after it goes through a real verb.
VT_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RVT="$(make_repo verdicts)"; ( cd "$RVT" && git commit -q --allow-empty -m init )
git -C "$RVT" config user.name "Dana Fixture"
VT_B="$(git -C "$RVT" rev-parse HEAD)"
PVT="$(s42_plan "$RVT" 5 "  worktree: .worktrees/01-fixture
  base-sha: ${VT_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PVT" > "$PVT.tmp" && mv "$PVT.tmp" "$PVT"
s42_builds_landed "$PVT"
# Three criteria, each with a matrix row at T2 and an Eval design row naming it; matrix-render fills the blocks and the head.
awk '/^## Verification Matrix/ {
       print "## Eval design\n"
       print "| Requirement | Criterion | Approach | Eval | Fails when |"
       print "|---|---|---|---|---|"
       print "| REQ-1 | AC-1.1 | hermetic | `tests/a.test.sh` | a is wrong |"
       print "| REQ-1 | AC-1.2 | hermetic | `tests/b.test.sh` | b is wrong |"
       print "| REQ-1 | AC-1.3 | hermetic | `tests/c.test.sh` | c is wrong |\n" }
     { print }
     /^\| AC-1\.1 \| T2 \|/ { print "| AC-1.2 | T2 | pending | — | — |"; print "| AC-1.3 | T2 | pending | — | — |" }' \
  "$PVT" > "$PVT.tmp" && mv "$PVT.tmp" "$PVT"
vt_rigor() { sed "s/^rigor: .*/rigor: $1/" "$PVT" > "$PVT.tmp" && mv "$PVT.tmp" "$PVT"; }
vt_rigor single
( cd "$RVT" && git add -f "$PVT" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RVT/.worktrees/01-fixture" "$VT_B" ) >/dev/null 2>&1
VT_WT="$RVT/.worktrees/01-fixture"; VT_DIR="$RVT/.bionic/docs/record/wave-01-fixture"; mkdir -p "$VT_DIR"
VT_A="$(s57_commit "$VT_WT" lib/a.sh A)"
VT_RECS="ev-double ev-single ev-again ev-notable ev-noverdict ev-twice ev-stray ev-empty"
VT_FILES=""; for n in $VT_RECS; do VT_FILES="${VT_FILES:+$VT_FILES,}.bionic/docs/record/wave-01-fixture/$n.md"; done
new_roster "$RVT"
printf '%s|questions=evidence\n' "$(roster_row_fixture session="$SID" name=vt-crit agent_id=a-vt-crit \
  subagent_type=bionic:critic files="$VT_FILES")" >> "$(roster_of "$RVT")"
vt_cell() {  # <AC> -> its matrix row's auditor cell, trimmed
  awk -F'|' -v a="$1" '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 }
    m && /^\|/ { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == a) { v = $6; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$PVT"
}
vt_cells() { printf '%s|%s|%s' "$(vt_cell AC-1.1)" "$(vt_cell AC-1.2)" "$(vt_cell AC-1.3)"; }
vt_head() {  # <key> -> the matrix head's <key>: lines, whole, `;`-joined
  awk -v k="$1" '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } m && index($0, k ":") == 1' "$PVT" | paste -sd';' -
}
vt_order() {  # -> the matrix section's head lines and its table header, in file order, by key
  awk '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } !m { next }
    /^stack-health:/ { o = o "stack-health," } /^auditor-wave:/ { o = o "auditor-wave," } /^\| AC \|/ { o = o "table"; exit }
    END { print o }' "$PVT"
}
vt_rec() {  # <name> <verdict: line or -> [<table row>...] -> an evidence reading over base..A
  local f="$VT_DIR/$1.md" v="$2" r; shift 2
  { printf '# evidence\n\nreviewed: %s..%s\nquestion: evidence\nresult: flag\nscope: whole\n\n## Row verdicts\n\n' "${VT_B:0:10}" "$VT_A"
    if [ "$#" -gt 0 ]; then printf '| AC | verdict | why |\n|---|---|---|\n'; for r in "$@"; do printf '%s\n' "$r"; done; fi
    [ "$v" = - ] || printf '\n%s\n' "$v"
    printf '\nwhat the critic found\n'; } > "$f"
}
vt_add() { poke "$RVT" proof-add review "record/wave-01-fixture/$1.md" --question evidence --reader vt-crit; }
VT_ROWS=('| AC-1.1 | CONFIRMED | the row reddens without the change |' '| AC-1.2 | REFUTED | the fixture cannot reach the failure |'
  '| AC-1.3 | UNVERIFIABLE | the record is missing |')

poke "$RVT" matrix-render
expect_eq "VT-0 setup: matrix-render renders the three blocks and the head's stub (exit 0)" "0|stack-health: pending" "$RC|$(vt_head stack-health)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "VT-0b precondition: every auditor cell is empty, and the head has no auditor-wave: line" "—|—|—|" "$(vt_cells)|$(vt_head auditor-wave)"

# ---------- §VERDICTS: the critic's table and wave verdict reach the auditor cells and the head ----------
vt_rigor double
vt_rec ev-double 'verdict: REFUTED — AC-1.2 is refuted' "${VT_ROWS[@]}"
vt_add ev-double
expect_eq "VT-1 control: at double rigor the same record registers (exit 0) and leaves the auditor cells as they were" "0|—|—|—" "$RC|$(vt_cells)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "VT-1b …and writes no auditor-wave: line (the head's stack-health: still read: the extractor is not empty)" "|stack-health: pending" \
  "$(vt_head auditor-wave)|$(vt_head stack-health)"
vt_rigor single
vt_rec ev-single 'verdict: REFUTED — AC-1.2 is refuted' "${VT_ROWS[@]}"
vt_add ev-single
expect_eq "VT-2 §VERDICTS AC-6.1 at single rigor the critic's evidence record registers (exit 0) and its verdicts reach the auditor cells" \
  "0|CONFIRMED|REFUTED|UNVERIFIABLE" "$RC|$(vt_cells)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "VT-2b …and the head carries the wave verdict on its auditor-wave: line" "auditor-wave: REFUTED — AC-1.2 is refuted" "$(vt_head auditor-wave)"
expect_eq "VT-2c …beside stack-health:, above the table" "stack-health,auditor-wave,table" "$(vt_order)"
expect_eq "VT-2d …in the same plan write as the proof line" "1" \
  "$(s46_proved "$PVT" | /usr/bin/grep -c "^proved: kind=review head=$VT_A .* evidence=record/wave-01-fixture/ev-single.md question=evidence ")"
expect_eq "VT-3 a CONFIRMED row needs no discharge: its table row reads the bare token, written by the review's registration" \
  "| AC-1.1 | T2 | pending | — | CONFIRMED |" "$(/usr/bin/grep -E '^\| AC-1\.1 \|' "$PVT")"
# A later reading replaces both: a row's verdict is the newest reading's, the head keeps one auditor-wave: line.
vt_rec ev-again 'verdict: CONFIRMED — every requirement has a row' '| AC-1.1 | CONFIRMED | — |' '| AC-1.2 | CONFIRMED | refixed |'
vt_add ev-again
expect_eq "VT-4 a second reading rewrites the rows it names and leaves the row it does not name as it was (exit 0)" \
  "0|CONFIRMED|CONFIRMED|UNVERIFIABLE" "$RC|$(vt_cells)"
expect_eq "VT-4b …and the head holds one auditor-wave: line, the newest" "auditor-wave: CONFIRMED — every requirement has a row" "$(vt_head auditor-wave)"
# What the record must carry at single rigor: each refusal leaves the plan byte-identical.
vt_rec ev-notable 'verdict: CONFIRMED — fine'
s42_snap "$RVT" "$PVT"; vt_add ev-notable
s42_unchanged "VT-5 a single-rigor evidence record with no AC | verdict table" 1 "$PVT"
expect_contains "VT-5b …named in the refusal" "the columns AC and verdict" "$OUT"
vt_rec ev-noverdict - '| AC-1.1 | CONFIRMED | — |'
vt_add ev-noverdict
s42_unchanged "VT-6 a single-rigor evidence record with the table and no verdict: line" 1 "$PVT"
expect_contains "VT-6b …named in the refusal" "verdict:" "$OUT"
vt_rec ev-twice 'verdict: CONFIRMED — one' '| AC-1.1 | CONFIRMED | — |'; printf 'verdict: REFUTED — two\n' >> "$VT_DIR/ev-twice.md"
vt_add ev-twice
s42_unchanged "VT-7 a record giving the wave verdict twice" 1 "$PVT"
vt_rec ev-stray 'verdict: CONFIRMED — fine' '| AC-1.1 | CONFIRMED | — |' '| AC-9.9 | CONFIRMED | — |'
vt_add ev-stray
s42_unchanged "VT-8 a row verdict for a criterion the matrix has no row for" 1 "$PVT"
expect_contains "VT-8b …naming it" "AC-9.9" "$OUT"
vt_rec ev-empty 'verdict: CONFIRMED — fine' '| AC-1.1 |  | — |'
vt_add ev-empty
s42_unchanged "VT-9 a row whose verdict cell is empty" 1 "$PVT"

# ---------- §DISCHARGE: discharge refuses at single rigor and writes at double ----------
s42_snap "$RVT" "$PVT"
poke "$RVT" discharge AC-1.3
s42_unchanged "VT-10 §DISCHARGE AC-6.2 discharge on a single-rigor plan" 1 "$PVT"
expect_contains "VT-10b …naming proof-add review" "proof-add review" "$OUT"
vt_rigor double
poke "$RVT" discharge AC-1.3
expect_eq "VT-11 …on a double-rigor plan it writes the cell as before (exit 0)" "0|CONFIRMED" "$RC|$(vt_cell AC-1.3)"
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
VT_C="$(s57_commit "$VT_WT" lib/b.sh C)"
printf 'Gating: 2 passed, 1 failed\nFailed:\n    - c.test.sh\n' | regression_fixture "$PVT" "$VT_DIR/whole-red.log" "$VT_C" 0 1
poke "$RVT" proof-add regression record/wave-01-fixture/whole-red.log
expect_eq "VT-12 §STACK AC-7.1 a red regression proof (exit 0) writes stack-health: red, its pass having left c.test.sh owed, with its head, pass and total, over the stub" \
  "0|$(vt_sh_line red "$VT_C" 2 3 record/wave-01-fixture/whole-red.log c.test.sh)" "$RC|$(vt_head stack-health)"
expect_eq "VT-12b …the line proof-add wrote is the function's rendering" "$(vt_head stack-health)" "$(vt_health)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
VT_D="$(s57_commit "$VT_WT" lib/c.sh D)"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture "$PVT" "$VT_DIR/whole-green.log" "$VT_D" 0 0
poke "$RVT" proof-add regression record/wave-01-fixture/whole-green.log
expect_eq "VT-13 a green regression proof (exit 0) replaces the line it wrote: one stack-health: line, green with its numbers" \
  "0|$(vt_sh_line green "$VT_D" 3 3 record/wave-01-fixture/whole-green.log)" "$RC|$(vt_head stack-health)"
expect_eq "VT-13b …still above the table, auditor-wave: beside it" "stack-health,auditor-wave,table" "$(vt_order)"
# A declared n/a: is the plan's word that stack health does not apply, so a proof leaves it as written.
sed 's/^stack-health: .*/stack-health: n\/a: no long-running serve/' "$PVT" > "$PVT.tmp" && mv "$PVT.tmp" "$PVT"
VT_E="$(s57_commit "$VT_WT" lib/d.sh E)"
printf 'Gating: 3 passed, 0 failed\n' | regression_fixture "$PVT" "$VT_DIR/whole-na.log" "$VT_E" 0 0
poke "$RVT" proof-add regression record/wave-01-fixture/whole-na.log
expect_eq "VT-14 a declared stack-health: n/a: is left as the plan wrote it (the proof registers, exit 0)" \
  "0|stack-health: n/a: no long-running serve|1" \
  "$RC|$(vt_head stack-health)|$(s46_proved "$PVT" | /usr/bin/grep -c "^proved: kind=regression head=$VT_E ")"
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
# The tick starts `regression-run --starter tick` detached through booked.sh as the roster object
# `regression@<h8>`, whose one suite is run.sh, and never waits on it; the run's proof lands through
# proof-add regression. A landing past that proof moves the head, so the next tick starts again there. A
# live object is the guard: the next tick starts nothing beside it. A run the gate did not admit (75) is
# told as waiting and started again.
# FIXTURE FIDELITY: §VERDICTS's shape built fresh: a plan bound to this session at Step 4, its working
# branch in a linked worktree, real commits, a regression proof at an older head written by proof-add over
# a run line from the product's writer (regression_fixture). The runner is the worktree's own committed
# tests/run.sh, a stub that holds while a hold file stands, exits 75 with no verdict while a full file
# stands, and otherwise reports a green whole run; everything else is the real tick, booked.sh,
# regression-run and proof-add. The writer row is the production writer's (mkrow), closed by the real ack.
# fails-when: the quiet condition is inverted (a writer row open still starts, or a quiet roster does not);
# the head comparison reads anything but the last regression proof's head; the detached call drops
# proof-add; a live object does not stop a second start; a 75 is not told and not started again.
ST_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RST="$(make_repo starter)"; ( cd "$RST" && git commit -q --allow-empty -m init )
git -C "$RST" config user.name "Dana Fixture"
ST_CTL="$TMPROOT/starter-ctl"; mkdir -p "$ST_CTL"
mkdir -p "$RST/tests"
cat > "$RST/tests/run.sh" <<RUNNER
#!/bin/bash
# The fixture's whole run: holds while the hold file stands, exits 75 with no verdict while the full file stands.
i=0; while [ -e "$ST_CTL/hold" ] && [ "\$i" -lt 600 ]; do i=\$((i + 1)); sleep 0.1; done
[ ! -e "$ST_CTL/full" ] || exit 75
printf 'Gating: 1 passed, 0 failed\n'
RUNNER
( cd "$RST" && git add tests/run.sh && git commit -qm runner ) >/dev/null 2>&1
ST_B="$(git -C "$RST" rev-parse HEAD)"
PST="$(s42_plan "$RST" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${ST_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PST" > "$PST.tmp" && mv "$PST.tmp" "$PST"
( cd "$RST" && git add -f "$PST" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RST/.worktrees/01-fixture" "$ST_B" ) >/dev/null 2>&1
ST_WT="$RST/.worktrees/01-fixture"; ST_DIR="$RST/.bionic/docs/record/wave-01-fixture"; mkdir -p "$ST_DIR"
ST_H0="$(s57_commit "$ST_WT" lib/a.sh H0)"
printf 'Gating: 1 passed, 0 failed\n' | regression_fixture "$PST" "$ST_DIR/whole-h0.log" "$ST_H0" 0 0
poke "$RST" proof-add regression record/wave-01-fixture/whole-h0.log
expect_eq "ST-0 precondition: the plan holds a regression proof at H0 (proof-add exit 0)" "0|$ST_H0" "$RC|$(s46_last "$PST" regression)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
ST_H1="$(s57_commit "$ST_WT" lib/a.sh H1)"
new_roster "$RST"
add_row "$RST" name=w-T2 agent_id=a-w-T2 subagent_type=implementor launched_at="$(iso_ago 60)" \
  deliverable="$RST/record/T2.md" duration=60m
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
st_runline() { /usr/bin/grep -F "|ev=run|log=$1|" "$(st_rec)" 2>/dev/null | tail -n 1; }   # <log from its root> -> its run line
: > "$ST_CTL/hold"

# Each tick below but one forgets the last digest, so it prints in full and a line it did not print is a
# line it did not say. The one that keeps it (ST-6) is the tick whose only news is the start itself.
# The control: T2 still writes (its row active, its writer open on the roster), so nothing starts.
forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-1-pre the control tick printed its decision line (the extractor reads real output)" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker-tick/v1|')"
expect_eq "ST-1 AC-6.1 control: with a writer row running, the tick starts nothing and the roster holds no object" \
  "|" "$(st_started)|$(st_objects "${ST_H1:0:8}")"

# Quiet: every row landed, the writer closed by its ack, the head past the proof.
s42_builds_landed "$PST"
awk '/^\| T5 \| 5 \| verify \|/ { sub(/\| pending \|$/, "| landed |") } { print }' "$PST" > "$PST.tmp" && mv "$PST.tmp" "$PST"
ack_rows "$RST" w-T2
forget_digest "$RST"; poke "$RST" tick
expect_contains "ST-2 AC-6.1 nothing ready, no writer open, the head past the proof: the tick starts regression-run as regression@<h8>" \
  "poker: regression-run started regression@${ST_H1:0:8} (log $(st_log "${ST_H1:0:8}"))" "$(st_started)"
[ -n "$(st_started)" ] || printf '      the tick said: %s\n' "$OUT"
expect_contains "ST-2b …and the roster holds the object: a run row, its one suite run.sh, a read-only role, waived as no agent" \
  "|status=run|" "$(st_objects "${ST_H1:0:8}" | head -n 1)"
expect_contains "ST-2c …whose budget is run.sh, so the gate's whole-run budget admits it" "|suites_allowed=run.sh|" \
  "$(st_objects "${ST_H1:0:8}" | head -n 1)"
expect_true "ST-2d …and booked.sh marks the run on it (run_pid=)" st_until 20 eval 'st_objects "${ST_H1:0:8}" | /usr/bin/grep -q "|run_pid="'
expect_true "ST-2e …and the tick did not wait on it: the run is still held by the runner when the tick has returned" \
  test ! -e "$(st_log "${ST_H1:0:8}").rc"

# The guard: a live object for this head means the next tick starts nothing beside it.
forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-3-pre the guard tick names the live run (the extractor reads real output)" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep "^poker: RUNNING regression@${ST_H1:0:8} run=")"
expect_eq "ST-3 a live regression@<h8> object: the next tick starts nothing, and the roster still names one run" \
  "|1" "$(st_started)|$(st_starts "${ST_H1:0:8}")"
rm -f "$ST_CTL/hold"
expect_true "ST-4-pre the detached run ends once the runner is let go" st_until 60 st_ended "$(st_log "${ST_H1:0:8}")"
expect_eq "ST-4 AC-6.3 the started run leaves its proof in the plan through proof-add: proved: kind=regression head=<H1>" "1" \
  "$(s46_proved "$PST" | /usr/bin/grep -c "^proved: kind=regression head=$ST_H1 ")"
[ "$(s46_proved "$PST" | /usr/bin/grep -c "^proved: kind=regression head=$ST_H1 ")" = 1 ] || sed -n '1,40p' "$(st_log "${ST_H1:0:8}")"
expect_contains "ST-4b …from a run whose run line names the tick as its starter" "|starter=tick|" \
  "$(st_runline "record/wave-01-fixture/regression-run-$ST_H1.log")"
expect_contains "ST-4c …and booked.sh's own run line for the detached run carries the command's --starter too" "|starter=tick|" \
  "$(st_runline ".bionic/tmp/runs/regression_${ST_H1:0:8}-run.sh.log")"
forget_digest "$RST"; poke "$RST" tick
expect_nonempty "ST-5-pre the tick at the proved head printed its decision line" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker-tick/v1|')"
expect_eq "ST-5 control: the head is the last proof's, so nothing starts" "" "$(st_started)"

# A fix row lands past the proof: the head moved, so the next tick starts again there. The runner is full
# first, so the run ends 75 with no verdict, and the tick after it says so and starts it again.
: > "$ST_CTL/full"
ST_H2="$(s57_commit "$ST_WT" lib/b.sh H2)"
poke "$RST" tick
expect_contains "ST-6 AC-6.2 a landing past the proof: the next tick starts again at the new head" \
  "poker: regression-run started regression@${ST_H2:0:8} " "$(st_started)"
expect_true "ST-6b …its run ends 75, the gate's word that nothing ran" st_until 60 st_ended "$(st_log "${ST_H2:0:8}")"
expect_eq "ST-6c …read off its log's end" "75" "$(cat "$(st_log "${ST_H2:0:8}").rc" 2>/dev/null)"
rm -f "$ST_CTL/full"
forget_digest "$RST"; poke "$RST" tick
expect_eq "ST-7 the tick after a 75 says the gate had no room, once" "1" "$(st_waiting)"
expect_contains "ST-7b …and starts the run again at the same head, as a second attempt" \
  "poker: regression-run started regression@${ST_H2:0:8} (log $(st_log "${ST_H2:0:8}" -2))" "$(st_started)"
ST_LOG2="$(st_started | sed -n 's/^.*(log \(.*\))$/\1/p')"
expect_true "ST-7c …which ends" st_until 60 st_ended "${ST_LOG2:-$TMPROOT/none}"
expect_eq "ST-7d …with its proof at the new head" "1" "$(s46_proved "$PST" | /usr/bin/grep -c "^proved: kind=regression head=$ST_H2 ")"
POKE_BOUND="$ST_BOUND_WAS"


# ============================================================
section "§WALK: the walk's verdicts settle the cells they confirm, through proof-add walk, never a status write"
# ============================================================
# The walk record carries the critic's shape: a `| AC | verdict | why |` table and one flush-left `verdict:` line, read
# by proof_verdicts. `proof-add walk <record>` writes, in one plan write: status `discharged` and the record as evidence
# (cell and block key) for each CONFIRMED row no landing settled; every other row as it stands; the Step-5 block's and
# the matrix head's `walk-artifact:`; a `proved: kind=walk` line. It appends one `ev=walk` line to the landing record,
# never `ev=matrix-set`, so the hand-holds fold counts no status write.
#
# FIXTURE FIDELITY. §VERDICTS' shape built fresh: a plan bound to this session at Step 5, its working branch in a linked
# worktree, real commits, the matrix rendered by matrix-render from the plan's Eval design with `walk: required`, so the
# head carries the stub the gate reads. The one landing-settled row is written as `line_settle` leaves it: its cells
# discharged with the landing's log, and the landing record's `ev=settled` line through the product's line_event.
WK_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RWK="$(make_repo walk)"; ( cd "$RWK" && git commit -q --allow-empty -m init )
git -C "$RWK" config user.name "Dana Fixture"
WK_B="$(git -C "$RWK" rev-parse HEAD)"
PWK="$(s42_plan "$RWK" 5 "  worktree: .worktrees/01-fixture
  base-sha: ${WK_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PWK" > "$PWK.tmp" && mv "$PWK.tmp" "$PWK"
s42_builds_landed "$PWK"
awk '/^## Verification Matrix/ {
       print "## Eval design\n"
       print "| Requirement | Criterion | Approach | Eval | Fails when |"
       print "|---|---|---|---|---|"
       print "| REQ-1 | AC-1.1 | hermetic | `tests/a.test.sh` | a is wrong |"
       print "| REQ-1 | AC-1.2 | hermetic | `tests/b.test.sh` | b is wrong |"
       print "| REQ-1 | AC-1.3 | hermetic | `tests/c.test.sh` | c is wrong |\n" }
     { print }
     /^\| AC-1\.1 \| T2 \|/ { print "| AC-1.2 | T2 | pending | — | — |"; print "| AC-1.3 | T2 | pending | — | — |" }' \
  "$PWK" > "$PWK.tmp" && mv "$PWK.tmp" "$PWK"
sed -e 's/^rigor: .*/rigor: single/' -e 's/^walk: .*/walk: required/' "$PWK" > "$PWK.tmp" && mv "$PWK.tmp" "$PWK"
( cd "$RWK" && git add -f "$PWK" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RWK/.worktrees/01-fixture" "$WK_B" ) >/dev/null 2>&1
WK_WT="$RWK/.worktrees/01-fixture"; WK_DIR="$RWK/.bionic/docs/record/wave-01-fixture"; mkdir -p "$WK_DIR"
WK_A="$(s57_commit "$WK_WT" lib/a.sh A)"
WK_C="$(s57_commit "$WK_WT" lib/c.sh C)"
wk_row() { /usr/bin/grep -E "^\| $1 \|" "$PWK"; }   # <AC> -> its matrix table row, whole
wk_key() {  # <AC> <key> -> the AC block's <key>: value
  awk -v a="$1:" -v k="$2" '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } !m { next }
    index($0, a) == 1 { b = 1; next } b && /^[^ \t]/ { b = 0 }
    b { t = $0; sub(/^[ \t]+/, "", t); if (index(t, k ":") == 1) { sub(/^[^:]*:[ \t]*/, "", t); print t; exit } }' "$PWK"
}
wk_head() { awk -v k="$1" '/^## Verification Matrix/ { m = 1; next } /^## / { m = 0 } m && index($0, k ":") == 1' "$PWK" | paste -sd';' -; }
wk_step5() {  # -> the Step 5 block's walk-artifact: lines, trimmed, `;`-joined
  awk '/^- Step 5:/ { s = 1; next } s && /^- / { s = 0 } s && /^[ \t]+walk-artifact:/ { t = $0; sub(/^[ \t]+/, "", t); print t }' "$PWK" | paste -sd';' -
}
wk_recfile() { bash -c '. "$1/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "${S46_LIB%/*}" "$PWK"; }
wk_ev() { /usr/bin/grep -F "|ev=$1|" "$(wk_recfile)" 2>/dev/null; }   # <ev> -> its lines in the landing record
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

poke "$RWK" matrix-render
expect_eq "WK-0 setup: matrix-render renders the head with the walk stub (exit 0)" "0|walk-artifact: pending" "$RC|$(wk_head walk-artifact)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
# The first fixture criterion settled by a landing, as line_settle writes it: cells and block key, and the settled line.
WK_SET_LOG="record/wave-01-fixture/T2-a.test.sh.log"; printf 'head=%s rc=0\n' "$WK_A" > "$RWK/.bionic/docs/$WK_SET_LOG"
bash -c '. "$1/units.sh" >/dev/null 2>&1 && matrix_row_cells "$2" AC-1.1 "3=discharged" "4=$3" > "$2.c" && matrix_block_key "$2.c" AC-1.1 evidence "$3" > "$2" && rm -f "$2.c"' \
  _ "${S46_LIB%/*}" "$PWK" "$WK_SET_LOG"
bash -c '. "$1/line.sh" >/dev/null 2>&1 && line_event "$2" settled row=T2 "commit=$3" findings= cells=AC-1.1' _ "${S46_LIB%/*}" "$PWK" "$WK_A"
( cd "$RWK" && git add -f "$PWK" && git commit -qm settled ) >/dev/null 2>&1
WK_ROW11="$(wk_row AC-1.1)"; WK_ROW13="$(wk_row AC-1.3)"
expect_eq "WK-0b precondition: AC-1.1 reads the landing's discharge and the record names it settled; AC-1.2 and AC-1.3 pending" \
  "| AC-1.1 | T2 | discharged | $WK_SET_LOG | — ||1|pending|pending" \
  "$WK_ROW11|$(wk_ev settled | /usr/bin/grep -c '|cells=AC-1.1|')|$(wk_row AC-1.2 | cut -d'|' -f4 | tr -d ' ')|$(wk_row AC-1.3 | cut -d'|' -f4 | tr -d ' ')"
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

# ---------- one write settles the confirmed cells no landing settled ----------
wk_rec walk 'verdict: REFUTED — AC-1.3 is refuted' - "${WK_ROWS[@]}"
wk_add walk
expect_eq "WK-3 §WALK AC-8.1 AC-8.2 the record with the table and one verdict: line registers (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "WK-4 AC-8.2 the pending CONFIRMED row reads discharged with the walk record as its evidence, cell and block key" \
  "| AC-1.2 | T2 | discharged | record/wave-01-fixture/walk.md | — ||record/wave-01-fixture/walk.md" \
  "$(wk_row AC-1.2)|$(wk_key AC-1.2 evidence)"
expect_eq "WK-5 AC-8.2 the landing-settled CONFIRMED row is the landing's: its row and its evidence key as the landing wrote them" \
  "$WK_ROW11|$WK_SET_LOG" "$(wk_row AC-1.1)|$(wk_key AC-1.1 evidence)"
expect_eq "WK-6 AC-8.2 the REFUTED row stays as it stood, pending" "$WK_ROW13" "$(wk_row AC-1.3)"
expect_contains "WK-6b …(the extractor reads it: its status cell)" "| pending |" "$(wk_row AC-1.3)"
expect_eq "WK-7 AC-8.2 the walk-artifact: pointer is written in both places: the Step 5 block and the matrix head" \
  "walk-artifact: record/wave-01-fixture/walk.md|walk-artifact: record/wave-01-fixture/walk.md" "$(wk_step5)|$(wk_head walk-artifact)"
expect_eq "WK-8 AC-8.2 one proved: kind=walk line at the working head, naming the record" "1" \
  "$(s46_proved "$PWK" | /usr/bin/grep -c "^proved: kind=walk head=$WK_C at=[0-9TZ:-]* evidence=record/wave-01-fixture/walk.md$")"
[ "$(s46_proved "$PWK" | /usr/bin/grep -c '^proved: kind=walk ')" = 1 ] || s46_proved "$PWK" | sed 's/^/      /'
expect_eq "WK-9 AC-8.2 the landing record gains one ev=walk line, naming the record and the one row it discharged" "1" \
  "$(wk_ev walk | /usr/bin/grep -c '|record=record/wave-01-fixture/walk.md|discharged=1|at=')"
expect_eq "WK-9b …and no ev=matrix-set line" "0" "$(wk_ev matrix-set | awk 'END { print NR }')"
poke "$RWK" landing-report --hand-holds --since "$WK_SINCE"
expect_contains "WK-10 AC-8.2 the hand-holds fold over the walk's window reads no status write" "· status-writes=0 ·" "$OUT"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"

# A second walk naming its head on a head: line: the proof names that head; the row the first walk discharged is not a
# landing's, so a CONFIRMED verdict writes it again with the new record.
wk_rec walk-again 'verdict: CONFIRMED — every card read the judge' "head: $WK_A" \
  '| AC-1.2 | CONFIRMED | again |' '| AC-1.3 | CONFIRMED | refixed |'
wk_add walk-again
expect_eq "WK-11 a walk record's head: line is the head its proof names (exit 0)" "0|1" \
  "$RC|$(s46_proved "$PWK" | /usr/bin/grep -c "^proved: kind=walk head=$WK_A .* evidence=record/wave-01-fixture/walk-again.md$")"
expect_eq "WK-11b …and its CONFIRMED rows read discharged with it as their evidence" \
  "discharged record/wave-01-fixture/walk-again.md|discharged record/wave-01-fixture/walk-again.md" \
  "$(wk_row AC-1.2 | awk -F'|' '{ gsub(/ /, "", $4); gsub(/ /, "", $5); print $4 " " $5 }')|$(wk_row AC-1.3 | awk -F'|' '{ gsub(/ /, "", $4); gsub(/ /, "", $5); print $4 " " $5 }')"
wk_rec walk-nohead 'verdict: CONFIRMED — fine' "head: 0123456789012345678901234567890123456789" '| AC-1.2 | CONFIRMED | — |'
s42_snap "$RWK" "$PWK"; wk_add walk-nohead
s42_unchanged "WK-12 a head: line naming no commit of the working branch" 1 "$PWK"
expect_contains "WK-12b …named in the refusal" "head: 0123456789012345678901234567890123456789" "$OUT"
# The control: a hand status write in the same window is counted, so the fold read above counts the walk's window.
poke "$RWK" matrix-set AC-1.3 status=blocked
poke "$RWK" landing-report --hand-holds --since "$WK_SINCE"
expect_contains "WK-13 control: a matrix-set status write in the same window is counted (status-writes=1)" "· status-writes=1 ·" "$OUT"

# ---------- the walk row's landing settles the cells, in deliver's own write ----------
# A record row has no commit, so it lands through deliver, never ready: a verify row whose artifact is a wave's walk
# record is registered by the landing itself. The control is the same deliver with the walk test removed in a doctored
# copy: it lands the row and settles nothing, so the cells read here are the landing's doing.
WK_DREL="record/wave-02-fixture/walk.md"; mkdir -p "$RWK/.bionic/docs/record/wave-02-fixture"
awk '{ print } /^\| T5 \| 5 \| verify \|/ { print "| T6 | 5 | verify | the walk | — | T1, T2 | 30 | REQ-1 | .bionic/docs/'"$WK_DREL"' | — | — | pending |" }' \
  "$PWK" > "$PWK.tmp" && mv "$PWK.tmp" "$PWK"
wk_task() { s48_row "$PWK" "$1" | awk -F'|' '{ print $NF }'; }   # <row> -> its status cell
wk_cell() { wk_row "$1" | awk -F'|' '{ gsub(/ /, "", $4); gsub(/ /, "", $5); print $4 " " $5 }'; }   # <AC> -> status evidence
wk_rec ../wave-02-fixture/walk - - '| AC-1.3 | CONFIRMED | the scorecard read the register |'
s42_snap "$RWK" "$PWK"; poke "$RWK" deliver T6
s42_unchanged "WK-14 AC-8.3 deliver of the walk row whose record has no verdict: line" 1 "$PWK"
expect_contains "WK-14b …the landing refused naming the walk record and the line it lacks" "$WK_DREL" "$OUT"
expect_contains "WK-14c …(and the line)" "verdict:" "$OUT"
wk_rec ../wave-02-fixture/walk 'verdict: CONFIRMED — the scorecard read the register' - '| AC-1.3 | CONFIRMED | the scorecard read the register |'
s42_snap "$RWK" "$PWK"
rd_mutant nowalk 's/RL_WALK="\$rel"; RL_WALK_REAL="\$real"/:/'
expect_eq "WK-15-pre the doctored poker differs from the real one in exactly one line (the doctor took)" "1" \
  "$(diff <(poker_text "$POKER") <(poker_text "$RD_MUT/nowalk/hooks/session-poker.sh") | /usr/bin/grep -c '^>')"
WK_REAL_POKER="$POKER"; POKER="$RD_MUT/nowalk/hooks/session-poker.sh"
poke "$RWK" deliver T6
POKER="$WK_REAL_POKER"
expect_eq "WK-15 control: with the walk test removed, deliver lands the row (exit 0) and settles nothing: AC-1.3 stays blocked, no walk proof" \
  "0|landed|blocked record/wave-01-fixture/walk-again.md|0" "$RC|$(wk_task T6)|$(wk_cell AC-1.3)|$(s46_proved "$PWK" | /usr/bin/grep -c "evidence=$WK_DREL\$")"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
cp "$TMPROOT/s42-before" "$PWK"
poke "$RWK" deliver T6
expect_eq "WK-16 §WALK AC-8.3 deliver lands the walk row (exit 0) and the plan shows its CONFIRMED row discharged with the record" \
  "0|landed|discharged $WK_DREL" "$RC|$(wk_task T6)|$(wk_cell AC-1.3)"
[ "$RC" = 0 ] || printf '      the verb said: %s\n' "$OUT"
expect_eq "WK-16b …in the landing's write: the walk proof, both pointers, and one ev=walk line naming it" \
  "1|walk-artifact: $WK_DREL|walk-artifact: $WK_DREL|1" \
  "$(s46_proved "$PWK" | /usr/bin/grep -c "^proved: kind=walk head=$WK_C .* evidence=$WK_DREL\$")|$(wk_step5)|$(wk_head walk-artifact)|$(wk_ev walk | /usr/bin/grep -c "|record=$WK_DREL|discharged=1|")"
POKE_BOUND="$WK_BOUND_WAS"

finish
