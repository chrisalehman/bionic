#!/bin/bash
# tests/log.test.sh — payload/scripts/lib/log.sh, the one appender of a run's log.
#
# `log_append <type> <key>=<value>…` writes `run/v1|ev=<type>|<key>=<value>|…|at=<UTC seconds>` to the
# file RUN_LOG names, and refuses (exit 2, file unchanged) what would break the shape or the list.
#
#   §SHAPE   a line matches the shape and reads back by field name; no type, a bare word, a `|` in a
#            value and a caller's own `at=` are refused; LOG_AT stamps the line when in the shape, is refused
#            when not, and only the files its list names set it, each for its reason.
#   §TYPES   a hyphenated type no list holds and a retired word are refused; each of the 30 listed types is accepted,
#            and the list holds those thirty and no more.
#   §SEAL    each append is checked against the run's seal, written, and sealed again: an append to a sealed run
#            leaves it clean; a hand change to the log or the plan is marked changed at the next append, whose line
#            still lands, and no later append clears the mark; an open run with no seal is sealed as found, once,
#            with one hand line `what=seal` ahead of the caller's; a closed run and a dry call seal nothing as found;
#            an epic's log and a tree's linked spelling find their plan; a held lock leaves the line unsealed and
#            owed beside the seal, so it reads clean; eight racing appends leave the run clean.
#
# FIXTURE FIDELITY. The log is a real file in a scratch directory; only its path is synthesized. §SEAL's world is a
# real `git init` with a real linked worktree, and its hand changes are the shell writes a person would type.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/log.sh"

export RUN_LOG; RUN_LOG="$(mktemp -d)/record/w/run.log"
refused() {  # <label> <args…> -> exit 2 and the file byte-for-byte as it was
  local before; before="$(cat "$RUN_LOG")"; local l="$1"; shift
  log_append "$@" 2>/dev/null; expect_eq "$l: exit 2" 2 "$?"
  expect_eq "$l: file unchanged" "$before" "$(cat "$RUN_LOG")"
}

section "SHAPE"
log_append ready row=T6 name=w50-T6; expect_eq "a valid call exits 0" 0 "$?"
log_append step n=4 by=me; line="$(tail -n 1 "$RUN_LOG")"
expect_regex "the line is run/v1, ev, fields, at as UTC seconds" \
  '^run/v1\|ev=step\|n=4\|by=me\|at=[0-9]{4}(-[0-9]{2}){2}T[0-9]{2}(:[0-9]{2}){2}Z$' "$line"
expect_eq "a field reads back by name" "me" "$(line_value "$line" by)"
refused "no event type"
refused "a bare word" step n
refused "a value with a bar" step "why=a|b"
refused "a key that sets at" step at=1
LOG_AT=2026-10-06T11:48:01Z log_append ask key=a:b
expect_eq "a caller's instant in the log's shape stamps the line" "2026-10-06T11:48:01Z" "$(line_value "$(tail -n 1 "$RUN_LOG")" at)"
LOG_AT=2026-10-06T11:48Z refused "a caller's instant off the log's shape" ask key=a:b
LA_WHO="hooks/poker/proof.sh:the approval of the plan and its asks close at one instant
payload/scripts/close-out.sh:the delivery is restated with the archive line at its own second, so every reader of it reads one instant
payload/scripts/lib/owed.sh:the asks library stamps a round of an ask at the instant it was raised"
expect_eq "no file hands the appender an instant but those the list names, each for its reason" "$(printf '%s\n' "$LA_WHO" | cut -d: -f1 | paste -sd' ' -)" "$(cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rl 'LOG_AT=' payload hooks | LC_ALL=C sort | paste -sd' ' -)"

section "TYPES"
refused "a hyphenated type no list holds" plant-type row=T1
refused "a retired type" settled row=T1
refused "a type holding a space" "ready step" row=T1
for t in ready candidate verdict published returned stalled standing admitted void run walk step \
  approval proof finding waiver decision order bind handoff dispatch tree born ask stop debt \
  abandon cancel hand drop ruling; do
  log_append "$t" k=v 2>/dev/null; rc=$?; n=$((${n:-0} + 1)); expect_eq "$t is accepted" 0 "$rc"
