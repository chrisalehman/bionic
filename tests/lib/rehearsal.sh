# tests/lib/rehearsal.sh — the rehearsal: a small run played forward in a sandbox through the commands a real run
# uses, until it holds one of the four states the sitrep card is read in.
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR names the tree under test
#     . "$(dirname "$0")/lib/rehearsal.sh"          # sources tests/lib/door.sh, and with it tests/lib/world.sh
#     plan="$(rehearse <state> "$WORLD_ROOT/<name>")"
#
#     bash tests/lib/rehearsal.sh <state> <dir>     # the same into <dir>/<state>, from the command line; kept
#
# THE INTERFACE:
#
#   rehearse <state> <dir>   builds the sandbox under <dir> (absent or empty), plays it to <state> and prints the
#                            sandbox plan's path. The sandbox is <dir>/project, its session's config directory
#                            <dir>/config, and every command it ran is logged, with its exit, its seconds and its
#                            output, in <dir>/rehearsal.log, beside a `# by hand:` line for each file written by
#                            hand. A command that fails stops the rehearsal: its line and output go to stderr, rc 1,
#                            and nothing is printed on stdout. A state the library does not know is rc 2.
#
#   The states:
#     delivered        the failed-review run, its project declaring its real release check, carried through the
#                      verbs to close-out's delivered: (rehearse prints the archived plan's path): the sweeper acks
#                      the failing reviewer, a fix row born of the review's finding is added, cut, launched and
#                      landed through ready, the release check runs at its head, the release approval card is
#                      rendered there and the user's reply approves it, the integrate row opens the pull request
#                      through gh, the person merges it, the integrate row delivers its record, and close-out runs.
#     failed-review    the release-waiting run, then the user's reply "all recommended", Step 8, a whole structure
#                      review registered failing, the working branch merged into main as the pull request lands
#                      it, and close-out refused on the failing review: the register holds waive:structure and
#                      hold:merge.
#     release-waiting  the release order (the release row at step 7, a regression row, an integrate row reading both
#                      approvals), the build landed, the matrix discharged, Steps 5 to 7 with the regression, its row
#                      delivered, five passing reviews and the release check, the release landed, and the release
#                      approval card rendered: the register holds approve:release and approve:merge.
#     stop-rule        the build row landed; the release row reads the approval of a stop-rule decision, which
#                      is put through `decisions put`: the register holds that decision's decide: ask.
#     clean            the build row landed and the release row is still active: the register holds no open ask.
#
# THE SANDBOX is tests/lib/door.sh's `door_world`: a real repository carrying the plugin's hooks and scripts and a
# plan in its Step-3 shape, bound to WORLD_SID. Each command runs from the sandbox's root through `door_run`, and the
# poker, close-out, the sweeper and the door are the sandbox's own copies, so a kept sandbox is read by the same
# plugin that played it. The plugin's context files are laid beside its scripts, as an install lays them out.
#
# WHAT IS WRITTEN BY HAND is what a run's people and agents write by hand, and each `# by hand:` line names its
# kind first, one of RH_HAND_KINDS:
#   [prose]   the person's words: the plan's Step-3 prose and goals, its Step-3 approval line, stamped when the
#             rehearsal starts, and the project's config
#   [record]  a record an agent writes: a review's, a criterion's evidence, the walk and the audit, a row's report,
#             the records two of the goals are measured by, the document Step 7 names
#   [code]    a row's code and its suite, and the release's changelog entry
#   [typed]   the user's typed words in the session's transcript, with the session's start record: the CLI and
#             session-start write those two in a real session
#   [launch]  a launched agent's roster row, through the roster's production writer (below)
# A register, a ledger line a verb owns, a proof line, a step line, an approval or a landing record is never written
# here: each comes from its command.
#
# THE ROSTER ROW of each reviewer is written through the roster's production writer (`roster_row`, by
# tests/lib/roster-row.sh), as the dispatch wall writes it when the reviewer is launched; the sweeper's own `ack`
# closes it.
#
# A STAND-IN `gh` (delivered alone). The pull request is an outward act, so the integrate row's `gh` is a stand-in
# put first on the PATH of the commands that call it, every directory holding another `gh` left off that PATH: it
# appends each call's arguments to <dir>/bin/gh.log, answers `pr create` with a placeholder address, and for `pr
# merge` moves the pull request's base to its head, as the hosting service's merge and the person's pull bring it
# home; the sandbox has no remote to merge on.
#
# FROM THE COMMAND LINE nothing is removed: <dir> keeps the sandbox, its gate store, its config and the log. <dir>
# must lie outside the plugin tree that runs it, because `door_run` strips that tree's paths from every command's
# environment. Read a kept sandbox as its session: from <dir>/<state>/project, with CLAUDE_CODE_SESSION_ID set to
# 11111111-2222-4333-8444-555555555555 (WORLD_SID), BIONIC_GATE_DIR to <dir>/gate and CLAUDE_CONFIG_DIR to
# <dir>/<state>/config.
#
# bash 3.2 (ADR-001).

