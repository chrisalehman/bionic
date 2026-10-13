#!/bin/bash
# tests/bash-walls-egd.test.sh — the §EG-DERIVE sections of the one-process PreToolUse|Bash
# hook, split out of tests/bash-walls.test.sh at wave-30 T9 (D8, REQ-4 AC-4.1).
#
# NOTHING HERE READS A CLOCK (wave-35 T11; REQ-2 AC-2.2, D11). §EG-DERIVE's cost rows (EGD-7b,
# EGD-7f, EGD-8 and the per-reading mutant EGD-mut4) count what a commit or a derivation does
# over 8 readings and over 88 — the commands it runs below the step that reads them, the reads
# of the plan where it derives — and assert the two counts equal: a pass per reading is a count
# that grows, on any machine, at any load.
#
# The fixtures, the hook runner and §EG-6's plan writer and gate drive live in
# tests/bash-walls.prelude.sh, sourced by both suites. Usage: bash tests/bash-walls-egd.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HOOK="${BIONIC_BASH_WALLS_UNDER_TEST:-${BIONIC_HOOKS_DIR}/bash-walls.sh}"

# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.
. "$(dirname "$0")/bash-walls.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/bound-marker.sh"

require_helpers mk_repo mk_payload run_hook eg6_gate

# ---------------------------------------------------------------------------
section "§EG-DERIVE — the commit wall reads a reading's result as the judge derives it (wave-28 T60; REQ-8 AC-8.6, AC-8.7; D33; A-orch-161)"
# ---------------------------------------------------------------------------
# A reading a `moved:` line re-rates (the user's word sending a finding to defer or to fix) has a result
# its findings derive at their effective ratings, which the judge reads (lib/proof.sh
# `_proof_reading_result`). The wall used to read the `result=` the review registered, so after a re-rating
# the judge and the wall answered a section two ways (§EG-6's promise). The collector (hooks/bash-walls.sh)
# now hands the wall the derived result for the plan it judges. AN OLD `check:` LINE RE-RATES NOTHING
# (wave-31 T32; D6): a reader's rating is final, so a plan still carrying one is judged as written, by the
# wall and the judge alike. FIXTURE FIDELITY: §EG-6's repository, plan writer and gate drive; the records
# are in the shape the producing verb reads (`reviewed:`, `findings:`, `finding:`, `shown:`), the judge
# half is `facts_state` over the same plan text.
EGD_REC="$R_EG6/.bionic/docs/record/w28t60"
mkdir -p "$EGD_REC"
egd_rec() {  # <file> <result> <finding line> -> a one-finding adversarial reading record, the finding shown
  { printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: %s\nscope: piece\nfindings: 1\n' "${H_EG6:0:10}" "$H_EG6" "$2"
    printf '%s\nshown: 1 bash x.sh --twice\n\nwhat the reader found\n' "$3"; } > "$EGD_REC/$1.md"
}
egd_rec adv fail "finding: 1 S2 on x.sh:9 - data lost on a second run"
egd_rec flag flag "finding: 1 S3 off x.sh:9 - a message the reader could not rate"
EGD_DEFERRED='moved: record/w28t60/adv.md#1 to=defer by=Dana at=2026-10-07T12:00:00Z words="defer it to the next wave" why="the user ruled it"'
EGD_REFUTED='check: record/w28t60/adv.md#1 S2 on "data lost on a second run" refuted by=record/w28t60/chk.md'
EGD_SETTLED='check: record/w28t60/flag.md#1 S3 off "a message the reader could not rate" settled=S1:on by=record/w28t60/chk.md'
egd_judge() {  # <question> -> the judge's state of its piece line, over the plan eg6_gate wrote last
  bash -c '. "$1" && facts_state "$2" "$3"' _ "$EG6_LIB" "$R_EG6/.bionic/docs/plans/active.md" "$H_EG6" 2>/dev/null \
    | awk -F'\t' -v q="$1" '$1 == "review" && $2 == q && $4 == "piece" { print $5 }'
}
egd_lib() {  # <plan> <evidence> <written> -> the result the judge derives
  bash -c '. "$1" && _proof_reading_result "$2" "$3" "$4" "$5"' _ "$EG6_LIB" "$1" "$R_EG6/.bionic/docs" "$2" "$3" 2>/dev/null
}

# ---------- a finding moved to defer: the reading written result=fail is derived to flag ----------
EGD_BASE="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)
$(eg6_reading "$H_EG6" adversarial fail record/w28t60/adv.md)"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE")"
expect_status "EGD-1 the newest adversarial reading is result=fail and no line re-rates it: the commit is refused (the control)" 2 "$ST"
expect_contains "EGD-1b …naming the failing reading and its evidence" \
  "- adversarial: the newest reading is result=fail (evidence=record/w28t60/adv.md)" "$ERR"
