#!/bin/bash
# BACKGROUND-SUITE GUARD — a subagent may not run a suite where nobody reads the output.
# (B-9, wave-bionic-1.3.2; spec R-9, AC-23/AC-24.)
#
# THE DEFECT. A dispatched agent that runs `bash tests/run.sh` with the Bash tool's
# `run_in_background: true` gets a shell id back instead of a result. The suite runs, the
# agent's turn ends, and the evidence the slice was dispatched to produce exists nowhere:
# no file, no transcript, no exit status anyone read. The fix the role files carry in prose
# — foreground, bounded by the Bash tool's own `timeout` parameter, output tee'd to an
# evidence log — is a rule, and a rule that only lives in prose is a wish. This is the wall.
#
# WHAT IT REFUSES. Exactly one shape: a Bash call whose `tool_input.run_in_background` is
# `true` AND whose command is suite-class by payload/scripts/lib/cmd-class.sh. Everything
# else exits 0 in silence — a backgrounded `git status`, a foreground suite, and a suite
# whose `run_in_background` key is simply absent.
#
# ABSENT, NOT FALSE. The CLI omits `run_in_background` from `tool_input` when the caller
# did not set it (@anthropic-ai/claude-code 2.1.251, sdk-tools.d.ts:722 declares it
# optional on the Bash tool input), so the test is `== true` and never `!= false`.
#
# WHERE IT LIVES. hooks/hooks.json, PreToolUse|Bash, BEHIND hooks/agent-context-guard.sh —
# so it is alive only inside an agent context of a session that is armed (design D2, Chris
# 2026-08-30). The main thread is already walled by hooks/farm-out-reminder.sh on the skill
# channel, which refuses a suite there whether backgrounded or not; registering this raw
# as well would refuse background suites in every session on the machine, bionic or not.
# The guard in front owns `agent_id` and the roster; this file re-checks neither, which is
# what lets the positive controls in tests/cmd-class.test.sh drive it straight.
#
# Exit 2 + stderr = block the tool call, the protect-main.sh convention. Exit 0 otherwise.
# [WALL: tests/cmd-class.test.sh]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat) || exit 0
[ -n "$INPUT" ] || exit 0

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''; }

[ "$(_jq '.tool_name')" = "Bash" ] || exit 0
[ "$(_jq '.tool_input.run_in_background|tostring')" = "true" ] || exit 0
COMMAND=$(_jq '.tool_input.command')
[ -n "$COMMAND" ] || exit 0

# ---------- the command reader, sourced FAIL-CLOSED (design D1) ----------
#
# A wall that cannot classify refuses rather than waving work through. The refusal is
# bounded to this arm's own precondition — a call that is not backgrounded left above,
# unread — so a missing library costs backgrounded commands, not every command.
#
# TWO SPELLINGS OF ONE DIRECTORY. payload/hooks is a symlink to <repo>/hooks and `$0` is
# textual, so "../scripts/lib" resolves only when the harness reached this file through
# ${CLAUDE_PLUGIN_ROOT}/hooks/. The repo spelling is the second candidate. Both land on
# payload/scripts/lib/cmd-class.sh — tests/cmd-class.test.sh §C6 pins that.
CMD_CLASS_LIB_WANT="$(dirname "$0")/../scripts/lib/cmd-class.sh"
CMD_CLASS_LIB=""
for _cand in "$CMD_CLASS_LIB_WANT" "$(dirname "$0")/../payload/scripts/lib/cmd-class.sh"; do
  [ -f "$_cand" ] && { CMD_CLASS_LIB="$_cand"; break; }
done
if [ -z "$CMD_CLASS_LIB" ] || ! . "$CMD_CLASS_LIB"; then
  cat >&2 <<EOF
BLOCKED: background-suite-guard cannot read this command — its classifier failed to load
($CMD_CLASS_LIB_WANT). A wall that cannot classify refuses rather than waving a
backgrounded command through.

Fix: restore payload/scripts/lib/cmd-class.sh, or re-install the plugin. Meanwhile run the
command in the FOREGROUND, bounded by the Bash tool's own timeout parameter:

    <command> 2>&1 | tee <evidence log>
EOF
  exit 2
fi

[ "$(cmd_class "$COMMAND")" = "suite" ] || exit 0

# ---------- refuse, naming the shape that works ----------
#
# The command is echoed back so the fix is a copy-paste rather than a retype. It is the
# agent's own text going back to the agent — no third party reads this stream — so it is
# quoted whole rather than scrubbed and truncated the way farm-out-reminder.sh's audit
# line is.
cat >&2 <<EOF
BLOCKED: a suite may not run with run_in_background — nobody would read the result.

A backgrounded suite returns a shell id, not an outcome. Your turn can end before it
finishes, and then the evidence this slice exists to produce lives nowhere: no file, no
exit status anyone saw. Reports are turn-scoped; files are not.

Run it in the FOREGROUND instead, bounded by the Bash tool's own timeout parameter (never
a timeout/gtimeout binary), with the output tee'd to the evidence log your brief names:

    $COMMAND 2>&1 | tee <evidence log>

Then read the log and quote the pass/total line. If the suite is genuinely longer than any
timeout you can set, say so in your report and stop — do not background it.
EOF
exit 2