if [ -z "${BIONIC_SCRIPTS_DIR:-}" ]; then
  BIONIC_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
  export BIONIC_SCRIPTS_DIR
fi
if ! type -t roster_row_fixture >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "${BIONIC_SCRIPTS_DIR}/tests/lib/roster-row.sh" || return 1 2>/dev/null || exit 1
fi

# The kinds of hand write, each what a person, an agent or the harness writes in a real run (above).
RH_HAND_KINDS="prose record code typed launch"
# The verbs whose refusals the replay follows: a refusal of a verb that writes the plan's cells names the one of
# these that writes the cell, and the replay calls it on that cell and then the refused call again.
RH_FOLLOW_VERBS="deliver amend task-set step-field"

# The run's three goals, as the plan's goals: line declares them: met, not met and not measured yet in every state.
RH_GOALS="shown · the person says from the card what they owe (record/wave-x/goal-shown.md) ; asks · every ask on the register is on the card (record/wave-x/goal-asks.md) ; walked · the walk finds nothing to fix (record/wave-x/goal-walked.md)"

# rh_state_known <state> -> 0 for one of the five
rh_state_known() {
  case "${1:-}" in delivered|failed-review|release-waiting|stop-rule|clean) return 0 ;; esac
  return 1
}

# _rh_do <label> <cmd> [args] -> runs <cmd> from the sandbox root as the bound session, logging the label, the
# command, its exit and its output; a non-zero exit is reported on stderr and returned.
_rh_do() {
  local label="$1" t0="$SECONDS"
  shift
  door_run "${RH_CWD:-$RH_ROOT}" "$@"
  { printf '$'; printf ' %q' "$@"; printf '\n'; printf '%s\n' "$DOOR_OUT" | sed 's/^/  | /'; printf '  rc=%s  (%s, %s s)\n' "$DOOR_RC" "$label" "$((SECONDS - t0))"; } >> "$RH_LOG"
  [ "$DOOR_RC" = 0 ] && return 0
  printf 'rehearse %s: %s failed (rc %s): %s\n' "$RH_STATE" "$label" "$DOOR_RC" "$*" >&2
  printf '%s\n' "$DOOR_OUT" | sed 's/^/  | /' >&2
  return 1
}
_rh_poker() { local l="$1"; shift; _rh_do "$l" bash "$RH_ROOT/hooks/session-poker.sh" "$@"; }   # <label> <verb> [args]
# _rh_refused <label> <cmd> [args] -> _rh_do's run of a command the state needs refused: 0 when it exits non-zero
_rh_refused() {
  local label="$1"
  shift
  ! _rh_do "$label" "$@" 2>/dev/null && return 0
  printf 'rehearse %s: %s was to be refused and exited 0: %s\n' "$RH_STATE" "$label" "$*" >&2
  return 1
}
_rh_hand() { printf '# by hand: [%s] %s\n' "$1" "$2" >> "$RH_LOG"; }   # <kind> <what a person or an agent wrote>
_rh_head() { git -C "$RH_ROOT" rev-parse --verify -q refs/heads/wave/x; }
_rh_commit() { git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" commit --quiet -m "$2"; }   # <tree> <message>

# _rh_typed <words> -> the session's transcript holds <words> as a prompt the user typed, under the rehearsal's own
# config directory, and the session's start record names this root: the two witnesses a verb holding words to what
# the user typed asks (lib/said.sh). The CLI writes the one and session-start the other; the rehearsal stands in for
# both, in their shapes (tests/fixtures/transcript-move).
_rh_typed() {
  local proj fx="$BIONIC_SCRIPTS_DIR/tests/fixtures/transcript-move"
  proj="$CLAUDE_CONFIG_DIR/projects/$(bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ \
    "$RH_ROOT/payload/scripts/lib" "$RH_ROOT")" || return 1
  mkdir -p "$proj" || return 1
  [ -s "$proj/$WORLD_SID.jsonl" ] || cat "$fx/frame.jsonl" > "$proj/$WORLD_SID.jsonl" || return 1
  jq -c --arg t "$1" --arg s "$WORLD_SID" '.message.content = $t | .sessionId = $s' "$fx/typed.jsonl" \
    >> "$proj/$WORLD_SID.jsonl" || return 1
  [ -f "$RH_ROOT/.bionic/tmp/loaded-$WORLD_SID.state" ] \
    || printf 'root=%s\nstarted=2026-10-01T00:00:00Z\ncwd=%s\n' "$RH_ROOT/hooks" "$RH_ROOT" \
      > "$RH_ROOT/.bionic/tmp/loaded-$WORLD_SID.state" || return 1
  _rh_hand typed "the user typed '$1' (the session's transcript, and its start record)"
}

# _rh_land <row> -> the row's tree landed by hand through the sandbox's door
_rh_land() {
  _rh_do "land $1" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" land "$RH_ROOT/.worktrees/$1" --by-hand \
    --reason "the rehearsal lands $1 by hand"
}

# _rh_build -> the build row written in its tree, with a one-row suite, and landed
_rh_build() {
  local t
  t="$(door_piece "$RH_ROOT" T1)" || { echo "rehearse $RH_STATE: door_piece T1 failed" >&2; return 1; }
  printf 'rehearsal_landed() { :; }\n' >> "$t/payload/scripts/lib/said.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\nsection "the rehearsal holds"\nexpect_eq "one is one" 1 1\nfinish\n' \
    > "$t/tests/rehearsal-row.test.sh"
  _rh_commit "$t" "a library change and its suite" || return 1
  _rh_hand code "T1's code and its suite, committed in .worktrees/T1"
  _rh_land T1
}

# _rh_review <name> <question> <scope> <a> <b> <pass|fail> -> the reviewer's record and roster row
_rh_review() {
  local nm="$1" q="$2" sc="$3" res="$6" t=bionic:critic n=0
  [ "$q" != evidence ] || t=bionic:auditor
  [ "$res" = pass ] || n=1
  { printf 'reviewed: %s..%s\nquestion: %s\nresult: %s\nscope: %s\n' "$4" "$5" "$q" "$res" "$sc"
    [ "$q" != structure ] || awk -v r="$res" '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s)
      print "check: " s " " (r == "pass" ? "PASS" : "FAIL") " the build row is one line of a library and a one-row suite" }' \
      "$RH_ROOT/payload/context/checks-structure.md"
    printf '\nfindings: %s\n' "$n"
    # A finding the severity scale sends to fix names its site at the reviewed head and how it was shown, as a
    # reviewer is pushed to write it: without both the record's findings do not parse, and no row can be born of one.
    [ "$n" = 0 ] || printf 'finding: 1 S1 off payload/scripts/lib/said.sh:%s the library change is not reached by any caller\nshown: 1 grep -rn rehearsal_landed payload/scripts hooks\n' \
      "$(git -C "$RH_ROOT" show "$5:payload/scripts/lib/said.sh" 2>/dev/null | /usr/bin/grep -n '^rehearsal_landed()' | cut -d: -f1)"
    printf '\nThe review read the rows and found %s.\n' "$([ "$n" = 0 ] && echo nothing || echo one finding)"; } > "$RH_REC/$nm.md"
  printf '%s|questions=%s\n' "$(roster_row_fixture session="$WORLD_SID" name="$nm" agent_id="a-$nm" subagent_type="$t" \
    launched_at=2026-10-01T00:00:00Z deliverable="$RH_REC/$nm.md")" "$q" >> "$RH_ROOT/.bionic/tmp/roster-$WORLD_SID.state"
  _rh_hand record "the review record record/wave-x/$nm.md"; _rh_hand launch "$nm's roster row (roster_row)"
  _rh_poker "proof-add $nm" proof-add review "record/wave-x/$nm.md" --question "$q" --reader "$nm"
}

