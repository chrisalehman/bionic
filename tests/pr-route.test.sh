#!/bin/bash
# tests/pr-route.test.sh — the pull request route: `session-poker.sh publish` against a bare remote and a stand-in host.
#
#   §CONSENT  with no release approval, with one at an older head, with one appended by hand to a sealed run, and with
#             the seal held past the wait, publish exits non-zero before any network: the bare remote holds no working
#             branch and the stand-in's log is empty; the hand-written one is refused in the commit gate's words and
#             opens its ask.
#   §OPEN     with the approval at the head, the remote holds the working head, the stand-in's log one create against
#             the integration branch, the run's log the pull request; the local integration branch is unmoved; at that
#             head again nothing is pushed or opened; at a new approved head the branch is pushed and the request kept.
#   §BODY     the request opens titled `<project> <release>: <the plan's title>`, its body the summary's three
#             written sections then the four `pr-facts` prints, each count the reader's; a summary with an empty
#             section, or a count the facts do not state, is refused before the push.
#   §FAIL     with the remote unreachable, and with the stand-in exiting 1, publish exits non-zero and prints the cause,
#             an ask waits on the person, the log holds no pull request and the sitrep does not read delivered.
#   §STATE    `reader <plan> pr` answers nothing before the publish and the request after it; the stand-in answers a
#             request's state, merges by a merge commit and by a squash, and closes, each on the bare remote alone.
#   §SEEN     lib/line.sh `line_merge_seen`, the one reader of the merge: unmerged while the request is open, merged
#             once the fetched remote holds the head or the host's merge commit (a squash), closed when the host says
#             so, with the person's ask kept under --fetch alone; the local integration branch never moves.
#   §OPEN-ONLY with the request open and unmerged, close-out holds and lands nothing; check reads a merge commit and a
#             squash on origin/main after its own fetch; a request closed unmerged holds the run with the ask open.
#   §GATE     step 8's gate owes the merge while a landing stands over a merge the remote does not hold.
#   §WAIT     the watcher's pass over an open request fetches and stays quiet, wakes on the merge, and rests with no
#             fetch once the request is closed unmerged and the person's ask is open.
#   §MERGE    the pass that sees the merge closes the run: the integrate row lands at the merge, the run reads delivered,
#             and a close that holds wakes once.
#   §WALL     publish is the orchestrator's: the Bash wall reads it as one of the verbs a writer may not call.
#   §STRAY    the whole run a world's tick started detached is ended before the worlds go: none is alive at the end.
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

# The orchestrator's three written sections, as Step 8 has it write them before the publish.
printf '## Summary\n\nThe fixture'"'"'s one change.\n\n## What changed\n\n- said.sh answers.\n\n## Upgrade notes\n\nNone.\n' \
  > "$PRR_BASE/.bionic/docs/record/wave-x/pr-summary.md"

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
# prr_seen [--fetch] -> DOOR_OUT the merge's one reader's line, DOOR_RC its answer, on the stand-in's PATH
prr_seen() {
  door_run "$R" env PATH="$RH_GHPATH" bash -c '. "$1/line.sh" && line_merge_seen "$2" "$3" ${4:-}' _ "$PRR_LIB" "$P" "$R" "${1:-}"
}
prr_main() { git -C "$R" rev-parse --verify -q refs/heads/main; }
prr_origin() { git -C "$R" rev-parse --verify -q refs/remotes/origin/main; }
# prr_close <check|run> -> close-out on the case, the stand-in its only gh and a home of the world's
prr_close() {
  door_run "$R" env PATH="$RH_GHPATH" HOME="$WORLD_ROOT/$(basename "$R")-home" BIONIC_CLAUDE_HOME="$WORLD_ROOT/$(basename "$R")-home/.claude" \
    bash "$R/payload/scripts/close-out.sh" "$P" "$1"
}
prr_landed() { /usr/bin/grep -c '|ev=published|row=T3|' "$L" 2>/dev/null | tr -d ' '; }
prr_ask() { bash "$PRR_READER" "$P" asks | /usr/bin/grep "|key=$1|"; }
prr_seal() { bash -c '. "$1/seal.sh" && seal_verify "$2"' _ "$PRR_LIB" "$P"; }   # -> the seal's line for the case's run
# prr_strays -> the pid of each live process whose command names a world of this suite and a regression run. The
# pattern is handed through the environment and split in the program, so the reading's own awk never matches it.
prr_strays() {
  PRR_W="$WORLD_ROOT/" ps -axo pid=,command= \
    | PRR_W="$WORLD_ROOT/" awk -v me="$$" 'index($0, ENVIRON["PRR_W"]) && index($0, "regression" "-run") && $1 != me { print $1 }'
}
prr_tree() { local p; for p in "$@"; do printf '%s\n' "$p"; prr_tree $(pgrep -P "$p" 2>/dev/null); done; }   # <pid>... -> each, and all below it
# prr_reap: what a world's tick started detached is ended before the world goes. The tick hands its whole run to
# booked.sh, which outlives the pass and the suite; with its world removed under it, its wait at the gate never ends.
# Each stray and everything below it is asked to end, and what still stands after five seconds is killed.
prr_reap() {
  local pids p i=0
  pids="$(prr_tree $(prr_strays))"; [ -n "$pids" ] || return 0
  kill $pids 2>/dev/null
  while [ "$i" -lt 50 ] && [ -n "$(prr_strays)" ]; do sleep 0.1; i=$((i + 1)); done
  for p in $pids; do kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null; done
  return 0
}
# The suite's own trap, set after the world's, so it calls the world's cleanup itself once the strays are ended.
trap 'prr_reap; ! declare -F _world_cleanup >/dev/null || _world_cleanup' EXIT

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