expect_eq "EGD-1c …and the judge reads that piece line as failing, on the same text" "failing" "$(egd_judge adversarial)"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_DEFERRED")"
expect_eq "EGD-2c precondition: the judge derives flag for the reading its proof line writes as fail (its only finding moved to defer)" \
  "flag|covered" "$(egd_lib "$R_EG6/.bionic/docs/plans/active.md" record/w28t60/adv.md fail)|$(egd_judge adversarial)"
expect_status "EGD-2 §EG-6 AC-8.6 the only finding moved to defer by a moved: line, the Step-6 commit is admitted" 0 "$ST"
expect_absent "EGD-2b …and no reading question is named unanswered" "a reading question is unanswered" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_REFUTED")"
expect_eq "EGD-2d §FINAL-RATING an old refuted check: line re-rates nothing (wave-31 T32): the judge derives fail and holds the piece line failing" \
  "fail|failing" "$(egd_lib "$R_EG6/.bionic/docs/plans/active.md" record/w28t60/adv.md fail)|$(egd_judge adversarial)"
expect_status "EGD-2e …and the wall agrees: the commit is refused, as EGD-1" 2 "$ST"

# ---------- an old check: line settling a finding to fix on a reading written flag re-rates nothing ----------
EGD_FLAGBASE="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)
$(eg6_reading "$H_EG6" adversarial flag record/w28t60/flag.md)"
eg6_gate "$(eg6_plan 6 wave "$EGD_FLAGBASE")"
expect_status "EGD-3 the reading written result=flag and no line re-rating it: the commit is admitted (the control)" 0 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EGD_FLAGBASE
$EGD_SETTLED")"
expect_eq "EGD-4 §FINAL-RATING the judge derives flag for it beside an old check: line settling it to S1 on, and holds the piece line covered (wave-31 T32)" \
  "flag|covered" "$(egd_lib "$R_EG6/.bionic/docs/plans/active.md" record/w28t60/flag.md flag)|$(egd_judge adversarial)"
expect_status "EGD-4b …and the wall agrees: the commit is admitted, as EGD-3" 0 "$ST"

# ---------- a moved finding: the reading written flag is derived to fail at the moved priority ----------
{ printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: flag\nscope: piece\nfindings: 1\n' "${H_EG6:0:10}" "$H_EG6"
  printf 'finding: 1 S2 off x.sh:9 - a side path still wrong\n\nwhat the reader found\n'; } > "$EGD_REC/mv.md"
EGD_MOVED='moved: record/w28t60/mv.md#1 to=fix by=Dana at=2026-10-07T12:00:00Z words="fix it before the release" why="the user ruled it"'
EGD_MVBASE="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)
$(eg6_reading "$H_EG6" adversarial flag record/w28t60/mv.md)"
eg6_gate "$(eg6_plan 6 wave "$EGD_MVBASE")"
expect_status "EGD-5 a reading written flag whose one finding is a deferral, no move: the commit is admitted (the control)" 0 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EGD_MVBASE
$EGD_MOVED")"
expect_eq "EGD-6 precondition: the judge derives fail for it once a moved: line sends the finding to fix, and holds the piece line failing" \
  "fail|failing" "$(egd_lib "$R_EG6/.bionic/docs/plans/active.md" record/w28t60/mv.md flag)|$(egd_judge adversarial)"
expect_status "EGD-6b §EG-6 AC-8.6 the moved priority is the one the wall reads: the commit is refused" 2 "$ST"
expect_contains "EGD-6c …naming the reading failing at its derived result" \
  "- adversarial: the newest reading is result=fail (evidence=record/w28t60/mv.md)" "$ERR"

# ---------- the mutation arm: the wall back on the written result= ----------
EGD_MUT="$SANDBOX/derive-mutant"
mkdir -p "$EGD_MUT/hooks"
cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$EGD_MUT/scripts"
cp "$HOOK" "$EGD_MUT/hooks/bash-walls.sh"
EGD_NEEDLE='r[PROOF_QUESTION] = ((ev SUBSEP PROOF_RESULT) in D) ? D[ev SUBSEP PROOF_RESULT] : PROOF_RESULT;'
anchor "$EGD_MUT/scripts/lib/walls.sh" "$EGD_NEEDLE" 1
EGD_N="$EGD_NEEDLE" awk 'BEGIN { n = ENVIRON["EGD_N"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) "r[PROOF_QUESTION] = PROOF_RESULT;" substr($0, i + length(n)); print }' \
  "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh" > "$EGD_MUT/scripts/lib/walls.sh"
expect_eq "EGD-mut0 the mutant library differs from the shipped one in one line" "1" \
  "$(diff "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh" "$EGD_MUT/scripts/lib/walls.sh" | /usr/bin/grep -c '^>')"
