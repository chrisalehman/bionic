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

# Source the library (functions only; main suppressed). classify_goal becomes
# callable; QUIET_THRESHOLD/WEDGE_QUIET/POKE_CAP land in scope. HOME is re-pointed
# per case AFTER this, and every poker function reads $HOME at call time, so the
# single source is safe across cases. Transcript planting uses this suite's OWN
# real_project_dir sanitizer (below) — the poker no longer maps cwd→dir at all
# (it globs by session id), so the harness must derive the realistic path itself.
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
# POKE path: capture argv, cwd, stdin, and whether the OAuth token reached this
# child (F1); honor planted stderr (F3), a per-call transcript append (F2, models
# the live "Not logged in" turn write), and an exit code.
echo "$*" >> "$STUBDIR/claude-calls.log"
pwd >> "$STUBDIR/claude-cwd.log"
cat >> "$STUBDIR/claude-stdin.log"
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo present >> "$STUBDIR/claude-token.log"
else
  echo absent >> "$STUBDIR/claude-token.log"
fi
[ -f "$STUBDIR/poke.stdout" ] && cat "$STUBDIR/poke.stdout"
[ -f "$STUBDIR/poke.stderr" ] && cat "$STUBDIR/poke.stderr" >&2
if [ -f "$STUBDIR/poke-append" ]; then
  tp=$(cat "$STUBDIR/poke-append")
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text"}]}}' >> "$tp"
fi
# F3: model a HUNG poke — real foreground work (NOT a leading sleep, which the
# harness blocks), self-bounded (~8s) so a poker WITHOUT the timeout wrapper does
# not hang the suite (it finishes late, rc=0). With the perl-alarm wrapper and a
# small POKE_TIMEOUT the child is SIGALRM-killed first → rc=142 → POKE-TIMEOUT.
if [ -f "$STUBDIR/poke-block" ]; then
  _end=$(( $(date +%s) + 8 ))
  while [ "$(date +%s)" -lt "$_end" ]; do : ; done
fi
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

# Claude Code's project-dir sanitizer, implemented INDEPENDENTLY of the poker (the
# poker no longer maps cwd→dir — it globs by session id): the FULL cwd with every
# [^a-zA-Z0-9] replaced by '-'. Used only to PLANT transcripts at realistic paths;
# the sid-glob resolver finds them by session id regardless of the dir name.
real_project_dir() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g')"
}

# plant_transcript_age <cwd> <sid> <age-seconds> [last-event: user|busy]
# Writes the session transcript under the REAL (independently sanitized) Claude
# project dir and back-dates its mtime. The poker resolves it by SESSION-ID GLOB,
# so the exact dir name is immaterial to resolution — only that the file is named
# <sid>.jsonl under some $HOME/.claude/projects/* dir.
plant_transcript_age() {
  local cwd="$1" sid="$2" age="$3" ev="${4:-user}"
  local pdir; pdir=$(real_project_dir "$cwd")
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
    POKE_TIMEOUT="${POKE_TIMEOUT:-900}" \
    BIONIC_NTFY_TOPIC="${BIONIC_NTFY_TOPIC:-}" bash "$POKER" 2>&1); POKER_EXIT=$?
}

# A cron-faithful poll (F1): model the C7 entry's `. cron.env && poker`, but with
# NEITHER the token NOR the topic present in the invoking environment (env -u), and
# the cron.env sourced by the PARENT sh as PLAIN, non-exported KEY=value — so the
# parent-shell binding does NOT reach the poker child. Only the poker's own
# self-source (C8 amendment) can carry the identity through. No BIONIC_NTFY_TOPIC
# is injected here (unlike run_poker); the poker must self-source it.
run_poker_cron() {
  local cronenv="$HOME/.claude/cron.env"
  POKER_OUT=$(env -u BIONIC_NTFY_TOPIC -u CLAUDE_CODE_OAUTH_TOKEN \
    HOME="$HOME" PATH="$HOME/.claude/.stub:$ORIG_PATH" \
    POKE_CLAUDE_BIN="$HOME/.claude/.stub/claude" \
    /bin/sh -c '. "$1" && bash "$2"' sh "$cronenv" "$POKER" 2>&1); POKER_EXIT=$?
}

