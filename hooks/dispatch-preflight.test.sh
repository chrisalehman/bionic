#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE (epic-15 wave-01R).
#
# PreToolUse|Agent. Serves AC-2, and the start-side share of AC-9/AC-10.
#
# Governing design: design/orchestrator-subagent-coordination.md §4 "The start
# gate", §3.4 Starting, §7 (fail-direction table).
#
# HERMETIC. Every payload is crafted and piped straight into the script under
# test; nothing here dispatches a real Agent tool call, touches the live
# installed hooks, or depends on a live wave. Repos are throwaway git inits
# under a mktemp'd sandbox; attestations are written directly as fixtures
# (never by invoking the real preflight-probe.sh), except in the S9
# runnability check, which installs a COPY of the real producer into a
# sandboxed HOME specifically to prove its fix command executes.
#
# Usage: bash hooks/dispatch-preflight.test.sh

set -uo pipefail

GATE="$(cd "$(dirname "$0")" && pwd)/dispatch-preflight.sh"
PROBE_SRC="$(cd "$(dirname "$0")" && pwd)/preflight-probe.sh"
SWEEPER_SRC="$(cd "$(dirname "$0")" && pwd)/session-sweeper.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dispatch-preflight-test.XXXXXX")" && pwd)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS; do kill -9 "$p" 2>/dev/null; done
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0

