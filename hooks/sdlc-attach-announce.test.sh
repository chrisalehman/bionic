#!/bin/bash
# Tests for sdlc-attach-announce.sh — SessionStart(resume) hook (wave-keepalive
# S10, spec R12/AC-13, design KA-R15). Verifies the hook announces the attach
# hand-off on a watchdog-armed cwd match, stays silent otherwise, and never
# exits nonzero regardless of how malformed the inputs are.
#
# Usage: bash hooks/sdlc-attach-announce.test.sh

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/sdlc-attach-announce.sh"
ANNOUNCEMENT="Autopilot paused — you have the conn while attached. Exit, and autopilot resumes within ~3 minutes."
PASS=0
FAIL=0
TOTAL=0

# ---------- fixture planters ----------

cleanup_homes=()
cleanup() { for d in "${cleanup_homes[@]}"; do rm -rf "$d"; done; }
trap cleanup EXIT

# make_home — a fresh sandbox $HOME with an empty sdlc-goals dir.
make_home() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.claude/sdlc-goals"
  cleanup_homes+=("$dir")
  echo "$dir"
}

# plant_goal <home> <gid> <plan> <cwd> <sid> [drop-key]
plant_goal() {
  local home="$1" gid="$2" plan="$3" cwd="$4" sid="$5" drop="${6:-}"
  local f="$home/.claude/sdlc-goals/$gid"
  {
    [ "$drop" = "PLAN" ]       || echo "PLAN=$plan"
    [ "$drop" = "CWD" ]        || echo "CWD=$cwd"
    [ "$drop" = "SESSION_ID" ] || echo "SESSION_ID=$sid"
    echo "PID=4242"
    echo "ARMED_AT=2026-07-21T00:00:00Z"
  } > "$f"
}

# plant_goal_cronly <home> <gid> <plan> <cwd> <sid> — CR-only line endings
# (no \n at all), the old-Mac shape S10's normalize_nl must still parse.
plant_goal_cronly() {
  local home="$1" gid="$2" plan="$3" cwd="$4" sid="$5"
  local f="$home/.claude/sdlc-goals/$gid"
  printf 'PLAN=%s\rCWD=%s\rSESSION_ID=%s\rPID=4242\rARMED_AT=2026-07-21T00:00:00Z\r' \
    "$plan" "$cwd" "$sid" > "$f"
}

# plant_plan <path> [scale] [watchdog] [pilot]
# Empty watchdog/pilot ⇒ the key is ABSENT from frontmatter (fallback-table
# resolution applies) — mirrors sdlc-poker.test.sh's plant_plan convention.
plant_plan() {
  local p="$1" scale="${2:-wave}" wd="${3:-}" pilot="${4:-}"
  mkdir -p "$(dirname "$p")"
  {
    echo "---"
    echo "governing-skill: superpowers:writing-plans"
    echo "canonical_sdlc_version: 12"
    echo "scale: $scale"
    [ -n "$wd" ] && echo "watchdog: $wd"
    [ -n "$pilot" ] && echo "pilot: $pilot"
    echo "---"
    echo ""
    echo "## SDLC State"
    echo ""
    echo "current: 3"
  } > "$p"
}

# plant_plan_cronly <path> <scale> <watchdog> <pilot> — CR-only frontmatter.
plant_plan_cronly() {
  local p="$1" scale="$2" wd="$3" pilot="$4"
  mkdir -p "$(dirname "$p")"
  printf -- '---\rscale: %s\rwatchdog: %s\rpilot: %s\r---\r\r## SDLC State\r\rcurrent: 3\r' \
    "$scale" "$wd" "$pilot" > "$p"
}

# run_hook <home> <json-stdin>
run_hook() {
  local home="$1" input="$2"
  HOOK_STDOUT=$(HOME="$home" bash "$HOOK" <<< "$input" 2>/dev/null)
  HOOK_EXIT=$?
}

expect_silent() {
  local label="$1" home="$2" input="$3"
  TOTAL=$((TOTAL + 1))
  run_hook "$home" "$input"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDOUT" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected silent exit 0): $label"
    echo "  exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
    FAIL=$((FAIL + 1))
  fi
}

expect_announcement() {
  local label="$1" home="$2" input="$3"
  TOTAL=$((TOTAL + 1))
  run_hook "$home" "$input"
  if [ "$HOOK_EXIT" -ne 0 ]; then
    echo "FAIL (exit=$HOOK_EXIT): $label"
    echo "  stdout='$HOOK_STDOUT'"
    FAIL=$((FAIL + 1))
    return
  fi
  local ctx name
  ctx=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  name=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
  if [ -z "$ctx" ]; then
    echo "FAIL (no additionalContext): $label"
    echo "  stdout='$HOOK_STDOUT'"
    FAIL=$((FAIL + 1))
    return
  fi
  if [ "$name" != "SessionStart" ]; then
    echo "FAIL (hookEventName='$name'): $label"
    FAIL=$((FAIL + 1))
    return
  fi
  if echo "$ctx" | grep -qF "$ANNOUNCEMENT"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (context missing announcement sentence): $label"
    echo "  context='$ctx'"
    FAIL=$((FAIL + 1))
  fi
}