audit_of()  { cat "$HOME/.claude/sdlc-poker-audit.log" 2>/dev/null || true; }
status_of() { cat "$HOME/.claude/sdlc-status/$1.md" 2>/dev/null || true; }
status_exists() { [ -f "$HOME/.claude/sdlc-status/$1.md" ]; }
claude_calls() { cat "$HOME/.claude/.stub/claude-calls.log" 2>/dev/null || true; }
claude_stdin() { cat "$HOME/.claude/.stub/claude-stdin.log" 2>/dev/null || true; }
claude_cwd()   { cat "$HOME/.claude/.stub/claude-cwd.log" 2>/dev/null || true; }
claude_token() { cat "$HOME/.claude/.stub/claude-token.log" 2>/dev/null || true; }
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

# ADR-002 Decision 2a: signal wrappers sanctioned on the poker's own poke
# path only — the perl alarm-exec idiom may appear inside do_poke's body and
# nowhere else. Extracts do_poke's own line range (function-boundary awk) and
# returns any 'alarm' hits found outside it; empty output means confined.
alarm_confined_to_do_poke() {  # $1=poker script path
  local script="$1" range start end
  range=$(awk '
    /^do_poke\(\) \{/ { start = NR }
    start && /^}$/ { end = NR; exit }
    END { print start, end }
  ' "$script")
  start=${range%% *}; end=${range##* }
  if [ -z "$start" ] || [ -z "$end" ]; then
    echo "do_poke boundaries not found in $script"
    return
  fi
  grep -nE 'alarm' "$script" \
    | awk -F: -v s="$start" -v e="$end" '$1 < s || $1 > e { print }'
}

# plant_alarm_drift <in> <out>: writes a copy of the poker with an alarm-idiom
# mention inserted into dispatch_actions — OUTSIDE do_poke — proving
# alarm_confined_to_do_poke REDs when the signal-bearing pattern escapes its
# sanctioned function. Never touches the real script (agent-roles.test.sh
# drift-planter precedent: mutate a copy, never the source).
plant_alarm_drift() {
  awk '
    /^dispatch_actions\(\) \{/ && !done {
      print
      print "  # planted drift (meta-evidence): perl alarm-exec idiom outside do_poke"
      done = 1
      next
    }
    { print }
  ' "$1" > "$2"
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

  # ADR-002 Decision 2a: signal wrappers sanctioned on the poker's own poke
  # path only — assert the alarm-exec idiom never escapes do_poke.
  TOTAL=$((TOTAL + 1))
  local alarm_hits; alarm_hits=$(alarm_confined_to_do_poke "$POKER")
  if [ -z "$alarm_hits" ]; then pass "4/2-3 alarm-wrapper confined to do_poke (ADR-002 D2a)"; else fail "4/2-3 alarm-wrapper escaped do_poke" "offenders: $alarm_hits"; fi

  # Meta-evidence: a planted alarm mention OUTSIDE do_poke (in dispatch_actions,
  # on a tmp copy — the shipped poker is never mutated) must make the guard
  # above go RED, proving it actually enforces the boundary.
  TOTAL=$((TOTAL + 1))
  local drift_copy; drift_copy=$(mktemp)
  plant_alarm_drift "$POKER" "$drift_copy"
  local drift_hits; drift_hits=$(alarm_confined_to_do_poke "$drift_copy")
  rm -f "$drift_copy"
  if [ -n "$drift_hits" ]; then pass "meta: alarm-wrapper-outside-do_poke drift detected"; else fail "meta: planted alarm drift NOT detected"; fi
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
  sleep 1  # mtime distinctness: same-age re-plant within one wall-clock second is byte-identical (c9 idiom); poke_capped resets only on mtime != smtime
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
# ============  slice 4/3 — T3 walk findings  ================
# F1 env self-source (C8 amendment), F2 failure-aware retry-cap (C4 amendment),
# F3 stderr audit tail (C4 amendment). Root-cause evidence: .bionic/tmp/walk/walk.log
# (7 unbounded rc=1 pokes, no POKE-FAIL, stderr swallowed, "no ntfy topic").

echo "=== 4/3-1 (F1): poker self-sources cron.env → token reaches poke child, topic reaches notify ==="
f1() {
  new_home
  # cron.env with PLAIN (non-exported) KEY=value lines — the live file shape.
  {
    echo "CLAUDE_CODE_OAUTH_TOKEN=fake-oauth-token-value"
    echo "BIONIC_NTFY_TOPIC=fake-selfsourced-topic"
  } > "$HOME/.claude/cron.env"
  chmod 600 "$HOME/.claude/cron.env"
  local dcwd ccwd
  dcwd=$(real_cwd f1d); ccwd=$(real_cwd f1c)
  arm_goal f1dead 4  "$dcwd" sid-f1d 2147483647 30 user   # DEAD → poke (token check)
  arm_goal f1comp 10 "$ccwd" sid-f1c 4242         30 user   # COMPLETE → notify (topic check)
  stub_registry_state absent                                # sid-f1d absent → DEAD
  run_poker_cron
  assert_eq "4/3-1 poker exit 0 (cron-invoked, self-sourced)" 0 "$POKER_EXIT"
  assert_contains "4/3-1 OAuth token reached the poke child (self-sourced from cron.env)" \
    "present" "$(claude_token)"
  assert_contains "4/3-1 ntfy topic reached do_notify (curl POST carries self-sourced topic)" \
    "fake-selfsourced-topic" "$(curl_calls)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(claude_token)" | grep -qx absent; then
    pass "4/3-1 no poke child ever saw an absent token"
  else fail "4/3-1 token presence" "a poke child observed CLAUDE_CODE_OAUTH_TOKEN absent"; fi
}
f1

echo "=== 4/3-2 (F2): failure-aware cap — rc=1 pokes that MOVE the transcript still hit POKE_CAP ==="
# The rewritten proof for the recorded false-green: the pre-amendment episode was
# keyed on transcript mtime alone, so a persistently-failing poke's own turn write
# reset the episode every poll → unbounded pokes, POKE-FAIL never fired (live: 7/7).
f2() {
  new_home
  local cwd tpath; cwd=$(real_cwd fp2)
  arm_goal af2 4 "$cwd" sid-f2 4242 260 user    # idle + 260s → IDLE_STALLED (pokeable)
  stub_registry_state idle sid-f2
  echo 1 > "$HOME/.claude/.stub/poke.rc"         # every poke fails (models "Not logged in")
  tpath="$(real_project_dir "$cwd")/sid-f2.jsonl"
  # Each poll: the failed poke's own turn lands as fresh transcript movement
  # (distinct, still-stale mtimes, all >QUIET_THRESHOLD so the goal stays IDLE_STALLED).
  local age
  for age in 250 240 230 220; do
    set_mtime_age "$tpath" "$age"
    run_poker
  done
  assert_eq "4/3-2 exactly POKE_CAP(3) pokes despite per-poll transcript movement" \
    "3" "$(count_lines "$(claude_calls)" "resume sid-f2")"
  assert_contains "4/3-2 POKE-FAIL fires (a failed poke's own write never resets the episode)" \
    "Title: af2: POKE-FAIL" "$(curl_calls)"
  set_mtime_age "$tpath" 210
  run_poker                                       # parked: still no poke after cap
  assert_eq "4/3-2 no further poke after cap (parked despite continued movement)" \
    "3" "$(count_lines "$(claude_calls)" "resume sid-f2")"
}
f2

echo "=== 4/3-3 (F3): rc!=0 POKE audit tail — combined stdout+stderr, trailing, truncated, scrubbed ==="
f3() {
  # 3a: the live failure ("Not logged in · Please run /login") rides STDOUT — the
  # -p result stream — with stderr empty (walk repro). Capturing stderr alone
  # would still be blind, so the audit tail must span the COMBINED stream.
  new_home
  local cwd; cwd=$(real_cwd fp3a)
  arm_goal af3a 4 "$cwd" sid-f3a 2147483647 30 user   # dead pid + registry absent → DEAD → poke
  stub_registry_state absent
  echo 1 > "$HOME/.claude/.stub/poke.rc"
  printf 'Not logged in - Please run /login (STDOUT-DISTINCTIVE)\n' > "$HOME/.claude/.stub/poke.stdout"
  run_poker
  assert_contains "4/3-3a live STDOUT failure line captured in the POKE audit tail" \
    "STDOUT-DISTINCTIVE" "$(audit_of)"

  # 3b: stderr is also captured; the tail is the TRAILING ~120 chars (the failure
  # reason surfaces at the end of the stream) and the topic secret is scrubbed.
  new_home
  cwd=$(real_cwd fp3b)
  arm_goal af3b 4 "$cwd" sid-f3b 2147483647 30 user
  stub_registry_state absent
  echo 1 > "$HOME/.claude/.stub/poke.rc"
  {
    printf 'LEADmarker '                               # far from the tail → truncated away
    head -c 140 < /dev/zero | tr '\0' x
    printf ' token=%s TRAILmarker\n' "$BIONIC_NTFY_TOPIC"   # inside the trailing tail
  } > "$HOME/.claude/.stub/poke.stderr"
  run_poker
  local audit havetrail; audit="$(audit_of)"
  assert_contains "4/3-3b stderr tail captured (trailing marker present)" "TRAILmarker" "$audit"
  # Truncation + scrub are gated on the trailing marker being present, so neither
  # passes vacuously if the stream is swallowed or the wrong end is kept.
  havetrail=no; printf '%s' "$audit" | grep -qF -- "TRAILmarker" && havetrail=yes
  TOTAL=$((TOTAL + 1))
  if [ "$havetrail" = yes ] && ! printf '%s' "$audit" | grep -qF -- "LEADmarker"; then
    pass "4/3-3b tail truncated to the trailing ~120 chars — LEADmarker dropped"
  else fail "4/3-3b truncation" "tail absent or leading content survived truncation"; fi
  TOTAL=$((TOTAL + 1))
  if [ "$havetrail" = yes ] && ! printf '%s' "$audit" | grep -qF -- "$BIONIC_NTFY_TOPIC"; then
    pass "4/3-3b topic secret scrubbed from the tail"
  else fail "4/3-3b secret scrub" "tail absent or topic value leaked into the audit line"; fi
}
f3

# ============================================================
# ============  slice 4/4 — step-6 review fold-ins  ==========
# F1 SESSION-ID GLOB transcript resolution (C2 amendment), F3 poke timeout
# (C4 amendment B), F4 goal-id validation (C1 addendum).

echo "=== 4/4-1 (F1): transcript resolved by SESSION-ID GLOB, not cwd→project-dir transform ==="
# false-green-2 rewrite. The retired harness planted transcripts via the poker's
# OWN project_dir_for_cwd, so its buggy [/.]-only mapping always "found" what it
# planted — grading the poker against its own mapping. Here the transcript is
# planted at the REAL Claude-Code path — the FULL cwd sanitized [^a-zA-Z0-9]→- —
# computed INDEPENDENTLY (hardcoded literal below, never via a poker function). An
# underscore-bearing cwd is exactly where the shipped transform silently diverged:
# it preserved '_', so it looked in the wrong project dir, the transcript went
# unfound, quiet collapsed to 0, and a real stall was misclassified IDLE (not
# IDLE_STALLED) — defeating stall/wedge detection.
f1_glob() {
  new_home
  local cwd="/tmp/bn_fix/my_proj" sid="sid-underscore-glob"
  # Independent hardcoded expected project dir (apply [^a-zA-Z0-9]→- BY HAND):
  #   /tmp/bn_fix/my_proj  →  -tmp-bn-fix-my-proj
  local realdir="$HOME/.claude/projects/-tmp-bn-fix-my-proj"
  mkdir -p "$realdir"
  local t="$realdir/$sid.jsonl"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"continue"}}' > "$t"
  set_mtime_age "$t" 300            # >180 → IDLE_STALLED iff the transcript is found
  local plan="$HOME/plans/uscore.plan.md"; plant_plan "$plan" 4 0 continuous
  plant_goal uscore "$plan" "$cwd" "$sid" 4242
  stub_registry_state idle "$sid"
  assert_classify uscore IDLE_STALLED "F1 underscore cwd: sid-glob finds real transcript → IDLE_STALLED"

  # Regression: an old-style (no-underscore) cwd — the [/.] transform and the real
  # [^a-zA-Z0-9] sanitizer agree here, so the glob subsumes the mapping and finds
  # the transcript by sid regardless of the project-dir name.
  local cwd2="/tmp/plain/proj" sid2="sid-plain-glob"
  local realdir2="$HOME/.claude/projects/-tmp-plain-proj"
  mkdir -p "$realdir2"
  local t2="$realdir2/$sid2.jsonl"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"continue"}}' > "$t2"
  set_mtime_age "$t2" 300
  local plan2="$HOME/plans/plain.plan.md"; plant_plan "$plan2" 4 0 continuous
  plant_goal plainx "$plan2" "$cwd2" "$sid2" 4242
  stub_registry_state idle "$sid2"
  assert_classify plainx IDLE_STALLED "F1 non-underscore cwd: sid-glob finds old-style path → IDLE_STALLED"
}
f1_glob