# ---------- assertions ----------

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_absent()   { if printf '%s' "$3" | grep -qF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design / rule
# fixtures-can-pin-away-the-test).
#
# Source: .bionic/docs/record/epic-15-kill-interception-experiment.md, CLI
# 2.1.220 verbatim captures.
#
#   * PreToolUse payload ENVELOPE — FAITHFUL to §2.2, field for field:
#     session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
#     hook_event_name, tool_name, tool_input, tool_use_id. §2.2 is captured
#     for tool_name:"TaskStop", but §2.1/§2.12 establish this is the SAME
#     builder for every PreToolUse invocation (only tool_name/tool_input
#     differ) — the matcher "Task" matching tool_name "Agent" (§2.12,
#     confirmed live in §2.1) independently corroborates that "Agent" is the
#     real tool_name value for a subagent dispatch.
#   * tool_name:"Agent" value and tool_input SHAPE — FAITHFUL as of slice 4/3
#     to .bionic/docs/record/w3-slice1-posttooluse-probe.md capture E (an
#     Agent-tool payload captured live at CLI 2.1.222): tool_input carries
#     description, prompt, subagent_type, run_in_background, and — when the
#     dispatch names one — name. The earlier note here ("SHAPE-ONLY, no
#     verbatim Agent capture exists") described the pre-probe state and is
#     superseded. tool_input became load-bearing in slice 4/3: the roster row
#     is lifted from it.
#   * tool_input.model — SHAPE-EXTRAPOLATED and declared: the Agent tool
#     accepts a `model` override, but no captured payload carries one (every
#     probe dispatch inherited). It is fixtured here because the roster
#     records it WHEN PRESENT; its absence is deliberately not an absence
#     finding, and S10c drives the no-model path.
#   * dispatch brief text (BRIEF_FULL / the compact variant) — SYNTHESIZED,
#     but its LABEL GRAMMAR is the shipped one: skills/canonical-sdlc/SKILL.md
#     §Dispatch's seven-field sentence (span-pinned by
#     tests/dispatch-spans.test.sh §5d) and the exemplar brief recorded
#     verbatim at .bionic/docs/record/w2-ac3-run.md:25-40.
#   * attestation record — FAITHFUL to hooks/preflight-probe.sh's own
#     schema/comment block: `# comment` + `key=value` lines, read BY KEY
#     (checklist A6), `session_id=` the field this gate keys on (Slice 4/1
#     resolution: spelled to match the payload field name).
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, message
#     text. None is a platform surface.

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="1f4a7c02-3bd9-4e15-8a66-90c1de77b204"

# A realistic dispatch brief carrying all seven labeled contract fields in the
# shipped grammar. The DEFAULT for every payload below, because a brief that
# carries its contract fields is the ordinary case — the roster's absence
# warning must not fire on it (that is what keeps the §7 "positive pair: pass in
# silence" row true), and a fixture that omitted them would have made every
# pre-slice-4/3 pass case silently exercise the absence path instead
# (.claude memory: fixtures-can-pin-away-the-test). The absence path gets its
# own bare-brief fixture in S10c, and both directions are asserted.
BRIEF_FULL='Canonical-sdlc Step 4, slice 4/9 of epic-99 wave-01; build · audited · wave.
Your slice: implement the widget behind the existing seam.
Scope constraint: touch only lib/widget.sh and its paired suite.
Expected artifact: .bionic/docs/record/w99-widget.txt
Exit condition: the artifact exists and the paired suite is green.
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-widget.progress'

# mk_agent_payload <sid> <cwd> [prompt] [name] [model]
#
# prompt/name/model default to the contract-complete brief; pass "-" for name or
# model to omit the field from tool_input entirely (the absence cases).
mk_agent_payload() {
  local prompt="${3-$BRIEF_FULL}" name="${4-w99-impl}" model="${5-claude-sonnet-5}"
  jq -n --arg s "$1" --arg c "$2" --arg p "$prompt" --arg n "$name" --arg m "$model" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:({description:"a test dispatch", subagent_type:"implementor",
                   prompt:$p, run_in_background:true}
                  + (if $n == "-" then {} else {name:$n} end)
                  + (if $m == "-" then {} else {model:$m} end)),
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

mk_bash_payload() {  # <sid> <cwd>  — an irrelevant tool, for the A7 hoist tests
  jq -n --arg s "$1" --arg c "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:"echo hi"}, tool_use_id:"toolu_0irrelevant"}'
}

GATE_OUT=""; GATE_ERR=""; GATE_ST=0
# Set to a directory to drive the gate with a sandboxed CLAUDE_CONFIG_DIR — the
# roster prune's liveness lookup reads <config>/projects/*/<session>.jsonl, and
# the operator's REAL config dir would decide which fixtures survive otherwise.
GATE_CONFIG_DIR=""
run_gate() {  # <payload-json>
  if [ -n "$GATE_CONFIG_DIR" ]; then
    GATE_OUT=$(printf '%s' "$1" | CLAUDE_CONFIG_DIR="$GATE_CONFIG_DIR" bash "$GATE" 2>"$SANDBOX/.err")
  else
    GATE_OUT=$(printf '%s' "$1" | bash "$GATE" 2>"$SANDBOX/.err")
  fi
  GATE_ST=$?
  GATE_ERR=$(cat "$SANDBOX/.err")
  return 0
}

# ---------- roster readers (slice 4/3) ----------
#
# BY KEY, never by position — the same rule the attestation and the observation
# record already follow (checklist A6), so an added field is inert here.
roster_path()  { printf '%s/.bionic/tmp/roster-%s.state' "$1" "$2"; }
roster_rows()  { grep -v '^#' "$1" 2>/dev/null | grep -c . ; }
roster_row()   { grep -v '^#' "$1" 2>/dev/null | sed -n "${2}p"; }   # <file> <n>
roster_field() { printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

# make_repo <name> <active-wave:yes|no> -> echoes the repo path
make_repo() {
  local name="$1" wave="$2"
  local repo="$SANDBOX/$name/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  if [ "$wave" = "yes" ]; then
    mkdir -p "$repo/.bionic/docs/plans/epic-99-test"
    cat > "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 13
intent: build
rigor: audited
scale: wave
---

# Test wave plan

## SDLC State

integration-branch: main
current: 4

- Step 4: slices in flight
PLAN
  fi
  printf '%s' "$repo"
}

# write_attestation <repo> <session_id> [extra kv lines...]
#
# slice 4/2 (D-5): writes to the PER-SESSION filename, preflight-<sid>.state — the
# filename is now the primary key, matching hooks/preflight-probe.sh's own scheme.
write_attestation() {
  local repo="$1" sid="$2"; shift 2
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=1\n'
    printf 'kind=preflight-attestation\n'
    printf 'session_id=%s\n' "$sid"
    printf 'written_at=1785790000\n'
    printf 'repo=%s\n' "$repo"
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$repo/.bionic/tmp/preflight-$sid.state"
  chmod 600 "$repo/.bionic/tmp/preflight-$sid.state"
}

# write_legacy_attestation <repo> <session_id> — the OLD, pre-wave-03 single-slot
# filename. Used to prove the gate never consults it (slice 4/2).
write_legacy_attestation() {
  local repo="$1" sid="$2"
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=1\n'
    printf 'kind=preflight-attestation\n'
    printf 'session_id=%s\n' "$sid"
    printf 'written_at=1785790000\n'
    printf 'repo=%s\n' "$repo"
  } > "$repo/.bionic/tmp/preflight.state"
  chmod 600 "$repo/.bionic/tmp/preflight.state"
}

# ============================================================
echo "=== S1 — relevance hoist (A7): irrelevant tool passes, silent ==="
# ============================================================

expect_status "gate script exists and is invocable" "0" "$([ -f "$GATE" ] && echo 0 || echo 1)"

REPO=$(make_repo r1 yes)
# no attestation exists at all — if tool_name gating were bypassed, an
# "Agent" payload here would be REFUSED. A "Bash" payload must still pass.
run_gate "$(mk_bash_payload "$SID_A" "$REPO")"
expect_status "irrelevant tool exits 0 even with no attestation in an active wave" "0" "$GATE_ST"
expect_empty "irrelevant tool produces no stdout" "$GATE_OUT"
expect_empty "irrelevant tool produces no stderr" "$GATE_ERR"

# static pin: the relevance check must appear in the source BEFORE the
# active-wave machinery (resolve_docs_root / the plan-directory find) — this
# is the textual half of A7's hoist proof; the behavioral half is above.
TOOL_LINE=$(grep -n '\[ "\$TOOL_NAME" = "Agent" \]' "$GATE" | head -1 | cut -d: -f1)
WALK_LINE=$(grep -n 'resolve_docs_root()' "$GATE" | head -1 | cut -d: -f1)
if [ -n "$TOOL_LINE" ] && [ -n "$WALK_LINE" ] && [ "$TOOL_LINE" -lt "$WALK_LINE" ]; then
  ok "relevance check (line $TOOL_LINE) precedes the plan-directory walk (line $WALK_LINE)"
else
  no "relevance check precedes the plan-directory walk" "tool=$TOOL_LINE walk=$WALK_LINE"
fi

# ============================================================
echo "=== S2 — ambiguity: repo unresolvable -> OPEN, silent ==="
# ============================================================

run_gate "$(mk_agent_payload "$SID_A" "")"
expect_status "empty cwd exits 0" "0" "$GATE_ST"
expect_empty "empty cwd produces no stdout" "$GATE_OUT"
expect_empty "empty cwd produces no stderr" "$GATE_ERR"

NONGIT="$SANDBOX/not-a-repo"; mkdir -p "$NONGIT"
run_gate "$(mk_agent_payload "$SID_A" "$NONGIT")"
expect_status "non-git cwd exits 0" "0" "$GATE_ST"
expect_empty "non-git cwd produces no stdout" "$GATE_OUT"
expect_empty "non-git cwd produces no stderr" "$GATE_ERR"

# ============================================================
echo "=== S3 — no active wave -> inert, nothing to decide ==="
# ============================================================

REPO_NOWAVE=$(make_repo r3a no)
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE")"
expect_status "no plan directory at all exits 0" "0" "$GATE_ST"
expect_empty "no plan directory produces no stdout" "$GATE_OUT"
expect_empty "no plan directory produces no stderr" "$GATE_ERR"

REPO_NOWAVE2=$(make_repo r3b yes)
# overwrite with a plan that has no ## SDLC State at all
cat > "$REPO_NOWAVE2/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 13
---
# A plan with no SDLC State section
PLAN
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE2")"
expect_status "plan with no SDLC State section exits 0" "0" "$GATE_ST"
expect_empty "no SDLC State produces no stdout" "$GATE_OUT"
expect_empty "no SDLC State produces no stderr" "$GATE_ERR"

# even with NO attestation present, no-active-wave still passes an Agent
# dispatch — proving the wave check, not the attestation check, gates entry.
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE")"
expect_status "Agent dispatch with no wave and no attestation still exits 0" "0" "$GATE_ST"

# ============================================================
echo "=== S4 — active wave + payload missing session_id -> OPEN, silent (§7 table) ==="
# ============================================================

REPO=$(make_repo r4 yes)
run_gate "$(mk_agent_payload "" "$REPO")"
expect_status "missing session_id in an active wave exits 0" "0" "$GATE_ST"
expect_empty "missing session_id produces no stdout" "$GATE_OUT"
expect_empty "missing session_id produces no stderr" "$GATE_ERR"

# ============================================================
echo "=== S5 — active wave + no attestation on disk -> REFUSE, fix command named (AC-2) ==="
# ============================================================

REPO=$(make_repo r5 yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no attestation in an active wave exits 2" "2" "$GATE_ST"
expect_empty "refusal produces no stdout" "$GATE_OUT"
expect_contains "refusal names the install-path fix command" "bash ~/.claude/hooks/preflight-probe.sh" "$GATE_ERR"
expect_absent "refusal does not name a repo-relative fix command (checklist A1)" "hooks/preflight-probe.sh\"" "$GATE_ERR"
case "$GATE_ERR" in
  *"hooks/dispatch-preflight.sh"*) no "refusal never names itself as the fix" ;;
  *) ok "refusal never names itself as the fix" ;;
esac

# ============================================================
echo "=== S6 — active wave + only a FOREIGN session's attestation exists -> REFUSE (AC-2) ==="
# ============================================================
#
# slice 4/2 (D-5): the foreign attestation is written at ITS OWN per-session filename
# (preflight-<SID_B>.state) — there is no file at all for SID_A, which is exactly what
# "foreign, however fresh, is not an attestation for this session" means once filenames
# are the primary key.

REPO=$(make_repo r6 yes)
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "foreign-only attestation exits 2 (no file exists for this session)" "2" "$GATE_ST"
expect_contains "foreign-only refusal names the fix command" "bash ~/.claude/hooks/preflight-probe.sh" "$GATE_ERR"

# ============================================================
echo "=== S6b — active wave + BOTH sessions hold valid attestations concurrently (AC-2) ==="
# ============================================================
#
# The D-5 core case: two sessions on one repo, each with its own per-session file. Both
# dispatches pass — session B's attestation existing is neither necessary nor sufficient
# for session A's gate, and vice versa.

REPO=$(make_repo r6b yes)
write_attestation "$REPO" "$SID_A"
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "session A's dispatch passes with both attestations present" "0" "$GATE_ST"
expect_empty "session A's pass produces no stdout" "$GATE_OUT"
run_gate "$(mk_agent_payload "$SID_B" "$REPO")"
expect_status "session B's dispatch ALSO passes with both attestations present" "0" "$GATE_ST"
expect_empty "session B's pass produces no stdout" "$GATE_OUT"

# ============================================================
echo "=== S6c — the legacy single-slot file is NEVER consulted (slice 4/2) ==="
# ============================================================
#
# A legacy preflight.state carrying this session's own, perfectly valid-looking
# session_id= must still refuse: only the per-session filename is ever read.

REPO=$(make_repo r6c yes)
write_legacy_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a legacy single-slot attestation (even keyed to this session) still exits 2" "2" "$GATE_ST"
expect_contains "legacy-file refusal names the fix command" "bash ~/.claude/hooks/preflight-probe.sh" "$GATE_ERR"

# ============================================================
echo "=== S7 — active wave + attestation IS this session -> pass, verdict silent (AC-2) ==="
# ============================================================
#
# "Silent" here is about the VERDICT (no BLOCKED refusal, nothing on stdout ever) — not
# absolute stderr silence, which S10c's absence warning already established is not the
# invariant. Since slice 4/3 this fixture also has no sweeper armed, so its stderr is
# exactly the unarmed-sweeper nag (S11 drives that behavior directly); asserted here too so
# this section's own claim of what "silent" means stays accurate.

REPO=$(make_repo r7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "matching attestation exits 0" "0" "$GATE_ST"
expect_empty "matching attestation produces no stdout (never print on the allow path)" "$GATE_OUT"
expect_absent "matching attestation prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_contains "matching attestation's only stderr is the unarmed-sweeper nag (no ledger armed here)" \
  "no session sweeper is armed" "$GATE_ERR"

# forward-compatibility (A6): unknown extra fields, reordered, must still
# read the session_id BY KEY, not by position — mirrors
# preflight-probe.test.sh's own reorder case. Written at the PER-SESSION path.
REPO=$(make_repo r7b yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'unknown_future_field=x\nsession_id=%s\nversion=1\nrepo=%s\n' "$SID_A" "$REPO" \
  > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "reordered/extended attestation with a matching key still passes" "0" "$GATE_ST"
expect_empty "reordered/extended pass produces no stdout" "$GATE_OUT"

# ============================================================
echo "=== S8 — hostile/malformed attestation shapes -> REFUSE, never followed (AC-8-adjacent) ==="
# ============================================================

# attestation path occupied by a directory
REPO=$(make_repo r8a yes)
mkdir -p "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation path is a directory -> refuse" "2" "$GATE_ST"

# attestation path is a symlink to a file that DOES contain a matching
# session_id= line — proves the gate never follows it, even when doing so
# would happen to "pass": the wall must not be foolable by planted content.
REPO=$(make_repo r8b yes)
mkdir -p "$REPO/.bionic/tmp"
DECOY="$SANDBOX/decoy-attestation"
printf 'session_id=%s\nversion=1\n' "$SID_A" > "$DECOY"
ln -s "$DECOY" "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation path is a symlink -> refuse, not followed" "2" "$GATE_ST"

# S1 (Step-6 security review, slice 4/7): the DIRECTORY levels are guarded too.
# Checking only the file leaves the same class open one level up — a repo
# controls its own `.bionic/` contents, so pointing `.bionic/tmp` (or `.bionic`)
# at a directory holding a valid same-session attestation opens the wall with
# content the repo arranges. §8's load-bearing property is that a hostile repo
# can CLOSE or AIM these walls but never OPEN them, and the sibling gate already
# refuses at both levels (hooks/stop-guard.sh's state_paths(); checklist A3
# names this variant, discharged for the WRITE path only).
for _lvl in .bionic/tmp .bionic; do
  _tag=$(printf '%s' "$_lvl" | tr -d './')
  REPO=$(make_repo "r8d-$_tag" yes)
  ELSEWHERE="$SANDBOX/elsewhere-$_tag/.bionic/tmp"
  mkdir -p "$ELSEWHERE"
  printf 'session_id=%s\nversion=1\nkind=preflight-attestation\n' "$SID_A" \
    > "$ELSEWHERE/preflight-$SID_A.state"
  if [ "$_lvl" = ".bionic/tmp" ]; then
    mkdir -p "$REPO/.bionic"
    ln -s "$ELSEWHERE" "$REPO/.bionic/tmp"
  else
    # The whole `.bionic` redirected: the active plan has to travel with it, or
    # the case is vacuous (no wave, nothing to decide).
    cp -R "$REPO/.bionic/docs" "$SANDBOX/elsewhere-$_tag/.bionic/docs"
    rm -rf "$REPO/.bionic"
    ln -s "$SANDBOX/elsewhere-$_tag/.bionic" "$REPO/.bionic"
  fi
  run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
  expect_status "a planted DIRECTORY symlink at ${_lvl} -> refuse, not read through (S1)" \
    "2" "$GATE_ST"
done

# attestation file exists but is empty / has no session_id= line at all
REPO=$(make_repo r8c yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'version=1\nkind=preflight-attestation\n' > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation with no session_id= line -> refuse" "2" "$GATE_ST"

# ============================================================
echo "=== S9 — the fix command is runnable from a NON-REPO cwd (checklist A1) ==="
# ============================================================

REPO=$(make_repo r9 yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
FIXLINE=$(printf '%s\n' "$GATE_ERR" | grep '^Fix: ' | sed 's/^Fix: //')
expect_contains "a fix line was captured to execute" "preflight-probe.sh" "$FIXLINE"

RUNHOME="$SANDBOX/run9/home"
mkdir -p "$RUNHOME/.claude/hooks"
cp "$PROBE_SRC" "$RUNHOME/.claude/hooks/preflight-probe.sh"
chmod +x "$RUNHOME/.claude/hooks/preflight-probe.sh"

NONREPO_CWD="$SANDBOX/run9/nowhere"
mkdir -p "$NONREPO_CWD"

RUN9_OUT="$SANDBOX/run9.out"; RUN9_ERR="$SANDBOX/run9.err"
( cd "$NONREPO_CWD" && env -i \
    HOME="$RUNHOME" PATH="$PATH" \
    CLAUDE_CONFIG_DIR="$RUNHOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$SID_A" \
    ANTHROPIC_API_KEY="sk-fixture-marker" \
    bash -c "$FIXLINE" ) >"$RUN9_OUT" 2>"$RUN9_ERR"
RUN9_ST=$?

# 127 = command not found, 126 = found but not executable — exactly the
# failure shapes a repo-relative fix command produces from a foreign cwd.
if [ "$RUN9_ST" -eq 127 ] || [ "$RUN9_ST" -eq 126 ]; then
  no "fix command runs from a non-repo cwd" "exit $RUN9_ST (not found/not executable): $(cat "$RUN9_ERR")"
else
  ok "fix command runs from a non-repo cwd (exit $RUN9_ST, a preflight-probe.sh code)"
fi
expect_absent "fix-command run produces no 'No such file or directory'" "No such file or directory" "$RUN9_ERR"
expect_absent "fix-command run produces no 'command not found'" "command not found" "$RUN9_ERR"

# ============================================================
echo "=== S10 — the roster row is written on the pass path (AC-1, launch half) ==="
# ============================================================
#
# Governing design: spec §Design "Roster" + §Component boundaries. The row is
# appended at launch with status `intended`; the full agent id and `confirmed`
# are slice 4/4's, not this one's.

REPO=$(make_repo r10 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
R10=$(roster_path "$REPO" "$SID_A")

expect_status "a contract-complete dispatch still passes (verdict unchanged)" "0" "$GATE_ST"
expect_empty "a contract-complete dispatch still prints nothing on stdout" "$GATE_OUT"
# Not absolute stderr silence since slice 4/3: this fixture arms no sweeper, so the
# unarmed-sweeper nag (S11) is expected stderr, not a regression — the invariant this row
# actually protects is "no BLOCKED refusal", asserted directly.
expect_absent "a contract-complete dispatch prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_status "the roster file exists at the per-session path" "0" "$([ -f "$R10" ] && echo 0 || echo 1)"
expect_contains "the roster carries a versioned schema header" "roster-state/v1" "$(head -1 "$R10" 2>/dev/null)"
expect_status "exactly one row was appended" "1" "$(roster_rows "$R10")"

ROW=$(roster_row "$R10" 1)
expect_contains "the row's leading field is the schema version" "roster-state/v1" "$(printf '%s' "$ROW" | cut -d'|' -f1)"
expect_status "row status is 'intended'" "intended" "$(roster_field "$ROW" status)"
expect_status "row carries this session's id" "$SID_A" "$(roster_field "$ROW" session)"
expect_status "row carries the agent name from tool_input" "w99-impl" "$(roster_field "$ROW" name)"
expect_status "row carries subagent_type from tool_input" "implementor" "$(roster_field "$ROW" subagent_type)"
expect_status "row carries the model from tool_input" "claude-sonnet-5" "$(roster_field "$ROW" model)"
expect_status "row carries the tool_use_id (the recorder's correlation key)" \
  "toolu_018jyjgop7KMxP6yKtoAWWtB" "$(roster_field "$ROW" tool_use_id)"
expect_status "row's agent_id is empty at launch (slice 4/4 fills it)" "" "$(roster_field "$ROW" agent_id)"

LAUNCHED=$(roster_field "$ROW" launched_at)
if printf '%s' "$LAUNCHED" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "row carries a UTC ISO launch timestamp ($LAUNCHED)"
else
  no "row carries a UTC ISO launch timestamp" "got '$LAUNCHED'"
fi

# contract state, lifted from the brief's labeled fields
expect_status "row lifts the deliverable path from 'Expected artifact:'" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_contains "row lifts the expected duration" "25" "$(roster_field "$ROW" duration)"
expect_status "row lifts the progress path from 'Progress artifact:'" \
  ".bionic/tmp/w99-widget.progress" "$(roster_field "$ROW" progress)"
expect_status "no contract field is recorded absent for a complete brief" "" "$(roster_field "$ROW" absent)"

# ============================================================
echo "=== S10b — the compact one-line label grammar is lifted too (AC-1) ==="
# ============================================================
#
# Real briefs put two labels on one line ("Expected duration: ~35 minutes.
# Progress: append to <path> per stage") — see the exemplar at
# .bionic/docs/record/w2-ac3-run.md. A line-scoped extractor would swallow the
# second label into the first's value; the span must end at the NEXT LABEL, not
# at the newline.

BRIEF_COMPACT='Slice 4/4 of epic-99 wave-01; build · audited · wave.
Deliverables: (1) one commit `feat(x): thing (epic-99 w1 slice 4/4)`; (2) record/w99-two.txt, verbatim.
Expected duration: ~35 minutes. Progress: append to .bionic/tmp/w99-two.progress per stage.
Exit: both deliverables exist.'

REPO=$(make_repo r10b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_COMPACT" "w99-two")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "compact grammar: the dispatch passes" "0" "$GATE_ST"
expect_contains "compact grammar: deliverable lifted from 'Deliverables:'" \
  "record/w99-two.txt" "$(roster_field "$ROW" deliverable)"
expect_contains "compact grammar: duration lifted, not swallowed by the next label" \
  "35" "$(roster_field "$ROW" duration)"
expect_absent "compact grammar: the duration value stops at the next label" \
  "Progress" "$(roster_field "$ROW" duration)"
expect_status "compact grammar: progress path lifted from a mid-line 'Progress:'" \
  ".bionic/tmp/w99-two.progress" "$(roster_field "$ROW" progress)"
# "4/4" inside the commit subject is slash-bearing but not a path; a lifted
# deliverable list containing it would mean the extractor is matching fractions.
expect_absent "compact grammar: a bare fraction is not lifted as a deliverable path" \
  "4/4" "$(roster_field "$ROW" deliverable)"

# ============================================================
echo "=== S10c — a missing NON-deliverable field is RECORDED + WARNED, never blocked (AC-1) ==="
# ============================================================
#
# Spec §Component boundaries: "Extraction failure warns and records absence —
# starts fail open (TDD §7)." The verdict is the load-bearing assertion here: a
# brief missing everything BUT its deliverable is a warning, not a refusal.
#
# The deliverable is the one field that escaped this rule (S10W): a dispatch
# that names none is refused outright. So this fixture carries a deliverable and
# nothing else — which is also what keeps the two directions honest, since a
# brief carrying no fields at all now never reaches the roster to be warned about.

REPO=$(make_repo r10c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" \
  "Go and do the thing, please. Expected artifact: .bionic/docs/record/w99-min.txt" "-" "-")"
R10C=$(roster_path "$REPO" "$SID_A")
ROW=$(roster_row "$R10C" 1)

expect_status "a brief with only its deliverable still PASSES the gate" "0" "$GATE_ST"
expect_empty "the absence warning never goes to stdout" "$GATE_OUT"
expect_contains "the absence is warned on stderr" "WARN" "$GATE_ERR"
expect_contains "the warning names the duration field" "duration" "$GATE_ERR"
expect_contains "the warning names the progress field" "progress" "$GATE_ERR"
expect_absent "the warning is not phrased as a refusal" "BLOCKED" "$GATE_ERR"
expect_status "the row is still appended for a near-fieldless brief" "1" "$(roster_rows "$R10C")"
ABSENT=$(roster_field "$ROW" absent)
expect_contains "the row records the duration absence" "duration" "$ABSENT"
expect_contains "the row records the progress absence" "progress" "$ABSENT"
expect_contains "the row records the missing agent name" "name" "$ABSENT"
expect_absent "the deliverable it DID name is not recorded absent" "deliverable" "$ABSENT"
expect_status "the absent contract field is empty in the row, not fabricated" "" "$(roster_field "$ROW" duration)"
# An OMITTED model is not an absence finding — the Agent tool inherits the
# orchestrator's model when none is given, so a warning here would fire on the
# ordinary case and train the operator to read past the real ones.
expect_absent "an omitted model is NOT recorded as an absence" "model" "$ABSENT"

# ============================================================
echo "=== S10W — a brief naming NO deliverable is REFUSED; the in-brief waiver is the only way through ==="
# ============================================================
#
# USER-DIRECTED (epic-15 post-w4): "A wall. It should be a wall." The absence
# warning above was the whole enforcement for the one contract field the rest of
# the machinery cannot work without — the sweeper's delivered/not-delivered
# predicate has nothing to stat, and a dispatch that dies quietly leaves nothing
# behind. So this single field escalates from warn to REFUSAL, and every escape
# from the refusal is a line in the brief, which means it lands on the roster.
#
# Everything else stays exactly where it was: progress absence warns, duration
# absence warns, the unarmed-sweeper nag warns. This is one wall, not a policy.

BRIEF_NO_DELIVERABLE='Your slice: go and do the thing, please.
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-nodeliv.progress'

REPO=$(make_repo r10w yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_DELIVERABLE" "w99-nodeliv")"

expect_status "a dispatch whose brief names no deliverable is REFUSED" "2" "$GATE_ST"
expect_empty "the refusal never goes to stdout" "$GATE_OUT"
expect_contains "the refusal is phrased as a block" "BLOCKED" "$GATE_ERR"
expect_contains "the refusal names the field that is missing" "names no deliverable" "$GATE_ERR"
expect_contains "the refusal shows a label that lifts one" "Expected artifact:" "$GATE_ERR"
expect_contains "the refusal names the waiver escape verbatim" "Deliverable-waiver:" "$GATE_ERR"
# The wrong fix would be the environment attestation's — this refusal is a
# different one and must not send the operator to re-run the probe.
expect_absent "the refusal does not name the attestation fix command" "preflight-probe.sh" "$GATE_ERR"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- deliverable PRESENT: wholly unaffected ----
REPO=$(make_repo r10w2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-hasdeliv")"
expect_status "a brief that names a deliverable is not touched by the wall" "0" "$GATE_ST"
expect_absent "…and prints no refusal" "BLOCKED" "$GATE_ERR"
expect_status "…and is journalled as before" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- progress absence stays WARN-ONLY: only the deliverable escalated ----
BRIEF_NO_PROGRESS='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-noprog.txt
Expected duration: ~25 minutes.'

REPO=$(make_repo r10w3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_PROGRESS" "w99-noprog")"
expect_status "an absent PROGRESS path still passes — only the deliverable escalated" "0" "$GATE_ST"
expect_contains "…and is still warned" "progress" "$GATE_ERR"
expect_absent "…and is never phrased as a refusal" "BLOCKED" "$GATE_ERR"

# ---- the waiver: refusal becomes a warning that echoes the reason ----
BRIEF_WAIVED='Your slice: answer one question from the tree; nothing durable is produced.
Deliverable-waiver: read-only reconnaissance, the answer is the report itself
Expected duration: ~10 minutes.
Progress artifact: .bionic/tmp/w99-waived.progress'

REPO=$(make_repo r10w4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_WAIVED" "w99-waived")"
R10W4=$(roster_path "$REPO" "$SID_A")
ROW=$(roster_row "$R10W4" 1)

expect_status "an in-brief waiver converts the refusal into a pass" "0" "$GATE_ST"
expect_absent "a waived dispatch prints no refusal" "BLOCKED" "$GATE_ERR"
expect_contains "the waiver is echoed on stderr, so it is never silent" \
  "read-only reconnaissance, the answer is the report itself" "$GATE_ERR"
expect_contains "the echo is a warning, not a verdict" "WARN" "$GATE_ERR"
expect_status "the waived dispatch is journalled" "1" "$(roster_rows "$R10W4")"
expect_status "the row LEDGERS the waiver reason — every waiver is on the record" \
  "read-only reconnaissance, the answer is the report itself" "$(roster_field "$ROW" waiver)"
# The waiver excuses the refusal; it does not make the fact untrue.
expect_contains "the row still records the deliverable as absent" \
  "deliverable" "$(roster_field "$ROW" absent)"
expect_status "…and fabricates no deliverable path" "" "$(roster_field "$ROW" deliverable)"
# The waiver value must stop where the next labelled field starts.
expect_absent "the waiver reason does not swallow the field after it" \
  "10 minutes" "$(roster_field "$ROW" waiver)"

# ---- a waiver with no reason is not a waiver ----
BRIEF_EMPTY_WAIVER='Your slice: do the thing.
Deliverable-waiver:
Expected duration: ~10 minutes.'

REPO=$(make_repo r10w5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_EMPTY_WAIVER" "w99-emptywaiver")"
expect_status "a reasonless waiver does not open the wall" "2" "$GATE_ST"
expect_contains "…and the refusal still names the escape" "Deliverable-waiver:" "$GATE_ERR"

# ---- the ordinary brief records no waiver ----
REPO=$(make_repo r10w6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-nowaiver")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief that waives nothing carries an empty waiver field" \
  "" "$(roster_field "$ROW" waiver)"
expect_absent "…and no waiver is echoed for it" "waived" "$GATE_ERR"

# ============================================================
echo "=== S10L — the LIVENESS fields are lifted: cadence + the subprocess claim (6-axis A-1) ==="
# ============================================================
#
# The ratified liveness contract shipped into skills/canonical-sdlc/SKILL.md
# §Dispatch in slice 4/7 — "The progress-artifact path carries a `cadence`
# alongside it" and "A subprocess claim — a process pattern plus its output file
# — is conditional-required". The Step-6 six-axis review found the procedure
# layer instructing authors to declare two fields this writer had no extraction
# site for, with hooks/stop-check.sh:389 already READING `claims=` off the row
# (axis-3 FAIL: a shipped reader with no producer). These cases are the writer
# half of that closure; hooks/stop-check.test.sh §8(g) drives the reader half
# over a row THIS gate really wrote.
#
# GRAMMAR, stated because it is the one place this extractor reads a value that
# is not a path and not free text: `cadence` may be introduced by a colon OR by
# whitespace alone, because the ratified sentence puts it "alongside" the
# progress path inside one sentence rather than on a labeled line of its own.
# The subprocess claim's PATTERN is the backticked/quoted run when the author
# marks one, else the text up to the first comma or arrow; the output file half
# is the path the same span carries.

BRIEF_LIVENESS='Canonical-sdlc Step 4, slice 4/10 of epic-99 wave-01; build · audited · wave.
Your slice: the widget, behind the existing seam.
Expected artifact: .bionic/docs/record/w99-live.txt
Expected duration: ~50 minutes. Progress: .bionic/tmp/w99-live.progress, cadence ~6m.
Subprocess claim: `bash tests/run.sh` → .bionic/tmp/w99-suite.log
Exit condition: the artifact exists and the suite is green.'

REPO=$(make_repo r10L yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LIVENESS" "w99-live")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)

expect_status "liveness brief: the dispatch passes" "0" "$GATE_ST"
expect_status "the row lifts the cadence declared beside the progress path" \
  "~6m." "$(roster_field "$ROW" cadence)"
expect_status "the row lifts the subprocess claim's PATTERN, backticks stripped" \
  "bash tests/run.sh" "$(roster_field "$ROW" claims)"
expect_status "the progress path still stops at the cadence that follows it" \
  ".bionic/tmp/w99-live.progress" "$(roster_field "$ROW" progress)"
expect_absent "the cadence value stops at the next label" \
  "Subprocess" "$(roster_field "$ROW" cadence)"
expect_absent "the claimed pattern does not swallow the output file beside it" \
  "w99-suite.log" "$(roster_field "$ROW" claims)"
expect_status "the duration is unharmed by the new labels" \
  "~50 minutes." "$(roster_field "$ROW" duration)"

# The colon form and the unquoted comma form — the two other shapes the ratified
# sentence permits an author to write.
#
# The claim line reads `Subprocess claim:` rather than the bare `Claims:` this
# fixture used until the Step-6 critic (F-2). That bare label was withdrawn from
# the grammar because it also matched "verify every claim the report claims:" in
# an ordinary review brief and invented a subprocess from it. The two properties
# this case exists for are untouched by the respelling — a cadence introduced by
# a colon on its own line, and an unquoted pattern that stops at the comma before
# its output file — and the vocabulary it now uses is the contract's own.
BRIEF_LIVENESS2='Slice 4/11 of epic-99 wave-01.
Deliverables: record/w99-b.txt
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99-b.progress
Cadence: every 5 minutes
Subprocess claim: pgrep-me-w99, output .bionic/tmp/w99-b.log
Exit: the deliverable exists.'

REPO=$(make_repo r10L2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LIVENESS2" "w99-live2")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the colon form of cadence lifts too" \
  "every 5 minutes" "$(roster_field "$ROW" cadence)"
expect_status "an unquoted claim pattern stops at the comma before its output file" \
  "pgrep-me-w99" "$(roster_field "$ROW" claims)"

# CONDITIONAL-REQUIRED, both directions: a brief that declares neither field
# leaves both EMPTY rather than fabricating one, and — because the subprocess
# claim is declared only when the task backgrounds a long command — its absence
# is never an absence FINDING. The whole point of the contract is that shape
# emerges from which fields are present.
REPO=$(make_repo r10L3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-noclaim")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief with no subprocess claim leaves claims= empty, not fabricated" \
  "" "$(roster_field "$ROW" claims)"
expect_status "a brief with no cadence leaves cadence= empty" "" "$(roster_field "$ROW" cadence)"
expect_absent "an undeclared subprocess claim is NOT an absence finding" \
  "claims" "$(roster_field "$ROW" absent)"

# THE NEGATIVE DIRECTION, which is the one that was missing (Step-6 critic F-2).
# Every case above declares a liveness contract and checks it is read correctly.
# None checked the far more common brief that declares NONE and merely uses one
# of the words in prose — and both labels fabricated a declaration from it.
#
# Fabrication is not neutral noise here. Under the ratified contract
# (skills/canonical-sdlc/SKILL.md) field PRESENCE is the shape key — "shape
# emerges from which are present… adding a subprocess claim is a delegated
# command" — and a claims= value opens a `-- claimed process (P2) --` section
# whose pgrep finds nothing and prints `live: no`, the ALARM direction. So a
# brief that says "keep a steady cadence" was classified long-shape and armed a
# quiescence watcher, and one that says "verify every claim" grew a phantom
# subprocess. Both briefs below are verbatim from the critic's repro
# (.bionic/docs/record/w3-critic-repro-lift.sh, briefs C and D).
BRIEF_PROSE_CADENCE='Your slice: write the report.
Deliverables: .bionic/docs/record/w99.md
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99.progress, a line per section.
Scope constraint: keep a steady cadence and do not batch the sections.
Exit: report written.'

REPO=$(make_repo r10L4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CADENCE" "w99-prose1")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the word 'cadence' in ordinary prose declares no cadence" \
  "" "$(roster_field "$ROW" cadence)"
# …and the fix is not a blunt one: the fields this brief DOES declare still lift.
expect_status "…while the progress path the same brief declares still lifts" \
  ".bionic/tmp/w99.progress" "$(roster_field "$ROW" progress)"
expect_status "…and its duration" "~40 minutes." "$(roster_field "$ROW" duration)"

BRIEF_PROSE_CLAIMS='Your slice: audit the report.
Deliverables: .bionic/docs/record/audit.md
Expected duration: ~20 minutes.
Progress: .bionic/tmp/audit.progress, a line per claim checked.
Scope constraint: verify every claim the report claims: proof or the label unverified.
Exit: audit written.'

REPO=$(make_repo r10L5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CLAIMS" "w99-prose2")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief that REVIEWS claims declares no subprocess claim" \
  "" "$(roster_field "$ROW" claims)"
expect_status "…and grows no cadence either" "" "$(roster_field "$ROW" cadence)"
expect_status "…while its own progress path is still read" \
  ".bionic/tmp/audit.progress" "$(roster_field "$ROW" progress)"

# The cadence rule stated as the rule it is: the word only declares a cadence
# where the contract puts it — beside the progress path — so the SAME word in the
# SAME brief lifts or does not lift depending on where it falls.
BRIEF_CADENCE_PLACE='Your slice: build it.
Deliverables: .bionic/docs/record/w99.md
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99.progress, cadence ~9m.
Scope constraint: keep a steady cadence throughout.
Exit: built.'

REPO=$(make_repo r10L6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CADENCE_PLACE" "w99-place")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the cadence beside the progress path is the one that counts" \
  "~9m." "$(roster_field "$ROW" cadence)"

# ============================================================
echo "=== S10d — rows APPEND; the roster is a ledger, not a slot ==="
# ============================================================

REPO=$(make_repo r10d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "first-agent")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "second-agent")"
R10D=$(roster_path "$REPO" "$SID_A")
expect_status "two dispatches leave two rows" "2" "$(roster_rows "$R10D")"
expect_status "the first row survives the second dispatch" "first-agent" "$(roster_field "$(roster_row "$R10D" 1)" name)"
expect_status "the second row is the second dispatch" "second-agent" "$(roster_field "$(roster_row "$R10D" 2)" name)"
expect_status "the schema header is written once, not per row" "1" \
  "$(grep -c '^# bionic session roster' "$R10D")"

# ============================================================
echo "=== S10e — the roster is per-session from birth (D-5) ==="
# ============================================================

REPO=$(make_repo r10e yes)
write_attestation "$REPO" "$SID_A"
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "agent-of-A")"
run_gate "$(mk_agent_payload "$SID_B" "$REPO" "$BRIEF_FULL" "agent-of-B")"
RA=$(roster_path "$REPO" "$SID_A"); RB=$(roster_path "$REPO" "$SID_B")
expect_status "session A has its own roster file" "0" "$([ -f "$RA" ] && echo 0 || echo 1)"
expect_status "session B has its own roster file" "0" "$([ -f "$RB" ] && echo 0 || echo 1)"
expect_status "session A's roster holds only A's launch" "1" "$(roster_rows "$RA")"
expect_status "session B's roster holds only B's launch" "1" "$(roster_rows "$RB")"
expect_status "A's row is A's agent" "agent-of-A" "$(roster_field "$(roster_row "$RA" 1)" name)"
expect_status "B's row is B's agent" "agent-of-B" "$(roster_field "$(roster_row "$RB" 1)" name)"
expect_status "no shared single-slot roster.state was created" "1" \
  "$([ -f "$REPO/.bionic/tmp/roster.state" ] && echo 0 || echo 1)"

# ============================================================
echo "=== S10f — dead-session rosters are pruned, LIVE foreign ones are not (D-5) ==="
# ============================================================
#
# Same liveness rule slice 4/2 established for the attestation
# (hooks/preflight-probe.sh: a session is live iff its transcript still exists
# somewhere under CLAUDE_CONFIG_DIR/projects). A live foreign session's roster
# surviving another session's dispatch IS the concurrency D-5 exists for.

SID_DEAD="deadfeed-0000-4000-8000-000000000001"
SID_LIVE="1ivefeed-0000-4000-8000-000000000002"
CFG="$SANDBOX/cfg10f/.claude"
mkdir -p "$CFG/projects/-some-project"
: > "$CFG/projects/-some-project/$SID_LIVE.jsonl"
: > "$CFG/projects/-some-project/$SID_A.jsonl"
# SID_DEAD deliberately has NO transcript anywhere.

REPO=$(make_repo r10f yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic/tmp"
printf '# bionic session roster — schema roster-state/v1\nroster-state/v1|status=intended|session=%s|name=ghost\n' \
  "$SID_DEAD" > "$(roster_path "$REPO" "$SID_DEAD")"
printf '# bionic session roster — schema roster-state/v1\nroster-state/v1|status=intended|session=%s|name=neighbour\n' \
  "$SID_LIVE" > "$(roster_path "$REPO" "$SID_LIVE")"

GATE_CONFIG_DIR="$CFG"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
GATE_CONFIG_DIR=""

expect_status "the dispatch still passes while pruning" "0" "$GATE_ST"
expect_status "a DEAD session's roster is pruned" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_DEAD")" ] && echo 0 || echo 1)"
expect_status "a LIVE foreign session's roster is left untouched" "0" \
  "$([ -f "$(roster_path "$REPO" "$SID_LIVE")" ] && echo 0 || echo 1)"
expect_contains "the live foreign roster's content is unmodified" "neighbour" \
  "$(cat "$(roster_path "$REPO" "$SID_LIVE")" 2>/dev/null)"
expect_status "our own roster was written" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# The prune must not reach across artifacts: the attestation files share the
# same directory and the same per-session scheme.
expect_status "the prune leaves attestations alone" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"

# ============================================================
echo "=== S10g — a roster WRITE FAILURE warns and leaves the verdict alone ==="
# ============================================================
#
# TDD §7: starts fail open. The roster is a ledger, not a wall — a gate that
# refused a dispatch because it could not journal it would be a new failure
# mode, not a safety property.

REPO=$(make_repo r10g yes)
write_attestation "$REPO" "$SID_A"
chmod 555 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 755 "$REPO/.bionic/tmp"
expect_status "an unwritable state dir does not change the PASS verdict" "0" "$GATE_ST"
expect_empty "a write failure prints nothing on stdout" "$GATE_OUT"
expect_contains "a write failure is warned on stderr" "WARN" "$GATE_ERR"
expect_status "no roster file was left behind" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ============================================================
echo "=== S10h — a symlinked roster path is never written through (§8) ==="
# ============================================================
#
# A hostile repo controls its own .bionic/ contents. It may make this gate fail
# to journal; it must not gain an arbitrary-file append. (The DIRECTORY-level
# variants are already refused upstream by the attestation check — S8 drives
# them — so the file level is the only one reachable here.)

REPO=$(make_repo r10h yes)
write_attestation "$REPO" "$SID_A"
DECOY_ROSTER="$SANDBOX/decoy-roster.txt"
printf 'untouched\n' > "$DECOY_ROSTER"
ln -s "$DECOY_ROSTER" "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a symlinked roster path does not change the PASS verdict" "0" "$GATE_ST"
expect_contains "a symlinked roster path is warned" "WARN" "$GATE_ERR"
expect_status "the symlink target is not appended to" "untouched" "$(cat "$DECOY_ROSTER")"

# ============================================================
echo "=== S10i — no row on any path that is not a launch ==="
# ============================================================

# refused dispatch (active wave, no attestation): the launch never happens.
REPO=$(make_repo r10i yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a REFUSED dispatch still exits 2" "2" "$GATE_ST"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# no active wave: this gate has nothing to decide and nothing to ledger.
REPO=$(make_repo r10i2 no)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a dispatch outside an active wave exits 0" "0" "$GATE_ST"
expect_empty "a dispatch outside an active wave stays silent" "$GATE_ERR"
expect_status "a dispatch outside an active wave writes no roster" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# a non-Agent tool is not a launch.
REPO=$(make_repo r10i3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_bash_payload "$SID_A" "$REPO")"
expect_status "a Bash call in an attested active wave writes no roster" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ============================================================
echo "=== S11 — unarmed-sweeper nag: warn-only, never blocks (slice 4/3, AC-6) ==="
# ============================================================
#
# spec §Component boundaries: "hooks/dispatch-preflight.sh (modified): warn-only unarmed
# check at dispatch, sourced from the sweeper ledger's live-PID state." Ownership table row
# "live-arming state": the sweeper ledger file is the single SSoT; the agreement test proves
# this nag and the sweeper's OWN arm-refusal read that same ledger fixture and agree — which
# is why the nag invokes the sibling `session-sweeper.sh status` (dirname-relative) rather
# than a second hand-rolled ledger parser.

ledger_path() { printf '%s/.bionic/tmp/sweeper-%s.state' "$1" "$2"; }

# write_ledger_arm <repo> <sid> <pid> [tick] — a single open (never closed) arm entry, the
# same shape session-sweeper.test.sh's own "stale open entry" fixture uses.
write_ledger_arm() {
  local repo="$1" sid="$2" pid="$3" tick="${4:-120}"
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n'
    printf 'sweeper-ledger/v1|event=arm|at=2026-08-06T00:00:00Z|epoch=1780000000|pid=%s|tick=%s|session=%s|rows=0|degraded=\n' \
      "$pid" "$tick" "$sid"
  } > "$(ledger_path "$repo" "$sid")"
  chmod 600 "$(ledger_path "$repo" "$sid")"
}

# ---- no ledger at all: never armed this session -> WARN, never blocks ----
REPO=$(make_repo r11a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no-ledger dispatch still passes (never blocks)" "0" "$GATE_ST"
expect_contains "no-ledger dispatch WARNs about the unarmed sweeper" "WARN" "$GATE_ERR"
expect_contains "the nag names the exact arm command" \
  "bash ~/.claude/hooks/session-sweeper.sh arm" "$GATE_ERR"

# ---- a DEAD-pid arming on the ledger: not live -> WARN, agreement with arm's own refusal ----
REPO=$(make_repo r11b yes)
write_attestation "$REPO" "$SID_A"
write_ledger_arm "$REPO" "$SID_A" "999999"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "dead-pid ledger dispatch still passes" "0" "$GATE_ST"
expect_contains "dead-pid ledger dispatch WARNs (agrees: not live)" "WARN" "$GATE_ERR"
expect_contains "the nag names the exact arm command (dead-pid case)" \
  "bash ~/.claude/hooks/session-sweeper.sh arm" "$GATE_ERR"

# AGREEMENT: the sweeper's OWN arm refusal, reading the identical ledger fixture, agrees —
# a dead pid is NOT refused; a second arm entry is appended.
( cd "$REPO" && exec env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER_SRC" arm --tick 30 ) \
  >"$SANDBOX/s11b-arm.out" 2>&1 &
P11B=$!
BG_PIDS="$BG_PIDS $P11B"
L11B="$(ledger_path "$REPO" "$SID_A")"
_i=0
while [ "$(grep -c 'event=arm' "$L11B" 2>/dev/null || echo 0)" -lt 2 ] && [ "$_i" -lt 50 ]; do
  sleep 0.1; _i=$((_i + 1))
done
expect_status "agreement: arm over the dead-pid fixture SUCCEEDS (second arm entry appended)" \
  "0" "$([ "$(grep -c 'event=arm' "$L11B" 2>/dev/null)" -ge 2 ] && echo 0 || echo 1)"
( cd "$REPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER_SRC" retire ) >/dev/null 2>&1
kill -9 "$P11B" 2>/dev/null

# ---- a LIVE-pid arming on the ledger: live -> SILENT, agreement with arm's own refusal ----
REPO=$(make_repo r11c yes)
write_attestation "$REPO" "$SID_A"
sleep 300 & LIVE_PID=$!
BG_PIDS="$BG_PIDS $LIVE_PID"
write_ledger_arm "$REPO" "$SID_A" "$LIVE_PID"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "live-pid ledger dispatch still passes" "0" "$GATE_ST"
expect_empty "live-pid ledger dispatch stays completely silent (agrees: live)" "$GATE_ERR"

# AGREEMENT: the sweeper's OWN arm refusal, reading the identical ledger fixture, agrees —
# a live pid IS refused.
RC_ARM=$( ( cd "$REPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER_SRC" arm --tick 30 \
              >"$SANDBOX/s11c-arm.out" 2>&1 ); echo $? )
expect_status "agreement: arm over the live-pid fixture is REFUSED (exit 1)" "1" "$RC_ARM"
kill -9 "$LIVE_PID" 2>/dev/null

# ---- an UNREADABLE-pid arming: nothing is provably armed -> WARN (never silence) ----
#
# The Step-6 critic's F-1 state, from the nag's side. The sweeper answers `live=unknown`
# here and exits 1, and that exit is what this nag reads — so the nag WARNs. That is the
# safe direction and the deliberate one: nothing is provably watching this session, and a
# nag that went quiet over a damaged ledger would hide exactly the state that needs saying.
# The two readers still read one ledger through one parser; what differs is the ACTION each
# takes on the third answer — the nag warns, arm refuses — which is the asymmetry
# hooks/session-sweeper.sh's warn_bad_pid note records.
REPO=$(make_repo r11e yes)
write_attestation "$REPO" "$SID_A"
write_ledger_arm "$REPO" "$SID_A" "-1"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "unreadable-pid ledger dispatch still passes (never blocks)" "0" "$GATE_ST"
expect_contains "unreadable-pid ledger dispatch WARNs, never stays silent" "WARN" "$GATE_ERR"
expect_contains "the nag names the exact arm command (unreadable-pid case)" \
  "bash ~/.claude/hooks/session-sweeper.sh arm" "$GATE_ERR"

# AGREEMENT-WITH-ASYMMETRY: over the identical fixture the sweeper's own arm REFUSES —
# fail-closed where the nag is fail-toward-warning. Both are about the same unreadable
# entry; neither pretends to know whether a sweeper is live.
RC_ARM=$( ( cd "$REPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER_SRC" arm --tick 30 \
              >"$SANDBOX/s11e-arm.out" 2>&1 ); echo $? )
expect_status "agreement: arm over the unreadable-pid fixture is REFUSED (exit 1)" "1" "$RC_ARM"
expect_contains "…naming the unreadable value" "unreadable" "$(cat "$SANDBOX/s11e-arm.out")"

# ---- the nag never fires on a REFUSED dispatch (no attestation): nothing is about to launch ----
REPO=$(make_repo r11d yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a refused dispatch (no attestation) still exits 2" "2" "$GATE_ST"
expect_absent "a refused dispatch prints no sweeper nag" "session-sweeper.sh" "$GATE_ERR"

# ============================================================
echo "=== S12 — dispatch-wall record/ inference (slice 4/4, AC-8) ==="
# ============================================================
#
# Interfaces produced (plan slice 4): an unlabeled path-shaped token whose
# normalized form starts with `record/`, `.bionic/docs/record/`, or
# `<docs-root>/record/` satisfies the deliverable wall; roster row records it
# under `deliverable=` plus a new field `source=inferred` (labeled lifts
# record `source=declared`). `.bionic/tmp/` and `/tmp/` prefixed tokens NEVER
# satisfy the wall from inference. Labeled behavior for other paths —
# including a labeled tmp path — stays byte-identical to today.

# ---- RED 1: bare .bionic/docs/record/ mention, no label -> passes, source=inferred ----
BRIEF_BARE_RECORD='Your slice: read the tree and note what you find.
It belongs in .bionic/docs/record/w99-bare.md when finished.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_RECORD" "w99-bare")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "an unlabeled .bionic/docs/record/ mention passes the wall" "0" "$GATE_ST"
expect_absent "…and prints no refusal" "BLOCKED" "$GATE_ERR"
expect_status "the roster records the inferred path as the deliverable" \
  ".bionic/docs/record/w99-bare.md" "$(roster_field "$ROW" deliverable)"
expect_status "the roster marks the source as inferred" "inferred" "$(roster_field "$ROW" source)"
expect_absent "an inferred deliverable is not recorded absent" "deliverable" "$(roster_field "$ROW" absent)"

# ---- a bare record/ prefix (no .bionic/docs/ prefix) infers too ----
BRIEF_BARE_RECORD2='Your slice: capture findings as you go.
Write to record/w99-bare2.md at the end.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12a2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_RECORD2" "w99-bare2")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a bare record/ prefix (no .bionic/docs/) also passes the wall" "0" "$GATE_ST"
expect_status "…and is recorded as the inferred deliverable" \
  "record/w99-bare2.md" "$(roster_field "$ROW" deliverable)"
expect_status "…marked inferred" "inferred" "$(roster_field "$ROW" source)"

# ---- RED 2: only a non-record path (Read first:) -> still refused (pinned negative) ----
BRIEF_ONLY_READFIRST='Read first: skills/canonical-sdlc/SKILL.md
Expected duration: ~10 minutes.'

REPO=$(make_repo r12b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_READFIRST" "w99-readfirst")"
expect_status "a brief whose only path is a non-record 'Read first:' mention is still refused" \
  "2" "$GATE_ST"
expect_contains "…with the deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- RED 3: only a .bionic/tmp/ path, unlabeled -> refused (tmp never inferred) ----
BRIEF_ONLY_TMP='Your slice: write scratch notes to .bionic/tmp/w99-scratch.md as you go.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_TMP" "w99-tmp")"
expect_status "a brief whose only unlabeled path is under .bionic/tmp/ is refused" "2" "$GATE_ST"
expect_contains "…with the deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- an unlabeled /tmp/ (not .bionic/tmp/) path is refused too ----
BRIEF_ONLY_SYSTMP='Your slice: write scratch notes to /tmp/w99-scratch.md as you go.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12c2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_SYSTMP" "w99-systmp")"
expect_status "a brief whose only unlabeled path is under /tmp/ is refused" "2" "$GATE_ST"

# ---- RED 4: a labeled brief records source=declared; behavior otherwise unchanged ----
REPO=$(make_repo r12d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-declared")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a labeled deliverable passes the wall (unchanged)" "0" "$GATE_ST"
expect_status "the row's deliverable is exactly the labeled path" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "the row marks the source as declared" "declared" "$(roster_field "$ROW" source)"
expect_status "duration is unaffected by the new inference field" \
  "~25 minutes." "$(roster_field "$ROW" duration)"
expect_status "progress is unaffected by the new inference field" \
  ".bionic/tmp/w99-widget.progress" "$(roster_field "$ROW" progress)"

# ---- a LABELED .bionic/tmp/ deliverable keeps today's behavior (label is explicit design) ----
BRIEF_LABELED_TMP='Your slice: report interim status to a scratch file.
Expected artifact: .bionic/tmp/w99-labeledtmp.txt
Expected duration: ~10 minutes.'

REPO=$(make_repo r12e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LABELED_TMP" "w99-labeledtmp")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a LABELED .bionic/tmp/ deliverable still passes the wall (unchanged)" "0" "$GATE_ST"
expect_status "…and is recorded exactly as labeled" \
  ".bionic/tmp/w99-labeledtmp.txt" "$(roster_field "$ROW" deliverable)"
expect_status "…marked declared, not inferred (the label is explicit designation)" \
  "declared" "$(roster_field "$ROW" source)"

# ---- the refusal text names the inference rule (interfaces: "gains one line") ----
REPO=$(make_repo r12f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_READFIRST" "w99-refusaltext")"
expect_contains "the refusal names the record/ inference rule" "inferred automatically" "$GATE_ERR"
expect_contains "the refusal names the tmp exclusion" ".bionic/tmp/ or /tmp/ paths never are" "$GATE_ERR"

echo ""
echo "----------------------------------------"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
