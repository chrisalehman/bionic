#!/bin/bash
# tests/pr-route.test.sh — the pull request route: `session-poker.sh publish` against a bare remote and a stand-in host.
#
#   §CONSENT  with no release approval, and with one at an older head, publish exits non-zero before any network: the
#             bare remote holds no working branch and the stand-in's log is empty.
#   §OPEN     with the approval at the head, the remote holds the working head, the stand-in's log one create against
#             the integration branch, the run's log the pull request; the local integration branch is unmoved; at that
#             head again nothing is pushed or opened; at a new approved head the branch is pushed and the request kept.
#   §FAIL     with the remote unreachable, and with the stand-in exiting 1, publish exits non-zero and prints the cause,
#             an ask waits on the person, the log holds no pull request and the sitrep does not read delivered.
#   §STATE    `reader <plan> pr` answers nothing before the publish and the request after it; the stand-in answers a
#             request's state, merges by a merge commit and by a squash, and closes, each on the bare remote alone.
#   §WALL     publish is the orchestrator's: the Bash wall reads it as one of the verbs a writer may not call.
#
# FIXTURE FIDELITY. Each case is a copy of one door fixture (tests/lib/door.sh): a real repository on its working branch
# with its bound plan, the plan's header naming `integration-branch: main` as a planner writes it. The remote is a bare
# repository holding main alone (tests/lib/rehearsal.sh `rh_remote`), the host the stand-in gh (`rh_host`), the only gh
# on the PATH publish runs under. The release approval is the approval event the approve verb writes, planted through
# its writer (lib/proof.sh `proof_approval_event`). Nothing here reaches a real remote or a real host.
#
# Usage: bash tests/pr-route.test.sh

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
. "$(dirname "$0")/lib/rehearsal.sh"
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"

PRR_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
PRR_READER="${BIONIC_SCRIPTS_DIR}/payload/scripts/reader.sh"
PRR_URL1="https://example.invalid/pull/1"
PRR_BASE="$(door_world "$WORLD_ROOT/base")"; PRR_BASE="${PRR_BASE% *}"
# The planner's header names the integration branch; the door fixture's page leaves it out.
awk 'NR == 1 { print; print "integration-branch: main"; next } { print }' "$PRR_BASE/$DOOR_PLAN_REL" > "$PRR_BASE/p.n" \
  && mv "$PRR_BASE/p.n" "$PRR_BASE/$DOOR_PLAN_REL"
# The working branch carries one commit past main, the row's work, so a merge has something to merge.
printf 'rehearsal_landed() { return 0; }\n' > "$PRR_BASE/payload/scripts/lib/said.sh" \
  && git -C "$PRR_BASE" add -A && git -C "$PRR_BASE" commit --quiet -m "the row's work"

# prr_case <name> -> a copy of the fixture under WORLD_ROOT/<name>, its bare remote at <name>.git and its host in
# <name>-host; sets R (the copy), B (the bare remote), HD (the host's directory), P (the plan), L (the run's log)
prr_case() {
  R="$(door_copy "$PRR_BASE" "$WORLD_ROOT/$1")"; R="${R% *}"; B="$WORLD_ROOT/$1.git"; HD="$WORLD_ROOT/$1-host"
  P="$R/$DOOR_PLAN_REL"; L="$R/.bionic/docs/record/wave-x/run.log"
  rh_remote "$R" "$B" && rh_host "$HD"
}
prr_head() { git -C "$R" rev-parse --verify -q "refs/heads/$DOOR_BRANCH"; }
prr_approve() {  # <head> -> the release approved at <head>, as the approve verb records it
  bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_approval_event "$2" release by=fixture "head=$3" said=approved' _ "$PRR_LIB" "$P" "$1"
}
prr_code() {  # -> one commit of code on the working branch: past an approval, it is no prose
  printf 'rehearsal_landed() { return 0; }\n# %s\n' "$RANDOM" >> "$R/payload/scripts/lib/said.sh"
  git -C "$R" add -A && git -C "$R" commit --quiet -m "a library change"
}
prr_publish() { door_run "$R" env PATH="$RH_GHPATH" bash "$DOOR_POKER" publish; }
prr_remote_heads() { git -C "$B" for-each-ref --format='%(refname:short)' refs/heads | paste -sd' ' -; }
prr_gh_log() { cat "$HD/bin/gh.log" 2>/dev/null; }
prr_pr_events() { /usr/bin/grep -c '|ev=published|part=pr|' "$L" 2>/dev/null | tr -d ' '; }
prr_gh() { door_run "$R" env PATH="$RH_GHPATH" gh "$@"; }

