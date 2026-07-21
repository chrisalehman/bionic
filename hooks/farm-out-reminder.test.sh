#!/bin/bash
# Tests for hooks/farm-out-reminder.sh — fixture stdin replays the REAL
# captured PreToolUse JSON shape (epic-08 Q1 spike, scrubbed).
#
# Slice 4/1 sections: negatives (N1-N8) + invariants (I1-I6). Classifier
# arms (tier-1 deny, tier-2 nudge, cooldown) land in 4/2-4/3; their D/W/T/
# G/M/O/A cases append to this file then. N8's deny is deferred to 4/2 (R8′)
# — here it only proves missing-keys classifies as main and stays silent
# under the skeleton (no classifier yet).
#
# Usage: bash hooks/farm-out-reminder.test.sh
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/farm-out-reminder.sh"
PASS=0; FAIL=0; TOTAL=0
pass() { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "FAIL: $1" >&2; }

SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]:-}"; do [ -n "$d" ] && chmod -R u+rwx "$d" 2>/dev/null; rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

setup() {  # fresh sandbox project per case
  SANDBOX=$(mktemp -d); mkdir -p "$SANDBOX/.bionic/tmp" "$SANDBOX/.bionic/memory"
  SANDBOXES+=("$SANDBOX")
}
audit_file() { printf '%s' "$SANDBOX/.bionic/memory/sdlc-v11-audit.md"; }

stdin_for() {  # $1=command $2=agent_type ("" = main thread)
  local at=""
  [ -n "${2:-}" ] && at=",\"agent_id\":\"a-fixture-$2\",\"agent_type\":\"$2\""
  printf '{"session_id":"s-fixture","transcript_path":"/tmp/t.jsonl","cwd":"%s","prompt_id":"p-1","permission_mode":"bypassPermissions"%s,"effort":{"level":"high"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s,"description":"fixture"},"tool_use_id":"toolu_fixture"}' \
    "$SANDBOX" "$at" "$(printf '%s' "$1" | jq -Rs .)"
}

run_hook() {  # stdin on $1
  HOOK_STDOUT=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$SANDBOX" bash "$HOOK" 2>/dev/null)
  HOOK_EXIT=$?
}

