#!/bin/bash
# tests/reader.test.sh — payload/scripts/reader.sh, the one program that reads a run's log and answers.
#
# `reader <plan> <question> [args]` reads record/<wave>/run.log, found from the plan by name, folds it,
# and answers one question of a closed list: yes or no by exit code alone, a value as `key=value`
# lines, a list as one `run/v1` line per item.
#
#   §FOLD     a repeated line counts once, a later value answers, a cancelled line is absent, a step written again answers;
#             an act by hand taken again at another time counts again.
#   §NAME     every answer over a planted log equals the answer over it with each line's fields moved.
#   §FORM     a yes or no answer prints nothing; value lines are `key=value`; list lines start `run/v1|`.
#   §UNKNOWN  an unlisted question exits 2 and prints the list.
#   §REST     the twelve log-side questions each answer a planted log in their form, honour the fold, and
#             answer the same with each line's fields moved.
#   §HEADER     the plan's header keys, its body never read as one, in both shapes of a plan, CR-only line ends too.
#   §ROW        a Tasks row is its nine authored cells, named by the table's header in both shapes.
#   §CRITERION  a criterion is its Eval design row, an escaped bar kept as a bar.
#   §CELL       a criterion is discharged only by a standing proof, waiver or approval naming it.
#   §JOIN       a plan's log is found by its name; a header key pointing elsewhere is only words.
#   §READY      ready reads a row's deps from its Tasks cell when the caller names none.
#   §JOIN-14    a version-14 row's waits are its reads cell: ready, stop's ready rows, holds, status; a dropped
#               row is never ready and a wait on it is met; a dispatch with no instant never outranks a fact.
#   §JOIN-15    a nine-cell row's waits are its deps and what its kind and step imply.
#   §SECTION    a task's own section is the heading whose first word is its id, read to the next heading.
#   §PLACES     a plan at each place the run walk admits reads its record; any other place is refused.
#   §TABLE      a fenced table is prose, the heading reads in either case and may go on, the header line is the
#               one naming the key column, and a lone CR ends a line.
#   §WAITS      each row a read names carries the reads naming it; a row reading its own id waits on itself, and
#               one reading live:head still writes the settled head.
#   §HALF       a run whose landings and asks stand partly in the landing record and asks register and partly in
#               its log reads as one run in order, a landing the plan's ledger also copies counted once; brought
#               forward (kept/, its log rewritten), it reads its log alone.
#   §ASK-LOG    lib/owed.sh writes each act on an ask to the run's log on its own clock and never the register, and
#               reads the register, then the log, as one list.
#   §ASK-DOORS  a passing reading closes its question's waiver; the Stop over an approved plan closes the step asks.
#               A registered proof is one proof event in the run's log, the plan byte for byte as it was; a
#               registered walk discharges each criterion it confirms by one proof naming it.
#   §HANDS      an amend, a hold, an extension, an adoption, a by-hand landing and a person's stop of a run each leave
#               one hand event with its reason, through the one writer that refuses an act with none; the tick's
#               withdrawal of a request for the load leaves none.
#   §HELD       the run's held place answers as the whole fold, over every form of the step's and approval's line
#               and every plan this suite built: a home that writes one of the three and is not in the place's list
#               turns it red.
#
# FIXTURE FIDELITY. The plan and its log are real files in a scratch docs tree; the lines are planted.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
READER="${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh"
D="$(mktemp -d)/docs"; H="$(printf 'a%.0s' {1..40})"; G="$(printf 'b%.0s' {1..40})"
plan() {  # <wave> -> a plan whose run log is fed from stdin
  mkdir -p "$D/plans/epic-x" "$D/record/$1"; printf '# %s\n' "$1" > "$D/plans/epic-x/$1.plan.md"
  cat > "$D/record/$1/run.log"
}
ask() { bash "$READER" "$D/plans/epic-x/$W.plan.md" "$@"; }
keys() { ask "$@" | awk -F'|' '{ for (i = 2; i <= NF; i++) if ($i ~ /^(key|row)=/) print substr($i, 5) }' | tr '\n' ' '; }

section "FOLD"
W=fold; plan fold <<EOF
run/v1|ev=step|n=4|by=me|at=2026-11-01T00:00:01Z
run/v1|ev=published|row=T1|commit=c1|kind=queue|at=2026-11-01T00:00:02Z
run/v1|ev=published|row=T1|commit=c1|kind=queue|at=2026-11-01T00:00:03Z
run/v1|ev=published|row=T2|commit=c2|kind=hand|at=2026-11-01T00:00:04Z
run/v1|ev=ask|key=decide:D1|sent=s|at=2026-11-01T00:00:05Z
run/v1|ev=ask|key=decide:D2|sent=s|at=2026-11-01T00:00:06Z
run/v1|ev=ask|key=decide:D1|sent=s|reply=yes|at=2026-11-01T00:00:07Z
run/v1|ev=proof|kind=regression|head=$H|rc=1|at=2026-11-01T00:00:08Z
run/v1|ev=proof|kind=regression|head=$H|rc=0|at=2026-11-01T00:00:09Z
run/v1|ev=approval|key=step3|by=me|at=2026-11-01T00:00:10Z
run/v1|ev=approval|key=release|by=me|at=2026-11-01T00:00:11Z
run/v1|ev=cancel|of=approval|key=release|at=2026-11-01T00:00:12Z
run/v1|ev=step|n=5|by=me|at=2026-11-01T00:00:13Z
EOF
expect_eq "a repeated line counts once: two landings, not three" "T1 T2 " "$(keys landed)"
expect_eq "a later value answers: the replied ask is closed, the other open" "decide:D2 " "$(keys asks)"
ask green "$H"; expect_status "a later value answers: the regression rerun at rc=0 is green" 0 "$?"
expect_eq "a later value answers: one proof at the head, the later" "rc=0" "$(ask proof "$H" | grep -o 'rc=[0-9]')"
ask approved step3; expect_status "an approval no cancel names is a yes" 0 "$?"
ask approved release; expect_status "a cancelled approval is absent" 1 "$?"
expect_eq "the later step answers" "n=5 state=open" "$(ask step | tr '\n' ' ' | sed 's/ $//')"
printf 'run/v1|ev=step|n=4|by=me|at=2026-11-01T00:00:14Z\n' >> "$D/record/fold/run.log"; expect_eq "a step written again is the step the run went back to" "n=4 state=open " "$(ask step | tr '\n' ' ')"
W=back14; printf '## SDLC State\ncurrent: 1\n- Step 0: a\n- Step 1: a\n- Step 4: a\n' > "$D/plans/epic-x/back14.plan.md"; expect_eq "a version-14 plan taken back stands at its current:, its Step lines the history" "n=1 state=open " "$(ask step | tr '\n' ' ')"
for f in 'current: 4\r\n|CRLF' '   current :  4\n|indented' 'current:4\n|unspaced' 'current: 4\ncurrent: x\n|the first of two'; do
  W=form; printf "## SDLC State\n${f%|*}- Step 3: a\n" > "$D/plans/epic-x/form.plan.md"; expect_eq "a version-14 current: ${f#*|} is read as the gate reads it" "n=4 state=open " "$(ask step | tr '\n' ' ')"; done
printf '## SDLC State\rcurrent: 4\r- Step 3: a\r' > "$D/plans/epic-x/form.plan.md"; expect_eq "a version-14 current: on CR-only line ends is read" "n=4 state=open " "$(ask step | tr '\n' ' ')"
for f in '- Step 8: a\n|with no Step 9 line' '- Step 9: drafted\n|with its Step 9 line not delivered' '- Step 9: report, delivered: x\n|delivered'; do
  printf "## SDLC State\ncurrent: 9\n${f%|*}" > "$D/plans/epic-x/form.plan.md"; W=form; s=open d=no; [ "${f#*|}" = delivered ] && s=delivered d=x
  expect_eq "a version-14 plan at 9 ${f#*|} stands at 9, $s, its delivery the step's own field" "n=9 delivered=$d state=$s " "$(ask step | tr '\n' ' ')"; done