expect_eq "EGD-mut0b …and parses" "0" "$(bash -n "$EGD_MUT/scripts/lib/walls.sh" >/dev/null 2>&1; echo $?)"
EGD_HOOK_KEEP="$HOOK"; HOOK="$EGD_MUT/hooks/bash-walls.sh"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE")"
expect_status "EGD-mut1 the mutant runs: it refuses the failing reading no check names, as the shipped wall does (EGD-1)" 2 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_DEFERRED")"
expect_status "EGD-mut2 …and refuses the one moved to defer the shipped wall admits: EGD-2 goes red" 2 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EGD_MVBASE
$EGD_MOVED")"
expect_status "EGD-mut4 …and admits the moved one the shipped wall refuses: EGD-6b goes red" 0 "$ST"
HOOK="$EGD_HOOK_KEEP"

# ---------------------------------------------------------------------------
section "§EG-DERIVE (T72) — the collector derives only where the gate reads, in one pass (wave-28 T72; REQ-8 AC-8.6, AC-8.7; D33; A-orch-213)"
# ---------------------------------------------------------------------------
# T60's collector ran `proof_readings_derived` on every commit in a bound root at every step, one awk
# over the plan per reading and more per binding line, while the wall reads `BIONIC_READINGS` only from
# `current: 6` (measured on a copy of this wave's plan: 13 s with 88 binding lines, against the hook's 10 s
# clock, past which the CLI lets the commit through). The collector now derives only when the plan's
# declared `current:` is a step the wall reads (lib/walls.sh `eg_plan_reads_readings`, the wall's own
# step rule `eg_step_reads_readings`), only when a `deferred:` or `moved:` line binds a pass (wave-31
# T32 took `check:` out), and in one pass over the plan. FIXTURE FIDELITY: §EG-DERIVE's repository, plan
# writer and gate drive; 88 readings in the producing verb's line shape, each with a record of one finding
# and a `moved:` line sending it to defer;
# the collector's hand-over is read through a COPY of the hook that writes `BIONIC_READINGS` out just
# before the verdict is folded (the copy changes nothing else).
EGD_NOBS="$SANDBOX/egd-readings-seen"
# THE COUNT (tests/hook-timeout.test.sh's tracer). Two numbers come off one trace: the commands
# run, and how many times a command names the plan — every read of the plan names its path, so
# the second is the count of plan reads. Each reading's own record is read once per reading,
# which is work that must grow with the readings; what T72 removed was a read of the PLAN per
# reading (one awk over it each time: 13 s at 88 readings), and that is the count asserted flat.
# THE TRACER: every bash the drive starts sources the prelude
# through BASH_ENV, which points xtrace at fd 87 with a marker in PS4 (BASH_XTRACEFD from bash 4.1;
# bash 3.2 re-points fd 2 before each command instead), and the markers are counted as bytes.
EGD_PRELUDE="$SANDBOX/egd-xtrace-prelude.sh"
cat > "$EGD_PRELUDE" <<'PRELUDE'
exec 87>>"$EGD_TRACE_OUT"
PS4='+|EGDCOUNT|${BASH_SOURCE##*/}:${LINENO}| '
if [ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 1 ]; }; then
  BASH_XTRACEFD=87
else
  exec 2>&87
  set -T
  trap 'exec 2>&87' DEBUG
fi
set -x
PRELUDE
EGD_TRACE="$SANDBOX/egd-trace"
egd_marks() { LC_ALL=C grep -o '|EGDCOUNT|' "$EGD_TRACE" 2>/dev/null | wc -l | tr -d ' '; }
egd_names() {  # <path> -> how many times the trace names <path>: every read of a file names it
  LC_ALL=C grep -o -F -- "$1" "$EGD_TRACE" 2>/dev/null | wc -l | tr -d ' '
}
egd_gate_count() {  # <plan text> -> EGD_CN (commands the commit ran) and ST, traced
  : > "$EGD_TRACE"
  printf '%s\n' "$1" > "$R_EG6/.bionic/docs/plans/active.md"
  bw_bind "$R_EG6"
  run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')" BASH_ENV="$EGD_PRELUDE" EGD_TRACE_OUT="$EGD_TRACE"
  EGD_CN="$(egd_marks)"; EGD_PN="$(egd_names "$R_EG6/.bionic/docs/plans/active.md")"
}
egd_hook() {  # <name> <scripts dir> <code> -> a copy of the hook that runs <code> just before it folds the verdict
  local d="$SANDBOX/egd-hook-$1"
  mkdir -p "$d/hooks"; ln -s "$2" "$d/scripts" 2>/dev/null
  EGD_CODE="$3" awk 'BEGIN { c = ENVIRON["EGD_CODE"] } index($0, "bionic_fold \"$EVENT\"") == 1 { print c } { print }' \
    "$EGD_HOOK_KEEP" > "$d/hooks/bash-walls.sh"
  printf '%s' "$d/hooks/bash-walls.sh"
}
egd_seen() {  # -> `seen|<lines handed>` once the copy has run, `unseen|` before
  if [ -f "$EGD_NOBS" ]; then printf 'seen|%s' "$(grep -c . "$EGD_NOBS")"; else printf 'unseen|'; fi
}
EGD_SCRIPTS="$BIONIC_SCRIPTS_DIR/payload/scripts"
EGD_N=88
EGD_NS=8   # the small plan of each count pair: the first EGD_NS of the same readings and moved: lines
EGD88=""; EGD88_CHECKS=""; EGD8=""; EGD8_CHECKS=""
for _egd_i in $(seq 1 "$EGD_N"); do
  egd_rec "w88-$_egd_i" fail "finding: 1 S2 on x.sh:9 - data lost on a second run"
  _egd_r="$(eg6_reading "$H_EG6" adversarial fail "record/w28t60/w88-$_egd_i.md")"
  _egd_m="moved: record/w28t60/w88-$_egd_i.md#1 to=defer by=Dana at=2026-10-07T12:00:00Z words=\"defer it to the next wave\" why=\"the user ruled it\""
  EGD88="${EGD88:+$EGD88
}$_egd_r"
  EGD88_CHECKS="${EGD88_CHECKS:+$EGD88_CHECKS
}$_egd_m"
  if [ "$_egd_i" -le "$EGD_NS" ]; then
    EGD8="${EGD8:+$EGD8
}$_egd_r"
    EGD8_CHECKS="${EGD8_CHECKS:+$EGD8_CHECKS
}$_egd_m"
  fi