# ============================================================
section "§CONSENT: publish checks the release approval at the working head before any network"
# ============================================================
# fails-when: publish pushes or calls the host with no release approval, or with one at a head the working head moved
# past with code.
prr_case consent-none
expect_eq "CN-0 precondition: the bare remote holds main alone, the plan names the integration branch, no approval stands" \
  "main|main|1" "$(prr_remote_heads)|$(bash "$PRR_READER" "$P" header integration-branch | sed 's/^integration-branch=//')|$(bash "$PRR_READER" "$P" approved release; echo $?)"
prr_publish
expect_eq "CN-1 with no release approval publish exits 1, refused" "1|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q 'REFUSED' && echo yes)"
expect_eq "CN-2 …the bare remote holds main and no working branch, the stand-in's log is empty, the run's log holds no request" \
  "main||0" "$(prr_remote_heads)|$(prr_gh_log)|$(prr_pr_events)"

prr_case consent-stale
PRR_OLD="$(prr_head)"; prr_approve "$PRR_OLD"; prr_code
expect_eq "CN-3 precondition: the approval names the old head and the working head moved past it with code" "$PRR_OLD|yes" \
  "$(bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_approved_head "$2" release' _ "$PRR_LIB" "$P")|$([ "$(prr_head)" != "$PRR_OLD" ] && echo yes)"
prr_publish
expect_eq "CN-4 with the approval at an older head publish exits 1, refused, naming both heads" "1|yes|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "${PRR_OLD:0:12}" && echo yes)|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "$(prr_head | cut -c1-12)" && echo yes)"
expect_eq "CN-5 …the bare remote holds main and no working branch, the stand-in's log is empty, the run's log holds no request" \
  "main||0" "$(prr_remote_heads)|$(prr_gh_log)|$(prr_pr_events)"

# ============================================================
section "§OPEN: with the approval at the head, publish pushes, opens one request and records it, once a head"
# ============================================================
# fails-when: the remote lacks the working head, the stand-in holds no create or two, the create names another base or
# head, the run's log holds no published event of part pr with its address, branch, head and base, the local main moves,
# a second publish at one head pushes or opens anything, or a new approved head opens a second request.
prr_case open
OP_H="$(prr_head)"; OP_MAIN="$(git -C "$R" rev-parse --verify -q refs/heads/main)"; prr_approve "$OP_H"
prr_publish
expect_eq "OP-1 publish exits 0 and names the request's address" "0|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -qF "$PRR_URL1" && echo yes)"
[ "$DOOR_RC" = 0 ] || printf '%s\n' "$DOOR_OUT" | tail -5 | sed 's/^/    | /'
expect_eq "OP-2 the bare remote holds the working branch at the working head" "$OP_H" \
  "$(git -C "$B" rev-parse --verify -q "refs/heads/$DOOR_BRANCH")"
expect_eq "OP-3 the stand-in's log holds one create, against main from the working branch" "1|1" \
  "$(prr_gh_log | /usr/bin/grep -c '^pr create ' | tr -d ' ')|$(prr_gh_log | /usr/bin/grep -c "^pr create --base main --head $DOOR_BRANCH " | tr -d ' ')"
expect_contains "OP-4 the run's log holds the request as a published event of its own part" \
  "|ev=published|part=pr|url=$PRR_URL1|branch=$DOOR_BRANCH|commit=$OP_H|base=main|by=publish|at=" "$(cat "$L")"
expect_eq "OP-5 the local integration branch points where it did before the route" "$OP_MAIN" \
  "$(git -C "$R" rev-parse --verify -q refs/heads/main)"
# The second call meets an unreachable remote: a push or a call to the host would fail it.
git -C "$R" remote set-url origin "$WORLD_ROOT/nowhere.git"
prr_publish
expect_eq "OP-6 at the same head again publish exits 0 and says nothing was made" "0|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q 'nothing was pushed or opened' && echo yes)"
expect_eq "OP-6b …no second create, no second event" "1|1" \
  "$(prr_gh_log | /usr/bin/grep -c '^pr create ' | tr -d ' ')|$(prr_pr_events)"