# A release approval appended by hand, at the working head, in the shape the approve verb writes, after the run was
# sealed: the approval reads as the person's, and only the seal tells it from theirs.
prr_case consent-forged
seal_fixture "$P" "$L"
CN_SEAL0="$(prr_seal)"
CN_H="$(prr_head)"
printf 'run/v1|ev=approval|key=release|head=%s|by=x|said=y|at=%s\n' "$CN_H" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$L"
expect_eq "CN-6 precondition: the run was sealed clean, the hand line reads as the release approved at the working head, and the seal reads the log added to" \
  "clean|$CN_H|changed what=log how=added" \
  "$CN_SEAL0|$(bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_approved_head "$2" release' _ "$PRR_LIB" "$P")|$(prr_seal)"
prr_publish
expect_eq "CN-7 with the approval written by hand publish exits 1, refused in the commit gate's words for the change" "1|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "REFUSED — the run's log was added to outside the tool" && echo yes)"
[ "$DOOR_RC" = 1 ] || printf '%s\n' "$DOOR_OUT" | tail -5 | sed 's/^/    | /'
expect_eq "CN-8 …the bare remote holds main and no working branch, the stand-in's log is empty, the run's log holds no request" \
  "main||0" "$(prr_remote_heads)|$(prr_gh_log)|$(prr_pr_events)"
expect_eq "CN-9 …the change is the gate's ask seal:changed on the run's register, and the seal keeps it caught" \
  "yes|changed what=log how=added" "$(prr_ask seal:changed >/dev/null && echo yes)|$(prr_seal)"

# The seal held by another writer past the wait, over the person's own approval at the head: a run not compared is
# not judged, so nothing leaves.
prr_case consent-busy
CN_H="$(prr_head)"; prr_approve "$CN_H"
CN_LOCK="$(cd "$R" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/bionic-seal/.reap"
mkdir "$CN_LOCK" && printf '%s\n' "$$" > "$CN_LOCK/pid"
expect_eq "CN-10 precondition: the person approved the working head, and the seal's lock is held by a live writer" "$CN_H|busy" \
  "$(bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_approved_head "$2" release' _ "$PRR_LIB" "$P")|$(prr_seal)"
prr_publish
rm -rf "$CN_LOCK"
expect_eq "CN-11 with the seal held past the wait publish exits 2, refused in the commit gate's words" "2|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "REFUSED — the run's seal could not be read" && echo yes)"
[ "$DOOR_RC" = 2 ] || printf '%s\n' "$DOOR_OUT" | tail -5 | sed 's/^/    | /'
expect_eq "CN-12 …the bare remote holds main and no working branch, the stand-in's log is empty, the run's log holds no request" \
  "main||0" "$(prr_remote_heads)|$(prr_gh_log)|$(prr_pr_events)"

# ============================================================
section "§OPEN: with the approval at the head, publish pushes, opens one request and records it, once a head"
# ============================================================
# fails-when: the remote lacks the working head, the stand-in holds no create or two, the create names another base or
# head, the run's log holds no published event of part pr with its address, branch, head and base, the local main moves,
# a second publish at one head pushes or opens anything, or a new approved head opens a second request.
prr_case open
OP_H="$(prr_head)"; OP_MAIN="$(git -C "$R" rev-parse --verify -q refs/heads/main)"; prr_approve "$OP_H"
expect_eq "OP-0 precondition: the run publish is asked of is sealed and matches its seal" "clean" "$(prr_seal)"
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
section "§BODY: the request is titled and its body is seven headings, the facts printed and the summary checked (AC-20.1, AC-20.2)"
# ============================================================
# fails-when: the body is commit subjects, a heading is missing or out of order, the title is not the project, the
# release and the plan's title, a count under Testing, Review, Known limits or Decision records differs from the
# reader's, or a summary with an empty section or a count the facts do not state is opened.
prr_put() { bash -c '. "$1/run.sh" && . "$1/proof.sh" && . "$1/line.sh" && "${@:2}"' _ "$PRR_LIB" "$1" "$P" "${@:2}"; }   # <writer> <field>=<value>…
prr_capture() {  # -> the stand-in keeps the title and the body its create is handed, in gh.title and gh.body
  mv "$HD/bin/gh" "$HD/bin/gh.real" && printf '%s\n' '#!/bin/bash' 'me="$(cd "$(dirname "$0")" && pwd -P)"; a=("$@")' \
    'for i in "${!a[@]}"; do case "${a[i]}" in --title) printf "%s\n" "${a[i+1]}" > "$me/gh.title" ;; --body) printf "%s\n" "${a[i+1]}" > "$me/gh.body" ;; esac; done' \
    'exec "$me/gh.real" "$@"' > "$HD/bin/gh" && chmod +x "$HD/bin/gh"
}
bd_part() { awk -v h="## $1" '$0 == h { on = 1; next } /^## / { on = 0 } on && /^- /' "$HD/bin/gh.body"; }   # <heading> -> its bullets
prr_case body; prr_capture
BD_H="$(prr_head)"; prr_approve "$BD_H"
for s in a b; do prr_put line_verdict_event row=regression "commit=$BD_H" "suite=$s.test.sh" result=green kind=regression; done
prr_put line_verdict_event row=regression "commit=$BD_H" suite=c.test.sh result=red kind=regression
prr_put proof_event kind=task "head=$BD_H" evidence=record/wave-x/T1.md ac=AC-1.1 rc=0
prr_put proof_event kind=review "head=$BD_H" evidence=record/wave-x/critic.md question=adversarial reader=r result=pass scope=whole
prr_put proof_finding_event ref=record/wave-x/critic.md#1 severity=S3 reach=on to=deferred title=t "stated=The cap is not measured."
mkdir -p "$R/.bionic/docs/adrs/epic-x"
printf -- '---\nwave: wave-x\nstatus: accepted\n---\n# ADR-001 — the run'"'"'s own\n' > "$R/.bionic/docs/adrs/epic-x/adr-001-own.md"
printf -- '---\nwave: wave-y\nstatus: accepted\n---\n# ADR-002 — another run'"'"'s\n' > "$R/.bionic/docs/adrs/epic-x/adr-002-other.md"
BD_G="$(bash "$PRR_READER" "$P" verdicts regression | /usr/bin/grep "|commit=$BD_H|" | /usr/bin/grep -c '|result=green|' | tr -d ' ')"
BD_RV="$(bash "$PRR_READER" "$P" reviews | /usr/bin/grep -c . | tr -d ' ')"
expect_eq "BD-0 precondition: the reader holds 2 green suites of the head's regression, one review and AC-1.1 discharged" \
  "2|1|state=discharged" "$BD_G|$BD_RV|$(bash "$PRR_READER" "$P" cell AC-1.1 | head -1)"
