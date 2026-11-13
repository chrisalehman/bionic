#!/bin/bash
# tests/bring-forward.test.sh — payload/scripts/lib/translate.sh, a version-14 plan's state read as events.
#
# A run with no record/<wave>/run.log keeps its state in the plan's text. `translate <plan> events` turns
# that text into `run/v1` lines in the order they happened; `translate <plan> gaps` names each fact the
# text does not hold. The reader takes the translation when the run has no log.
#
#   §GAPS    every value in the translation is found in the plan; a fact the plan lacks is on the gaps
#            list and absent from the line.
#   §SHAPE   every translated line is a type the appender takes, with fields it takes.
#   §READER  the reader answers a version-14 plan with no run.log through the translation, in time order.
#   §PLACE     an approval written by then instant is read; an untimed deferral stands at its review's proof.
#   §MATRIX    a discharged matrix row is a proof and a waived one a waiver, by ac= with what its cells hold,
#              and a waiver with the author, instant and words of its block's waiver: line.
#   §ONE-FACT  a criterion a state line and a matrix row both name is the state line's one fact.
#   §UNREAD    the header's abandoned: is an abandon; an inherited: line no ruled type carries is a gap.
#   §RENAME  each landing-record line of a ruled type is carried with its first field renamed and every
#            other field the same; the other kinds are a hand act, an admitted red, a void, or a gap; a
#            landed: header that copies a published line writes nothing.
#   §ASKS    the asks register is ask events: a closed round its opening and its reply, an open one open.
#   §ONE     a landing read from the plan and from the record is one fact, and so is a tree; a row the
#            plan holds as landed and the record lacks is still landed.
#   §DECISIONS  a design ledger's put and ruled headings are decision rounds; any other heading is a gap.
#   §DEBTS      a debt ledger's lines are debts, burned= its row when burned; a line of another form is a gap.
#   §ACT     payload/scripts/bring-forward.sh <plan>: the plan keeps no state, matrix or handoff section, its
#            rows the nine authored cells, and the reader's step, read from the log it wrote, is the old current:.
#   §TWICE   a second act changes no byte of the plan or the log.
#   §KEPT    the old plan and record are kept beside the new, byte for byte.
#   §HALF    a run whose log already holds some of its facts is brought forward: the act exits 0, the log it writes
#            holds the old homes' landings and the log's own in order, the log as it stood is kept, a second act
#            changes no byte.
#   §WAITS   a wait on a row is that row's id in deps; one the kind implies is dropped; any other is a gap.
#   §DROPPED a dropped row's cell is the run's drop: after the act the row stays, reads dropped, and waits on it are met.
#   §CRITERIA each criterion's block task is carried into the Eval design's Task column, so it is owed at the same step after the
#            act; a task with no Eval design row, or a token 15 cannot say (a 9 beside an id), is on the gaps list.
#   §CELLS   a row's suites and lands-on go to the task's own section, past a fenced # line in it, or to the gaps list when it has none.
#   §STEPS   a Step follows the Step above it and a proof or waiver the line above it in its block, whatever
#            their instants, so the step is the old current: and closure; a Step held (pending) is a gap.
#   §PARKED  a Step 9 line with no delivered: (a parked plan's note) is a gap, not a step; close-out's parked delivery is.
#   §NAME    a plan not named *.plan.md is refused before anything is written, in words naming it for its directory.
#
# FIXTURE FIDELITY. The plan is a real file in a scratch docs tree, in the shape version-14 plans hold.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
. "$LIB/translate.sh"; . "$LIB/log.sh"
D="$(mktemp -d)/docs"; H="$(printf 'a%.0s' {1..40})"; C="$(printf 'c%.0s' {1..40})"
P="$D/plans/epic-x/wave-9-old.plan.md"; mkdir -p "${P%/*}" "$D/record/wave-9-old"
cat > "$P" <<EOF
---
canonical_sdlc_version: 14
---
# wave-9-old

## Tasks
| id | step | kind | task | agent | deps | size | Files | worktree | base | status | suites |
| T1 | 4 | build | One. | w9-T1 | — | 30 | a.sh | .worktrees/9-T1 | 1111111aa | landed | a.test.sh |
| T2 | 4 | build | Two. | w9-T2 | — | 30 | b.sh | .worktrees/9-T2 | 1111111aa | landed | — |
| T3 | 5 | verify | Three. | — | — | 30 | — | — | — | pending | — |

## Handoff

handoff: .bionic/docs/record/handoffs/2026-11-01-wave-9-old.md written 2026-11-01 09:37 PST

## SDLC State

current: 5
approved-by: Ann Person 2026-11-01T02:25:48Z "Approved"
approved: release by Ann Person 2026-11-01T15:53:06Z head=$H "all recommended"
- Step 0: configured at 2026-11-01T01:10Z via Ann Person "approved, D1: 1" at the Step-0 card
- Step 1: requirements: r.md; approved at 2026-11-01T01:21Z by Ann Person "go" at the Step-1 card
- Step 2: spec: s.md; approved at 2026-11-01 by Ann Person "fine"
- Step 3: plan: p.md; approved at 2026-11-01T02:25:48Z "Approved" at the Step-3 card
- Step 4: rows dispatched from the working branch
  base-sha: 1111111aa
- Step 5: verify at $H
- session: s-one bound 2026-11-01T01:06:35Z by write
- T1: landed $C 2026-11-01T02:37:51Z — .worktrees/9-T1
- T2: landed-by-hand: orchestrator 2026-11-01T05:22:07Z "record-only row" judged-by=35d5 — .worktrees/9-T2
- T3: pending dispatch — added by task-add at 2026-11-01T05:22:50Z born: review S2 on of=record/wave-9-old/critic.md#1
proved: kind=regression head=$H at=2026-11-01T05:00:00Z evidence=record/wave-9-old/r1.log rc=1
proved: kind=regression head=$H at=2026-11-01T06:00:00Z evidence=record/wave-9-old/r2.log run=2026-11-01T05:59:00Z head=$H rc=0
moved: record/wave-9-old/critic.md#1 to=fixed row=T3 by=Ann Person at=2026-11-01T06:02:42Z
deferred: record/wave-9-old/critic.md#2 S3 on "a key one" stated="the cd || exit prefix"
deferred: record/wave-9-old/critic.md#3 S3 off "repeats all but at=" stated="kept whole"
waived: question=evidence head=$H by Ann Person 2026-11-01T15:53:03Z "all recommended"
order: given 2026-11-01T07:00:00Z "hold the line"
EOF
EV="$(translate "$P" events)"; GAPS="$(translate "$P" gaps)"
of() { printf '%s\n' "$EV" | grep "^run/v1|ev=$1|" | grep -F -- "$2"; }

