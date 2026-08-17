#!/usr/bin/env bash
# tests/plugin-hooks.test.sh — pins hooks/hooks.json (the plugin-format hook
# manifest, epic-17 wave-01 slice 2) against claude-bootstrap.sh's
# MANAGED_HOOKS array so the two surfaces cannot silently drift while both
# exist.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ THIS WHOLE FILE RETIRES AT EPIC-17 W5, WITH claude-bootstrap.sh.          │
# │                                                                          │
# │ It is the DESIGNATED TRANSITIONAL HOME (epic-17 wave-02 spec AC-2): the   │
# │ one and only test file allowed to read claude-bootstrap.sh after wave 02. │
# │ Every bootstrap-coupled assertion in the repo lives here, so W5's         │
# │ deletion of the installer is a ONE-SITE deletion — `rm` this file and     │
# │ drop its hand-listed line from tests/run.sh — instead of surgery inside   │
# │ a 3,000-line cross-gate suite.                                            │
# │                                                                          │
# │ Sections 6–9 below were DISPLACED here from                               │
# │ tests/cross-gate-agreement.test.sh §L.2/§L.3/§L.4/§L.6 by wave-02 S3,     │
# │ which made §L payload-pure (it now asserts the same invariants against    │
# │ hooks/hooks.json + SKILL.md frontmatter). Both sides are live on purpose: │
# │ §L asserts the payload, these sections assert the old world, and          │
# │ sections 1–5 pin the two together. Do not "deduplicate" them — deleting   │
# │ a section here un-tests a path that still ships until W5.                 │
# └──────────────────────────────────────────────────────────────────────────┘
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

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
BOOTSTRAP="${BIONIC_SCRIPTS_DIR}/claude-bootstrap.sh"
HOOKS_JSON="${BIONIC_HOOKS_DIR}/hooks.json"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Containment helpers for the displaced sections (6–9). Done IN-PROCESS with `case`,
# never `printf '%s' "$hay" | grep -qF -- "$needle"`: under the `set -o pipefail` above
# that pipe is the race tests/assert-helper-race.test.sh exists to pin — grep exits on
# first match without draining stdin, printf takes SIGPIPE, pipefail promotes 141, and
# the absent-direction helper returns a false GREEN on a needle that is present. Nothing
# here to pin, by construction.
expect_contains_lit() {  # <label> <needle> <haystack>
  TOTAL=$((TOTAL + 1))
  case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 — missing: $2" ;; esac
}
expect_absent_lit() {    # <label> <needle> <haystack>
  TOTAL=$((TOTAL + 1))
  case "$3" in *"$2"*) fail "$1 — unexpectedly present: $2" ;; *) pass "$1" ;; esac
}
expect_equal() {         # <label> <expected> <actual>
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — expected '$2', got '$3'"; fi
}

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

# ==========================================================================
# DISPLACED FROM tests/cross-gate-agreement.test.sh §L — epic-17 wave-02 S3.
#
# Sections 1–5 above derive everything from the live array, which is the right
# shape for an agreement pin: it cannot go stale. Sections 6–9 below are the
# opposite on purpose — they assert the array's CONTENT by verbatim literal and
# by driving the writer, which is what §L used to do and what nothing else in
# the repo does any more. An agreement pin proves the two surfaces MATCH; it
# says nothing about whether the thing they agree on is the right thing. Both
# halves are needed until the old surface is deleted.
# ==========================================================================

echo ""
echo "=== Section 6: MANAGED_HOOKS ABSENCE — the sdlc scripts that went skill-only ==="
# Displaced from §L.2. None of the four sdlc scripts that moved to the SKILL.md
# frontmatter block may appear anywhere in the array bootstrap still converges on at
# install — a lingering entry fires that wall in every session on the machine,
# defeating epic-16 wave-2 R1 even after the frontmatter side is right.
for _script in canonical-sdlc-evidence-gate.sh stop-guard.sh \
               execution-recorder.sh context-spend.sh; do
  expect_absent_lit "MANAGED_HOOKS no longer names $_script (moved to frontmatter)" \
    "hooks/$_script" "$managed_hooks_src"
done
# THE THREE WALLS THAT CAME BACK (session-20260815 T6, then T2) are a conditional
# absence, not an absence: they are named in this array again, and every occurrence must
# sit behind hooks/agent-context-guard.sh. A bare entry is the R1 regression wearing the
# new registration's clothes, and section 9's present-and-guarded checks would still pass
# beside it.
l2_unguarded="$(printf '%s\n' "$managed_hooks_src" \
  | /usr/bin/grep -E 'dispatch-preflight\.sh|canonical-sdlc-governing-skill\.sh|landing-gate\.sh' \
  | /usr/bin/grep -v 'agent-context-guard\.sh')"
expect_equal "…and the three walls that returned are never named UNGUARDED" "" "$l2_unguarded"
# The landing gate is the one wall registered on TWO events across the two channels, so
# its settings entry must not drift onto the event the skill channel already owns: a
# second Stop registration would sweep twice per turn and journal two markers.
expect_equal "…and the landing gate is registered here for SubagentStop alone" "1" \
  "$(printf '%s\n' "$managed_hooks_src" | /usr/bin/grep -c 'landing-gate\.sh')"
expect_equal "…never for Stop, which the skill channel owns" "0" \
  "$(printf '%s\n' "$managed_hooks_src" | /usr/bin/grep -c '"Stop|')"