echo "=== 4/4-2 (F3): poke timeout — a hung poke is alarmed, POKE-TIMEOUT audited, counts to cap, lock released ==="
# A hung `claude --resume` otherwise holds the poker's own lock forever (every
# later poll sees a live holder and exits) → one hung poke stalls the whole relay.
# The perl-alarm wrapper SIGALRM-kills our own timed-out child (process hygiene,
# not the no-force verb — that protects TARGET sessions).
f3_timeout() {
  new_home
  local cwd; cwd=$(real_cwd f4t)
  arm_goal at4 4 "$cwd" sid-t4 4242 200 user     # idle + 200s → IDLE_STALLED (pokeable)
  stub_registry_state idle sid-t4
  : > "$HOME/.claude/.stub/poke-block"           # stub busy-works past POKE_TIMEOUT
  POKE_TIMEOUT=2 run_poker                        # poll1: poke hangs → alarmed
  assert_eq "4/4-2 poker exits 0 after a timed-out poke (run completes, lock released)" 0 "$POKER_EXIT"
  assert_contains "4/4-2 POKE-TIMEOUT audit line emitted" "at4 POKE-TIMEOUT" "$(audit_of)"
  assert_contains "4/4-2 the timed-out poke was still attempted (argv recorded)" "--resume sid-t4" "$(claude_calls)"
  TOTAL=$((TOTAL + 1))
  if [ ! -d "$HOME/.claude/sdlc-poker.lock" ]; then pass "4/4-2 poker lock released after a timed-out poke"; else fail "4/4-2 lock leaked after timeout"; fi
  POKE_TIMEOUT=2 run_poker                        # poll2: count 2
  POKE_TIMEOUT=2 run_poker                        # poll3: count 3 (cap reached)
  POKE_TIMEOUT=2 run_poker                        # poll4: cap exhausted → POKE-FAIL, no poke
  assert_eq "4/4-2 timed-out pokes count toward POKE_CAP (exactly 3 attempts)" "3" "$(count_lines "$(claude_calls)" "resume sid-t4")"
  assert_contains "4/4-2 POKE-FAIL fires once the cap of timed-out pokes is exhausted" "Title: at4: POKE-FAIL" "$(curl_calls)"
  rm -f "$HOME/.claude/.stub/poke-block"

  # A fast rc=0 poke (no block) is unaffected by the timeout wrapper.
  new_home
  cwd=$(real_cwd f4f)
  arm_goal at4f 4 "$cwd" sid-t4f 4242 200 user
  stub_registry_state idle sid-t4f
  POKE_TIMEOUT=2 run_poker
  assert_contains "4/4-2 a fast poke under the timeout succeeds (normal POKE rc=0 audit)" "resume sid-t4f rc=0" "$(audit_of)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(audit_of)" | grep -q "at4f POKE-TIMEOUT"; then pass "4/4-2 a fast poke never audits POKE-TIMEOUT"; else fail "4/4-2 fast poke wrongly timed out"; fi
}
f3_timeout