done
EGD88_PLAN_BODY="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)
$EGD88
$EGD88_CHECKS"
EGD8_PLAN_BODY="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)
$EGD8
$EGD8_CHECKS"
EGD_PROBE="$(egd_hook probe "$EGD_SCRIPTS" "printf '%s' \"\$BIONIC_READINGS\" > '$EGD_NOBS'")"
HOOK="$EGD_PROBE"

# ---------- the gate: a commit below the step that reads is not derived for ----------
rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 4 wave "$EGD88_PLAN_BODY")"
expect_eq "EGD-7 precondition: the plan holds $EGD_N reading lines of the adversarial question and $EGD_N moved: lines" \
  "$EGD_N|$EGD_N" "$(grep -c '^proved: .*question=adversarial' "$R_EG6/.bionic/docs/plans/active.md")|$(grep -c '^moved: ' "$R_EG6/.bionic/docs/plans/active.md")"
expect_eq "EGD-7a §EG-DERIVE (T72) at current: 4 the hook ran (the copy wrote its file) and handed the wall no readings" "seen|0" "$(egd_seen)"
ST4_KEEP="$ST"
egd_gate_count "$(eg6_plan 4 wave "$EGD8_PLAN_BODY")";  EGD_C4S="$EGD_CN"; EGD_ST4S="$ST"
egd_gate_count "$(eg6_plan 4 wave "$EGD88_PLAN_BODY")"; EGD_C4L="$EGD_CN"; EGD_ST4L="$ST"
echo "      (EGD-7b counts at current 4: $EGD_C4S commands over $EGD_NS readings, $EGD_C4L over $EGD_N; exits $EGD_ST4S $EGD_ST4L)"
expect_true "EGD-7b0 …the tracer counted both commits, and both took the untraced commit's exit ($ST4_KEEP)" \
  test "${EGD_C4S:-0}" -gt 0 -a "$EGD_ST4S|$EGD_ST4L" = "$ST4_KEEP|$ST4_KEEP"
expect_eq "EGD-7b …and the commit runs as many commands over $EGD_N readings as over $EGD_NS: nothing is done per reading below the step that reads them" \
  "$EGD_C4S" "$EGD_C4L"
rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD88_PLAN_BODY")"
expect_eq "EGD-7c the same plan at current: 6: the collector handed the wall a derived result for each reading it read" \
  "seen|$((EGD_N + 2))" "$(egd_seen)"
expect_eq "EGD-7d …$EGD_N of them written fail and derived flag (every finding moved to defer)" "$EGD_N" \
  "$(awk -F'\t' '$2 == "fail" && $3 == "flag"' "$EGD_NOBS" | grep -c .)"
expect_status "EGD-7e …and the wall read them: the commit is admitted, though every reading was written result=fail" 0 "$ST"
ST6_KEEP="$ST"
egd_gate_count "$(eg6_plan 6 wave "$EGD8_PLAN_BODY")";  EGD_C6S="$EGD_CN"; EGD_P6S="$EGD_PN"; EGD_ST6S="$ST"
egd_gate_count "$(eg6_plan 6 wave "$EGD88_PLAN_BODY")"; EGD_C6L="$EGD_CN"; EGD_P6L="$EGD_PN"; EGD_ST6L="$ST"
echo "      (EGD-7f counts at current 6: $EGD_C6S commands and $EGD_P6S plan reads over $EGD_NS readings, $EGD_C6L and $EGD_P6L over $EGD_N; exits $EGD_ST6S $EGD_ST6L)"
expect_true "EGD-7f0 …the tracer counted both commits reading the plan, and both were admitted as the untraced one was ($ST6_KEEP)" \
  test "${EGD_P6S:-0}" -gt 0 -a "$EGD_ST6S|$EGD_ST6L" = "$ST6_KEEP|$ST6_KEEP"