door_run "$R" bash "$DOOR_POKER" pr-facts; BD_FACTS="$DOOR_OUT"
expect_eq "BD-1 pr-facts exits 0 and prints the four fact sections, in order" "0|Testing|Review|Known limits|Decision records" \
  "$DOOR_RC|$(printf '%s\n' "$BD_FACTS" | sed -n 's/^## //p' | paste -sd'|' -)"
prr_publish
expect_eq "BD-2 publish exits 0, its request titled <project> <release>: <the plan's title>" \
  "0|body $DOOR_VERSION: door fixture plan (tests/lib/door.sh)" "$DOOR_RC|$(cat "$HD/bin/gh.title" 2>/dev/null)"
[ "$DOOR_RC" = 0 ] || printf '%s\n' "$DOOR_OUT" | tail -5 | sed 's/^/    | /'
expect_eq "BD-3 …its body the seven headings in order, no commit subject in it, and its tail what pr-facts printed" \
  "Summary|What changed|Upgrade notes|Testing|Review|Known limits|Decision records|0|yes" \
  "$(sed -n 's/^## //p' "$HD/bin/gh.body" | paste -sd'|' -)|$(/usr/bin/grep -c "the row's work" "$HD/bin/gh.body" | tr -d ' ')|$([ -n "$BD_FACTS" ] && [ "$(sed -n '/^## Testing$/,$p' "$HD/bin/gh.body")" = "$BD_FACTS" ] && echo yes)"
expect_eq "BD-4 …Testing names the reader's green suites of 3 and its criteria, Review its one review" \
  "yes|yes|1" "$(bd_part Testing | /usr/bin/grep -q "$BD_G of 3 suites green" && echo yes)|$(bd_part Testing | /usr/bin/grep -q '1 of 1 criteria discharged' && echo yes)|$(bd_part Review | /usr/bin/grep -c 'adversarial: pass' | tr -d ' ')"
expect_eq "BD-5 …Known limits the deferral's sentence, Decision records the run's one ADR and not another run's" \
  "- The cap is not measured.|1|0" "$(bd_part 'Known limits')|$(bd_part 'Decision records' | /usr/bin/grep -c 'ADR-001' | tr -d ' ')|$(bd_part 'Decision records' | /usr/bin/grep -c 'ADR-002' | tr -d ' ')"
# A count the facts do not state, then an empty section: each refused before the push, nothing opened.
prr_case body-wrong; BW_S="$R/.bionic/docs/record/wave-x/pr-summary.md"; prr_approve "$(prr_head)"
printf '## Summary\n\nAll 137 of 137 suites green.\n\n## What changed\n\n- x\n\n## Upgrade notes\n\nNone.\n' > "$BW_S"
prr_publish
expect_eq "BD-6 a summary stating a count the facts do not is refused, naming it: exit 2, no push, no create, no request" \
  "2|yes|main||0" "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q '137 of 137' && echo yes)|$(prr_remote_heads)|$(prr_gh_log)|$(prr_pr_events)"
printf '## Summary\n\nThe change.\n\n## What changed\n\n## Upgrade notes\n\nNone.\n' > "$BW_S"
prr_publish
expect_eq "BD-7 a summary with an empty section is refused, naming it: exit 2, no push, no create, no request" \
  "2|yes|main||0" "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q 'What changed' && echo yes)|$(prr_remote_heads)|$(prr_gh_log)|$(prr_pr_events)"

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
section "§SEEN: one reader says whether the working branch is merged, read on the remote and from the host"
# ============================================================
# fails-when: the reader answers merged while neither the working head nor the host's merge commit is on the fetched
# remote branch; answers unmerged after a merge commit or a squash the remote holds; reads a closed request as open or
# opens no ask for it; writes an ask or fetches without --fetch; or the local integration branch moves.
prr_case seen-merge
SN_MAIN="$(prr_main)"; prr_approve "$(prr_head)"; prr_publish
prr_seen --fetch
expect_eq "SN-1 the request open: unmerged (1), naming it, the branch read origin/main" "1|unmerged|origin/main|yes" \
  "$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$(printf '%s' "$DOOR_OUT" | cut -f3)|$(printf '%s' "$DOOR_OUT" | /usr/bin/grep -qF "$PRR_URL1 is open" && echo yes)"
prr_gh pr merge "$PRR_URL1" --merge; SN_TIP="$(git -C "$B" rev-parse --verify -q refs/heads/main)"
prr_seen
expect_eq "SN-2 merged on the host, nothing fetched: still unmerged, the host's merge commit not yet on origin/main" "1|unmerged|no" \
  "$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$([ "$(prr_origin)" = "$SN_TIP" ] && echo yes || echo no)"
prr_seen --fetch
expect_eq "SN-3 with --fetch the merge commit is seen: merged (0) at the remote's tip, the head reached" "0|merged|$SN_TIP|reached" \
  "$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$(printf '%s' "$DOOR_OUT" | cut -f2)|$(printf '%s' "$DOOR_OUT" | cut -f4)"
expect_eq "SN-3b …origin/main fetched to the remote's tip, and the local main where it was" "$SN_TIP|$SN_MAIN" "$(prr_origin)|$(prr_main)"

prr_case seen-squash
SN_MAIN="$(prr_main)"; SN_H="$(prr_head)"; prr_approve "$SN_H"; prr_publish
prr_gh pr merge 1 --squash; SN_TIP="$(git -C "$B" rev-parse --verify -q refs/heads/main)"
prr_seen --fetch
expect_eq "SN-4 a squash: the head is on no remote branch, and the host names its commit: merged (0) at it, by the host" \
  "no|0|merged|$SN_TIP|host $PRR_URL1" \
  "$(git -C "$R" merge-base --is-ancestor "$SN_H" "$(prr_origin)" && echo yes || echo no)|$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$(printf '%s' "$DOOR_OUT" | cut -f2)|$(printf '%s' "$DOOR_OUT" | cut -f4)"
