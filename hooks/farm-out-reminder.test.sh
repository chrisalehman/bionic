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

stdin_for() {  # $1=command $2=agent_type ("" = main thread) $3=session_id (default s-fixture)
  local at="" sid="${3:-s-fixture}"
  [ -n "${2:-}" ] && at=",\"agent_id\":\"a-fixture-$2\",\"agent_type\":\"$2\""
  printf '{"session_id":"%s","transcript_path":"/tmp/t.jsonl","cwd":"%s","prompt_id":"p-1","permission_mode":"bypassPermissions"%s,"effort":{"level":"high"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s,"description":"fixture"},"tool_use_id":"toolu_fixture"}' \
    "$sid" "$SANDBOX" "$at" "$(printf '%s' "$1" | jq -Rs .)"
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
assert_nudge_has() { printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qF "$2" && pass || fail "$1"; }
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
echo "=== N8: missing agent_type key entirely (real main JSON) → classified MAIN → deny (4/2 landed; see R8′) ==="
n8() {
  setup
  run_hook "$(stdin_for 'bash test.sh' '')"   # stdin_for '' omits agent_id/agent_type keys entirely
  assert_deny "N8 missing-keys classifies main → tier-1 deny (was silent under 4/1 skeleton)"
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
# Tier-1 DENY (AC-1) — every class fires on a planted main-thread
# fixture; deny reason names role + original command + override token.
# ============================================================

echo ""
echo "=== D1: bash test.sh (main) → deny; reason has role + command + override token ==="
d1() {
  setup
  run_hook "$(stdin_for 'bash test.sh' '')"
  assert_deny "D1 bash test.sh → deny"
  assert_reason_has "D1 reason names role test-runner" "test-runner"
  assert_reason_has "D1 reason embeds original command" "bash test.sh"
  assert_reason_has "D1 reason names override token" "FARM_OUT_ALLOW=1"
}
d1

echo ""
echo "=== D2: bash tests/run.sh (main) → deny, class=suite ==="
d2() {
  setup
  run_hook "$(stdin_for 'bash tests/run.sh' '')"
  assert_deny "D2 bash tests/run.sh → deny"
  assert_audit_has "D2 audit class=suite" "farm-out deny: class=suite"
}
d2

echo ""
echo "=== D3: bash hooks/context-spend.test.sh (main) → deny, class=suite ==="
d3() {
  setup
  run_hook "$(stdin_for 'bash hooks/context-spend.test.sh' '')"
  assert_deny "D3 *.test.sh → deny"
  assert_audit_has "D3 audit class=suite" "farm-out deny: class=suite"
}
d3

echo ""
echo "=== D4: pnpm test / pytest / cargo test / go test ./... / make test → deny each ==="
d4() {
  local cmd
  for cmd in 'pnpm test' 'pytest' 'cargo test' 'go test ./...' 'make test'; do
    setup
    run_hook "$(stdin_for "$cmd" '')"
    assert_deny "D4 [$cmd] → deny"
  done
}
d4

echo ""
echo "=== D5: ./claude-bootstrap.sh (main) → deny, class=bootstrap, role=implementor ==="
d5() {
  setup
  run_hook "$(stdin_for './claude-bootstrap.sh' '')"
  assert_deny "D5 bootstrap → deny"
  assert_audit_has "D5 audit class=bootstrap" "farm-out deny: class=bootstrap"
  assert_reason_has "D5 reason names role implementor" "implementor"
}
d5

echo ""
echo "=== D6: npm install / pip install / brew install / uv sync → deny each, class=install ==="
d6() {
  local cmd
  for cmd in 'npm install' 'pip install requests' 'brew install jq' 'uv sync'; do
    setup
    run_hook "$(stdin_for "$cmd" '')"
    assert_deny "D6 [$cmd] → deny"
    assert_audit_has "D6 [$cmd] audit class=install" "farm-out deny: class=install"
  done
}
d6

echo ""
echo "=== D7: pnpm run build / docker build . / cargo build / make → deny each, class=build ==="
d7() {
  local cmd
  for cmd in 'pnpm run build' 'docker build .' 'cargo build' 'make'; do
    setup
    run_hook "$(stdin_for "$cmd" '')"
    assert_deny "D7 [$cmd] → deny"
    assert_audit_has "D7 [$cmd] audit class=build" "farm-out deny: class=build"
  done
}
d7

echo ""
echo "=== D8: cd /x && npm install && npm run build (3 segs, tier-1 seg) → deny, class=chain ==="
d8() {
  setup
  run_hook "$(stdin_for 'cd /x && npm install && npm run build' '')"
  assert_deny "D8 3-seg chain with tier-1 segment → deny"
  assert_audit_has "D8 audit class=chain" "farm-out deny: class=chain"
}
d8

# ============================================================
# Wrapper closure (AC-1) — one-level unwrap; a wrapper whose inner
# matches tier-1 is tier-1 (workaround closure).
# ============================================================

echo ""
echo "=== W1: sh -c 'bash test.sh' → deny (unwrap) ==="
w1() {
  setup
  run_hook "$(stdin_for "sh -c 'bash test.sh'" '')"
  assert_deny "W1 sh -c 'bash test.sh' → deny"
}
w1

echo ""
echo "=== W2: bash -c \"pnpm test\" → deny ==="
w2() {
  setup
  run_hook "$(stdin_for 'bash -c "pnpm test"' '')"
  assert_deny "W2 bash -c \"pnpm test\" → deny"
}
w2

echo ""
echo "=== W3: eval bash tests/run.sh → deny ==="
w3() {
  setup
  run_hook "$(stdin_for 'eval bash tests/run.sh' '')"
  assert_deny "W3 eval bash tests/run.sh → deny"
}
w3

echo ""
echo "=== W4: bash <(cat test.sh) → deny (process-sub closure; inner names test.sh) ==="
w4() {
  setup
  run_hook "$(stdin_for 'bash <(cat test.sh)' '')"
  assert_deny "W4 bash <(cat test.sh) → deny"
}
w4

echo ""
echo "=== W5: nohup bash test.sh / timeout 600 bash test.sh → deny each ==="
w5() {
  local cmd
  for cmd in 'nohup bash test.sh' 'timeout 600 bash test.sh'; do
    setup
    run_hook "$(stdin_for "$cmd" '')"
    assert_deny "W5 [$cmd] → deny"
  done
}
w5

# ============================================================
# Override (AC-1/AC-3) — FARM_OUT_ALLOW=1 proceeds (no decision
# emitted) AND logs a loud, sanctioned override line.
# ============================================================

echo ""
echo "=== O1: FARM_OUT_ALLOW=1 bash test.sh → no decision emitted, audit override ==="
o1() {
  setup
  run_hook "$(stdin_for 'FARM_OUT_ALLOW=1 bash test.sh' '')"
  assert_silent "O1 override → exit 0, no permissionDecision emitted"
  assert_audit_has "O1 audit override line present" "farm-out override:"
}
o1

echo ""
echo "=== O2: env FARM_OUT_ALLOW=1 bash test.sh → same (protect-main env-prefix form) ==="
o2() {
  setup
  run_hook "$(stdin_for 'env FARM_OUT_ALLOW=1 bash test.sh' '')"
  assert_silent "O2 env-prefixed override → exit 0, no decision"
  assert_audit_has "O2 audit override line present" "farm-out override:"
}
o2

# ============================================================
# Audit shape (AC-5) — one line per event in the log_finding shape;
# exempt commands never log.
# ============================================================

echo ""
echo "=== A1: D1 deny → exact audit line 'farm-out deny: class=suite mode=block' ==="
a1() {
  setup
  run_hook "$(stdin_for 'bash test.sh' '')"
  assert_audit_has "A1 exact deny line shape" "farm-out deny: class=suite mode=block"
}
a1

echo ""
echo "=== A2: git status (exempt) → no audit line ==="
a2() {
  setup
  run_hook "$(stdin_for 'git status' '')"
  assert_audit_absent "A2 exempt command never logs" "farm-out"
}
a2

# ============================================================
# Modes (AC-2) — advisory downgrades tier-1 deny to a nudge and
# logs deny-downgraded.
# ============================================================

echo ""
echo "=== G1: bash test.sh with farm-out-mode: advisory → nudge not deny; audit deny-downgraded ==="
g1() {
  setup
  printf 'farm-out-mode: advisory\n' > "$SANDBOX/.bionic/config.yaml"
  run_hook "$(stdin_for 'bash test.sh' '')"
  assert_nudge "G1 advisory → nudge (additionalContext), not deny"
  assert_audit_has "G1 audit deny-downgraded" "farm-out deny-downgraded: class=suite"
}
g1

# ============================================================
# Meta-evidence (AC-3) — planted stub hooks prove the suite catches
# a hook that STOPS denying AND one that STARTS over-blocking.
# ============================================================

echo ""
echo "=== M1: silent stub must NOT satisfy the deny check (suite catches a dead deny) ==="
m1() {
  setup
  local stub="$SANDBOX/stub-silent.sh"
  printf '#!/bin/bash\nexit 0\n' > "$stub"
  local saved="$HOOK"; HOOK="$stub"
  run_hook "$(stdin_for 'bash test.sh' '')"
  HOOK="$saved"
  if printf '%s' "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    fail "M1 meta: silent stub wrongly passed the deny check — suite blind to a dead deny"
  else
    pass
  fi
}
m1

echo ""
echo "=== M2: deny-everything stub must break an exempt-silent case (suite catches over-blocking) ==="
m2() {
  setup
  local stub="$SANDBOX/stub-denyall.sh"
  cat > "$stub" <<'STUB'
#!/bin/bash
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"stub-denies-all"}}'
exit 0
STUB
  local saved="$HOOK"; HOOK="$stub"
  run_hook "$(stdin_for 'git status' '')"
  HOOK="$saved"
  if [ -n "$HOOK_STDOUT" ] && printf '%s' "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    pass
  else
    fail "M2 meta: deny-all stub produced no deny for an exempt cmd — suite blind to over-blocking"
  fi
}
m2