expect_eq "EGD-7f …and the commit that derives reads the plan as many times over $EGD_N readings as over $EGD_NS: one pass, whatever the count of readings" \
  "$EGD_P6S" "$EGD_P6L"
# the derivation alone, over a plan the size of this wave's: one pass
EGD_TPLAN="$SANDBOX/egd-time.plan.md"; EGD_TPLAN8="$SANDBOX/egd-time8.plan.md"
egd_tplan() {  # <readings body> <dest> -> the bound plan's text over that body, then 3000 prose lines
  { eg6_plan 6 wave "$1"; printf '\n## Notes\n\n'; for _egd_i in $(seq 1 3000); do printf 'prose line %s of the plan body\n' "$_egd_i"; done; } > "$2"
}
egd_tplan "$EGD88_PLAN_BODY" "$EGD_TPLAN"
egd_tplan "$EGD8_PLAN_BODY" "$EGD_TPLAN8"
egd_derive_count() {  # <scripts dir> <plan> -> commands one `proof_readings_derived` runs over <plan> (the records are the fixture's)
  : > "$EGD_TRACE"
  env BASH_ENV="$EGD_PRELUDE" EGD_TRACE_OUT="$EGD_TRACE" \
    bash -c '. "$1/lib/roots.sh" 2>/dev/null; . "$1/lib/proof.sh" && proof_readings_derived "$2" "$3"' _ "$1" "$2" "$R_EG6" >"$SANDBOX/egd-derived.out" 2>/dev/null
  printf '%s %s' "$(egd_marks)" "$(egd_names "$2")"
}
read -r EGD_D8 EGD_DP8 <<<"$(egd_derive_count "$EGD_SCRIPTS" "$EGD_TPLAN8")"
read -r EGD_D88 EGD_DP88 <<<"$(egd_derive_count "$EGD_SCRIPTS" "$EGD_TPLAN")"
echo "      (EGD-8 counts: $EGD_D8 commands and $EGD_DP8 plan reads over $EGD_NS readings, $EGD_D88 and $EGD_DP88 over $EGD_N, each in a $(wc -l < "$EGD_TPLAN" | tr -d ' ')-line plan)"
expect_true "EGD-8a …the tracer counted the derivation reading the plan ($EGD_DP8 reads in $EGD_D8 commands)" test "${EGD_DP8:-0}" -gt 0
expect_eq "EGD-8 §EG-DERIVE (T72) one pass: $EGD_N moved: lines over a $(wc -l < "$EGD_TPLAN" | tr -d ' ')-line plan are derived in as many reads of the plan as $EGD_NS (13 s before, one awk over it per reading)" \
  "$EGD_DP8" "$EGD_DP88"
expect_eq "EGD-8b …and the lines are there to be read (the extractor returns real output): $EGD_N written fail, derived flag" "$EGD_N" \
  "$(awk -F'\t' '$2 == "fail" && $3 == "flag"' "$SANDBOX/egd-derived.out" | grep -c .)"

# ---------- no line binds a pass: nothing to derive, the written results stand ----------
rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE")"
expect_eq "EGD-9 §EG-DERIVE (T72) readings and no deferred: or moved: line, at current: 6: the collector handed the wall nothing" "seen|0" "$(egd_seen)"
expect_status "EGD-9b …and the wall's verdict is the written result's: the failing reading is refused (EGD-1)" 2 "$ST"
rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_DEFERRED")"
expect_eq "EGD-9c …while the same readings with one moved: line are derived (the extractor does return lines)" "seen|3" "$(egd_seen)"
expect_status "EGD-9d …and the reading moved to defer is admitted (EGD-2)" 0 "$ST"
rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_REFUTED")"
expect_eq "EGD-9e §FINAL-RATING …and an old check: line binds no pass (wave-31 T32): the collector hands the wall nothing" "seen|0" "$(egd_seen)"

# ---------- the facts are for one plan: BIONIC_DEBTS_PLAN other than the plan judged ----------
EGD_OTHER="$(egd_hook other "$EGD_SCRIPTS" "printf '%s' \"\$BIONIC_READINGS\" > '$EGD_NOBS'; BIONIC_DEBTS_PLAN=/nonexistent/other.plan.md")"
HOOK="$EGD_OTHER"; rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_DEFERRED")"
expect_eq "EGD-10 §EG-DERIVE (T72) the collector derived the lines (the extractor returns real output)…" "seen|3" "$(egd_seen)"
expect_status "EGD-10b …but handed for another plan than the one judged they are ignored: the failing reading is refused, as written" 2 "$ST"
HOOK="$EGD_PROBE"

