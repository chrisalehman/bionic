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

# write_plan_crlf: E3-style plan (current: $2) with \r\n line endings.
write_plan_crlf() {  # $1=dir $2=step [$3=rel-plan-path]
  local dir="$1" step="$2" rel="${3:-epic-t/wave-t.plan.md}"
  write_plan "$dir" "$step" "$rel"
  local f="$dir/.bionic/docs/plans/$rel"
  sed 's/$/\r/' "$f" > "$f.crlf" && mv "$f.crlf" "$f"
}

# write_plan_cronly: same plan, transformed via `tr '\n' '\r'` (classic-Mac,
# CR-only line endings — no \n anywhere in the file).
write_plan_cronly() {  # $1=dir $2=step [$3=rel-plan-path]
  local dir="$1" step="$2" rel="${3:-epic-t/wave-t.plan.md}"
  write_plan "$dir" "$step" "$rel"
  local f="$dir/.bionic/docs/plans/$rel"
  tr '\n' '\r' < "$f" > "$f.cr" && mv "$f.cr" "$f"
}

# write_transcript_u1: top-level usage sums to 142137; iterations[] holds
# TWO objects whose own token sums total 284274 (exactly 2x divergent).
# A summing implementation would log 284274; the hook must log 142137.
write_transcript_u1() {  # $1=dir
  local dir="$1"
  cat > "$dir/transcript.jsonl" <<'EOF'
{"type":"user","message":"scrubbed"}
{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":100000,"cache_creation_input_tokens":30000,"cache_read_input_tokens":12137,"output_tokens":50,"iterations":[{"input_tokens":142137,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},{"input_tokens":142137,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}]}}}
EOF
}

# write_transcript_u4: three assistant entries with different usage sums
# (50000, 90000, 142137). Only the LAST one's occupied value must be logged.
write_transcript_u4() {  # $1=dir
  local dir="$1"
  cat > "$dir/transcript.jsonl" <<'EOF'
{"type":"user","message":"scrubbed"}
{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}
{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":90000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":20}}}
{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":142137,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":30}}}
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

stdin_for() {  # $1=project $2=transcript-path [$3=session_id, default "scrubbed"]
  local sess="${3:-scrubbed}"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$sess" "$2" "$1"
}

run_hook() {  # $1=project $2=stdin-json
  HOOK_STDOUT=$(CLAUDE_PROJECT_DIR="$1" bash "$HOOK" <<< "$2" 2>/dev/null); HOOK_EXIT=$?
}

fire() {  # $1=project [$2=session_id, default "scrubbed"] — build real-shape stdin and run
  run_hook "$1" "$(stdin_for "$1" "$1/transcript.jsonl" "${2:-scrubbed}")"
}

audit_of() { cat "$1/.bionic/memory/sdlc-v11-audit.md" 2>/dev/null || true; }
state_of() { cat "$1/.bionic/tmp/context-spend.state" 2>/dev/null || true; }

# assert_silent: advisory invariant (A1) — every hook invocation, on every
# path, exits 0 and emits nothing on stdout (a Stop hook's stdout can carry
# a block payload; this hook must never emit one). Reads HOOK_EXIT/
# HOOK_STDOUT set by the most recent run_hook/fire call.
assert_silent() {  # $1=label
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDOUT" ]; then
    pass "$label: exit 0 + empty stdout"
  else
    fail "$label: expected exit 0 + empty stdout" "exit=$HOOK_EXIT stdout='$HOOK_STDOUT'"
  fi
}

