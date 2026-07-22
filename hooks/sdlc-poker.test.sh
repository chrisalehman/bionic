#!/bin/bash
# Fixture suite for hooks/sdlc-poker.sh — slice 4/1 (poker core):
# consent-registry reading (C1), P3 registry-primary classification (C2),
# run discipline (lock / audit / status / state-cache, C8).
#
# Harness idiom mirrors hooks/context-spend.test.sh: PASS/FAIL counters, a
# fresh fake $HOME per case (mktemp), a PATH-shadowed stub `claude` binary
# that serves canned `agents --json` registry states from files under
# $HOME/.claude/.stub/, and planted registrations/plans/transcripts with
# controlled mtimes. The registry JSON shape replicates the live 2.1.216
# samples in .bionic/docs/spikes/spike-{dead-vs-busy,cron-env}-20260721.md:
# per-session objects with pid/cwd/kind/sessionId/name and a `status`
# (busy|idle) that print (`-p`) children omit entirely (NOSTATUS).
#
# The suite SOURCES the poker with SDLC_POKER_LIB=1 (main suppressed) so
# classify_goal can be called directly on a planted goal (cases 1-7, 11), and
# runs the whole script as a fresh child (run_poker) for the run-discipline
# cases (8-10, 12) that exercise the main loop, arming filter, and lock.
#
# Usage: bash hooks/sdlc-poker.test.sh

set -uo pipefail

POKER="$(cd "$(dirname "$0")" && pwd)/sdlc-poker.sh"
ORIG_PATH="$PATH"
PASS=0; FAIL=0; TOTAL=0
CLEAN_HOMES=()

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