expect_eq "SN-4b …and the local main where it was" "$SN_MAIN" "$(prr_main)"
printf 'HTTP 502: the host is down\n' > "$HD/bin/gh.fail"
prr_seen
expect_eq "SN-5 the host down over a squash: unread (2), the host's cause named" "2|unread|yes" \
  "$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$(printf '%s' "$DOOR_OUT" | /usr/bin/grep -qF 'HTTP 502: the host is down' && echo yes)"
rm -f "$HD/bin/gh.fail"
prr_code
prr_seen --fetch
expect_eq "SN-6 a working head past the request the host merged: unmerged (1), the work past it is in no merge" "1|unmerged|yes" \
  "$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$(printf '%s' "$DOOR_OUT" | /usr/bin/grep -q 'is past it' && echo yes)"

prr_case seen-close
prr_approve "$(prr_head)"; prr_publish; prr_seen --fetch; prr_gh pr close "$PRR_URL1"
prr_seen
expect_eq "SN-7 closed unmerged, read without --fetch: closed (3), and no ask written" "3|closed|" \
  "$DOOR_RC|$(printf '%s' "$DOOR_OUT" | cut -f1)|$(prr_ask pr-closed:wave:01-x)"
prr_seen --fetch
expect_eq "SN-8 …with --fetch: closed (3), an ask on the register naming the request, waiting on the person" "3|yes|user" \
  "$DOOR_RC|$(prr_ask pr-closed:wave:01-x | /usr/bin/grep -qF "$PRR_URL1" && echo yes)|$(OWED_ROOT="$R" OWED_PLAN="$P" bash -c '. "$1/owed.sh" && ask_waits_on pr-closed:wave:01-x' _ "$PRR_LIB")"
awk -F'|' -v OFS='|' '$1 == 1 { $2 = "OPEN" } { print }' "$HD/bin/gh.prs" > "$HD/bin/gh.prs.n" && mv "$HD/bin/gh.prs.n" "$HD/bin/gh.prs"
prr_seen --fetch
expect_eq "SN-9 the person reopens it: unmerged (1), and the ask is closed" "1|" "$DOOR_RC|$(prr_ask pr-closed:wave:01-x)"

prr_case seen-none
prr_seen; SN_RC="$DOOR_RC|$(printf '%s' "$DOOR_OUT" | /usr/bin/grep -q 'origin/main names no commit' && echo yes)"
prr_seen --fetch
expect_eq "SN-10 never fetched: unread (2), origin/main names no commit; with --fetch and no request, unmerged (1)" "2|yes|1|yes" \
  "$SN_RC|$DOOR_RC|$(printf '%s' "$DOOR_OUT" | /usr/bin/grep -q 'no pull request of' && echo yes)"

# ============================================================
section "§OPEN-ONLY: with the pull request open and unmerged, close-out holds and lands nothing (AC-14.3)"
# ============================================================
# fails-when: close-out's run exits 0, or the log gains a landing of the integrate row, while neither the working head
# nor the host's merge commit is on the remote's integration branch; or check reads a merge the remote does not hold, or
# misses one it does; or anything moves the local integration branch. No fetch is typed here: close-out makes its own.
# FIXTURE FIDELITY: the door fixture carried to Step 8 by its log's step events, its plan gaining the integrate row a
# planner writes (T3, step 8); the request is the publish verb's, the merge the stand-in host's.
PRR_BASE8="$(door_copy "$PRR_BASE" "$WORLD_ROOT/base8")"; PRR_BASE8="${PRR_BASE8% *}"
awk '{ print } /^\| T2 \|/ { print "| T3 | 8 | integrate | the pull request | T1, T2 | 10 | REQ-1 | — | — |" }' "$PRR_BASE8/$DOOR_PLAN_REL" > "$PRR_BASE8/p.n" \
  && mv "$PRR_BASE8/p.n" "$PRR_BASE8/$DOOR_PLAN_REL"
printf 'run/v1|ev=step|n=%s|at=2026-10-04T01:0%s:00Z\n' 5 1 6 2 7 3 8 4 >> "$PRR_BASE8/.bionic/docs/record/wave-x/run.log"
prr_case8() { local b="$PRR_BASE"; PRR_BASE="$PRR_BASE8"; prr_case "$1"; PRR_BASE="$b"; }

prr_case8 only-open
OO_MAIN="$(prr_main)"; prr_approve "$(prr_head)"; prr_publish
prr_close run
expect_eq "OO-1 the request open: close-out's run holds (exit 2), saying the working branch is not reachable from origin/main" "2|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q 'is not reachable from origin/main' && echo yes)"
expect_eq "OO-2 …the log holds no landing of the integrate row, and the local main is where it was" "0|$OO_MAIN" "$(prr_landed)|$(prr_main)"
prr_close check
expect_eq "OO-3 check says the merge would refuse, and lands nothing until the merge is seen" "yes|yes" \
  "$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q '^merge: WOULD REFUSE' && echo yes)|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q '^rows-landed: none — run lands T3 only once the merge is seen' && echo yes)"
prr_gh pr merge "$PRR_URL1" --merge; OO_TIP="$(git -C "$B" rev-parse --verify -q refs/heads/main)"
prr_close check
expect_eq "OO-4 merged by a merge commit: check reads it on origin/main after its own fetch, and would land T3 at the merge" "yes|yes" \
  "$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "^merge: wave/01-x @ [0-9a-f]* reachable from origin/main @ ${OO_TIP:0:7}" && echo yes)|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "^rows-landed: run would land T3 at origin/main @ ${OO_TIP:0:7}" && echo yes)"
expect_eq "OO-4b …the local main is where it was" "$OO_MAIN" "$(prr_main)"

