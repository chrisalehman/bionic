#!/bin/bash
# Tests for context-spend.sh Stop hook.
# Emission section (AC-1): one context-spend line per SDLC step boundary,
# correct format/attribution/delta arithmetic, silence on non-boundaries.
#
# Harness idiom mirrors memory-cleanup.test.sh: PASS/FAIL counters, mktemp
# projects, run_hook via CLAUDE_PROJECT_DIR. Fixtures replay the REAL Stop
# stdin JSON + assistant transcript entry captured in slice 4/1 (scrubbed):
#   stdin  keys: session_id, transcript_path, cwd, hook_event_name, stop_hook_active
#   entry: message.model + message.usage with top-level token fields AND iterations[]
#
# Usage: bash hooks/context-spend.test.sh

set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/context-spend.sh"
PASS=0; FAIL=0; TOTAL=0

# ---------- helpers ----------

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

# Write a plan with `current: $step` under a chosen relative path.
write_plan() {  # $1=dir $2=step  [$3=rel-plan-path]
  local dir="$1" step="$2" rel="${3:-epic-t/wave-t.plan.md}"
  mkdir -p "$dir/.bionic/docs/plans/$(dirname "$rel")"
  cat > "$dir/.bionic/docs/plans/$rel" <<EOF
---
governing-skill: superpowers:writing-plans
---
## SDLC State

integration-branch: main
current: $step

- Step 0: ok
EOF
}

# Write a transcript whose LAST assistant entry has the given top-level usage.
# iterations[] carry deliberately-divergent tiny numbers (never summed).
write_transcript() {  # $1=dir $2=input $3=cache_c $4=cache_r
  local dir="$1" input="$2" cache_c="$3" cache_r="$4"
  cat > "$dir/transcript.jsonl" <<EOF
{"type":"user","message":"scrubbed"}
{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":$input,"cache_creation_input_tokens":$cache_c,"cache_read_input_tokens":$cache_r,"output_tokens":50,"iterations":[{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}]}}}
EOF
}

# make_env: scratch project + plan (current: $1) + transcript (occupied sum
# $2+$3+$4). Returns project dir.
make_env() {  # $1=step $2=input $3=cache_c $4=cache_r
  local step="$1" input="$2" cache_c="$3" cache_r="$4"
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/memory"
  write_plan "$dir" "$step"
  write_transcript "$dir" "$input" "$cache_c" "$cache_r"
  echo "$dir"
}

stdin_for() {  # $1=project $2=transcript-path — real captured shape, paths swapped
  printf '{"session_id":"scrubbed","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$2" "$1"
}

run_hook() {  # $1=project $2=stdin-json
  HOOK_STDOUT=$(CLAUDE_PROJECT_DIR="$1" bash "$HOOK" <<< "$2" 2>/dev/null); HOOK_EXIT=$?
}

fire() {  # $1=project — build real-shape stdin and run
  run_hook "$1" "$(stdin_for "$1" "$1/transcript.jsonl")"
}

audit_of() { cat "$1/.bionic/memory/sdlc-v11-audit.md" 2>/dev/null || true; }
state_of() { cat "$1/.bionic/tmp/context-spend.state" 2>/dev/null || true; }

cleanup_projects=()
cleanup() { for d in "${cleanup_projects[@]:-}"; do rm -rf "$d"; done; }
trap cleanup EXIT

# ============================================================
# Emission section (AC-1)
# ============================================================

echo ""
echo "=== E1: first-seen at current:4 — no line, state seeded ==="
e1() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local plan="$dir/.bionic/docs/plans/epic-t/wave-t.plan.md"
  fire "$dir"
  TOTAL=$((TOTAL + 1))
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$(audit_of "$dir")" ]; then
    pass "E1 first-seen: exit 0, no audit line"
  else
    fail "E1 first-seen: expected silent no-line" "exit=$HOOK_EXIT audit='$(audit_of "$dir")'"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$(state_of "$dir")" = "$(printf '%s\t4\t100000' "$plan")" ]; then
    pass "E1 first-seen: state seeded plan<TAB>4<TAB>100000"
  else
    fail "E1 first-seen: state seed" "state='$(state_of "$dir")'"
  fi
}
e1

