# tests/lib/rehearsal.sh — the rehearsal: a small run played forward in a sandbox through the commands a real run
# uses, from the skill's invocation and the configuration card of a project with no plan, until it holds one of the
# states the sitrep card is read in, or the Verify gate of a single-rigor run.
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
#                            After each command the run's log as it stood is kept as <dir>/logs/<n>.log, and the
#                            plan's checksum before and after it is a line `<label>|<before>|<after>` of
#                            <dir>/plan-sums: what the run's log and the plan were at every point of the run.
#                            RH_WITHIN=<seconds> bounds each rehearsed ready's wait at the world's gate (300 unset).
#
#   Every state starts the same way, at version 15 (_rh_fresh): the skill invoked, the planner's page with its header
#   and goal, the configuration card, and Steps 0 to 3 each through its card, its approval and its advance, the plan
#   approved and Step 4 entered; nothing between is stamped.
#
#   The states:
#     delivered        the failed-review run, its project declaring its real release check, carried through the
#                      verbs to close-out's delivered: (rehearse prints the archived plan's path): the sweeper acks
#                      the failing reviewer, a second review failing on the same site is registered, a fix row born
#                      of the first review's finding is added (the later rows' deps naming it), cut, launched and
#                      landed through ready, settling both, the release check runs at its head, the release approval
#                      card is rendered there and the user's reply approves it, the integrate row renders the release entry's
#                      reviews part on the working branch and opens the pull request through gh, the person merges
#                      it, the integrate row delivers its record, close-out runs, and the Patrol is disarmed.
#     failed-review    the release-waiting run, the user's reply (all recommended: the release landing past the
#                      pass is a release commit with its check passing, so the head reads green and the card asks no
#                      merge without a pass; the reply records the release approval), Step 8, a whole structure
#                      review failing, the branch merged into main, and close-out refused on the review: the register
#                      holds waive:structure and hold:merge.
#     release-waiting  the release order (the release row at step 7, a regression row, an integrate row), the build
#                      landed through ready, Steps 5 to 7 with the regression and its row delivered, five passing
#                      reviews and the release check, the release landed, and the release approval card rendered.
#     stop-rule        the build row landed; a stop-rule decision put through `decisions put`: the register holds that
#                      decision's decide: ask.
#     clean            the build row landed through ready and the release row is launched: the register holds no open ask.
#     single-verify    the run at rigor: single, carried to the Verify gate: the build landed
#                      through ready, its criterion left pending by that landing, the evidence review at the landed head,
#                      the walk registered (its proof discharges the criterion), the regression proved, and Step 5 entered.
#
# THE SANDBOX is tests/lib/door.sh's `door_project`: a real repository carrying the plugin's hooks and scripts, its
# config, and no plan. Each command runs from the sandbox's root through `door_run`, and the poker, the cards,
# close-out, the sweeper and the door are the sandbox's own copies, so a kept sandbox is read by the same plugin that
# played it. The plugin's context files and skills are laid beside its scripts, as an install lays them out.
#
# WHAT IS WRITTEN BY HAND is what a run's people and agents write by hand, and each `# by hand:` line names its
# kind first, one of RH_HAND_KINDS:
#   [prose]   the person's words: the plan's page (its header, goal, rows and Eval design), the requirements and
#             the spec, and the project's config
#   [record]  a record an agent writes: a review's, a criterion's evidence, the walk and the audit, a row's report,
#             the records two of the goals are measured by, the document Step 7 names
#   [code]    a row's code and its suite, and the release's changelog entry
#   [typed]   what the CLI writes in the session's transcript, the user's typed words and the answer to the
#             orchestrator's ListAgents call, with the session's start record, which session-start writes
#   [launch]  a launched agent's roster row, through the roster's production writer (below)
#   [plan]    the orchestrator's edit of the plan's ## Tasks table: a row added, which task-add then records, or a
#             row's cell changed, judged by the table check the write hook runs
# A register, a ledger line a verb owns, a proof, a step, an approval, a brief or a landing record is never written
# here: each comes from its command.
#
# THE ROSTER ROW of each reviewer is written through the roster's production writer (`roster_row`, by
# tests/lib/roster-row.sh), as the dispatch wall writes it when the reviewer is launched; `stop-orders.sh stopped`
# closes it once the session's panel reads the reviewer gone (_rh_stopped).
#
# A STAND-IN `gh` (delivered alone). The pull request is an outward act, so the integrate row's `gh` is a stand-in, the
# only `gh` on the PATH of the commands that call it: it logs each call's arguments to <dir>/bin/gh.log, answers `pr
# create` with a placeholder address, and for `pr merge` moves the base to the head, as the merge and the pull would.
#
# FROM THE COMMAND LINE nothing is removed: <dir>, outside the plugin tree (`door_run` strips that tree's paths from every
# command's environment), keeps the sandbox, its gate store, its config and the log. Read it as its session: from
# <dir>/<state>/project, with CLAUDE_CODE_SESSION_ID=11111111-2222-4333-8444-555555555555 (WORLD_SID),
# BIONIC_GATE_DIR=<dir>/gate and CLAUDE_CONFIG_DIR=<dir>/<state>/config.
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
# shellcheck source=/dev/null
type -t live_answer_body >/dev/null 2>&1 || . "${BIONIC_SCRIPTS_DIR}/tests/lib/live-answer.sh" || return 1 2>/dev/null || exit 1

