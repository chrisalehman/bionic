#!/bin/bash
# tests/hooks-closed.test.sh — §CLOSED: each blocking hook with no library exits 2 and says it cannot
# load; beside its library it lets a quiet payload through. Stop and SubagentStop refuse once, since
# exit 2 holds the turn open: the re-entry, no field, a payload that is not JSON and no jq all end it.
# §OPEN: each advisory hook alone passes, saying it steps aside. §REPAIR: the Bash wall alone admits the four
# commands that mend an install, and the four its verbose refusal names are the four it admits. Every hook holds
# the loader's stub, so a hook alone is a hook with no loader beside it.
# FIXTURE FIDELITY. The shipped hooks, copied; HOME and BIONIC_PLUGINS_DIR in a sandbox, so no healing
# candidate exists. Only the payloads are synthesized.
set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

S="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$S/hooks" "$S/home" "$S/plugins" "$S/nojq"
hc() {  # <hook file> <event> <tool> <stop_hook_active: true|false|null (absent)|raw (not JSON)> [PATH] -> exit status
  { if [ "$4" = raw ]; then printf 'not json'; else jq -nc --arg d "$S" --arg e "$2" --arg t "$3" --argjson a "$4" \
      '{session_id:"hc",cwd:$d,hook_event_name:$e,tool_name:$t,tool_input:{command:"ls",file_path:"\($d)/x.md"},
        agent_id:"a1",stop_hook_active:$a} | if $a == null then del(.stop_hook_active) else . end'; fi; } \
    | (cd "$S" && env HOME="$S/home" BIONIC_PLUGINS_DIR="$S/plugins" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID=hc \
        PATH="${5:-$PATH}" /bin/bash "$1" >/dev/null 2>"$S/err"); echo $?
}

section "CLOSED"
while read -r h ev tool _; do
  cp "$BIONIC_HOOKS_DIR/$h.sh" "$S/hooks/"
  expect_eq "$h on $ev, no library: exit 2" 2 "$(hc "$S/hooks/$h.sh" "$ev" "$tool" false)"
  expect_contains "$h on $ev, no library: it says it cannot load" "cannot load the bionic library" "$(cat "$S/err")"
  expect_eq "$h on $ev, library present, quiet payload: exit 0" 0 "$(hc "$BIONIC_HOOKS_DIR/$h.sh" "$ev" "$tool" false)"
done <<'EOF'
bash-walls PreToolUse Bash
dispatch-preflight PreToolUse Agent
canonical-sdlc-governing-skill PreToolUse Write
permission-answer PermissionRequest Bash  exit 2 is not honoured on this event: the dialog shows
stop Stop -
stop SubagentStop -
EOF
# THE PERSON'S REFUSAL KEEPS ITS CHANNEL (fails-when: the broken install's refusal at a turn end loses its words on the
# person's stream; its exit 2 is the row above).
hc "$S/hooks/stop.sh" Stop - false >/dev/null
expect_eq "stop on Stop, no library: the person's line, whole, on the person's stream" \
  "bionic: load refused — stop cannot load the bionic library (run /bionic:doctor)" "$(cat "$S/err")"
for ev in Stop SubagentStop; do
  for a in true null raw; do expect_eq "stop on $ev, no library, stop_hook_active $a: the turn ends" 0 "$(hc "$S/hooks/stop.sh" "$ev" - "$a")"; done
  expect_eq "stop on $ev, no library, no jq: the turn ends" 0 "$(hc "$S/hooks/stop.sh" "$ev" - false "$S/nojq")"
done


# ha <hook file> <payload> [args...] -> exit status; stdout in $S/out, stderr in $S/err
ha() {
  local f="$1" p="$2"; shift 2
  printf '%s' "$p" | (cd "$S" && env HOME="$S/home" BIONIC_PLUGINS_DIR="$S/plugins" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID=hc \
    /bin/bash "$f" "$@" >"$S/out" 2>"$S/err"); echo $?
}
STUB="$( . "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/loader.sh" && bionic_loader_pin | sed -n '4p')"
expect_contains "the stub's line that sources the loader is read" '. "$_bl_l"; bionic_load' "$STUB"
expect_eq "each of the fourteen hooks holds it" 14 "$(cd "$BIONIC_HOOKS_DIR" && /usr/bin/grep -lxF -- "$STUB" bash-walls.sh \
  canonical-sdlc-governing-skill.sh dispatch-preflight.sh engage.sh execution-recorder.sh permission-answer.sh preflight-probe.sh \
  session-poker.sh session-start.sh session-sweeper.sh stop-check.sh stop-orders.sh stop.sh watch.sh | wc -l | tr -d ' ')"

section "OPEN"
while IFS='|' read -r h p a; do
  cp "$BIONIC_HOOKS_DIR/$h.sh" "$S/hooks/"
  # shellcheck disable=SC2086
  expect_eq "$h, no library: exit 0" 0 "$(ha "$S/hooks/$h.sh" "$p" $a)"
  expect_contains "$h, no library: it says it steps aside" "$h: library " "$(cat "$S/err")"
  expect_eq "$h, no library: nothing on stdout" "" "$(cat "$S/out")"
done <<EOF
engage|{"session_id":"hc","cwd":"$S","hook_event_name":"UserPromptExpansion","command_name":"canonical-sdlc"}|
execution-recorder|{"session_id":"hc","cwd":"$S","hook_event_name":"SubagentStart","agent_id":"a1","agent_type":"x"}|
preflight-probe||
session-poker||adopt
session-start|{"session_id":"hc","cwd":"$S","hook_event_name":"SessionStart","source":"startup"}|
session-sweeper||verdict
stop-check||no-such-agent
stop-orders||stopped no-such-agent
watch|{"session_id":"hc","cwd":"$S","hook_event_name":"Stop","stop_hook_active":false}|
EOF

section "REPAIR"
cp "$BIONIC_HOOKS_DIR/bash-walls.sh" "$S/hooks/"
bw() { ha "$1" "$(jq -nc --arg d "$S" --arg c "$2" '{session_id:"hc",cwd:$d,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"; }
for c in "claude plugin update bionic@bionic" "claude plugin install bionic@bionic" "bash $S/scripts/doctor.sh" "bash $S/scripts/setup.sh"; do
  expect_eq "bash-walls, no library: '$c' passes" 0 "$(bw "$S/hooks/bash-walls.sh" "$c")"
  expect_eq "…in silence" "" "$(cat "$S/err")"
done
expect_eq "bash-walls, no library: a repair with a push chained after it is refused" 2 "$(bw "$S/hooks/bash-walls.sh" "bash $S/scripts/doctor.sh; git push origin main")"
# Beside a lib/ holding only the loader, the verbose refusal names the commands; each named one passes.
mkdir -p "$S/lo/hooks" "$S/lo/scripts/lib"; cp "$BIONIC_HOOKS_DIR/bash-walls.sh" "$S/lo/hooks/"; cp "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/loader.sh" "$S/lo/scripts/lib/"
NAMED="$(BIONIC_WALL_VERBOSE=1 bw "$S/lo/hooks/bash-walls.sh" ls >/dev/null; sed -n 's/^    \(.*[a-z]\)$/\1/p' "$S/err")"
expect_eq "bash-walls, loader alone: the verbose refusal names four commands" 4 "$(printf '%s\n' "$NAMED" | grep -c .)"
while IFS= read -r c; do expect_eq "…and '$c', as named, passes" 0 "$(bw "$S/lo/hooks/bash-walls.sh" "$c")"; done <<EOF
$NAMED
EOF

finish