cleanup() { for d in "${CLEAN_HOMES[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# Source the library (functions only; main suppressed). project_dir_for_cwd
# and classify_goal become callable; QUIET_THRESHOLD/WEDGE_QUIET/POKE_CAP land
# in scope. HOME is re-pointed per case AFTER this, and every poker function
# reads $HOME at call time, so the single source is safe across cases.
SDLC_POKER_LIB=1 . "$POKER"

# ---------- fresh fake HOME + PATH-shadowed stub claude / curl ----------
# The claude stub serves canned `agents --json` registry states AND records the
# POKE (argv → claude-calls.log, stdin → claude-stdin.log, cwd → claude-cwd.log),
# honoring an optional exit code (poke.rc) so a failing poke can be planted. The
# curl stub records the ntfy POST (argv → curl-calls.log), honoring curl.rc.
new_home() {
  HOME=$(mktemp -d); export HOME
  mkdir -p "$HOME/.claude/sdlc-goals" "$HOME/.claude/sdlc-status" "$HOME/.claude/.stub"
  cat > "$HOME/.claude/.stub/claude" <<'STUB'
#!/bin/sh
STUBDIR="$HOME/.claude/.stub"
if [ "$1" = "agents" ]; then
  rc=0
  [ -f "$STUBDIR/registry.rc" ] && rc=$(cat "$STUBDIR/registry.rc")
  [ -f "$STUBDIR/registry.json" ] && cat "$STUBDIR/registry.json"
  exit "$rc"
fi
# POKE path: capture argv, cwd, and stdin; honor a planted exit code.
echo "$*" >> "$STUBDIR/claude-calls.log"
pwd >> "$STUBDIR/claude-cwd.log"
cat >> "$STUBDIR/claude-stdin.log"
prc=0
[ -f "$STUBDIR/poke.rc" ] && prc=$(cat "$STUBDIR/poke.rc")
exit "$prc"
STUB
  chmod +x "$HOME/.claude/.stub/claude"
  cat > "$HOME/.claude/.stub/curl" <<'STUB'
#!/bin/sh
STUBDIR="$HOME/.claude/.stub"
echo "$*" >> "$STUBDIR/curl-calls.log"
crc=0
[ -f "$STUBDIR/curl.rc" ] && crc=$(cat "$STUBDIR/curl.rc")
exit "$crc"
STUB
  chmod +x "$HOME/.claude/.stub/curl"
  export PATH="$HOME/.claude/.stub:$ORIG_PATH"
  export BIONIC_NTFY_TOPIC="test-secret-topic-$$"   # secret; must never reach audit/status
  CLEAN_HOMES+=("$HOME")
}

# ---------- fixture planters ----------
# plant_goal <gid> <plan> <cwd> <sid> <pid> [drop-key]
plant_goal() {
  local gid="$1" plan="$2" cwd="$3" sid="$4" pid="$5" drop="${6:-}"
  local f="$HOME/.claude/sdlc-goals/$gid"; mkdir -p "$(dirname "$f")"
  {
    [ "$drop" = "PLAN" ]       || echo "PLAN=$plan"
    [ "$drop" = "CWD" ]        || echo "CWD=$cwd"
    [ "$drop" = "SESSION_ID" ] || echo "SESSION_ID=$sid"
    [ "$drop" = "PID" ]        || echo "PID=$pid"
    [ "$drop" = "ARMED_AT" ]   || echo "ARMED_AT=2026-07-21T00:00:00Z"
  } > "$f"
}

# plant_plan <path> <current> [wake:0/1] [scale=continuous]
plant_plan() {
  local p="$1" cur="$2" wake="${3:-0}" scale="${4:-continuous}"
  mkdir -p "$(dirname "$p")"
  {
    echo "---"
    echo "governing-skill: superpowers:writing-plans"
    echo "canonical_sdlc_version: 12"
    echo "scale: $scale"
    echo "---"
    echo ""
    echo "## SDLC State"
    echo ""
    echo "current: $cur"
    echo ""
    if [ "$wake" = "1" ]; then
      echo "## Wake Note"
      echo ""
      echo "blocked on decision X — stopping."
      echo ""
    fi
    echo "- G1: evidence"
  } > "$p"
}

# set_mtime_age <file> <seconds-ago>  (BSD date first, GNU fallback)
set_mtime_age() {
  local f="$1" age="$2" ts
  if ts=$(date -v-"${age}"S +%Y%m%d%H%M.%S 2>/dev/null); then
    touch -t "$ts" "$f"
  else
    touch -d "@$(( $(date +%s) - age ))" "$f"
  fi
}

# plant_transcript_age <cwd> <sid> <age-seconds> [last-event: user|busy]
# Writes the session transcript under the cwd-keyed Claude project dir (the
# poker's own project_dir_for_cwd, so the mapping is identical by construction)
# and back-dates its mtime.
plant_transcript_age() {
  local cwd="$1" sid="$2" age="$3" ev="${4:-user}"
  local pdir; pdir=$(project_dir_for_cwd "$cwd")
  mkdir -p "$pdir"
  local t="$pdir/$sid.jsonl"
  case "$ev" in
    busy) printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]},"stop_reason":"tool_use"}' > "$t" ;;
    *)    printf '%s\n' '{"type":"user","message":{"role":"user","content":"continue"}}' > "$t" ;;
  esac
  set_mtime_age "$t" "$age"
}

# stub_registry_state <absent|busy|idle|nostatus|fail> [sid]
stub_registry_state() {
  local kind="$1" sid="${2:-}"
  local f="$HOME/.claude/.stub/registry.json"
  local rcf="$HOME/.claude/.stub/registry.rc"
  echo 0 > "$rcf"
  case "$kind" in
    absent)  # registry non-empty but the target sid is NOT in it (by-id lookup)
      printf '[{"pid":11,"cwd":"/other","kind":"interactive","sessionId":"decoy-sid","status":"idle","name":"d"}]\n' > "$f" ;;
    fail)    printf '' > "$f"; echo 1 > "$rcf" ;;
    busy)    printf '[{"pid":4242,"cwd":"/x","kind":"interactive","sessionId":"%s","status":"busy","name":"t"}]\n' "$sid" > "$f" ;;
    idle)    printf '[{"pid":4242,"cwd":"/x","kind":"interactive","sessionId":"%s","status":"idle","name":"t"}]\n' "$sid" > "$f" ;;
    nostatus)printf '[{"pid":4242,"cwd":"/x","kind":"interactive","sessionId":"%s","name":"t"}]\n' "$sid" > "$f" ;;
  esac
}