echo ""
echo "=== E2: unchanged step — still no line, state untouched ==="
e2() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"; local st1; st1=$(state_of "$dir")
  fire "$dir"
  TOTAL=$((TOTAL + 1))
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$(audit_of "$dir")" ]; then
    pass "E2 unchanged step: still no line"
  else
    fail "E2 unchanged step: expected no line" "audit='$(audit_of "$dir")'"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$(state_of "$dir")" = "$st1" ]; then
    pass "E2 unchanged step: state unchanged"
  else
    fail "E2 unchanged step: state changed" "before='$st1' after='$(state_of "$dir")'"
  fi
}
e2

echo ""
echo "=== E3: boundary 4->5 — exactly one line, format, +delta ==="
e3() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local plan="$dir/.bionic/docs/plans/epic-t/wave-t.plan.md"
  fire "$dir"                        # seed at step 4, occ 100000
  write_plan "$dir" 5
  write_transcript "$dir" 142137 0 0
  fire "$dir"                        # boundary: step 4 ended, occ 142137
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  local n; n=$(printf '%s\n' "$audit" | grep -c 'context-spend step-')
  if [ "$n" -eq 1 ]; then
    pass "E3 boundary: exactly one line"
  else
    fail "E3 boundary: line count" "n=$n audit='$audit'"
  fi
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -qE '^- [0-9TZ:-]+ context-spend step-4: occupied=142137 delta=\+42137 model=claude-fable-5 \(.*wave-t\.plan\.md\)$'; then
    pass "E3 boundary: full line format + ended-step attribution + delta"
  else
    fail "E3 boundary: format mismatch" "audit='$audit'"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$(state_of "$dir")" = "$(printf '%s\t5\t142137' "$plan")" ]; then
    pass "E3 boundary: state advanced to 5<TAB>142137"
  else
    fail "E3 boundary: state advance" "state='$(state_of "$dir")'"
  fi
}
e3

echo ""
echo "=== E4: boundary with compaction — negative delta ==="
e4() {
  local dir; dir=$(make_env 5 142137 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed at step 5, occ 142137
  write_plan "$dir" 6
  write_transcript "$dir" 90000 0 0
  fire "$dir"                        # boundary: occ dropped to 90000
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -qE 'context-spend step-5: occupied=90000 delta=-52137 '; then
    pass "E4 negative delta: -52137"
  else
    fail "E4 negative delta" "audit='$audit'"
  fi
}
e4

echo ""
echo "=== E5: task-scale ids — step-T2 attribution ==="
e5() {
  local dir; dir=$(make_env T2 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed at T2
  write_plan "$dir" T3
  write_transcript "$dir" 120000 0 0
  fire "$dir"                        # boundary: T2 ended
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -qE 'context-spend step-T2: occupied=120000 delta=\+20000 '; then
    pass "E5 task-scale id: step-T2"
  else
    fail "E5 task-scale id" "audit='$audit'"
  fi
}
e5

echo ""
echo "=== E6: newest plan changes — silent re-seed, no line ==="
e6() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed pointing at wave-t.plan.md
  sleep 1
  write_plan "$dir" 7 "epic-t/wave-u.plan.md"   # newer plan becomes ls -t head
  touch "$dir/.bionic/docs/plans/epic-t/wave-u.plan.md"
  fire "$dir"
  TOTAL=$((TOTAL + 1))
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$(audit_of "$dir")" ]; then
    pass "E6 plan-change: silent re-seed, no line"
  else
    fail "E6 plan-change: expected silence" "audit='$(audit_of "$dir")'"
  fi
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$(state_of "$dir")" | grep -q 'wave-u.plan.md'; then
    pass "E6 plan-change: state re-pointed at new plan"
  else
    fail "E6 plan-change: state re-seed" "state='$(state_of "$dir")'"
  fi
}
e6

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "context-spend: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