prr_case8 only-squash
prr_approve "$(prr_head)"; prr_publish; prr_gh pr merge 1 --squash; OO_TIP="$(git -C "$B" rev-parse --verify -q refs/heads/main)"
prr_close check
expect_eq "OO-5 merged by a squash: check reads the host's merge commit on origin/main" "yes|yes" \
  "$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "^merge: wave/01-x @ [0-9a-f]* merged into origin/main by the pull request $PRR_URL1 as ${OO_TIP:0:7}" && echo yes)|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q "^rows-landed: run would land T3 at origin/main @ ${OO_TIP:0:7}" && echo yes)"

prr_case8 only-closed
prr_approve "$(prr_head)"; prr_publish; prr_gh pr close "$PRR_URL1"
prr_close run
expect_eq "OO-6 closed unmerged: run holds naming it, lands nothing, and the person's ask is open" "2|yes|0|yes" \
  "$DOOR_RC|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -qF "$PRR_URL1 was closed unmerged" && echo yes)|$(prr_landed)|$([ -n "$(prr_ask pr-closed:wave:01-x)" ] && echo yes)"

# ============================================================
section "§GATE: step 8's gate asks the same reader of a landing it holds"
# ============================================================
# fails-when: at Step 8 a landing of the integrate row stands for a merge the remote does not hold and the gate owes
# nothing, or it owes the merge once the remote holds it.
# FIXTURE FIDELITY: §OPEN-ONLY's Step-8 fixture, given the facts the earlier steps owe at the working head (a passing
# review of each question, the regression's proof, the walk waived) so the gate reaches Step 8's asks; the landing is
# the line close-out writes, planted at the integration tip the request was opened against, as the arm that read no
# merge used to write it. The gate is the case's own bash-walls.sh on a commit from the project, its owed lines read as
# the gate prints them.
prr_gate() {  # -> GATE_SAID: what the gate says of a commit from the case's project
  local in
  in="$(jq -n --arg s "$WORLD_SID" --arg c "$R" '{session_id: $s, cwd: $c, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git commit -m x"}}')"
  GATE_SAID="$(cd "$R" && env PATH="$RH_GHPATH" HOME="$WORLD_ROOT/gate-home" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_WALL_VERBOSE=1 bash "$R/hooks/bash-walls.sh" <<< "$in" 2>&1 >/dev/null)"
}
prr_case8 gate
prr_approve "$(prr_head)"; prr_publish; prr_seen --fetch
GA_H="$(prr_head)"; GA_REC="$R/.bionic/docs/record/wave-x"
for q in evidence adversarial structure; do
  : > "$GA_REC/$q.md"
  printf 'run/v1|ev=proof|evidence=record/wave-x/%s.md|head=%s|kind=review|question=%s|reader=r|result=pass|scope=whole|at=2026-10-04T01:30:00Z\n' "$q" "$GA_H" "$q" >> "$L"
done
printf 'whole\n' > "$GA_REC/reg.log"
printf 'run/v1|ev=%s|at=2026-10-04T01:31:00Z\n' "proof|kind=regression|head=$GA_H|evidence=record/wave-x/reg.log" 'waiver|question=walk|by=f|said=yes' >> "$L"
printf 'run/v1|ev=published|row=T3|commit=%s|kind=close|by=close-out|why=merged|at=2026-10-04T02:00:00Z\n' "$(prr_origin)" >> "$L"
seal_fixture "$P" "$L"
prr_gate
expect_eq "GA-1 a landing at origin/main's tip while the request is open: the gate owes Step 8's merge, with no merge read" "yes" \
  "$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -q "Step 8's merge: the integrate row's landing, with no merge read" && echo yes)"
prr_gh pr merge "$PRR_URL1" --merge; prr_seen --fetch
prr_gate
expect_eq "GA-2 …once origin/main holds the merge the gate owes no merge, and still owes what close-out gives the step" "|yes" \
  "$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -o "Step 8's merge" | head -1)|$(printf '%s\n' "$GATE_SAID" | /usr/bin/grep -q "owed at 15: Step 8's cleanup" && echo yes)"