section "GAPS"
expect_eq "every source gives lines: 27 events" 27 "$(printf '%s\n' "$EV" | grep -c '^run/v1|ev=')"
missing="$(printf '%s\n' "$EV" | awk -F'|' '{ for (i = 3; i <= NF; i++) { v = substr($i, index($i, "=") + 1)
  if (v ~ /^step[0-9]$/) v = "Step " substr(v, 5); if (v != "") print v } }' | while IFS= read -r v; do
  grep -qF -- "$v" "$P" || printf '%s\n' "$v"; done)"
expect_nonempty "the value scan reads values" "$(printf '%s\n' "$EV" | grep -F "commit=$C")"
expect_empty "every value in the translation is found in the plan" "$missing"
expect_contains "Step 4 is a step" "|n=4|at=" "$(of step 'n=4|')"
expect_regex "Step 4 has no instant, and none is made" '\|at=$' "$(of step 'n=4|')"
expect_contains "the gaps list names Step 4's instant" "gap/v1|ev=step|n=4|field=at|why=absent" "$GAPS"
expect_contains "a deferral is a finding" "severity=S3" "$(of finding 'critic.md#2')"
expect_contains "…carrying its reach, read before its title" "|reach=on|" "$(of finding 'critic.md#2')"
expect_contains "…and a title holding a word that ends in = is kept whole" "|title=repeats all but at=|" "$(of finding 'critic.md#3')"
expect_absent "a value holding a bar is not written" "stated=" "$(of finding 'critic.md#2')"
expect_contains "the gaps list names the unwritable value" "ref=record/wave-9-old/critic.md#2|field=stated|why=bar" "$GAPS"
expect_contains "a deferral's author is a gap" "ref=record/wave-9-old/critic.md#2|field=by|why=absent" "$GAPS"
expect_contains "the agent cell is a dispatch" "name=w9-T1" "$(of dispatch 'row=T1')"
expect_absent "a dispatch has no session" "session=" "$(of dispatch 'row=T1')"
expect_contains "the gaps list names the dispatch's session" "gap/v1|ev=dispatch|row=T1|field=session|why=absent" "$GAPS"
expect_contains "the worktree cell is a tree with its base" "path=.worktrees/9-T1|base=1111111aa|at=" "$(of tree 'row=T1')"
expect_contains "a tree's branch is a gap: the plan holds none" "gap/v1|ev=tree|row=T1|field=branch|why=absent" "$GAPS"
expect_contains "a hand landing has no commit, and the gaps list says so" "ev=published|row=T2|field=commit" "$GAPS"

section "SHAPE"
refused() {  # <events> <log> -> each line the appender refuses, or that has no closing at=
  printf '%s\n' "$1" | while IFS= read -r l; do
    body="${l#run/v1|ev=}"; t="${body%%|*}"; body="${body#"$t"}"; body="${body%|at=*}"
    [ "${l%|at=*}" != "$l" ] || { printf 'no at: %s\n' "$l"; continue; }
    IFS='|' read -r -a fs <<< "${body#|}"
    RUN_LOG="$2" log_append "$t" "${fs[@]}" || printf 'refused: %s\n' "$l"
  done
}
bad="$(refused "$EV" "$D/shape.log")"
expect_eq "the appender took every line" "$(printf '%s\n' "$EV" | wc -l)" "$(wc -l < "$D/shape.log")"
expect_empty "no translated line is refused by the appender" "$bad"