# assert_degraded: a no-data class (D1-D8/A3) must be silent (A1) AND leave
# both outputs untouched — no audit line, state exactly as before the run.
assert_degraded() {  # $1=dir $2=label $3=pre-run state_of() snapshot
  local dir="$1" label="$2" pre="$3"
  assert_silent "$label"
  TOTAL=$((TOTAL + 1))
  if [ -z "$(audit_of "$dir")" ]; then
    pass "$label: no audit line"
  else
    fail "$label: unexpected audit line" "audit='$(audit_of "$dir")'"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$(state_of "$dir")" = "$pre" ]; then
    pass "$label: state untouched"
  else
    fail "$label: state changed" "before='$pre' after='$(state_of "$dir")'"
  fi
}

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
  assert_silent "E1 first-seen"
  TOTAL=$((TOTAL + 1))
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$(audit_of "$dir")" ]; then
    pass "E1 first-seen: exit 0, no audit line"
  else
    fail "E1 first-seen: expected silent no-line" "exit=$HOOK_EXIT audit='$(audit_of "$dir")'"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$(state_of "$dir")" = "$(printf '%s\tscrubbed\t4\t100000' "$plan")" ]; then
    pass "E1 first-seen: state seeded plan<TAB>session<TAB>4<TAB>100000"
  else
    fail "E1 first-seen: state seed" "state='$(state_of "$dir")'"
  fi
}
e1

echo ""
echo "=== E2: unchanged step — still no line, state untouched ==="
e2() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"; assert_silent "E2 unchanged (seed run)"; local st1; st1=$(state_of "$dir")
  fire "$dir"
  assert_silent "E2 unchanged (repeat run)"
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
  assert_silent "E3 seed run"
  write_plan "$dir" 5
  write_transcript "$dir" 142137 0 0
  fire "$dir"                        # boundary: step 4 ended, occ 142137
  assert_silent "E3 boundary run"
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
  if [ "$(state_of "$dir")" = "$(printf '%s\tscrubbed\t5\t142137' "$plan")" ]; then
    pass "E3 boundary: state advanced to session<TAB>5<TAB>142137"
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
  assert_silent "E4 seed run"
  write_plan "$dir" 6
  write_transcript "$dir" 90000 0 0
  fire "$dir"                        # boundary: occ dropped to 90000
  assert_silent "E4 boundary run"
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
  assert_silent "E5 seed run"
  write_plan "$dir" T3
  write_transcript "$dir" 120000 0 0
  fire "$dir"                        # boundary: T2 ended
  assert_silent "E5 boundary run"
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
  assert_silent "E6 seed run"
  sleep 1
  write_plan "$dir" 7 "epic-t/wave-u.plan.md"   # newer plan becomes ls -t head
  touch "$dir/.bionic/docs/plans/epic-t/wave-u.plan.md"
  fire "$dir"
  assert_silent "E6 plan-change run"
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
# Concurrency section (critic-fix F1; folds under AC-1/AC-4) — state is session-scoped. Two
# sessions interleaving Stops on the same project/plan must
# never synthesize a cross-session delta; a session change
# re-seeds silently, same as a plan change (E6).
# ============================================================

echo ""
echo "=== C1: session A then session B (different transcript) — no cross-session delta, silent re-seed ==="
c1() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local plan="$dir/.bionic/docs/plans/epic-t/wave-t.plan.md"
  # Session A seeds at step 4, occupancy 100000.
  run_hook "$dir" "$(stdin_for "$dir" "$dir/transcript.jsonl" "sess-a")"
  assert_silent "C1 session A seed"
  # Session B fires at step 5, on its OWN transcript, occupancy 500000.
  # A same-session boundary here would compute delta=+400000; the hook
  # must instead detect the session change and re-seed silently.
  write_plan "$dir" 5
  cat > "$dir/transcript-b.jsonl" <<'EOF'
{"type":"user","message":"scrubbed"}
{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":500000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
EOF
  run_hook "$dir" "$(stdin_for "$dir" "$dir/transcript-b.jsonl" "sess-b")"
  assert_silent "C1 session B run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if [ -z "$audit" ]; then
    pass "C1 cross-session: no audit line (no synthesized delta)"
  else
    fail "C1 cross-session: unexpected audit line (cross-session delta leaked)" "audit='$audit'"
  fi
  TOTAL=$((TOTAL + 1))
  if [ "$(state_of "$dir")" = "$(printf '%s\tsess-b\t5\t500000' "$plan")" ]; then
    pass "C1 cross-session: state re-seeded to sess-b/5/500000"
  else
    fail "C1 cross-session: state re-seed" "state='$(state_of "$dir")'"
  fi
}
c1