printf '## SDLC State\n- Step 3: a\n- Step 4: a\n' > "$D/plans/epic-x/form.plan.md"; expect_eq "Step lines with no current: are no step" "state=open " "$(ask step | tr '\n' ' ')"
W=fields; plan fields < /dev/null; bash -c '. "$1/proof.sh" && proof_step_event "$2" 8 cleanup=done && ! proof_step_event "$2" 8 merge=main' _ "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib" "$D/plans/epic-x/fields.plan.md"
expect_eq "a field given at the advance is in the step's answer, and one its step does not carry is refused unwritten" "n=8 cleanup=done state=open |1" "$(ask step | tr '\n' ' ')|$(grep -c . "$D/record/fields/run.log")"
W=form; printf '## SDLC State\ncurrent: 9\n- Step 8: closed\n  merge: main\n  cleanup: done\n- Step 9: delivered: v1\n  archived: /a\n' > "$D/plans/epic-x/form.plan.md"
expect_eq "a version-14 step's own fields are read from its block, and no other line of it" "n=9 delivered=v1 archived=/a state=delivered " "$(ask step | tr '\n' ' ')"
for f in '- approved-by: u 2026-01-01T00:00Z "ok"|0' '  approved-by: u 2026-01-01T00:00Z "ok"|0' 'approved-by:  |1'; do
  printf '## SDLC State\ncurrent: 4\n%s\n' "${f%|*}" > "$D/plans/epic-x/form.plan.md"; ask approved step3; expect_status "the approval line '${f%|*}' is read as the fill reads it" "${f#*|}" "$?"; done

# fails-when: a proof is identified without its scope, so a piece reading replaces a whole one of the same question
# at the same head, and the judge over the reader reads the whole read absent.
W=scope; plan scope <<EOF
run/v1|ev=proof|kind=review|head=$H|question=adversarial|result=pass|scope=whole|at=2026-11-01T00:00:01Z
run/v1|ev=proof|kind=review|head=$H|question=adversarial|result=pass|scope=piece|at=2026-11-01T00:00:02Z
run/v1|ev=proof|kind=review|head=$H|question=adversarial|result=fail|scope=piece|at=2026-11-01T00:00:03Z
EOF
expect_eq "a whole and a piece reading at one head are two facts, the later piece replacing the earlier" "whole/pass piece/fail " \
  "$(ask reviews "$H" | awk -F'|' '{ for (i = 2; i <= NF; i++) { if ($i ~ /^scope=/) s = substr($i, 7); if ($i ~ /^result=/) r = substr($i, 8) } printf "%s/%s ", s, r }')"
# fails-when: a review proof is identified without its record, so a second record of one question at one head and
# scope replaces the first and a finding of the first reads unregistered; or a check is, so a rerun stands beside it.
W=records; plan records <<EOF
run/v1|ev=proof|kind=review|head=$H|question=structure|result=fail|scope=piece|evidence=r/b.md|at=2026-11-01T00:00:01Z
run/v1|ev=proof|kind=review|head=$H|question=structure|result=fail|scope=piece|evidence=r/c.md|at=2026-11-01T00:00:02Z
run/v1|ev=proof|kind=check|head=$H|rc=1|evidence=r/1.log|at=2026-11-01T00:00:03Z
run/v1|ev=proof|kind=check|head=$H|rc=0|evidence=r/2.log|at=2026-11-01T00:00:04Z
EOF
expect_eq "two review records of one question at one head and scope both stand, and a check's rerun replaces it" "r/b.md r/c.md r/2.log " \
  "$(ask proof "$H" | awk -F'|' '{ for (i = 2; i <= NF; i++) if ($i ~ /^evidence=/) printf "%s ", substr($i, 10) }')"

# fails-when: two open debts of one concept and two kinds are one fact; a burned line closes another kind than its own.
W=debtkind; mkdir -p "$D/plans/epic-x" "$D/record/debtkind"; printf '# debtkind\n' > "$D/plans/epic-x/debtkind.plan.md"
printf '%s\n' 'cv | duplicate | a.sh:1 | raised-by r.md | touches 1 | —' 'cv | unpinned-pair | b.sh:2 | raised-by r.md | touches 2 | —' > "$D/record/debtkind/debt.md"
dkinds() { ask debts | awk -F'|' '{ for (i = 2; i <= NF; i++) if ($i ~ /^kind=/) printf "%s ", substr($i, 6) }'; }
expect_eq "two open debts of one concept and two kinds are two facts" "duplicate unpinned-pair " "$(dkinds)"
printf '%s\n' 'cv | duplicate | a.sh:1 | raised-by r.md | touches 1 | burned T9' 'cv | unpinned-pair | b.sh:2 | raised-by r.md | touches 2 | —' > "$D/record/debtkind/debt.md"
expect_eq "a burned line closes the debt of its own kind, and the other stays open" "unpinned-pair " "$(dkinds)"

# fails-when: two acts by hand equal but for their time are one fact, so a second amend of one agent for one reason
# goes uncounted; two equal lines with no time, which nothing tells apart, are two; a cancel naming the act misses one.
W=twice; plan twice <<EOF
run/v1|ev=hand|what=amend|name=w1|by=s|why=the brief missed a.sh|at=2026-11-01T00:00:01Z
run/v1|ev=hand|what=amend|name=w1|by=s|why=the brief missed a.sh|at=2026-11-01T00:00:02Z
run/v1|ev=hand|what=stop-run|name=w2|why=an older line
run/v1|ev=hand|what=stop-run|name=w2|why=an older line
EOF
whats() { ask hands | awk -F'|' '{ for (i = 2; i <= NF; i++) if ($i ~ /^what=/) printf "%s ", substr($i, 6) }'; }
expect_eq "two amends of one agent for one reason at two times are two acts; two equal untimed lines are one" "amend amend stop-run " "$(whats)"
printf 'run/v1|ev=cancel|of=hand|what=amend|name=w1|by=s|why=the brief missed a.sh|at=2026-11-01T00:00:03Z\n' >> "$D/record/twice/run.log"
expect_eq "…and a cancel naming the act by its fields retracts it at each time it was taken" "stop-run " "$(whats)"

section "NAME"
QS=("step" "approved step3" "approved release" "green $H" "green $G" "proof $H" "proof $H regression" "landed" "asks")
answers() { local q; for q in "${QS[@]}"; do W=$1; out="$(ask $q)"; printf '%s rc=%s %s\n' "$q" "$?" "$out"; done; }
awk -F'|' -v OFS='|' '{ f = $2; for (i = 2; i < NF; i++) $i = $(i + 1); $NF = f; print }' \
  "$D/record/fold/run.log" | plan moved
expect_regex "the moved log has ev off its place" '^run/v1\|n=4\|by=me\|at=[^|]*\|ev=step$' "$(head -1 "$D/record/moved/run.log")"
expect_contains "the planted log answers a list with lines" "proof $H rc=0 run/v1|ev=proof|" "$(answers fold)"
expect_eq "every answer is the same with each line's fields moved" "$(answers fold)" "$(answers moved)"

section "FORM"
W=fold; out="$(ask approved step3)"; expect_status "a yes exits 0" 0 "$?"; expect_empty "a yes prints nothing" "$out"
out="$(ask green "$G")"; expect_status "a no exits 1" 1 "$?"; expect_empty "a no prints nothing" "$out"
out="$(ask step)"; expect_nonempty "a value answer prints" "$out"
expect_eq "every value line is key=value" "" "$(printf '%s\n' "$out" | grep -Ev '^[a-z][a-z0-9_-]*=')"
out="$(ask landed; ask asks; ask proof "$H")"; expect_eq "the lists print four lines" 4 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
expect_eq "every list line starts run/v1|" "" "$(printf '%s\n' "$out" | grep -v '^run/v1|ev=')"
W=done; printf 'run/v1|ev=step|n=9|by=me|at=2026-11-01T00:00:01Z\n' | plan done
expect_eq "a run at Step 9 is delivered" "n=9 state=delivered" "$(ask step | tr '\n' ' ' | sed 's/ $//')"
W=gone; printf 'run/v1|ev=step|n=6|at=2026-11-01T00:00:01Z\nrun/v1|ev=abandon|by=me|why=w|at=2026-11-01T00:00:02Z\n' | plan gone
expect_eq "an abandoned run says so" "n=6 state=abandoned" "$(ask step | tr '\n' ' ' | sed 's/ $//')"

section "UNKNOWN"
W=fold; out="$(ask nosuch 2>&1)"; expect_status "an unlisted question exits 2" 2 "$?"
for q in step approved proof green landed asks; do expect_contains "the refusal lists $q" "$q" "$out"; done
ask step >/dev/null; expect_status "a listed question is answered" 0 "$?"