# ---------- runners / assertions ----------
# A poll: run the whole poker as a fresh child. POKE_CLAUDE_BIN points the
# absolute-binary poke at the stub (C4 uses /opt/homebrew/bin/claude, overridable
# exactly as the thresholds are — AS resolution logged in the report); the ntfy
# topic rides through as the standing-service identity would supply it.
run_poker() {
  POKER_OUT=$(HOME="$HOME" PATH="$HOME/.claude/.stub:$ORIG_PATH" \
    POKE_CLAUDE_BIN="$HOME/.claude/.stub/claude" \
    BIONIC_NTFY_TOPIC="${BIONIC_NTFY_TOPIC:-}" bash "$POKER" 2>&1); POKER_EXIT=$?
}

audit_of()  { cat "$HOME/.claude/sdlc-poker-audit.log" 2>/dev/null || true; }
status_of() { cat "$HOME/.claude/sdlc-status/$1.md" 2>/dev/null || true; }
status_exists() { [ -f "$HOME/.claude/sdlc-status/$1.md" ]; }
claude_calls() { cat "$HOME/.claude/.stub/claude-calls.log" 2>/dev/null || true; }
claude_stdin() { cat "$HOME/.claude/.stub/claude-stdin.log" 2>/dev/null || true; }
claude_cwd()   { cat "$HOME/.claude/.stub/claude-cwd.log" 2>/dev/null || true; }
curl_calls()   { cat "$HOME/.claude/.stub/curl-calls.log" 2>/dev/null || true; }
count_lines()  { printf '%s' "$1" | grep -c -e "$2" 2>/dev/null || true; }
# A real, existing cwd (the poke `cd`s into it) mapped like production paths.
real_cwd() { local d="$HOME/work/$1"; mkdir -p "$d"; printf '%s' "$d"; }

assert_classify() {  # <gid> <expected> <label>
  TOTAL=$((TOTAL + 1))
  local got; got=$(classify_goal "$1")
  if [ "$got" = "$2" ]; then pass "$3 → $2"; else fail "$3" "expected='$2' got='$got'"; fi
}

assert_eq() {  # <label> <expected> <actual>
  TOTAL=$((TOTAL + 1))
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1" "expected='$2' actual='$3'"; fi
}

assert_true() {  # <label> <cmd...>
  local label="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then pass "$label"; else fail "$label"; fi
}
assert_contains() {  # <label> <needle> <haystack>
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$3" | grep -qF -- "$2"; then pass "$1"; else fail "$1" "expected to contain '$2'"; fi
}

# A goal that is armed and classifiable: continuous plan + registration +
# a transcript at a chosen age. Returns nothing; sets fixture state.
arm_goal() {  # <gid> <cur> <cwd> <sid> <pid> <age> [event] [wake]
  local gid="$1" cur="$2" cwd="$3" sid="$4" pid="$5" age="$6" ev="${7:-user}" wake="${8:-0}"
  local plan="$HOME/plans/$gid.plan.md"
  plant_plan "$plan" "$cur" "$wake"
  plant_goal "$gid" "$plan" "$cwd" "$sid" "$pid"
  plant_transcript_age "$cwd" "$sid" "$age" "$ev"
}

# ============================================================
echo "=== Case 1: plan current:10 → COMPLETE regardless of session state ==="
c1() {
  new_home
  arm_goal g1 10 /proj/one sid-1 4242 30 user
  stub_registry_state busy sid-1
  assert_classify g1 COMPLETE "case1 charter-close current:10 (session busy)"
}
c1