# ============================================================
# R8′ — N8 re-assertion: real main JSON (no agent keys) + bash test.sh
# → deny (missing keys degrade toward MORE enforcement, never silence).
# ============================================================

echo ""
echo "=== R8′: real main JSON (no agent_type/agent_id) + bash test.sh → deny ==="
r8prime() {
  setup
  run_hook "$(stdin_for 'bash test.sh' '')"   # stdin_for '' omits agent_id/agent_type keys entirely
  assert_deny "R8′ missing-keys classifies MAIN → tier-1 deny"
}
r8prime

# ============================================================
# Tier-2 NUDGE + cooldown (AC-2) — fuzzy production-shaped commands
# get ONE additionalContext nudge per (session, class); a repeat within
# the same session is suppressed. State: .bionic/tmp/farm-out.state,
# lines session_id<TAB>class.
# ============================================================

echo ""
echo "=== T1: git clone … (main) → nudge + audit nudge:class=clone ==="
t1() {
  setup
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_nudge "T1 git clone → nudge (additionalContext)"
  assert_audit_has "T1 audit nudge class=clone" "farm-out nudge: class=clone"
}
t1

echo ""
echo "=== T2: git clone twice same session → 2nd silent + audit suppressed ==="
t2() {
  setup
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_nudge "T2 first git clone → nudge"
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_silent "T2 second git clone same session → suppressed (silent)"
  assert_audit_has "T2 audit suppressed class=clone" "farm-out suppressed: class=clone"
}
t2

