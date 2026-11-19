#!/bin/bash
# tests/run-seal.test.sh — the seal that vouches for a run's plan and log (payload/scripts/lib/seal.sh),
# and the one resolver of the repository's common git directory it lives in (lib/root.sh git_common_dir).
#
#   §HOME     git_common_dir answers the same directory from the main checkout, a linked worktree, a
#             subdirectory and a path not made yet, and nothing outside a repository; a seal written from
#             a worktree lands in the common directory, never in the tree's own git directory, and a plan
#             reached through a linked directory is the same seal.
#   §SEAL     verify, write and remove driven directly: no seal, clean, and each road of a change named by
#             what and how; a caught change stays caught through an honest write until the run is vouched
#             for; the command a write wraps runs between the check and the new seal.
#   §LOCK     a held lock turns a call away in well under a hook's ten seconds with nothing run; a dead
#             holder's lock is taken over; honest appends racing each other leave the run clean.
#
# FIXTURE FIDELITY. Every world is a real `git init` in a scratch directory, with a real linked worktree
# where one is named; plan and log are real files changed by the shell commands a person would type.
#
# ANTI-VACUITY. Each absence read sits beside a presence read of the same thing in the same world: no seal
# in the tree's git directory beside one in the common directory, nothing run under a held lock beside the
# same command run once the holder is dead, the lock gone beside the lock planted.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/seal.sh"

SB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export GIT_CEILING_DIRECTORIES="$SB"
M="$SB/main"
mkdir -p "$M/.bionic/docs/plans/e" "$M/.bionic/docs/record/w" "$SB/outside"
git -C "$M" init -q && git -C "$M" -c user.email=t@example.com -c user.name=T commit -q --allow-empty -m seed
git -C "$M" worktree add -q "$SB/tree" 2>/dev/null
P="$M/.bionic/docs/plans/e/w.plan.md"
L="$M/.bionic/docs/record/w/run.log"
HOME_DIR="$M/.git/bionic-seal"
base() {  # the run as it stood when sealed: no seal, a two-line plan, a three-line log
  seal_remove "$P"
  printf '# plan\n| T1 | row |\n' > "$P"
  printf 'run/v1|ev=step|n=1|at=a\nrun/v1|ev=step|n=2|at=b\nrun/v1|ev=step|n=3|at=c\n' > "$L"
  seal_write "$P" "$L"
}
road() {  # <label> <expected line> <shell change> — seal the base run, make the change, verify
  local out rc
  base; eval "$3"
  out="$(seal_verify "$P")"; rc=$?
  expect_eq "$1: verify names it" "$2" "$out"
  expect_status "$1: verify exits 1" 1 "$rc"
}

section "HOME"
expect_eq "the main checkout's common directory is its .git" "$M/.git" "$(git_common_dir "$M")"
expect_eq "a linked worktree answers the same directory" "$M/.git" "$(git_common_dir "$SB/tree")"
expect_eq "a subdirectory answers it" "$M/.git" "$(git_common_dir "$M/.bionic/docs/plans/e")"
expect_eq "a path not made yet answers its nearest directory's" "$M/.git" "$(git_common_dir "$M/no/such/dir")"
out="$(git_common_dir "$SB/outside")"; rc=$?
expect_status "outside any repository it exits 1" 1 "$rc"
expect_empty "and prints nothing" "$out"
TP="$SB/tree/w.plan.md"; printf 'p\n' > "$TP"
seal_write "$TP" "$SB/tree/run.log"; rc=$?
expect_status "a run whose plan sits in a worktree is sealed" 0 "$rc"
expect_eq "its seal is in the common directory" 1 "$(ls "$HOME_DIR"/*.seal 2>/dev/null | wc -l | tr -d ' ')"
expect_eq "and not in the tree's own git directory" "" "$(find "$M/.git/worktrees" -name '*.seal')"
expect_eq "the seal names the plan by its canonical path" "plan=$TP" "$(grep '^plan=' "$HOME_DIR"/*.seal)"
ln -s "$SB/tree" "$SB/link"
expect_eq "the plan reached through a linked directory is the same seal" clean "$(seal_verify "$SB/link/w.plan.md")"
seal_remove "$TP"

section "SEAL"
out="$(seal_verify "$P")"; rc=$?
expect_eq "a run never sealed reads none" none "$out"
expect_status "and exits 2" 2 "$rc"
printf '# plan\n' > "$P"; : > "$L"
seal_write "$P" "$L"; rc=$?
expect_status "the first seal of an open run is written clean" 0 "$rc"
expect_eq "and says no seal stood before it" none "$SEAL_WAS"
S="$(ls "$HOME_DIR"/*.seal)"
expect_eq "the seal is plain text: plan, digest, log, length, digest, state" \
  "seal/v1|plan=$P|plan_sum=$(cksum < "$P")|log=$L|log_len=0|log_sum=$(cksum < /dev/null | cut -d' ' -f1)|state=clean|what=|how=" \
  "$(paste -sd'|' - < "$S")"
