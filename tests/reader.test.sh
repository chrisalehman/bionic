#!/bin/bash
# tests/reader.test.sh — payload/scripts/reader.sh, the one program that reads a run's log and answers.
#
# `reader <plan> <question> [args]` reads record/<wave>/run.log, found from the plan by name, folds it,
# and answers one question of a closed list: yes or no by exit code alone, a value as `key=value`
# lines, a list as one `run/v1` line per item.
#
#   §FOLD     a repeated line counts once, a later value answers, a cancelled line is absent.
#   §NAME     every answer over a planted log equals the answer over it with each line's fields moved.
#   §FORM     a yes or no answer prints nothing; value lines are `key=value`; list lines start `run/v1|`.
#   §UNKNOWN  an unlisted question exits 2 and prints the list.
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

finish