echo ""
echo "=== T3: different class (npx …) same session after clone → nudge ==="
t3() {
  setup
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_nudge "T3 prime cooldown with clone → nudge"
  run_hook "$(stdin_for 'npx create-react-app demo' '')"
  assert_nudge "T3 npx (pkg-exec) uncooled class → nudge"
  assert_audit_has "T3 audit nudge class=pkg-exec" "farm-out nudge: class=pkg-exec"
}
t3

echo ""
echo "=== T4: same class, different session_id → nudge (state keyed by session) ==="
t4() {
  setup
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_nudge "T4 session s-fixture clone → nudge"
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '' 's-other')"
  assert_nudge "T4 session s-other same class → nudge (not suppressed)"
}
t4

echo ""
echo "=== T5: 3-seg exempt-only chain (git add && git commit && git log) → silent ==="
t5() {
  setup
  run_hook "$(stdin_for 'git add -A && git commit -m wip && git log --oneline -1' '')"
  assert_silent "T5 exempt-only chain → silent"
  assert_audit_absent "T5 no audit line" "farm-out"
}
t5

echo ""
echo "=== T6: 3-seg mixed non-tier-1 chain (mkdir && curl && tar) → nudge class=chain ==="
t6() {
  setup
  run_hook "$(stdin_for 'mkdir out && curl -o out/f.tgz https://ex/f && tar xf out/f.tgz' '')"
  assert_nudge "T6 mixed non-tier-1 chain → nudge"
  assert_audit_has "T6 audit nudge class=chain" "farm-out nudge: class=chain"
}
t6