base; expect_eq "a sealed run that is unchanged verifies clean" clean "$(seal_verify "$P")"
expect_status "and exits 0" 0 "$(seal_verify "$P" >/dev/null; echo $?)"
road "the plan removed" "changed what=plan how=gone" 'rm "$P"'
road "the plan renamed off its name" "changed what=plan how=gone" 'mv "$P" "${P%.plan.md}.md"'
road "the plan edited in place" "changed what=plan how=changed" 'sed -i.bak "s/row/ROW/" "$P"'
road "a line added to the plan" "changed what=plan how=changed" 'printf "| T9 | x |\n" >> "$P"'
road "the log removed" "changed what=log how=gone" 'rm "$L"'
road "the log emptied" "changed what=log how=shortened" ': > "$L"'
road "the log's last line cut" "changed what=log how=shortened" 'sed -i.bak "\$d" "$L"'
road "a line added to the log by hand" "changed what=log how=added" 'printf "run/v1|ev=abandon|at=d\n" >> "$L"'
road "a byte of the log changed at its length" "changed what=log how=changed" 'sed -i.bak "s/n=2/n=9/" "$L"'
road "the log rewritten longer" "changed what=log how=changed" 'sed -i.bak "s/n=2/n=29/" "$L"'
seal_remove "$P"; rm -f "$L"; seal_write "$P" "$L"
printf 'run/v1|ev=step|n=9|at=z\n' > "$L"
expect_eq "a log made by hand where the seal had none reads added" "changed what=log how=added" "$(seal_verify "$P")"
base; printf 'run/v1|ev=step|n=9|at=d\n' >> "$L"
seal_write "$P" "$L"; rc=$?
expect_status "an honest write over a caught change seals it changed" 1 "$rc"
expect_eq "and says what it caught" "changed what=log how=added" "$SEAL_WAS"
expect_eq "the change stays caught though the files now match the seal" "changed what=log how=added" "$(seal_verify "$P")"
seal_write "$P" "$L" sh -c 'printf "run/v1|ev=hand|at=e\n" >> "$1"' _ "$L"
expect_eq "a later honest append does not clear it" "changed what=log how=added" "$(seal_verify "$P")"
seal_write --vouch run "$P" "$L"; rc=$?
expect_status "the person's word seals the run as it stands" 0 "$rc"
expect_eq "and the run verifies clean" clean "$(seal_verify "$P")"
base; seal_write "$P" "$L" sh -c 'printf "run/v1|ev=hand|at=e\n" >> "$1"' _ "$L"; rc=$?
expect_status "an append wrapped by the write is sealed with it" 0 "$rc"
expect_eq "so the run verifies clean" clean "$(seal_verify "$P")"
expect_eq "and the append happened" 4 "$(wc -l < "$L" | tr -d ' ')"
seal_write "$P" "$L" false
expect_eq "the wrapped command's exit is handed back" 1 "$SEAL_RC"
base; printf '| T2 | new |\n' >> "$P"
seal_write --vouch plan "$P" "$L"; rc=$?
expect_status "a plan write the hook admitted is vouched for" 0 "$rc"
expect_eq "so the run verifies clean" clean "$(seal_verify "$P")"
printf 'run/v1|ev=hand|at=f\n' >> "$L"
seal_write --vouch plan "$P" "$L"
expect_eq "vouching for the plan never vouches for a hand change to the log" "changed what=log how=added" "$(seal_verify "$P")"
rm "$P"; seal_write --vouch run "$P" "$L"; rc=$?
expect_status "a run whose plan is gone cannot be vouched for" 1 "$rc"
expect_eq "it stays changed, plan gone" "changed what=plan how=gone" "$(seal_verify "$P")"
seal_remove "$P"; rc=$?
expect_status "remove exits 0" 0 "$rc"
expect_eq "and the run reads none" none "$(seal_verify "$P")"
expect_status "remove of a seal not there exits 0" 0 "$(seal_remove "$P"; echo $?)"
seal_write "$P" "$L"; rc=$?
expect_status "with no seal and no plan nothing is sealed" 2 "$rc"
expect_eq "and no seal file is left" "" "$(ls "$HOME_DIR"/*.seal 2>/dev/null)"
OP="$SB/outside/w.plan.md"; printf 'p\n' > "$OP"
seal_write "$OP" "$SB/outside/run.log" sh -c ': > "$1"' _ "$SB/outside/ran"; rc=$?
expect_status "outside any repository nothing is sealed" 2 "$rc"
expect_true "but the wrapped command still ran" test -f "$SB/outside/ran"
expect_eq "and verify says there is no home" nohome "$(seal_verify "$OP")"

section "LOCK"
base
mkdir "$HOME_DIR/.reap"; printf '%s\n' "$$" > "$HOME_DIR/.reap/pid"
expect_true "a live holder's lock stands" test -d "$HOME_DIR/.reap"
t0=$SECONDS; seal_write "$P" "$L" sh -c ': > "$1"' _ "$SB/held"; rc=$?; waited=$((SECONDS - t0))
expect_status "a write meets a held lock and exits 75" 75 "$rc"
expect_true "it waited, then gave up well under ten seconds ($waited s)" test "$waited" -ge 1 -a "$waited" -le 4
expect_false "and ran nothing" test -f "$SB/held"
out="$(seal_verify "$P")"; rc=$?
expect_eq "verify meets it too and says busy" busy "$out"
expect_status "with exit 75" 75 "$rc"
sh -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$HOME_DIR/.reap/pid"
seal_write "$P" "$L" sh -c ': > "$1"' _ "$SB/held"; rc=$?
expect_status "a dead holder's lock is taken over" 0 "$rc"
expect_true "and the command ran" test -f "$SB/held"
expect_false "and the lock is let go" test -d "$HOME_DIR/.reap"
base
for i in 1 2 3 4 5 6 7 8; do
  seal_write "$P" "$L" sh -c 'printf "run/v1|ev=hand|n=%s|at=g\n" "$2" >> "$1"' _ "$L" "$i" &
done
wait
expect_eq "eight appends racing each other all landed" 11 "$(wc -l < "$L" | tr -d ' ')"
expect_eq "and the run verifies clean" clean "$(seal_verify "$P")"

finish
