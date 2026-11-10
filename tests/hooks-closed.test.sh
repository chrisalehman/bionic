#!/bin/bash
# tests/hooks-closed.test.sh — §CLOSED: each blocking hook with no library exits 2 and says it cannot
# load; beside its library it lets a quiet payload through. Stop and SubagentStop refuse once, since
# exit 2 holds the turn open: the re-entry, no field, a payload that is not JSON and no jq all end it.
# FIXTURE FIDELITY. The shipped hooks, copied; HOME and BIONIC_PLUGINS_DIR in a sandbox, so no healing
# candidate exists. Only the payloads are synthesized.
set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

S="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$S/hooks" "$S/home" "$S/plugins" "$S/nojq"; : > "$S/target.sh"
hc() {  # <hook file> <event> <tool> <stop_hook_active: true|false|null (absent)|raw (not JSON)> [PATH] -> exit status
  { if [ "$4" = raw ]; then printf 'not json'; else jq -nc --arg d "$S" --arg e "$2" --arg t "$3" --argjson a "$4" \
      '{session_id:"hc",cwd:$d,hook_event_name:$e,tool_name:$t,tool_input:{command:"ls",file_path:"\($d)/x.md"},
        agent_id:"a1",stop_hook_active:$a} | if $a == null then del(.stop_hook_active) else . end'; fi; } \
    | (cd "$S" && env HOME="$S/home" BIONIC_PLUGINS_DIR="$S/plugins" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID=hc \
        PATH="${5:-$PATH}" /bin/bash "$1" "$S/target.sh" >/dev/null 2>"$S/err"); echo $?
}

section "CLOSED"
while read -r h ev tool _; do
  cp "$BIONIC_HOOKS_DIR/$h.sh" "$S/hooks/"
  expect_eq "$h, no library: exit 2" 2 "$(hc "$S/hooks/$h.sh" "$ev" "$tool" false)"
  expect_contains "$h, no library: it says it cannot load" "cannot load the bionic library" "$(cat "$S/err")"
  expect_eq "$h, library present, quiet payload: exit 0" 0 "$(hc "$BIONIC_HOOKS_DIR/$h.sh" "$ev" "$tool" false)"
done <<'EOF'
bash-walls PreToolUse Bash
dispatch-preflight PreToolUse Agent
canonical-sdlc-governing-skill PreToolUse Write
stop-guard PreToolUse TaskStop
permission-answer PermissionRequest Bash  exit 2 is not honoured on this event: the dialog shows
stop Stop -
agent-context-guard SubagentStop -
EOF
for h in stop agent-context-guard; do
  for a in true null raw; do expect_eq "$h, no library, stop_hook_active $a: the turn ends" 0 "$(hc "$S/hooks/$h.sh" Stop - "$a")"; done
  expect_eq "$h, no library, no jq: the turn ends" 0 "$(hc "$S/hooks/$h.sh" Stop - false "$S/nojq")"
done

finish