# The kinds of hand write, each what a person, an agent or the harness writes in a real run (above).
RH_HAND_KINDS="prose record code typed launch plan"

# The run's three goals, as the plan's goals: line declares them: met, not met and not measured yet in every state.
RH_GOALS="shown · the person says from the card what they owe (record/wave-x/goal-shown.md) ; asks · every ask on the register is on the card (record/wave-x/goal-asks.md) ; walked · the walk finds nothing to fix (record/wave-x/goal-walked.md)"

# rh_state_known <state> -> 0 for one of the six
rh_state_known() {
  case "${1:-}" in delivered|failed-review|release-waiting|stop-rule|clean|single-verify) return 0 ;; esac
  return 1
}

# _rh_cmdline <cmd> [args] -> the command as one shell line, `$ ` first, quoted in the C locale. Under a UTF-8 locale
# bash 3.2's %q escapes a multibyte character's trailing bytes and leaves its lead byte raw, a line no UTF-8 reader
# can decode (macOS awk stops at it, and every row reading past it reads nothing); in C every byte past ASCII is
# escaped, so the log stays valid text and the line still runs as the same command.
_rh_cmdline() { ( LC_ALL=C; printf '$'; printf ' %q' "$@"; printf '\n' ); }

# _rh_sum -> the plan's checksum, read where close-out archives it once it has left the project; `none` before it exists
_rh_sum() {
  local f="$RH_PLAN"
  [ -f "$f" ] || f="$(find "$RH_DIR/home" -path "*/$DOOR_PLAN_REL" -type f 2>/dev/null | head -1)"
  if [ -n "$f" ] && [ -f "$f" ]; then cksum < "$f" | awk '{ print $1 "-" $2 }'; else echo none; fi
}
# _rh_run <label> <cmd> [args] -> runs <cmd> from the sandbox root as the bound session, logging the label, the
# command, its exit and its output, then keeping the run's log as it stands and the plan's checksum on each side
_rh_run() {
  local label="$1" t0="$SECONDS" s0 n
  shift
  s0="$(_rh_sum)"
  door_run "${RH_CWD:-$RH_ROOT}" "$@"
  { _rh_cmdline "$@"; printf '%s\n' "$DOOR_OUT" | sed 's/^/  | /'; printf '  rc=%s  (%s, %s s)\n' "$DOOR_RC" "$label" "$((SECONDS - t0))"; } >> "$RH_LOG"
  printf '%s|%s|%s\n' "$label" "$s0" "$(_rh_sum)" >> "$RH_DIR/plan-sums"
  # Numbered by the logs already kept, so a command run in a subshell keeps its place in the order.
  n="$(( $(ls "$RH_DIR/logs" | wc -l) + 1 ))"
  cat "$RH_REC/run.log" > "$RH_DIR/logs/$n.log" 2>/dev/null || : > "$RH_DIR/logs/$n.log"
}
# _rh_do <label> <cmd> [args] -> _rh_run's run; a non-zero exit is reported on stderr and returned.
_rh_do() {
  local label="$1"
  _rh_run "$@"
  shift
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
# _rh_row <label> <Tasks line> <id> [--born <b>] -> the orchestrator's edit adding the row, one hand write, then task-add
_rh_row() { _rh_addrow "$2" "$3" && _rh_poker "$1" task-add "${@:3}"; }
# _rh_addrow <Tasks line> <id> -> the orchestrator's edit adding the row as the table's last, one hand write
_rh_addrow() { RH_R="$1" awk '/^## / { t = ($0 ~ /^## Tasks/) } { L[NR] = $0 } t && /^\|/ { last = NR } END { for (i = 1; i <= NR; i++) { print L[i]; if (i == last) print ENVIRON["RH_R"] } }' \
  "$RH_PLAN" > "$RH_PLAN.t" && mv "$RH_PLAN.t" "$RH_PLAN" && _rh_hand plan "the row $2"; }
# _rh_cell <what> <row> <column>=<value>… -> the person's edit of a Tasks row's cells, written as text beside the plan
# (lib/units.sh `units_table_cells`) and judged by the table check the write hook runs before it replaces it
_rh_cell() {
  local w="$1"; shift
  bash -c '. "$1/units.sh" 2>/dev/null && units_table_cells "$2" set tasks "${@:3}" > "$2.t" && [ -z "$(units_validate "$2.t" "$2" 2>&1)" ] && mv "$2.t" "$2" || { rm -f "$2.t"; exit 1; }' \
    _ "$RH_ROOT/payload/scripts/lib" "$RH_PLAN" "$@" || { echo "rehearse $RH_STATE: the edit of $1 was refused: $w" >&2; return 1; }
  _rh_hand plan "$w: $*"
}
_rh_head() { git -C "$RH_ROOT" rev-parse --verify -q "refs/heads/$DOOR_BRANCH"; }
_rh_commit() { git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" commit --quiet -m "$2"; }   # <tree> <message>

# _rh_typed <words> -> the session's transcript holds <words> as a prompt the user typed, under the rehearsal's own
# config directory, and the session's start record names this root: the two witnesses a verb holding words to what
# the user typed asks (lib/said.sh). The CLI writes the one and session-start the other; the rehearsal stands in for
# both, in their shapes (tests/fixtures/transcript-move).
_rh_transcript() {  # -> the session's transcript, its frame written once
  local proj
  proj="$CLAUDE_CONFIG_DIR/projects/$(bash -c '. "$1/detect.sh" >/dev/null 2>&1; project_slug "$2"' _ \
    "$RH_ROOT/payload/scripts/lib" "$RH_ROOT")" || return 1
  mkdir -p "$proj" && { [ -s "$proj/$WORLD_SID.jsonl" ] || cat "$BIONIC_SCRIPTS_DIR/tests/fixtures/transcript-move/frame.jsonl" > "$proj/$WORLD_SID.jsonl"; } \
    && printf '%s' "$proj/$WORLD_SID.jsonl"
}
_rh_typed() {
  local tr
  tr="$(_rh_transcript)" || return 1
  jq -c --arg t "$1" --arg s "$WORLD_SID" '.message.content = $t | .sessionId = $s' "$BIONIC_SCRIPTS_DIR/tests/fixtures/transcript-move/typed.jsonl" \
    >> "$tr" || return 1
  [ -f "$RH_ROOT/.bionic/tmp/loaded-$WORLD_SID.state" ] \
    || printf 'root=%s\nstarted=2026-10-01T00:00:00Z\ncwd=%s\n' "$RH_ROOT/hooks" "$RH_ROOT" \
      > "$RH_ROOT/.bionic/tmp/loaded-$WORLD_SID.state" || return 1
  _rh_hand typed "the user typed '$1' (the session's transcript, and its start record)"
}

# _rh_stopped <name>… -> each agent's report reaching the session (the envelope the harness writes into its transcript
# for the agent's SendMessage naming its deliverable), the session's panel read fresh (the harness's answer to the
# orchestrator's ListAgents call, after the last prompt, in tests/lib/live-answer.sh's corpus shape) listing none of
# them, and each row closed by the act the dispatch page names, `stop-orders.sh stopped`
_rh_stopped() {
  local n tr at d
  tr="$(_rh_transcript)" && at="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" || return 1
  for n; do
    d="$(/usr/bin/grep -h "|name=$n|" "$RH_ROOT"/.bionic/tmp/roster-*.state 2>/dev/null | tail -1 | tr '|' '\n' | sed -n 's/^deliverable=//p')"
    _live_answer_entry_prompt "$at" "<teammate-message teammate_id=\"$n\">$n: done, the report is $d</teammate-message>" >> "$tr" || return 1
  done
  # The panel is read after the reports arrive, half a second into the same second: a reading older than the last
  # prompt is stale.
  at="${at%.000Z}.500Z"
  { _live_answer_entry_tool_use "$at" "toolu-panel-$#-$1"; _live_answer_entry_tool_result "$at" "toolu-panel-$#-$1" "$(live_answer_body)"; } >> "$tr" || return 1
  _rh_hand typed "the reports of $* and the panel the orchestrator read before closing their rows, in the session's transcript"
  for n; do _rh_do "the orchestrator closes $n's row" bash "$RH_ROOT/hooks/stop-orders.sh" stopped "$n" || return 1; done
}

# _rh_reply <label> -> the user's reply to the newest release card at the working head, typed, then replayed: all as
# recommended. The release landing past the pass is a release commit with its check passing, so the head reads green and
# the card asks no merge without a pass; the reply records the release approval. Where the card does put the merge
# without a pass, its number is the one the judge's exit names (lib/proof.sh `proof_merge_decision`), and the reply merges.
_rh_reply() {
  local n w='all recommended'
  n="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" && proof_merge_decision "$2" "$3" "$4"' _ \
    "$RH_ROOT/payload/scripts/lib" "$RH_PLAN" "$RH_ROOT" "$(_rh_head)" 2>/dev/null)" || n=""
  [ -z "$n" ] || w="$n merge, rest recommended"
  _rh_typed "$w" && _rh_poker "$1" reply "$w"
}

# _rh_land <row> -> the row's tree landed by hand through the sandbox's door
_rh_land() {
  _rh_do "land $1" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" land "$RH_ROOT/.worktrees/$1" --by-hand \
    --reason "the rehearsal lands $1 by hand"
}

# _rh_build_ready -> the build row written in a tree the create verb makes for its writer, with a one-row suite, and
# landed through ready on that suite: its landing writes the criterion's evidence and status (lib/line.sh `line_settle`)
_rh_build_ready() {
  local t="$RH_ROOT/.worktrees/T1"
  _rh_brief dw-T1 T1 || return 1
  _rh_do "the build row's tree" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" create "$(_rh_head)" wt/T1 --for dw-T1 || return 1
  _rh_launch dw-T1 T1 rehearsal-row.test.sh || return 1
  printf 'rehearsal_landed() { :; }\n' >> "$t/payload/scripts/lib/said.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\nsection "the rehearsal holds"\nexpect_eq "one is one" 1 1\nfinish\n' \
    > "$t/tests/rehearsal-row.test.sh"
  _rh_commit "$t" "a library change and its suite" || { echo "rehearse $RH_STATE: the build's commit in .worktrees/T1 failed" >&2; return 1; }
  _rh_hand code "T1's code and its suite, committed in .worktrees/T1"
  RH_CWD="$t" _rh_do "the build row says ready" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" ready --within "${RH_WITHIN:-300}" || return 1
  printf '# T1: the build\n\nThe library change and its suite.\n' > "$RH_REC/T1.md" || return 1
  _rh_hand record "T1's report record/wave-x/T1.md"
  _rh_stopped dw-T1
}

# _rh_review <name> <question> <scope> <a> <b> <pass|fail> -> the reviewer's record and roster row. The evidence question
# is the auditor's only at double rigor, as the poker deals it; otherwise the critic holds it.
_rh_review() {
  local nm="$1" q="$2" sc="$3" res="$6" t=bionic:critic n=0
  [ "$q" != evidence ] || [ "$(_rh_rigor)" != double ] || t=bionic:auditor
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

# _rh_rigor -> the plan's rigor: word, as its planner wrote it
_rh_rigor() { awk '/^---$/ { n++; next } n == 1 && /^rigor:/ { sub(/^rigor:[[:space:]]*/, ""); print; exit }' "$RH_PLAN"; }

# _rh_verify -> the build landed through ready, the evidence review at the landed head (the auditor's at double rigor,
# the critic's at single), which is the verdict a criterion a logged proof discharges reads, the walk registered (its
# record the critic's shape, one CONFIRMED row for the one criterion, so the walk's proof discharges it), the whole run's
# regression proved at the head, and Step 5 entered. Only a double-rigor run deals an auditor, so only there is the
# audit's record written.
_rh_verify() {
  local dbl=no
  [ "$(_rh_rigor)" != double ] || dbl=yes
  _rh_build_ready || return 1
  _rh_review w-evidence-whole evidence whole "$RH_BASE" "$(_rh_head)" pass || return 1
  _rh_stopped w-evidence-whole || return 1
  printf '# walk\n\n| AC | verdict | why |\n|---|---|---|\n| AC-1.1 | CONFIRMED | the build row read whole |\n\nverdict: CONFIRMED — the one criterion\n' > "$RH_REC/walk.md"
  if [ "$dbl" = yes ]; then
    printf 'CONFIRMED: the one criterion is proved\n' > "$RH_REC/audit.md"
    _rh_hand record "the walk record/wave-x/walk.md and the audit record/wave-x/audit.md"
  else
    _rh_hand record "the walk record/wave-x/walk.md"
  fi
  _rh_poker "register the walk" proof-add walk record/wave-x/walk.md || return 1
  _rh_poker "run the regression" regression-run || return 1
  _rh_poker "record the regression" proof-add regression "record/wave-x/regression-run-$(_rh_head).log" || return 1
  _rh_poker "enter Step 5" current 5
}

# _rh_release_card -> the release row's run carried to the release approval card: the release order, the build, the
# matrix, Steps 5 to 7 with the regression, the five reviews and the release check, the release landed, the card
_rh_release_card() {
  local h1 qs t2
  _rh_cell "the release row moves to step 7" T2 step=7 || return 1
  _rh_row "add the regression row" '| T3 | 5 | test | the regression. The whole suite runs once. | — | 10 | REQ-1 | .bionic/docs/record/wave-x/T3.md | — |' T3 || return 1
  _rh_row "add the integrate row" '| T4 | 8 | integrate | merge into main. The run reaches main by its merge. | — | 10 | REQ-1 | — | — |' T4 || return 1
  _rh_verify || return 1
  h1="$(_rh_head)"
  printf '# T3: the regression\n\nThe whole run at %s exited 0: record/wave-x/regression-run-%s.log.\n' "$h1" "$h1" > "$RH_REC/T3.md"
  _rh_hand record "the regression row's report record/wave-x/T3.md"
  _rh_tick_land "the tick lands the regression row" T3 record/wave-x/T3.md || return 1
  for qs in evidence:piece adversarial:piece structure:piece adversarial:whole structure:whole; do
    _rh_review "w-${qs%%:*}-${qs#*:}" "${qs%%:*}" "${qs#*:}" "$RH_BASE" "$h1" pass || return 1
  done
  _rh_stopped \
    w-evidence-piece w-adversarial-piece w-structure-piece w-adversarial-whole w-structure-whole || return 1
  _rh_poker "enter Step 6" current 6 || return 1
  _rh_poker "the release check at the build head" release-check || return 1
  _rh_poker "enter Step 7" current 7 || return 1
  t2="$RH_ROOT/.worktrees/T2"
  _rh_brief dw-T2 T2 && _rh_do "the release row's tree" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" create "$(_rh_head)" wt/T2 --for dw-T2 \
    && _rh_launch dw-T2 T2 release-check.test.sh || return 1
  DOOR_RUNNER=_rh_note door_release "$RH_ROOT" "$t2" >/dev/null \
    || { echo "rehearse $RH_STATE: the release commit in .worktrees/T2 failed" >&2; return 1; }
  _rh_hand code "the release $DOOR_VERSION: its changelog entry (release-note's numbers) and plugin.json, committed in .worktrees/T2"
  _rh_land T2 || return 1
  door_readers "$RH_ROOT" "$(_rh_head)" || return 1; _rh_hand record "the release's five readers green at its head, as its ready over them records them"
  _rh_poker "the release check at the release head" release-check || return 1
  _rh_poker "the release approval card" release-approval "$RH_PLAN"
}

# _rh_note <root> <cmd> [args] -> door_release's run of the release note, as the rehearsal runs each command
_rh_note() { shift; _rh_run "the release note's numbers" "$@"; }

# _rh_brief <name> <row> -> the brief of <row> rendered for <name> by the brief verb, which the tree verb reads the row from
_rh_brief() { _rh_poker "render $2's brief for $1" brief "$2" "$1"; }

# _rh_launch <name> <row> <suite> -> the writer's roster row, as the dispatch wall writes it when the writer is launched
# on <row> with its brief's Lands-on suite, confirmed by the launch recorder: the run's dispatch event
_rh_launch() {
  local u="toolu-$1"
  roster_row_fixture status=intended session="$WORLD_SID" name="$1" agent_id= subagent_type=bionic:senior-implementor \
    launched_at=2026-10-01T00:00:00Z deliverable="$RH_REC/$2.md" plan="$RH_PLAN" row="$2" lands_on="$3" tool_use_id="$u" \
    brief=".bionic/docs/record/wave-x/briefs/$1.md" brief_sum=- >> "$RH_ROOT/.bionic/tmp/roster-$WORLD_SID.state" || return 1
  _rh_hand launch "$1's roster row on $2, landing on $3 (roster_row)"
  _rh_do "$1's launch confirmed: its dispatch event" bash -c 'printf %s "$1" | bash "$2"' _ \
    "$(jq -nc --arg s "$WORLD_SID" --arg c "$RH_ROOT" --arg n "$1" --arg u "$u" '{session_id:$s, cwd:$c, hook_event_name:"PostToolUse",
      tool_name:"Agent", tool_input:{name:$n}, tool_response:{agentId:("a-" + $n)}, tool_use_id:$u}')" "$RH_ROOT/hooks/execution-recorder.sh"
}


# _rh_landed <row> -> 0 when the units helper reads <row> landed
_rh_landed() {
  [ "$(bash -c '. "$1/units.sh" >/dev/null 2>&1 && units_rows "$2"' _ "$RH_ROOT/payload/scripts/lib" "$RH_PLAN" 2>/dev/null \
    | awk -F'\t' -v r="$1" '$1 == r { print $10 }')" = landed ]
}
# _rh_tick_land <label> <row> <record> -> a record row landed by the tick, the person's act: a tick runs, and when the row
# does not read landed its words name the edit of the row's cell, which is made, and the tick runs again
_rh_tick_land() {
  local label="$1" row="$2" rec="$3" key val n
  for n in 1 2; do
    _rh_run "$label, tick $n" bash "$RH_ROOT/hooks/session-poker.sh" tick
    _rh_landed "$row" && return 0
    [ "$n" = 1 ] || break
    key="$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -oE "edit the [A-Za-z-]+ cell of $row in the plan" | head -1)"; key="${key#edit the }"; key="${key%% *}"
    case "$key" in
      Files) val=".bionic/docs/$rec" ;;
      artifact) val="$rec" ;;
      *) break ;;
    esac
    printf '# not landed: %s · names: edit %s\n' "$label" "$key" >> "$RH_LOG"
    _rh_cell "the tick names the edit of $row's $key cell" "$row" "$key=$val" || return 1
  done
  printf 'rehearse %s: %s: the tick did not land %s\n' "$RH_STATE" "$label" "$row" >&2
  printf '%s\n' "$DOOR_OUT" | sed 's/^/  | /' >&2
  return 1
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
  _rh_stopped w-structure-whole-2 || return 1
  # A second reader of the same head names the same site under another question, dealt it on its roster row: the fix
  # row's landing settles that finding too, so no move follows the landing.
  _rh_review w-adversarial-whole-2 adversarial whole "$RH_BASE" "$(_rh_head)" fail || return 1
  _rh_stopped w-adversarial-whole-2 || return 1
  # The fix row, and the rows of later steps waiting on it as task-add asks: their deps name it.
  _rh_addrow '| T5 | 4 | build | Answer the structure finding. A caller reaches the library change. The caller and the library agree again. · born: review | — | 10 | REQ-1 | payload/scripts/lib/said.sh, tests/rehearsal-row.test.sh | — |' T5 \
    && _rh_cell "the release row waits on the fix" T2 deps=T5 && _rh_cell "the integrate row waits on the fix" T4 deps=T5 \
    && _rh_poker "the fix row born of the finding" task-add T5 --born record/wave-x/w-structure-whole-2.md#1 || return 1
  _rh_brief w-T5 T5 || return 1
  _rh_do "the fix row's tree" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" create "$(_rh_head)" wt/T5 --for w-T5 || return 1
  _rh_launch w-T5 T5 rehearsal-row.test.sh || return 1
  t="$RH_ROOT/.worktrees/T5"; f="$t/tests/rehearsal-row.test.sh"
  printf '#!/bin/bash\n. "$(dirname "$0")/lib/assert.sh"\n. "$(dirname "$0")/../payload/scripts/lib/said.sh"\nsection "the rehearsal holds"\nexpect_eq "one is one" 1 1\nexpect_eq "a caller reaches the library change" 0 "$(rehearsal_landed; echo $?)"\nfinish\n' > "$f" \
    && _rh_commit "$t" "a caller reaches the library change" \
    || { echo "rehearse $RH_STATE: the fix's commit in .worktrees/T5 failed" >&2; return 1; }
  _rh_hand code "T5's suite, a caller of the library change, committed in .worktrees/T5"
  RH_CWD="$t" _rh_do "the fix row says ready" bash "$RH_ROOT/payload/scripts/spawn-worktree.sh" ready --within "${RH_WITHIN:-300}" || return 1
  printf '# T5: the fix\n\nThe suite calls rehearsal_landed, so the library change has a caller.\n' > "$RH_REC/T5.md" || return 1
  _rh_hand record "T5's report record/wave-x/T5.md"
  _rh_stopped w-T5 || return 1
  _rh_poker "the release check at the fix's head" release-check || return 1
  _rh_poker "the release approval card at the fix's head" release-approval "$RH_PLAN" || return 1
  _rh_reply "the user's reply to the card at the fix's head" || return 1
  # The part goes on the branch before the pull request opens, so the merge carries it to main.
  _rh_poker "the integrate row renders the entry's reviews part" reviews-part T4 || return 1
  _rh_gh "$dir" || { echo "rehearse $RH_STATE: the stand-in gh could not be written in $dir/bin" >&2; return 1; }
  _rh_do "the gh on the integrate row's PATH" env PATH="$RH_GHPATH" bash -c 'type -a gh' || return 1
  _rh_do "the integrate row opens the pull request" env PATH="$RH_GHPATH" gh pr create --base main --head "$DOOR_BRANCH" --fill || return 1
  h="$DOOR_OUT"
  printf '# T4: the pull request\n\n    gh pr create --base main --head %s --fill\n\n%s\n' "$DOOR_BRANCH" "$h" > "$RH_REC/T4-pr.md" || return 1
  _rh_hand record "T4's report record/wave-x/T4-pr.md: the pull request's command and its address"
  _rh_do "the person merges the pull request" env PATH="$RH_GHPATH" gh pr merge "$DOOR_BRANCH" --merge || return 1
  # The integrate row is the merge's: close-out lands it at the integration head, the act below.
  _rh_do "close-out, the tail" env HOME="$dir/home" BIONIC_CLAUDE_HOME="$dir/home/.claude" \
    bash "$RH_ROOT/payload/scripts/close-out.sh" "$RH_PLAN" run || return 1
  # close-out archives a delivered run's plans under the home's archive, keeping their path below the project.
  f="$(find "$dir/home" -path "*/$DOOR_PLAN_REL" -type f 2>/dev/null | head -1)"
  [ -n "$f" ] || { echo "rehearse $RH_STATE: close-out ran and no archived plan holds $DOOR_PLAN_REL under $dir/home" >&2; return 1; }
  RH_PLAN="$f"
  # At the run's close the Patrol's stamp goes with it, as the skill says to end it.
  _rh_poker "the Patrol is disarmed at the close" disarm
}