section "READER"
ask() { bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$P" "$@"; }
expect_eq "the step is the old current:" "n=5 state=open" "$(ask step | tr '\n' ' ' | sed 's/ $//')"
for k in step0 step1 step2 step3 release; do ask approved "$k"; expect_status "approved $k" 0 "$?"; done
ask approved merge-unproved; expect_status "an approval the plan lacks is a no" 1 "$?"
ask green "$H"; expect_status "the later proof answers: rc=0 at 06:00 after rc=1 at 05:00" 0 "$?"
expect_eq "two landings" "T1 T2 " "$(ask landed | grep -o 'row=T[0-9]*' | cut -c5- | tr '\n' ' ')"
printf 'run/v1|ev=step|n=7|at=2026-11-02T00:00:00Z\n' > "$D/record/wave-9-old/run.log"
expect_eq "a run with a log and nothing kept reads both: the log's later step, the plan's two landings" "n=7 state=open T1 T2 " \
  "$(ask step | tr '\n' ' ')$(ask landed | grep -o 'row=T[0-9]*' | cut -c5- | tr '\n' ' ')"
section "PLACE"
Q="$D/plans/epic-x/wave-7-by.plan.md"; printf '%s\n' '## SDLC State' '- Step 1: r.md; approved by Ann Person 2026-11-01T01:21Z "go" at the card' \
  "proved: kind=review head=$H at=2026-11-01T02:00:00Z evidence=c.md" 'moved: c.md#1 to=fixed at=2026-11-01T09:00:00Z' 'deferred: c.md#2 S3 on "t"' \
  "proved: kind=review head=$H at=2026-11-01T05:00:00Z evidence=o.md" > "$Q"; QEV="$(translate "$Q" events)"
expect_contains "an approval written by then instant is read" "|ev=approval|key=step1|by=Ann Person|said=go|at=2026-11-01T01:21Z" "$QEV"
expect_eq "an untimed deferral stands at its review's proof, not beside a later finding, and its instant is a gap" "c.md c.md#2~ o.md c.md#1 " \
  "$(printf '%s\n' "$QEV" | awk -F'|' '{ for (i = 2; i <= NF; i++) if ($i ~ /^(ref|evidence)=/) printf "%s%s ", substr($i, index($i, "=") + 1), ($NF == "at=" ? "~" : "") }')"
QF="$D/plans/epic-x/wave-7-fence.plan.md"; printf '%s\n' '## SDLC State' "proved: kind=review head=$H at=2026-11-01T02:00:00Z evidence=k.md" '```' \
  "proved: kind=review head=$H at=2026-11-01T03:00:00Z evidence=fenced.md" 'moved: fenced.md#1 to=fixed at=2026-11-01T04:00:00Z' '```' > "$QF"
QFE="$(translate "$QF" events)"
expect_contains "a proof outside a fence is read" "|ev=proof|kind=review|head=$H|evidence=k.md|" "$QFE"
expect_absent "a fenced proof and a fenced move are examples: no event" "fenced.md" "$QFE"
M="$D/plans/epic-x/wave-8-matrix.plan.md"
cat > "$M" <<EOF
---
abandoned: 2026-11-02 — folded into wave-9
---
## Eval design
$(printf '| Criterion |\n|---|\n'; printf '| AC-%s |\n' 1 2 3 4 5)
## Verification Matrix
stack-health: pending
| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T2 | discharged | record/wave-8-matrix/a.log | CONFIRMED |
| AC-2 | T0 | waived | record/wave-8-matrix/w.md | REFUTED |
| AC-3 | T2 | pending | — | — |
| AC-4 | T1 | discharged | — | — |
| AC-5 | T2 | discharged | record/wave-8-matrix/m.log | CONFIRMED |

AC-2: the waived one.
  waiver: Ann Person 2026-11-01T08:00:00Z "not run here" — the reason
AC-3: the pending one.
  waiver: Bo Person 2026-11-01 "later, by hand"
## SDLC State
proved: kind=unit head=$H ac=AC-5 at=2026-11-01T06:00:00Z evidence=record/wave-8-matrix/s.log rc=0
inherited: a.test.sh base=$C head=$H at=2026-11-01T07:00:00Z evidence=record/wave-8-matrix/i.log
EOF
MEV="$(translate "$M" events)"; MG="$(translate "$M" gaps)"
expect_eq "the translation reads every source whatever IFS its caller holds" "$MEV" "$(IFS=$'\t'; translate "$M" events)"
askm() { bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$M" "$@" | tr '\n' ' ' | sed 's/ $//'; }
acof() { printf '%s\n' "$MEV" | grep -F "|ac=$1|" | grep -v '^run/v1|ev=hand|'; }

section "MATRIX"
expect_eq "a discharged row is discharged by its proof" "state=discharged by=proof" "$(askm cell AC-1)"
expect_eq "a waived row is discharged by its waiver" "state=discharged by=waiver" "$(askm cell AC-2)"
expect_eq "a pending row is pending" "state=pending" "$(askm cell AC-3)"
expect_eq "a waived row takes its author, instant and words from its block's waiver: line" \
  "run/v1|ev=waiver|ac=AC-2|evidence=record/wave-8-matrix/w.md|auditor=REFUTED|by=Ann Person|said=not run here|at=2026-11-01T08:00:00Z" "$(acof AC-2)"
expect_eq "the proof carries its evidence and auditor cells and nothing else" "run/v1|ev=proof|ac=AC-1|evidence=record/wave-8-matrix/a.log|auditor=CONFIRMED|at=" "$(acof AC-1)"
expect_absent "a pending row writes no proof and no waiver" "ac=AC-3|" "$(acof AC-3)"
# a block waiver: line is a hand act whatever its row reads; only the status cell makes a waiver, so the pending row stays pending
expect_contains "a waiver line in a pending row's block is a hand act, its day as written" \
  "run/v1|ev=hand|ac=AC-3|what=waive-row|by=Bo Person|said=later, by hand|at=2026-11-01" "$MEV"
expect_contains "…and so is a waived row's own block line" "run/v1|ev=hand|ac=AC-2|what=waive-row|by=Ann Person|said=not run here|at=2026-11-01T08:00:00Z" "$MEV"
expect_eq "the reader's hand acts are the two block lines" "AC-2 AC-3" "$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$M" hands | sed -n 's/.*|ac=\(AC-[0-9]*\)|.*|what=waive-row|.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
for f in kind head at; do expect_contains "a row holds no $f: a gap" "gap/v1|ev=proof|ac=AC-1|field=$f|why=absent" "$MG"; done
expect_eq "an empty evidence cell is still discharged" "state=discharged by=proof" "$(askm cell AC-4)"
expect_eq "and its proof holds no field the row lacks" "run/v1|ev=proof|ac=AC-4|at=" "$(acof AC-4)"
expect_contains "the empty evidence cell is a gap" "gap/v1|ev=proof|ac=AC-4|field=evidence|why=absent" "$MG"
section "ONE-FACT"
expect_eq "a criterion a proved: line and a matrix row both name is one proof" 1 "$(acof AC-5 | grep -c .)"
expect_contains "the stated proof stands, with its head and instant" "head=$H|ac=AC-5|" "$(acof AC-5)"
section "UNREAD"
expect_eq "an abandoned: header is the abandon the step question reads" "state=abandoned" "$(askm step)"
expect_contains "the abandon keeps its words and its day as written" "run/v1|ev=abandon|why=folded into wave-9|at=2026-11-02" "$MEV"
expect_contains "who abandoned it is a gap" "gap/v1|ev=abandon|run=wave-8-matrix|field=by|why=absent" "$MG"
expect_contains "an inherited: line no ruled type carries is a gap" "gap/v1|ev=inherited|suite=a.test.sh|field=ev|why=unruled" "$MG"
expect_absent "and writes no line" "a.test.sh" "$MEV"
bad="$(printf '%s\n' "$MEV" | while IFS= read -r l; do [ "${l%|at=*}" != "$l" ] || printf 'no at: %s\n' "$l"; body="${l#run/v1|ev=}"; t="${body%%|*}"; body="${body#"$t"}"
  IFS='|' read -r -a fs <<< "${body%|at=*}"; RUN_LOG="$D/shape8.log" log_append "$t" "${fs[@]:1}" || printf '%s\n' "$l"; done)"
expect_eq "the appender took every matrix and header line" "$(printf '%s\n' "$MEV" | wc -l)" "$(wc -l < "$D/shape8.log")"
expect_empty "and refused none" "$bad"

# SYNTHESIZED: a run whose record holds one line of each kind; the bed's closed runs are read in place.
P8="$D/plans/epic-x/wave-8-rec.plan.md"; R8="$D/record/wave-8-rec"; mkdir -p "$R8"
cat > "$P8" <<EOF
## Tasks
| id | step | kind | task | agent | deps | size | Files | worktree | base | status | suites |
| T1 | 4 | build | One. | w8-T1 | — | 30 | a.sh | .worktrees/8-T1 | 1111111aa | landed | a.test.sh |
| T2 | 4 | build | Two. | — | — | 30 | — | — | — | landed | — |
| T3 | 4 | build | Three. | — | — | 30 | — | — | — | landed | — |
## SDLC State
- T1: landed $C 2026-11-01T02:37:51Z — .worktrees/8-T1
- T2: landed-by-hand: orchestrator 2026-11-01T05:22:07Z "record-only row" judged-by=35d5
EOF
cat > "$R8/landing-proofs.log" <<EOF
line/v1|ev=ready|row=T1|name=w8-T1|commit=$H|branch=wt/8-T1|tree=/p/.worktrees/8-T1|at=2026-11-01T02:37:05Z
line/v1|ev=published|row=T1|commit=$C|kind=queue|by=-|why=|at=2026-11-01T02:37:51Z
landed: row=T1 branch=wt/8-T1 head=$H merge=$C at=2026-11-01T02:37:51Z
line/v1|ev=settled|row=T1|commit=$C|findings=|cells=AC-1.1|at=2026-11-01T02:37:52Z
line/v1|ev=stop-run|run=w8-T1-a.test.sh|name=w8-T1-a.test.sh|by=s-one|why=-|at=2026-11-01T03:00:00Z
line/v1|ev=published|row=T2|commit=$H|kind=hand|by=orchestrator|why=record-only row|at=2026-11-01T05:22:07Z
debt: id=d1 row=T1 branch=wt/8-T1 head=$H suite=a.test.sh token=tk at=2026-11-01T02:30:00Z
void: id=d1 branch=wt/8-T1 at=2026-11-01T02:40:00Z why=merge-undone
stamp/v1|log=x.log|head=$H|rc=0|at=2026-11-01T02:31:00Z
line/v1|ev=close-out|part=reviews|commit=$C|branch=wave/8|at=2026-11-01T09:00:00Z
landed: row=T9 branch=wt/8-T9 head=$H merge=$H at=2026-11-01T05:30:00Z
line/v1|ev=matrix-set|ac=AC-1.1|cells=status,task|by=s-one|at=2026-11-01T03:10:00Z
line/v1|ev=refusal|needs=person|verb=x|at=2026-11-01T03:20:00Z
EOF
printf 'owed/v1|key=decide:D1|state=closed|by=ruled|at=2026-11-01T01:16:28Z|opened=2026-11-01T01:07:09Z\n%s\n' \
  'owed/v1|key=approve:step4|state=open|sent=2026-11-01T06:00:01Z|at=2026-11-01T06:00:00Z|title=Step 4 card|reply=approve' > "$R8/asks.state"
printf 'fill-ledger/v1|at=2026-11-01T04:00:00Z|session=s-one|turn=u1|state=ok|width=3|launched=T1|room=0\n' > "$R8/fill-ledger.log"
EV8="$(translate "$P8" events)"; GP8="$(translate "$P8" gaps)"; in8() { printf '%s\n' "$EV8" | grep -cxF -- "$1"; }
ask8() { bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$P8" "$@"; }
BED="$BIONIC_SCRIPTS_DIR/tests/fixtures/replay"; W9=wave-49-what-a-run-costs; W6=wave-46-asks-nothing
P9="$BED/$W9/plans/epic-23-bionic-tech-debt/$W9.plan.md"; R9="$BED/$W9/record/$W9"; EV9="$(translate "$P9" events)"

section "RENAME"
ruled="$(awk -F'|' -v t="$LOG_TYPES" '$1 == "line/v1" && index(t, " " substr($2, 4) " ") { print "run/v1" substr($0, 8) }' "$R9/landing-proofs.log")"
expect_nonempty "the closed run's record holds landing lines of ruled types" "$ruled"
expect_empty "each is carried with its first field renamed and every other field the same" "$(printf '%s\n' "$ruled" | grep -vxF -f <(printf '%s\n' "$EV9"))"
heads="$(grep '^landed: ' "$R9/landing-proofs.log" | sed 's/^landed: /run\/v1|ev=published|/; s/ merge=/ commit=/; s/ /|/g')"
expect_nonempty "the closed run's record holds landed: headers" "$heads"
expect_eq "a landed: header that copies a published line of its row and commit writes nothing" 0 "$(printf '%s\n' "$heads" | grep -cxF -f <(printf '%s\n' "$EV9"))"
expect_eq "…so the landing is the line's, and keeps its kind" "kind=queue" "$(ask8 landed T1 | grep -o 'kind=[^|]*')"
expect_eq "a landed: header no line copies is a landing, merge read as its commit, every other field the same" 1 \
  "$(in8 "run/v1|ev=published|row=T9|branch=wt/8-T9|head=$H|commit=$H|at=2026-11-01T05:30:00Z")"
expect_eq "a status written into the matrix is a hand act: what it was, and the fields it holds" 1 \
  "$(in8 "run/v1|ev=hand|what=matrix-set|ac=AC-1.1|cells=status,task|by=s-one|at=2026-11-01T03:10:00Z")"
expect_eq "a refusal is a hand act: what it was, and the fields it holds" 1 "$(in8 "run/v1|ev=hand|what=refusal|needs=person|verb=x|at=2026-11-01T03:20:00Z")"
expect_eq "a stop-run is a hand act: what it was, and the fields it holds" 1 "$(in8 "run/v1|ev=hand|what=stop-run|run=w8-T1-a.test.sh|name=w8-T1-a.test.sh|by=s-one|why=-|at=2026-11-01T03:00:00Z")"
expect_eq "a debt line is an admitted red, a void line a void" "1 1" "$(in8 "run/v1|ev=admitted|id=d1|row=T1|branch=wt/8-T1|head=$H|suite=a.test.sh|token=tk|at=2026-11-01T02:30:00Z") $(in8 "run/v1|ev=void|id=d1|branch=wt/8-T1|why=merge-undone|at=2026-11-01T02:40:00Z")"
expect_eq "a fill-ledger line is a stop" 1 "$(in8 "run/v1|ev=stop|session=s-one|turn=u1|state=ok|width=3|launched=T1|room=0|at=2026-11-01T04:00:00Z")"
expect_contains "a kind no ruled type carries is named whole on the gaps list" "gap/v1|ev=settled|row=T1|field=ev|why=unruled" "$GP8"
expect_absent "and is not written" "ev=settled" "$EV8"
expect_contains "close-out is the Step 9 line, so what that line lacks is named on the step" "gap/v1|ev=step|n=9|field=part|why=unruled" "$GP8"
expect_absent "and close-out is not written a second time" "close-out" "$EV8"
expect_absent "a stamp is a copy of a run: no line and no gap" "x.log" "$EV8$GP8"
vals="$(printf '%s\n' "$EV8" | awk -F'|' '{ for (i = 3; i <= NF; i++) { v = substr($i, index($i, "=") + 1); if (v != "") print v } }')"
expect_contains "the value scan reads the record's values" "merge-undone" "$vals"
expect_empty "every value written is found in the plan or the record" "$(printf '%s\n' "$vals" | while IFS= read -r v; do grep -qF -- "$v" "$P8" "$R8"/* || printf '%s\n' "$v"; done)"
bad="$(refused "$EV8" "$D/shape8.log"; refused "$EV9" "$D/shape9.log")"
expect_eq "the appender took every record line" "$(printf '%s\n' "$EV9" | wc -l)" "$(wc -l < "$D/shape9.log")"
expect_empty "no line read from a record is refused by the appender" "$bad"

section "ASKS"
expect_eq "a closed round is its opening, then its reply at its close" "1 1" "$(in8 "run/v1|ev=ask|key=decide:D1|at=2026-11-01T01:07:09Z") $(in8 "run/v1|ev=ask|key=decide:D1|reply=ruled|at=2026-11-01T01:16:28Z")"
expect_contains "a closed round's sent= is gone from the register, and named" "gap/v1|ev=ask|key=decide:D1|field=sent|why=absent" "$GP8"
expect_eq "an open round keeps sent and title" 1 "$(in8 "run/v1|ev=ask|key=approve:step4|sent=2026-11-01T06:00:01Z|title=Step 4 card|at=2026-11-01T06:00:00Z")"
expect_contains "the register's reply= is the words asked for, not a reply given: named, not written" "gap/v1|ev=ask|key=approve:step4|field=reply|why=unruled" "$GP8"
expect_eq "the reader's open asks are the register's open rounds" "approve:step4" "$(ask8 asks | grep -o 'key=[^|]*' | cut -c5-)"
expect_eq "a second round keeps its round" 1 "$(printf '%s\n' "$EV9" | grep -cxF 'run/v1|ev=ask|key=decide:D13|round=2|reply=ruled|at=2026-11-07T04:00:12Z')"
expect_eq "every closed register row of the closed run is an opening and a reply" "$(( $(grep -c 'state=closed' "$R9/asks.state") * 2 ))" "$(printf '%s\n' "$EV9" | grep -c '^run/v1|ev=ask|')"
expect_eq "the cut run's one open ask" "decide:D13" "$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$BED/wave-49-mid/plans/epic-23-bionic-tech-debt/$W9.plan.md" asks | grep -o 'key=[^|]*' | cut -c5-)"

section "ONE"
pairs() { awk -F'|' '{ r = c = ""; for (i = 2; i <= NF; i++) { if ($i ~ /^row=/) r = substr($i, 5); if ($i ~ /^commit=/) c = substr($i, 8) } printf "%s=%s ", r, c }'; }
expect_eq "one landing per row: the record's for a hand landing, the plan's for a row the record lacks" "T1=$C T2=$H T9=$H T3= " "$(ask8 landed | pairs)"
expect_eq "one tree per row: the plan's cell, none made from the ready line" ".worktrees/8-T1" "$(printf '%s\n' "$EV8" | grep '^run/v1|ev=tree|' | grep -o 'path=[^|]*' | cut -c6-)"
for w in $W9 $W6; do
  rows="$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$BED/$w/plans/epic-23-bionic-tech-debt/$w.plan.md" landed | grep -o '|row=[^|]*')"
  led="$(grep -cE '^- T[0-9]+: landed' "$BED/$w/plans/epic-23-bionic-tech-debt/$w.plan.md")"
  expect_eq "$w: every row the plan or the record holds as landed is one landing" "$led $led" "$(printf '%s\n' "$rows" | grep -c .) $(printf '%s\n' "$rows" | sort -u | grep -c .)"
done
expect_contains "a row the plan holds as landed and the log lacks is still landed" "commit=837ddc39161b522a7071b996cf9d0d9121f1c61b" "$(bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$BED/$W6/plans/epic-23-bionic-tech-debt/$W6.plan.md" landed T17)"

