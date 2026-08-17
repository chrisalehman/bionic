#!/usr/bin/env bash
# tests/plugin-hooks.test.sh — pins hooks/hooks.json (the plugin-format hook
# manifest, epic-17 wave-01 slice 2) against claude-bootstrap.sh's
# MANAGED_HOOKS array so the two surfaces cannot silently drift while both
# exist.
#
# MANAGED_HOOKS is parsed out of claude-bootstrap.sh AT TEST RUNTIME (never
# copy-pasted here) — the expected hook set is derived from the live array,
# not a snapshot of it. Six pipe-delimited entries: event|matcher|command.
# A blank matcher means the plugin-format group omits the "matcher" key.
#
# Translation rule under test: every occurrence of the literal
# "~/.claude/hooks/" in a MANAGED_HOOKS command is replaced with the literal
# "${CLAUDE_PLUGIN_ROOT}/hooks/" — nothing else about the command string
# changes (order, spacing, trailing args are preserved verbatim).
#
# Usage: bash tests/plugin-hooks.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${REPO}/claude-bootstrap.sh"
HOOKS_JSON="${REPO}/hooks/hooks.json"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "=== Section 0: prerequisites ==="
TOTAL=$((TOTAL + 1))
if command -v jq >/dev/null 2>&1; then
  pass "jq is available"
else
  fail "jq is not available (required to validate hooks.json)"
  echo ""
  echo "========================================"
  echo "Results: $PASS/$TOTAL passed, $FAIL failed"
  echo "========================================"
  exit 1
fi

TOTAL=$((TOTAL + 1))
if [ -f "$HOOKS_JSON" ]; then
  pass "hooks/hooks.json exists"
else
  fail "hooks/hooks.json does not exist at $HOOKS_JSON"
fi

TOTAL=$((TOTAL + 1))
if [ -f "$HOOKS_JSON" ] && jq empty "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks/hooks.json is valid JSON"
else
  fail "hooks/hooks.json is missing or not valid JSON"
  echo ""
  echo "========================================"
  echo "Results: $PASS/$TOTAL passed, $FAIL failed"
  echo "========================================"
  exit 1
fi

TOTAL=$((TOTAL + 1))
if jq -e 'has("hooks") and (.hooks | type == "object")' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks/hooks.json has a top-level .hooks object (plugin hooks.json shape)"
else
  fail "hooks/hooks.json lacks a top-level .hooks object"
  echo ""
  echo "========================================"
  echo "Results: $PASS/$TOTAL passed, $FAIL failed"
  echo "========================================"
  exit 1
fi

echo ""
echo "=== Section 1: derive the expected set from MANAGED_HOOKS (live parse) ==="
TOTAL=$((TOTAL + 1))
managed_hooks_src="$(awk '/^MANAGED_HOOKS=\(/{flag=1} flag{print; if ($0 ~ /^\)/) exit}' "$BOOTSTRAP")"
if [ -n "$managed_hooks_src" ]; then
  pass "MANAGED_HOOKS array block found in claude-bootstrap.sh"
else
  fail "could not locate a MANAGED_HOOKS=( ... ) block in claude-bootstrap.sh"
  echo ""
  echo "========================================"
  echo "Results: $PASS/$TOTAL passed, $FAIL failed"
  echo "========================================"
  exit 1
fi

# The extracted text is a bash array literal of quoted strings only — no
# command substitution, no side effects — so eval'ing it here just defines
# MANAGED_HOOKS in this shell, exactly as claude-bootstrap.sh would.
eval "$managed_hooks_src"

TOTAL=$((TOTAL + 1))
if [ "${#MANAGED_HOOKS[@]}" -eq 6 ]; then
  pass "MANAGED_HOOKS has exactly 6 entries (${#MANAGED_HOOKS[@]} found)"
else
  fail "MANAGED_HOOKS has ${#MANAGED_HOOKS[@]} entries, expected 6 — bootstrap's managed set moved out from under this test"
fi

plugin_prefix='${CLAUDE_PLUGIN_ROOT}/hooks/'

