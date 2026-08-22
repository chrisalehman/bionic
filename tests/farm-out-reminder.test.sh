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
# Usage: bash tests/farm-out-reminder.test.sh
set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
HOOK="${BIONIC_HOOKS_DIR}/farm-out-reminder.sh"
PASS=0; FAIL=0; TOTAL=0
pass() { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "FAIL: $1" >&2; }

SANDBOXES=()
cleanup() { for d in "${SANDBOXES[@]:-}"; do [ -n "$d" ] && chmod -R u+rwx "$d" 2>/dev/null; rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

setup() {  # fresh sandbox project per case
  SANDBOX=$(mktemp -d); mkdir -p "$SANDBOX/.bionic/tmp"
  SANDBOXES+=("$SANDBOX")
  # The fake HOME is a SIBLING of the sandbox project, never a child: SEC3/SEC4
  # assert "nothing under the project tree" with `find "$SANDBOX"`, which a
  # nested home would satisfy falsely. A real $HOME is not inside a project.
  FAKE_HOME=$(mktemp -d); SANDBOXES+=("$FAKE_HOME")
}
# Incident 0001: the audit file lives under $HOME, never in the project tree.
# Slug must match hooks/farm-out-reminder.sh audit_path() byte for byte.
slug_for() { printf '%s-%s' "$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')" \
                            "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
audit_file() { printf '%s/.claude/logs/%s/sdlc-audit.md' "$FAKE_HOME" "$(slug_for "$SANDBOX")"; }

stdin_for() {  # $1=command $2=agent_type ("" = main thread) $3=session_id (default s-fixture)
  local at="" sid="${3:-s-fixture}"
  [ -n "${2:-}" ] && at=",\"agent_id\":\"a-fixture-$2\",\"agent_type\":\"$2\""
  printf '{"session_id":"%s","transcript_path":"/tmp/t.jsonl","cwd":"%s","prompt_id":"p-1","permission_mode":"bypassPermissions"%s,"effort":{"level":"high"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s,"description":"fixture"},"tool_use_id":"toolu_fixture"}' \
    "$sid" "$SANDBOX" "$at" "$(printf '%s' "$1" | jq -Rs .)"
}

run_hook() {  # stdin on $1
  # HOME is sandboxed on EVERY invocation — the hook writes under $HOME now,
  # and an inherited real HOME would append to the developer's own logs.
  HOOK_STDOUT=$(printf '%s' "$1" | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$SANDBOX" bash "$HOOK" 2>/dev/null)
  HOOK_EXIT=$?
}

assert_exit0()  { [ "$HOOK_EXIT" -eq 0 ] && pass || fail "$1 (exit=$HOOK_EXIT)"; }
assert_silent() { [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDOUT" ] && pass || fail "$1 (exit=$HOOK_EXIT out=$HOOK_STDOUT)"; }
assert_deny()   { printf '%s' "$HOOK_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 && pass || fail "$1"; }
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
echo "=== I5: unwritable .bionic/tmp (chmod 555) → nudge still emitted, exit 0 ==="
# The hook's ONLY project-tree write is nudge_once()'s
# $PROJECT_DIR/.bionic/tmp/farm-out.state (farm-out-reminder.sh:174-175), so
# .bionic/tmp is the sole directory whose permissions this hook can trip over.
# Two things make this case discriminating, and both are load-bearing:
#   - a TIER-2 command. Tier-1 (`bash test.sh`) denies and exits at emit_tier1
#     without ever reaching nudge_once, so the chmod would be unreachable.
#   - asserting the state file is ABSENT. Without it the case passes whether or
#     not the chmod took effect, which is how the pre-2026-07-27 version — which
#     chmod'd .bionic/memory, a directory the hook never touched — passed
#     vacuously for its entire life.
i5() {
  setup
  chmod 555 "$SANDBOX/.bionic/tmp"
  run_hook "$(stdin_for 'npx cowsay hi' '')"
  assert_exit0 "I5 unwritable .bionic/tmp → exit 0"
  assert_nudge "I5 nudge still emitted despite unwritable state dir"
  # Proves the unwritable path was actually exercised: the append is `|| true`,
  # so a writable dir would leave the file behind here.
  [ ! -f "$SANDBOX/.bionic/tmp/farm-out.state" ] \
    && pass || fail "I5 state file should not exist (chmod did not take effect)"
  chmod u+rwx "$SANDBOX/.bionic/tmp" 2>/dev/null || true
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
echo "=== D1: bash test.sh (main) → deny ==="
d1() {
  setup
  run_hook "$(stdin_for 'bash test.sh' '')"
  assert_deny "D1 bash test.sh → deny"
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
echo "=== D3: bash tests/context-spend.test.sh (main) → deny, class=suite ==="
d3() {
  setup
  run_hook "$(stdin_for 'bash tests/context-spend.test.sh' '')"
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
echo "=== D5: ./claude-bootstrap.sh (main) → deny, class=bootstrap ==="
d5() {
  setup
  run_hook "$(stdin_for './claude-bootstrap.sh' '')"
  assert_deny "D5 bootstrap → deny"
  assert_audit_has "D5 audit class=bootstrap" "farm-out deny: class=bootstrap"
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

echo ""
echo "=== O3: cd /x && FARM_OUT_ALLOW=1 bash tests/run.sh (mid-chain, W4's false-fire shape) → override, silent ==="
o3() {
  setup
  run_hook "$(stdin_for 'cd /x && FARM_OUT_ALLOW=1 bash tests/run.sh' '')"
  assert_silent "O3 mid-chain override (2-seg &&) → exit 0, no decision"
  assert_audit_has "O3 audit override line present" "farm-out override:"
}
o3

echo ""
echo "=== O4: npm install && FARM_OUT_ALLOW=1 (trailing position, tier-1 seg precedes) → override, silent ==="
o4() {
  setup
  run_hook "$(stdin_for 'npm install && FARM_OUT_ALLOW=1' '')"
  assert_silent "O4 trailing-position override → exit 0, no decision"
  assert_audit_has "O4 audit override line present" "farm-out override:"
}
o4

echo ""
echo "=== O5: cd /x; env FARM_OUT_ALLOW=1 bash tests/run.sh (semicolon, env-prefixed, mid-chain) → override, silent ==="
o5() {
  setup
  run_hook "$(stdin_for 'cd /x; env FARM_OUT_ALLOW=1 bash tests/run.sh' '')"
  assert_silent "O5 semicolon env-prefixed mid-chain override → exit 0, no decision"
  assert_audit_has "O5 audit override line present" "farm-out override:"
}
o5

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
# F5 / AC-5: bootstrap arm anchors to COMMAND position.
# Reading the script is not running it (field annoyance 2026-07-22:
# ls/wc/grep on claude-bootstrap.sh were denied as bootstrap-class).
setup
run_hook "$(stdin_for 'ls claude-bootstrap.sh' '')"
assert_silent "AC-5a: ls claude-bootstrap.sh is not a bootstrap run"
run_hook "$(stdin_for 'wc -l claude-bootstrap.sh' '')"
assert_silent "AC-5a: wc -l claude-bootstrap.sh silent"
run_hook "$(stdin_for 'grep -n cert claude-bootstrap.sh' '')"
assert_silent "AC-5a: grep on claude-bootstrap.sh silent"
run_hook "$(stdin_for 'cat hooks/../claude-bootstrap.sh' '')"
assert_silent "AC-5a: cat path/claude-bootstrap.sh silent"
run_hook "$(stdin_for 'shasum -a 256 claude-reset.sh' '')"
assert_silent "AC-5a: shasum claude-reset.sh silent"

run_hook "$(stdin_for './claude-bootstrap.sh' '')"
assert_deny "AC-5b: ./claude-bootstrap.sh still denied"
run_hook "$(stdin_for 'bash claude-bootstrap.sh' '')"
assert_deny "AC-5b: bash claude-bootstrap.sh denied"
run_hook "$(stdin_for 'bash /some/path/claude-reset.sh' '')"
assert_deny "AC-5b: bash /path/claude-reset.sh denied"
run_hook "$(stdin_for 'echo prep; ./claude-bootstrap.sh' '')"
assert_deny "AC-5b: post-separator execution denied"

# ============================================================
# SEC — incident 0001: no command-derived text in any sink.
# FAKE_SECRET is a planted constant, never a real credential.
# ============================================================
FAKE_SECRET="deadbeefcafebabe0123456789abcdef0123456789abcdefdeadbeefcafeb00f"

echo ""
echo "=== SEC1: audit line carries no command text (AC-1) ==="
sec1() {
  setup
  run_hook "$(stdin_for "sed -i 's/$FAKE_SECRET/x/' notes.md && npm install" '')"
  assert_deny "SEC1 denies"
  # Two segments only, so the chain arm (>=3) does not fire — the `npm install`
  # segment classifies this as class=install. Which class is incidental to AC-1;
  # the assertion only needs an audit line to exist at all.
  assert_audit_has    "SEC1 audit still records the class" "farm-out deny: class=install"
  assert_audit_absent "SEC1 audit omits the planted secret" "$FAKE_SECRET"
  assert_audit_absent "SEC1 audit omits command text"       "notes.md"
}
sec1

echo ""
echo "=== SEC2: deny reason scrubbed + bounded (AC-2) ==="
sec2() {
  setup
  # The secret sits past char 120 so a truncate-first implementation would
  # still pass a naive check — this case pins scrub-BEFORE-truncate.
  local pad="cd /some/fairly/long/path/that/pushes/the/secret/past/the/bound &&"
  run_hook "$(stdin_for "$pad TOKEN=$FAKE_SECRET npm install" '')"
  assert_deny "SEC2 denies"
  local reason; reason=$(printf '%s' "$HOOK_STDOUT" \
    | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)
  printf '%s' "$reason" | grep -qF "$FAKE_SECRET" \
    && fail "SEC2 deny reason leaks the planted secret" || pass
  printf '%s' "$reason" | grep -qE '[A-Fa-f0-9]{32,}' \
    && fail "SEC2 deny reason leaks a hex run" || pass

  # Ordering probe. The fixture above does NOT actually discriminate: the
  # `TOKEN=` arm redacts the fragment even when truncation runs first, so a
  # truncate-first build passes every assertion above (verified by mutation).
  # This fixture removes that rescue — a BARE hex run starting at char 99, so
  # `cut -c1-120` leaves a 22-char fragment that is below the {32,} threshold
  # and matches neither scrub rule. Truncate-first leaks `deadbeefcafebabe0123`;
  # scrub-first redacts the whole run. Do not "fix" a failure here by
  # reordering — the ordering IS the property under test.
  setup
  local deep="/opt/vendor/build/artifacts/staging/release/candidate/deep/nested/tree/leaf/dir"
  run_hook "$(stdin_for "cd $deep && npm install $FAKE_SECRET" '')"
  assert_deny "SEC2b denies"
  local r2; r2=$(printf '%s' "$HOOK_STDOUT" \
    | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)
  printf '%s' "$r2" | grep -qF "${FAKE_SECRET:0:20}" \
    && fail "SEC2b truncation split a hex run and leaked a secret prefix" || pass
}
sec2

echo ""
echo "=== SEC3: audit file lands under HOME, never in the project tree (AC-3) ==="
sec3() {
  setup
  run_hook "$(stdin_for 'bash tests/run.sh' '')"
  assert_audit_has "SEC3 line at relocated path" "farm-out deny: class=suite"
  [ -z "$(find "$SANDBOX" -name 'sdlc-audit.md' 2>/dev/null)" ] \
    && pass || fail "SEC3 no audit file anywhere under the project tree"
}
sec3

echo ""
echo "=== SEC4: unwritable destination drops the line, never falls back (AC-4) ==="
sec4() {
  setup
  chmod a-w "$FAKE_HOME" 2>/dev/null
  run_hook "$(stdin_for 'bash tests/run.sh' '')"
  assert_exit0 "SEC4 hook still exits 0"
  assert_deny  "SEC4 enforcement unaffected"
  [ -z "$(find "$SANDBOX" -name 'sdlc-audit.md' 2>/dev/null)" ] \
    && pass || fail "SEC4 no fallback into the project tree"
  chmod u+w "$FAKE_HOME" 2>/dev/null
}
sec4

echo ""
echo "=== SEC5: slug is deterministic and collision-resistant (AC-5) ==="
sec5() {
  local a b
  a=$(slug_for /tmp/alpha/myproj); b=$(slug_for /tmp/beta/myproj)
  [ "$a" = "$(slug_for /tmp/alpha/myproj)" ] && pass || fail "SEC5 slug is deterministic"
  [ "$a" != "$b" ] && pass || fail "SEC5 same basename, different parent → different slug"
}
sec5

echo ""
echo "=== SEC5b: collision-resistance through the REAL hook (AC-5) ==="
sec5b() {
  # SEC5 only exercises the harness's slug_for copy. This case drives two
  # project roots with the SAME basename under different parents through the
  # hook itself and requires two distinct audit files under one HOME. A
  # basename-only slug (the plausible wrong audit_path) collapses them to one.
  local root; root=$(mktemp -d); SANDBOXES+=("$root")
  FAKE_HOME=$(mktemp -d); SANDBOXES+=("$FAKE_HOME")
  local p
  for p in "$root/alpha/myproj" "$root/beta/myproj"; do
    SANDBOX="$p"; mkdir -p "$SANDBOX/.bionic/tmp"
    run_hook "$(stdin_for 'bash tests/run.sh' '')"
    assert_deny "SEC5b deny under $(basename "$(dirname "$p")")/myproj"
    assert_audit_has "SEC5b audit line under $(basename "$(dirname "$p")")/myproj" \
      "farm-out deny: class=suite"
  done
  [ "$(find "$FAKE_HOME" -name 'sdlc-audit.md' 2>/dev/null | wc -l | tr -d ' ')" -eq 2 ] \
    && pass || fail "SEC5b same-basename projects must not share one audit file"
}
sec5b

# ============================================================
# Results
# ============================================================
echo ""
echo "farm-out-reminder: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