# _rh_release_card -> the release row's run carried to the release approval card: the release order, the build, the
# matrix, Steps 5 to 7 with the regression, the five reviews and the release check, the release landed, the card
_rh_release_card() {
  local h1 qs t2
  _rh_poker "move the release row to step 7" task-set T2 step=7 --reason 'the release is the doc row at step 7' || return 1
  _rh_poker "add the regression row" task-add T3 5 test 'the regression' orchestrator — 10 REQ-1 — || return 1
  _rh_poker "add the integrate row" task-add T4 8 integrate 'merge into main' orchestrator — 10 REQ-1 — \
    'approval:release, approval:merge, head' || return 1
  _rh_build || return 1
  printf 'the library change holds\n' > "$RH_REC/ac-1.1.md"; _rh_hand record "the criterion's evidence record/wave-x/ac-1.1.md"
  _rh_poker "render the matrix" matrix-render || return 1
  _rh_poker "discharge the row" matrix-set AC-1.1 status=discharged evidence=record/wave-x/ac-1.1.md task=T1 || return 1
  _rh_poker "the auditor cell" discharge AC-1.1 || return 1
  printf 'the walk the build row needed\n' > "$RH_REC/walk.md"
  printf 'CONFIRMED: the one criterion is proved\n' > "$RH_REC/audit.md"
  _rh_hand record "the walk record/wave-x/walk.md and the audit record/wave-x/audit.md"
  _rh_poker "Step 5's line" step-line 5 'regression at record/wave-x/regression-run.log' || return 1
  _rh_poker "Step 5's walk" step-field 5 walk-artifact=record/wave-x/walk.md || return 1
  _rh_poker "Step 5's auditor" step-field 5 'auditor=CONFIRMED, record/wave-x/audit.md' || return 1
  _rh_poker "enter Step 5" current 5 || return 1
  h1="$(_rh_head)"
  _rh_poker "run the regression" regression-run || return 1
  _rh_poker "record the regression" proof-add regression "record/wave-x/regression-run-$h1.log" || return 1
  printf '# T3: the regression\n\nThe whole run at %s exited 0: record/wave-x/regression-run-%s.log.\n' "$h1" "$h1" > "$RH_REC/T3.md"
  _rh_hand record "the regression row's report record/wave-x/T3.md"
  _rh_poker "the regression row lands itself" deliver T3 || return 1
  for qs in evidence:piece adversarial:piece structure:piece adversarial:whole structure:whole; do
    _rh_review "w-${qs%%:*}-${qs#*:}" "${qs%%:*}" "${qs#*:}" "$RH_BASE" "$h1" pass || return 1
  done
  _rh_do "the sweeper acks the five reviewers" bash "$RH_ROOT/hooks/session-sweeper.sh" ack \
    w-evidence-piece w-adversarial-piece w-structure-piece w-adversarial-whole w-structure-whole || return 1
  _rh_poker "Step 6's line" step-line 6 'review at record/wave-x/w-evidence-piece.md' || return 1
  _rh_poker "enter Step 6" current 6 || return 1
  _rh_poker "the release check at the build head" release-check || return 1
  printf 'no decision this run\n' > "$RH_REC/adr.md"; _rh_hand record "the document record/wave-x/adr.md"
  _rh_poker "Step 7's line" step-line 7 'documented at record/wave-x/adr.md' || return 1
  _rh_poker "Step 7's document" step-field 7 adr=record/wave-x/adr.md || return 1
  _rh_poker "enter Step 7" current 7 || return 1
  t2="$(door_piece "$RH_ROOT" T2)" && door_release "$RH_ROOT" "$t2" >/dev/null \
    || { echo "rehearse $RH_STATE: the release commit in .worktrees/T2 failed" >&2; return 1; }
  _rh_hand code "the release $DOOR_VERSION: its changelog entry (release-note's numbers) and plugin.json, committed in .worktrees/T2"
  _rh_land T2 || return 1
  _rh_poker "the release check at the release head" release-check || return 1
  _rh_poker "the release approval card" release-approval "$RH_PLAN"
}