# _rh_card <step> <artifact> -> the step's card rendered by its verb
_rh_card() { _rh_do "the Step ${1#step} card" bash "$RH_ROOT/payload/scripts/card.sh" "$1" "$2"; }
# _rh_approve <name> -> the user types the literal word, and the approval of <name> is recorded on it
_rh_approve() { _rh_typed approved && _rh_poker "approve $1" approve "$1" approved; }

# _rh_fresh <rigor> -> the run from the skill's invocation to Step 4, each step's artifact written by its person and the
# rest by commands: the session engages, the planner's page binds it, and each of Steps 0 to 3 ends on its card, its
# approval and its advance.
_rh_fresh() {
  local spec="$RH_ROOT/.bionic/docs/specs/epic-x"
  _rh_do "the skill is invoked: the session engages" bash -c 'printf %s "$1" | bash "$2"' _ \
    "$(jq -nc --arg s "$WORLD_SID" --arg c "$RH_ROOT" '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Skill", tool_input:{skill:"bionic:canonical-sdlc"}}')" \
    "$RH_ROOT/hooks/engage.sh" || return 1
  mkdir -p "${RH_PLAN%/*}" "$spec" || return 1
  # The planner names the branch the run merges into and the run's goals, each measured by a record: one the
  # rehearsal writes passing, one failing, and one it never writes, so every state's sheet reads a goal met, one not
  # met and one not measured yet. The run writes no durable decision, so its document is none, with the reason.
  cat > "$RH_PLAN" <<PLAN || return 1