# SYNTHESIZED: a run whose record holds a design ledger and a debt ledger, each form the closed runs' files hold.
P7="$D/plans/epic-x/wave-7-led.plan.md"; R7="$D/record/wave-7-led"; mkdir -p "$R7"; printf '# wave-7-led\n' > "$P7"
cat > "$R7/design-ledger.md" <<'EOF'
## Δ0 — D1 put (orchestrator 2026-11-01 5:47 PM PST): How the log fills (first)
Body prose is no heading.
## Δ1 — D1 ruled "2 <- and 'why' (a note)" (Ann Person 2026-11-01 5:49 PM PST): How the log fills (first)
## Δ2 — D2 put (Ann Person 2026-10-03): A day only
## Δ3 — D2 amended "x" (Ann Person 2026-10-04): Another verb
## Δ4 — D3 put (orchestrator 2026-11-01 6:00 PM | PST): A bar in the instant
## Deltas
## Δ5 — D2 re-ruled "y" (Ann Person 2026-10-05): Re-ruled
## Δ6 — D2 amended again "z" (Ann Person 2026-10-06), its words after
## Δ7 — D4 ratified "Yes" (Ann Person 2026-10-07): Ratified
## Δ8 — D4 settled by the go on Δ7 (Ann Person 2026-10-08 8:12 PM): "go"
## Δ9 — D5 glyphs final "w" (Ann Person 2026-10-09): A qualified word
## Δ10 — D5 withdrawn (Ann Person 2026-10-10): Withdrawn
## Δ11 — D6 ruled: No reply (Ann Person 2026-10-11)
## Δ12 — D6 ruled "4", provisionally (Ann Person 2026-10-12): undelimited
- D7 ruled "1" (Ann Person 2026-10-13): A Step-1 bullet
```
## Δ13 — D8 ruled "f" (Ann Person 2026-10-14): fenced
```
EOF
cat > "$R7/debt.md" <<'EOF'
# debt ledger: concept | kind | sites | raised-by <record> | touches N | burned <row> | —
c-open | duplicate | a.sh:1, b.sh:2 | raised-by record/w/critic.md | touches 3 | —
c-burned | unpinned-pair | a.sh:4 | raised-by record/w/critic-2.md | touches 1 | burned T5
c-note | duplicate | a.sh:9 | raised-by record/w/critic.md | touches 2 | next wave: a note
- A-orch-1 (2026-10-17 4:22 PM): prose about a debt.
EOF
EV7="$(translate "$P7" events)"; GP7="$(translate "$P7" gaps)"; in7() { printf '%s\n' "$EV7" | grep -cxF -- "$1"; }; ask7() { bash "${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh" "$P7" "$@"; }