section "REST"
# Each row: the question, the field its lines are read by (`-` the whole line), and `rc=<exit> <values>`.
W=rest; t=2026-11-02T00:00; plan rest <<EOF
run/v1|ev=ask|key=approve:step3|sent=s|at=${t}:01Z
run/v1|ev=ask|key=approve:release|sent=s|holds=T9|at=${t}:02Z
run/v1|ev=ask|key=decide:D1|sent=s|at=${t}:03Z
run/v1|ev=proof|kind=review|head=$H|question=adversarial|result=pass|at=${t}:04Z
run/v1|ev=proof|kind=review|head=$H|question=adversarial|result=pass|at=${t}:05Z
run/v1|ev=proof|kind=review|head=$G|question=structure|result=fail|at=${t}:06Z
run/v1|ev=waiver|question=evidence|head=$H|by=me|at=${t}:07Z
run/v1|ev=decision|d=D1|verb=put|at=${t}:08Z
run/v1|ev=decision|d=D1|verb=ruled|said=yes|at=${t}:09Z
run/v1|ev=decision|d=D2|verb=put|at=${t}:10Z
run/v1|ev=finding|ref=F1|to=defer|at=${t}:11Z
run/v1|ev=finding|ref=F2|to=carried|at=${t}:12Z
run/v1|ev=finding|ref=F1|to=fix|row=T5|at=${t}:13Z
run/v1|ev=debt|concept=c1|kind=k|at=${t}:14Z
run/v1|ev=debt|concept=c2|kind=k|at=${t}:15Z
run/v1|ev=debt|concept=c2|kind=k|burned=T4|at=${t}:16Z
run/v1|ev=admitted|id=d1|row=T3|at=${t}:17Z
run/v1|ev=admitted|id=d2|row=T3|at=${t}:18Z
run/v1|ev=void|id=d2|why=w|at=${t}:19Z
run/v1|ev=stop|session=s1|state=held|room=2|at=${t}:20Z
run/v1|ev=stop|session=s1|state=free|room=3|at=${t}:21Z
run/v1|ev=order|act=given|said=away|at=${t}:22Z
run/v1|ev=order|act=lifted|said=away|at=${t}:23Z
run/v1|ev=order|act=given|said=away|at=${t}:24Z
run/v1|ev=hand|kind=amend|lacked=x|at=${t}:25Z
run/v1|ev=published|row=T2|commit=c2|kind=hand|at=${t}:26Z
run/v1|ev=published|row=T1|commit=c1|kind=queue|at=${t}:27Z
run/v1|ev=dispatch|row=T3|name=w3|suites=a.test.sh|files=f|at=${t}:28Z
run/v1|ev=dispatch|row=T3|name=w3|suites=b.test.sh|files=f|at=${t}:29Z
run/v1|ev=tree|row=T3|path=/t3|branch=wt/T3|base=c0|at=${t}:30Z
run/v1|ev=returned|row=T3|why=red|at=${t}:31Z
run/v1|ev=dispatch|row=T4|name=w4|at=${t}:32Z
run/v1|ev=cancel|of=dispatch|row=T4|name=w4|at=${t}:33Z
run/v1|ev=handoff|path=/h1|at=${t}:34Z
run/v1|ev=handoff|path=/h2|at=${t}:35Z
run/v1|ev=handoff|path=/h1|at=${t}:36Z
run/v1|ev=verdict|row=T1|commit=c1|suite=s.test.sh|result=red|at=${t}:37Z
run/v1|ev=verdict|row=T1|commit=c1|suite=s.test.sh|result=green|at=${t}:38Z
run/v1|ev=verdict|row=T1|commit=c1|suite=s.test.sh|result=discarded|at=${t}:39Z
run/v1|ev=verdict|row=T1|commit=c1|suite=u.test.sh|result=discarded|at=${t}:40Z
run/v1|ev=verdict|row=T1|commit=c1|suite=u.test.sh|result=red|at=${t}:41Z
EOF
printf '\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n' >> "$D/plans/epic-x/rest.plan.md"
for r in T1 T2 T3 T4; do printf '| %s | 4 | build | t | — | 30 | R | f | out/%s.md |\n' $r $r >> "$D/plans/epic-x/rest.plan.md"; done
REST=("holds|holds|rc=0 step 4,T9" "reviews|question|rc=0 adversarial,structure,evidence" "reviews $H|question|rc=0 adversarial,evidence"
  "ledger|verb|rc=0 put,ruled,put" "ledger D1|verb|rc=0 put,ruled" "findings|to|rc=0 carried,fix" "findings fix|ref|rc=0 F1"
  "debts|concept/id/ref|rc=0 F2,c1,d1" "stop|-|rc=0 room=3,session=s1,state=free,at=${t}:21Z,order=given,asks=3,ready="
  "order|-|rc=0 order=given,said=away,at=${t}:24Z" "hands|kind|rc=0 amend,hand" "handoff|-|rc=0 path=/h1,at=${t}:36Z"
  "status T3|-|rc=0 state=returned,files=f,name=w3,suites=b.test.sh,tree=/t3,branch=wt/T3,base=c0"
  "status T4|-|rc=0 state=pending" "status T1|-|rc=0 state=landed,commit=c1" "ready T4 T1|-|rc=0 " "ready T4 T3|-|rc=1 "
  "ready T3|-|rc=1 " "ready T1|-|rc=1 " "verdicts|result|rc=0 green,red" "verdicts T9|result|rc=0 ")
pick() {  # <field[/field…]|-> -> each line's first named field, or the whole line, joined by commas
  awk -F'|' -v f="$1" 'BEGIN { n = split(f, w, "/") } { v = (f == "-") ? $0 : ""
    for (j = 1; j <= n && v == ""; j++) for (i = 2; i <= NF; i++) if (index($i, w[j] "=") == 1) v = substr($i, length(w[j]) + 2)
    printf "%s%s", (NR > 1 ? "," : ""), v }'
}
rest() { local r q f; for r in "${REST[@]}"; do q="${r%%|*}"; f="${r#*|}"; f="${f%%|*}"; out="$(ask $q)"; printf '%s|rc=%s %s\n' "$q" "$?" "$(printf '%s\n' "$out" | pick "$f")"; done; }
got="$(rest)"; for r in "${REST[@]}"; do expect_eq "${r%%|*} answers its fold" "${r##*|}" "$(printf '%s\n' "$got" | awk -v p="${r%%|*}|" 'index($0, p) == 1 { print substr($0, length(p) + 1) }')"; done
awk -F'|' -v OFS='|' '{ f = $2; for (i = 2; i < NF; i++) $i = $(i + 1); $NF = f; print }' "$D/record/rest/run.log" | plan restmoved
cp "$D/plans/epic-x/rest.plan.md" "$D/plans/epic-x/restmoved.plan.md"
expect_eq "the twelve answer the same with each line's fields moved" "$got" "$(W=restmoved; rest)"
ask status 2>/dev/null; expect_status "status with no row exits 2" 2 "$?"
ask ready 2>/dev/null; expect_status "ready with no row exits 2" 2 "$?"

# Both shapes hold the same authored words with the Tasks columns in other places, so a cell read by
# its place answers one shape wrongly. The older shape also carries the machine's cells and sections.
EVAL='| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-7 | planted | AC-7.1 | unit | `cell` \| `row` | none |
| REQ-7 | planted | AC-7.2 | unit | e2 | f2 |
| REQ-7 | planted | AC-7.3 | unit | e3 | f3 |
| REQ-7 | planted | AC-7.4 | unit | e4 | f4 |
| REQ-7 | planted | AC-7.5 | unit | e5 | f5 |'
mkdir -p "$D/plans/epic-x" "$D/record/old" "$D/record/new"; : > "$D/record/old/run.log"
cat > "$D/plans/epic-x/old.plan.md" <<EOF
---
sdlc-step: 4
rigor: double
log: record/new/run.log
scale-recommendation: "one wave: one plan"
---

## Eval design

$EVAL

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads | suites | lands-on | artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | Read the plan. | w-T1 | — | 120 | REQ-7 | a.sh, b.sh | .worktrees/T1 | 7aff3fc3 | active | approval:plan | r.test.sh | r.test.sh | out/T1.md |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-7.4 | T1 | discharged | e.md | CONFIRMED |
| AC-8.1 | T4 | pending | — | REFUTED |
AC-7.4: read
  user-confirmed: Ann 2026-11-01 saw it
AC-8.1: a row the Eval design lacks
  serves: REQ-8
  user-confirmed: Bo 2026-11-02 tried it