# expect_hook_registered <label> <event> <matcher> <translated-command>
# Passes if hooks.json's .hooks[event] array contains a group whose matcher
# matches (or, for a blank expected matcher, whose group omits "matcher"
# entirely) and whose .hooks array contains a {"type":"command","command":...}
# leaf equal to the expected translated command.
expect_hook_registered() {
  local label="$1" event="$2" matcher="$3" cmd="$4"
  TOTAL=$((TOTAL + 1))
  if jq -e --arg ev "$event" --arg mt "$matcher" --arg cmd "$cmd" '
      (.hooks[$ev] // []) as $groups
      | ($groups | any(
          (($mt == "" and (has("matcher") | not)) or (.matcher? == $mt))
          and ((.hooks // []) | any(.type == "command" and .command == $cmd))
        ))
    ' "$HOOKS_JSON" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label (event=$event matcher='$matcher' command='$cmd' not found as a group in hooks.json)"
  fi
}

echo ""
echo "=== Section 2: each MANAGED_HOOKS entry is registered, translated, in hooks.json ==="
declare -a expected_events=()
entry_num=0
for entry in "${MANAGED_HOOKS[@]}"; do
  entry_num=$((entry_num + 1))
  IFS='|' read -r event matcher cmd <<< "$entry"
  translated_cmd="${cmd//\~\/.claude\/hooks\//$plugin_prefix}"
  expected_events+=("$event")
  expect_hook_registered \
    "entry ${entry_num} (event=${event} matcher='${matcher}') translated and present" \
    "$event" "$matcher" "$translated_cmd"
done

echo ""
echo "=== Section 3: EXACTLY six hooks are registered — no drift, no extras ==="
TOTAL=$((TOTAL + 1))
actual_leaf_count="$(jq '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$HOOKS_JSON" 2>/dev/null)"
if [ "$actual_leaf_count" = "${#MANAGED_HOOKS[@]}" ]; then
  pass "hooks.json registers exactly ${#MANAGED_HOOKS[@]} command hooks (found $actual_leaf_count)"
else
  fail "hooks.json registers $actual_leaf_count command hooks, expected exactly ${#MANAGED_HOOKS[@]} (MANAGED_HOOKS count)"
fi

echo ""
echo "=== Section 4: event set matches exactly — no unmanaged events, none missing ==="
expected_events_sorted="$(printf '%s\n' "${expected_events[@]}" | sort -u)"
actual_events_sorted="$(jq -r '.hooks | keys[]' "$HOOKS_JSON" 2>/dev/null | sort -u)"
TOTAL=$((TOTAL + 1))
if [ "$expected_events_sorted" = "$actual_events_sorted" ]; then
  pass "hooks.json's event set exactly matches MANAGED_HOOKS's event set"
else
  fail "hooks.json event set diverges from MANAGED_HOOKS: expected [$(echo "$expected_events_sorted" | tr '\n' ' ')] got [$(echo "$actual_events_sorted" | tr '\n' ' ')]"
fi

echo ""
echo "=== Section 5: every command path uses \${CLAUDE_PLUGIN_ROOT}/hooks/, none left as ~/.claude/hooks/ ==="
TOTAL=$((TOTAL + 1))
stale_prefix_count="$(grep -c '~/.claude/hooks/' "$HOOKS_JSON" 2>/dev/null || true)"
stale_prefix_count="${stale_prefix_count:-0}"
if [ "$stale_prefix_count" -eq 0 ]; then
  pass "no command in hooks.json still uses the ~/.claude/hooks/ literal"
else
  fail "hooks.json still has $stale_prefix_count occurrence(s) of the literal ~/.claude/hooks/"
fi

TOTAL=$((TOTAL + 1))
all_commands_use_plugin_root="$(jq -r '
    [.hooks | to_entries[] | .value[] | .hooks[] | select(.type == "command") | .command]
    | all(test("\\$\\{CLAUDE_PLUGIN_ROOT\\}/hooks/"))
  ' "$HOOKS_JSON" 2>/dev/null)"
if [ "$all_commands_use_plugin_root" = "true" ]; then
  pass "every command hook's command path uses \${CLAUDE_PLUGIN_ROOT}/hooks/"
else
  fail "at least one command hook's command does not use \${CLAUDE_PLUGIN_ROOT}/hooks/"
fi

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