section "DECISIONS"
expect_eq "the ledger lists D1 put, its wait the line under it and each its Δ, then ruled with its reply and who ruled, each instant as the heading writes it" \
  "run/v1|ev=decision|by=orchestrator|d=D1|entry=Δ0|title=How the log fills (first)|verb=put|wait=Body prose is no heading.|at=2026-11-01 5:47 PM PST run/v1|ev=decision|by=Ann Person|d=D1|entry=Δ1|said=2 <- and 'why' (a note)|title=How the log fills (first)|verb=ruled|at=2026-11-01 5:49 PM PST" "$(ask7 ledger D1 | paste -sd' ' -)"
expect_eq "a day-only instant is kept as written; one the appender refuses is not written" "1 1" "$(in7 'run/v1|ev=decision|d=D2|entry=Δ2|verb=put|by=Ann Person|title=A day only|at=2026-10-03') $(in7 'run/v1|ev=decision|d=D3|entry=Δ4|verb=put|by=orchestrator|title=A bar in the instant|at=')"
expect_contains "and is named" "gap/v1|ev=decision|d=D3|field=at|why=bar" "$GP7"
# Every word a ruling is written with is its round's verb, a qualifier before it kept with it; the reply is said=,
# a settled-by heading's reply the quote after it and its title what settled it; a bullet under a Δ is a round too.
lf() { ask7 ledger "$1" | awk -F'|' '{ v = s = t = a = ""; for (i = 2; i <= NF; i++) { k = substr($i, 1, index($i, "=") - 1); x = substr($i, length(k) + 2)
  if (k == "verb") v = x; else if (k == "said") s = x; else if (k == "title") t = x; else if (k == "at") a = x }; printf "%s/%s/%s/%s;", v, s, t, a }'; }