echo "=== Case 2: plan has ## Wake Note → GATED (precedence over liveness) ==="
c2() {
  new_home
  arm_goal g2 4 /proj/two sid-2 4242 30 user 1
  stub_registry_state busy sid-2
  assert_classify g2 GATED "case2 wake-note present (session busy)"
}
c2

echo "=== Case 3: registry ABSENT by session-id → DEAD ==="
c3() {
  new_home
  # PID intentionally dead so ps corroboration agrees; registry omits the sid.
  arm_goal g3 4 /proj/three sid-3 2147483647 30 user
  stub_registry_state absent
  assert_classify g3 DEAD "case3 sid absent from registry"
}
c3

echo "=== Case 4: status:busy → BUSY at <WEDGE_QUIET, WEDGED at >WEDGE_QUIET ==="
c4() {
  new_home
  arm_goal g4 4 /proj/four sid-4 4242 200 busy
  stub_registry_state busy sid-4
  assert_classify g4 BUSY "case4 busy + quiet 200s (<540)"
  # Age the same transcript past WEDGE_QUIET.
  plant_transcript_age /proj/four sid-4 600 busy
  assert_classify g4 WEDGED "case4 busy + quiet 600s (>540)"
}
c4

echo "=== Case 5: status:idle → IDLE_STALLED at >QUIET_THRESHOLD, IDLE at < ==="
c5() {
  new_home
  arm_goal g5 4 /proj/five sid-5 4242 200 user
  stub_registry_state idle sid-5
  assert_classify g5 IDLE_STALLED "case5 idle + quiet 200s (>180)"
  plant_transcript_age /proj/five sid-5 60 user
  assert_classify g5 IDLE "case5 idle + quiet 60s (<180)"
}
c5

echo "=== Case 6: registry present, no status field → BUSY (alive-working) ==="
c6() {
  new_home
  arm_goal g6 4 /proj/six sid-6 4242 30 busy
  stub_registry_state nostatus sid-6
  assert_classify g6 BUSY "case6 NOSTATUS print-child (quiet 30s)"
}
c6

echo "=== Case 7: quiet-never-dead — present + age 10000s → never DEAD ==="
c7() {
  new_home
  arm_goal g7 4 /proj/seven sid-7 4242 10000 user
  stub_registry_state idle sid-7
  TOTAL=$((TOTAL + 1))
  got=$(classify_goal g7)
  if [ "$got" != "DEAD" ] && [ "$got" = "IDLE_STALLED" ]; then
    pass "case7 present+10000s quiet → IDLE_STALLED, never DEAD"
  else
    fail "case7 quiet-never-dead" "got='$got' (must not be DEAD)"
  fi
}
c7

echo "=== Case 8: exclusive arming — both halves required ==="
c8() {
  # 8a: registration present but plan NOT scale:continuous → skipped (unarmed).
  new_home
  local plan="$HOME/plans/g8a.plan.md"
  plant_plan "$plan" 4 0 wave        # scale: wave, not continuous
  plant_goal g8a "$plan" /proj/8a sid-8a 4242
  plant_transcript_age /proj/8a sid-8a 30 user
  stub_registry_state idle sid-8a
  run_poker
  assert_eq "case8a non-continuous plan → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! status_exists g8a; then pass "case8a unarmed (scale!=continuous) → no status written"; else fail "case8a unarmed" "status file present"; fi

  # 8b: continuous plan exists but NO registration → nothing to iterate.
  new_home
  plant_plan "$HOME/plans/g8b.plan.md" 4 0 continuous
  plant_transcript_age /proj/8b sid-8b 30 user
  stub_registry_state idle sid-8b
  run_poker
  assert_eq "case8b no registration → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! status_exists g8b; then pass "case8b no registration → no status written"; else fail "case8b no registration" "status file present"; fi

  # 8c: both halves present → armed → classified → status written.
  new_home
  arm_goal g8c 4 /proj/8c sid-8c 4242 30 user
  stub_registry_state idle sid-8c
  run_poker
  assert_eq "case8c both halves → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if status_exists g8c; then pass "case8c armed (both halves) → status written"; else fail "case8c armed" "no status file; out='$POKER_OUT'"; fi
}
c8