EOF
cat > "$D/plans/epic-x/new.plan.md" <<EOF
---
rigor: single
scale-recommendation: 'one wave'
---

## Goal

release: none, said in prose.

## Eval design

$EVAL

## Tasks

| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | Read the plan. | — | 120 | REQ-7 | a.sh, b.sh | out/T1.md |
| T2 | 4 | build | Ask the log. | T1 | 60 | REQ-4 | c.sh | out/T2.md |
| T3 | 4 | build | Wait on two. | T1, T9 | 30 | REQ-4 | d.sh | out/T3.md |
EOF
both() { local a; W=old; a="$(ask "$@")"; expect_nonempty "$* answers in the older shape" "$a"; W=new; expect_eq "$* reads the same in both shapes" "$a" "$(ask "$@")"; }
flat() { ask "$@" | tr '\n' ' ' | sed 's/ $//'; }

section "HEADER"
W=old; expect_eq "a header key, its quotes dropped" "scale-recommendation=one wave: one plan" "$(ask header scale-recommendation)"
expect_eq "every header key in its order" "sdlc-step rigor log scale-recommendation" "$(ask header | cut -d= -f1 | tr '\n' ' ' | sed 's/ $//')"
W=new; expect_eq "the newer header, its quotes dropped" "rigor=single scale-recommendation=one wave" "$(flat header)"
ask header sdlc-step; expect_status "a key the header lacks answers no" 1 "$?"
W=cr; plan cr < /dev/null; printf -- '---\rrigor: double\rabandoned: 2026-11-01\r---\rbody: no\r' > "$D/plans/epic-x/cr.plan.md"
expect_eq "a CR-only header reads key by key, as a CRLF one does" "rigor=double abandoned=2026-11-01|rigor=double" \
  "$(flat header)|$(printf -- '---\r\nrigor: double\r\n---\r\n' > "$D/plans/epic-x/cr.plan.md"; ask header)"