done
expect_eq "thirty-one types were driven" 31 "$n"
# shellcheck disable=SC2086
set -- $LOG_TYPES
expect_eq "the list is closed at thirty-one: the sealing adds no type" 31 "$#"

section "SEAL"
# A real repository: the plan in plans/e/, its log in record/w/, the seal in the repository's .git.
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/seal.sh"
SWT="$(cd "$(mktemp -d)" && pwd -P)"; SW="$SWT/r"; mkdir -p "$SW"
export GIT_CEILING_DIRECTORIES="$SWT"
git -C "$SW" init -q && git -C "$SW" -c user.email=t@example.com -c user.name=T commit -q --allow-empty -m seed
D="$SW/.bionic/docs"; mkdir -p "$D/plans/e" "$D/record/w"
WP="$D/plans/e/w.plan.md"; WL="$D/record/w/run.log"; SH="$SW/.git/bionic-seal"
STEP4='run/v1|ev=step|n=4|at=2026-11-01T00:00:00Z'
sealed() {  # an open run at step 4, sealed clean as it stands
  seal_remove "$WP"; printf '# plan\n' > "$WP"; printf '%s\n' "$STEP4" > "$WL"
  seal_write "$WP" "$WL"
}
unsealed() {  # <log lines> -> the run with no seal
  seal_remove "$WP"; printf '# plan\n' > "$WP"; printf '%s\n' "$1" > "$WL"
}
mark() { grep -hE '^(state|what|how)=' "$SH/w.plan.md".*.seal 2>/dev/null | paste -sd' ' -; }
sealings() { /usr/bin/grep -c '^run/v1|ev=hand|what=seal|' "$1"; }

sealed
RUN_LOG="$WL" log_append dispatch row=T1; rc=$?
expect_status "an append to a sealed run exits 0" 0 "$rc"
expect_regex "and lands" '^run/v1\|ev=dispatch\|row=T1\|at=' "$(tail -n 1 "$WL")"
expect_eq "and is sealed with the run, which verifies clean" clean "$(seal_verify "$WP")"
expect_eq "the seal holds the log's length after the append" "log_len=$(wc -c < "$WL" | tr -d ' ')" \
  "$(grep -h '^log_len=' "$SH/w.plan.md".*.seal)"

sealed; printf 'run/v1|ev=abandon|at=2026-11-01T00:00:01Z\n' >> "$WL"
RUN_LOG="$WL" log_append dispatch row=T2; rc=$?
expect_status "an append after a hand line exits 0" 0 "$rc"
expect_regex "and its line still lands" 'row=T2\|' "$(tail -n 1 "$WL")"
expect_eq "the hand line is caught at the check and marked in the seal" "state=changed what=log how=added" "$(mark)"
RUN_LOG="$WL" log_append dispatch row=T3
expect_regex "a later honest append lands" 'row=T3\|' "$(tail -n 1 "$WL")"
expect_eq "and does not clear the mark" "state=changed what=log how=added" "$(mark)"
expect_eq "so the run reads changed though its files match the seal" "changed what=log how=added" "$(seal_verify "$WP")"

sealed; printf '| T9 | x |\n' >> "$WP"
RUN_LOG="$WL" log_append dispatch row=T4
expect_regex "an append after a hand edit of the plan lands" 'row=T4\|' "$(tail -n 1 "$WL")"
expect_eq "and the plan's change is marked" "state=changed what=plan how=changed" "$(mark)"

unsealed 'run/v1|ev=step|n=3|at='
expect_eq "an open run never sealed reads none" none "$(seal_verify "$WP")"
RUN_LOG="$WL" log_append dispatch row=T5; rc=$?
expect_status "its first append exits 0" 0 "$rc"
expect_eq "and seals it as found, the line no appender wrote with it" clean "$(seal_verify "$WP")"
expect_regex "the sealing is logged as a hand act, ahead of the caller's line" \
  '^run/v1\|ev=hand\|what=seal\|why=[^|]+\|at=' "$(tail -n 2 "$WL" | head -n 1)"