---
working-branch: $DOOR_BRANCH
integration-branch: main
goals: $RH_GOALS
base-sha: $RH_BASE
release: $DOOR_VERSION
rigor: $1
scale: wave
adrs: none: the run decides nothing durable
canonical_sdlc_version: 15
---
# a rehearsed run

## Goal

One library change, released.
PLAN
  _rh_hand prose "the plan's page at Step 0, $DOOR_PLAN_REL: its header (branches, base, release, rigor, scale, goals, document) and its goal"
  _rh_poker "the plan binds the session" bind "$RH_PLAN" || return 1
  _rh_card step0 "$RH_PLAN" && _rh_approve step0 && _rh_poker "enter Step 1" current 1 || return 1
  cat > "$spec/wave-x.requirements.md" <<REQ || return 1
---
working-branch: $DOOR_BRANCH
integration-branch: main
---
# wave x · requirements

## Goal

One library change, released.

## Not Doing

- A second change: one is enough to rehearse.

## The change

The run ships one change.

### REQ-1 — the library change

The library gains one function, and a suite proves it.

provenance: user 2026-11-12 "rehearse a run"
- AC-1.1 the library change holds. Fails when: the build row's suite is red.
REQ
  _rh_hand prose "the requirements, specs/epic-x/wave-x.requirements.md"
  _rh_card step1 "$spec/wave-x.requirements.md" && _rh_approve step1 && _rh_poker "enter Step 2" current 2 || return 1
  cat > "$spec/wave-x.spec.md" <<SPEC || return 1