echo ""
echo "=== C2: same session_id across a boundary — still emits the E3-format line ==="
c2() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  run_hook "$dir" "$(stdin_for "$dir" "$dir/transcript.jsonl" "sess-x")"
  assert_silent "C2 seed run"
  write_plan "$dir" 5
  write_transcript "$dir" 142137 0 0
  run_hook "$dir" "$(stdin_for "$dir" "$dir/transcript.jsonl" "sess-x")"
  assert_silent "C2 boundary run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -qE '^- [0-9TZ:-]+ context-spend step-4: occupied=142137 delta=\+42137 model=claude-fable-5 \(.*wave-t\.plan\.md\)$'; then
    pass "C2 same-session boundary: E3-format line emitted"
  else
    fail "C2 same-session boundary" "audit='$audit'"
  fi
}
c2

# ============================================================
# Degradation section (AC-2) — no-data classes: exit 0, empty
# stdout, no audit line, state untouched from before the run.
# ============================================================

echo ""
echo "=== D1: stdin missing transcript_path key ==="
d1() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local pre; pre=$(state_of "$dir")
  local stdin; stdin=$(printf '{"session_id":"scrubbed","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$dir")
  run_hook "$dir" "$stdin"
  assert_degraded "$dir" "D1 missing transcript_path" "$pre"
}
d1

echo ""
echo "=== D2: transcript file absent ==="
d2() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local pre; pre=$(state_of "$dir")
  run_hook "$dir" "$(stdin_for "$dir" "$dir/does-not-exist.jsonl")"
  assert_degraded "$dir" "D2 transcript absent" "$pre"
}
d2

echo ""
echo "=== D3: transcript has no assistant-usage entries ==="
d3() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  cat > "$dir/transcript.jsonl" <<'EOF'
{"type":"user","message":"scrubbed"}
{"type":"system","message":"scrubbed"}
EOF
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "D3 no assistant-usage entries" "$pre"
}
d3

echo ""
echo "=== D4: no plans dir / no *.plan.md under it ==="
d4a() {
  local dir; dir=$(mktemp -d); cleanup_projects+=("$dir")
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/memory"
  write_transcript "$dir" 100000 0 0
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "D4a no plans dir at all" "$pre"
}
d4a

d4b() {
  local dir; dir=$(mktemp -d); cleanup_projects+=("$dir")
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/memory" "$dir/.bionic/docs/plans"
  write_transcript "$dir" 100000 0 0
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "D4b plans dir empty (no *.plan.md)" "$pre"
}
d4b

echo ""
echo "=== D5: plan lacking current: line (or lacking ## SDLC State) ==="
d5a() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  cat > "$dir/.bionic/docs/plans/epic-t/wave-t.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
---
## SDLC State

integration-branch: main

- Step 0: ok
EOF
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "D5a plan lacks current: line" "$pre"
}
d5a

d5b() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  cat > "$dir/.bionic/docs/plans/epic-t/wave-t.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
---
## Some Other Section

current: 4
EOF
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "D5b plan lacks ## SDLC State section entirely" "$pre"
}
d5b

echo ""
echo "=== D6: jq absent (PATH stripped) ==="
d6() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local pre; pre=$(state_of "$dir")
  HOOK_STDOUT=$(CLAUDE_PROJECT_DIR="$dir" PATH=/nonexistent /bin/bash "$HOOK" <<< "$(stdin_for "$dir" "$dir/transcript.jsonl")" 2>/dev/null); HOOK_EXIT=$?
  assert_degraded "$dir" "D6 jq absent" "$pre"
}
d6

echo ""
echo "=== D7: malformed stdin (not JSON) ==="
d7() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  local pre; pre=$(state_of "$dir")
  run_hook "$dir" "this is not json at all"
  assert_degraded "$dir" "D7 malformed stdin" "$pre"
}
d7

echo ""
echo "=== D8: occupied=0 (all three token fields zero) ==="
d8() {
  local dir; dir=$(make_env 4 0 0 0); cleanup_projects+=("$dir")
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "D8 occupied=0" "$pre"
}
d8

# ============================================================
# Advisory-invariant section (AC-4) — meta-evidence planted in
# BOTH directions: A1 (silence contract, retrofit onto E1-E6
# above + every D/A case via assert_silent), A2 (positive
# re-assert: a planted boundary DOES append exactly one line),
# A3 (fence-blind parser would wrongly emit; this hook must not).
# ============================================================