# _rh_launch <name> <row> <suite> -> the writer's roster row, as the dispatch wall writes it when the writer is launched
# on <row> with its brief's Lands-on suite
_rh_launch() {
  roster_row_fixture session="$WORLD_SID" name="$1" agent_id="a-$1" subagent_type=bionic:senior-implementor \
    launched_at=2026-10-01T00:00:00Z deliverable="$RH_REC/$2.md" plan="$RH_PLAN" row="$2" lands_on="$3" \
    >> "$RH_ROOT/.bionic/tmp/roster-$WORLD_SID.state" || return 1
  _rh_hand launch "$1's roster row on $2, landing on $3 (roster_row)"
}

# _rh_follow <label> <row> <record> <cmd> [args] -> <cmd> run; refused, the refusal's first named verb of
# RH_FOLLOW_VERBS is read, a `# refused:` line names it, the cell it names on <row> is written with <record> (a path
# under the docs root) through that verb, and <cmd> is run again. A refusal naming no such verb, or a cell the replay
# holds no value for, stops the rehearsal.
_rh_follow() {
  local label="$1" row="$2" rec="$3" said v key val
  shift 3
  _rh_do "$label" "$@" 2>/dev/null && return 0
  said="$DOOR_OUT"
  v="$(printf '%s\n' "$said" | /usr/bin/grep -oE 'session-poker\.sh [a-z][a-z-]*' | awk -v set=" $RH_FOLLOW_VERBS " \
    '{ w = $2; if (index(set, " " w " ")) { print w; exit } }')"
  printf '# refused: %s · names: %s\n' "$label" "${v:-none}" >> "$RH_LOG"
  case "$v" in
    task-set)
      key="$(printf '%s\n' "$said" | /usr/bin/grep -oE "task-set $row [A-Za-z-]+=" | head -1)"; key="${key##* }"; key="${key%=}"
      case "$key" in
        Files) val=".bionic/docs/$rec" ;;
        artifact) val="$rec" ;;
        *) printf 'rehearse %s: %s refused naming task-set %s %s=, a cell the replay holds no value for\n' "$RH_STATE" "$label" "$row" "${key:-<none>}" >&2
           return 1 ;;
      esac
      _rh_poker "follow: task-set $row $key" task-set "$row" "$key=$val" --reason "the cell the refusal named" || return 1 ;;
    *)
      printf 'rehearse %s: %s refused naming %s, no verb that writes the cell:\n' "$RH_STATE" "$label" "${v:-none of $RH_FOLLOW_VERBS}" >&2
      printf '%s\n' "$said" | sed 's/^/  | /' >&2
      return 1 ;;
  esac
  _rh_do "$label, again" "$@"
}