# ---------- the mutation arms ----------
# (1) the step gate removed from the collector: the commit at current 4 is derived for
EGD_GATE=' && eg_plan_reads_readings "$BIONIC_DEBTS_PLAN"'
anchor "$EGD_HOOK_KEEP" "$EGD_GATE" 1
EGD_MG="$SANDBOX/egd-mut-gate"; mkdir -p "$EGD_MG/hooks"; ln -s "$EGD_SCRIPTS" "$EGD_MG/scripts"
EGD_N_="$EGD_GATE" awk 'BEGIN { n = ENVIRON["EGD_N_"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(n)); print }' \
  "$EGD_PROBE" > "$EGD_MG/hooks/bash-walls.sh"
expect_eq "EGD-mut0 the gate-removed copy differs from the probe copy in one line" "1" "$(diff "$EGD_PROBE" "$EGD_MG/hooks/bash-walls.sh" | grep -c '^>')"
HOOK="$EGD_MG/hooks/bash-walls.sh"; rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 4 wave "$EGD88_PLAN_BODY")"
expect_eq "EGD-mut1 the mutant derives at current: 4 and hands the wall $((EGD_N + 2)) lines: EGD-7a goes red" "seen|$((EGD_N + 2))" "$(egd_seen)"
# (2) one pass back to one per reading: the old function appended to a copy of the library
EGD_MP="$SANDBOX/egd-mut-pass"; rm -rf "$EGD_MP"; cp -R "$EGD_SCRIPTS" "$EGD_MP"
cat >> "$EGD_MP/lib/proof.sh" <<'EGD_OLD_FN'

proof_readings_derived() {
  local plan="${1:-}" tree="${2:-}" droot="" ev res lines
  [ -f "$plan" ] || return 0
  droot="$(docs_root "$tree" 2>/dev/null)"
  lines="$(awk "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      m = split($0, f, /[ \t]+/); ev = ""
      for (i = 2; i <= m; i++) if (f[i] ~ /^evidence=/) ev = substr(f[i], 10)
      if (ev != "" && !((ev SUBSEP PROOF_RESULT) in seen)) { seen[ev SUBSEP PROOF_RESULT] = 1; print ev "\t" PROOF_RESULT }
    }' "$plan")"
  while IFS='	' read -r ev res; do
    [ -n "$ev" ] || continue
    printf '%s\t%s\t%s\n' "$ev" "$res" "$(_proof_reading_result "$plan" "$droot" "$ev" "$res")"
  done <<PROOF_READINGS
$lines
PROOF_READINGS
}
EGD_OLD_FN
expect_eq "EGD-mut2 the per-reading copy of the library parses" "0" "$(bash -n "$EGD_MP/lib/proof.sh" >/dev/null 2>&1; echo $?)"
read -r _ EGD_MD8 <<<"$(egd_derive_count "$EGD_MP" "$EGD_TPLAN8")"
read -r _ EGD_MD88 <<<"$(egd_derive_count "$EGD_MP" "$EGD_TPLAN")"
expect_eq "EGD-mut3 the per-reading copy derives the same lines (the extractor returns real output)…" "$EGD_N" \
  "$(awk -F'\t' '$2 == "fail" && $3 == "flag"' "$SANDBOX/egd-derived.out" | grep -c .)"
expect_true "EGD-mut4 …but reads the plan more times over $EGD_N readings than over $EGD_NS ($EGD_MD8 then $EGD_MD88): EGD-8 goes red" \
  test "${EGD_MD88:-0}" -gt "${EGD_MD8:-0}"
# (3) nothing binds, yet the collector hands the lines over: the no-binding-line exit removed
EGD_NB='if (!nbind && ENVIRON["PROOF_HAS_FIXED"] == "") exit'
anchor "$EGD_SCRIPTS/lib/proof.sh" "$EGD_NB" 1
EGD_MB="$SANDBOX/egd-mut-bind"; rm -rf "$EGD_MB"; cp -R "$EGD_SCRIPTS" "$EGD_MB"
EGD_N_="$EGD_NB" awk 'BEGIN { n = ENVIRON["EGD_N_"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) "if (0) exit" substr($0, i + length(n)); print }' \
  "$EGD_SCRIPTS/lib/proof.sh" > "$EGD_MB/lib/proof.sh"
expect_eq "EGD-mut5 the copy without the no-binding exit differs from the library in one line" "1" \
  "$(diff "$EGD_SCRIPTS/lib/proof.sh" "$EGD_MB/lib/proof.sh" | grep -c '^>')"