---
working-branch: $DOOR_BRANCH
integration-branch: main
---
# wave x · spec

## Goal

Answer the requirements with one function.

## Design

### 1. Domain model

- **The change** — one function in a library.

### 2. Component boundaries and interfaces

- **\`payload/scripts/lib/said.sh\`** owns the function. (D1; REQ-1)

### 3. Ownership table

| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| the change | \`payload/scripts/lib/said.sh\` | none fits: new | none | \`tests/rehearsal-row.test.sh\` |

### 4. Rejected alternatives

- No change — lost: nothing to rehearse.

### 5. Assumptions

- The library is sourced by its callers.

### Decisions

- **D1 — one function** (D1; REQ-1)

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | the build row's suite | AC-1.1 | hermetic | \`rehearsal-row.test.sh\` | the build row's suite is red |
SPEC
  _rh_hand prose "the spec, specs/epic-x/wave-x.spec.md"
  _rh_card step2 "$spec/wave-x.spec.md" && _rh_approve step2 && _rh_poker "enter Step 3" current 3 || return 1
  cat >> "$RH_PLAN" <<PLAN || return 1

## Tasks

| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a library change. One function and its suite. | — | 10 | REQ-1 | payload/scripts/lib/said.sh, tests/rehearsal-row.test.sh | — |
| T2 | 4 | doc | the release $DOOR_VERSION. Its changelog entry and version. | — | 10 | REQ-1 | CHANGELOG.md, payload/.claude-plugin/plugin.json | — |

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | the build row's suite | AC-1.1 | hermetic | \`rehearsal-row.test.sh\` | the build row's suite is red |
PLAN
  _rh_hand prose "the plan's Step-3 prose: its rows and its Eval design"
  _rh_card step3 "$RH_PLAN" && _rh_approve plan && _rh_poker "enter Step 4" current 4
}

# rehearse <state> <dir> -> the sandbox plan's path
rehearse() {
  local state="${1:-}" dir="${2:-}" built rigor=double
  rh_state_known "$state" || { echo "rehearse: no state '$state': delivered, failed-review, release-waiting, stop-rule, clean or single-verify" >&2; return 2; }
  [ -n "$dir" ] || { echo "rehearse: name a directory" >&2; return 2; }
  mkdir -p "$dir" && dir="$(cd "$dir" && pwd -P)" || return 1
  RH_STATE="$state"; RH_LOG="$dir/rehearsal.log"; RH_DIR="$dir"
  # A rehearsed landing asks the gate, and a suite's verdict never turns on what else the host is doing: the world is a
  # quiet machine, planted through the readers' pins as the gate's own suites plant one, so only its own store and config
  # (a share, a reserve) can make a rehearsed landing wait. Callers run rehearse in a subshell, so nothing leaks.
  export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
  : > "$RH_LOG"; : > "$dir/plan-sums"; mkdir -p "$dir/logs" || return 1
  [ "$state" != single-verify ] || rigor=single
  built="$(door_project "$dir/project")" || { echo "rehearse $state: door_project failed under $dir" >&2; return 1; }
  RH_ROOT="${built% *}"; RH_BASE="${built##* }"
  RH_PLAN="$RH_ROOT/$DOOR_PLAN_REL"
  RH_REC="$RH_ROOT/.bionic/docs/record/wave-x"
  # The plugin's context files and skills go beside its scripts, as an install lays them out: the poker reads the
  # structure checks and the brief's scaffold from there. Excluded from the sandbox's git, so they never enter the range.
  cp -R "$BIONIC_SCRIPTS_DIR/payload/context" "$RH_ROOT/payload/context" && cp -R "$BIONIC_SCRIPTS_DIR/skills" "$RH_ROOT/skills" \
    && printf 'payload/context/\nskills/\n' >> "$RH_ROOT/.git/info/exclude" \
    || { echo "rehearse $state: the plugin's context files and skills could not be laid beside its scripts" >&2; return 1; }
  # A project's config is its person's words, so it is written by hand. The run that closes declares the project's
  # real release check, the one door_project commits, since its close is judged by that check. The other states
  # declare the name scan alone: no state short of the close turns on the rest of the check.
  if [ "$state" = delivered ]; then
    printf 'release-check: bash tests/lib/release-check.sh %s\n' "$RH_ROOT-names.list" > "$RH_ROOT/.bionic/config.yaml"
    _rh_hand prose "the project's .bionic/config.yaml, declaring its real release check, tests/lib/release-check.sh"
  else
    printf 'release-check: bash tests/lib/name-scan.sh %s\n' "$RH_ROOT-names.list" > "$RH_ROOT/.bionic/config.yaml"
    _rh_hand prose "the project's .bionic/config.yaml, declaring the name scan as its release check"
  fi
  export CLAUDE_CONFIG_DIR="$dir/config"
  mkdir -p "$CLAUDE_CONFIG_DIR/bionic" "$dir/home/.claude"
  printf '# rehearse %s: door_project built %s at %s, with no plan and no session bound\n' "$state" "$RH_ROOT" "$RH_BASE" >> "$RH_LOG"
  _rh_fresh "$rigor" || return 1
  printf '# the card read\n\nverdict: pass\n' > "$RH_REC/goal-shown.md" \
    && printf '# the asks checked\n\nverdict: fail\n' > "$RH_REC/goal-asks.md" || return 1
  _rh_hand record "the goal records record/wave-x/goal-shown.md (verdict: pass) and record/wave-x/goal-asks.md (verdict: fail)"
  case "$state" in
    clean)
      _rh_build_ready && _rh_brief dw-T2 T2 && _rh_launch dw-T2 T2 release-check.test.sh || return 1 ;;
    single-verify)
      _rh_verify || return 1 ;;
    stop-rule)
      _rh_build_ready || return 1
      _rh_poker "put D1" decisions put D1 'stop the run: the release row waits until the user rules on going on' || return 1 ;;
    release-waiting)
      _rh_release_card || return 1 ;;
    failed-review|delivered)
      _rh_release_card || return 1
      _rh_reply "the user's reply to the card" || return 1
      _rh_poker "enter Step 8" current 8 || return 1
      _rh_review w-structure-whole-2 structure whole "$RH_BASE" "$(_rh_head)" fail || return 1
      # The integrate row's merge, as the pull request's merge lands it: main moves to the working head.
      _rh_do "merge the working branch into main" git -C "$RH_ROOT" fetch --quiet . "$DOOR_BRANCH:main" || return 1
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
    || { echo "usage: bash tests/lib/rehearsal.sh <delivered|failed-review|release-waiting|stop-rule|clean|single-verify> <dir>" >&2; exit 2; }
  mkdir -p "$2" && WORLD_ROOT="$(cd "$2" && pwd -P)" || exit 1
  case "$WORLD_ROOT/" in
    "$BIONIC_SCRIPTS_DIR"/*) echo "rehearsal.sh: $WORLD_ROOT lies inside the plugin tree $BIONIC_SCRIPTS_DIR — name a directory outside it" >&2; exit 2 ;;
  esac
  export WORLD_ROOT WORLD_SID="11111111-2222-4333-8444-555555555555"
  export BIONIC_GATE_DIR="$WORLD_ROOT/gate" BIONIC_VERB_LOG="$WORLD_ROOT/verbs.log"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
fi

# The run's working branch is shaped as its wave scale's branch cell asks (wave/<NN>-<slug>), which the close's census
# reads its wave number from.
DOOR_BRANCH="wave/01-x"
# shellcheck source=/dev/null
. "${BIONIC_SCRIPTS_DIR}/tests/lib/door.sh" || return 1 2>/dev/null || exit 1

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  rehearse "$1" "$WORLD_ROOT/$1"
  exit $?
fi
