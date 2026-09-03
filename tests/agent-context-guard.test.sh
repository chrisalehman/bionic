#!/bin/bash
# Tests for hooks/agent-context-guard.sh — THE SETTINGS-CHANNEL PARTITION GUARD
# (session-20260815-landing-supervision, T6; design D1, plan AC-8).
#
# The guard is the whole of the settings-channel registration's correctness. Two
# walls are registered a second time through settings.json — where the skill
# channel is measurably dead (t1-probe-report.md §3) — and that channel is alive
# on MAIN-THREAD events too, and in EVERY session on the machine including the
# unarmed ones. So the guard has to answer one question and answer it four ways:
#
#     agent_id present  x  roster-<sid>.state present   ->  run the wall
#     anything else                                     ->  exit 0, in silence
#
# HERMETIC. Every payload is crafted and piped into the guard; nothing here
# dispatches a real Agent tool call, reads ~/.claude, or depends on a live wave.
# Repos are throwaway git inits under a mktemp'd sandbox.
#
# FIXTURE FIDELITY (declared, per .claude memory fixtures-can-pin-away-the-test):
#   * PreToolUse payload envelope — the shape tests/dispatch-preflight.test.sh
#     already pins from the CLI 2.1.220 verbatim captures, plus the ONE field
#     this guard turns on: a top-level `agent_id`. That field's presence in an
#     agent context and absence on the main thread is measured, not assumed —
#     t1-probe-report.md §3 (`ctx=.payload.agent_id // "MAIN"`), CLI 2.1.233.
#   * agent id VALUE — the transcript form measured there for a named teammate
#     (`a<name>-<16 hex>`). Its shape is never parsed by the guard; only its
#     presence is.
#   * attestation record, plan text, session ids — SYNTHESIZED, same schema the
#     sibling suites write.
#
# THE POSITIVE CONTROL IS NOT OPTIONAL HERE. Three of the four cells assert
# SILENCE, and a guard that had simply broken would pass all three. So every
# silent cell is paired with the same payload driven STRAIGHT INTO the wall,
# which must refuse it — proving the payload is refusable and the silence is the
# guard's decision rather than a dud fixture.
#
# Usage: bash tests/agent-context-guard.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HOOKS_DIR="${BIONIC_HOOKS_DIR}"
GUARD="$HOOKS_DIR/agent-context-guard.sh"
DISPATCH_WALL="$HOOKS_DIR/dispatch-preflight.sh"
ARTIFACT_WALL="$HOOKS_DIR/canonical-sdlc-governing-skill.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/agent-context-guard-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }

SID="9d1c0e64-6b21-4f7a-9d3e-2a7c5f81b0aa"
AGENT_ID="at6mate-fdaa80c4b3cb703f"

# ---------- fixtures ----------

# make_repo <name> -> repo path, git-initialised, one active wave on disk
make_repo() {
  local repo="$SANDBOX/$1/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
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
  mkdir -p "$repo/.bionic/tmp"
  {
    printf '# bionic environment attestation — machine-local, safe to delete\n'
    printf 'version=1\n'
    printf 'kind=preflight-attestation\n'
    printf 'session_id=%s\n' "$SID"
    printf 'written_at=1785790000\n'
    printf 'repo=%s\n' "$repo"
  } > "$repo/.bionic/tmp/preflight-$SID.state"
  chmod 600 "$repo/.bionic/tmp/preflight-$SID.state"
  # A LIVE WAVE HAS A LIVE PATROL (epic-17 W5 4/4). hooks/dispatch-preflight.sh refuses any
  # dispatch — nested ones included, which is the whole subject of G5 — whose session has no
  # fresh Patrol stamp. Armed here so the guard's own walls are what these cases measure,
  # not the arming wall in front of them (tests/dispatch-preflight.test.sh S21 owns that).
  printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" > "$repo/.bionic/tmp/patrol-$SID.state"
  chmod 600 "$repo/.bionic/tmp/patrol-$SID.state"
  printf '%s' "$repo"
}

arm_roster() {  # <repo> — the fact that proves this session is armed
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$1/.bionic/tmp/roster-$SID.state"
  chmod 600 "$1/.bionic/tmp/roster-$SID.state"
}

disarm_roster() { rm -f "$1/.bionic/tmp/roster-$SID.state"; }

roster_rows() {  # grep -c prints 0 AND exits 1 on no match, so never `|| echo 0`
  local n
  n=$(grep -cv '^#' "$1/.bionic/tmp/roster-$SID.state" 2>/dev/null)
  printf '%s' "${n:-0}"
}