echo ""
echo "=== Section 7: MANAGED_HOOKS PRESENCE — the irreversible-damage guards, by value ==="
# Displaced from §L.3. The two guards that stay global no matter what skill is armed
# (epic-16 wave-2 R2: guard-set parity), pinned as verbatim array entries — the exact
# set, not just "still there somewhere among leftovers."
expect_contains_lit "MANAGED_HOOKS keeps protect-main.sh on PreToolUse|Bash" \
  '"PreToolUse|Bash|~/.claude/hooks/protect-main.sh"' "$managed_hooks_src"
expect_contains_lit "…protect-database.sh on PreToolUse|Bash" \
  '"PreToolUse|Bash|~/.claude/hooks/protect-database.sh"' "$managed_hooks_src"
# farm-out-reminder.sh moved OUT of this array at session-20260815 T5 (AC-6): unlike the
# three walls above it, it guards a workflow preference rather than irreversible damage,
# so it binds only in armed sessions now, registered once through the skill frontmatter
# with no agent-context twin here.
expect_absent_lit "…and farm-out-reminder.sh is no longer here at all (moved to skill frontmatter, T5)" \
  "hooks/farm-out-reminder.sh" "$managed_hooks_src"
expect_equal "…and exactly six entries total — two unconditional, four guarded" \
  "6" "$(printf '%s\n' "$managed_hooks_src" | /usr/bin/grep -c '"')"

echo ""
echo "=== Section 8: the AGENT-CONTEXT entries are guarded, by value ==="
# Displaced from §L.6. A tool-class event raised inside a teammate or subagent context is
# dispatched under the AGENT key and never reaches a skill-frontmatter registration, so
# the dispatch wall, the artifact wall and the landing verdict are registered a SECOND
# time through settings — behind hooks/agent-context-guard.sh, which runs the named wall
# only for a payload carrying a top-level agent_id in a session that has a roster on disk.
# Pinned by verbatim value: an entry that pointed straight at a wall would fire it in
# every session on the machine.
expect_contains_lit "MANAGED_HOOKS registers the DISPATCH wall for agent contexts, behind the guard" \
  '"PreToolUse|Agent|~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/dispatch-preflight.sh"' \
  "$managed_hooks_src"
expect_contains_lit "…the ARTIFACT wall on Write, behind the guard" \
  '"PreToolUse|Write|~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/canonical-sdlc-governing-skill.sh"' \
  "$managed_hooks_src"
expect_contains_lit "…and on Edit, behind the guard" \
  '"PreToolUse|Edit|~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/canonical-sdlc-governing-skill.sh"' \
  "$managed_hooks_src"
expect_contains_lit "…and the LANDING verdict on SubagentStop, behind the guard" \
  '"SubagentStop||~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/landing-gate.sh"' \
  "$managed_hooks_src"

echo ""
echo "=== Section 9: DRIVEN — what wire_managed_hooks actually WRITES ==="
# Displaced from §L.4 + §L.6's driven half.
#
# The epic-16 Step-6 review's C-4: wire_managed_hooks attached `"timeout": 10` only on the
# matcher branch, so the two events that wave added — the ones that carry no matcher —
# registered with no ceiling at all, and the platform default was the only thing in front
# of the landing gate's verdict subprocess. A timeout is the safe direction precisely
# because the gate is fail-open: a hook that is killed lets the stop through.
#
# Driven rather than grepped: the real function is extracted from the real script and run
# against a sandboxed settings file, the same convention tests/installer-behavior.test.sh
# uses — so this asserts what bootstrap WRITES, not what its source looks like.
WSBX="$(mktemp -d "${TMPDIR:-/tmp}/plugin-hooks-wire.XXXXXX")"
trap 'rm -rf "$WSBX"' EXIT
WCODE="$WSBX/wire.sh"
awk '/^wire_managed_hooks\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP" > "$WCODE"
awk '/^MANAGED_HOOKS=\(/{f=1} f{print} f&&/^\)$/{exit}' "$BOOTSTRAP" >> "$WCODE"
WSETTINGS="$WSBX/settings.json"
echo '{}' > "$WSETTINGS"
# shellcheck disable=SC1090
( . "$WCODE"; settings="$WSETTINGS"; wire_managed_hooks ) >/dev/null 2>&1
w_rc=$?
expect_equal "wire_managed_hooks runs against a sandboxed settings file" "0" "$w_rc"
expect_equal "…and registers every managed hook (this section is not vacuous)" \
  "${#MANAGED_HOOKS[@]}" \
  "$(jq '[.hooks[][].hooks[]] | length' "$WSETTINGS" 2>/dev/null)"
expect_equal "EVERY registered hook carries a timeout — the no-matcher branch included" "0" \
  "$(jq '[.hooks[][].hooks[] | select(has("timeout") | not)] | length' "$WSETTINGS" 2>/dev/null)"
# What bootstrap writes for a guarded entry is ONE command string carrying both paths,
# with its matcher and its timeout — the shape the harness executes through a shell, and
# the shape that hands the guard its argument.
w_agent_cmds="$(jq -r '.hooks.PreToolUse[]? | select(.matcher=="Agent") | .hooks[].command' "$WSETTINGS" 2>/dev/null)"
expect_contains_lit "wire_managed_hooks writes the guarded dispatch entry as ONE command with the wall as its argument" \
  "agent-context-guard.sh ~/.claude/hooks/dispatch-preflight.sh" "$w_agent_cmds"
expect_equal "…and the guarded entries are bounded by the same timeout: 10" "0" \
  "$(jq '[.hooks.PreToolUse[]? | select(.matcher=="Agent" or .matcher=="Write" or .matcher=="Edit")
         | .hooks[] | select(.timeout != 10)] | length' "$WSETTINGS" 2>/dev/null)"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