git -C "$R" remote set-url origin "$B"
prr_code; OP_H2="$(prr_head)"; prr_approve "$OP_H2"
prr_publish
expect_eq "OP-7 at a new approved head publish exits 0, the remote holds the new head, the request is kept: no second create" \
  "0|$OP_H2|1" "$DOOR_RC|$(git -C "$B" rev-parse --verify -q "refs/heads/$DOOR_BRANCH")|$(prr_gh_log | /usr/bin/grep -c '^pr create ' | tr -d ' ')"
expect_contains "OP-7b …and the run's log holds the request at the new head, the same address" \
  "|ev=published|part=pr|url=$PRR_URL1|branch=$DOOR_BRANCH|commit=$OP_H2|base=main|by=publish|at=" "$(tail -1 "$L")"

# ============================================================
section "§FAIL: a failed push or request exits non-zero with the cause and leaves an ask for the person"
# ============================================================
# fails-when: publish exits 0 on a failed push or create, prints no cause, opens no ask, opens one that waits on an
# event, writes a request into the run's log, or the sitrep reads delivered.
prr_fail_reads() {  # <id> <the case> <cause> -> the failure's assertions on the case at hand
  local ask
  expect_eq "$1 $2: publish exits 4 and prints the cause" "4|yes" \
    "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -qF -- "$3" && echo yes)"
  ask="$(bash "$PRR_READER" "$P" asks | /usr/bin/grep '|key=pr:wave:01-x|')"
  expect_eq "${1}b …an ask on the register for the publish, waiting on the person" "yes|user" \
    "$([ -n "$ask" ] && echo yes)|$(OWED_ROOT="$R" bash -c '. "$1/owed.sh" && ask_waits_on pr:wave:01-x' _ "$PRR_LIB")"
  expect_eq "${1}c …its prompt names the cause" "yes" "$(printf '%s\n' "$ask" | /usr/bin/grep -qF -- "$3" && echo yes)"
  expect_eq "${1}d …the run's log holds no request" "0" "$(prr_pr_events)"
  door_run "$R" bash "$DOOR_POKER" sitrep
  expect_eq "${1}e …the sitrep reads the run at step 4, not delivered" "run.step: 4|" \
    "$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep '^run.step:' | cut -c1-11)|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -i '^run.step:.*delivered')"
}
prr_case fail-remote
prr_approve "$(prr_head)"
git -C "$R" remote set-url origin "$WORLD_ROOT/nowhere.git"
prr_publish
prr_fail_reads FL-1 "with the remote unreachable" "does not appear to be a git repository"
expect_eq "FL-1f …and the host was never called" "" "$(prr_gh_log)"

prr_case fail-host
prr_approve "$(prr_head)"; FL_H="$(prr_head)"
printf 'HTTP 502: the host is down\n' > "$HD/bin/gh.fail"
prr_publish
prr_fail_reads FL-2 "with the stand-in exiting 1" "HTTP 502: the host is down"
expect_eq "FL-2f …the push was made, the create asked once" "$FL_H|1" \
  "$(git -C "$B" rev-parse --verify -q "refs/heads/$DOOR_BRANCH")|$(prr_gh_log | /usr/bin/grep -c '^pr create ' | tr -d ' ')"
rm -f "$HD/bin/gh.fail"
prr_publish
expect_eq "FL-3 once the host answers, publish exits 0, records the request and closes the ask" "0|1|" \
  "$DOOR_RC|$(prr_pr_events)|$(bash "$PRR_READER" "$P" asks | /usr/bin/grep '|key=pr:wave:01-x|')"

# ============================================================
section "§STATE: the reader answers the run's request, and the stand-in answers its state and merges it three ways"
# ============================================================
# fails-when: `reader pr` answers before the publish or answers nothing after it; the stand-in answers a state the
# request is not in, a merge commit with other parents, a squash that is not one commit holding the head's tree, a
# close that moves the remote; or any of them moves the local integration branch.
prr_case state-merge
ST_H="$(prr_head)"; ST_MAIN="$(git -C "$R" rev-parse --verify -q refs/heads/main)"
ST_NONE="$(bash "$PRR_READER" "$P" pr)"; ST_RC=$?
expect_eq "ST-1 before the publish the reader's pr answers nothing, exit 1" "1|" "$ST_RC|$ST_NONE"
prr_approve "$ST_H"; prr_publish
expect_eq "ST-2 after it the reader's pr answers the request: its address, branch, head and base" \
  "0|$PRR_URL1|$DOOR_BRANCH|$ST_H|main" \
  "$(bash "$PRR_READER" "$P" pr >/dev/null; echo $?)|$(bash "$PRR_READER" "$P" pr | sed -n 's/^url=//p')|$(bash "$PRR_READER" "$P" pr | sed -n 's/^branch=//p')|$(bash "$PRR_READER" "$P" pr | sed -n 's/^commit=//p')|$(bash "$PRR_READER" "$P" pr | sed -n 's/^base=//p')"