echo "=== 4/4-3 (F4): goal-id validation — filename must match ^[a-z0-9-]+\$; invalid → MALFORMED-RECORD + skip ==="
# ids reach paths and notification titles; harden the consent-registry boundary.
# The bad goal is otherwise WELL-FORMED (all keys, continuous plan) so ONLY the id
# check can reject it; a valid-id goal in the same run proves the run continues.
f4_id() {
  new_home
  local badplan="$HOME/plans/badid.plan.md"; plant_plan "$badplan" 4 0 continuous
  local bf="$HOME/.claude/sdlc-goals/Bad_ID!"
  {
    echo "PLAN=$badplan"; echo "CWD=/proj/badid"; echo "SESSION_ID=sid-badid"
    echo "PID=4242"; echo "ARMED_AT=2026-07-21T00:00:00Z"
  } > "$bf"
  arm_goal okid 4 /proj/okid sid-okid 4242 30 user
  stub_registry_state idle sid-okid
  run_poker
  assert_eq "4/4-3 poker exit 0 despite an invalid goal-id" 0 "$POKER_EXIT"
  assert_contains "4/4-3 MALFORMED-RECORD audit for the invalid goal-id" "Bad_ID! MALFORMED-RECORD" "$(audit_of)"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$HOME/.claude/sdlc-status/Bad_ID!.md" ]; then pass "4/4-3 invalid-id goal skipped (no status, never poked)"; else fail "4/4-3 invalid id was processed"; fi
  assert_true "4/4-3 run continued to the valid-id goal (status written)" status_exists okid
}
f4_id

# ============================================================
echo ""
echo "========================================"
echo "sdlc-poker core: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