expect_eq "each ruling word is a decision round with that word its verb" \
  "put//A day only/2026-10-03;amended/x/Another verb/2026-10-04;re-ruled/y/Re-ruled/2026-10-05;amended again/z/its words after/2026-10-06;|ratified/Yes/Ratified/2026-10-07;settled/go/the go on Δ7/2026-10-08 8:12 PM;|glyphs final/w/A qualified word/2026-10-09;withdrawn//Withdrawn/2026-10-10;|ruled//No reply/2026-10-11;|ruled/1/A Step-1 bullet/2026-10-13;" \
  "$(lf D2)|$(lf D4)|$(lf D5)|$(lf D6)|$(lf D7)"
expect_eq "rounds from every heading and bullet the ledger rules or puts in, none fenced" 13 "$(printf '%s\n' "$EV7" | grep -c '^run/v1|ev=decision|')"
expect_no_regex "body prose is no line and no gap, a reply not delimited is no round, a fenced one is none" "Body prose|undelimited|fenced" "$(printf '%s\n' "$EV7" | grep -v '|wait=Body prose')$GP7"
expect_contains "a ruling whose reply is not delimited is named whole" "gap/v1|ev=decision|heading=Δ12|field=ev|why=shape" "$GP7"

section "DEBTS"
expect_eq "the debts question lists the open debt and not the burned one" "run/v1|ev=debt|concept=c-open|kind=duplicate|raised-by=record/w/critic.md|sites=a.sh:1, b.sh:2|touches=3|at=" "$(ask7 debts)"
expect_eq "a burned line is a debt with burned= its row" 1 "$(in7 'run/v1|ev=debt|concept=c-burned|kind=unpinned-pair|sites=a.sh:4|raised-by=record/w/critic-2.md|touches=1|burned=T5|at=')"
expect_contains "the ledger holds no instant: a gap" "gap/v1|ev=debt|concept=c-open|field=at|why=absent" "$GP7"
for g in decision\|heading=Deltas debt\|concept=c-note debt\|line=5; do expect_contains "another form is named whole: $g" "gap/v1|ev=$g|field=ev|why=shape" "$GP7"; done
expect_no_regex "and writes nothing" "undelimited|c-note|A-orch" "$EV7"
vals="$(printf '%s\n' "$EV7" | awk -F'|' '{ for (i = 3; i <= NF; i++) { v = substr($i, index($i, "=") + 1); if (v != "") print v } }')"; bad="$(refused "$EV7" "$D/shape7.log")"
expect_contains "the value scan reads the ledgers' values" "2026-11-01 5:49 PM PST" "$vals"
expect_empty "every value written is found in a ledger" "$(printf '%s\n' "$vals" | while IFS= read -r v; do grep -qF -- "$v" "$R7"/* || printf '%s\n' "$v"; done)"
expect_eq "the appender took every ledger line" "$(printf '%s\n' "$EV7" | wc -l)" "$(wc -l < "$D/shape7.log")"
expect_empty "no line read from a ledger is refused by the appender" "$bad"

# THE ACT runs on sandbox copies of the three bed runs and on a SYNTHESIZED run holding the waits, a dropped
# row and a task's own section; never on a tracked file.
SB="$(mktemp -d)"; BF="${BIONIC_SCRIPTS_DIR}/payload/scripts/bring-forward.sh"; RS="${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh"
for r in $W6 $W9 wave-49-mid; do cp -R "$BED/$r" "$SB/$r"; done
RUNS="$W6:$W6 $W9:$W9 wave-49-mid:$W9"; at() { printf '%s/%s/plans/epic-23-bionic-tech-debt/%s.plan.md' "$1" "${2%%:*}" "${2#*:}"; }
machine() { grep -cE '^## (SDLC State|Verification Matrix|Handoff) *$' "$1"; }

section "ACT"
for r in $RUNS; do p="$(at "$SB" "$r")"; cur="$(sed -n 's/^current: *//p' "$p")"; pre="$(machine "$p")"
  bash "$BF" "$p" > "$SB/${r%%:*}.out"; expect_status "${r%%:*}: the act exits 0" 0 "$?"
  expect_eq "${r%%:*}: the reader's step is the old current: ($cur)" "n=$cur" "$(bash "$RS" "$p" step | grep '^n=')"
  expect_eq "${r%%:*}: the state, matrix and handoff sections the plan held are gone" "held 0" "$([ "$pre" -ge 3 ] && echo held) $(machine "$p")"
  expect_eq "${r%%:*}: each Tasks row holds the nine authored cells" "id step kind task deps size serves files artifact" "$(plan_read_rows "$p" Tasks | awk -F'\t' '{ for (i = 1; i <= NF; i++) printf "%s%s", (i > 1 ? " " : ""), substr($i, 1, index($i, "=") - 1); print "" }' | sort -u)"
done

section "TWICE"
for r in $RUNS; do p="$(at "$SB" "$r")"; l="$SB/${r%%:*}/record/${r#*:}/run.log"; sum="$(cksum < "$p") $(cksum < "$l")"
  expect_nonempty "${r%%:*}: the act wrote the run's log" "$(grep '^run/v1|ev=step|' "$l")"
  expect_eq "${r%%:*}: a second act changes no byte of the plan or the log, and prints the same" "$sum $(cat "$SB/${r%%:*}.out")" "$(bash "$BF" "$p" | { o="$(cat)"; printf '%s %s %s' "$(cksum < "$p")" "$(cksum < "$l")" "$o"; })"
done