# A brief that the absent-deliverable wall refuses: no deliverable, no waiver.
BRIEF_BROKEN='Canonical-sdlc Step 4. Your slice: implement the widget behind the seam.
Exit condition: the paired suite is green.'

# A brief every wall accepts — used for the LEDGER cases, where the point is what
# gets journalled on a dispatch that passes.
BRIEF_OK='Canonical-sdlc Step 4, slice 4/9 of epic-99 wave-01; build · audited · wave.
Your slice: implement the widget behind the existing seam.
Expected artifact: .bionic/docs/record/w99-widget.txt
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-widget.progress, cadence ~5m'

# mk_agent_payload <cwd> <with-agent-id:yes|no> [prompt] [session_id]
mk_agent_payload() {
  local sid="${4:-$SID}"
  jq -n --arg s "$sid" --arg c "$1" --arg a "$AGENT_ID" --arg p "${3:-$BRIEF_BROKEN}" \
    --argjson withid "$([ "$2" = yes ] && echo true || echo false)" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a nested dispatch", subagent_type:"implementor",
                  prompt:$p, run_in_background:true, name:"t6nested"},
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}
     + (if $withid then {agent_id:$a} else {} end)'
}

# mk_write_payload <cwd> <file> <with-agent-id:yes|no> [content]
mk_write_payload() {
  jq -n --arg s "$SID" --arg c "$1" --arg f "$2" --arg a "$AGENT_ID" \
    --arg body "${4:-# a plan with no frontmatter at all}" \
    --argjson withid "$([ "$3" = yes ] && echo true || echo false)" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Write",
      tool_input:{file_path:$f, content:$body},
      tool_use_id:"toolu_01writeplan"}
     + (if $withid then {agent_id:$a} else {} end)'
}

# The environment every run gets: a sandboxed config dir carrying this session's
# transcript, so the wall's roster pruning never consults the operator's ~/.claude
# and never decides a fixture roster is stale.
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude/projects/-sandbox"
: > "$FAKE_HOME/.claude/projects/-sandbox/$SID.jsonl"