expect_regex "and the caller's line is last" 'row=T5\|' "$(tail -n 1 "$WL")"
RUN_LOG="$WL" log_append dispatch row=T6
expect_eq "a run is sealed as found once" 1 "$(sealings "$WL")"
expect_eq "and stays clean" clean "$(seal_verify "$WP")"

unsealed "$STEP4"
printf 'run/v1|ev=abandon|at=2026-11-01T00:00:01Z\n' >> "$WL"
RUN_LOG="$WL" log_append dispatch row=T7; rc=$?
expect_status "an append to an abandoned run with no seal exits 0" 0 "$rc"
expect_regex "and lands" 'row=T7\|' "$(tail -n 1 "$WL")"
expect_eq "a closed run is not sealed as found" none "$(seal_verify "$WP")"
expect_eq "and no sealing is logged" 0 "$(sealings "$WL")"

unsealed "$STEP4"
BIONIC_DRY_STEP=5 RUN_LOG="$WL" log_append dispatch row=T8
expect_regex "an append under a dry call lands" 'row=T8\|' "$(tail -n 1 "$WL")"
expect_eq "but a dry call never seals a run as found" none "$(seal_verify "$WP")"
sealed
BIONIC_DRY_STEP=5 RUN_LOG="$WL" log_append dispatch row=T9
expect_eq "while its append to a sealed run is sealed" clean "$(seal_verify "$WP")"

mkdir -p "$D/record/orphan"; OL="$D/record/orphan/run.log"
RUN_LOG="$OL" log_append dispatch row=T10
expect_regex "a log no plan names takes the append" 'row=T10\|' "$(tail -n 1 "$OL")"
expect_nonempty "a sealed run's seal names its log" "$(grep -l "^log=$WL\$" "$SH"/*.seal 2>/dev/null)"
expect_empty "and no seal names a log no plan has" "$(grep -l "^log=$OL\$" "$SH"/*.seal 2>/dev/null)"

EP="$D/plans/epic-9/epic.plan.md"; EL="$D/record/epic-9/run.log"
mkdir -p "${EP%/*}" "${EL%/*}"; printf '# epic\n' > "$EP"; printf '%s\n' "$STEP4" > "$EL"
RUN_LOG="$EL" log_append dispatch row=T11
expect_eq "an epic's log is joined to its plan by the folder, and sealed" clean "$(seal_verify "$EP")"

git -C "$SW" worktree add -q "$SW/tree" 2>/dev/null; ln -s "$SW/.bionic" "$SW/tree/.bionic"
sealed
RUN_LOG="$SW/tree/.bionic/docs/record/w/run.log" log_append dispatch row=T12
expect_regex "an append through a tree's linked state folder lands in the one log" 'row=T12\|' "$(tail -n 1 "$WL")"
expect_eq "and is sealed in the one seal" clean "$(seal_verify "$WP")"

sealed
mkdir "$SH/.reap"; printf '%s\n' "$$" > "$SH/.reap/pid"
RUN_LOG="$WL" log_append dispatch row=T13; rc=$?
expect_status "an append that meets a held lock exits 0" 0 "$rc"
expect_regex "and lands" 'row=T13\|' "$(tail -n 1 "$WL")"
rm -rf "$SH/.reap"
expect_eq "unsealed, its line owed beside the seal, so the run reads clean" clean "$(seal_verify "$WP")"

sealed
for i in 1 2 3 4 5 6 7 8; do RUN_LOG="$WL" log_append dispatch "row=R$i" & done
wait
expect_eq "eight appends racing all land" 9 "$(wc -l < "$WL" | tr -d ' ')"
expect_eq "and the run verifies clean" clean "$(seal_verify "$WP")"
rm -rf "$SWT"

finish