expect_status_line_contains() {
  local label="$1" home="$2" input="$3" needle="$4"
  TOTAL=$((TOTAL + 1))
  run_hook "$home" "$input"
  local ctx
  ctx=$(echo "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  if echo "$ctx" | grep -qF "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (status line missing '$needle'): $label"
    echo "  context='$ctx'"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# (a) armed-goal cwd match → announcement present, status line populated
# ============================================================
echo ""
echo "=== (a) armed-goal cwd match ==="

h1=$(make_home)
plan1="$h1/plans/wave-keepalive.plan.md"
plant_plan "$plan1" wave on auto
plant_goal "$h1" goal-armed-1 "$plan1" /proj/one sess-1

expect_announcement "same-session resume of an armed goal announces" \
  "$h1" '{"session_id":"sess-1","cwd":"/proj/one"}'
expect_status_line_contains "status line carries the goal id" \
  "$h1" '{"session_id":"sess-1","cwd":"/proj/one"}' "goal-armed-1"
expect_status_line_contains "status line carries the plan path" \
  "$h1" '{"session_id":"sess-1","cwd":"/proj/one"}' "$plan1"
expect_status_line_contains "status line carries the pilot value" \
  "$h1" '{"session_id":"sess-1","cwd":"/proj/one"}' "auto"

# Successor/poked session: different session id, same cwd, plan still armed
# (watchdog-effective=on) — must still announce (KA-R16 successor spine).
expect_announcement "different-session cwd match on an armed plan still announces" \
  "$h1" '{"session_id":"sess-SUCCESSOR","cwd":"/proj/one"}'

# ============================================================
# (b) unarmed cwd → silent, rc 0
# ============================================================
echo ""
echo "=== (b) unarmed cwd ==="

h2=$(make_home)
expect_silent "no registration at all → silent" \
  "$h2" '{"session_id":"sess-2","cwd":"/proj/nowhere"}'

plan2="$h2/plans/task.plan.md"
plant_plan "$plan2" task off manual
plant_goal "$h2" goal-unarmed "$plan2" /proj/two sess-2b

expect_silent "cwd matches but watchdog explicit off, different session → silent" \
  "$h2" '{"session_id":"sess-2","cwd":"/proj/two"}'

plan2c="$h2/plans/absent-flags.plan.md"
plant_plan "$plan2c" task
plant_goal "$h2" goal-fallback-off "$plan2c" /proj/three sess-3b

expect_silent "cwd matches, flags absent, non-continuous scale fallback=off → silent" \
  "$h2" '{"session_id":"sess-3","cwd":"/proj/three"}'

# ============================================================
# (c) malformed record → silent rc 0
# ============================================================
echo ""
echo "=== (c) malformed record ==="

h3=$(make_home)
plan3="$h3/plans/armed.plan.md"
plant_plan "$plan3" wave on manual
plant_goal "$h3" goal-noplan "$plan3" /proj/malformed sess-9 PLAN

expect_silent "record missing PLAN key → silent" \
  "$h3" '{"session_id":"sess-9","cwd":"/proj/malformed"}'

plant_goal "$h3" goal-badplan "$h3/plans/does-not-exist.plan.md" /proj/malformed2 sess-10
expect_silent "record PLAN points at a nonexistent file, different session → silent" \
  "$h3" '{"session_id":"sess-DIFFERENT","cwd":"/proj/malformed2"}'

plant_goal "$h3" goal-nocwd "$plan3" /proj/malformed3 sess-11 CWD
expect_silent "record missing CWD key → silent" \
  "$h3" '{"session_id":"sess-11","cwd":"/proj/malformed3"}'

# ============================================================
# (d) missing/garbled stdin JSON → silent rc 0
# ============================================================
echo ""
echo "=== (d) missing/garbled stdin JSON ==="

h4=$(make_home)
plan4="$h4/plans/armed.plan.md"
plant_plan "$plan4" wave on auto
plant_goal "$h4" goal-armed-4 "$plan4" /proj/four sess-4

expect_silent "empty stdin → silent" "$h4" ""
expect_silent "garbled non-JSON stdin → silent" "$h4" "not json {{{ at all"
expect_silent "valid JSON missing cwd key → silent" "$h4" '{"session_id":"sess-4"}'
expect_silent "JSON with null cwd → silent" "$h4" '{"session_id":"sess-4","cwd":null}'

# ============================================================
# (e) never nonzero — re-assert exit 0 across every scenario shape above
# ============================================================
echo ""
echo "=== (e) never nonzero ==="

_assert_rc0() {
  local label="$1" home="$2" input="$3"
  TOTAL=$((TOTAL + 1))
  run_hook "$home" "$input"
  if [ "$HOOK_EXIT" -eq 0 ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (exit=$HOOK_EXIT, expected 0): $label"
    FAIL=$((FAIL + 1))
  fi
}

_assert_rc0 "armed match never nonzero" "$h1" '{"session_id":"sess-1","cwd":"/proj/one"}'
_assert_rc0 "unarmed cwd never nonzero" "$h2" '{"session_id":"sess-2","cwd":"/proj/two"}'
_assert_rc0 "malformed record never nonzero" "$h3" '{"session_id":"sess-9","cwd":"/proj/malformed"}'
_assert_rc0 "garbled stdin never nonzero" "$h4" "not json {{{ at all"

h5=$(make_home)
rm -rf "$h5/.claude/sdlc-goals"
_assert_rc0 "missing goals dir entirely never nonzero" "$h5" '{"session_id":"s","cwd":"/proj/anything"}'

# ============================================================
# (f) CR-only line-ending record handled
# ============================================================
echo ""
echo "=== (f) CR-only line-ending record ==="

h6=$(make_home)
plan6="$h6/plans/cronly.plan.md"
plant_plan_cronly "$plan6" wave on auto
plant_goal_cronly "$h6" goal-cronly "$plan6" /proj/cronly sess-cr

expect_announcement "CR-only registration + CR-only plan frontmatter still announce" \
  "$h6" '{"session_id":"sess-cr","cwd":"/proj/cronly"}'
expect_status_line_contains "CR-only record status line carries pilot value" \
  "$h6" '{"session_id":"sess-cr","cwd":"/proj/cronly"}' "auto"

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