echo "=== Case 9: disarm — registration removed → next run takes no action ==="
c9() {
  new_home
  arm_goal g9 4 /proj/nine sid-9 4242 30 user
  stub_registry_state idle sid-9
  run_poker
  assert_true "case9 armed first run wrote status" status_exists g9
  local mt1; mt1=$(file_mtime "$HOME/.claude/sdlc-status/g9.md")
  sleep 1
  rm -f "$HOME/.claude/sdlc-goals/g9"        # disarm
  run_poker
  local mt2; mt2=$(file_mtime "$HOME/.claude/sdlc-status/g9.md")
  assert_eq "case9 disarmed goal not re-derived (status mtime unchanged)" "$mt1" "$mt2"
}
c9

echo "=== Case 10: malformed record (missing CWD) → MALFORMED-RECORD, continue ==="
c10() {
  new_home
  # A malformed goal (no CWD) and a healthy armed goal in the same run.
  local badplan="$HOME/plans/bad.plan.md" okplan="$HOME/plans/ok.plan.md"
  plant_plan "$badplan" 4 0 continuous
  plant_goal g10bad "$badplan" /proj/bad sid-bad 4242 CWD    # drop CWD
  arm_goal g10ok 4 /proj/ok sid-ok 4242 30 user
  stub_registry_state idle sid-ok
  run_poker
  assert_eq "case10 poker exit 0 despite malformed record" 0 "$POKER_EXIT"
  assert_contains "case10 MALFORMED-RECORD audit line for bad goal" "g10bad MALFORMED-RECORD" "$(audit_of)"
  assert_true "case10 run continued to the healthy goal (status written)" status_exists g10ok
}
c10

echo "=== Case 11: registry call fails → DEGRADE audit + ps/grammar fallback, exit 0 ==="
c11() {
  new_home
  # Live pid ($$ = this test process) so ps says alive; idle grammar, young age.
  arm_goal g11 4 /proj/eleven sid-11 "$$" 60 user
  stub_registry_state fail
  local got; got=$(classify_goal g11)
  assert_eq "case11 degrade path resolves via ps(alive)+grammar(idle) → IDLE" "IDLE" "$got"
  assert_contains "case11 DEGRADE audit line emitted" "g11 DEGRADE" "$(audit_of)"
}
c11

echo "=== Case 12: lock — concurrent run exits silently; stale lock reclaimed ==="
c12() {
  # 12a: a LIVE lock holder ($$) → second run exits 0 and does nothing.
  new_home
  arm_goal g12a 4 /proj/12a sid-12a 4242 30 user
  stub_registry_state idle sid-12a
  mkdir -p "$HOME/.claude/sdlc-poker.lock"; echo "$$" > "$HOME/.claude/sdlc-poker.lock/pid"
  run_poker
  assert_eq "case12a live lock → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! status_exists g12a; then pass "case12a live lock → goal not processed (no status)"; else fail "case12a live lock" "status written despite held lock"; fi

  # 12b: a STALE lock (dead pid) → reclaimed, goal processed.
  new_home
  arm_goal g12b 4 /proj/12b sid-12b 4242 30 user
  stub_registry_state idle sid-12b
  mkdir -p "$HOME/.claude/sdlc-poker.lock"; echo 2147483647 > "$HOME/.claude/sdlc-poker.lock/pid"
  run_poker
  assert_eq "case12b stale lock → poker exit 0" 0 "$POKER_EXIT"
  assert_true "case12b stale lock reclaimed → goal processed (status written)" status_exists g12b
}
c12

# ============================================================
# ===================  slice 4/2 — actions  ==================
# poke (C4), retry-cap episodes, ntfy transitions (C5), no-force wedge (C3).