printf -- '---\ngoals: a · one (x)\nrigor: double\ngoals: b · two (y)\n---\ngoals: body\n' > "$D/plans/epic-x/cr.plan.md"
every() { ( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/plan-read.sh" && plan_read_header "$D/plans/epic-x/cr.plan.md" "$@" ) | tr '\n' '|'; }
expect_eq "a repeated key answers its first line, and with all every line of it in the header, the body not read" \
  "goals=a · one (x)||goals=a · one (x)|goals=b · two (y)|" "$(every goals)|$(every goals all)"

section "ROW"
W=new; expect_eq "a row is its nine authored cells" \
  "id=T2 step=4 kind=build task=Ask the log. deps=T1 size=60 serves=REQ-4 files=c.sh artifact=out/T2.md" "$(flat row T2)"
both row T1
ask row T9; expect_status "a row the table lacks answers no" 1 "$?"
ask row; expect_status "row with no id is refused" 2 "$?"

section "CRITERION"
W=old; expect_eq "a criterion is its Eval design row, an escaped bar read as a bar" \
  "requirement=REQ-7 approach=planted criterion=AC-7.1 eval-type=unit eval=\`cell\` | \`row\` fails-when=none" "$(flat criterion AC-7.1)"
both criterion AC-7.4
ask criterion AC-9.9; expect_status "a criterion the Eval design lacks answers no" 1 "$?"

section "CELL"
W=new; cat > "$D/record/new/run.log" <<EOF
run/v1|ev=proof|kind=eval|head=$H|ac=AC-7.1|rc=0|at=2026-11-01T00:00:01Z
run/v1|ev=cancel|of=proof|kind=eval|head=$H|ac=AC-7.1|at=2026-11-01T00:00:02Z
run/v1|ev=finding|ref=AC-7.1|severity=S2|at=2026-11-01T00:00:03Z
run/v1|ev=approval|key=AC-7.2|by=me|at=2026-11-01T00:00:04Z
run/v1|ev=proof|kind=eval|head=$H|ac=AC-7.4|rc=0|evidence=record/new/e4.md|at=2026-11-01T00:00:05Z
run/v1|ev=proof|kind=eval|head=$H|ac=AC-7.3|rc=1|at=2026-11-01T00:00:06Z
run/v1|ev=waiver|ac=AC-7.5|head=$H|by=me|why=w|at=2026-11-01T00:00:07Z
run/v1|ev=proof|kind=eval|head=$H|ac=AC-9.9|rc=0|at=2026-11-01T00:00:08Z
run/v1|ev=proof|kind=review|question=evidence|head=$H|result=pass|evidence=record/new/a.md|at=2026-11-01T00:00:09Z
run/v1|ev=proof|kind=review|question=evidence|head=$G|result=fail|evidence=record/new/b.md|at=2026-11-01T00:00:10Z
EOF
cells() { local c; for c in 1 2 3 4 5; do printf '%s; ' "$(flat cell "AC-7.$c")"; done; }
expect_eq "discharged only with a standing proof, waiver or approval naming the criterion" \
  "state=pending; state=discharged by=approval; state=pending; state=discharged by=proof; state=discharged by=waiver; " "$(cells)"
every() { ( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/reader.sh" && reader_cells "$D/plans/epic-x/$W.plan.md" "$@" ) | tr '\037\n' ',;'; }
expect_eq "at 15 every criterion in one fold: its state, its tier by its eval type, its proof's evidence, the evidence review at the head (failed, a finding; no head, none), its approval" \
  "AC-7.1,pending,,T1,,CONFIRMED,,REQ-7;AC-7.2,discharged,approval,T1,,CONFIRMED,me 2026-11-01 AC-7.2,REQ-7;AC-7.3,pending,,T1,,CONFIRMED,,REQ-7;AC-7.4,discharged,proof,T1,record/new/e4.md,CONFIRMED,,REQ-7;AC-7.5,discharged,waiver,T1,,CONFIRMED,,REQ-7;|REFUTED|" "$(every "$H")|$(every "$G" | cut -d, -f6)|$(every | cut -d, -f6)"
W=old; expect_eq "at 14 a row the table holds answers its event, else its own cells and block; a row the Eval design lacks follows, tiered by its cell" \
  "AC-7.4,discharged,proof,T1,e.md,CONFIRMED,Ann 2026-11-01 saw it,;AC-8.1,pending,,T4,,REFUTED,Bo 2026-11-02 tried it,REQ-8;" "$(every | tr ';' '\n' | grep -E '^AC-(7.4|8.1),' | tr '\n' ';')"
W=aud; plan aud <<< "run/v1|ev=proof|kind=review|question=evidence|head=$H|result=pass|evidence=record/aud/a.md|at=2026-11-01T00:00:09Z
run/v1|ev=proof|ac=AC-7.3|evidence=record/aud/w.md|at=2026-11-01T00:00:10Z"
sed 's/^| AC-8\.1 |/| AC-7.3 | T1 | pending | — | — |\n| AC-7.5 | T1 | discharged | e5.md | — |\n&/' "$D/plans/epic-x/old.plan.md" | sed 's/\\n/\n/g' > "$D/plans/epic-x/aud.plan.md"
aud() { every "$@" | tr ';' '\n' | awk -F, '$1 ~ /^AC-7\.[345]$/ { printf "%s=%s ", $1, $6 }'; }
expect_eq "at 14 a row a logged proof discharges with no verdict reads the evidence review at the head (none with no head); the table's own rows keep their cells" \
  "AC-7.3=CONFIRMED AC-7.4=CONFIRMED AC-7.5= |AC-7.3= AC-7.4=CONFIRMED AC-7.5= " "$(aud "$H")|$(aud)"
W=wv; plan wv <<< "run/v1|ev=waiver|ac=AC-7.4|by=me|said=let it go|at=2026-11-01T00:00:11Z"; cp "$D/plans/epic-x/old.plan.md" "$D/plans/epic-x/wv.plan.md"
expect_eq "at 14 a row the text discharges, with a logged waiver of it, reads waived by the waiver; with none, discharged by the proof" \
  "state=discharged by=waiver|state=discharged by=proof" "$(flat cell AC-7.4)|$(W=old; flat cell AC-7.4)"
W=old; ask cell AC-9.9; expect_status "a criterion the plan lacks has no cell" 1 "$?"
ask cell; expect_status "cell with no criterion is refused" 2 "$?"

section "JOIN"
W=new; expect_eq "a plan with no pointer key reads its log by name" "state=discharged by=proof" "$(flat cell AC-7.4)"
W=old; expect_eq "a pointer key in the header is never followed: the approval the pointed-at log holds discharges nothing here" \
  "log=record/new/run.log state=pending" "$(flat header log) $(flat cell AC-7.2)"

section "READY"
W=new; printf 'run/v1|ev=%s|at=2026-11-01T00:00:09Z\n' 'published|row=T1|commit=c1|kind=queue' 'approval|key=step3|by=me' 'step|n=4' >> "$D/record/new/run.log"
readies() { local r; for r in "$@"; do ask ready $r; printf '%s=%s ' "${r// /+}" "$?"; done; }
expect_eq "ready reads the deps cell, and deps a caller names stand as given" "T2=0 T3=1 T3+T1=0 T1=1 T7=1 " "$(readies T2 T3 'T3 T1' T1 T7)"

# A version-14 table holds a row's waits in its reads cell: a row id, or a path a row's Files write, is that
# row. A nine-cell table holds them in deps, and its kind and step imply the rest. A1's status cell says
# landed and the log does not: state is the log's, so A2 still waits on it.
JLOG="run/v1|ev=approval|key=step3|by=me|at=2026-11-03T00:00:01Z
run/v1|ev=step|n=4|at=2026-11-03T00:00:02Z
run/v1|ev=ask|key=approve:ship|sent=s|at=2026-11-03T00:00:03Z
run/v1|ev=ask|key=waive:F1|sent=s|at=2026-11-03T00:00:04Z
run/v1|ev=proof|kind=review|head=$H|question=adversarial|result=pass|at=2026-11-03T00:00:05Z"
printf '%s\n' "$JLOG" | plan w14; printf '%s\n' "$JLOG" | plan w15
cat > "$D/plans/epic-x/w14.plan.md" <<'EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads | suites | lands-on | artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | 4 | build | t | — | — | 30 | R | src/a.sh, out/A1.md | — | — | landed | approval:plan | — | — | out/A1.md |
| A2 | 4 | build | t | — | — | 30 | R | out/A2.md | — | — | pending | approval:plan, out/A1.md | — | — | out/A2.md |
| A3 | 4 | build | t | — | — | 30 | R | out/A3.md | — | — | pending | approval:plan, A1 | — | — | out/A3.md |
| A4 | 4 | build | t | — | — | 30 | R | out/A4.md | — | — | pending | approval:plan, approval:ship | — | — | out/A4.md |
| A5 | 8 | integrate | t | — | — | 30 | R | out/A5.md | — | — | pending | approval:plan | — | — | out/A5.md |
EOF
cat > "$D/plans/epic-x/w15.plan.md" <<'EOF'
## Tasks

| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| B1 | 4 | build | t | — | 30 | R | src/b.sh, out/B1.md | out/B1.md |
| B2 | 4 | build | t | B1 | 30 | R | out/B2.md | out/B2.md |
| B3 | 6 | test | t | — | 30 | R | tests/b.test.sh | out/B3.md |
| B4 | 8 | integrate | t | — | 30 | R | out/B4.md | out/B4.md |
EOF
joined() {  # <row…> -> each row's ready exit; the stop's ready= line; each ask holds lists, as key>holds; status of an absent row
  local h; h="$(ask holds | awk -F'|' '{ for (i = 2; i <= NF; i++) { if ($i ~ /^key=/) k = substr($i, 5); if ($i ~ /^holds=/) v = substr($i, 7) }; printf "%s>%s ", k, v }')"
  local rc; ask status Z9 >/dev/null; rc=$?; printf '%s; %s; %s; Z9=%s' "$(readies "$@")" "$(ask stop | grep '^ready=')" "$h" "$rc"
}
land() { printf 'run/v1|ev=published|row=%s|commit=c|kind=queue|at=2026-11-03T00:00:09Z\n' "$1" >> "$D/record/$W/run.log"; }

section "JOIN-14"
W=w14; expect_eq "a reads cell's row and path wait on the row, an approval on its ask; stop lists the ready rows" \
  "A1=0 A2=1 A3=1 A4=1 A5=1 ; ready=A1; approve:ship>A4 waive:F1>A5 ; Z9=1" "$(joined A1 A2 A3 A4 A5)"
land A1; expect_eq "once the row lands its readers are ready, in table order" "A1=1 A2=0 A3=0 A4=1 A5=1 ; ready=A2 A3" "$(joined A1 A2 A3 A4 A5 | cut -d';' -f1-2)"
ask status A1 >/dev/null; expect_status "a row the plan holds has a status" 0 "$?"
printf 'run/v1|ev=%s\n' 'dispatch|row=A1|name=n|at=' 'dispatch|row=A3|name=n|at=' 'stalled|row=A4|at=2026-11-03T00:00:10Z' \
  'dispatch|row=A4|name=n|at=2026-11-03T00:00:11Z' 'stalled|row=A5|at=2026-11-03T00:00:10Z' 'dispatch|row=A5|name=n|at=' >> "$D/record/w14/run.log"
expect_eq "a dispatch with no instant sets a state only alone; a timed one by its time" "A1=landed A3=dispatched A4=dispatched A5=stalled " \
  "$(for r in A1 A3 A4 A5; do printf '%s=%s ' $r "$(ask status $r | sed -n 's/^state=//p')"; done)"
printf '%s\n' "$JLOG" | plan w14d; sed 's/| landed |/| dropped |/' "$D/plans/epic-x/w14.plan.md" > "$D/plans/epic-x/w14d.plan.md"
W=w14d; expect_eq "a dropped row is not ready and says so; a wait on it is met, named or read" \
  "A1=1 A2=0 A3=0 A4=1 A5=1 ; ready=A2 A3|A3+A1=0 |state=dropped" "$(joined A1 A2 A3 A4 A5 | cut -d';' -f1-2)|$(readies 'A3 A1')|$(ask status A1 | head -1)"
printf '%s\n' "$JLOG" | plan w14e; sed 's/| pending | approval:plan, approval:ship |/| dropped | approval:plan, approval:ship |/' "$D/plans/epic-x/w14.plan.md" > "$D/plans/epic-x/w14e.plan.md"
W=w14e; expect_eq "a dropped row is held by no ask: the approval it read holds nothing, the integrate row's waiver still holds it" \
  " waive:F1>A5 " "$(joined A5 | cut -d';' -f3)"

section "JOIN-15"
W=w15; expect_eq "a nine-cell row waits on its deps and what its kind and step imply, and no approval holds it" \
  "B1=0 B2=1 B3=1 B4=1 ; ready=B1; waive:F1>B4 ; Z9=1" "$(joined B1 B2 B3 B4)"
land B1; expect_eq "a test row at Step 6 waits for the code writers before it" "B1=1 B2=0 B3=1 B4=1 ; ready=B2" "$(joined B1 B2 B3 B4 | cut -d';' -f1-2)"

section "SECTION"
SP="$D/plans/epic-x/sec.plan.md"
printf '%s\n' '## Tasks' '' '| id | task |' '|---|---|' '| T1 | one |' '' '## T1 — the first' '' 'Research to read: a.md' '' \
  'suites: a.test.sh, b.test.sh' '' '### T10: not the first' "T10's words." '## T2' > "$SP"
sect() { ( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/plan-read.sh" && plan_read_section "$SP" "$@" ); }
expect_eq "a section is the body under the heading whose first word is the id, to the next heading" \
  "Research to read: a.md||suites: a.test.sh, b.test.sh|" "$(sect T1 | tr '\n' '|')"
expect_eq "the first word is the whole id, its trailing colon dropped" "T10's words." "$(sect T10)"
expect_eq "a key line of the section answers its value" "a.test.sh, b.test.sh" "$(sect T1 suites)"
sect T2 >/dev/null; expect_status "a heading with no body is a section" 0 "$?"
sect T1 artifact >/dev/null; expect_status "a key the section lacks answers no" 1 "$?"
sect T3 >/dev/null; expect_status "a row with no heading of its own has no section" 1 "$?"

# A version-14 run is read through the translation, then the same run once it has a log: the old homes and the log.
section "PLACES"
P="$(mktemp -d)"
at() {  # <place> -> the rows landed over a version-14 run there, then over its log
  local d="$P/${1//\//-}" r; r="${1##*/}"; r="$d/record/${r%.plan.md}"
  mkdir -p "$d/${1%/*}" "$r"; printf '# r\n' > "$d/$1"; printf 'landed: row=T1 merge=c1 at=2026-11-01T00:00:01Z\n' > "$r/landing-proofs.log"
  bash "$READER" "$d/$1" landed | grep -o 'row=T[0-9]'
  printf 'run/v1|ev=published|row=T2|commit=c2|kind=queue|at=2026-11-01T00:00:02Z\n' > "$r/run.log"
  bash "$READER" "$d/$1" landed | grep -o 'row=T[0-9]'
}
for pl in plans/flat.plan.md plans/epic-y/nest.plan.md incidents/0001-x/plan.md; do expect_eq "$pl: the translation, then the translation and the log, read from its record" \
  "row=T1 row=T1 row=T2" "$(at $pl | tr '\n' ' ' | sed 's/ $//')"; done
for pl in notes/w.plan.md plans/a/b/w.plan.md; do
  mkdir -p "$P/out/${pl%/*}"; printf '# r\n' > "$P/out/$pl"; bash "$READER" "$P/out/$pl" step 2>/dev/null
  expect_status "$pl: no place the walk admits, refused" 2 "$?"
done


section "TABLE"
# Each plan's real Tasks row T1 is `real`; a decoy where the old walk would look is `decoy`.
TH='| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|'
TR='| T1 | 4 | build | real | — | 30 | R | a.sh | out/T1.md |'
tp() { printf '%s\n' "$2" > "$D/plans/epic-x/$1.plan.md"; }
tp tfence "## Goal
\`\`\`
## Tasks
$TH
| T1 | 4 | build | decoy | — | 30 | R | z.sh | out/T1.md |
\`\`\`
## Tasks
$TH
$TR"
tp tsuffix "## Tasks (amended)

$TH
$TR"
tp tlower "## tasks

$TH
$TR"
tp tnote "## Tasks

| note | here |
|---|---|
$TH
$TR"
printf '## Tasks\r\r%s\r%s\r' "$(printf '%s' "$TH" | tr '\n' '\r')" "$TR" > "$D/plans/epic-x/tcr.plan.md"
expect_eq "a fenced table is prose, the heading reads in either case and may go on, the header names id, a lone CR ends a line" \
  "tfence=real tsuffix=real tlower=real tnote=real tcr=real " \
  "$(for W in tfence tsuffix tlower tnote tcr; do printf '%s=%s ' $W "$(ask row T1 | sed -n 's/^task=//p')"; done)"

section "WAITS"
# The rows each read names carry the read: a row reading its own id waits on itself, and a row reading
# live:head writes the settled head for a row that reads it.
cat > "$D/plans/epic-x/wr.plan.md" <<'EOF2'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C1 | 4 | build | t | — | — | 30 | R | src/c.sh | — | — | pending | approval:plan, C1, head |
| C2 | 4 | build | t | — | — | 30 | R | src/d.sh | — | — | pending | live:head |
| C3 | 4 | build | t | — | — | 30 | R | record/C3.md | — | — | pending | approval:plan, src/c.sh, C1 |
EOF2
rw() { ( . "${READER%/reader.sh}/lib/reader.sh" && plan_read_waits "$D/plans/epic-x/wr.plan.md" ) | awk -F'\t' '$2 == "row" { printf "%s>%s<%s ", $1, $3, $4 }'; }
expect_eq "each row a read names, with the reads that name it" "C1>C1<C1 C1>C2<head C3>C1<src/c.sh,C1 " "$(rw)"
section "HALF"
# The half-moved run: T1's landing and two asks opened stand in the old homes, T2's landing (its ledger copy in the
# plan too), a reply to one ask, a run and its verdict in the log, appended later. fails-when: the reader reads the log
# alone (T1 gone, the open ask gone), counts T2 twice, or reads the old homes once the run is brought forward.
HD="$D/record/half"; mkdir -p "$HD"; HC="$(printf 'd%.0s' {1..40})"
printf '%s\n' '# half' '' '## SDLC State' '' '- T2: landed-by-hand: Ann 2026-11-03T00:00:05Z "the copy names no commit"' > "$D/plans/epic-x/half.plan.md"
printf 'line/v1|ev=published|row=T1|commit=c1|kind=queue|by=-|why=-|at=2026-11-01T00:00:01Z\n' > "$HD/landing-proofs.log"
printf 'owed/v1|key=%s|state=open|sent=-|at=2026-11-01T00:00:0%s|title=t|reply=r\n' decide:D1 2 approve:x 3 > "$HD/asks.state"
printf 'run/v1|ev=%s|at=2026-11-03T00:00:0%s\n' "published|row=T2|commit=$HC|kind=queue|by=-|why=-" 5 'ask|key=decide:D1|reply=yes' 6 \
  "run|log=record/half/r.log|head=$HC|dirty=0|rc=0|sha256=s" 7 "verdict|row=T2|commit=$HC|suite=a.test.sh|result=green|log=-" 8 > "$HD/run.log"
W=half
expect_eq "the landings read in order, the old home's first, and the one the plan's ledger copies once" "T1 T2 " "$(keys landed)"
expect_eq "the ask the log answers is closed, and the one the register alone holds stays open" "approve:x " "$(keys asks)"
expect_eq "the log's run and verdict read beside them" "1 1" "$(ask verdicts | grep -c '|row=T2|') $(ask landed T2 | grep -c .)"
mkdir -p "$HD/kept/record"; cp "$HD/run.log" "$HD/kept/record/run.log"
expect_eq "kept, the log still its kept copy (an act broken off): still read as one" "T1 T2 " "$(keys landed)"
printf 'run/v1|ev=step|n=4|at=2026-11-03T00:00:09Z\n' >> "$HD/run.log"
expect_eq "brought forward, the log changed after its kept copy: the log alone" "T2 " "$(keys landed)"

section "ASK-LOG"
# The asks library writes each act on an ask as an ask event in the run's log, at its own clock, and reads the register
# then the log as one list. fails-when: an act writes asks.state, an act leaves no event or one off the library's clock,
# a standing ask of the register reads otherwise than as before until the log answers it, or a round the log opens is
# numbered off the register's count.
AR="$(mktemp -d)"; AP="$AR/.bionic/docs/plans/epic-x/askl.plan.md"; AD="$AR/.bionic/docs/record/askl"; T0=1793577600
mkdir -p "${AP%/*}" "$AD"; printf '# askl\n' > "$AP"
printf '%s\n' 'owed/v1|key=waive:old|state=open|sent=-|at=2026-11-01T00:00:01Z|title=t|reply=r' \
  'owed/v1|key=approve:step2|state=closed|by=card|at=2026-11-01T00:00:03Z|opened=2026-11-01T00:00:02Z' > "$AD/asks.state"
cp "$AD/asks.state" "$AR/register.was"
ao() {  # <epoch> <owed.sh function> [args] -> its answer, the run askl bound, the clock fixed at <epoch>
  local e="$1"; shift
  OWED_ROOT="$AR" OWED_PLAN="$AP" OWED_SID=s1 BIONIC_NOW_EPOCH="$e" \
    bash -c '. "$1/roots.sh" && . "$1/owed.sh" && shift && "$@"' _ "${READER%/reader.sh}/lib" "$@" 2>/dev/null
}
ao $((T0 + 60)) owed_open waive:new "t new" "poker: r new"; ao $((T0 + 120)) owed_answer waive:new no
ao $((T0 + 180)) owed_mark_sent waive:new; ao $((T0 + 240)) owed_close waive:new waive
ao $((T0 + 300)) owed_answer waive:old carry; ao $((T0 + 360)) owed_open approve:step2 "t2" "poker: r2"
expect_eq "each act is an ask event in the run's log: open, answer, sent, close of the new; answer of the old; round 2" \
  "waive:new waive:new waive:new waive:new waive:old approve:step2" \
  "$(awk -F'|' '$2 == "ev=ask" { for (i = 3; i <= NF; i++) if ($i ~ /^key=/) printf "%s ", substr($i, 5) }' "$AD/run.log" 2>/dev/null | sed 's/ $//')"
expect_eq "…and the register is as it was, never written" "same" "$(cmp -s "$AD/asks.state" "$AR/register.was" && echo same)"
expect_eq "every round reads as one list, the register's first, on the library's clock, the log's round numbered 2" \
  "approve:step2 1 closed 2026-11-01T00:00:02Z 2026-11-01T00:00:03Z|approve:step2 2 open 2026-11-02T00:06:00Z -|waive:new 1 closed 2026-11-02T00:01:00Z 2026-11-02T00:04:00Z|waive:old 1 open 2026-11-01T00:00:01Z -" \
  "$(ao "$T0" owed_rounds 'approve:step2|waive:.*' | tr '\t' ' ' | LC_ALL=C sort | paste -sd'|' -)"
expect_eq "the open list: the register's standing ask, then the log's new round, each with its title and line" \
  "waive:old - t r|approve:step2 - t2 poker: r2" "$(ao "$T0" owed_list | tr '\t' ' ' | paste -sd'|' -)"
expect_eq "the answers read on either home: the closed new keeps its own, the standing old has the log's" \
  "no 2026-11-02T00:02:00Z|carry 2026-11-02T00:05:00Z" \
  "$(ao "$T0" owed_answer_of waive:new | cut -f1-2 | tr '\t' ' ')|$(ao "$T0" owed_answer_of waive:old | cut -f1-2 | tr '\t' ' ')"
ao $((T0 + 420)) owed_close waive:old waive
expect_eq "the register's standing ask closed through the log reads closed, and the reader agrees" "approve:step2|approve:step2 " \
  "$(ao "$T0" owed_list | cut -f1 | paste -sd' ' -)|$(W=askl; D="$AR/.bionic/docs"; keys asks)"

section "ASK-DOORS"
# The doors that close an ask which no verb's own suite pins: a passing reading proof-add registers closes its
# question's waiver, and the Stop over an approved plan closes the step asks the cards left open. fails-when: either
# leaves its ask open on the run's list, or the Stop closes the step asks of a plan not approved.
# FIXTURE FIDELITY: session-poker-3 §FACT's shape (s42_plan, s47_plan), a linked worktree with real commits, roster rows
# from the production writer; the Stop is the shipped hook.
. "$(dirname "$0")/lib/bound-marker.sh"; . "$(dirname "$0")/lib/roster-row.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"; S31_STOP_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"; . "$(dirname "$0")/session-poker.prelude.sh"
AL="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"; POKE_BOUND=180
al() { bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && shift && "$@"' _ "$AL" "$@" 2>/dev/null; }
reg() { al owed_list_plan "$2" "$1" | cut -f1 | LC_ALL=C sort | paste -sd' ' -; }   # <root> <plan> -> the open keys
RF="$(make_repo ask-doors)"; ( cd "$RF" && git commit -q --allow-empty -m init ); git -C "$RF" config user.name "Dana Fixture"
RF_B="$(git -C "$RF" rev-parse HEAD)"; PF="$(s42_plan "$RF" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${RF_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PF" > "$PF.tmp" && mv "$PF.tmp" "$PF"; s42_builds_landed "$PF"
( cd "$RF" && git add -f "$PF" && git commit -qm wb && git worktree add -q -b wave/01-fixture "$RF/.worktrees/01-fixture" "$RF_B" ) >/dev/null 2>&1
RF_DIR="$RF/.bionic/docs/record/wave-01-fixture"; mkdir -p "$RF_DIR"; new_roster "$RF"
printf '%s|questions=evidence\n' "$(roster_row_fixture session="$SID" name=w-aud agent_id=a-w-aud subagent_type=bionic:auditor \
  files=.bionic/docs/record/wave-01-fixture/ev-fail.md,.bionic/docs/record/wave-01-fixture/ev-pass.md)" >> "$(roster_of "$RF")"
rec() { printf '# reading\n\nreviewed: %s..%s\nquestion: evidence\nresult: %s\nscope: piece\n\nwhat the reader found\n' "${RF_B:0:10}" "$2" "$3" > "$RF_DIR/$1"; }
rec ev-fail.md "$(s57_commit "$RF/.worktrees/01-fixture" lib/a.sh C1)" fail
RF_SUM="$(cksum < "$PF")"
poke "$RF" proof-add review record/wave-01-fixture/ev-fail.md --question evidence --reader w-aud
expect_eq "a registered proof leaves the plan byte for byte as it was and adds one proof event to the run's log" "$RF_SUM|1" \
  "$(cksum < "$PF")|$(/usr/bin/grep -c '^run/v1|ev=proof|kind=review|head=[0-9a-f]*|evidence=record/wave-01-fixture/ev-fail.md|question=evidence|' "$RF_DIR/run.log")"
expect_eq "a failing reading registered (exit 0) opens its waiver on the run's list at once" "0|waive:evidence" "$RC|$(reg "$RF" "$PF")"
rec ev-pass.md "$(s57_commit "$RF/.worktrees/01-fixture" lib/a.sh C2)" pass
poke "$RF" proof-add review record/wave-01-fixture/ev-pass.md --question evidence --reader w-aud
expect_eq "a passing reading of the question registered (exit 0) closes it, the closer named" "0||yes" "$RC|$(reg "$RF" "$PF")|$(al owed_lines "$PF" "$RF" \
  | /usr/bin/grep -q '|key=waive:evidence|state=closed|by=passing reading|' && echo yes)"
printf '| AC | verdict | why |\n|---|---|---|\n| AC-1.1 | CONFIRMED | walked |\n\nverdict: CONFIRMED — one row\n' > "$RF_DIR/walk.md"
RF_SUM="$(cksum < "$PF")"; poke "$RF" proof-add walk record/wave-01-fixture/walk.md
expect_eq "a registered walk discharges the criterion it confirms by one proof naming it, the plan byte for byte as it was" \
  "0|$RF_SUM|1|state=discharged by=proof" "$RC|$(cksum < "$PF")|$(/usr/bin/grep -c '^run/v1|ev=proof|ac=AC-1\.1|evidence=record/wave-01-fixture/walk\.md|' \
  "$RF_DIR/run.log")|$(bash "$READER" "$PF" cell AC-1.1 | paste -sd' ' -)"
SW_KEYS="approve:step0 approve:step1 approve:step2 approve:step3"
for a in 0 1; do
  SR="$(make_repo "sweep$a")"; new_roster "$SR"
  SW="$(SP_APPROVED_LINE="$([ "$a" = 1 ] && echo 'approved-by: Dana Fixture 2026-10-21T12:00:00Z "approved"')" \
    s47_plan "$SR" 8 "| T1 | 4 | build | a work row | implementor | — | 10 | REQ-x | payload/a.sh | pending | |")"; bound_marker "$SR" "$SID" "$SW"
  for k in $SW_KEYS; do OWED_PLAN="$SW" OWED_ROOT="$SR" OWED_SID=sw-sid al owed_open "$k" "approval: $k" "Do you approve?"; done
  SB="$(reg "$SR" "$SW")"; s31_stop "$SR" "$(s31_transcript "$SR" "carry on")"
  SWEPT="${SWEPT:-}$a:$SB>$(reg "$SR" "$SW")>$(al owed_lines "$SW" "$SR" | /usr/bin/grep -c '|state=closed|by=plan approved-by|') "
done
expect_eq "the Stop over a plan with no approved-by: closes no step ask; over one carrying it, all four, the closer named" \
  "0:$SW_KEYS>$SW_KEYS>0 1:$SW_KEYS>>4 " "$SWEPT"

section "HANDS"
# Each act a person takes by hand is one hand event the hands question answers, saying what it was and why, written
# through the one writer, which refuses an act with no reason. fails-when: an amend, a hold, an extension, an adoption,
# a by-hand landing or a person's stop of a run leaves no event or one with no reason; the writer writes one with no
# reason; the tick's withdrawal of a request for the load is answered as an act by hand.
# FIXTURE FIDELITY: §ASK-DOORS' bound plan and roster rows; the verbs are the shipped ones, the run a stand-in shim.
HR="$(make_repo hands)"; HP="$(s34_plan "$HR" 4)"; new_roster "$HR"; HD="$HR/.bionic/docs/record/wave-01-fixture"
hw() {  # <what> -> `<what>:<why>` for each answer of the hands question that names it, `|` between
  bash "$READER" "$HP" hands | awk -F'|' -v w="$1" '{ a = ""; y = ""; for (i = 2; i <= NF; i++) { if ($i == "what=" w) a = w
    if (index($i, "why=") == 1) y = substr($i, 5) } if (a != "") printf "%s%s:%s", (n++ ? "|" : ""), a, y }'
}
lh() { bash -c '. "$1/line.sh" && shift && line_hand_event "$@"' _ "$AL" "$@"; }   # <plan> <what> <why> [key=value]
lh "$HP" probe 'a reason given' row=T1; LH_RC=$?
expect_eq "the writer appends one hand event with its what and its why (exit 0)" "0|probe:a reason given" "$LH_RC|$(hw probe)"
for y in '' '  ' '-'; do lh "$HP" probe "$y" 2>/dev/null; LH_NO="${LH_NO:-}$?"; done
expect_eq "…and refuses each act with no reason, exit 2, writing nothing (an empty, a blank, a dash)" "222|probe:a reason given" \
  "$LH_NO|$(hw probe)"
s30_row "$HR" deliverable="$HR/w1.md" "$(said "$HR" w1)"; echo done > "$HR/w1.md"
poke "$HR" amend w1 --files+ lib/z.sh --reason 'the brief missed lib/z.sh'; AM_RC="$RC"
poke "$HR" hold w1 'kept for a second pass'; HO_RC="$RC"
poke "$HR" extend w1 'more to read'
expect_eq "an amend, a hold and an extension each leave one hand event with the verb's reason (exits)" \
  "0 0 0|amend:the brief missed lib/z.sh|extend:more to read|hold:kept for a second pass" \
  "$AM_RC $HO_RC $RC|$(hw amend)|$(hw extend)|$(hw hold)"
HPRED="9f1e2d3c-4b5a-6978-8899-aabbccddeeff"; roster_header > "$(roster_of "$HR" "$HPRED")"
for n in a1 a2; do roster_row_fixture status=identified session="$HPRED" name="w-$n" agent_id="a$n" plan="$HP" >> "$(roster_of "$HR" "$HPRED")"; done
poke "$HR" adopt --why 'the session was cleared at 8:21'
expect_eq "an adoption leaves one hand event per row adopted, with its reason (exit 0 or 1, open rows found)" \
  "yes|adopt:the session was cleared at 8:21|adopt:the session was cleared at 8:21" "$( [ "$RC" -le 1 ] && echo yes)|$(hw adopt)"
mkdir -p "$TMPROOT/hshim"; printf '#!/bin/bash\nwhile :; do sleep 0.2; done\n' > "$TMPROOT/hshim/booked.sh"; HL="$HR/.bionic/tmp/runs/h.log"
mkdir -p "${HL%/*}"; : > "$HL"
perl -MPOSIX -e 'my $l = shift; exit 0 if fork; POSIX::setsid(); open(my $f, ">", "$l.pid"); print $f "$$\n"; close $f; exec @ARGV' \
  "$HL" bash "$TMPROOT/hshim/booked.sh" --run-log "$HL"
i=0; while [ ! -s "$HL.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
poke "$HR" stop-run "$HL"; SR0="$RC"
expect_true "a person's stop of a run with no reason is refused, the run still alive" kill -0 "$(cat "$HL.pid")"
poke "$HR" stop-run "$HL" --why 'hung on a closed pipe'
expect_eq "…and with one stops it and leaves one hand event naming it (exits)" "2 0|stop-run:hung on a closed pipe" "$SR0 $RC|$(hw stop-run)"
mkdir -p "$BIONIC_GATE_DIR/requests"
sg() {  # <id> <why> [--waiting] -> stop_run_gate as the verb and the tick call it, the session bound to the plan
  printf 'key=k%s\nkind=work\nwho=%s:w-q%s\nasked=1000\nholder=-\n' "$1" "$SID" "$1" > "$BIONIC_GATE_DIR/requests/$1"
  ( cd "$HR" && CLAUDE_CODE_SESSION_ID="$SID" SR_WHY="$2" SR_MACHINE="${SR_MACHINE:-}" P="$HP" bash -c 'H="$1"; shift; say() { :; }; die() { :; }
    resolve_run() { POKER_RUN_PLAN="$P"; POKER_RUN_OPEN=yes; }; for l in roots session gate slots run line; do . "$H/../payload/scripts/lib/$l.sh"; done
    . "$H/poker/roster.sh"; REPO_REAL="$PWD"; SR_REPORT_ONLY=no; stop_run_gate "$@"' _ "$BIONIC_HOOKS_DIR" "$1" ${3:+"$3"} ) >/dev/null 2>&1
}
sg 901 'a person stopped it'; SR_MACHINE=tick sg 902 'stood down for the load' --waiting
expect_eq "a request a person stops is a hand event; the tick's withdrawal for the load is none" \
  "stop-run:a person stopped it" "$(hw stop-run | tr '|' '\n' | /usr/bin/grep -v 'closed pipe')"
LR2="$TMPROOT/hland"; git init -q "$LR2" && git -C "$LR2" commit -q --allow-empty -m init && mkdir -p "$LR2/.bionic/tmp"
LB="$(git -C "$LR2" rev-parse HEAD)"; SPW="${BIONIC_SCRIPTS_DIR}/payload/scripts/spawn-worktree.sh"
( cd "$LR2" && bash "$SPW" create "$LB" wave/20-demo && bash "$SPW" create "$LB" wt/20-T1 ) >/dev/null 2>&1
LT="$(git -C "$LR2" worktree list --porcelain | sed -n 's/^worktree //p' | /usr/bin/grep '20-T1$')"
[ -n "$LT" ] && echo w > "$LT/t1.txt" && git -C "$LT" add t1.txt && git -C "$LT" commit -qm T1
LP="$LR2/.bionic/docs/plans/epic-x/wave-x.plan.md"; mkdir -p "${LP%/*}"
printf -- '---\nworking-branch: wave/20-demo\n---\n# plan\n\n## SDLC State\n\ncurrent: 4\n' > "$LP"
printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$LP" > "$LR2/.bionic/tmp/engaged-$SID.state"
( cd "$LR2" && CLAUDE_CODE_SESSION_ID="$SID" bash "$SPW" land "$LT" --by-hand --reason 'no Lands-on could be read' ) >/dev/null 2>&1; LH_RC=$?
expect_eq "a by-hand landing is one published landing of the hand kind with its reason, answered by hands (exit)" \
  "0|hand|no Lands-on could be read" "$LH_RC|$(bash "$READER" "$LP" hands | awk -F'|' '{ for (i = 2; i <= NF; i++) if ($i ~ /^(kind|why)=/) printf "|%s", substr($i, index($i, "=") + 1) }' | cut -c2-)"
section "HELD"
i=0; while IFS= read -r f; do i=$((i + 1)); printf '%b' "## SDLC State\n$f\n" > "$D/plans/epic-x/held$i.plan.md"; done <<'EOF'
current: 4\napproved-by: u 2026-01-01T00:00Z "ok"\n- Step 4: x
   current :  4\napproved-by: u 2026-01-01T00:00Z "ok"
current:4\napproved-by:u 2026-01-01T00:00Z "ok"
current: 4\ncurrent: notastep
current: 8b\n- Step 8: x
current: 9\n- Step 8: x\n- Step 9: drafted
current: 9\napproved-by: u 2026-01-01T00:00Z "ok"\nStep 9:\n  delivered: PR 1
current: 9\n- Step 8: x
current: 9\n- Step 9: report, delivered: 2026-01-01
- Step 3: x\n- Step 4: y
current: T3
current: 12
current: <N>
current: 4\n- approved-by: u 2026-01-01T00:00Z "ok"
current: 4\n  approved-by: u 2026-01-01T00:00Z "ok"
current: 4\napproved-by:
current: 4\napproved: step3 u 2026-01-01T00:00Z "ok"
current: 4\r\napproved-by: u 2026-01-01T00:00Z "ok"\r
current: 4\rapproved-by: u 2026-01-01T00:00Z "ok"\r
EOF
# each plan asked of the held place cold and of the whole fold: `<compared> <the plans that disagree>`
held() { TMPDIR="$(mktemp -d)" bash -c '. "$1/lib/proof.sh"; _proof_reader_load; n=0; bad=""; for p in "$2"/*.plan.md; do n=$((n + 1))
  w="$(reader_q_step "$p"; if reader_q_approved "$p" step3; then echo approved=1; else echo approved=0; fi)"; [ "$(proof_step_held "$p")" = "$w" ] || bad="$bad ${p##*/}"; done
  echo "$n$bad"' _ "${READER%/*}" "$D/plans/epic-x"; }
HELD="$(held)"
expect_eq "the held place answers as the whole fold on every form and every plan this suite built, nineteen forms among them" \
  "1|" "$([ "${HELD%% *}" -ge 19 ] && echo 1)|$(printf '%s' "${HELD#* }" | sed 's/^[0-9]*$//')"

finish