# _rh_gh <dir> -> the stand-in gh in <dir>/bin, and RH_GHPATH: that directory, then every PATH entry holding no gh
_rh_gh() {
  local p d
  mkdir -p "$1/bin" || return 1
  cat > "$1/bin/gh" <<'GH'
#!/bin/bash
# A stand-in for gh: each call's arguments go to gh.log beside it. `pr create` prints a placeholder address; `pr
# merge` moves the created pull request's base to its head in the repository it is run from.
printf '%s\n' "$*" >> "$(dirname "$0")/gh.log"
case "${1:-} ${2:-}" in
  "pr create") echo "https://example.invalid/pull/1" ;;
  "pr merge")
    l="$(/usr/bin/grep '^pr create ' "$(dirname "$0")/gh.log" | tail -1)"
    b="${l#* --base }"; b="${b%% *}"; h="${l#* --head }"; h="${h%% *}"
    git fetch --quiet . "refs/heads/$h:refs/heads/$b" || exit 1
    echo "merged $h into $b" ;;
esac
GH
  chmod +x "$1/bin/gh" || return 1
  RH_GHPATH="$1/bin"
  # The tree under test's own directories are left off too, as door_run leaves them off every command's PATH.
  for d in $(printf '%s\n' "$PATH" | tr ':' ' '); do
    case "$d" in "$BIONIC_SCRIPTS_DIR"*) continue ;; esac
    [ -x "$d/gh" ] || RH_GHPATH="$RH_GHPATH:$d"
  done
}