HOOK="$(egd_hook mutbind "$EGD_MB" "printf '%s' \"\$BIONIC_READINGS\" > '$EGD_NOBS'")"; rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE")"
expect_eq "EGD-mut6 the mutant hands the wall the readings' written results as derived lines: EGD-9 goes red" "seen|3" "$(egd_seen)"
# (4) the plan guard removed from the wall: lines handed for another plan are read
EGD_GUARD='[ "${BIONIC_DEBTS_PLAN:-}" != "$PLAN" ] || handed=1'
anchor "$EGD_SCRIPTS/lib/walls.sh" "$EGD_GUARD" 1
EGD_MW="$SANDBOX/egd-mut-guard"; rm -rf "$EGD_MW"; cp -R "$EGD_SCRIPTS" "$EGD_MW"
EGD_N_="$EGD_GUARD" awk 'BEGIN { n = ENVIRON["EGD_N_"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) "handed=1" substr($0, i + length(n)); print }' \
  "$EGD_SCRIPTS/lib/walls.sh" > "$EGD_MW/lib/walls.sh"
expect_eq "EGD-mut7 the guard-removed copy differs from the library in one line" "1" \
  "$(diff "$EGD_SCRIPTS/lib/walls.sh" "$EGD_MW/lib/walls.sh" | grep -c '^>')"
HOOK="$(egd_hook mutguard "$EGD_MW" "printf '%s' \"\$BIONIC_READINGS\" > '$EGD_NOBS'; BIONIC_DEBTS_PLAN=/nonexistent/other.plan.md")"; rm -f "$EGD_NOBS"
eg6_gate "$(eg6_plan 6 wave "$EGD_BASE
$EGD_DEFERRED")"
expect_status "EGD-mut8 the mutant reads the lines handed for another plan and admits the reading moved to defer: EGD-10b goes red" 0 "$ST"
HOOK="$EGD_HOOK_KEEP"


# ---------------------------------------------------------------------------
section "§JURIS — the commit wall's jurisdiction: an outside commit it can place is exempt, one it cannot is refused for the split and never judged by the plan (wave-35 T4; REQ-4 AC-4.2, D13)"
# ---------------------------------------------------------------------------
# WHAT WENT WRONG (A-orch-30, wave-34). A walker committed in its own scratch repository with
# `cd <scratch> && ln -s … payload && git add payload && git commit`. `ln` was not on the
# placement allow-list (`_eg_git_only`: git, true, :, exit), so the commit was not exempted, and
# the gate then judged it against THIS run's bound plan ("Step-5 head … is not a commit in the
# repository at <scratch>"). Two fixes, one ruling (spec D13, tactical 4): the allow-list grows by
# exactly `ln mkdir cp mv rm touch printf echo`, which run in a child or print and cannot move the
# shell; builtins and `GIT_*=` prefixes stay out. A commit the reader places outside the root but
# cannot exempt is refused with a jurisdiction message naming the split, and the bound plan is
# never read for it. FIXTURE FIDELITY: §18's shape, a real engaged repository under `block_plan`
# (current: 5, a placeholder Step-5 line), so every commit the gate still judges is refused by the
# plan, and a real `git init`-ed scratch repository beside it.
JUR_R="$(mk_repo juris)"; block_plan "$JUR_R"
JUR_S="$SANDBOX/scratchpad/juris-scratch"
mkdir -p "$JUR_S"; git -C "$JUR_S" init -q 2>/dev/null
JUR_PLAN_TEXT="Plan: $JUR_R/.bionic/docs/plans/active.md"
JUR_SPLIT="git -C $JUR_S commit"
jur_line() {  # -> the one boundary line an exempt commit into the scratch repository gets
  printf 'evidence-gate: %s is outside the engaged repository (%s); the evidence gate has no plan here' "$JUR_S" "$JUR_R"
}
jur_drive() {  # <command> [payload cwd, default the engaged root] -- the project is the engaged root, as the CLI names it
  run_hook "$(mk_payload "${2:-$JUR_R}" "$1")" CLAUDE_PROJECT_DIR="$JUR_R"
}
jur_exempt() {  # <label> <command> [payload cwd]
  jur_drive "$2" "${3:-}"
  expect_status "$1" 0 "$ST"
  expect_eq "$1 …with exactly the one boundary line" "$(jur_line)" "$ERR"
}
jur_refused() {  # <label> <command> [payload cwd] -> refused by jurisdiction: the split named, the plan never read
  jur_drive "$2" "${3:-}"
  expect_status "$1" 2 "$ST"
  expect_contains "$1 …refused at the boundary" "is outside the engaged repository ($JUR_R)" "$ERR"
  expect_contains "$1 …naming the split" "Split it" "$ERR"
  expect_contains "$1 …and the one command that commits alone" "$JUR_SPLIT" "$ERR"
  expect_absent "$1 …and never judged by the bound plan" "$JUR_PLAN_TEXT" "$ERR"
}

