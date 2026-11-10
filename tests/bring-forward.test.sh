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
|---|---|---|---|---|---|---|---|---|---|---|---|
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
proved: kind=regression head=$H at=2026-11-01T06:00:00Z evidence=record/wave-9-old/r2.log run=2026-11-01T05:59:00Z head=$H rc=0
proved: kind=regression head=$H at=2026-11-01T05:00:00Z evidence=record/wave-9-old/r1.log rc=1
moved: record/wave-9-old/critic.md#1 to=fixed row=T3 by=Ann Person at=2026-11-01T06:02:42Z
deferred: record/wave-9-old/critic.md#2 S3 on "a key one" stated="the cd || exit prefix"
waived: question=evidence head=$H by Ann Person 2026-11-01T15:53:03Z "all recommended"
order: given 2026-11-01T07:00:00Z "hold the line"
EOF
EV="$(translate "$P" events)"; GAPS="$(translate "$P" gaps)"
of() { printf '%s\n' "$EV" | grep "^run/v1|ev=$1|" | grep -F -- "$2"; }

section "GAPS"
expect_eq "every source gives lines: 26 events" 26 "$(printf '%s\n' "$EV" | grep -c '^run/v1|ev=')"
missing="$(printf '%s\n' "$EV" | awk -F'|' '{ for (i = 3; i <= NF; i++) { v = substr($i, index($i, "=") + 1)
  if (v ~ /^step[0-9]$/) v = "Step " substr(v, 5); if (v != "") print v } }' | while IFS= read -r v; do
  grep -qF -- "$v" "$P" || printf '%s\n' "$v"; done)"
expect_nonempty "the value scan reads values" "$(printf '%s\n' "$EV" | grep -F "commit=$C")"
expect_empty "every value in the translation is found in the plan" "$missing"
expect_contains "Step 4 is a step" "|n=4|at=" "$(of step 'n=4|')"
expect_regex "Step 4 has no instant, and none is made" '\|at=$' "$(of step 'n=4|')"
expect_contains "the gaps list names Step 4's instant" "gap/v1|ev=step|n=4|field=at|why=absent" "$GAPS"
expect_contains "a deferral is a finding" "severity=S3" "$(of finding 'critic.md#2')"
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
bad="$(printf '%s\n' "$EV" | while IFS= read -r l; do
  body="${l#run/v1|ev=}"; t="${body%%|*}"; body="${body#"$t"}"; body="${body%|at=*}"
  [ "${l%|at=*}" != "$l" ] || { printf 'no at: %s\n' "$l"; continue; }
  IFS='|' read -r -a fs <<< "${body#|}"
  RUN_LOG="$D/shape.log" log_append "$t" "${fs[@]}" || printf 'refused: %s\n' "$l"
done)"
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
expect_eq "a run with a log reads the log alone" "n=7 state=open" "$(ask step | tr '\n' ' ' | sed 's/ $//')"

finish