# THE WATCHER'S PASS OVER A RUN WAITING ON ITS MERGE. The world is §OPEN-ONLY's Step-8 fixture as a run reaches it once
# every row has landed: the session armed on an empty roster, the request published, and what the earlier steps owe held
# at the working head (`prr_owed`), so the close itself has nothing left to refuse once the merge is there. The pass is
# the shipped `session-poker.sh tick --watch`, run from the project with the stand-in its only gh and a home of the
# world's; its codes are read from their one home, lib/patrol.sh. No fetch is typed in these sections: the pass makes it.
prr_watch_rc() { bash -c '. "$1/patrol.sh" >/dev/null 2>&1 && eval "printf %s \"\${$2:-}\""' _ "$PRR_LIB" "$1"; }
PRR_QUIET="$(prr_watch_rc WATCH_RC_QUIET)"; PRR_WAKE="$(prr_watch_rc WATCH_RC_WAKE)"; PRR_REST="$(prr_watch_rc WATCH_RC_REST)"
PRR_LINE_MAX="$(prr_watch_rc WATCH_LINE_MAX)"
prr_owed() {  # -> every fact the run owes at the working head, each a passing proof with its evidence on disk
  local rec="$R/.bionic/docs/record/wave-x" h
  h="$(prr_head)"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    facts_owed "$(plan_frontmatter_get "$2" rigor)" "$(plan_frontmatter_get "$2" scale)" "$4" \
      | while IFS="	" read -r k q role scope; do
          case "$k" in
            regression) printf "whole\n" > "$5/reg.log"; l="$(proof_line regression "$3" 2026-10-04T12:00:00Z record/wave-x/reg.log)" ;;
            review) : > "$5/$q-$scope.md"; l="$(proof_line review "$3" 2026-10-04T12:00:00Z "record/wave-x/$q-$scope.md" "$q" r pass "$scope")" ;;
            check) printf "ok\n" > "$5/check.log"; l="$(proof_line check "$3" 2026-10-04T12:00:00Z record/wave-x/check.log)" ;;
            *) echo "prr_owed: no proof planted for $k" >&2; exit 1 ;;
          esac
          f="${l#proved: }"; LOG_AT=2026-10-04T12:00:00Z proof_event "$2" ${f/ at=2026-10-04T12:00:00Z/}
        done' _ "$PRR_LIB" "$P" "$h" "$R" "$rec"
  printf 'the walk\n' > "$rec/walk.md"
  printf 'run/v1|ev=proof|%s|at=2026-10-04T12:01:00Z\n' "ac=AC-1.1|evidence=record/wave-x/walk.md|auditor=a" \
    "kind=walk|head=$h|evidence=record/wave-x/walk.md" >> "$L"
  seal_fixture "$P" "$L"
}
prr_watch_world() {  # <name> [bare] -> §OPEN-ONLY's fixture armed and published; with `bare`, nothing the steps owe
  prr_case8 "$1"
  : > "$R/.bionic/tmp/roster-$WORLD_SID.state"
  prr_approve "$(prr_head)"; prr_publish
  [ "${2:-}" = bare ] || prr_owed
}
# prr_pass [<env assignment>...] -> PASS_OUT (the pass's stdout alone), PASS_RC: one watcher pass from the case's
# project, the assignments in its environment
prr_pass() {
  door_run "$R" env PATH="$RH_GHPATH" HOME="$WORLD_ROOT/$(basename "$R")-home" BIONIC_CLAUDE_HOME="$WORLD_ROOT/$(basename "$R")-home/.claude" "$@" \
    bash -c 'bash "$1" tick --watch 2>/dev/null; echo "rc=$?"' _ "$DOOR_POKER"
  PASS_RC="$(printf '%s\n' "$DOOR_OUT" | sed -n '$s/^rc=//p')"; PASS_OUT="$(printf '%s\n' "$DOOR_OUT" | sed '$d')"
}
prr_side() {  # <name> -> one commit of someone else's on the bare remote's main, pushed from a clone of its own
  local c="$WORLD_ROOT/side-$1"
  git clone --quiet "$B" "$c" && printf '%s\n' "$1" > "$c/side-$1.txt" && git -C "$c" add -A \
    && git -C "$c" -c user.name=side -c user.email=side@example.invalid commit --quiet -m "someone else's change" \
    && git -C "$c" push --quiet origin HEAD:main
}
prr_bare_main() { git -C "$B" rev-parse --verify -q refs/heads/main; }
# prr_log_step -> the reader's step answer over the run's log alone, `n=<step> state=<state>`: the close moves the plan
# into the archive
prr_log_step() {
  bash -c '. "$1/reader.sh" || exit 9; f="$(cat "$2")"; reader_facts() { printf "%s\n" "$f"; }; reader_q_step - | /usr/bin/grep -E "^(n|state)=" | paste -sd" " -' \
    _ "$PRR_LIB" "$L" 2>/dev/null
}
prr_close_out() { cat "$R/.bionic/tmp/close-${WORLD_SID:0:8}.out" 2>/dev/null; }

# ============================================================
section "§WAIT: while the pull request is open each pass fetches and stays quiet, and the merge wakes it (AC-10.5)"
# ============================================================
# fails-when: a pass wakes or rests while the request is open and unmerged; a pass makes no fetch, so origin/main stays
# behind the remote; the pass after the merge stays quiet; a request closed unmerged keeps the watch passing instead of
# resting on the person's ask; or a pass fetches while the request is closed.
prr_watch_world wait
WT_MAIN="$(prr_main)"
expect_eq "WT-0 precondition: the request open on the stand-in, origin/main never fetched, the run at step 8" "OPEN -||n=8 state=open" \
  "$(door_run "$R" env PATH="$RH_GHPATH" gh pr view "$PRR_URL1" --json state,mergeCommit --jq '.state + " " + (.mergeCommit.oid // "-")'; printf '%s' "$DOOR_OUT")|$(prr_origin)|$(prr_log_step)"
prr_pass
expect_eq "WT-1 the request open: the pass is quiet and prints nothing" "$PRR_QUIET|" "$PASS_RC|$PASS_OUT"
expect_eq "WT-1b …it fetched: origin/main is the remote's main, and the local main where it was" "$(prr_bare_main)|$WT_MAIN" "$(prr_origin)|$(prr_main)"
prr_side wait
prr_pass
expect_eq "WT-2 someone else's change on the remote's main, the request still open: the next pass is quiet too" "$PRR_QUIET|" "$PASS_RC|$PASS_OUT"
expect_eq "WT-2b …and it fetched again: origin/main follows the remote's main" "$(prr_bare_main)" "$(prr_origin)"
expect_eq "WT-3 …nothing is landed, and the run is still at step 8" "0|n=8 state=open" "$(prr_landed)|$(prr_log_step)"
# The watcher itself, hooks/watch.sh, as the platform starts it, its day cut to a second: the request is still out.
door_run "$R" env PATH="$RH_GHPATH" HOME="$WORLD_ROOT/wait-home" BIONIC_CLAUDE_HOME="$WORLD_ROOT/wait-home/.claude" BIONIC_WATCH_DEADLINE=1 \
  bash -c 'printf "{\"session_id\":\"%s\",\"cwd\":\"%s\",\"hook_event_name\":\"Stop\"}" "$2" "$3" | bash "$1" 2>&1 >/dev/null; echo "rc=$?"' \
  _ "$BIONIC_SCRIPTS_DIR/hooks/watch.sh" "$WORLD_SID" "$R"
expect_eq "WT-3c the watcher's day ends with nothing on the roster and the request open: it wakes once to be renewed" "rc=$PRR_WAKE|yes" \
  "$(printf '%s\n' "$DOOR_OUT" | tail -1)|$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -q '^bionic watch: RENEW - .*pull request open' && echo yes)"
