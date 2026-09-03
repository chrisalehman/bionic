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
# Usage: bash tests/dispatch-preflight.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

GATE="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"
PROBE_SRC="${BIONIC_HOOKS_DIR}/preflight-probe.sh"

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
expect_contains() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_absent()   { if grep -qF -- "$2" <<<"$3"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
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
#     tests/dispatch-spans.test.sh §5d — that suite was deleted in an earlier
#     purge, commit b959b5e, and nothing replaced the span pin) and the
#     exemplar brief recorded verbatim at .bionic/docs/record/w2-ac3-run.md:25-40.
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
# Extra `KEY=VALUE` assignments for the gate's own environment, applied unquoted so a
# space-free list can carry several (none of the values below contain spaces). Added for
# the combined preflight (S16): the gate now runs the real preflight-probe.sh inline, and
# the probe reads a credential and a config dir out of the environment — which must be the
# SANDBOX's, never the operator's.
GATE_ENV=""
run_gate() {  # <payload-json>
  if [ -n "$GATE_CONFIG_DIR" ]; then
    # shellcheck disable=SC2086
    GATE_OUT=$(printf '%s' "$1" | env $GATE_ENV CLAUDE_CONFIG_DIR="$GATE_CONFIG_DIR" bash "$GATE" 2>"$SANDBOX/.err")
  else
    # shellcheck disable=SC2086
    GATE_OUT=$(printf '%s' "$1" | env $GATE_ENV bash "$GATE" 2>"$SANDBOX/.err")
  fi
  GATE_ST=$?
  GATE_ERR=$(cat "$SANDBOX/.err")
  return 0
}

# ---------- the combined preflight's environment (epic-16 w2 S5) ----------
#
# As of R5 the gate RUNS hooks/preflight-probe.sh inline whenever this session has no
# attestation on disk, so most cases in this file now reach the real producer. Its
# blocking probes read a credential and its D-5 pruning reads a config directory, and
# both of those are machine-global by default: the operator's login keychain answers the
# credential probe no matter what a sandbox does, and the operator's own `~/.claude`
# decides which fixture rosters look "live". Substituting the ENVIRONMENT (not the
# script) is the same technique preflight-probe.test.sh uses, and it is on for the whole
# file so that no case accidentally depends on the machine it runs on.
#
# The transcript file makes THIS session look live to the probe's own scan; SESSION B
# gets one too, since several cases below turn on a live foreign session being left
# alone rather than pruned.
PROBE_ENV_HOME="$SANDBOX/probehome"
PROBE_ENV_PROJ="$PROBE_ENV_HOME/.claude/projects/-sandbox"
mkdir -p "$PROBE_ENV_PROJ"
: > "$PROBE_ENV_PROJ/$SID_A.jsonl"
: > "$PROBE_ENV_PROJ/$SID_B.jsonl"
probe_env_on() {
  GATE_CONFIG_DIR="$PROBE_ENV_HOME/.claude"
  GATE_ENV="ANTHROPIC_API_KEY=sk-fixture-marker HOME=$PROBE_ENV_HOME"
}
probe_env_on

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
    # A live wave has a live Patrol: it is armed at engagement, before the first dispatch
    # (skills/canonical-sdlc/SKILL.md §Dispatch). Every wave-active fixture therefore
    # carries a fresh stamp for the session ids this suite dispatches with, and the S21
    # arms remove or backdate it to drive the arming wall. Without this the wall would be
    # under test in every case in the file rather than in its own section.
    mkdir -p "$repo/.bionic/tmp"
    local _psid
    for _psid in "${SID_A:-}" "${SID_B:-}" "${SID_DEAD:-}" "${SID_LIVE:-}"; do
      [ -n "$_psid" ] || continue
      printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_psid" > "$repo/.bionic/tmp/patrol-$_psid.state"
      chmod 600 "$repo/.bionic/tmp/patrol-$_psid.state"
    done
    mkdir -p "$repo/.bionic/docs/plans/epic-99-test"
    cat > "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
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
canonical_sdlc_version: 14
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
echo "=== S5 — active wave + no attestation on disk -> AUTO-PROBE, then pass (AC-2 / AC-4) ==="
# ============================================================
#
# THE DIRECTION REVERSED IN EPIC-16 WAVE-02 (R5). Through wave-01 this refused and named
# a command for the operator to run by hand — and the Synthesis field report measured
# what that cost: five serialized minutes between deciding to dispatch and the agent
# existing, paid again after every /clear, which re-fires the this-session demand
# mid-wave although nothing about the machine has changed.
#
# A missing attestation is not evidence of a broken environment; it is the absence of
# evidence, and re-reading the fact costs a second and cannot go stale. So the gate takes
# the reading itself. The refusal did not disappear — it MOVED, onto the probe's own
# verdict (S16 drives that half, and the arc end to end).

REPO=$(make_repo r5 yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no attestation in an active wave no longer refuses" "0" "$GATE_ST"
expect_empty "the auto-probe path produces no stdout" "$GATE_OUT"
expect_absent "…and no refusal is printed" "BLOCKED" "$GATE_ERR"
expect_status "…the attestation it was missing now exists" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"

# The fix command survives where it still means something — the probe-failure refusal —
# and checklist A1's requirement on it is unchanged: an install-path spelling, runnable
# from any cwd, never this gate itself. Driven here on the one path that still refuses.
REPO=$(make_repo r5b yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_contains "a probe-failure refusal still names the install-path fix command" \
  "bash $PROBE_SRC" "$GATE_ERR"
expect_absent "refusal does not name a repo-relative fix command (checklist A1)" "hooks/preflight-probe.sh\"" "$GATE_ERR"
case "$GATE_ERR" in
  *"hooks/dispatch-preflight.sh"*) no "refusal never names itself as the fix" ;;
  *) ok "refusal never names itself as the fix" ;;
esac

# ============================================================
echo "=== S6 — active wave + only a FOREIGN session's attestation exists -> AUTO-PROBE (AC-2) ==="
# ============================================================
#
# slice 4/2 (D-5): the foreign attestation is written at ITS OWN per-session filename
# (preflight-<SID_B>.state) — there is no file at all for SID_A, which is exactly what
# "foreign, however fresh, is not an attestation for this session" means once filenames
# are the primary key. That reading is UNCHANGED by R5; what changed is what follows from
# it. A foreign record is still never read as mine — the gate takes my own reading
# instead of refusing, and B's record is left exactly where it was.

REPO=$(make_repo r6 yes)
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "foreign-only attestation auto-probes rather than refusing" "0" "$GATE_ST"
expect_status "…and this session gets a record of its OWN, at its own filename" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
expect_status "…while the LIVE foreign session's record is untouched (D-5)" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_B.state" ] && echo 0 || echo 1)"

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
expect_status "a legacy single-slot attestation is not consulted; the probe runs instead" "0" "$GATE_ST"
expect_status "…and the record that admits the dispatch is at the PER-SESSION filename" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
# The probe prunes the legacy slot on every run — the strongest form of "never consulted"
# is that the file is not there to consult by the time the next dispatch asks.
expect_status "…the legacy slot is gone, not merely ignored" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight.state" ] && echo 1 || echo 0)"

# ============================================================
echo "=== S7 — active wave + attestation IS this session -> pass, verdict silent (AC-2) ==="
# ============================================================
#
# "Silent" here is about the VERDICT (no BLOCKED refusal, nothing on stdout ever) — not
# absolute stderr silence, which S10c's absence warning already established is not the
# invariant. Since the unarmed-sweeper nag was deleted with the watcher (epic-16 w2 S1) a
# contract-complete fixture like this one has nothing to say on stderr either, and that is
# asserted directly below rather than left implied.

REPO=$(make_repo r7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "matching attestation exits 0" "0" "$GATE_ST"
expect_empty "matching attestation produces no stdout (never print on the allow path)" "$GATE_OUT"
expect_absent "matching attestation prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_absent "…and says nothing about a sweeper being armed (the nag is deleted)" \
  "sweeper" "$GATE_ERR"

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
    # make_repo plants a real .bionic/tmp (the Patrol stamp lives there); it has to GO,
    # or `ln -s` lands the link INSIDE it and the hostile shape under test never exists.
    rm -rf "$REPO/.bionic/tmp"
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

# attestation file exists but is empty / has no session_id= line at all. Unlike the
# hostile shapes above, this is not an attack — it is an unreadable fact, which R5 treats
# as no fact at all: the probe re-takes it and overwrites the unreadable record. The
# security property is untouched, because the two are distinguished by WHO fixes them —
# a symlink is refused by the probe, a bad record is replaced by it.
REPO=$(make_repo r8c yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'version=1\nkind=preflight-attestation\n' > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation with no session_id= line -> re-taken, not refused" "0" "$GATE_ST"
expect_status "…and the unreadable record is replaced by a keyed one" "0" \
  "$(grep -qx "session_id=$SID_A" "$REPO/.bionic/tmp/preflight-$SID_A.state" && echo 0 || echo 1)"

# ============================================================
echo "=== S9 — the fix command is runnable from a NON-REPO cwd (checklist A1) ==="
# ============================================================

# The fix line now lives on the surviving refusal — a probe that FAILED — rather than on
# a missing attestation, which the gate takes for itself (S5). What A1 asks of it is
# unchanged: whatever command the refusal hands an operator has to run from wherever they
# are standing, which a repo-relative spelling does not.
REPO=$(make_repo r9 yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
# THE FIX LINE AS THE GATE ACTUALLY PRINTED IT, never a grep for the spelling we
# hope to find. The old form was `grep -oF "bash $PROBE_SRC"`, which could only ever
# yield the exact absolute command or nothing at all — so the one defect A1 exists to
# catch, a repo-relative spelling, made FIXLINE EMPTY, `bash -c ""` exited 0 with no
# stderr, and all three assertions below passed over a run that never happened. The
# extractor pinned away the property under test (.claude memory:
# fixtures-can-pin-away-the-test); proven vacuous by mutation in epic-18 W3 4/2, where
# rewriting PREFLIGHT_CMD to `bash preflight-probe.sh` flipped nothing.
# Lifting the gate's own text lets a relative spelling reach the execution below.
FIXLINE=$(printf '%s\n' "$GATE_ERR" | sed -n 's/.*re-run by hand: \(.*\))\..*/\1/p' | head -1)
# The extractor's own non-emptiness, positive, on the same fixture — without it the
# three assertions below are again a test of nothing (authoring rule: prove the
# extractor before asserting an absence through it).
expect_contains "a fix line was captured to execute" "preflight-probe.sh" "$FIXLINE"

# A throwaway HOME, so executing the captured fix line cannot touch the real one. Since
# epic-17 W1 S3 the fix line resolves the probe beside the GATE rather than under $HOME, so
# the installed copy below is no longer what makes the line runnable — it stays as the
# hostile case: a stale ~/.claude/hooks/ copy that the fix line must NOT be reaching for.
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
  ok "fix command runs from a non-repo cwd"
fi
# `$RUN9_ERR` is the PATH of the capture file; these two used to pass it as the
# HAYSTACK, so they asked whether the string "/tmp/.../run9.err" contains "No such
# file or directory" — which it never can, on any run, however broken. Both were
# vacuous from birth; proven so in epic-18 W3 4/2, where pointing the fix command at
# a file that does not exist (exit 127, that exact message on stderr) flipped neither.
# The arm above already reads the CONTENTS, via `$(cat "$RUN9_ERR")`; these now do too.
RUN9_ERR_TEXT="$(cat "$RUN9_ERR")"
expect_absent "fix-command run produces no 'No such file or directory'" "No such file or directory" "$RUN9_ERR_TEXT"
expect_absent "fix-command run produces no 'command not found'" "command not found" "$RUN9_ERR_TEXT"

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
# The invariant this row protects is "no BLOCKED refusal", asserted directly. Since the
# unarmed-sweeper nag was deleted with the watcher there is nothing else on this stream for
# a contract-complete dispatch either.
expect_absent "a contract-complete dispatch prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_absent "…and nothing about an unarmed sweeper" "sweeper" "$GATE_ERR"
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
  ok "row carries a UTC ISO launch timestamp"
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
# The label sits on its OWN line (R8: final-audit A-1 pinned the deliverable-kind
# labels to line start) — a trailing mid-line occurrence would no longer register
# as a hit at all, and this fixture is meant to test the near-fieldless-brief
# warning path, not the line-start rule.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" \
  "Go and do the thing, please.
Expected artifact: .bionic/docs/record/w99-min.txt" "-" "-")"
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
# the machinery cannot work without — the sweeper's landing verdict has nothing to
# stat, and a dispatch that dies quietly leaves nothing behind. So this single
# field escalates from warn to REFUSAL, and every escape from the refusal is a
# line in the brief, which means it lands on the roster.
#
# Everything else stays exactly where it was: progress absence warns, duration
# absence warns. This is one wall, not a policy.

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
# half of that closure; tests/stop-check.test.sh §8(g) drives the reader half
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
# THE REWRITTEN ASSERTION (Step-6 critic N-2). The line here used to read
#   expect_absent "the cadence value stops at the next label" "Subprocess" …
# which certified a property that was never under threat — the span was ALWAYS
# bounded by the next label — while the real defect (a value running ON past its
# own duration token, on its own line, before any label) went undriven and the
# green masked it. The property that matters is that cadence carries the token
# and NOTHING after it; the run-on case below drives the shape the production
# writer actually emits, and this pins the no-run-on baseline exactly.
expect_status "cadence carries the duration token and no run-on (real property, N-2)" \
  "~6m." "$(roster_field "$ROW" cadence)"
expect_status "the duration is unharmed by the new labels" \
  "~50 minutes." "$(roster_field "$ROW" duration)"

# ---- THE RUN-ON case (Step-6 critic N-2, C-1/F-3 root): cadence followed by
# run-on NON-label prose on the SAME line must still lift a bounded token. This
# is the shape the production writer emitted onto the live roster
# (w2-t3-victim2: `cadence=2m) claims=…`) — the field-merge that flipped a
# visibly-alive agent to UNMET by feeding parse_seconds a value it refuses. The
# defect is NOT rescued by a following label: the run-on sits BEFORE the label,
# already inside the value. Bounded extraction stops at the first clause
# boundary (comma / closing bracket / newline), the same restraint claimpat()
# already applies to the subprocess pattern.
BRIEF_CADENCE_RUNON='Canonical-sdlc Step 4, slice 4/12 of epic-99 wave-01; build · audited · wave.
Your slice: the widget behind the seam.
Expected artifact: .bionic/docs/record/w99-runon.txt
Expected duration: ~50 minutes.
Progress: .bionic/tmp/w99-runon.progress, cadence 2m) claims=w99-marker,/var/tmp/f3 and keep going
Exit condition: the artifact exists.'

REPO=$(make_repo r10Lrunon yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CADENCE_RUNON" "w99-runon")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "run-on cadence: the dispatch passes" "0" "$GATE_ST"
expect_status "run-on cadence: the value is the bounded token, not the swallowed line" \
  "2m" "$(roster_field "$ROW" cadence)"
expect_absent "run-on cadence: the swallowed 'claims=' text never enters the cadence field" \
  "claims=" "$(roster_field "$ROW" cadence)"
expect_absent "run-on cadence: nor does the swallowed path" \
  "/var/tmp/f3" "$(roster_field "$ROW" cadence)"
# The same bounded discipline protects duration from a run-on sentence (A-2:
# an unreadable duration silently exempts a row from overdue notification forever).
BRIEF_DURATION_RUNON='Your slice: build it.
Expected artifact: .bionic/docs/record/w99-durrunon.txt
Expected duration: ~15 minutes. Every verbatim output you quote is its own evidence, laid out.
Progress: .bionic/tmp/w99-durrunon.progress'
REPO=$(make_repo r10Ldur yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_DURATION_RUNON" "w99-durrunon")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "run-on duration: the value stops at the end of its own sentence" \
  "~15 minutes." "$(roster_field "$ROW" duration)"
expect_absent "run-on duration: the following sentence never enters the field" \
  "verbatim" "$(roster_field "$ROW" duration)"

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
probe_env_on   # restore the file-wide sandbox, never the operator's own config dir

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

# refused dispatch (active wave, the environment probe refuses): the launch never
# happens. The driver moved with the wall itself in epic-16 wave-02 — a missing
# attestation is now taken rather than refused, so the refusal this case needs is the one
# that survived: a blocking probe failure, here an unwritable state directory.
REPO=$(make_repo r10i yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
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
echo "=== S11 — the unarmed-sweeper nag is GONE (epic-16 w2 slice S1) ==="
# ============================================================
#
# A warn-only nag stood here: it asked the sibling sweeper whether a watcher was live for
# this session and, when none was, named the command to arm one. Both the watcher and its
# `status` verb are deleted, so the nag went with them — supervision reads facts off disk at
# the moment a decision needs them rather than depending on a process staying up.
#
# Pinned as an ABSENCE, in the section that used to drive its presence, for two reasons. A
# nag that names a verb the CLI no longer answers to is worse than no nag: it sends an
# operator to a refusal. And this gate has a standing invariant that the allow path prints
# nothing but ratified advisories — a stale one would be invisible to every other assertion
# here, all of which only ask about BLOCKED.

# ---- no ledger at all: the dispatch passes in SILENCE, where it used to warn ----
REPO=$(make_repo r11a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no-ledger dispatch passes" "0" "$GATE_ST"
expect_empty "…in silence: there is no sweeper state left to nag about" "$GATE_ERR"

# ---- a ledger present but naming no live anything: still silent ----
#
# The ledger survives as ack's journal, so this fixture is the shape a real session leaves
# behind. The gate must not read it, or resurrect an opinion about it.
REPO=$(make_repo r11b yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic/tmp"
{
  printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n'
  printf 'sweeper-ledger/v1|event=ack|at=2026-08-06T00:00:00Z|epoch=1780000000|pid=999999|session=%s|name=some-row\n' \
    "$SID_A"
} > "$REPO/.bionic/tmp/sweeper-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a dispatch over an ack-only ledger passes" "0" "$GATE_ST"
expect_empty "…and still says nothing about it" "$GATE_ERR"

# ---- the gate never names the deleted verbs, and never invokes the sweeper at all ----
GATE_SRC="$(cat "$GATE")"
expect_absent "the gate source names no arm command" "session-sweeper.sh arm" "$GATE_SRC"
expect_absent "…and carries no SWEEPER_ARM_CMD constant" "SWEEPER_ARM_CMD" "$GATE_SRC"
# The stronger claim, and the one that keeps a future nag from growing back through some
# other verb: this gate runs the sweeper on NO path. It writes the roster the verdict later
# reads; it never asks the verdict anything.
expect_status "the gate executes the sweeper on no path at all" "0" \
  "$(printf '%s' "$GATE_SRC" | grep -cE 'bash [^\n]*session-sweeper\.sh')"

# ---- a REFUSED dispatch is unchanged: still exits 2, still says nothing about a sweeper ----
REPO=$(make_repo r11d yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_status "a refused dispatch (the probe refused) still exits 2" "2" "$GATE_ST"
expect_absent "a refused dispatch prints no sweeper nag" "session-sweeper.sh" "$GATE_ERR"

# ============================================================
echo "=== S12 — inference WITHDRAWN: an unlabeled path never satisfies the wall (R1, AC-3) ==="
# ============================================================
#
# THE REVERSAL (Step-6 decision, plan assumption 48). Wave-02 R4 let an unlabeled
# `record/`-prefixed path satisfy the deliverable wall by INFERENCE — walking the
# whole brief for a path-shaped token. The Step-6 critic (N-1) found the machine
# then enforced that GUESS with a declared fact's full weight: the landing gate
# ordered the agent to write a path the wall picked out of prose. Chris's ruling:
# the wall NEVER guesses a deliverable from prose. A deliverable comes ONLY from a
# canonical label; a brief that declares none REFUSES at dispatch, naming what to
# add. These cases pin the withdrawal: every prose path that used to infer now
# refuses, and only a labeled declaration passes.

# ---- an unlabeled .bionic/docs/record/ mention no longer infers -> REFUSE ----
BRIEF_BARE_RECORD='Your slice: read the tree and note what you find.
It belongs in .bionic/docs/record/w99-bare.md when finished.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_RECORD" "w99-bare")"
expect_status "an unlabeled .bionic/docs/record/ mention is REFUSED (no inference)" "2" "$GATE_ST"
expect_contains "…with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "…and no prose path is lifted onto a roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- a bare record/ prefix in prose is refused the same way ----
BRIEF_BARE_RECORD2='Your slice: capture findings as you go.
Write to record/w99-bare2.md at the end.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12a2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_RECORD2" "w99-bare2")"
expect_status "a bare record/ prefix in prose is also REFUSED" "2" "$GATE_ST"
expect_contains "…with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- the same, but DECLARED: adding a canonical label is the whole fix ----
#
# The friction R1 accepts is that a brief must DECLARE its deliverable. The same
# work, with `Expected artifact:` in front of the path, passes and is `declared`.
BRIEF_BARE_DECLARED='Your slice: read the tree and note what you find.
Expected artifact: .bionic/docs/record/w99-bare.md
Expected duration: ~10 minutes.'

REPO=$(make_repo r12a3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_BARE_DECLARED" "w99-baredecl")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "declaring the same path with a canonical label passes" "0" "$GATE_ST"
expect_status "…and the row carries the declared path" \
  ".bionic/docs/record/w99-bare.md" "$(roster_field "$ROW" deliverable)"
expect_status "…marked declared" "declared" "$(roster_field "$ROW" source)"

# ---- a non-record path in a 'Read first:' is still refused (unchanged) ----
BRIEF_ONLY_READFIRST='Read first: skills/canonical-sdlc/SKILL.md
Expected duration: ~10 minutes.'

REPO=$(make_repo r12b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_READFIRST" "w99-readfirst")"
expect_status "a brief whose only path is a non-record 'Read first:' mention is refused" \
  "2" "$GATE_ST"
expect_contains "…with the deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- an unlabeled .bionic/tmp/ path is refused (a scratch path was never durable) ----
BRIEF_ONLY_TMP='Your slice: write scratch notes to .bionic/tmp/w99-scratch.md as you go.
Expected duration: ~10 minutes.'

REPO=$(make_repo r12c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_TMP" "w99-tmp")"
expect_status "a brief whose only unlabeled path is under .bionic/tmp/ is refused" "2" "$GATE_ST"
expect_contains "…with the deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- a labeled brief records source=declared; behavior otherwise unchanged ----
REPO=$(make_repo r12d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-declared")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a labeled deliverable passes the wall (unchanged)" "0" "$GATE_ST"
expect_status "the row's deliverable is exactly the labeled path" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "the row marks the source as declared" "declared" "$(roster_field "$ROW" source)"
expect_status "duration is unaffected" \
  "~25 minutes." "$(roster_field "$ROW" duration)"
expect_status "progress is unaffected" \
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
expect_status "…marked declared (the label is explicit designation)" \
  "declared" "$(roster_field "$ROW" source)"

# ---- the refusal text names the declared-only rule, not an inference rule ----
REPO=$(make_repo r12f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONLY_READFIRST" "w99-refusaltext")"
expect_contains "the refusal names a canonical label to add" "Expected artifact:" "$GATE_ERR"
expect_contains "the refusal says the wall never guesses" "never guesses" "$GATE_ERR"
expect_absent "…and no longer promises to infer an unlabeled record/ mention" \
  "inferred automatically" "$GATE_ERR"

# ---- SHADOWED LABEL: an earlier pathless deliverable-kind hit no longer hides a
# later real labeled line — the declared extractor iterates every deliverable hit ----
#
# The live specimen (a real brief false-blocked): a brief quoting landing-verdict
# prose — "…per deliverable:" — ahead of its real "Expected artifact:" line. The
# bare `deliverable` label hits FIRST by position, and its span ("missing=<x> |
# empty=<y>") carries no path. Under R1 the extractor does not stop at the first
# hit; it walks EVERY deliverable-kind hit in order and returns the first that
# yields a path — so the real, later, labeled line is recovered, and recorded
# `declared` because it came from a label, not from a prose scan.
BRIEF_SHADOW_LABEL='UNMET detail lists every failing conjunct, per deliverable:
missing=<x> | empty=<y>

Expected artifact: .bionic/docs/record/w1-specimen.md'

REPO=$(make_repo r12g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_SHADOW_LABEL" "w1-specimen")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "an earlier pathless 'per deliverable:' hit no longer shadows the real labeled line" \
  "0" "$GATE_ST"
expect_absent "…and prints no refusal" "BLOCKED" "$GATE_ERR"
expect_status "the roster records the real declared deliverable, recovered by iterating hits" \
  ".bionic/docs/record/w1-specimen.md" "$(roster_field "$ROW" deliverable)"
expect_status "the recovered value is DECLARED — it came from a label, not a prose scan" \
  "declared" "$(roster_field "$ROW" source)"

# ============================================================
echo "=== S13 — Step-6 review remediation A + R1: C-1/C-2/F-RD, S-1, S-2, S-4 ==="
# ============================================================
#
# Holes found by the independent Step-6 reviewers (w1-review-corr-sec.md and, for
# this wave, w2-review-cs.md C-2 + w2-review-rd.md F-RD). Each case below was
# written and run against the PRE-FIX gate first and observed to fail.

# ---------- C-1/F-RD (blocking) — a path the brief tells the agent to READ, or
# merely names in prose, must never become the deliverable. Under R1 the property
# is enforced structurally, not by a label whitelist: the deliverable comes ONLY
# from a canonical label, so an input path (labeled or bare prose) is refused, not
# guessed. This ends the whitelist arms race the critic named — F-RD walked past
# the wave-01 `Read first:`/`scope constraint:` whitelist through a `Context:`
# heading the guard did not know.

BRIEF_READFIRST_RECORD='Please review the design.

Read first: .bionic/docs/record/w1-walk.md and the spec.

Expected duration: 20 minutes'

REPO=$(make_repo r13a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_READFIRST_RECORD" "readerbot")"
expect_status "C-1: a record/ path inside a Read-first span is never the deliverable — the dispatch is refused" \
  "2" "$GATE_ST"
expect_contains "C-1: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "C-1: …and no roster row claims the input as a deliverable" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# The other input-designating label, refused the same way.
BRIEF_SCOPE_RECORD='Your slice: tidy the tree.
Scope constraint: do not touch .bionic/docs/record/context.md.
Expected duration: 20 minutes'

REPO=$(make_repo r13b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_SCOPE_RECORD" "scopebot")"
expect_status "C-1: a record/ path inside a Scope-constraint span is never the deliverable either" \
  "2" "$GATE_ST"

# F-RD, EXACT re-materialization: the review's own brief named its inputs under a
# `Context:` heading the wave-01 whitelist did not recognise, and the wall inferred
# the AUDITOR's report as the reviewer's deliverable — the landing gate then ordered
# the reviewer to overwrite an independent audit. Under R1 there is no inference:
# `Context:` is not a canonical deliverable label, so the path is never lifted and
# the dispatch REFUSES, naming what to declare.
BRIEF_CONTEXT_PATH='Your slice: an independent read-and-duplication review.
Context: read the auditor report record/w2-auditor-report.md and the spec first.
Report: your findings belong in record/w2-review-rd.md.
Expected duration: 20 minutes'

REPO=$(make_repo r13frd yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CONTEXT_PATH" "w2-rev-rd")"
expect_status "F-RD: a 'Context:' record/ path is NOT lifted as the deliverable — the dispatch is refused" \
  "2" "$GATE_ST"
expect_contains "F-RD: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "F-RD: …and no roster row contracts the reviewer to the auditor's report" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# C-2 (w2-review-cs.md) — the LABELLED span used to take up to four path tokens and
# run on into whatever prose followed, so files the brief named as INPUTS ("while
# you are there, read …"; "do not touch …") were recorded `source=declared` and the
# landing gate demanded all four. R1 answered by taking the FIRST path in the label's
# first sentence; the R6 critic showed that is a guess with a declaration's weight
# (R6-1), so R7 refuses instead: a span yielding more than one path names candidates
# and asks the author which one is theirs. The input paths are still never contracted —
# now because nothing is contracted until the brief is unambiguous.
BRIEF_LABEL_RUNON='Your slice: write the report.
Expected artifact: record/w99-report.md — and while you are there, read record/legacy-notes.md
and do not touch tests/run.sh or .bionic/docs/plans/epic-99-test/wave-01-test.plan.md
Expected duration: ~20 minutes.'

REPO=$(make_repo r13c2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LABEL_RUNON" "runonbot")"
expect_status "C-2: a run-on labelled span naming four paths is REFUSED as ambiguous (R7)" \
  "2" "$GATE_ST"
expect_contains "C-2: …the refusal names the declared artifact" \
  "record/w99-report.md" "$GATE_ERR"
expect_contains "C-2: …and the 'read …' input path, so neither is chosen for the author" \
  "record/legacy-notes.md" "$GATE_ERR"
expect_contains "C-2: …and the 'do not touch' suite runner" "tests/run.sh" "$GATE_ERR"
expect_status "C-2: …and no roster row demands any of the four" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# THE PAIRED POSITIVE: the exactly-one rule must not become "declaring is off" — a
# properly DECLARED path outside any input mention still lifts, and this is the
# resubmission the refusal above asks for: the same brief with the input clauses moved
# to their own labeled lines.
BRIEF_LABEL_CLEAN='Your slice: write the report.
Expected artifact: record/w99-report.md
Read first: record/legacy-notes.md
Expected duration: ~20 minutes.'

REPO=$(make_repo r13c3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LABEL_CLEAN" "cleanbot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "C-2 paired positive: a cleanly declared deliverable still passes" "0" "$GATE_ST"
expect_status "C-2 paired positive: …recorded as the declared path" \
  "record/w99-report.md" "$(roster_field "$ROW" deliverable)"
expect_status "C-2 paired positive: …marked declared" "declared" "$(roster_field "$ROW" source)"

# ---------- S-1 (High) — the waiver label lifts only at LINE START, and a
# placeholder-shaped reason is not a reason. One quoted line of documentation
# must not silence the landing contract.

# (a) the reviewer's revsec002 quoter: a real deliverable, and the wall's own
# message quoted mid-sentence. The row must carry NO waiver.
BRIEF_QUOTER='Expected artifact: .bionic/docs/record/quoter-out.md
Expected duration: 20 minutes

Check that the wall message still reads: "Or waive it — Deliverable-waiver: <why this dispatch produces nothing durable>".
Report whether the wording drifted.'

REPO=$(make_repo r13d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTER" "quoter")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S-1: a mid-sentence quoted waiver label lifts NO waiver" \
  "" "$(roster_field "$ROW" waiver)"
expect_absent "S-1: …and nothing is echoed as waived" "waived" "$GATE_ERR"
expect_status "S-1: …the real labeled deliverable is unaffected" \
  ".bionic/docs/record/quoter-out.md" "$(roster_field "$ROW" deliverable)"

# (b) the same quoting with NO deliverable — this is the fail-open the review
# named: one quoted line and the wall opens. The reason quoted here is a REAL
# one, so only the line-start rule can refuse it.
BRIEF_QUOTED_WAIVER='Your slice: check the wall text.
Confirm the message still reads: "Or waive it — Deliverable-waiver: read-only reconnaissance".
Expected duration: 20 minutes'

REPO=$(make_repo r13e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTED_WAIVER" "quoter2")"
expect_status "S-1: a quoted mid-sentence waiver does not open the absent-deliverable wall" \
  "2" "$GATE_ST"
expect_contains "S-1: …the refusal still names the escape" "Deliverable-waiver:" "$GATE_ERR"

# (c) a line-start waiver whose reason is the literal placeholder from the wall
# text is not a reason.
BRIEF_PLACEHOLDER_WAIVER='Your slice: do the thing.
Deliverable-waiver: <why this dispatch produces nothing durable>
Expected duration: 20 minutes'

REPO=$(make_repo r13f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PLACEHOLDER_WAIVER" "placeholder")"
expect_status "S-1: a placeholder-shaped waiver reason does not open the wall" "2" "$GATE_ST"

# CONTROL: a real line-start waiver still lifts, indented or not.
BRIEF_INDENTED_WAIVER='Your slice: answer one question from the tree.
    Deliverable-waiver: read-only reconnaissance, the answer is the report itself
Expected duration: 20 minutes'

REPO=$(make_repo r13g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_INDENTED_WAIVER" "waived2")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S-1 control: an indented line-start waiver with a real reason still lifts" \
  "0" "$GATE_ST"
expect_status "S-1 control: …and is ledgered" \
  "read-only reconnaissance, the answer is the report itself" "$(roster_field "$ROW" waiver)"

# ---------- S-2 (Medium) — a deliverable that resolves outside the repo root is
# refused at dispatch, where it is still fixable. Otherwise the verdict stats
# arbitrary paths and reports their mtime back to the stopping agent.

BRIEF_ESCAPE_REL='Your slice: do the thing.
Expected artifact: ../../../../../../etc/hosts
Expected duration: 20 minutes'

REPO=$(make_repo r13h yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ESCAPE_REL" "escaper")"
expect_status "S-2: a ..-escaping deliverable is refused at the dispatch wall" "2" "$GATE_ST"
expect_contains "S-2: …the refusal is phrased as a block" "BLOCKED" "$GATE_ERR"
expect_contains "S-2: …and names the offending path" "../../../../../../etc/hosts" "$GATE_ERR"
expect_status "S-2: …and no roster row is written for it" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

BRIEF_ESCAPE_ABS='Your slice: do the thing.
Expected artifact: /usr/share
Expected duration: 20 minutes'

REPO=$(make_repo r13i yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ESCAPE_ABS" "escaper2")"
expect_status "S-2: an absolute out-of-repo deliverable is refused too" "2" "$GATE_ST"
expect_contains "S-2: …and names it" "/usr/share" "$GATE_ERR"

# CONTROL: an in-repo ABSOLUTE path is a perfectly good deliverable and must
# still pass — the check is containment, not a ban on absolute paths.
REPO=$(make_repo r13j yes)
write_attestation "$REPO" "$SID_A"
BRIEF_ABS_INREPO="Your slice: do the thing.
Expected artifact: $REPO/.bionic/docs/record/w99-abs.md
Expected duration: 20 minutes"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ABS_INREPO" "absbot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S-2 control: an in-repo absolute deliverable still passes" "0" "$GATE_ST"
expect_status "S-2 control: …and is recorded verbatim" \
  "$REPO/.bionic/docs/record/w99-abs.md" "$(roster_field "$ROW" deliverable)"

# ---------- S-4 (Low, defence-in-depth) — the payload session_id is shape-checked
# before it is interpolated into any state path.
#
# The escape is only OBSERVABLE if the intermediate directories exist, so the
# fixture creates them; the vulnerability is the unchecked interpolation, not the
# directories. With sid `a/../../rogue`, both the attestation path and the roster
# path resolve to $REPO/.bionic/rogue.state — one level ABOVE the state dir the
# symlink guards protect.
SID_EVIL="a/../../rogue"
REPO=$(make_repo r13k yes)
mkdir -p "$REPO/.bionic/tmp/preflight-a" "$REPO/.bionic/tmp/roster-a"
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\n'
  printf 'kind=preflight-attestation\n'
  printf 'session_id=%s\n' "$SID_EVIL"
  printf 'written_at=1785790000\n'
  printf 'repo=%s\n' "$REPO"
} > "$REPO/.bionic/rogue.state"
run_gate "$(mk_agent_payload "$SID_EVIL" "$REPO" "$BRIEF_FULL" "evilsid")"
expect_status "S-4: a shape-invalid session_id degrades to a silent pass" "0" "$GATE_ST"
expect_status "S-4: …and NO roster row is written outside the state directory" "0" \
  "$(grep -c '^roster-state/' "$REPO/.bionic/rogue.state" 2>/dev/null)"
expect_absent "S-4: …and the escaped path is never named on stderr" "rogue.state" "$GATE_ERR"

# ============================================================
echo "=== S14 — a templated deliverable is not a declaration: it REFUSES (R1) ==="
# ============================================================
#
# The `<slot>` shape has a long lineage. Wave-01 remediation A-b made `ispath()`
# reject any token carrying an unfilled `<…>` slot, so a brief quoting the wall's
# own help text — `Expected artifact: .bionic/docs/record/<name>.md` — could not
# lift a contract nothing would satisfy. Wave-02 R4 then FILLED the slot from the
# agent name and recorded `source=inferred`. R1 withdraws that fill: filling a slot
# from the agent's name is guessing a deliverable, which is exactly what the wall
# must never do. A slot is still not a path (ispath rejects it), so a brief whose
# ONLY deliverable is a template names no concrete path and REFUSES — the author is
# told at dispatch to name it exactly. A real declared line alongside the template
# is still recovered (the extractor iterates every deliverable hit).

BRIEF_QUOTES_HELP='Your slice: check that the wall message still reads right.
It currently says: Fix: name a durable artifact path in the brief —
    Expected artifact: .bionic/docs/record/<name>.md
Report whether the wording drifted.
Expected duration: 20 minutes'

REPO=$(make_repo r14a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTES_HELP" "helpquoter")"
expect_status "a brief whose only deliverable is the help-text template is REFUSED (no fill)" \
  "2" "$GATE_ST"
expect_contains "…with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "…and no roster row is written at all" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# A quoted template ahead of a REAL labeled line: the real one is recovered (the
# extractor walks every deliverable hit), and the slot never reaches the row.
BRIEF_HELP_THEN_REAL='Your slice: verify the wall text, then write up what you find.
The message reads: Expected artifact: .bionic/docs/record/<name>.md
Expected artifact: .bionic/docs/record/w99-shape2.md
Expected duration: 20 minutes'

REPO=$(make_repo r14b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_HELP_THEN_REAL" "helpquoter2")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a quoted template ahead of a real line does not shadow it" "0" "$GATE_ST"
expect_status "…the row carries the REAL artifact, never the slot" \
  ".bionic/docs/record/w99-shape2.md" "$(roster_field "$ROW" deliverable)"
expect_status "…recorded declared (it came from a label)" "declared" "$(roster_field "$ROW" source)"
expect_absent "…and the slot appears nowhere on the row" "<name>" "$ROW"

# An ordinary labeled deliverable is untouched by any of this.
REPO=$(make_repo r14c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-stillworks")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "control: an ordinary labeled deliverable is unaffected" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "…and is still marked declared" "declared" "$(roster_field "$ROW" source)"

# A templated PROGRESS path is also not filled — progress is advisory (absent
# warns), so a template that names no concrete path leaves it EMPTY and WARNED,
# exactly as a missing one is. The real deliverable is unaffected.
BRIEF_PLACEHOLDER_PROGRESS='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-progplaceholder.md
Progress artifact: .bionic/tmp/<name>.progress
Expected duration: 20 minutes'

REPO=$(make_repo r14d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PLACEHOLDER_PROGRESS" "progplaceholder")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a templated PROGRESS path is not filled — the field is left empty" \
  "" "$(roster_field "$ROW" progress)"
expect_absent "…so no slot reaches the field the liveness check stats" "<" \
  "$(roster_field "$ROW" progress)"
expect_contains "…and the absent progress path is warned" "progress" "$GATE_ERR"
expect_status "…while the real deliverable still passes the wall" "0" "$GATE_ST"

# ============================================================
echo "=== S15 — the ship-day corners now pass BY DECLARING, not by guessing (R1, AC-3) ==="
# ============================================================
#
# The two 2026-08-08 false blocks were GRAMMAR corners
# (`plans/epic-16-landing-contract/continuation.md` §charter-seed, decision 3: "Both of
# the day's false blocks were grammar corners (mid-string `<slot>` vs `^<`, and the
# quoted-help-text deliverable lift)"). R4 answered them by GUESSING a deliverable from
# prose and filling slots from the agent name. The Step-6 critic (N-1) showed the guess
# is then enforced with a declared fact's full weight, so Chris withdrew inference: the
# friction the wave wanted to remove was the requirement to DECLARE, and the reframe is
# that declaring is cheap and robustly parsed while guessing is off-thesis. So each
# corner now takes the same shape — as-written it REFUSES (there is no concrete declared
# path), and adding one canonical label makes it pass as `declared`.
#
# FIXTURE FIDELITY — declared, narrower than "verbatim": no ship-day brief text survives
# on disk (searched: `grep -rn "names no deliverable\|false-block" .bionic/docs/record/`);
# what survives is a DESCRIPTION of each corner in the charter seed, commit 121d277's
# message, and `record/w1-remediation-A2-report.md`. These briefs are RECONSTRUCTED to
# those descriptions. What IS verbatim is the thing that made the corner:
# BRIEF_QUOTES_HELP quotes this gate's own help text, where every ship-day `<name>.md`
# came from. Each corner is driven BOTH ways — refused as-written, accepted once declared.

# ---- corner 1: the MID-STRING slot in prose. As-written -> REFUSE ----
BRIEF_CORNER1='Canonical-sdlc Step 4, slice S4 of epic-99 wave-02; build · audited · wave.
Your slice: reconcile the label grammar with the declared parse.
Write your findings to .bionic/docs/record/w2-<slice>-notes.md when the suite is green.
Expected duration: ~20 minutes.'

REPO=$(make_repo r15a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CORNER1" "corner1")"
expect_status "AC-3 corner 1 (mid-string slot in prose): REFUSED, no path is guessed" "2" "$GATE_ST"
expect_contains "AC-3 corner 1: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"
expect_status "AC-3 corner 1: …and no roster row is written" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# corner 1, DECLARED: adding a canonical label with a concrete name is the whole fix.
BRIEF_CORNER1_FIXED='Canonical-sdlc Step 4, slice S4 of epic-99 wave-02; build · audited · wave.
Your slice: reconcile the label grammar with the declared parse.
Expected artifact: .bionic/docs/record/w2-s4-notes.md
Expected duration: ~20 minutes.'

REPO=$(make_repo r15a2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CORNER1_FIXED" "corner1")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "AC-3 corner 1 fixed: declaring a concrete path passes" "0" "$GATE_ST"
expect_status "AC-3 corner 1 fixed: …the row carries the declared path" \
  ".bionic/docs/record/w2-s4-notes.md" "$(roster_field "$ROW" deliverable)"
expect_status "AC-3 corner 1 fixed: …marked declared" "declared" "$(roster_field "$ROW" source)"
expect_absent "AC-3 corner 1 fixed: …no slot survives onto the roster" "<" "$ROW"

# ---- corner 2: the QUOTED-HELP-TEXT template. As-written it REFUSES (S14 r14a); the
# fix is BRIEF_HELP_THEN_REAL — the same quote plus a real declared line (S14 r14b).
# Both are pinned in S14; here we assert the FRAMING: the corner's resolution is to
# declare, and the declared line is what carries the contract.
REPO=$(make_repo r15b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_HELP_THEN_REAL" "helpquoter")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "AC-3 corner 2 (quoted help text + a real declaration): passes" "0" "$GATE_ST"
expect_status "AC-3 corner 2: …the declared line carries the contract, not the quoted slot" \
  ".bionic/docs/record/w99-shape2.md" "$(roster_field "$ROW" deliverable)"
expect_status "AC-3 corner 2: …recorded declared" "declared" "$(roster_field "$ROW" source)"

# ---- THE PLANTED FAILURE (AC-3): a brief naming no concrete path STILL refuses ----
#
# The wall did not become advisory. A brief that names no concrete declared path — no
# label, no record/ mention, no template — has given the machinery nothing to stat.
BRIEF_NOTHING='Your slice: read the wall message through and tell me whether the wording drifted.
Expected duration: ~15 minutes.'

REPO=$(make_repo r15c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NOTHING" "saysnothing")"
expect_status "AC-3 planted failure: a brief naming no plausible deliverable is STILL refused" \
  "2" "$GATE_ST"
expect_contains "AC-3 planted failure: …with the absent-deliverable refusal" \
  "names no deliverable" "$GATE_ERR"

# ---- an unnamed dispatch whose only deliverable is a template is refused (no fill,
# no ancestor fallback) — the withdrawal is total, not "fill when a name exists" ----
REPO=$(make_repo r15f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_QUOTES_HELP" "-")"
expect_status "AC-3: an unnamed dispatch with only a templated path is REFUSED" "2" "$GATE_ST"
expect_contains "AC-3: …with the absent-deliverable refusal" "names no deliverable" "$GATE_ERR"

# ---- a real declared path always wins over a quoted template, wherever it sits, and
# is recorded DECLARED — the extractor walks every deliverable hit and takes the first
# that yields a concrete path ----
REPO=$(make_repo r15h yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_HELP_THEN_REAL" "helpquoter2")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "AC-3: a quoted template ahead of a real line still loses to it" \
  ".bionic/docs/record/w99-shape2.md" "$(roster_field "$ROW" deliverable)"
expect_status "AC-3: …recorded declared, because a label yielded it" \
  "declared" "$(roster_field "$ROW" source)"

# ============================================================
echo "=== S16 — the combined preflight: a missing attestation AUTO-RUNS the probe (epic-16 w2 S5, AC-4) ==="
# ============================================================
#
# Synthesis §3, the five serialized minutes between order and spawn: the operator was
# refused, ran the probe by hand, retried, and only then dispatched. R5 makes the
# attestation a FACT the gate takes for itself — the probe is run inline, once, and the
# dispatch proceeds. Blocking survives in exactly one place on this path: the probe
# REFUSING, which means the environment is genuinely broken and the fleet would die.
#
# The probe invoked here is the REAL `hooks/preflight-probe.sh` sitting beside the gate —
# no stub, no seam. Its environment is substituted instead (a sandboxed config dir and a
# fixture credential), which is the same technique preflight-probe.test.sh uses.

# ---- ONE invocation, order to spawn: no attestation in, dispatch out ----
REPO=$(make_repo r16a yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "AC-4: a dispatch with NO attestation is no longer refused" "0" "$GATE_ST"
expect_status "AC-4: …the probe ran inline and left this session's attestation on disk" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
expect_status "AC-4: …keyed to THIS session, not whatever the shell was" "0" \
  "$(grep -qx "session_id=$SID_A" "$REPO/.bionic/tmp/preflight-$SID_A.state" && echo 0 || echo 1)"
expect_contains "AC-4: …and the auto-run is announced, not silent" "attestation" "$GATE_ERR"
expect_absent "AC-4: …with no refusal anywhere in it" "BLOCKED" "$GATE_ERR"
expect_status "AC-4: …the dispatch is journalled exactly once (one invocation, one row)" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# The probe roots from the PINNED root, so the record it writes describes the repo the
# gate is guarding — the Synthesis field case (attestation redone because the root came
# from the shell's working directory) read the other way round.
# Compared PHYSICALLY on both sides. The sandbox lives under the platform temp dir,
# which is reached through a symlink on macOS (/var -> /private/var), so a string compare
# against the test's own spelling of the path would fail on a correct answer.
ATT_REPO=$(grep -m1 '^repo=' "$REPO/.bionic/tmp/preflight-$SID_A.state" | cut -d= -f2-)
expect_status "AC-4: …and the attestation names the pinned repo root" \
  "$(cd "$REPO" && pwd -P)" "$(cd "$ATT_REPO" 2>/dev/null && pwd -P)"

# ---- a FOREIGN-only attestation is the same fact: absent for me ----
REPO=$(make_repo r16b yes)
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "AC-4: a foreign-only attestation auto-probes rather than refusing" "0" "$GATE_ST"
expect_status "AC-4: …and session B's record is left strictly alone" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_B.state" ] && echo 0 || echo 1)"

# ---- probe FAILURE fails CLOSED: the one surviving attestation refusal ----
#
# Driven by an unwritable state directory rather than an absent credential: the
# credential's third source is the machine keychain, which no sandbox can take away, so
# an absent-credential fixture would pass on this operator's machine and fail on a build
# box. An unwritable directory is the same blocking-probe class and is deterministic.
REPO=$(make_repo r16c yes)
mkdir -p "$REPO/.bionic/tmp"
chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_status "AC-4: a probe that FAILS blocks the dispatch (the environment is broken)" \
  "2" "$GATE_ST"
expect_contains "AC-4: …the refusal is phrased as a block" "BLOCKED" "$GATE_ERR"
expect_contains "AC-4: …and hands over the probe's own reason, not a paraphrase" \
  "state dir" "$GATE_ERR"
expect_status "AC-4: …and a blocked dispatch is journalled nowhere (AC-12)" "0" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 1 || echo 0)"

# ============================================================
echo "=== S17 — ledger hygiene: a refusal leaves NO row; a same-path claim WARNS (epic-16 w2 S4, AC-12) ==="
# ============================================================
#
# The F-4 phantom-intended-rows class, closed by inventory rather than by inspection: the
# roster is compared BYTE FOR BYTE across a refused dispatch, so a row added anywhere on
# any refusal path fails this regardless of what it says. Each absence assertion carries
# its accepted-dispatch twin, because "no row was written" is trivially true of a gate
# that writes no rows at all.

# ---- the paired positive first: an accepted dispatch writes exactly one row ----
REPO=$(make_repo r17a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "AC-12 paired positive: an ACCEPTED dispatch creates exactly one row" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- and each refusal path leaves the inventory untouched ----
#
# The roster is pre-seeded with a real accepted dispatch so the comparison is against a
# NON-EMPTY ledger: "identical" then means the refusal added nothing, not that the file
# never existed.
for _case in nodeliverable outofrepo; do
  REPO=$(make_repo "r17-$_case" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "seed-row")"
  RP="$(roster_path "$REPO" "$SID_A")"
  BEFORE="$(cat "$RP" 2>/dev/null)"
  BEFORE_N="$(roster_rows "$RP")"
  case "$_case" in
    nodeliverable) _brief="$BRIEF_NOTHING" ;;
    outofrepo)     _brief='Your slice: build it.
Expected artifact: ../../../../../../etc/hosts
Expected duration: ~15 minutes.' ;;
  esac
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$_brief" "ghost-$_case")"
  expect_status "AC-12 ($_case): the dispatch is refused" "2" "$GATE_ST"
  expect_status "AC-12 ($_case): the roster is byte-identical across the refusal" \
    "$BEFORE" "$(cat "$RP" 2>/dev/null)"
  expect_status "AC-12 ($_case): …and still holds only the accepted dispatch's row" \
    "$BEFORE_N" "$(roster_rows "$RP")"
  expect_absent "AC-12 ($_case): the refused agent's name appears on no row" \
    "ghost-$_case" "$(cat "$RP" 2>/dev/null)"
done

# ---- a second dispatch claiming a path an open row already owns: WARN, never block ----
REPO=$(make_repo r17b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "first-owner")"
expect_status "AC-12: the first claim on a path passes silently" "0" "$GATE_ST"
expect_absent "AC-12: …with no contention warning, since nothing else owns it" \
  "already" "$GATE_ERR"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "second-owner")"
expect_status "AC-12: a second dispatch claiming the same deliverable is NOT blocked" "0" "$GATE_ST"
expect_contains "AC-12: …it draws a warning" "already" "$GATE_ERR"
expect_contains "AC-12: …that names the OWNING row" "first-owner" "$GATE_ERR"
expect_contains "AC-12: …and the contested path" ".bionic/docs/record/w99-widget.txt" "$GATE_ERR"
expect_status "AC-12: …and the second row is journalled all the same" "2" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# a DIFFERENT path in the same session is not contention
REPO=$(make_repo r17c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "owner-a")"
BRIEF_OTHER_PATH='Your slice: build the other widget.
Expected artifact: .bionic/docs/record/w99-other.txt
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-other.progress'
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_OTHER_PATH" "owner-b")"
expect_status "AC-12 paired negative: a distinct deliverable draws no contention warning" "0" "$GATE_ST"
expect_absent "AC-12 paired negative: …and says nothing about an owner" "already" "$GATE_ERR"

# ============================================================
echo "=== S18 — EXACTLY ONE path under the deliverable label (R7: R6 critic R6-1/R6-2/R6-3/R6-4) ==="
# ============================================================
#
# R1 withdrew prose inference but kept a guess inside the label: it read the FIRST
# SENTENCE of the label span and took the FIRST path-shaped token in it. The R6 critic
# showed that is F-RD wearing a declaration's clothes — "same shape as A, written to B"
# contracted A, recorded `source=declared`, and the landing gate then ordered the agent
# to write A (an existing report it was told to READ). Worse than pre-R1, where the
# over-broad span at least CONTAINED the real deliverable.
#
# THE RULE (plan assumption 71, faithful completion of 48s never guess — declare or
# refuse): the deliverable labels span must yield EXACTLY ONE path. Zero refuses (name
# one); more than one REFUSES, naming every candidate, because choosing among them is
# the guess. No position heuristic, no reading-verb whitelist, no first-wins.
#
# Because ambiguity is now fatal rather than resolved, the search window WIDENS back to
# the whole span — which retires the false-block R1s first-sentence bound introduced
# (a path in the labels second sentence was invisible, and the refusal told the author
# to name a path they had already named).

# ---- R6-1 CASE 9: two paths in one deliverable sentence -> REFUSE, both named ----
BRIEF_TWO_PATHS_SHAPE='You are reviewing the wave.

Expected artifact: same shape as .bionic/docs/record/w2-critic-report.md, written to .bionic/docs/record/w2-probe-frd.md
Expected duration: 30 minutes.'

REPO=$(make_repo r18a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_PATHS_SHAPE" "shapebot")"
expect_status "R6-1 CASE 9: a deliverable span naming two paths is REFUSED, never resolved" \
  "2" "$GATE_ST"
expect_contains "R6-1 CASE 9: …the refusal names the reference path" \
  ".bionic/docs/record/w2-critic-report.md" "$GATE_ERR"
expect_contains "R6-1 CASE 9: …and the real artifact, so neither is silently contracted" \
  ".bionic/docs/record/w2-probe-frd.md" "$GATE_ERR"
expect_contains "R6-1 CASE 9: …and asks for exactly one" "exactly one" "$GATE_ERR"
expect_status "R6-1 CASE 9: …and no roster row contracts the agent to either" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- R6-1 CASE 10: the read-then-produce ordering, the F-RD harm verbatim ----
BRIEF_TWO_PATHS_READ='Your slice: an independent read-and-duplication review.
Deliverable: read .bionic/docs/record/w2-auditor-report.md first, then produce .bionic/docs/record/w2-probe-frd2.md
Expected duration: 20 minutes'

REPO=$(make_repo r18b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_PATHS_READ" "readproducebot")"
expect_status "R6-1 CASE 10: read-X-then-produce-Y is REFUSED, not contracted to X" "2" "$GATE_ST"
expect_contains "R6-1 CASE 10: …the auditors report is named as a candidate, not taken" \
  ".bionic/docs/record/w2-auditor-report.md" "$GATE_ERR"
expect_contains "R6-1 CASE 10: …alongside the artifact the agent was actually sent to write" \
  ".bionic/docs/record/w2-probe-frd2.md" "$GATE_ERR"
expect_status "R6-1 CASE 10: …and no row is written for either" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- the refusal DIAGNOSES ambiguity, and is not the absent-deliverable message ----
expect_absent "the ambiguity refusal is not misfiled as an absent deliverable" \
  "names no deliverable" "$GATE_ERR"
expect_contains "…it says where references belong instead" "outside" "$GATE_ERR"

# ---- THE RESUBMISSION: CASE 9 with one path in the label and the reference moved out ----
BRIEF_TWO_PATHS_FIXED='You are reviewing the wave.

Read first: .bionic/docs/record/w2-critic-report.md — match its shape.
Expected artifact: .bionic/docs/record/w2-probe-frd.md
Expected duration: 30 minutes.'

REPO=$(make_repo r18c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_PATHS_FIXED" "shapebot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the resubmission — one path in the label, the reference outside it — passes" \
  "0" "$GATE_ST"
expect_status "…contracted to the artifact the brief actually asked for" \
  ".bionic/docs/record/w2-probe-frd.md" "$(roster_field "$ROW" deliverable)"
expect_status "…marked declared" "declared" "$(roster_field "$ROW" source)"

# ---- R6-4 CASE 5: a path in the labels SECOND sentence is declared, not absent ----
#
# R1 bounded the search at the end of the first sentence, so this brief — which names a
# concrete path under a canonical label — was refused for naming none, and the message
# told the author to do what they had already done. With ambiguity fatal, the window can
# safely be the whole span.
BRIEF_LATE_PATH='Your slice: assess the wave.
Expected artifact: a written report. Put it at .bionic/docs/record/w2-probe-late.md when done.
Expected duration: 20 minutes'

REPO=$(make_repo r18d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LATE_PATH" "latepathbot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "R6-4 CASE 5: a path in the labels second sentence PASSES (no first-sentence bound)" \
  "0" "$GATE_ST"
expect_status "R6-4 CASE 5: …and is the contract" \
  ".bionic/docs/record/w2-probe-late.md" "$(roster_field "$ROW" deliverable)"
expect_status "R6-4 CASE 5: …recorded declared, because a label yielded it" \
  "declared" "$(roster_field "$ROW" source)"

# ---- paired positive: one path plus surrounding prose in the span still passes ----
BRIEF_ONE_PATH_PROSE='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-prose.md — the behavior table, the evidence,
and the judgment calls, written as prose rather than a log. Keep it short.
Expected duration: ~20 minutes.'

REPO=$(make_repo r18e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_ONE_PATH_PROSE" "prosebot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "paired positive: a one-path span wrapped in prose passes" "0" "$GATE_ST"
expect_status "paired positive: …with that path as the contract" \
  ".bionic/docs/record/w99-prose.md" "$(roster_field "$ROW" deliverable)"

# ---- the same path named twice is ONE path, not an ambiguity ----
BRIEF_SAME_TWICE='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-twice.md — append to .bionic/docs/record/w99-twice.md as you go.
Expected duration: ~20 minutes.'

REPO=$(make_repo r18f yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_SAME_TWICE" "twicebot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "one path named twice is not an ambiguity" "0" "$GATE_ST"
expect_status "…and lifts once" \
  ".bionic/docs/record/w99-twice.md" "$(roster_field "$ROW" deliverable)"

# ---- a WAIVER does not excuse an ambiguous declaration (R7 judgment call) ----
#
# The waiver excuses declaring NOTHING durable. A brief that declares a label naming two
# artifacts has not waived anything — it has written a contract the machine cannot read,
# and the author is the only one who can say which path is theirs.
BRIEF_AMBIG_WAIVED='Your slice: review the wave.
Deliverable-waiver: this dispatch returns its findings in the final message.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes'

REPO=$(make_repo r18g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_AMBIG_WAIVED" "waivedambig")"
expect_status "a waiver does not excuse an ambiguous deliverable label" "2" "$GATE_ST"
expect_contains "…and the refusal still names both candidates" "a-notes.md" "$GATE_ERR"

# ---- S18b: the deliverable span ends at the next LABELLED LINE, not at the next
# registered label (wave-bionic-1.3.2, found at dispatch) ----
#
# A span used to run on until the next label THIS WALL KNOWS or a blank line, so a brief
# that put `Evidence log: <path>` on the line after `Expected artifact: <path>` had two
# paths in one deliverable span and was refused as ambiguous — for a brief whose author had
# named exactly one deliverable and one input, each on its own labelled line. `Evidence
# log:` is not in the label table and does not need to be: any line that OPENS with a short
# `<Word>:` head is a new field, and a field ends where the next one begins. Two paths on
# the deliverable label OWN line are still the ambiguity the wall exists to refuse.
BRIEF_EVIDENCE_LOG='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-evlog.md
Evidence log: .bionic/docs/record/w99-evlog.log
Expected duration: ~20 minutes.'

REPO=$(make_repo r18evlog yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_EVIDENCE_LOG" "evlogbot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S18b Evidence log: on the NEXT line does not make the deliverable ambiguous" \
  "0" "$GATE_ST"
expect_status "S18b …and the deliverable is the one on the label own line" \
  ".bionic/docs/record/w99-evlog.md" "$(roster_field "$ROW" deliverable)"

# The same brief with the two paths on ONE line is still refused: the fix bounds the span,
# it does not stop the wall counting.
BRIEF_TWO_ON_ONE_LINE='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-two.md .bionic/docs/record/w99-two.log
Expected duration: ~20 minutes.'

REPO=$(make_repo r18twoline yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_TWO_ON_ONE_LINE" "twolinebot")"
expect_status "S18b two paths on the deliverable label OWN line are still REFUSED" "2" "$GATE_ST"
expect_contains "S18b …and the refusal still names both candidates" "w99-two.log" "$GATE_ERR"

# A prose continuation line (no label head) still belongs to the span — the R6-4 window
# stays open, so a path named in a later sentence is still found.
BRIEF_PROSE_CONT='Your slice: assess the wave.
Expected artifact: a written report.
Put it at .bionic/docs/record/w99-cont.md when you are done.
Expected duration: 20 minutes'

REPO=$(make_repo r18prosecont yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CONT" "contbot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "S18b a prose continuation line is still inside the span" "0" "$GATE_ST"
expect_status "S18b …and its path is the contract" \
  ".bionic/docs/record/w99-cont.md" "$(roster_field "$ROW" deliverable)"

# ---- R6-2: every refusal message recommends a brief the walls ACCEPT ----
#
# The containment refusal handed the author `Expected artifact: .bionic/docs/record/<name>.md`
# — the literal string tests/cross-gate-agreement.test.sh §N.4 pins as REFUSED, and which
# the SIBLING refusal (the absent-deliverable wall) explicitly calls out as not a name.
# Two refusal messages in one file in direct contradiction, green the whole time because
# no test read a Fix: line. This pin reads each walls own recommendation back out of its
# stderr and DRIVES IT: an author who follows the Fix: line verbatim must not be refused.
# It never hardcodes the example, so it holds when the wording is next edited.
fix_example() {  # <stderr> -> the artifact path the Fix: block recommends
  printf '%s\n' "$1" \
    | grep -m1 -E '^[[:space:]]+Expected artifact: ' \
    | sed -e 's/^[[:space:]]*Expected artifact: //' -e 's/[[:space:]]*$//'
}

BRIEF_OUT_OF_REPO='Your slice: build it.
Expected artifact: ../../../../../../etc/hosts
Expected duration: ~15 minutes.'

for _wall in containment absent ambiguous; do
  case "$_wall" in
    containment) _b="$BRIEF_OUT_OF_REPO" ;;
    absent)      _b="$BRIEF_NOTHING" ;;
    ambiguous)   _b="$BRIEF_TWO_PATHS_SHAPE" ;;
  esac
  REPO=$(make_repo "r18h-$_wall" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$_b" "fixline-$_wall")"
  expect_status "self-consistency ($_wall): the wall refuses" "2" "$GATE_ST"
  _ex=$(fix_example "$GATE_ERR")
  expect_status "self-consistency ($_wall): its Fix: block recommends a labeled example" "0" \
    "$([ -n "$_ex" ] && echo 0 || echo 1)"
  expect_absent "self-consistency ($_wall): …carrying no slot the walls themselves refuse" \
    "<" "$_ex"
  REPO=$(make_repo "r18i-$_wall" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your slice: do the work.
Expected artifact: $_ex
Expected duration: ~15 minutes." "followed-$_wall")"
  expect_status "self-consistency ($_wall): a brief following that Fix: line verbatim PASSES" \
    "0" "$GATE_ST"
  expect_status "self-consistency ($_wall): …and the recommended path is what lands on the row" \
    "$_ex" "$(roster_field "$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)" deliverable)"
done

# ---- R6-3: a parenthetical duration lifts readable, not truncated mid-phrase ----
#
# bound_field ended a value at `)` but not `(`, so a balanced parenthetical truncated with
# a dangling open bracket — `~45 minutes (phase 1 only` — which the poker's parse_seconds
# refuses (two numbers, one matched unit pair). An unreadable duration silently exempts the
# row from overdue notification, which is A-2 read from the writer side.
BRIEF_PAREN_DURATION='Your slice: build the widget.
Expected artifact: .bionic/docs/record/w99-paren.md
Expected duration: ~45 minutes (phase 1 only), phase 2 is a separate dispatch.'

REPO=$(make_repo r18j yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PAREN_DURATION" "parenbot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "R6-3: a parenthetical duration lifts the clause before the bracket" \
  "~45 minutes" "$(roster_field "$ROW" duration)"
expect_absent "R6-3: …with no dangling open bracket for parse_seconds to choke on" \
  "(" "$(roster_field "$ROW" duration)"
expect_absent "R6-3: …and none of the parentheticals own numbers" \
  "phase" "$(roster_field "$ROW" duration)"

# ============================================================
echo "=== S19 — deliverable-kind labels are LINE-START ONLY (R8: final-audit A-1) ==="
# ============================================================
#
# record/w2-r7-audit.md A-1: R7's ambiguity wall refuses when a deliverable SPAN
# holds two paths, but each of its three refusal messages quotes the same
# concrete, liftable example — "Expected artifact: .bionic/docs/record/
# my-slice-notes.md" — and briefs in this repo quote wall text constantly. A
# brief that quotes that line in PROSE ahead of its real, later "Expected
# artifact:" line puts each label in its OWN span (one path apiece), so the
# ambiguity wall never sees two paths in one span; decl_deliverable() then
# takes the FIRST hit that yields any path and silently contracts the agent to
# a file it will never write, recorded source=declared as though a human named
# it — the one shape that routes around the ambiguity wall entirely.
#
# THE FIX: the same mechanism `deliverable-waiver` already uses (S-1) — a
# deliverable-kind label counts only at LINE START. A mid-line occurrence is
# prose, not a declaration, and must not even register as a hit.

# ---- the audit's own P2 specimen, verbatim ----
BRIEF_P2_BAIT='Your slice: build the widget.
The wall told me to write: Expected artifact: .bionic/docs/record/my-slice-notes.md
Expected artifact: .bionic/docs/record/w2-probe-real.md
Expected duration: 20 minutes'

REPO=$(make_repo r19a yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_P2_BAIT" "p2bot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "A-1: a quoted wall-message bait ahead of the real label passes" \
  "0" "$GATE_ST"
expect_status "A-1: …contracted to the REAL line-start label's path" \
  ".bionic/docs/record/w2-probe-real.md" "$(roster_field "$ROW" deliverable)"
expect_absent "A-1: …never to the mid-line quoted bait" \
  "my-slice-notes.md" "$(roster_field "$ROW" deliverable)"
expect_status "A-1: …still recorded declared" "declared" "$(roster_field "$ROW" source)"

# ---- CONTROL: the bare `deliverable` label, same shape — proves the pin
# generalizes across the canonical variants, not just `expected artifact` ----
BRIEF_P2_BARE='Your slice: review the wave.
It said: Deliverable: .bionic/docs/record/bait-bare.md is the example.
Deliverable: .bionic/docs/record/w2-real-bare.md
Expected duration: 20 minutes'

REPO=$(make_repo r19b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_P2_BARE" "p2barebot")"
ROW=$(roster_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "A-1 control (bare label): passes" "0" "$GATE_ST"
expect_status "A-1 control (bare label): contracted to the real line-start path" \
  ".bionic/docs/record/w2-real-bare.md" "$(roster_field "$ROW" deliverable)"
expect_absent "A-1 control (bare label): never to the mid-line bait" \
  "bait-bare.md" "$(roster_field "$ROW" deliverable)"

# ============================================================
echo "=== S20 — the agent-context channel: walls travel, the LEDGER does not (T6, D1) ==="
# ============================================================
#
# hooks/agent-context-guard.sh registers this gate a second time, through
# settings.json, so a dispatch made from INSIDE a teammate or subagent context meets
# the same walls a main-thread one does — the skill channel is dead there
# (.bionic/docs/record/session-20260815-landing-supervision/t1-probe-report.md §3).
# What must not travel with the walls is the journal: the roster is the depth-one
# ledger of what the ORCHESTRATOR launched, and rows for a teammate's own subagents
# are contracts nobody confirms, lands or checks.
#
# The guard is the only writer of BIONIC_HOOK_CHANNEL and this is its only reader;
# tests/cross-gate-agreement.test.sh §L.6 pins the pair across the two files.
#
# BOTH DIRECTIONS, because a suppression that suppressed the WALL as well would look
# identical from the roster's side — and would be the R2 hole reopening in the act of
# closing it.
REPO=$(make_repo r20 yes)
write_attestation "$REPO" "$SID_A"
S20_SAVED_ENV="$GATE_ENV"
GATE_ENV="$GATE_ENV BIONIC_HOOK_CHANNEL=agent-context"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a contract-complete dispatch in an agent context passes" "0" "$GATE_ST"
expect_status "…and writes NO roster row (the ledger stays at depth one)" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# The wall itself is untouched by the channel — a deliverable-less brief is refused
# at depth, which is the entire point of the second registration.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Canonical-sdlc Step 4. Do the thing.
Exit condition: the suite is green.')"
expect_status "a deliverable-less dispatch in an agent context is still REFUSED" "2" "$GATE_ST"
expect_contains "…by the absent-deliverable wall, in its own words" \
  "BLOCKED: this dispatch brief names no deliverable" "$GATE_ERR"
GATE_ENV="$S20_SAVED_ENV"

# The paired positive: the same dispatch with no channel marker — the main thread, as
# the skill channel delivers it — still journals its row.
REPO=$(make_repo r20b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "the same dispatch on the main thread passes" "0" "$GATE_ST"
expect_status "…and DOES journal exactly one row" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# An unrelated value in the variable is not the channel: only the guard's exact
# spelling suppresses, so a stray export cannot silently stop the ledger.
S20_SAVED_ENV="$GATE_ENV"
GATE_ENV="$GATE_ENV BIONIC_HOOK_CHANNEL=something-else"
REPO=$(make_repo r20c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "an unrecognised channel value journals normally" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
GATE_ENV="$S20_SAVED_ENV"


# ============================================================
echo ""
echo "=== S21: the arming wall — a dispatch needs a live Patrol (epic-17 W5 4/4, AC-6) ==="
# ============================================================
#
# WHAT THIS WALL IS FOR. Every other wall on this path asks whether the dispatch is
# well-formed or the environment is sound. This one asks whether anything is WATCHING the
# fleet the dispatch is about to join. The Patrol is the run's one clock; when it is not
# armed, or was armed and has silently stopped firing, a launched agent can die quiet and
# nothing notices until a human wanders back. The stamp
# (.bionic/tmp/patrol-<sid>.state, written by hooks/session-poker.sh's `arm` and by every
# `tick` before it decides) is the liveness signal, and its AGE is the whole test:
# absent = never armed, older than 2x the poker-interval = armed-but-dead.
#
# SCOPE IS THE HOOK'S EXISTING ACTIVE-RUN PREDICATE, deliberately — no second definition of
# "active" (design ledger D-C mechanic 4). Outside a wave this gate has already exited long
# before reaching here, which the no-wave arm below drives directly.
#
# THE INTERVAL IS THE POKER'S OWN, read by invoking the sibling `interval` verb rather than
# by re-implementing the config knob. An interval this gate cannot read is an AMBIGUITY, not
# a finding, and takes §7's start-side direction: warn and pass.

s21_stamp_path() { printf '%s/.bionic/tmp/patrol-%s.state' "$1" "$2"; }

s21_backdate() {  # <file> <seconds ago>
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

# ---------- absent stamp: never armed ----------
REPO=$(make_repo r21a yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "an ABSENT Patrol stamp refuses the dispatch" "2" "$GATE_ST"
expect_contains "…in the checkpoint house style, not an alarm word" "patrol checkpoint" "$GATE_ERR"
expect_contains "…naming the state it found" "never armed" "$GATE_ERR"
expect_contains "…and naming the exact re-arm command, resolved" "session-poker.sh arm" "$GATE_ERR"
expect_contains "…and the CronCreate half, so the stamp is not re-armed into a dead clock" \
  "CronCreate" "$GATE_ERR"
expect_contains "…and says what to do after" "retry the dispatch" "$GATE_ERR"
expect_status "…and journals nothing: a refused dispatch is not a launch" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---------- stale stamp: armed, then died ----------
REPO=$(make_repo r21b yes)
write_attestation "$REPO" "$SID_A"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000   # > 2 x the 1800s default
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a STALE Patrol stamp refuses the dispatch" "2" "$GATE_ST"
expect_contains "…and names the armed-but-dead state, not the never-armed one" \
  "stopped firing" "$GATE_ERR"
expect_absent "…so the two arms cannot be confused in a transcript" "never armed" "$GATE_ERR"

# ---------- fresh stamp: passes, silently ----------
REPO=$(make_repo r21c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a FRESH Patrol stamp lets the dispatch through" "0" "$GATE_ST"
expect_absent "…and the wall says nothing on the pass path" "patrol checkpoint" "$GATE_ERR"
expect_status "…and the launch is journalled as usual" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---------- a stamp for ANOTHER session is not this session's liveness ----------
REPO=$(make_repo r21d yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a stamp keyed to a DIFFERENT session does not arm this one" "2" "$GATE_ST"
expect_contains "…and reads as never-armed here" "never armed" "$GATE_ERR"

# ---------- the wall rides the active-run predicate and nothing else ----------
REPO=$(make_repo r21e no)
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "with NO wave active an unarmed Patrol is not this gate's business" "0" "$GATE_ST"
expect_empty "…and the gate is silent, as it is for every other check outside a wave" "$GATE_ERR"

# ---------- the threshold is 2x the poker-interval, and follows the config knob ----------
REPO=$(make_repo r21f yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 1m\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 100     # inside 2 x 60s
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a stamp inside 2x the CONFIGURED interval passes (100s of 120s)" "0" "$GATE_ST"

REPO=$(make_repo r21g yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 1m\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 200     # past 2 x 60s
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "…and one past it refuses, on the same fixture the default would have passed" \
  "2" "$GATE_ST"
expect_contains "…naming the interval it measured against" "120s" "$GATE_ERR"

# ---------- a symlinked stamp is refused, never followed ----------
REPO=$(make_repo r21h yes)
write_attestation "$REPO" "$SID_A"
printf 'patrol-stamp/v1|at=2099-01-01T00:00:00Z|session=%s|verb=arm\n' "$SID_A" \
  > "$SANDBOX/planted-stamp"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
ln -s "$SANDBOX/planted-stamp" "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a SYMLINKED stamp cannot open this wall" "2" "$GATE_ST"

# ---------- an unreadable interval falls back to the poker's own default ----------
#
# CRITIC C-2 (W5). This used to skip BOTH arms of the wall and pass. `poker-interval:` is
# machine-local and agent-writable, so one line in a config file disabled an entire wall —
# in a file whose own §8 says a hostile repo may CLOSE a wall and must never be able to
# OPEN one. And the line that reaches it is the likeliest typo there is: a BARE NUMBER
# (`poker-interval: 30`) makes the poker refuse, where `30m` and `30 minutes` both parse.
#
# The interval is a THRESHOLD, not a precondition, and only one of the two arms needs it.
# So: the stamp-existence arm runs unconditionally (an absent stamp is absent at every
# interval), and the staleness arm falls back to the poker's own POKER_INTERVAL_DEFAULT —
# read from the poker, never retyped here, via its read-only `interval-default` verb. The
# dispatch still passes, because the operator's config really is unreadable and that is an
# ambiguity; what it no longer does is pass with nothing checked.
REPO=$(make_repo r21i yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: whenever\n' > "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "an interval the poker refuses to read does not refuse the dispatch" "0" "$GATE_ST"
expect_contains "…but says so, rather than passing a wall off as satisfied" \
  "Patrol interval" "$GATE_ERR"
expect_contains "…and says the wall RAN, at the default, rather than that it did not run" \
  "wall ran at default" "$GATE_ERR"

# r21j — THE MISSING COMBINATION, and the one that made C-2 a hole rather than a wording
# problem: the same unreadable interval with NO stamp at all. r21i above drives a FRESH
# stamp, so it can only ever show pass-stays-pass.
REPO=$(make_repo r21j yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 30\n' > "$REPO/.bionic/config.yaml"   # the bare-number typo: rc=2
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "an unreadable interval does NOT open the wall for an unarmed session" "2" "$GATE_ST"
expect_contains "…the never-armed arm still fires" "never armed" "$GATE_ERR"

# r21k — and the staleness arm runs too, measured against the fallback default.
REPO=$(make_repo r21k yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 30\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 4000   # > 2 x the 1800s default
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a stale stamp under an unreadable interval refuses at the DEFAULT threshold" \
  "2" "$GATE_ST"
expect_contains "…naming the armed-but-dead state" "stopped firing" "$GATE_ERR"

# r21l — the fallback is the POKER'S constant, not a number retyped in the gate. Proven
# by MUTATION: change POKER_INTERVAL_DEFAULT on a doctored copy of the poker tree and the
# threshold the gate measures against has to move with it. A gate carrying its own 1800
# would pass this fixture unchanged.
# THE DOCTORED TREE HAS THE SHAPE THE PLUGIN SHIPS — `hooks/` beside `scripts/lib`
# (bionic 1.4.0). The poker loads its library through the shared loader idiom, whose first
# candidate is `<dirname $0>/../scripts/lib`; a copy dropped into a bare temp directory
# finds none and fails open, and this mutation would then measure a poker that never ran.
# The library is LINKED rather than duplicated, so the copy under test reads exactly the
# functions the shipped script reads.
S21_TREE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/s21-poker-tree.XXXXXX")
S21_TREE="$S21_TREE_ROOT/hooks"
mkdir -p "$S21_TREE" "$S21_TREE_ROOT/scripts"
ln -s "$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)" "$S21_TREE_ROOT/scripts/lib"
cp "$GATE" "$S21_TREE/dispatch-preflight.sh"
sed 's/^POKER_INTERVAL_DEFAULT="30m"$/POKER_INTERVAL_DEFAULT="10s"/' \
  "${BIONIC_HOOKS_DIR}/session-poker.sh" > "$S21_TREE/session-poker.sh"
if grep -qF 'POKER_INTERVAL_DEFAULT="10s"' "$S21_TREE/session-poker.sh"; then
  ok "r21l meta: the doctored poker default landed (the sed anchor still matches)"
else
  no "r21l meta: the doctored poker default did NOT land — the arm below proves nothing"
fi
REPO=$(make_repo r21l yes)
write_attestation "$REPO" "$SID_A"
printf 'poker-interval: 30\n' > "$REPO/.bionic/config.yaml"
s21_backdate "$(s21_stamp_path "$REPO" "$SID_A")" 100   # fresh at 1800s, ancient at 10s
S21_SAVED_GATE="$GATE"; GATE="$S21_TREE/dispatch-preflight.sh"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r21l the fallback threshold moves with the POKER's constant, not the gate's" \
  "2" "$GATE_ST"
expect_contains "…and measures against 2x the doctored default" "20s" "$GATE_ERR"
GATE="$S21_SAVED_GATE"

# r21m — THE POKER ITSELF UNREACHABLE. `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/` is the
# gate's second lane for its siblings, and after the Step-9 legacy teardown that directory
# no longer holds hooks on any machine — so on a plugin-only install the only lane that
# resolves is the sibling one. If BOTH miss, there is no interval and no default to be had,
# and the honest degradation is per-arm: the existence half needs no threshold and still
# refuses, and the staleness half says out loud that it did not run. What must never happen
# is the whole wall going quiet, which is what a teardown would otherwise have bought.
S21_LONE=$(mktemp -d "${TMPDIR:-/tmp}/s21-lone-gate.XXXXXX")
cp "$GATE" "$S21_LONE/dispatch-preflight.sh"
S21_EMPTY_CONFIG=$(mktemp -d "${TMPDIR:-/tmp}/s21-empty-config.XXXXXX")
REPO=$(make_repo r21m yes)
write_attestation "$REPO" "$SID_A"
rm -f "$(s21_stamp_path "$REPO" "$SID_A")"
S21_SAVED_GATE="$GATE"; S21_SAVED_CONFIG="$GATE_CONFIG_DIR"
GATE="$S21_LONE/dispatch-preflight.sh"; GATE_CONFIG_DIR="$S21_EMPTY_CONFIG"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r21m with NO poker on either lane, the unarmed session is still refused" \
  "2" "$GATE_ST"
expect_contains "…by the existence arm, which never needed the interval" "never armed" "$GATE_ERR"

# …and the staleness half, which genuinely cannot run, says so instead of passing quietly.
REPO=$(make_repo r21n yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r21n …and a stamped session passes, the staleness half unmeasured" "0" "$GATE_ST"
expect_contains "…saying which half did not run, and why" \
  "staleness half" "$GATE_ERR"
GATE="$S21_SAVED_GATE"; GATE_CONFIG_DIR="$S21_SAVED_CONFIG"

echo ""
echo "----------------------------------------"
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