echo ""
echo "=== T7: unwritable state dir (chmod 555 .bionic/tmp) → nudge still emitted ==="
t7() {
  setup
  chmod 555 "$SANDBOX/.bionic/tmp"
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_nudge "T7 unwritable state dir → nudge still emitted (degrade loud)"
  chmod u+rwx "$SANDBOX/.bionic/tmp" 2>/dev/null || true
}
t7

echo ""
echo "=== T8: nudge JSON names subagent_type: implementor ==="
t8() {
  setup
  run_hook "$(stdin_for 'git clone https://github.com/foo/bar.git' '')"
  assert_nudge_has "T8 nudge additionalContext names subagent_type: implementor" "subagent_type: implementor"
}
t8

# ============================================================
# Make-target build coverage (critic F1) + segment anchoring
# (critic F2b). `make <target>` is tier-1 build EXCEPT `make clean`
# (trivial → silent) and `make test` (suite arm wins, not build).
# install/build regexes anchor on (^|[;&| ]) so a post-separator
# segment classifies like the suite/bootstrap arms already do —
# while a substring inside a word (remake) still never matches.
# ============================================================

echo ""
echo "=== F1: make build/release/all/dist/install → deny class=build ==="
f1() {
  local cmd
  for cmd in 'make build' 'make release' 'make all' 'make dist' 'make install'; do
    setup
    run_hook "$(stdin_for "$cmd" '')"
    assert_deny "F1 [$cmd] → deny"
    assert_audit_has "F1 [$cmd] audit class=build" "farm-out deny: class=build"
  done
}
f1

echo ""
echo "=== F2: make clean → silent (trivial exemption, no audit) ==="
f2() {
  setup
  run_hook "$(stdin_for 'make clean' '')"
  assert_silent "F2 make clean → silent"
  assert_audit_absent "F2 no audit line" "farm-out"
}
f2

echo ""
echo "=== F3: make test → still deny class=suite (regression; suite arm wins over build) ==="
f3() {
  setup
  run_hook "$(stdin_for 'make test' '')"
  assert_deny "F3 make test → deny"
  assert_audit_has "F3 audit class=suite" "farm-out deny: class=suite"
}
f3

echo ""
echo "=== F4: true ; npm install → deny class=install (segment anchor after ;) ==="
f4() {
  setup
  run_hook "$(stdin_for 'true ; npm install' '')"
  assert_deny "F4 true ; npm install → deny"
  assert_audit_has "F4 audit class=install" "farm-out deny: class=install"
}
f4

echo ""
echo "=== F5: true ; cargo build → deny class=build (segment anchor after ;) ==="
f5() {
  setup
  run_hook "$(stdin_for 'true ; cargo build' '')"
  assert_deny "F5 true ; cargo build → deny"
  assert_audit_has "F5 audit class=build" "farm-out deny: class=build"
}
f5

echo ""
echo "=== F6: echo remake → silent (word-boundary discipline; 'make' inside a word) ==="
f6() {
  setup
  run_hook "$(stdin_for 'echo remake' '')"
  assert_silent "F6 echo remake → silent"
  assert_audit_absent "F6 no audit line" "farm-out"
}
f6

echo ""
echo "=== F7: bash test.sh; echo done → deny class=suite (terminator unify; trailing ;) ==="
f7() {
  setup
  run_hook "$(stdin_for 'bash test.sh; echo done' '')"
  assert_deny "F7 bash test.sh; echo done → deny"
  assert_audit_has "F7 audit class=suite" "farm-out deny: class=suite"
}
f7

echo ""
echo "=== F8: npm ci → deny class=install (ci ratified into closed set; regression guard) ==="
f8() {
  setup
  run_hook "$(stdin_for 'npm ci' '')"
  assert_deny "F8 npm ci → deny"
  assert_audit_has "F8 audit class=install" "farm-out deny: class=install"
}
f8

# ============================================================
# Results
# ============================================================
echo ""
echo "farm-out-reminder: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