echo "=== 4/2-1: DEAD armed goal → poke via stdin, absolute binary, cd-first, no --model ==="
p1() {
  new_home
  local cwd; cwd=$(real_cwd d1)
  arm_goal ad1 4 "$cwd" sid-d1 2147483647 30 user   # dead pid; registry absent → DEAD
  stub_registry_state absent
  run_poker
  assert_eq "4/2-1 poker exit 0" 0 "$POKER_EXIT"
  assert_contains "4/2-1 poke argv: --resume <sid> -p" "--resume sid-d1 -p" "$(claude_calls)"
  assert_contains "4/2-1 poke argv: --dangerously-skip-permissions" "--dangerously-skip-permissions" "$(claude_calls)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(claude_calls)" | grep -q -- '--model'; then
    pass "4/2-1 no --model override in poke argv"
  else fail "4/2-1 no --model" "argv='$(claude_calls)'"; fi
  assert_contains "4/2-1 POKE_PROMPT arrived via stdin" "continue per the plan" "$(claude_stdin)"
  assert_contains "4/2-1 POKE_PROMPT carries the gate escape hatch" "if blocked on a decision" "$(claude_stdin)"
  local exp; exp=$(cd "$cwd" 2>/dev/null && pwd)
  assert_eq "4/2-1 poke ran cd-first in CWD" "$exp" "$(claude_cwd)"
  assert_true "4/2-1 script pins the absolute poke binary" grep -q "/opt/homebrew/bin/claude" "$POKER"
}
p1

echo "=== 4/2-2: IDLE_STALLED → poked; IDLE (fresh) → zero invocations ==="
p2() {
  new_home
  local cwd; cwd=$(real_cwd d2)
  arm_goal as2 4 "$cwd" sid-s2 4242 200 user   # idle + 200s → IDLE_STALLED
  stub_registry_state idle sid-s2
  run_poker
  assert_contains "4/2-2 IDLE_STALLED poked" "--resume sid-s2" "$(claude_calls)"
  new_home
  cwd=$(real_cwd d2b)
  arm_goal ai2 4 "$cwd" sid-i2 4242 60 user    # idle + 60s → IDLE (fresh)
  stub_registry_state idle sid-i2
  run_poker
  assert_eq "4/2-2 IDLE (fresh) → zero poke invocations" "" "$(claude_calls)"
}
p2

echo "=== 4/2-3: BUSY → SKIP-BUSY, no poke; WEDGED → no poke, no kill, target alive ==="
p3() {
  new_home
  local cwd; cwd=$(real_cwd d3)
  arm_goal ab3 4 "$cwd" sid-b3 4242 60 busy    # busy + 60s → BUSY
  stub_registry_state busy sid-b3
  run_poker
  assert_eq "4/2-3 BUSY → zero poke invocations" "" "$(claude_calls)"
  assert_contains "4/2-3 SKIP-BUSY audit line" "ab3 SKIP-BUSY" "$(audit_of)"

  new_home
  cwd=$(real_cwd d3w)
  arm_goal aw3 4 "$cwd" sid-w3 "$$" 600 busy   # busy + 600s → WEDGED; live pid == this process
  stub_registry_state busy sid-w3
  run_poker
  assert_eq "4/2-3 WEDGED → zero claude poke invocations" "" "$(claude_calls)"
  TOTAL=$((TOTAL + 1))
  if ps -p "$$" >/dev/null 2>&1; then pass "4/2-3 WEDGE target pid still alive (never signalled)"; else fail "4/2-3 target alive"; fi
  # No kill/pkill/killall INVOCATION in the script; comments and the recovery-
  # command STRING (the single printf template) are the only permitted mentions.
  TOTAL=$((TOTAL + 1))
  local hits
  hits=$(grep -nE '(kill|pkill|killall)' "$POKER" \
    | grep -vE ':[[:space:]]*#' \
    | grep -vF "printf 'kill %s && cd %s && claude --resume %s'")
  if [ -z "$hits" ]; then pass "4/2-3 no kill/pkill/killall invocation in script"; else fail "4/2-3 no-kill" "offenders: $hits"; fi
}
p3