echo ""
echo "=== A2: positive re-assert — planted boundary appends exactly one line ==="
a2() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"
  assert_silent "A2 seed run"
  write_plan "$dir" 5
  write_transcript "$dir" 142137 0 0
  fire "$dir"
  assert_silent "A2 boundary run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  local n; n=$(printf '%s\n' "$audit" | grep -c 'context-spend step-')
  if [ "$n" -eq 1 ]; then
    pass "A2 positive re-assert: exactly one line on planted boundary"
  else
    fail "A2 positive re-assert: line count" "n=$n audit='$audit'"
  fi
}
a2

echo ""
echo "=== A3: fenced-skeleton plan — current: only inside fences → silence ==="
a3() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  cat > "$dir/.bionic/docs/plans/epic-t/wave-t.plan.md" <<'PLANEOF'
---
governing-skill: superpowers:writing-plans
---
## SDLC State

integration-branch: main

```
current: 99
```

- Step 0: ok
PLANEOF
  local pre; pre=$(state_of "$dir")
  fire "$dir"
  assert_degraded "$dir" "A3 fenced-skeleton current: line" "$pre"
}
a3

# ============================================================
# Parsing-edges section (AC-3) — top-level-usage rule (never
# iterations[]) + CR/CRLF plan normalization + last-entry-wins.
# ============================================================

echo ""
echo "=== U1: top-level vs iterations[] — logs top-level sum, never the 2x-divergent iterations sum ==="
u1() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed at step 4
  assert_silent "U1 seed run"
  write_plan "$dir" 5
  write_transcript_u1 "$dir"
  fire "$dir"                        # boundary: divergent iterations[] present
  assert_silent "U1 boundary run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -q 'occupied=142137' && ! printf '%s\n' "$audit" | grep -q '284274'; then
    pass "U1 top-level vs iterations[]: occupied=142137, never 284274"
  else
    fail "U1 top-level vs iterations[]" "audit='$audit'"
  fi
}
u1

echo ""
echo "=== U2: CRLF plan — boundary still emits with correct step id ==="
u2() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed at step 4
  assert_silent "U2 seed run"
  write_plan_crlf "$dir" 5
  write_transcript "$dir" 142137 0 0
  fire "$dir"                        # boundary: CRLF-normalized plan
  assert_silent "U2 boundary run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -qE 'context-spend step-4: occupied=142137 delta=\+42137 '; then
    pass "U2 CRLF plan: boundary emits with correct step id"
  else
    fail "U2 CRLF plan" "audit='$audit'"
  fi
}
u2

echo ""
echo "=== U3: CR-only (classic-Mac) plan — boundary still emits with correct step id ==="
u3() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed at step 4
  assert_silent "U3 seed run"
  write_plan_cronly "$dir" 5
  write_transcript "$dir" 142137 0 0
  fire "$dir"                        # boundary: CR-only-normalized plan
  assert_silent "U3 boundary run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -qE 'context-spend step-4: occupied=142137 delta=\+42137 '; then
    pass "U3 CR-only plan: boundary emits with correct step id"
  else
    fail "U3 CR-only plan" "audit='$audit'"
  fi
}
u3

echo ""
echo "=== U4: multiple assistant entries in tail — only the LAST one's occupied value logged ==="
u4() {
  local dir; dir=$(make_env 4 100000 0 0); cleanup_projects+=("$dir")
  fire "$dir"                        # seed at step 4
  assert_silent "U4 seed run"
  write_plan "$dir" 5
  write_transcript_u4 "$dir"
  fire "$dir"                        # boundary: three assistant entries, differing sums
  assert_silent "U4 boundary run"
  local audit; audit=$(audit_of "$dir")
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$audit" | grep -q 'occupied=142137' && ! printf '%s\n' "$audit" | grep -qE 'occupied=(50000|90000)'; then
    pass "U4 multiple assistant entries: only last entry's occupied logged"
  else
    fail "U4 multiple assistant entries" "audit='$audit'"
  fi
}
u4

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "context-spend: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