prr_gh pr merge "$PRR_URL1" --merge
prr_pass
expect_eq "WT-4 merged by a merge commit: the next pass wakes, with one line" "$PRR_WAKE|1" "$PASS_RC|$(printf '%s\n' "$PASS_OUT" | awk 'END { print NR }')"
expect_regex "WT-4b …the line is the watcher's, naming the delivered run" '^bionic watch: DELIVERED - ' "$PASS_OUT"
expect_eq "WT-4c …within the line's ceiling" "yes" "$([ "${#PASS_OUT}" -le "$PRR_LINE_MAX" ] && echo yes)"

prr_watch_world wait-closed
prr_gh pr close "$PRR_URL1"
prr_pass
expect_eq "WT-5 the request closed unmerged: the pass that reads it is quiet, and opens the person's ask" "$PRR_QUIET||yes" \
  "$PASS_RC|$PASS_OUT|$([ -n "$(prr_ask pr-closed:wave:01-x)" ] && echo yes)"
WT_SEEN="$(prr_origin)"
prr_side wait-closed
prr_pass
expect_eq "WT-6 …the next pass rests: the run waits only on the person, who rules on the closed request" "$PRR_REST|" "$PASS_RC|$PASS_OUT"
expect_eq "WT-6b …and makes no fetch: origin/main stays where the last look left it, behind the remote's main" "$WT_SEEN|no" \
  "$(prr_origin)|$([ "$(prr_origin)" = "$(prr_bare_main)" ] && echo yes || echo no)"

# ============================================================
section "§MERGE: the pass that sees the merge lands the integrate row and the run reads delivered (AC-14.2)"
# ============================================================
# fails-when: after the stand-in merges into the bare remote, the next pass leaves the integrate row unlanded or the run
# at step 8; lands it at a commit the remote's main does not hold; moves the local main; leaves close-out's account
# unwritten; or, with the close held, wakes on every pass over the same hold.
prr_watch_world merge
MG_MAIN="$(prr_main)"
prr_pass
expect_eq "MG-0 precondition: the request open, the pass quiet, nothing landed" "$PRR_QUIET|0" "$PASS_RC|$(prr_landed)"
prr_gh pr merge 1 --squash; MG_TIP="$(prr_bare_main)"
prr_pass
expect_eq "MG-1 merged by a squash: the next pass wakes, naming the delivered run" "$PRR_WAKE|yes" \
  "$PASS_RC|$(printf '%s\n' "$PASS_OUT" | /usr/bin/grep -q '^bionic watch: DELIVERED - ' && echo yes)"
expect_contains "MG-2 …the log holds the integrate row's landing as merged, at the host's merge commit" \
  "|ev=published|row=T3|commit=$MG_TIP|kind=close|by=close-out|why=merged|" "$(cat "$L")"
expect_eq "MG-3 …and the run reads delivered" "n=9 state=delivered" "$(prr_log_step)"
expect_eq "MG-4 …origin/main is the remote's main, the local main where it was" "$MG_TIP|$MG_MAIN" "$(prr_origin)|$(prr_main)"
expect_eq "MG-5 …the line names the account close-out wrote, which says the run was delivered" "yes|yes" \
  "$(printf '%s\n' "$PASS_OUT" | /usr/bin/grep -qF ".bionic/tmp/close-${WORLD_SID:0:8}.out" && echo yes)|$(prr_close_out | /usr/bin/grep -q '^step9: delivered: ' && echo yes)"

prr_watch_world merge-held bare
prr_gh pr merge "$PRR_URL1" --merge
# The machine read as full for this pass, as it was each time a world's regression run was found outliving the
# suite: the whole run this world's tick starts detached waits at the gate for room, and §STRAY meets it there.
prr_pass BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192 BIONIC_PROBE_USED_PCT=99 BIONIC_PROBE_FREE_PCT=1 BIONIC_PROBE_FREE_MB=81 \
  BIONIC_PROBE_BUSY_CORES=64 BIONIC_PROBE_BUSY_CORES_5M=64 BIONIC_PROBE_LOAD_1M=64 BIONIC_PROBE_SWAP_PCT=0
expect_eq "MG-6 merged with the close's facts not held: the pass wakes, saying close-out held" "$PRR_WAKE|yes" \
  "$PASS_RC|$(printf '%s\n' "$PASS_OUT" | /usr/bin/grep -q '^bionic watch: MERGED - close-out held (exit [0-9]*): ' && echo yes)"
expect_eq "MG-6b …nothing landed, the run still at step 8, close-out's refusal in its account" "0|n=8 state=open|yes" \
  "$(prr_landed)|$(prr_log_step)|$(prr_close_out | /usr/bin/grep -q 'close-out refused' && echo yes)"
prr_pass
expect_eq "MG-7 …the next pass over the same hold is quiet: the hold was told once" "$PRR_QUIET|" "$PASS_RC|$PASS_OUT"

# ============================================================
section "§MERGE-LOOK: a pass over an unchanged run with the request open asks the host alone, and the merge is still read (AC-5.2)"
# ============================================================
# fails-when: the pass after the host merges the request reads the run as open; the pass over an unchanged run runs the
# tick again (the gate's judging passes are counted: none); a pass over an unchanged run makes no fetch, so the merge
# is not reached; an input the tick reads moves and the pass does not run the tick (a denied request is not told); or
# the request closed unmerged is not told to the person, and the pass after it does not rest; or, with a writer out on
# the roster, a pass over an unchanged run runs no tick, so what the tick's clock reads of the row is never read.
# The watcher names the file its passes keep what they read in (BIONIC_WATCH_LOOK); the first passes settle it, as the
# fetch of the first moves origin/main, which the tick reads.
prr_look_pass() {  # <world file stem> <n> -> PASS_OUT PASS_RC, and the pass's counts in <stem>.count.<n>
  : > "$WORLD_ROOT/$1.count.$2"
  prr_pass BIONIC_WATCH_LOOK="$WORLD_ROOT/$1.look" BIONIC_COUNT="$WORLD_ROOT/$1.count.$2"
}
prr_look_n() { awk -v k="$3" '$1 == k { n++ } END { print n + 0 }' "$WORLD_ROOT/$1.count.$2"; }   # <stem> <n> <kind>
prr_look_warm() {  # <stem> -> two passes over the world, the look file made first, each quiet
  : > "$WORLD_ROOT/$1.look"
  prr_look_pass "$1" 1; LK_R1="$PASS_RC"; prr_look_pass "$1" 2; LK_R2="$PASS_RC"
}
prr_watch_world lookmerge
prr_look_warm lookmerge
expect_eq "LK-0 precondition: two passes over the open request are quiet, and the tick judged in each (gate counted)" \
  "$PRR_QUIET $PRR_QUIET|yes" "$LK_R1 $LK_R2|$([ "$(prr_look_n lookmerge 1 gate)" -gt 0 ] && [ "$(prr_look_n lookmerge 2 gate)" -gt 0 ] && echo yes)"
LK_FETCH="$(prr_origin)"
rm -f "$R/.git/FETCH_HEAD"
prr_look_pass lookmerge 3
expect_eq "LK-1 the third pass over the unchanged run is quiet and prints nothing" "$PRR_QUIET|" "$PASS_RC|$PASS_OUT"
expect_eq "LK-1b …runs no tick: nothing judged, no status pass, no facts answer" "0 0 0" \
  "$(prr_look_n lookmerge 3 gate) $(prr_look_n lookmerge 3 status) $(prr_look_n lookmerge 3 facts)"
expect_eq "LK-1c …and still asks the host: the integration branch fetched, origin/main where it was" "yes|$LK_FETCH" \
  "$([ -f "$R/.git/FETCH_HEAD" ] && echo yes)|$(prr_origin)"
prr_gh pr merge 1 --squash; LK_TIP="$(prr_bare_main)"
prr_look_pass lookmerge 4
expect_eq "LK-2 merged on the host: the very next pass wakes, naming the delivered run" "$PRR_WAKE|yes" \
  "$PASS_RC|$(printf '%s\n' "$PASS_OUT" | /usr/bin/grep -q '^bionic watch: DELIVERED - ' && echo yes)"
expect_contains "LK-2b …the log holds the integrate row's landing as merged, at the host's merge commit" \
  "|ev=published|row=T3|commit=$LK_TIP|kind=close|by=close-out|why=merged|" "$(cat "$L")"
expect_eq "LK-2c …and the run reads delivered" "n=9 state=delivered" "$(prr_log_step)"

# AN INPUT THE TICK READS MOVES: the pass runs the tick, and a wake it owes is told.
prr_watch_world lookgate
prr_look_warm lookgate
prr_look_pass lookgate 3
expect_eq "LK-3 precondition: the third pass over the unchanged run judges nothing" "$PRR_QUIET|0" "$PASS_RC|$(prr_look_n lookgate 3 gate)"
printf 'gate/v1|at=2026-10-11T00:00:00Z|session=%s|asker=w99-T9|category=leaves-the-machine|head=git push origin wave/99-p\n' \
  "$WORLD_SID" >> "$R/.bionic/tmp/gate-$WORLD_SID.state"
prr_look_pass lookgate 4
expect_eq "LK-4 a request denied since the last pass: the pass runs the tick, and wakes with the gate's line" "$PRR_WAKE|yes|yes" \
  "$PASS_RC|$(printf '%s\n' "$PASS_OUT" | /usr/bin/grep -q '^bionic watch: GATE ' && echo yes)|$([ "$(prr_look_n lookgate 4 gate)" -gt 0 ] && echo yes)"

# A REQUEST CLOSED UNMERGED: the pass that reads it tells the person, and the pass after it rests with no fetch.
prr_watch_world lookclosed
prr_look_warm lookclosed
prr_gh pr close "$PRR_URL1"
prr_look_pass lookclosed 3
expect_eq "LK-5 the request closed on the host: the pass over the unchanged run is quiet, and opens the person's ask" "$PRR_QUIET||yes" \
  "$PASS_RC|$PASS_OUT|$([ -n "$(prr_ask pr-closed:wave:01-x)" ] && echo yes)"
LK_SEEN="$(prr_origin)"
prr_side lookclosed
prr_look_pass lookclosed 4
expect_eq "LK-6 …the next pass rests, the run waiting only on the person, and makes no fetch" "$PRR_REST|$LK_SEEN" "$PASS_RC|$(prr_origin)"

# A WRITER OUT: the tick reads its row against the clock (quiet past its cadence, past its duration, gone), which no file
# moving says, so with a row on the roster every pass runs the tick, the request open and nothing else moving.
prr_watch_world lookrow
LK_AT="$(t=$(( $(date +%s) - 60 )); date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ)"
roster_row_fixture session="$WORLD_SID" name=busy agent_id=abusy-1111111111111111 launched_at="$LK_AT" duration="4 hours" \
  deliverable="$R/never-written.md" >> "$R/.bionic/tmp/roster-$WORLD_SID.state"
prr_look_warm lookrow
prr_look_pass lookrow 3
expect_eq "LK-7 a writer out on the roster: three quiet passes over the unchanged run, and the third still judges (its tick ran)" \
  "$PRR_QUIET $PRR_QUIET $PRR_QUIET|yes" "$LK_R1 $LK_R2 $PASS_RC|$([ "$(prr_look_n lookrow 3 gate)" -gt 0 ] && echo yes)"

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

# ============================================================
section "§STRAY: nothing a world of this suite started outlives the suite"
# ============================================================
# fails-when: a regression run a world's tick started detached (§MERGE's merge-held world) is still alive when the
# suite ends, waiting on a gate whose world is about to go.
# A stand-in named as a world's regression run, so the reading is proved to see one before it is trusted to see none.
bash -c 'while :; do sleep 1; done' regression-run "$WORLD_ROOT/stand-in" &
SR_PID=$!
expect_eq "SR-0 precondition: the reading names a live process of a world's regression run" "yes" \
  "$(prr_strays | /usr/bin/grep -qx "$SR_PID" && echo yes)"
kill "$SR_PID" 2>/dev/null; wait "$SR_PID" 2>/dev/null
prr_reap
expect_eq "SR-1 at the suite's end no regression run started by a world of this suite is alive" "" \
  "$(prr_strays | paste -sd' ' -)"

finish