echo "=== 4/2-4: WEDGE notification — Title + recovery command verbatim ==="
p4() {
  new_home
  local cwd; cwd=$(real_cwd d4)
  arm_goal aw4 4 "$cwd" sid-w4 31337 600 busy   # WEDGED, known pid for recovery string
  stub_registry_state busy sid-w4
  run_poker
  assert_contains "4/2-4 WEDGE curl Title" "Title: aw4: WEDGE" "$(curl_calls)"
  assert_contains "4/2-4 WEDGE body carries recovery command verbatim" \
    "kill 31337 && cd $cwd && claude --resume sid-w4" "$(curl_calls)"
}
p4

echo "=== 4/2-5: GATED once; identical poll dedupes; driving→gated flip re-notifies ==="
p5() {
  new_home
  local cwd; cwd=$(real_cwd d5)
  local plan="$HOME/plans/ag5.plan.md"
  plant_plan "$plan" 4 1 continuous            # wake note → GATED
  plant_goal ag5 "$plan" "$cwd" sid-g5 4242
  plant_transcript_age "$cwd" sid-g5 60 user
  stub_registry_state busy sid-g5
  run_poker                                     # poll1: GATED transition → notify
  run_poker                                     # poll2: GATED again → dedupe
  assert_eq "4/2-5 GATED notified once across two identical polls" "1" "$(count_lines "$(curl_calls)" "GATED")"
  plant_plan "$plan" 4 0 continuous            # wake note gone → BUSY (driving)
  plant_transcript_age "$cwd" sid-g5 60 busy
  run_poker                                     # poll3: BUSY → no GATED curl
  plant_plan "$plan" 4 1 continuous            # wake note back → GATED
  plant_transcript_age "$cwd" sid-g5 60 user
  run_poker                                     # poll4: GATED transition again → notify #2
  assert_eq "4/2-5 GATED re-notified after driving→gated flip" "2" "$(count_lines "$(curl_calls)" "GATED")"
}
p5

echo "=== 4/2-6: COMPLETE once; registration retained (poker never disarms) ==="
p6() {
  new_home
  local cwd; cwd=$(real_cwd d6)
  arm_goal ac6 10 "$cwd" sid-c6 4242 60 user    # current:10 → COMPLETE
  stub_registry_state idle sid-c6
  run_poker
  assert_eq "4/2-6 COMPLETE notified once" "1" "$(count_lines "$(curl_calls)" "COMPLETE")"
  assert_true "4/2-6 registration retained" test -f "$HOME/.claude/sdlc-goals/ac6"
  run_poker
  assert_eq "4/2-6 COMPLETE deduped on second poll" "1" "$(count_lines "$(curl_calls)" "COMPLETE")"
}
p6

echo "=== 4/2-7: retry-cap — 3 pokes then POKE-FAIL; transcript movement resets episode ==="
p7() {
  new_home
  local cwd; cwd=$(real_cwd d7)
  arm_goal as7 4 "$cwd" sid-p7 4242 200 user    # IDLE_STALLED, pokeable
  stub_registry_state idle sid-p7
  run_poker; run_poker; run_poker               # 3 pokes, same episode (stub never moves transcript)
  assert_eq "4/2-7 three pokes within the cap" "3" "$(count_lines "$(claude_calls)" "resume sid-p7")"
  run_poker                                      # 4th poll: cap exhausted
  assert_eq "4/2-7 no 4th poke after cap exhausted" "3" "$(count_lines "$(claude_calls)" "resume sid-p7")"
  assert_contains "4/2-7 POKE-FAIL notified on cap exhaustion" "Title: as7: POKE-FAIL" "$(curl_calls)"
  plant_transcript_age "$cwd" sid-p7 200 user   # fresh mtime = transcript movement
  run_poker
  assert_eq "4/2-7 episode reset on movement → poke resumes" "4" "$(count_lines "$(claude_calls)" "resume sid-p7")"
}
p7