section "KEPT"
for r in $RUNS; do k="$(sed -n 's/^kept=//p' "$SB/${r%%:*}.out")"; o="$(at "$BED" "$r")"
  expect_nonempty "${r%%:*}: the act prints where it kept the old plan and record" "$k"
  expect_eq "${r%%:*}: the kept plan is the old one byte for byte, the new one is not" "differ" "$(cmp -s "$k/${r#*:}.plan.md" "$o" && ! cmp -s "$(at "$SB" "$r")" "$o" && echo differ)"
  expect_empty "${r%%:*}: the kept record is the old one byte for byte" "$(diff -r "$k/record" "$BED/${r%%:*}/record/${r#*:}" 2>&1)"
done
section "HALF"
HP="$SB/half/plans/epic-x/wave-8-half.plan.md"; HR="$SB/half/record/wave-8-half"; mkdir -p "${HP%/*}" "$HR"
printf '%s\n' '---' 'canonical_sdlc_version: 14' '---' '## Tasks' '| id | step | kind | task | deps | size | status |' '|---|---|---|---|---|---|---|' \
  '| T1 | 4 | build | One. | — | 30 | landed |' '| T2 | 4 | build | Two. | — | 30 | landed |' '| T3 | 4 | build | Three. | — | 30 | landed |' \
  '' '## SDLC State' 'current: 4' '- T1: landed 1111111111111111111111111111111111111111 2026-11-01T00:00:01Z' > "$HP"
printf 'line/v1|ev=published|row=T2|commit=c2|kind=queue|by=-|why=-|at=2026-11-02T00:00:01Z\n' > "$HR/landing-proofs.log"
printf 'run/v1|ev=published|row=T3|commit=c3|kind=queue|by=-|why=-|at=2026-11-03T00:00:01Z\n' > "$HR/run.log"; cp "$HR/run.log" "$SB/half.log"
HO="$(bash "$BF" "$HP" 2>&1)"; expect_eq "the act takes a run whose log stands with nothing kept (exit 0)" "0" "$?"
expect_eq "…its log holds the plan's landing, the landing record's and the log's own, in that order" "T1 T2 T3 " \
  "$(grep '^run/v1|ev=published|' "$HR/run.log" | grep -o 'row=T[0-9]*' | cut -c5- | tr '\n' ' ')"
expect_eq "…the log as it stood is kept byte for byte" "kept" "$(cmp -s "$HR/kept/record/run.log" "$SB/half.log" && echo kept)"
HS="$(cksum < "$HR/run.log") $(cksum < "$HP")"
bash "$BF" "$HP" >/dev/null 2>&1
expect_eq "…and a second act changes no byte of the log or the plan" "$HS" "$(cksum < "$HR/run.log") $(cksum < "$HP")"
W="$SB/docs/plans/epic-x/wave-7-act.plan.md"; mkdir -p "${W%/*}"; c="| — | — |"
cat > "$W" <<EOF
---
canonical_sdlc_version: 14
---
## Tasks
| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads | suites | lands-on | artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | One. | — | — | 30 | REQ-1 | a.sh, record/wave-7-act/T1.md $c landed | approval:plan | a.test.sh | a.test.sh | record/wave-7-act/T1.md |
| T2 | 4 | build | Two. | — | — | 30 | REQ-1 | b.sh $c pending | approval:plan, record/wave-7-act/T1.md, approval:D3 | b.test.sh | b.test.sh | — |
| T3 | 4 | build | Three. | — | — | 30 | REQ-1 | c.sh $c dropped | — | — | — | — |
| T4 | 4 | build | Four. | — | T3 | 30 | REQ-1 | d.sh $c pending | — | — | — | — |

### T1
One's own words.
$(printf '%s\n' '```bash' '# T2 waits on this' '```')

## Eval design
| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
$(for a in 1.1 1.2 1.3 1.4 1.6; do printf '| REQ-1 | a suite | AC-%s | hermetic | `a.test.sh` | a is red |\n' "$a"; done)

## Verification Matrix
| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
$(for a in 1.1 1.2 1.3 1.4 1.6; do printf '| AC-%s | T1 | pending | — | |\n' "$a"; done)

AC-1.1:
  task: T1
AC-1.2:
  task: 9
AC-1.3:
  fails-when: a is red
AC-1.4:
  task: T1, T4
AC-1.5:
  task: T2
AC-1.6:
  task: T2, 9

## SDLC State
current: 4
approved-by: Ann Person 2026-11-01T02:25:48Z "go"
EOF
askw() { bash "$RS" "$W" "$@"; }; say_rows() { for r in T1 T2 T3 T4; do askw status "$r" | head -1; done; askw landed | grep -c .; askw stop | grep '^ready='
  ( . "${RS%/*}/lib/units.sh"; units_rows "$W" | cut -f1,3,10; plan_read_waits "$W" | grep '	wait	approval:'
  . "${RS%/*}/lib/root.sh"; . "${RS%/*}/lib/run.sh"; . "${RS%/*}/lib/walls.sh" >/dev/null 2>&1
  for a in AC-1.1 AC-1.2 AC-1.3 AC-1.4 AC-1.6; do printf 'owed %s %s %s\n' "$a" "$(matrix_owing_step "$W" "$a")" "$(matrix_owing_open "$W" "$a")"; done ); }
PRE="$(say_rows)"; OUT="$(bash "$BF" "$W")"; KW="$(printf '%s\n' "$OUT" | sed -n 's/^kept=//p')/wave-7-act.plan.md"

section "WAITS"
expect_eq "a row that read another row's record has that row's id in deps, and the approval it named after it" "deps=T1, approval:D3" "$(askw row T2 | grep '^deps=')"
expect_eq "a wait the kind implies is in no cell: the old plan held it, the new holds none" "2 0" "$(grep -c 'approval:plan' "$KW") $(grep -c 'approval:plan' "$W")"
expect_eq "neither the named approval nor one the kind implies is on the gaps list" "0" "$(printf '%s\n' "$OUT" | grep -c 'field=approval:')"
expect_eq "the header names version 15" "canonical_sdlc_version=15" "$(askw header canonical_sdlc_version)"

section "DROPPED"
expect_contains "a dropped cell is carried into the run's log as its drop, its words saying so, no instant made" "run/v1|ev=drop|row=T3|why=carried from the status cell of a version-14 Tasks table|at=" "$(cat "${KW%/kept/*}/run.log")"
expect_eq "the dropped row is read dropped after the act, never absent" "state=dropped" "$(askw status T3 | grep '^state=')"
expect_eq "every row's state, the landings, the ready rows, the fill's rows and each approval a row waits on read after the act as at 14" "$PRE" "$(say_rows)"
askw ready T3; expect_status "a dropped row is not ready" 1 "$?"
printf 'run/v1|ev=approval|key=D3|by=Ann Person|at=2026-11-02T00:00:00Z\n' >> "${KW%/kept/*}/run.log"
expect_eq "the dropped row stays in the table, a wait on it stays a wait, met; T2 is ready once D3 stands" "| T3 |deps=T3 ready=T4 ready=T2 T4" "$(grep -o '^| T3 |' "$W")$(askw row T4 | grep '^deps=') $(grep '^ready=' <<< "$PRE") $(askw stop | grep '^ready=')"

section "CRITERIA"
expect_eq "at 14 each criterion is owed at its block's task's step, open while that task is: an id, the close, none, a list, and a mix of an id and 9 read as the id" \
  "owed AC-1.1 4 |owed AC-1.2 9 |owed AC-1.3  |owed AC-1.4 4 yes|owed AC-1.6 4 yes" "$(grep '^owed ' <<< "$PRE" | paste -sd'|' -)"
expect_eq "after the act each is owed at the same step, open alike: the Task column carries what each block said" "$(grep '^owed ' <<< "$PRE")" "$(say_rows | grep '^owed ')"
for x in "AC-1.1|T1" "AC-1.2|9" "AC-1.3|—" "AC-1.4|T1, T4" "AC-1.6|T2"; do
  expect_eq "${x%%|*}'s Eval design row holds its task in the Task column" "task=${x#*|}" "$(askw criterion "${x%%|*}" | grep '^task=')"; done
expect_contains "a block's task with no Eval design row to carry it is on the gaps list" "gap/v1|ev=criterion|criterion=AC-1.5|field=task|why=absent" "$OUT"
expect_contains "a token 15 cannot say, the 9 beside an id, is on the gaps list" "gap/v1|ev=criterion|criterion=AC-1.6|field=task:9|why=unruled" "$OUT"
WS="$(cksum < "$W")"; bash "$BF" "$W" >/dev/null 2>&1
expect_eq "a second act adds no second Task column: the plan is unchanged" "$WS" "$(cksum < "$W")"

section "CELLS"
expect_eq "a row's suites and lands-on go to the task's own section, after its fence" "One's own words. "'```bash ```'" suites: a.test.sh lands-on: a.test.sh" "$(sed -n '/^### T1$/,/^## /p' "$W" | grep -v '^#' | grep . | paste -sd' ' -)"
for f in suites lands-on; do expect_contains "a row with no section of its own has its $f on the gaps list" "gap/v1|ev=row|row=T2|field=$f|why=unruled" "$OUT"; done

section "STEPS"
U="$D/plans/epic-x/wave-6-untimed.plan.md"; B="$D/plans/epic-x/wave-5-back.plan.md"; s9='- Step 9: delivered: 2026-11-01T13:34Z'
printf '%s\n' '## SDLC State' 'current: 9' '- Step 0: configured at 2026-11-01T00:2xZ via Ann "go"' '- Step 1: r.md; approved by Ann 2026-11-01 "go"' \
  '- Step 2: s.md' '- Step 3: p.md; approved at 2026-11-01T02:25Z by Ann "go"' '- Step 8: CLOSED 2026-11-01T13:34Z' "$s9" > "$U"
printf '%s\n' '## SDLC State' 'current: 9' '- Step 7: documented at 2026-11-01T13:40Z' '- Step 8: CLOSED 2026-11-01T13:34Z' "$s9" > "$B"
A="$D/plans/epic-x/wave-4-held.plan.md"; printf '%s\n' '---' 'abandoned: 2026-11-02 held' '---' '## SDLC State' 'current: 3' '- Step 3: p.md' '- Step 4: (pending)' '- Step 9: (pending)' > "$A"
for x in "$U:n=9 state=delivered" "$B:n=9 state=delivered" "$A:n=3 state=abandoned"; do p="${x%%:*}"
  expect_eq "${p##*/}: the step is the plan's current: and its closure" "${x#*:}" "$(bash "$RS" "$p" step | /usr/bin/grep -E '^(n|state)=' | paste -sd' ' -)"; done
printf '%s\n' '## SDLC State' "waived: question=evidence head=$H by Ann 2026-11-01T15:53:03Z \"go\"" "proved: kind=review head=$H at=2026-10-04T00:00:00Z evidence=r.md question=evidence" > "$B.late"
expect_eq "a proof registered after a waiver stands after it, though its instant is earlier" "waiver proof " "$(translate "$B.late" events | sed -nE 's/^run\/v1\|ev=(waiver|proof)\|.*/\1/p' | tr '\n' ' ')"
expect_contains "a Step line held (pending) is no step reached: named, not written" "gap/v1|ev=step|n=9|field=ev|why=pending" "$(translate "$A" gaps)"
expect_eq "Steps stand in their numbers' order, wherever an instant sorts" "0 1 2 3 8 9 " "$(translate "$U" events | sed -n 's/^run\/v1|ev=step|n=\([0-9]*\)|.*/\1/p' | tr '\n' ' ')"
expect_contains "a Step with no instant keeps none, and its place makes none" "run/v1|ev=step|n=2|at=" "$(translate "$U" events | grep -x 'run/v1|ev=step|n=2|at=')"
expect_contains "and its instant is still a gap" "gap/v1|ev=step|n=2|field=at|why=absent" "$(translate "$U" gaps)"
section "PARKED"
# A person's note on a parked plan's Step 9 line, read as a step, would close the run before close-out does.
K="$D/plans/epic-x/wave-7-parked.plan.md"; k8='- Step 8: integrate: opened 2026-11-01T11:00Z'
printf '%s\n' '## SDLC State' 'current: 8' '- Step 7: documented at 2026-11-01T10:00Z' "$k8" '- Step 9: parked on wave/7-parked — waits on a hand test' > "$K"
expect_eq "a parked plan's Step 9 note is no delivery: the step is its current:" "n=8 state=open" "$(bash "$RS" "$K" step | paste -sd' ' -)"
expect_contains "the note is named on the gaps list, not written" "gap/v1|ev=step|n=9|field=ev|why=undelivered" "$(translate "$K" gaps)"
printf '%s\n' '## SDLC State' 'current: 9' '- Step 7: documented at 2026-11-01T10:00Z' "$k8" \
  '- Step 9: delivered: parked on wave/7-parked @ abc1234 — waits on a hand test (2026-11-01T12:00Z wave-7-parked)' > "$K"
expect_eq "close-out's own parked line is the delivery, its words the step's own field" "n=9|parked on wave/7-parked|state=delivered" "$(bash "$RS" "$K" step | sed 's/^delivered=\(parked on [^ ]*\).*/\1/' | paste -sd'|' -)"

section "NAME"
# An incident's plan named plain is a run at 14; at 15 a run is found and joined to its record by a name ending
# .plan.md, so the act on the plain name would leave a run no gate sees.
NI="$SB/name/incidents/0001-db-outage"; NP="$NI/plan.md"; mkdir -p "$NI"
printf '%s\n' '---' 'canonical_sdlc_version: 14' 'intent: incident-response' '---' '## Tasks' '| id | step | kind | task | deps | size | status |' \
  '|---|---|---|---|---|---|---|' '| T1 | 4 | build | Fix. | — | 30 | pending |' '' '## SDLC State' 'current: 4' > "$NP"; NS="$(cksum < "$NP")"
NO="$(bash "$BF" "$NP" 2>&1)"; expect_status "an incident's plan named plain is refused (exit 2)" 2 "$?"
expect_contains "…in words that name the plan for its directory and say to run the act again" "name it $NI/0001-db-outage.plan.md and run the act again" "$NO"
expect_eq "…before anything is written: the plan is unchanged and no record stands" "$NS|" "$(cksum < "$NP")|$(find "$SB/name" -path '*/record/*' -type f | sed 's#.*/name/##' | paste -sd' ' -)"
mv "$NP" "$NI/0001-db-outage.plan.md"; bash "$BF" "$NI/0001-db-outage.plan.md" >/dev/null 2>&1; expect_status "renamed as the words say, the act takes it (exit 0)" 0 "$?"
expect_contains "…and the record it writes is the incident's own" "record/0001-db-outage/run.log" "$(find "$SB/name" -path '*/record/*' -type f | sed 's#.*/name/##' | paste -sd' ' -)"
finish
