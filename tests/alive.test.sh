#!/bin/bash
# tests/alive.test.sh — payload/scripts/lib/alive.sh, the one rule for alive: a session or a run is
# alive while the process its record names is running and started when the record says; an agent is
# alive while its session is and the session's transcript does not show it finished.
#
#   §ONE    a session whose pid answers but whose recorded start differs reads dead to every library
#           caller (the rule, the Patrol's live and dead sets, the agent rule), and one whose start
#           matches reads alive to each of them.
#   §CLEAR  after a cleared conversation the CLI's file names the successor, and the predecessor reads
#           alive for as long as the process it ran in does: the answer keys on the process, not on
#           the conversation id. Once the process ends, the predecessor reads dead.
#
# FIXTURE FIDELITY. The CLI's session file carries the keys read from a live one on this machine
# (`pid`, `sessionId`, `procStart` in the C locale and UTC, `cwd`); the transcript is the corpus
# answer of tests/lib/live-answer.sh. HERMETIC: a sandboxed claude home (BIONIC_CLAUDE_HOME), and
# the processes are `sleep`s this suite starts.
# ANTI-VACUITY. Each dead reading sits beside an alive one on the same caller and fixture.
#
# Usage: bash tests/alive.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/live-answer.sh"

LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/alive-test.XXXXXX")" && pwd -P)"
sleep 600 & P1=$!
sleep 600 & P2=$!
trap 'kill "$P1" "$P2" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

export BIONIC_CLAUDE_HOME="$SANDBOX/home" CLAUDE_CODE_SESSION_ID=""
ROOT="$SANDBOX/repo"; mkdir -p "$BIONIC_CLAUDE_HOME/sessions" "$ROOT/.bionic/tmp"
# shellcheck disable=SC1091
. "$LIB/alive.sh"; . "$LIB/patrol.sh"; . "$LIB/agents.sh"

# <pid> <sid> <procStart> — the CLI's own file for a process, in the shape it writes.
cli_file() {
  jq -n --argjson p "$1" --arg s "$2" --arg t "$3" --arg c "$ROOT" \
    '{pid:$p, sessionId:$s, procStart:$t, cwd:$c, kind:"interactive"}' > "$BIONIC_CLAUDE_HOME/sessions/$1.json"
}
rc() { "$@" >/dev/null 2>&1; echo $?; }

section "ONE: a pid that answers with another start is dead to every caller"
GOOD=11111111-0000-4000-8000-000000000001; BAD=22222222-0000-4000-8000-000000000002
cli_file "$P1" "$GOOD" "$(_slots_since "$P1")"
cli_file "$P2" "$BAD" "Thu Jan  1 00:00:00 1970"
mkdir -p "$BIONIC_CLAUDE_HOME/projects/x"; : > "$BIONIC_CLAUDE_HOME/projects/x/$BAD.jsonl"
: > "$ROOT/.bionic/tmp/roster-$GOOD.state"; : > "$ROOT/.bionic/tmp/roster-$BAD.state"
expect_eq "the rule: the session whose start matches is alive" "0" "$(rc alive_session "$GOOD")"
expect_eq "…and the one whose pid answers with another start is dead, its transcript notwithstanding" \
  "1" "$(rc alive_session "$BAD")"
expect_eq "the Patrol's live set holds the matching one alone" "$GOOD" "$(patrol_live_session_ids)"
expect_eq "…and its dead set holds the other alone" "$BAD" "$(patrol_dead_sessions "$ROOT")"
live_answer_running "$SANDBOX/t.jsonl"
NAME="$(live_agents "$SANDBOX/t.jsonl" 2>/dev/null | cut -d'|' -f1)"
expect_eq "the transcript lists a running teammate" "research-code-map" "$NAME"
expect_eq "the agent rule: a running teammate of the live session is alive" "0" \
  "$(rc alive_agent "$GOOD" "$SANDBOX/t.jsonl" "$NAME")"
expect_eq "…and the same teammate of the dead session is dead" "1" \
  "$(rc alive_agent "$BAD" "$SANDBOX/t.jsonl" "$NAME")"
expect_eq "the caller's own session is alive to itself with no CLI file" "0" \
  "$(CLAUDE_CODE_SESSION_ID=33333333-0000-4000-8000-000000000003 rc alive_session 33333333-0000-4000-8000-000000000003)"

section "CLEAR: a cleared conversation's predecessor is alive while its process is"
OLD=44444444-0000-4000-8000-000000000004; NEW=55555555-0000-4000-8000-000000000005
rm -f "$BIONIC_CLAUDE_HOME/sessions/"*.json "$ROOT/.bionic/tmp/"*
cli_file "$P1" "$OLD" "$(_slots_since "$P1")"
expect_eq "the record is written while the conversation is current" "0" "$(rc alive_note "$OLD")"
expect_eq "…and an id no CLI file names writes none" "1" "$(rc alive_note "$NEW")"
cli_file "$P1" "$NEW" "$(_slots_since "$P1")"
: > "$ROOT/.bionic/tmp/roster-$OLD.state"
expect_eq "after the clear the predecessor is alive" "0" "$(rc alive_session "$OLD")"
expect_eq "…the Patrol's live set holds both conversations of the one process" "$NEW $OLD" \
  "$(patrol_live_session_ids | tr '\n' ' ' | sed 's/ $//')"
expect_eq "…so its dead set holds neither" "" "$(patrol_dead_sessions "$ROOT")"
kill "$P1" 2>/dev/null; wait "$P1" 2>/dev/null
expect_eq "once the process ends the predecessor is dead" "1" "$(rc alive_session "$OLD")"
expect_eq "…and the Patrol's dead set names it" "$OLD" "$(patrol_dead_sessions "$ROOT")"

finish