# ---------- the control: the plan judges what lands inside, and its text is what the rows below assert absent ----------
jur_drive 'git commit -m x'
expect_status "JURIS-0 control: a commit in the engaged root under block_plan is judged and refused" 2 "$ST"
expect_contains "JURIS-0b …and the plan's judgment names the plan (the text the refused rows read absent is real output)" "$JUR_PLAN_TEXT" "$ERR"
jur_exempt "JURIS-0c control: 'cd <scratch> && git commit' is exempt today" "cd $JUR_S && git commit -m x"

# ---------- AC-4.2: the walker's form, and each word the list gained ----------
jur_exempt "JURIS-1 AC-4.2 'cd <scratch> && ln -s x y && git add y && git commit' is exempt" \
  "cd $JUR_S && ln -s x y && git add y && git commit -m m"
for _jur_w in "mkdir -p d/e" "cp a b" "mv a b" "rm -f a" "touch a" "printf 'x\\n' > a" "echo x >> a"; do
  jur_exempt "JURIS-2 [${_jur_w%% *}] 'cd <scratch> && $_jur_w && git add -A && git commit' is exempt" \
    "cd $JUR_S && $_jur_w && git add -A && git commit -m m"
done
jur_exempt "JURIS-2b …and from a payload cwd in the scratch repo, 'touch a && git add a && git commit' is exempt" \
  "touch a && git add a && git commit -m m" "$JUR_S"

# ---------- §REQ-9 9a: the moving forms are still refused ----------
jur_refused "JURIS-3 9a R2-2 'cd <scratch> && if cd <root>; then git commit; fi' is still refused" \
  "cd $JUR_S && if cd $JUR_R; then git commit -m x; fi"
jur_refused "JURIS-3b 9a R2-2 …and 'cd <scratch> && time cd <root> && git commit'" \
  "cd $JUR_S && time cd $JUR_R && git commit -m x"
jur_refused "JURIS-3c 9a C1 …and a payload cwd in the scratch repo with 'pushd <root> && git commit'" \
  "pushd $JUR_R && git commit -m x" "$JUR_S"
jur_refused "JURIS-3d …and a moving word behind a word the list gained: 'cd <scratch> && mkdir -p d && pushd <root> && git commit'" \
  "cd $JUR_S && mkdir -p d && pushd $JUR_R && git commit -m x"
jur_refused "JURIS-3e 9a C1 …and 'git -C <scratch> -C <root> commit' (git obeys the last -C)" \
  "git -C $JUR_S -C $JUR_R commit -m x"
jur_refused "JURIS-3f 9a R1 …and two commits, both into the scratch repo (the count decides)" \
  "git -C $JUR_S commit -m x && git -C $JUR_S commit -m y"

# ---------- builtins and GIT_*= stay off the list: refused for the split, the plan never read ----------
jur_refused "JURIS-4 AC-4.2 an outside commit behind a builtin, 'cd <scratch> && export X=1 && git commit'" \
  "cd $JUR_S && export X=1 && git commit -m m"
jur_refused "JURIS-5 …and behind 'pwd', a builtin the list does not name" \
  "cd $JUR_S && pwd && git commit -m m"
jur_refused "JURIS-6 …and with a GIT_*= prefix, 'cd <scratch> && GIT_AUTHOR_NAME=x git commit'" \
  "cd $JUR_S && GIT_AUTHOR_NAME=x git commit -m m"

# ---------- a word the list gained cannot point the scratch repository at the root's .git ----------
# `ln`, `cp`, `mv`, `printf` and `echo` write files, and a `.git` in the scratch directory that
# names the root's repository makes the one commit land in the ROOT while the reader, which asks
# git before the command runs, places it outside. So a `.git` path anywhere in the text, a `$` or
# a glob in one of their segments, or `printf -v`, costs the exemption.
jur_refused "JURIS-7 'cd <scratch> && rm -rf .git && ln -s <root>/.git .git && git commit' is refused" \
  "cd $JUR_S && rm -rf .git && ln -s $JUR_R/.git .git && git add -A && git commit -m m"
jur_refused "JURIS-7b …and 'echo \"gitdir: <root>/.git\" > .git' before the commit" \
  "cd $JUR_S && echo \"gitdir: $JUR_R/.git\" > .git && git commit -m m"
jur_refused "JURIS-7c …and a glob that names it, 'ln -s <root>/.g?t .'" \
  "cd $JUR_S && ln -s $JUR_R/.g?t . && git commit -m m"
jur_refused "JURIS-7d …and an ANSI-C spelling of it, ln -s <root>/\$'\\x2egit' \$'\\x2egit'" \
  "cd $JUR_S && ln -s $JUR_R/\$'\\x2egit' \$'\\x2egit' && git commit -m m"
jur_refused "JURIS-7e …and 'printf -v', which sets a variable in the shell that commits" \
  "cd $JUR_S && printf -v PATH %s /x && git commit -m m"

finish