# _rh_replay <dir> -> the failed-review run carried through the verbs to delivered:; RH_PLAN then names the plan
# close-out archived. Every command it runs follows the `# replay:` line in the log.
_rh_replay() {
  local dir="$1" t f h
  printf '# replay: from failed-review, through the verbs to delivered:\n' >> "$RH_LOG"
  _rh_do "the sweeper acks the failing reviewer" bash "$RH_ROOT/hooks/session-sweeper.sh" ack w-structure-whole-2 || return 1
  _rh_poker "the fix row born of the finding" task-add T5 4 build 'answer the structure finding: a caller reaches the library change' \
    orchestrator — 10 REQ-1 'payload/scripts/lib/said.sh, tests/rehearsal-row.test.sh' \
    --born record/wave-x/w-structure-whole-2.md#1 || return 1
  _rh_do "the fix row's tree" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" create "$(_rh_head)" wt/T5 --for w-T5 || return 1
  _rh_launch w-T5 T5 rehearsal-row.test.sh || return 1
  _rh_poker "the launch written to the plan" launch-sync || return 1
  t="$RH_ROOT/.worktrees/T5"; f="$t/tests/rehearsal-row.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\n. "$(dirname "$0")/../payload/scripts/lib/said.sh"\nsection "the rehearsal holds"\nexpect_eq "one is one" 1 1\nexpect_eq "a caller reaches the library change" 0 "$(rehearsal_landed; echo $?)"\nfinish\n' > "$f" \
    && _rh_commit "$t" "a caller reaches the library change" \
    || { echo "rehearse $RH_STATE: the fix's commit in .worktrees/T5 failed" >&2; return 1; }
  _rh_hand code "T5's suite, a caller of the library change, committed in .worktrees/T5"
  RH_CWD="$t" _rh_do "the fix row says ready" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" ready --within 300 || return 1
  printf '# T5: the fix\n\nThe suite calls rehearsal_landed, so the library change has a caller.\n' > "$RH_REC/T5.md" || return 1
  _rh_hand record "T5's report record/wave-x/T5.md"
  _rh_do "the sweeper acks the fix row's writer" bash "$RH_ROOT/hooks/session-sweeper.sh" ack w-T5 || return 1
  _rh_poker "the release check at the fix's head" release-check || return 1
  _rh_poker "the release approval card at the fix's head" release-approval "$RH_PLAN" || return 1
  _rh_typed 'all recommended' || return 1
  _rh_poker "the user's reply to the card at the fix's head" reply 'all recommended' || return 1
  _rh_gh "$dir" || { echo "rehearse $RH_STATE: the stand-in gh could not be written in $dir/bin" >&2; return 1; }
  _rh_do "the gh on the integrate row's PATH" env PATH="$RH_GHPATH" bash -c 'type -a gh' || return 1
  _rh_do "the integrate row opens the pull request" env PATH="$RH_GHPATH" gh pr create --base main --head wave/x --fill || return 1
  h="$DOOR_OUT"
  printf '# T4: the pull request\n\n    gh pr create --base main --head wave/x --fill\n\n%s\n' "$h" > "$RH_REC/T4-pr.md" || return 1
  _rh_hand record "T4's report record/wave-x/T4-pr.md: the pull request's command and its address"
  _rh_do "the person merges the pull request" env PATH="$RH_GHPATH" gh pr merge wave/x --merge || return 1
  _rh_follow "the integrate row lands itself" T4 record/wave-x/T4-pr.md bash "$RH_ROOT/hooks/session-poker.sh" deliver T4 || return 1
  _rh_do "close-out, the tail" env HOME="$dir/home" BIONIC_CLAUDE_HOME="$dir/home/.claude" \
    bash "$RH_ROOT/payload/scripts/close-out.sh" "$RH_PLAN" run || return 1
  # close-out archives a delivered run's plans under the home's archive, keeping their path below the project.
  f="$(find "$dir/home" -path "*/$DOOR_PLAN_REL" -type f 2>/dev/null | head -1)"
  [ -n "$f" ] || { echo "rehearse $RH_STATE: close-out ran and no archived plan holds $DOOR_PLAN_REL under $dir/home" >&2; return 1; }
  RH_PLAN="$f"
}