echo "=== 4/2-8: a failing poke (exit nonzero) counts against the cap ==="
p8() {
  new_home
  local cwd; cwd=$(real_cwd d8)
  arm_goal as8 4 "$cwd" sid-p8 4242 200 user
  stub_registry_state idle sid-p8
  echo 1 > "$HOME/.claude/.stub/poke.rc"         # every poke exits nonzero
  run_poker; run_poker; run_poker
  assert_eq "4/2-8 three failing pokes counted" "3" "$(count_lines "$(claude_calls)" "resume sid-p8")"
  run_poker
  assert_eq "4/2-8 failing pokes count against cap (no 4th)" "3" "$(count_lines "$(claude_calls)" "resume sid-p8")"
  assert_contains "4/2-8 POKE-FAIL after failing pokes fill the cap" "Title: as8: POKE-FAIL" "$(curl_calls)"
}
p8

echo "=== 4/2-9: POKE_PROMPT contains no banned approval token (case-insensitive) ==="
p9() {
  new_home
  local cwd; cwd=$(real_cwd d9)
  arm_goal ap9 4 "$cwd" sid-b9 2147483647 30 user   # dead pid; registry absent → DEAD → poke
  stub_registry_state absent
  run_poker
  local stdin; stdin=$(claude_stdin)
  TOTAL=$((TOTAL + 1))
  if [ -n "$stdin" ] && ! printf '%s' "$stdin" \
     | grep -qiE 'approve|approved|approval|permission granted|yes to|go ahead with the gate|waiver'; then
    pass "4/2-9 POKE_PROMPT carries no banned approval token"
  else fail "4/2-9 banned-token scan" "stdin='$stdin'"; fi
}
p9

echo "=== 4/2-10: curl failure → NOTIFY-FAIL audit, exit 0, retry on next poll ==="
p10() {
  new_home
  local cwd; cwd=$(real_cwd d10)
  arm_goal ac10 10 "$cwd" sid-n10 4242 60 user   # COMPLETE → notifies
  stub_registry_state idle sid-n10
  echo 22 > "$HOME/.claude/.stub/curl.rc"         # curl fails (exit 22)
  run_poker
  assert_eq "4/2-10 poker exit 0 despite curl failure" 0 "$POKER_EXIT"
  assert_contains "4/2-10 NOTIFY-FAIL audit line" "ac10 NOTIFY-FAIL" "$(audit_of)"
  rm -f "$HOME/.claude/.stub/curl.rc"             # curl recovers
  run_poker
  assert_contains "4/2-10 notification retried on the next poll" "Title: ac10: COMPLETE" "$(curl_calls)"
}
p10

echo "=== 4/2-11: topic secrecy — \$BIONIC_NTFY_TOPIC never in audit log or status files ==="
p11() {
  new_home
  local cwd; cwd=$(real_cwd d11)
  # Exercise several notify + poke + wedge paths so every writer runs.
  arm_goal comp11 10 "$cwd" sid-cm 4242 60 user
  stub_registry_state idle sid-cm
  run_poker
  new_home
  cwd=$(real_cwd d11w)
  arm_goal wed11 4 "$cwd" sid-wd 4242 600 busy
  stub_registry_state busy sid-wd
  run_poker
  TOTAL=$((TOTAL + 1))
  if ! grep -rqF "$BIONIC_NTFY_TOPIC" "$HOME/.claude/sdlc-poker-audit.log" "$HOME/.claude/sdlc-status" 2>/dev/null; then
    pass "4/2-11 topic secret absent from audit log + status files"
  else fail "4/2-11 topic secrecy" "topic value leaked into audit/status"; fi
}
p11

# ============================================================
echo ""
echo "========================================"
echo "sdlc-poker core: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