assert_exit0()  { [ "$HOOK_EXIT" -eq 0 ] && pass || fail "$1 (exit=$HOOK_EXIT)"; }
assert_silent() { [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDOUT" ] && pass || fail "$1 (exit=$HOOK_EXIT out=$HOOK_STDOUT)"; }
assert_deny()   { printf '%s' "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 && pass || fail "$1"; }
assert_reason_has() { printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null | grep -qF "$2" && pass || fail "$1"; }
assert_nudge()  { printf '%s' "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && pass || fail "$1"; }
assert_no_decision() { printf '%s' "$HOOK_STDOUT" | grep -qv '"permissionDecision"' && pass || fail "$1"; }
assert_audit_has()   { grep -qF "$2" "$(audit_file)" 2>/dev/null && pass || fail "$1"; }
assert_audit_absent(){ ! grep -qF "$2" "$(audit_file)" 2>/dev/null && pass || fail "$1"; }

# ============================================================
# Negatives (AC-2) — main-thread exempt/unmatched + subagent
# early-exit + missing-keys. All silent under the skeleton.
# ============================================================

echo ""
echo "=== N1: git status (main) → silent, no audit ==="
n1() {
  setup
  run_hook "$(stdin_for 'git status' '')"
  assert_silent "N1 git status main → silent"
  assert_audit_absent "N1 no audit line" "farm-out"
}
n1

echo ""
echo "=== N2: ls -la hooks/ (main) → silent ==="
n2() {
  setup
  run_hook "$(stdin_for 'ls -la hooks/' '')"
  assert_silent "N2 ls main → silent"
}
n2

echo ""
echo "=== N3: cat hooks/context-spend.sh (main) → silent ==="
n3() {
  setup
  run_hook "$(stdin_for 'cat hooks/context-spend.sh' '')"
  assert_silent "N3 cat main → silent"
}
n3

echo ""
echo "=== N4: grep -rn foo hooks/ (main) → silent ==="
n4() {
  setup
  run_hook "$(stdin_for 'grep -rn foo hooks/' '')"
  assert_silent "N4 grep main → silent"
}
n4

echo ""
echo "=== N5: bash test.sh, agent_type=test-runner → silent (early exit) ==="
n5() {
  setup
  run_hook "$(stdin_for 'bash test.sh' 'test-runner')"
  assert_silent "N5 subagent early-exit → silent"
  assert_audit_absent "N5 no audit line" "farm-out"
}
n5

echo ""
echo "=== N6: ./claude-bootstrap.sh, agent_type=implementor → silent ==="
n6() {
  setup
  run_hook "$(stdin_for './claude-bootstrap.sh' 'implementor')"
  assert_silent "N6 subagent early-exit → silent"
}
n6

echo ""
echo "=== N7: unmatched exotic (openssl rand -hex 8) (main) → silent ==="
n7() {
  setup
  run_hook "$(stdin_for 'openssl rand -hex 8' '')"
  assert_silent "N7 unmatched exotic → silent"
}
n7

echo ""
echo "=== N8: missing agent_type key entirely (real main JSON) → main, silent here (deny re-asserted 4/2 R8′) ==="
n8() {
  setup
  run_hook "$(stdin_for 'bash test.sh' '')"   # stdin_for '' omits agent_id/agent_type keys entirely
  assert_silent "N8 missing-keys classifies main, silent under skeleton"
}
n8

# ============================================================
# Invariants (AC-3) — exit 0 on EVERY path; stdout stays the
# JSON contract only (empty here, no classifier).
# ============================================================

echo ""
echo "=== I1: empty stdin → exit 0, no stdout ==="
i1() {
  setup
  run_hook ""
  assert_silent "I1 empty stdin → exit 0 + empty stdout"
}
i1

echo ""
echo "=== I2: malformed stdin (not-json) → exit 0, no stdout ==="
i2() {
  setup
  run_hook "not-json"
  assert_silent "I2 malformed stdin → exit 0 + empty stdout"
}
i2

echo ""
echo "=== I3: CRLF/CR line endings in command → exit 0 ==="
i3() {
  setup
  local crlf; crlf=$(printf 'echo hi\r\necho mid\recho bye')
  run_hook "$(stdin_for "$crlf" '')"
  assert_exit0 "I3 CR/CRLF command → exit 0"
}
i3

echo ""
echo "=== I4: farm-out-mode: off + bash test.sh → silent, no audit ==="
i4() {
  setup
  printf 'farm-out-mode: off\n' > "$SANDBOX/.bionic/config.yaml"
  run_hook "$(stdin_for 'bash test.sh' '')"
  assert_silent "I4 mode=off → silent"
  assert_audit_absent "I4 no audit line" "farm-out"
}
i4

echo ""
echo "=== I5: unwritable .bionic/memory (chmod 555) at a logging path → exit 0 still ==="
i5() {
  setup
  chmod 555 "$SANDBOX/.bionic/memory"
  run_hook "$(stdin_for 'bash test.sh' '')"
  assert_exit0 "I5 unwritable memory dir → exit 0"
  chmod u+rwx "$SANDBOX/.bionic/memory" 2>/dev/null || true
}
i5

echo ""
echo "=== I6: tool_name != Bash → silent ==="
i6() {
  setup
  local j; j=$(printf '{"session_id":"s-fixture","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"x"}}' "$SANDBOX")
  run_hook "$j"
  assert_silent "I6 tool_name != Bash → silent"
}
i6

# ============================================================
# Results
# ============================================================
echo ""
echo "farm-out-reminder: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