# rehearse <state> <dir> -> the sandbox plan's path
rehearse() {
  local state="${1:-}" dir="${2:-}" built
  rh_state_known "$state" || { echo "rehearse: no state '$state': delivered, failed-review, release-waiting, stop-rule or clean" >&2; return 2; }
  [ -n "$dir" ] || { echo "rehearse: name a directory" >&2; return 2; }
  mkdir -p "$dir" && dir="$(cd "$dir" && pwd -P)" || return 1
  RH_STATE="$state"; RH_LOG="$dir/rehearsal.log"
  : > "$RH_LOG"
  built="$(door_world "$dir/project")" || { echo "rehearse $state: door_world failed under $dir" >&2; return 1; }
  read -r RH_ROOT RH_BASE <<EOF
$built
EOF
  RH_PLAN="$RH_ROOT/$DOOR_PLAN_REL"
  RH_REC="$RH_ROOT/.bionic/docs/record/wave-x"
  # The plugin's context files go beside its scripts, as an install lays them out: the poker reads the structure
  # checks from there. Excluded from the sandbox's git, so the plugin's files never enter the run's range.
  cp -R "$BIONIC_SCRIPTS_DIR/payload/context" "$RH_ROOT/payload/context" \
    && printf 'payload/context/\n' >> "$RH_ROOT/.git/info/exclude" \
    || { echo "rehearse $state: the plugin's context files could not be laid beside its scripts" >&2; return 1; }
  # A project's config is its person's words, so it is written by hand. The run that closes declares the project's
  # real release check, the one door_world commits and declares, since its close is judged by that check. The other
  # states declare the name scan alone: no state short of the close turns on the rest of the check.
  if [ "$state" = delivered ]; then
    printf 'release-check: bash tests/lib/release-check.sh %s\n' "$RH_ROOT-names.list" > "$RH_ROOT/.bionic/config.yaml"
    _rh_hand prose "the project's .bionic/config.yaml, declaring its real release check, tests/lib/release-check.sh"
  else
    printf 'release-check: bash tests/lib/name-scan.sh %s\n' "$RH_ROOT-names.list" > "$RH_ROOT/.bionic/config.yaml"
    _rh_hand prose "the project's .bionic/config.yaml, declaring the name scan as its release check"
  fi
  export CLAUDE_CONFIG_DIR="$dir/config"
  mkdir -p "$CLAUDE_CONFIG_DIR/bionic" "$dir/home/.claude"
  printf '# rehearse %s: door_world built %s at %s, its plan bound to %s\n' "$state" "$RH_ROOT" "$RH_BASE" "$WORLD_SID" >> "$RH_LOG"
  # The planner names the branch the run merges into; door_world's plan, which never merges, leaves it out. It also
  # declares the run's goals, each measured by a record: one the rehearsal writes passing, one failing, and one it
  # never writes, so every state's sheet reads a goal met, one not met and one not measured yet.
  awk -v g="$RH_GOALS" '{ print } $0 == "working-branch: wave/x" && !d { print "integration-branch: main"; print "goals: " g; d = 1 }' \
    "$RH_PLAN" > "$RH_PLAN.rh" && mv "$RH_PLAN.rh" "$RH_PLAN" || return 1
  _rh_hand prose "the plan's Step-3 prose, $DOOR_PLAN_REL (door_world), naming integration-branch: main and the run's three goals"
  printf '# the card read\n\nverdict: pass\n' > "$RH_REC/goal-shown.md" \
    && printf '# the asks checked\n\nverdict: fail\n' > "$RH_REC/goal-asks.md" || return 1
  _rh_hand record "the goal records record/wave-x/goal-shown.md (verdict: pass) and record/wave-x/goal-asks.md (verdict: fail)"
  # The person approves the plan at Step 3 just before the build, so the approval is stamped now: a stamp from the
  # fixture's own past would make the pace read the hours between it and the first landing, and the close land weeks out.
  awk -v at="$(date -u +%Y-%m-%dT%H:%MZ)" '/^approved-by:/ { print "approved-by: user " at " \"approved\""; next } { print }' "$RH_PLAN" > "$RH_PLAN.rh" \
    && mv "$RH_PLAN.rh" "$RH_PLAN" && /usr/bin/grep -q '^approved-by: user ' "$RH_PLAN" || return 1
  _rh_hand prose "the plan's Step-3 approval line, approved-by: user <now> \"approved\" (the person's words, at the rehearsal's start)"
  case "$state" in
    clean)
      _rh_build || return 1 ;;
    stop-rule)
      _rh_build || return 1
      _rh_poker "the release row reads D1" task-set T2 reads+=approval:D1 --reason 'the release waits on the stop-rule decision' \
        || return 1
      _rh_poker "put D1" decisions put D1 'stop the run: the release row waits until the user rules on going on' || return 1 ;;
    release-waiting)
      _rh_release_card || return 1 ;;
    failed-review|delivered)
      _rh_release_card || return 1
      _rh_typed 'all recommended' || return 1
      _rh_poker "the user's reply to the card" reply 'all recommended' || return 1
      _rh_poker "enter Step 8" current 8 || return 1
      _rh_review w-structure-whole-2 structure whole "$RH_BASE" "$(_rh_head)" fail || return 1
      # The integrate row's merge, as the pull request's merge lands it: main moves to the working head.
      _rh_do "merge wave/x into main" git -C "$RH_ROOT" fetch --quiet . wave/x:main || return 1
      _rh_refused "close-out, refused on the failing review" env HOME="$dir/home" BIONIC_CLAUDE_HOME="$dir/home/.claude" \
        bash "$RH_ROOT/payload/scripts/close-out.sh" "$RH_PLAN" run || return 1
      if [ "$state" = delivered ]; then
        _rh_replay "$dir" || return 1
      fi ;;
  esac
  printf '%s\n' "$RH_PLAN"
}

# From the command line: the sandbox is kept, under a world of its own rooted at <dir>.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  rh_state_known "${1:-}" && [ -n "${2:-}" ] \
    || { echo "usage: bash tests/lib/rehearsal.sh <delivered|failed-review|release-waiting|stop-rule|clean> <dir>" >&2; exit 2; }
  mkdir -p "$2" && WORLD_ROOT="$(cd "$2" && pwd -P)" || exit 1
  case "$WORLD_ROOT/" in
    "$BIONIC_SCRIPTS_DIR"/*) echo "rehearsal.sh: $WORLD_ROOT lies inside the plugin tree $BIONIC_SCRIPTS_DIR — name a directory outside it" >&2; exit 2 ;;
  esac
  export WORLD_ROOT WORLD_SID="11111111-2222-4333-8444-555555555555"
  export BIONIC_GATE_DIR="$WORLD_ROOT/gate" BIONIC_VERB_LOG="$WORLD_ROOT/verbs.log"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
fi

# shellcheck source=/dev/null
. "${BIONIC_SCRIPTS_DIR}/tests/lib/door.sh" || return 1 2>/dev/null || exit 1

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  rehearse "$1" "$WORLD_ROOT/$1"
  exit $?
fi