prr_gh pr view "$PRR_URL1" --json state,mergeCommit --jq '.state + " " + (.mergeCommit.oid // "-")'
expect_eq "ST-3 the stand-in answers the open request's state, with no merge commit" "0|OPEN -" "$DOOR_RC|$DOOR_OUT"
prr_gh pr merge "$PRR_URL1" --merge
ST_TIP="$(git -C "$B" rev-parse --verify -q refs/heads/main)"
prr_gh pr view "$DOOR_BRANCH" --json state,mergeCommit --jq '.state + " " + .mergeCommit.oid'
expect_eq "ST-4 merged by a merge commit: MERGED, the remote's main the merge commit, its parents the old main then the head" \
  "0|MERGED $ST_TIP|$ST_MAIN $ST_H" "$DOOR_RC|$DOOR_OUT|$(git -C "$B" rev-list --parents -n 1 "$ST_TIP" | cut -d' ' -f2-)"
expect_eq "ST-4b …and the local main has not moved" "$ST_MAIN" "$(git -C "$R" rev-parse --verify -q refs/heads/main)"

prr_case state-squash
ST_H="$(prr_head)"; prr_approve "$ST_H"; prr_publish
prr_gh pr merge 1 --squash
ST_TIP="$(git -C "$B" rev-parse --verify -q refs/heads/main)"
prr_gh pr view 1 --json state,mergeCommit --jq '.state + " " + .mergeCommit.oid'
expect_eq "ST-5 merged by a squash: MERGED, one commit on the remote's main whose parent is the old main and tree the head's" \
  "0|MERGED $ST_TIP|$ST_MAIN|$(git -C "$R" rev-parse "$ST_H^{tree}")" \
  "$DOOR_RC|$DOOR_OUT|$(git -C "$B" rev-list --parents -n 1 "$ST_TIP" | cut -d' ' -f2-)|$(git -C "$B" rev-parse "$ST_TIP^{tree}")"
expect_eq "ST-5b …the working head is not on the remote's main, and the local main has not moved" "no|$ST_MAIN" \
  "$(git -C "$B" merge-base --is-ancestor "$ST_H" "$ST_TIP" && echo yes || echo no)|$(git -C "$R" rev-parse --verify -q refs/heads/main)"

prr_case state-close
prr_approve "$(prr_head)"; prr_publish
prr_gh pr close "$PRR_URL1"
prr_gh pr view "$PRR_URL1" --json state,mergeCommit
expect_eq "ST-6 closed: CLOSED with no merge commit, the remote's main where it was" \
  '0|{"state":"CLOSED","mergeCommit":null}|'"$ST_MAIN" "$DOOR_RC|$DOOR_OUT|$(git -C "$B" rev-parse --verify -q refs/heads/main)"

# ============================================================
section "§WALL: publish is the orchestrator's verb"
# ============================================================
# fails-when: the Bash wall's reader of the verbs a writer may not call does not read publish as one, or reads a verb
# the writer may call (rulings) as one.
WL() { bash -c '. "$1/git-argv.sh" && . "$1/walls.sh" && _wall_poker_contract_verb "$2"; r=$?; printf "%s|%s" "$r" "$_WALL_POKER_VERB"' \
  _ "$PRR_LIB" "$1" 2>/dev/null; }
expect_eq "WL-0 the reader answers a listed verb, amend, as one" "0|amend" "$(WL 'bash hooks/session-poker.sh amend w-T1 --reason x')"
expect_eq "WL-1 the wall reads 'bash hooks/session-poker.sh publish' as a verb only the orchestrator calls" "0|publish" \
  "$(WL 'bash hooks/session-poker.sh publish')"
expect_eq "WL-2 …and reads a writer's own read, rulings, as none" "1|" "$(WL 'bash hooks/session-poker.sh rulings w-T1')"

finish