OUT=""; ERR=""; ST=0
# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2:
# a plain /clear re-keys both together). Since bionic 1.4.0 the guard takes its session
# id from lib/session.sh, where the env value is primary and the payload is a witness,
# so a driver that left the runner's own CLAUDE_CODE_SESSION_ID in the environment
# would be driving a divergence rather than a session — and every roster filename below
# would be built from the wrong key.
run_guard() {  # <payload> <target...>
  local payload="$1"; shift
  local _sid; _sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
          CLAUDE_CODE_SESSION_ID="$_sid" \
          ANTHROPIC_API_KEY=sk-fixture-marker bash "$GUARD" "$@" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

run_wall() {  # <payload> <wall> — the positive control: straight in, no guard
  local payload="$1" wall="$2"
  local _sid; _sid=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  OUT=$(printf '%s' "$payload" | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
          CLAUDE_CODE_SESSION_ID="$_sid" \
          ANTHROPIC_API_KEY=sk-fixture-marker bash "$wall" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# ============================================================
echo "=== G0 — the guard exists and is syntactically sound ==="
# ============================================================
# (file-exists fixture check removed epic-18 W3 4/6: no production subject -- see ledger-agent-context-guard.md)
if bash -n "$GUARD" 2>"$SANDBOX/.syn"; then ok "the guard parses (bash -n)"; else
  no "the guard parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi

# ============================================================
echo "=== G1 — the DISPATCH wall's four cells (agent_id x roster) ==="
# ============================================================
REPO_D=$(make_repo dispatch)

# --- cell (1,1): an agent context in an armed session — THE ONE THAT FIRES.
arm_roster "$REPO_D"
run_guard "$(mk_agent_payload "$REPO_D" yes)" "$DISPATCH_WALL"
expect_status "G1.1 agent_id + roster: the dispatch wall runs and REFUSES a deliverable-less brief" 2 "$ST"

# --- cell (0,1): the MAIN THREAD of the same armed session. The settings channel
# delivers this event too (t1 §3, MAIN rows), and the skill channel already
# covers it — firing here would double-refuse and double-journal one dispatch.
run_guard "$(mk_agent_payload "$REPO_D" no)" "$DISPATCH_WALL"
expect_status "G1.2 no agent_id (main thread), roster present: silent pass" 0 "$ST"
expect_empty "G1.2 …and says nothing at all" "$ERR$OUT"
run_wall "$(mk_agent_payload "$REPO_D" no)" "$DISPATCH_WALL"
expect_status "G1.2 positive control: that same payload IS refused by the wall itself" 2 "$ST"

# --- cell (1,0): an agent context in an UNARMED session — the machine-wide case.
disarm_roster "$REPO_D"
run_guard "$(mk_agent_payload "$REPO_D" yes)" "$DISPATCH_WALL"
expect_status "G1.3 agent_id, no roster (unarmed session): silent pass" 0 "$ST"
expect_empty "G1.3 …and says nothing at all" "$ERR$OUT"
run_wall "$(mk_agent_payload "$REPO_D" yes)" "$DISPATCH_WALL"
expect_status "G1.3 positive control: the wall itself would have refused it" 2 "$ST"

# --- cell (0,0): an ordinary unarmed session's main thread. Every Agent dispatch
# on this machine takes this path, and it must cost one stat and no words.
run_guard "$(mk_agent_payload "$REPO_D" no)" "$DISPATCH_WALL"
expect_status "G1.4 no agent_id, no roster: silent pass" 0 "$ST"
expect_empty "G1.4 …and says nothing at all" "$ERR$OUT"

# ============================================================
echo "=== G2 — the ARTIFACT wall's four cells (agent_id x roster) ==="
# ============================================================
REPO_A=$(make_repo artifact)
PLAN_TARGET="$REPO_A/.bionic/docs/plans/epic-99-test/new.plan.md"

arm_roster "$REPO_A"
run_guard "$(mk_write_payload "$REPO_A" "$PLAN_TARGET" yes)" "$ARTIFACT_WALL"
expect_status "G2.1 agent_id + roster: the artifact wall runs and REFUSES a frontmatter-less plan" 2 "$ST"

run_guard "$(mk_write_payload "$REPO_A" "$PLAN_TARGET" no)" "$ARTIFACT_WALL"
expect_status "G2.2 no agent_id (main thread), roster present: silent pass" 0 "$ST"
expect_empty "G2.2 …and says nothing at all" "$ERR$OUT"
run_wall "$(mk_write_payload "$REPO_A" "$PLAN_TARGET" no)" "$ARTIFACT_WALL"
expect_status "G2.2 positive control: that same payload IS refused by the wall itself" 2 "$ST"

disarm_roster "$REPO_A"
run_guard "$(mk_write_payload "$REPO_A" "$PLAN_TARGET" yes)" "$ARTIFACT_WALL"
expect_status "G2.3 agent_id, no roster (unarmed session): silent pass" 0 "$ST"
expect_empty "G2.3 …and says nothing at all" "$ERR$OUT"
run_wall "$(mk_write_payload "$REPO_A" "$PLAN_TARGET" yes)" "$ARTIFACT_WALL"
expect_status "G2.3 positive control: the wall itself would have refused it" 2 "$ST"

run_guard "$(mk_write_payload "$REPO_A" "$PLAN_TARGET" no)" "$ARTIFACT_WALL"
expect_status "G2.4 no agent_id, no roster: silent pass" 0 "$ST"
expect_empty "G2.4 …and says nothing at all" "$ERR$OUT"

# ============================================================
echo "=== G3 — the roster is read PER SESSION, under the payload's own root ==="
# ============================================================
#
# A roster belonging to some OTHER session in the same repo is not this session's
# arming fact — the filename is the key, exactly as the attestation's is.
REPO_S=$(make_repo session)
printf '# roster for a different session\n' > "$REPO_S/.bionic/tmp/roster-1f4a7c02-3bd9-4e15-8a66-90c1de77b204.state"
run_guard "$(mk_agent_payload "$REPO_S" yes)" "$DISPATCH_WALL"
expect_status "G3.1 a FOREIGN session's roster does not arm this one" 0 "$ST"
expect_empty "G3.1 …silently" "$ERR$OUT"
arm_roster "$REPO_S"
run_guard "$(mk_agent_payload "$REPO_S" yes)" "$DISPATCH_WALL"
expect_status "G3.2 …and this session's own roster does" 2 "$ST"

# A session key shaped like a path would leave the guarded directory entirely —
# the same belt hooks/dispatch-preflight.sh wears, taken in the same direction.
run_guard "$(mk_agent_payload "$REPO_S" yes "$BRIEF_BROKEN" "../../etc/passwd")" "$DISPATCH_WALL"
expect_status "G3.3 a session key that is not shaped like one: silent pass" 0 "$ST"
expect_empty "G3.3 …silently" "$ERR$OUT"

# ============================================================
echo "=== G4 — ambiguity and misconfiguration fail OPEN, in silence ==="
# ============================================================
run_guard "$(mk_agent_payload "$REPO_S" yes)"
expect_status "G4.1 no target argument: pass" 0 "$ST"
expect_empty "G4.1 …silently" "$ERR$OUT"

run_guard "$(mk_agent_payload "$REPO_S" yes)" "$SANDBOX/no-such-hook.sh"
expect_status "G4.2 a target that is not on disk: pass" 0 "$ST"
expect_empty "G4.2 …silently" "$ERR$OUT"

run_guard 'not json at all' "$DISPATCH_WALL"
expect_status "G4.3 an unparseable payload: pass" 0 "$ST"
expect_empty "G4.3 …silently" "$ERR$OUT"

NOCWD=$(jq -n --arg s "$SID" --arg a "$AGENT_ID" \
  '{session_id:$s, agent_id:$a, hook_event_name:"PreToolUse", tool_name:"Agent",
    tool_input:{prompt:"no cwd here"}}')
run_guard "$NOCWD" "$DISPATCH_WALL"
expect_status "G4.4 a payload with no cwd: pass" 0 "$ST"
expect_empty "G4.4 …silently" "$ERR$OUT"

# ============================================================
echo "=== G5 — the LEDGER stops at depth one (D1: refused-or-passed, never rostered) ==="
# ============================================================
#
# The dispatch wall is a wall AND the roster's writer. Registering it in agent
# contexts must not move the writer: a nested dispatch is walled, and the roster
# stays the depth-one ledger of what the ORCHESTRATOR launched. Otherwise a
# teammate's own subagents accrue rows nothing ever confirms or lands.
REPO_L=$(make_repo ledger)
arm_roster "$REPO_L"
BEFORE=$(roster_rows "$REPO_L")
run_guard "$(mk_agent_payload "$REPO_L" yes "$BRIEF_OK")" "$DISPATCH_WALL"
expect_status "G5.1 a contract-complete NESTED dispatch passes the wall" 0 "$ST"
expect_eq "G5.2 …and appends NO roster row (the ledger stays at depth one)" \
  "$BEFORE" "$(roster_rows "$REPO_L")"

# The paired positive: the same brief on the MAIN thread — no guard in front of
# it, which is how the skill channel delivers it — still journals its row.
run_wall "$(mk_agent_payload "$REPO_L" no "$BRIEF_OK")" "$DISPATCH_WALL"
expect_status "G5.3 positive control: the same dispatch on the main thread passes" 0 "$ST"
expect_eq "G5.3 …and DOES journal exactly one row" \
  "$((BEFORE + 1))" "$(roster_rows "$REPO_L")"

# ============================================================
echo "=== G6 — one guard, one root: the resolver is the shared copy ==="
# ============================================================
#
# The guard stats a path under the project root, so it has to land on the SAME root
# the dispatch wall wrote the roster into. Until bionic 1.4.0 that was arranged by
# carrying a byte-identical copy of `resolve_project_root` — one of eight, held
# together by an agreement suite. The copies are gone: there is one answer now,
# lib/root.sh's `project_root`, and what this section pins locally is that the guard
# ASKS for it and that the answer maps a WORKTREE onto its main repository, which is
# the property the family existed for.
expect_eq "G6.1 the guard has no private root resolver left" "" \
  "$(awk '/^resolve_project_root\(\)/,/^\}/' "$GUARD")"
expect_eq "G6.2 …and asks the library instead" "yes" \
  "$(grep -q 'project_root "\$CWD"' "$GUARD" && echo yes || echo no)"
GUARD_ROOT_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/root.sh"
[ -r "$GUARD_ROOT_LIB" ] || GUARD_ROOT_LIB="${BIONIC_HOOKS_DIR}/../scripts/lib/root.sh"
WT_MAIN="$SANDBOX/wt/repo"
mkdir -p "$WT_MAIN"
git -C "$WT_MAIN" init -q 2>/dev/null
git -C "$WT_MAIN" config user.email t@example.com
git -C "$WT_MAIN" config user.name "T"
echo seed > "$WT_MAIN/README.md"
git -C "$WT_MAIN" add README.md
git -C "$WT_MAIN" commit -qm seed 2>/dev/null
WT_LINK="$SANDBOX/wt/linked"
git -C "$WT_MAIN" worktree add -q -b t6-wt "$WT_LINK" >/dev/null 2>&1
# (fixture sanity check removed epic-18 W3 4/6: no production subject -- see ledger-agent-context-guard.md)
mkdir -p "$WT_MAIN/.bionic"
expect_eq "G6.3 the guard roots a worktree path at the MAIN repository" \
  "$(cd "$WT_MAIN" && pwd -P)" \
  "$( ( . "$GUARD_ROOT_LIB"; cd "$WT_LINK" && project_root "$WT_LINK" ) 2>/dev/null)"

# ============================================================
echo "=== G7 — the mutation loop: each half of the partition is load-bearing ==="
# ============================================================
#
# Three of the four cells assert silence, and silence is what a broken guard also
# produces — the §A2 discipline applied here. So each half of the predicate is
# DELETED from a copy of the shipped script, and the copy must answer differently
# on the one cell that half owns. A mutation that changes nothing means the
# assertion above was never testing anything.
MUTANT=""
# A MUTANT NEEDS THE LIBRARY BESIDE IT (bionic 1.4.0). The guard loads root.sh and
# session.sh through the shared loader idiom, whose first candidate is
# `$(dirname "$0")/../scripts/lib`; a copy alone in the sandbox root finds nothing
# there, fails OPEN, and every mutation arm below would be measuring the step-aside
# instead of the deleted predicate. So the mutants live in a tree shaped like the
# shipped one: hooks/ beside scripts/lib/.
MUTANT_TREE="$SANDBOX/mutants"
mkdir -p "$MUTANT_TREE/hooks" "$MUTANT_TREE/scripts/lib"
for _acg_lib in root.sh session.sh; do
  cp "${BIONIC_HOOKS_DIR}/../payload/scripts/lib/$_acg_lib" "$MUTANT_TREE/scripts/lib/$_acg_lib" 2>/dev/null \
    || cp "${BIONIC_HOOKS_DIR}/../scripts/lib/$_acg_lib" "$MUTANT_TREE/scripts/lib/$_acg_lib" 2>/dev/null || true
done

mutate_guard() {  # <name> <sed expression> -> sets MUTANT. Never echoes the path: the
                  # assertions below print, and a captured stdout would swallow them.
  MUTANT="$MUTANT_TREE/hooks/mutant-$1.sh"
  sed "$2" "$GUARD" > "$MUTANT"
  if cmp -s "$GUARD" "$MUTANT"; then
    no "the $1 mutation applies at all" "the mutation target matched nothing — this proof is vacuous"
  else
    ok "the $1 mutation applies at all"
  fi
}

run_mutant() {  # <mutant> <payload> <target>
  local _sid; _sid=$(printf '%s' "$2" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  OUT=$(printf '%s' "$2" | env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" \
          CLAUDE_CODE_SESSION_ID="$_sid" \
          ANTHROPIC_API_KEY=sk-fixture-marker bash "$1" "$3" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

REPO_M=$(make_repo mutant)
arm_roster "$REPO_M"

# Half 1 — the agent-context test. Without it the settings channel fires on the MAIN
# THREAD too, where the skill channel already runs the same wall: one dispatch, two
# refusals, and (for a passing one) two roster rows.
mutate_guard noctx "/^\[ -n \"\$(_jq '\.agent_id')\" \] || exit 0$/d"
run_mutant "$MUTANT" "$(mk_agent_payload "$REPO_M" no)" "$DISPATCH_WALL"
expect_status "G7.1 without the agent_id test the guard fires on the MAIN thread (double-fire)" 2 "$ST"
run_guard "$(mk_agent_payload "$REPO_M" no)" "$DISPATCH_WALL"
expect_status "G7.1 …and the shipped guard does not" 0 "$ST"

# Half 2 — the arming test. Without it every agent context on this machine, in every
# session that never invoked the skill, meets sdlc walls again — the exact scoping
# the walls were moved to the skill channel to get.
mutate_guard noarm '/^\[ ! -L "\$ROSTER_FILE" \] && \[ -f "\$ROSTER_FILE" \] || exit 0$/d'
disarm_roster "$REPO_M"
run_mutant "$MUTANT" "$(mk_agent_payload "$REPO_M" yes)" "$DISPATCH_WALL"
expect_status "G7.2 without the roster test the guard fires in an UNARMED session" 2 "$ST"
run_guard "$(mk_agent_payload "$REPO_M" yes)" "$DISPATCH_WALL"
expect_status "G7.2 …and the shipped guard does not" 0 "$ST"

# ============================================================
echo ""
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
