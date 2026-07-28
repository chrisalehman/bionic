#!/bin/bash
# Tests for canonical-sdlc-evidence-gate.sh
#
# Strategy: override HOME to a temp dir so the hook reads plan files from
# a test-controlled ~/.claude/plans/ and never touches the real user's
# plans directory.
#
# Usage: bash hooks/canonical-sdlc-evidence-gate.test.sh

set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/canonical-sdlc-evidence-gate.sh"
PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

cleanup_dirs=()
cleanup() {
  for d in "${cleanup_dirs[@]}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# Incident 0001: the audit file lives under $HOME, never in the project tree.
# Every runner in this suite already pins HOME to a make_home sandbox, so the
# relocated writes stay off the developer's real ~/.claude/logs. The sandbox
# HOME is always a SIBLING of the make_project fixtures (both are bare
# mktemp -d), never a parent — Section 21a's "nothing under the project tree"
# assertion depends on that.
# Slug must match hooks/canonical-sdlc-evidence-gate.sh audit_path() byte for byte.
slug_for() { printf '%s-%s' "$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')" \
                            "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
# $1 = sandbox HOME, $2 = the audit_root the hook resolved (the plan's project).
audit_file_for() { printf '%s/.claude/logs/%s/sdlc-audit.md' "$1" "$(slug_for "$2")"; }

# Creates an isolated $HOME-equivalent with an empty ~/.claude/plans/ dir.
make_home() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.claude/plans"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# Creates an isolated project dir with .bionic/docs/plans/ ready to receive
# plan files. Returned path plays the CLAUDE_PROJECT_DIR role.
make_project() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# Writes $2 as a plan file inside $1/.bionic/docs/plans/ (project-local dir).
write_project_plan() {
  local project_dir="$1" content="$2" name="${3:-active.md}"
  local path="$project_dir/.bionic/docs/plans/$name"
  printf '%s\n' "$content" > "$path"
  touch "$path"
  echo "$path"
}

# Writes $2 as the content of a plan file inside $1/.claude/plans/.
# Touches mtime to "now" so it becomes the newest.
write_plan() {
  local home_dir="$1" content="$2" name="${3:-active.md}"
  local path="$home_dir/.claude/plans/$name"
  printf '%s\n' "$content" > "$path"
  # Ensure mtime > any prior plan in this test by nudging forward.
  touch "$path"
  echo "$path"
}

# Runs hook with HOME set to $1 and the given bash-tool-call command $2.
# Sets globals HOOK_EXIT and HOOK_STDERR. The hook is stderr-only on block,
# silent on allow — no need to capture stdout.
run_hook() {
  local home_dir="$1" command="$2"
  local input
  # Pin the hook's cwd to the sandbox HOME so PROJECT_DIR resolves via the
  # documented input-cwd path instead of falling through to the runner's real
  # pwd — otherwise the suite's verdicts would depend on whatever plan files
  # live under the ambient working directory (a hermeticity leak).
  input=$(jq -n --arg c "$command" --arg cwd "$home_dir" '{tool_input: {command: $c}, cwd: $cwd}')
  local tmp_err
  tmp_err=$(mktemp)
  # Capture exit code without letting errexit kill the test runner, and
  # without the `|| true` trick (which replaces $? with 0).
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

# Like run_hook but also sets CLAUDE_PROJECT_DIR so the hook will scan
# project-local plan directories (.bionic/docs/plans/, docs/superpowers/plans/).
run_hook_with_project() {
  local home_dir="$1" project_dir="$2" command="$3"
  local input
  # CLAUDE_PROJECT_DIR (set below) already wins over cwd in the hook's
  # resolution, but pin cwd to the project sandbox anyway so the input is
  # hermetic and never consults the runner's real pwd.
  input=$(jq -n --arg c "$command" --arg cwd "$project_dir" '{tool_input: {command: $c}, cwd: $cwd}')
  local tmp_err
  tmp_err=$(mktemp)
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

expect_allow() {
  local label="$1" home_dir="$2" command="$3"
  TOTAL=$((TOTAL + 1))
  run_hook "$home_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected allow, exit 0, no stderr): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}

expect_block() {
  local label="$1" home_dir="$2" command="$3" expected_substr="${4:-BLOCKED}"
  TOTAL=$((TOTAL + 1))
  run_hook "$home_dir" "$command"
  if [ "$HOOK_EXIT" -eq 2 ] && echo "$HOOK_STDERR" | grep -q "$expected_substr"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected block exit 2 with substring '$expected_substr'): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}

# Minimal valid frontmatter for fixtures whose subject is NOT the frontmatter.
# scale: wave + rigor: tested keeps the wave-lane machinery (dispatch ledger,
# rigor lanes) out of the way so each fixture isolates the behavior under test.
FM='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 12
intent: build
rigor: tested
scale: wave
deploy_target: none
use_worktree: false
has_ui: false
---'

# ============================================================
# Section 1: non-commit commands always allowed
# ============================================================

echo ""
echo "=== Section 1: Non-commit commands pass through ==="

h1=$(make_home)
# Seed a plan that WOULD block if the command were a commit.
write_plan "$h1" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null

expect_allow "ls command — not a commit" "$h1" "ls /tmp"
expect_allow "git status — not a commit" "$h1" "git status"
expect_allow "git push — not a commit" "$h1" "git push origin main"
expect_allow "empty command" "$h1" ""

# ============================================================
# Section 2: commit with no plans directory / no plans
# ============================================================

echo ""
echo "=== Section 2: Commit with no canonical-sdlc state — allowed ==="

h2=$(make_home)
# plans dir exists but empty
expect_allow "empty plans dir — allow commit" "$h2" 'git commit -m "x"'

h2b=$(mktemp -d); cleanup_dirs+=("$h2b")
# No ~/.claude/plans/ at all
expect_allow "no plans dir at all — allow commit" "$h2b" 'git commit -m "x"'

h2c=$(make_home)
write_plan "$h2c" "# regular plan
Some content.
No SDLC State section here." > /dev/null
expect_allow "plan without ## SDLC State — allow commit" "$h2c" 'git commit -m "x"'

# ============================================================
# Section 3: valid evidence allows commit
# ============================================================

echo ""
echo "=== Section 3: Valid evidence in ## SDLC State — allowed ==="

h3=$(make_home)
write_plan "$h3" "$FM
# plan

## SDLC State
current: 3
Step 1: /path/to/ideate.md
Step 2: /path/to/spec.md
Step 3: ~/.claude/plans/this.md

## Other section" > /dev/null
expect_allow "valid pointer-step evidence — allow" "$h3" 'git commit -m "step 3 done"'

h3b=$(make_home)
write_plan "$h3b" "$FM
## SDLC State
current: 8b
Step 8b: critic report attached in docs/review.md" > /dev/null
expect_allow "valid step 8b evidence — allow" "$h3b" 'git commit -m "critic done"'

h3c=$(make_home)
write_plan "$h3c" "$FM
## SDLC State
current: 10
- Step 10: commit SHA abc123 body written" > /dev/null
expect_allow "bulleted Step line — allow" "$h3c" 'git commit -m "x"'

# ============================================================
# Section 4: malformed / missing SDLC State pieces
# ============================================================

echo ""
echo "=== Section 4: Malformed SDLC State — blocked ==="

h4=$(make_home)
write_plan "$h4" "$FM
## SDLC State
# no current line, no phase lines

## Next section" > /dev/null
expect_block "missing 'current: N' line" "$h4" 'git commit -m "x"' "missing a valid 'current: N'"

h4b=$(make_home)
write_plan "$h4b" "$FM
## SDLC State
current: 5
Step 1: done
Step 2: done
# no Step 5 line" > /dev/null
expect_block "no matching Step N line" "$h4b" 'git commit -m "x"' "no 'Step 5:' line"

h4c=$(make_home)
write_plan "$h4c" "$FM
## SDLC State
current: five
Step 5: something" > /dev/null
expect_block "non-numeric current" "$h4c" 'git commit -m "x"' "missing a valid 'current: N'"

# ============================================================
# Section 5: empty / placeholder evidence — blocked
# ============================================================

echo ""
echo "=== Section 5: Placeholder evidence — blocked ==="

h5=$(make_home)
write_plan "$h5" "$FM
## SDLC State
current: 5
Step 5:   " > /dev/null
expect_block "empty evidence line" "$h5" 'git commit -m "x"' "is empty"

for token in TODO pending "in progress" XXX TBD placeholder; do
  h=$(make_home)
  write_plan "$h" "$FM
## SDLC State
current: 5
Step 5: $token" > /dev/null
  expect_block "placeholder '$token'" "$h" 'git commit -m "x"' "placeholder"
done

# Case-insensitive placeholder match. Under whole-value equality the ENTIRE
# trimmed value must equal a token, so the fixture is the bare token 'Todo'
# (was "Todo — still writing", which is prose that merely starts with the
# token — legal under the new contract; see 5e).
h5b=$(make_home)
write_plan "$h5b" "$FM
## SDLC State
current: 5
Step 5: Todo" > /dev/null
expect_block "placeholder 'Todo' (mixed case, bare token)" "$h5b" 'git commit -m "x"' "placeholder"

# --- whole-value equality: the placeholder ban matches only when the whole
# trimmed, lowercased value EQUALS a token (todo/pending/in progress/
# inprogress/xxx/tbd/placeholder). A token appearing as a substring of a
# longer value is legal evidence.

# 5c — whole-line 'Step 5: pending' (single-line value) → block.
h5c=$(make_home)
write_plan "$h5c" "$FM
## SDLC State
current: 5
Step 5: pending" > /dev/null
expect_block "whole-line 'Step 5: pending' → block" "$h5c" 'git commit -m "x"' "placeholder"

# 5d — trim + lowercase before comparison: '  Pending  ' (padded, mixed case)
# as a continuation value still equals the token → block.
h5d=$(make_home)
write_plan "$h5d" "$FM
## SDLC State
current: 5
Step 5:
  readback:   Pending  " > /dev/null
expect_block "padded mixed-case 'readback:   Pending  ' → block" "$h5d" 'git commit -m "x"' "placeholder"

# 5e — a value that merely CONTAINS a token as a substring is legal:
# 'resolved all TODOs from the last review' (contains 'todo') → allow. Under
# the OLD substring ban this was a false block.
h5e=$(make_home)
write_plan "$h5e" "$FM
## SDLC State
current: 3
Step 3: resolved all TODOs from the last review" > /dev/null
expect_allow "substring-only 'resolved all TODOs' → allow (whole-value equality)" \
  "$h5e" 'git commit -m "x"'

# 5f — a continuation key whose whole value equals a token still blocks:
# 'stack-health: pending' (value 'pending') → block.
h5f=$(make_home)
write_plan "$h5f" "$FM
## SDLC State
current: 5
Step 5:
  stack-health: pending" > /dev/null
expect_block "continuation 'stack-health: pending' (whole value) → block" \
  "$h5f" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 6: compound commands + edge cases
# ============================================================

echo ""
echo "=== Section 6: Compound commands — commit detection ==="

h6=$(make_home)
write_plan "$h6" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_block "cd && git commit" "$h6" 'cd /tmp && git commit -m "x"' "placeholder"
expect_block "git add && git commit" "$h6" 'git add . && git commit -m "x"' "placeholder"

# False-positive check: quoted "git commit" as prose shouldn't trigger
# gate on its own, but a real `git commit` in the same command does.
h6b=$(make_home)
write_plan "$h6b" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_allow "echo only, no real commit" "$h6b" 'echo "we will git commit later"'

# ============================================================
# Section 7: newest-plan-wins
# ============================================================

echo ""
echo "=== Section 7: Newest plan file is the one enforced ==="

h7=$(make_home)
# Older plan with valid state
write_plan "$h7" "$FM
## SDLC State
current: 5
Step 5: tests green" "old.md" > /dev/null
# Make old.md older than now.
touch -t 202001010000 "$h7/.claude/plans/old.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h7/.claude/plans/old.md" 2>/dev/null || true
# Newer plan with bad state
write_plan "$h7" "$FM
## SDLC State
current: 5
Step 5: TODO" "new.md" > /dev/null
expect_block "newest plan rules — bad state blocks even with valid older plan" \
  "$h7" 'git commit -m "x"' "placeholder"

# Inverse: newer plan without ## SDLC State lets commit pass even if
# an older plan has bad state.
h7b=$(make_home)
write_plan "$h7b" "$FM
## SDLC State
current: 5
Step 5: TODO" "old-bad.md" > /dev/null
touch -t 202001010000 "$h7b/.claude/plans/old-bad.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h7b/.claude/plans/old-bad.md" 2>/dev/null || true
write_plan "$h7b" "# unrelated plan, no SDLC State" "new-neutral.md" > /dev/null
expect_allow "newest plan without SDLC State — allow despite bad older plan" \
  "$h7b" 'git commit -m "x"'

# ============================================================
# Section 8: project-local plan directory (.bionic/docs/plans/)
# ============================================================

echo ""
echo "=== Section 8: Project-local plan dir (CLAUDE_PROJECT_DIR) ==="

# Helpers that exercise both plan-dir paths at once.
expect_allow_both() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4"
  TOTAL=$((TOTAL + 1))
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected allow): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}

expect_block_both() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4" substr="${5:-BLOCKED}"
  TOTAL=$((TOTAL + 1))
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 2 ] && echo "$HOOK_STDERR" | grep -q "$substr"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected block with '$substr'): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}

# 8a — project-local plan alone, global empty: hook honors project plan.
h8a=$(make_home); p8a=$(make_project)
write_project_plan "$p8a" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_block_both "project-local plan (bad) blocks with no global plan" \
  "$h8a" "$p8a" 'git commit -m "x"' "placeholder"

# 8b — project-local plan alone, global empty: good evidence allows.
h8b=$(make_home); p8b=$(make_project)
write_project_plan "$p8b" "$FM
## SDLC State
current: 3
Step 3: commit abc123 tests green" > /dev/null
expect_allow_both "project-local plan (good) allows with no global plan" \
  "$h8b" "$p8b" 'git commit -m "x"'

# 8c — both plans exist, project is newer → project wins.
h8c=$(make_home); p8c=$(make_project)
write_plan "$h8c" "$FM
## SDLC State
current: 3
Step 3: commit xyz green" "old-global.md" > /dev/null
touch -t 202001010000 "$h8c/.claude/plans/old-global.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h8c/.claude/plans/old-global.md" 2>/dev/null || true
write_project_plan "$p8c" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_block_both "newer project plan (bad) wins over older global (good)" \
  "$h8c" "$p8c" 'git commit -m "x"' "placeholder"

# 8d — both plans exist, global is newer → global wins.
h8d=$(make_home); p8d=$(make_project)
write_project_plan "$p8d" "$FM
## SDLC State
current: 5
Step 5: TODO" "old-proj.md" > /dev/null
touch -t 202001010000 "$p8d/.bionic/docs/plans/old-proj.md" 2>/dev/null || \
  touch -d "2020-01-01" "$p8d/.bionic/docs/plans/old-proj.md" 2>/dev/null || true
write_plan "$h8d" "$FM
## SDLC State
current: 3
Step 3: commit xyz green" > /dev/null
expect_allow_both "newer global plan (good) wins over older project (bad)" \
  "$h8d" "$p8d" 'git commit -m "x"'

# 8e — project dir lacks .bionic/docs/plans/: hook falls back to global.
h8e=$(make_home)
p8e=$(mktemp -d); cleanup_dirs+=("$p8e") # no .bionic/docs/plans/ inside
write_plan "$h8e" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_block_both "project without .bionic/docs/plans/ falls back to global plan" \
  "$h8e" "$p8e" 'git commit -m "x"' "placeholder"

# 8f — CLAUDE_PROJECT_DIR unset: original behavior (global only).
h8f=$(make_home)
write_plan "$h8f" "$FM
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_block "CLAUDE_PROJECT_DIR unset: still gates on global plan" \
  "$h8f" 'git commit -m "x"' "placeholder"

# 8g — also covers superpowers convention.
h8g=$(make_home); p8g=$(mktemp -d); cleanup_dirs+=("$p8g")
mkdir -p "$p8g/docs/superpowers/plans"
printf '%s\n## SDLC State\ncurrent: 5\nStep 5: TODO\n' "$FM" > "$p8g/docs/superpowers/plans/active.md"
touch "$p8g/docs/superpowers/plans/active.md"
expect_block_both "docs/superpowers/plans/ plan is honored alongside bionic" \
  "$h8g" "$p8g" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 17: Verification Matrix gate
# ============================================================
#
# The Verify gate uses a pre-registered Verification Matrix
# stored in a top-level `## Verification Matrix` section of the plan. The
# Step-5 block keeps the tests floor (cmd/pass/total/output) and gains a
# required `auditor:` pointer; the matrix carries a per-session
# `stack-health:` line, a tier table (one row per AC), and one indented
# per-AC evidence block per non-waived row. Each row declares a tier
# (T0..T4); the hook demands that tier's evidence keys (keys_for_tier) —
# non-empty, placeholder-banned, and (on live tiers T3/T4) not self-written
# `n/a`. A `waiver:` entry exempts a row. At `current > 5` every non-waived
# row's auditor cell must read CONFIRMED. The matrix validates at current: 5
# (Step-5 validator) and as a prefix check for current: 6..9.

echo ""
echo "=== Section 17: Verification Matrix gate ==="

matrix_frontmatter() {
  local has_ui="${1:-true}" deploy="${2:-none}" use_wt="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 12
intent: build
rigor: audited
scale: wave
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
---
EOF
}

# Shared Step-5 block: tests floor + the required auditor pointer.
step5_base="  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"

# Assemble a full plan: frontmatter + ## SDLC State (current + Step
# block) + a ## Verification Matrix section. $1 current, $2 Step-block
# body (indented lines), $3 full matrix section text.
plan() {
  printf '%s\n## SDLC State\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(matrix_frontmatter true)" "$1" "$1" "$2" "$3"
}

# A pointer body for post-Verify steps (6..9): non-empty, non-placeholder.
step6_body="  review: .bionic/docs/plans/wave-01.plan.md#step-6-review"

# --- matrix fixtures -------------------------------------------------------

# Complete, valid matrix: T3 (all five fields), T1 (tier-run+readback),
# waived T3 row. stack-health present. All auditor cells CONFIRMED/waived.
matrix_complete="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: dana 2026-07-16 env stale | waived |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# discharged T3 row with NO matching AC evidence block (AC-1 block absent).
matrix_no_block="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |

AC-2:
  tier-run: bash test.sh
  readback: 332/332 asserted"

# AC-1 readback is a placeholder token.
matrix_placeholder="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a
  cold-client: fresh incognito profile
  contact: clicked open — panel closed → open
  readback: TBD"

# AC-1 (T3) contact is a self-written n/a with no waiver.
matrix_live_na="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a
  cold-client: fresh incognito profile
  contact: n/a: not reachable quickly
  readback: panel.visible === true via page eval"

# AC-1 declared T3 but carries only the suite-credit shape (tier-run +
# readback), missing fresh/cold-client/contact.
matrix_suite_credit="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: suite: hermetic-x
  readback: 12/12 asserted"

# Complete matrix but AC-1 auditor verdict is REFUTED.
matrix_refuted="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | REFUTED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: dana 2026-07-16 env stale | waived |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# Complete matrix; the waived row's auditor cell is empty (legal).
matrix_waived_empty="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: dana 2026-07-16 env stale |  |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# stack-health line absent.
matrix_no_stackhealth="## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted"

# stack-health via the n/a escape.
matrix_stackhealth_na="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted"

# T0/T1/T2-only matrix — no T3 fields, no browser artifacts anywhere.
matrix_lower_tiers="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T2 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T0 | discharged | see AC-3 | CONFIRMED |

AC-1:
  tier-run: bash test.sh — unit
  readback: 40/40 asserted
AC-2:
  tier-run: playwright hermetic run
  readback: rendered rows === 5
  fixture-fidelity: derived from captured prod payload 2026-07-10
AC-3:
  tier-run: pnpm build && tsc
  readback: 0 type errors"

# false-green entry with no paired rewritten entry.
matrix_false_green_unpaired="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted

false-green: hermetic-x — green over broken branch"

# false-green entry WITH a paired rewritten entry.
matrix_false_green_paired="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted

false-green: hermetic-x — green over broken branch
rewritten: fixed in commit abc123, test now RED-first"

# A malformed row: a stray literal | shears an extra cell.
matrix_malformed="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see | AC-1 | CONFIRMED |

AC-1:
  tier-run: x
  fresh: x
  cold-client: x
  contact: x
  readback: x"

# --- cases -----------------------------------------------------------------

# 17a — complete matrix at current: 5 → allow.
h17a=$(make_home)
write_plan "$h17a" "$(plan 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_allow "17a complete matrix (T3 + T1 + waived T3) at current 5 → allow" \
  "$h17a" 'git commit -m "x"'

# 17b — discharged row with NO AC evidence block → block, names the AC.
h17b=$(make_home)
write_plan "$h17b" "$(plan 5 "$step5_base" "$matrix_no_block")" > /dev/null
expect_block "17b discharged T3 row with no AC block → block (names AC-1)" \
  "$h17b" 'git commit -m "x"' "AC-1"

# 17c — placeholder token in an AC evidence field → block.
h17c=$(make_home)
write_plan "$h17c" "$(plan 5 "$step5_base" "$matrix_placeholder")" > /dev/null
expect_block "17c readback: TBD in AC block → block (placeholder ban)" \
  "$h17c" 'git commit -m "x"' "placeholder"

# 17c-substr — a matrix AC field VALUE that merely CONTAINS a placeholder
# token as a substring is legal; only a whole-value match blocks. readback:
# 'status pending → done ...' (contains 'pending') → allow.
matrix_substr_ok="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: status pending → done, 40/40 asserted"
h17c2=$(make_home)
write_plan "$h17c2" "$(plan 5 "$step5_base" "$matrix_substr_ok")" > /dev/null
expect_allow "17c matrix readback containing 'pending' substring → allow (whole-value equality)" \
  "$h17c2" 'git commit -m "x"'

# 17d — T3 row with self-written n/a on a field, no waiver → block, points
# at the Waiver Protocol.
h17d=$(make_home)
write_plan "$h17d" "$(plan 5 "$step5_base" "$matrix_live_na")" > /dev/null
expect_block "17d T3 contact: n/a, no waiver → block (Waiver Protocol)" \
  "$h17d" 'git commit -m "x"' "Waiver Protocol"

# 17d-case — the live-tier n/a ban must be case-insensitive: 'N/A' and
# 'N/a: <reason>' are the same self-written downgrade as lowercase 'n/a'
# (review-gate finding: a single capital letter must not defeat the ban).
# The variants are written as full literal matrices rather than derived from
# matrix_live_na via ${var/pat/rep}: a slash in the contact value forces
# an escaped slash in the pattern, and bash 3.2 leaves that backslash in the
# replacement (producing 'contact: N\/A'), so the variant is never built.
matrix_live_na_upper="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a
  cold-client: fresh incognito profile
  contact: N/A
  readback: panel.visible === true via page eval"
h17d2=$(make_home)
write_plan "$h17d2" "$(plan 5 "$step5_base" "$matrix_live_na_upper")" > /dev/null
expect_block "17d T3 contact: N/A (uppercase), no waiver → block" \
  "$h17d2" 'git commit -m "x"' "Waiver Protocol"

matrix_live_na_mixed="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a
  cold-client: fresh incognito profile
  contact: N/a: not reachable quickly
  readback: panel.visible === true via page eval"
h17d3=$(make_home)
write_plan "$h17d3" "$(plan 5 "$step5_base" "$matrix_live_na_mixed")" > /dev/null
expect_block "17d T3 contact: N/a: <reason> (mixed case), no waiver → block" \
  "$h17d3" 'git commit -m "x"' "Waiver Protocol"

# 17e — T3 row with only the suite-credit shape (missing fresh/cold-client/
# contact) → block.
h17e=$(make_home)
write_plan "$h17e" "$(plan 5 "$step5_base" "$matrix_suite_credit")" > /dev/null
expect_block "17e T3 suite-credit shape missing live-tier fields → block (fresh)" \
  "$h17e" 'git commit -m "x"' "fresh"

# 17f — current: 6, one row auditor REFUTED → block.
h17f1=$(make_home)
write_plan "$h17f1" "$(plan 6 "$step6_body" "$matrix_refuted")" > /dev/null
expect_block "17f current 6 with a REFUTED row → block (CONFIRMED required)" \
  "$h17f1" 'git commit -m "x"' "CONFIRMED"

# 17f — current: 6, all non-waived rows CONFIRMED → allow.
h17f2=$(make_home)
write_plan "$h17f2" "$(plan 6 "$step6_body" "$matrix_complete")" > /dev/null
expect_allow "17f current 6 all CONFIRMED (waived row exempt) → allow" \
  "$h17f2" 'git commit -m "x"'

# 17f — current: 6, waived row with an empty auditor cell → allow.
h17f3=$(make_home)
write_plan "$h17f3" "$(plan 6 "$step6_body" "$matrix_waived_empty")" > /dev/null
expect_allow "17f current 6 waived row with empty auditor cell → allow" \
  "$h17f3" 'git commit -m "x"'

# 17g — current: 5 with NO ## Verification Matrix section → block.
h17g=$(make_home)
write_plan "$h17g" "$(matrix_frontmatter true)
## SDLC State
current: 5
Step 5:
$step5_base" > /dev/null
expect_block "17g current 5 with no Verification Matrix section → block" \
  "$h17g" 'git commit -m "x"' "Verification Matrix"

# 17h — matrix missing the stack-health line → block.
h17h1=$(make_home)
write_plan "$h17h1" "$(plan 5 "$step5_base" "$matrix_no_stackhealth")" > /dev/null
expect_block "17h matrix missing stack-health → block" \
  "$h17h1" 'git commit -m "x"' "stack-health"

# 17h — stack-health via the n/a escape → allow.
h17h2=$(make_home)
write_plan "$h17h2" "$(plan 5 "$step5_base" "$matrix_stackhealth_na")" > /dev/null
expect_allow "17h stack-health: n/a with reason → allow" \
  "$h17h2" 'git commit -m "x"'

# 17i — T0/T1/T2-only matrix, no T3 fields, no browser artifacts → allow.
h17i=$(make_home)
write_plan "$h17i" "$(plan 5 "$step5_base" "$matrix_lower_tiers")" > /dev/null
expect_allow "17i lower-tier-only matrix (T0/T1/T2) → allow" \
  "$h17i" 'git commit -m "x"'

# 17j — Step-5 block missing the auditor pointer → block.
h17j1=$(make_home)
write_plan "$h17j1" "$(plan 5 "  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5" "$matrix_complete")" > /dev/null
expect_block "17j Step-5 missing auditor → block" \
  "$h17j1" 'git commit -m "x"' "auditor"

# 17j — Step-5 block missing the tests floor (cmd) → block (validator reuse).
h17j2=$(make_home)
write_plan "$h17j2" "$(plan 5 "  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md" "$matrix_complete")" > /dev/null
expect_block "17j Step-5 missing tests floor cmd → block" \
  "$h17j2" 'git commit -m "x"' "cmd"

# 17l — false-green entry with NO paired rewritten entry → block.
h17l1=$(make_home)
write_plan "$h17l1" "$(plan 5 "$step5_base" "$matrix_false_green_unpaired")" > /dev/null
expect_block "17l false-green without rewritten → block" \
  "$h17l1" 'git commit -m "x"' "rewritten"

# 17l — false-green entry WITH a paired rewritten entry → allow.
h17l2=$(make_home)
write_plan "$h17l2" "$(plan 5 "$step5_base" "$matrix_false_green_paired")" > /dev/null
expect_allow "17l false-green with paired rewritten → allow" \
  "$h17l2" 'git commit -m "x"'

# 17l — no false-green entry at all (key is optional) → allow.
h17l3=$(make_home)
write_plan "$h17l3" "$(plan 5 "$step5_base" "$matrix_lower_tiers")" > /dev/null
expect_allow "17l no false-green entry (optional key) → allow" \
  "$h17l3" 'git commit -m "x"'

# 17m — a malformed table row (stray literal | shears a cell) → block.
h17m=$(make_home)
write_plan "$h17m" "$(plan 5 "$step5_base" "$matrix_malformed")" > /dev/null
expect_block "17m malformed row (extra literal |) → block" \
  "$h17m" 'git commit -m "x"' "malformed"

# --- mid-discharge commits at the Verify gate ------------------------
#
# At current: 5 a row still being discharged (status pending/blocked) is
# exempt from its per-tier evidence keys, and the Step-5 `auditor:` pointer
# is required only once every row is discharged or waived — the full
# contract bites on the 5→6 advance (the 6..9 prefix check), mirroring the
# CONFIRMED rule. The status cell becomes load-bearing, so it gains an enum
# check (pending|blocked|discharged|waived). Rationale: without this, a
# corrective commit made mid-walk has no honest home — the observed
# workaround was editing `current:` back to 4, which silently disables the
# tests floor and misstates the step.

# Step-5 block with the tests floor but NO auditor pointer — the shape of a
# mid-walk corrective commit.
v101_step5_noauditor="  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5"

# Mixed matrix mid-walk: AC-1 discharged with full T3 evidence, AC-2 still
# pending with no AC block and an empty auditor cell.
v101_matrix_pending="## Verification Matrix

stack-health: before: process restarts 0; walk in progress

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T3 | pending | see AC-2 |  |

AC-1:
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval"

# Same shape with a blocked row (undrivable interaction, loud).
v101_matrix_blocked="${v101_matrix_pending/| AC-2 | T3 | pending | see AC-2 |  |/| AC-2 | T3 | blocked | montage panel undrivable — see AC-2 |  |}"

# Invalid status token in the status cell.
v101_matrix_bad_status="${v101_matrix_pending/| AC-2 | T3 | pending | see AC-2 |  |/| AC-2 | T3 | done | see AC-2 |  |}"

# Pending row that DOES carry a partial AC block with a live-tier n/a —
# exempt at current: 5 (the whole per-tier check is deferred, caught when
# the row flips to discharged or at the 6..9 prefix check).
v101_matrix_pending_partial="$v101_matrix_pending
AC-2:
  contact: n/a: staging origin down"

# 17n — pending row, no AC block, current: 5 → allow (mid-walk commit home).
h17n1=$(make_home)
write_plan "$h17n1" "$(plan 5 "$step5_base" "$v101_matrix_pending")" > /dev/null
expect_allow "17n pending row without AC block at current 5 → allow" \
  "$h17n1" 'git commit -m "x"'

# 17n — pending row AND no auditor pointer → allow (the auditor is the
# Step-5 exit gate; it cannot have run while rows are pending).
h17n2=$(make_home)
write_plan "$h17n2" "$(plan 5 "$v101_step5_noauditor" "$v101_matrix_pending")" > /dev/null
expect_allow "17n pending row + no auditor pointer at current 5 → allow" \
  "$h17n2" 'git commit -m "x"'

# 17n — blocked row, no auditor pointer → allow (same relaxation).
h17n3=$(make_home)
write_plan "$h17n3" "$(plan 5 "$v101_step5_noauditor" "$v101_matrix_blocked")" > /dev/null
expect_allow "17n blocked row + no auditor pointer at current 5 → allow" \
  "$h17n3" 'git commit -m "x"'

# 17n — pending row with a partial block carrying a live-tier n/a → allow
# at current 5 (deferred, not licensed: it blocks at discharge/advance).
h17n4=$(make_home)
write_plan "$h17n4" "$(plan 5 "$step5_base" "$v101_matrix_pending_partial")" > /dev/null
expect_allow "17n pending row with partial block (contact: n/a) at current 5 → allow" \
  "$h17n4" 'git commit -m "x"'

# 17o — fully discharged matrix + missing auditor pointer → still block
# (17j1 pins the same shape; this pins it against the mid-discharge relaxation).
h17o1=$(make_home)
write_plan "$h17o1" "$(plan 5 "$v101_step5_noauditor" "$matrix_complete")" > /dev/null
expect_block "17o fully discharged matrix + no auditor pointer → block" \
  "$h17o1" 'git commit -m "x"' "auditor"

# 17p — invalid status token → block, names the row and the enum.
h17p1=$(make_home)
write_plan "$h17p1" "$(plan 5 "$step5_base" "$v101_matrix_bad_status")" > /dev/null
expect_block "17p invalid status 'done' at current 5 → block (enum)" \
  "$h17p1" 'git commit -m "x"' "invalid status"

h17p2=$(make_home)
write_plan "$h17p2" "$(plan 6 "$step6_body" "$v101_matrix_bad_status")" > /dev/null
expect_block "17p invalid status 'done' at current 6 → block (enum)" \
  "$h17p2" 'git commit -m "x"' "invalid status"

# 17q — the relaxation is 5-only: a pending row at current: 6 blocks (its
# per-tier keys are demanded by the prefix check).
h17q=$(make_home)
write_plan "$h17q" "$(plan 6 "$step6_body" "$v101_matrix_pending")" > /dev/null
expect_block "17q pending row at current 6 → block (relaxation is 5-only)" \
  "$h17q" 'git commit -m "x"' "AC-2"

# ============================================================
# Section 18: matrix parser — section scoping + fenced-code skip
# ============================================================
#
# The matrix validator reads every parse (stack-health, false-green,
# tier-table rows, per-AC blocks) from matrix_section() — the body of the
# top-level `## Verification Matrix` section. Two properties this section
# pins:
#   (1) Row grammar applies ONLY inside that section — a leading-pipe line
#       in another section is never read as a table row.
#   (2) Inside that section, lines within ``` fenced code blocks are
#       skipped — so a jq/shell pipeline written in leading-pipe
#       continuation style does not masquerade as a malformed table row.
# Regression origin: epic-06's matrix section embeds fenced bash/jq blocks;
# a leading-pipe jq continuation line ('| select(.name == "chromium")') was
# parsed as a matrix row and blocked the commit with a bogus malformed-row
# error.

echo ""
echo "=== Section 18: matrix section scoping + fenced-code skip ==="

# A fenced bash block whose jq pipeline uses leading-pipe continuation lines
# — the exact shape that tripped the validator live. Single-quoted so the
# triple backticks and inner quotes stay literal (no command substitution).
v10_fence_block='```bash
playwright projects --json | jq -r '"'"'.browsers[]
       | select(.name == "chromium")
       | "\(.name)"'"'"'
```'

# (a) Valid, fully discharged matrix with a fenced pipeline appended inside
# the section (matrix is the last section, so the fence sits at EOF within
# it). RED before the fix: the '| select(...)' lines parse as malformed rows.
matrix_fence_after="$matrix_complete

$v10_fence_block"

h18a=$(make_home)
write_plan "$h18a" "$(plan 5 "$step5_base" "$matrix_fence_after")" > /dev/null
expect_allow "18a fenced jq (leading-pipe) inside matrix section at current 5 → allow" \
  "$h18a" 'git commit -m "x"'

# (b) A leading-pipe line OUTSIDE the matrix section (a later ## section),
# not fenced → allow. Pins that row grammar is scoped to the matrix section.
h18b=$(make_home)
write_plan "$h18b" "$(matrix_frontmatter true)
## SDLC State
current: 5
Step 5:
$step5_base

$matrix_complete

## Notes
| this stray pipe line lives outside the matrix section
| and must never be read as a table row" > /dev/null
expect_allow "18b leading-pipe line outside the matrix section → allow" \
  "$h18b" 'git commit -m "x"'

# (c) A fenced pipeline (skipped) AND a genuinely malformed table row (a
# stray literal | shears a cell) → still block. Pins that fence-skip does
# not suppress real malformed rows.
matrix_fence_and_malformed="## Verification Matrix

stack-health: n/a: no long-running serve

$v10_fence_block

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see | AC-1 | CONFIRMED |

AC-1:
  tier-run: x
  fresh: x
  cold-client: x
  contact: x
  readback: x"

h18c=$(make_home)
write_plan "$h18c" "$(plan 5 "$step5_base" "$matrix_fence_and_malformed")" > /dev/null
expect_block "18c fenced pipeline + genuinely malformed row → block (malformed)" \
  "$h18c" 'git commit -m "x"' "malformed"

# (d) A fenced pipeline placed between stack-health and the table (mid-
# section), containing leading-pipe lines → allow. Pins that fence-skip works
# anywhere in the section, not just at the tail.
matrix_fence_before_table="## Verification Matrix

stack-health: n/a: no long-running serve

$v10_fence_block

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted"

h18d=$(make_home)
write_plan "$h18d" "$(plan 5 "$step5_base" "$matrix_fence_before_table")" > /dev/null
expect_allow "18d fenced pipeline before the table (mid-section) → allow" \
  "$h18d" 'git commit -m "x"'

# ============================================================
# Section 15: CRLF and CR-only line endings
# ============================================================
#
# CRLF (\r\n) previously defeated the hook's exact-match awk frontmatter
# parser (`$0=="---"` never matches "---\r"), so the version marker and every
# frontmatter-keyed check were lost. The earlier fix `tr -d '\r'` then broke
# CR-only (classic-Mac) plans by deleting every line break, collapsing the file
# to ONE line so `/^## SDLC State/` never matched and the hook exited 0 as "not
# a canonical-sdlc plan" — every commit passed ungated. The parser now
# TRANSLATES \r to real newlines, so all three line-ending styles parse alike.
#
# Each style is proved BOTH ways: a valid plan must be allowed (no false block
# from a mangled parse) and a plan with a broken matrix row must be blocked on
# THAT row (proving the frontmatter and body actually parsed, rather than the
# file being waved through or rejected wholesale).

echo ""
echo "=== Section 15: CRLF and CR-only line endings ==="

# Inserts a literal CR before each newline. Bash-3.2-safe ANSI-C quoting embeds
# a real CR byte in the sed script itself (BSD sed's replacement text does not
# interpret the two-character "\r" as an escape).
to_crlf() {
  printf '%s' "$1" | sed $'s/$/\r/'
}

# Replaces every newline with a carriage return, so the content carries NO \n
# at all. (write_plan then appends one trailing \n; the internal line breaks
# stay pure \r — the faithful CR-only shape.)
to_cr() {
  printf '%s' "$1" | tr '\n' '\r'
}

# 15a — CRLF plan, complete Step 5 + complete matrix → allow.
h15a=$(make_home)
write_plan "$h15a" "$(to_crlf "$(plan 5 "$step5_base" "$matrix_complete")")" > /dev/null
expect_allow "CRLF plan, complete Step 5 + matrix → allow" \
  "$h15a" 'git commit -m "x"'

# 15b — CRLF plan whose matrix has a discharged row with no AC block → block on
# that row. A mangled parse would either allow, or block on the version.
h15b=$(make_home)
write_plan "$h15b" "$(to_crlf "$(plan 5 "$step5_base" "$matrix_no_block")")" > /dev/null
expect_block "CRLF plan, broken matrix row → block on AC-1 (frontmatter parsed)" \
  "$h15b" 'git commit -m "x"' "AC-1"

# 15c — CR-only plan, complete Step 5 + complete matrix → allow.
h15c=$(make_home)
write_plan "$h15c" "$(to_cr "$(plan 5 "$step5_base" "$matrix_complete")")" > /dev/null
expect_allow "CR-only plan, complete Step 5 + matrix → allow" \
  "$h15c" 'git commit -m "x"'

# 15d — CR-only plan with a broken matrix row → block on that row. Before the
# fix the whole file collapsed to one line and the commit passed ungated.
h15d=$(make_home)
write_plan "$h15d" "$(to_cr "$(plan 5 "$step5_base" "$matrix_no_block")")" > /dev/null
expect_block "CR-only plan, broken matrix row → block on AC-1 (body parsed)" \
  "$h15d" 'git commit -m "x"' "AC-1"

# ============================================================
# Section 19: triple, task ledger, merge-target
# ============================================================
#
# Governance keys off the intent × rigor × scale triple. Two shapes follow
# from `scale:`:
#   (1) Wave/epic-scale plans carry the numbered-step shape — pointer steps
#       1/2/3/4, the Verify gate at 5, document at 7, integrate=8, ship=9.
#   (2) Task-scale plans (scale: task) address a ledger TASK, not a numbered
#       step: `current: T<n>` with evidence on `- T<n>:` lines.
#
# A wave plan naming an `epic:` also gets a LOG-ONLY merge-target check at the
# integrate step. `current: T<n>` on a non-task plan still blocks — the
# T-format is scale: task only.

echo ""
echo "=== Section 19: triple, task ledger, merge-target ==="

# Log-only assertion helpers: exit 0 with a finding on stderr (the standard
# expect_allow requires EMPTY stderr, which a finding violates).
expect_finding() {
  local label="$1" home_dir="$2" command="$3" substr="$4"
  TOTAL=$((TOTAL + 1))
  run_hook "$home_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && echo "$HOOK_STDERR" | grep -q "$substr"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected allow exit 0 + stderr '$substr'): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}

expect_finding_both() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4" substr="$5"
  TOTAL=$((TOTAL + 1))
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && echo "$HOOK_STDERR" | grep -q "$substr"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected allow exit 0 + stderr '$substr'): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}

# Asserts the durable audit file exists under the sandbox HOME and carries a
# line matching $4 — pins the D14 file channel (not just the stderr echo).
expect_audit_line() {
  local label="$1" home_dir="$2" command="$3" substr="$4"
  TOTAL=$((TOTAL + 1))
  run_hook "$home_dir" "$command"
  # run_hook posts cwd=$home_dir with CLAUDE_PROJECT_DIR="", and the plan lives
  # at $home_dir/.claude/plans/ whose ancestry has no .bionic/ — so audit_root()
  # falls back to PROJECT_DIR == $home_dir. Incident 0001 keys the file on that
  # root but roots the file itself under HOME.
  local af; af=$(audit_file_for "$home_dir" "$home_dir")
  if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$af" ] && grep -q "$substr" "$af"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected exit 0 + audit-file line '$substr'): $label"
    echo "  exit=$HOOK_EXIT audit='$( [ -f "$af" ] && cat "$af" )'"
    FAIL=$((FAIL + 1))
  fi
}

# Frontmatter carrying the triple. $1 scale, $2 deploy, $3 use_worktree,
# $4 epic (omitted when empty).
frontmatter() {
  local scale="${1:-wave}" deploy="${2:-none}" use_wt="${3:-false}" epic="${4:-}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 12\n'
  printf -- 'intent: build\n'
  printf -- 'rigor: audited\n'
  printf -- 'scale: %s\n' "$scale"
  printf -- 'deploy_target: %s\n' "$deploy"
  printf -- 'use_worktree: %s\n' "$use_wt"
  printf -- 'has_ui: false\n'
  [ -n "$epic" ] && printf -- 'epic: %s\n' "$epic"
  printf -- '---\n'
}

# A wave plan: frontmatter + ## SDLC State (current + Step
# block) + ## Verification Matrix. Reuses the Section-17 matrix fixtures.
wave_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(frontmatter wave)" "$1" "$1" "$2" "$3"
}

# A wave plan naming an epic and carrying an integration-branch line, for
# the merge-target check. $1 current, $2 step body, $3 matrix, $4 epic,
# $5 integration-branch.
wave_epic_plan() {
  printf '%s\n## SDLC State\nintegration-branch: %s\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(frontmatter wave none false "$4")" "$5" "$1" "$1" "$2" "$3"
}

# A task-scale plan: frontmatter (scale: task) + the given body (a
# ## Tasks table followed by ## SDLC State).
task_plan() {
  printf '%s\n%s\n' "$(frontmatter task)" "$1"
}

# A task-scale plan at a caller-chosen frontmatter rigor (frontmatter
# hardcodes audited). $1 rigor, $2 body. Used to pin the log-only ledger-shape
# path that slice 4/3 promotes to BLOCKING only under frontmatter rigor:
# audited — a non-audited plan keeps logging findings.
task_frontmatter_rigor() {  # $1 rigor
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 12\n'
  printf -- 'intent: build\n'
  printf -- 'rigor: %s\n' "$1"
  printf -- 'scale: task\n'
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: false\n'
  printf -- '---\n'
}
task_plan_rigor() {  # $1 rigor  $2 body
  printf '%s\n%s\n' "$(task_frontmatter_rigor "$1")" "$2"
}

# A complete integrate (Step 8) block that passes the shape check, so the
# merge-target log-only check can be exercised in isolation.
integrate_body="  merge: merged wave into epic/07-x
  worktree-removed: n/a
  cleanup: n/a"

# --- (2) wave/epic-scale plans: the numbered-step shape ------------------

# 19a — wave plan at Step 5 with an incomplete matrix (discharged T3 row
# with no AC block) → block.
h19a=$(make_home)
write_plan "$h19a" "$(wave_plan 5 "$step5_base" "$matrix_no_block")" > /dev/null
expect_block "19a wave plan Step 5 incomplete matrix → block" \
  "$h19a" 'git commit -m "x"' "AC-1"

# 19b — wave plan at Step 5 with a complete matrix + auditor pointer →
# allow (pointer/matrix evidence in place).
h19b=$(make_home)
write_plan "$h19b" "$(wave_plan 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_allow "19b wave plan Step 5 complete matrix → allow" \
  "$h19b" 'git commit -m "x"'

# 19c — integrate is Step 8. A plan at current: 8 with a
# complete matrix but an integrate block missing merge/worktree-removed →
# block on the shape check (integrate fires at 8).
h19c=$(make_home)
write_plan "$h19c" "$(wave_plan 8 "  note: integrating now" "$matrix_complete")" > /dev/null
expect_block "19c integrate Step 8 missing merge fields → block" \
  "$h19c" 'git commit -m "x"' "merge"

# 19c2 — Step 4 is a pointer step: a pointer body allows.
h19c2=$(make_home)
write_plan "$h19c2" "$(frontmatter wave)
## SDLC State
current: 4
Step 4: .bionic/docs/plans/wave.plan.md#step-4" > /dev/null
expect_allow "19c2 wave plan Step 4 pointer → allow" \
  "$h19c2" 'git commit -m "x"'

# --- (2) task-scale ledger fixtures --------------------------------------

# Valid ledger: T1 done with evidence, T2 active with evidence; current: T2.
ledger_valid="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | refactor | peer-reviewed | extract the ledger helper | active |

## SDLC State

integration-branch: main
intent: build
rigor: peer-reviewed
scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: bash extract-helper.sh 4 cases green, commit def456"

# 19d — valid task ledger, current: T2 accepted → allow, no finding (BLOCKING-
# grade correctness: a false block here would be a defect).
h19d=$(make_home)
write_plan "$h19d" "$(task_plan_rigor tested "$ledger_valid")" > /dev/null
expect_allow "19d task plan current: T2 valid ledger → allow (T-format accepted)" \
  "$h19d" 'git commit -m "x"'

# 19e — no ## Tasks section on a NON-audited plan → exit 0 + task-ledger finding
# (log-only). Slice 4/3 promotes this check to BLOCKING under frontmatter
# rigor: audited (pinned by 22c5); a peer-reviewed plan keeps logging.
ledger_no_tasks="## SDLC State

intent: build
rigor: peer-reviewed
scale: task
current: T2

- T2: some evidence"
h19e=$(make_home)
write_plan "$h19e" "$(task_plan_rigor peer-reviewed "$ledger_no_tasks")" > /dev/null
expect_finding "19e missing ## Tasks section (non-audited) → exit 0 + task-ledger finding" \
  "$h19e" 'git commit -m "x"' "task-ledger"

# 19e2 — the finding is written to the durable audit file with the D14 format.
h19e2=$(make_home)
write_plan "$h19e2" "$(task_plan_rigor peer-reviewed "$ledger_no_tasks")" > /dev/null
expect_audit_line "19e2 missing ## Tasks → audit file line (evidence-gate task-ledger)" \
  "$h19e2" 'git commit -m "x"' "evidence-gate task-ledger:"

# 19f — status outside the enum (doing) on a NON-audited plan → exit 0 + finding
# (log-only). Slice 4/3 blocks this under rigor: audited (pinned by 22c1).
ledger_bad_status="${ledger_valid/| T2 | refactor | peer-reviewed | extract the ledger helper | active |/| T2 | refactor | peer-reviewed | extract the ledger helper | doing |}"
h19f=$(make_home)
write_plan "$h19f" "$(task_plan_rigor tested "$ledger_bad_status")" > /dev/null
expect_finding "19f invalid status 'doing' (non-audited) → exit 0 + task-ledger finding" \
  "$h19f" 'git commit -m "x"' "task-ledger"

# 19g — the ADDRESSED active task (T2, current: T2) with no `- T2:` evidence
# line → BLOCK. Slice 4/1 made the addressed-unit tested floor blocking; this
# case previously logged a finding (see Section 22 for the full lane coverage).
ledger_active_no_line="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | refactor | peer-reviewed | extract the ledger helper | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green"
h19g=$(make_home)
write_plan "$h19g" "$(task_plan_rigor tested "$ledger_active_no_line")" > /dev/null
expect_block "19g addressed active task without evidence line → block" \
  "$h19g" 'git commit -m "x"' "evidence line"

# 19h — the ADDRESSED active task (T2) with a placeholder evidence value
# (`- T2: TBD`) → BLOCK (slice 4/1 blocking floor; previously a finding).
ledger_active_placeholder="${ledger_valid/- T2: bash extract-helper.sh 4 cases green, commit def456/- T2: TBD}"
h19h=$(make_home)
write_plan "$h19h" "$(task_plan_rigor tested "$ledger_active_placeholder")" > /dev/null
expect_block "19h addressed active task placeholder evidence → block" \
  "$h19h" 'git commit -m "x"' "placeholder"

# 19i — done non-addressed task (T1) with an empty evidence line (`- T1:`) on a
# NON-audited plan → finding (log-only). Slice 4/3 blocks this under rigor:
# audited (pinned by 22c3).
ledger_done_empty="${ledger_valid/- T1: fixed in commit abc123, suite 5\/5 green/- T1:}"
h19i=$(make_home)
write_plan "$h19i" "$(task_plan_rigor peer-reviewed "$ledger_done_empty")" > /dev/null
expect_finding "19i done task missing evidence (non-audited) → exit 0 + task-ledger finding" \
  "$h19i" 'git commit -m "x"' "task-ledger"

# --- (2) task-scale CRLF -------------------------------------------------

# 19j — a valid task ledger with CRLF line endings → exit 0, no false finding
# (every parse path — frontmatter scale, current, ## Tasks, evidence lines —
# strips \r).
h19j=$(make_home)
write_plan "$h19j" "$(to_crlf "$(task_plan_rigor tested "$ledger_valid")")" > /dev/null
expect_allow "19j CRLF task ledger → allow, no false finding" \
  "$h19j" 'git commit -m "x"'

# 19j-cr — the same paths under CR-only (classic-Mac) line endings. Two
# assertions pin both directions of the normalization fix on the task path
# (frontmatter scale, current: T<n>, ## Tasks table, evidence lines):
#
# 19j-cr1 — a bad-status ledger under CR-only → exit 0 + task-ledger finding.
# Before the fix the file collapsed to one line, scale/## Tasks were never
# parsed → no finding at all (RED). After the fix the ledger validates and
# the bad status is caught.
h19jcr1=$(make_home)
write_plan "$h19jcr1" "$(to_cr "$(task_plan_rigor tested "$ledger_bad_status")")" > /dev/null
expect_finding "19j-cr1 CR-only bad-status ledger (non-audited) → exit 0 + task-ledger finding" \
  "$h19jcr1" 'git commit -m "x"' "task-ledger"

# 19j-cr2 — a valid ledger under CR-only → allow, no false finding (guard
# against over-flagging once CR-only parses correctly).
h19jcr2=$(make_home)
write_plan "$h19jcr2" "$(to_cr "$(task_plan_rigor tested "$ledger_valid")")" > /dev/null
expect_allow "19j-cr2 CR-only valid task ledger → allow, no false finding" \
  "$h19jcr2" 'git commit -m "x"'

# --- (4) epic merge-target consistency (log-only) ------------------------

# Build a project with an epic plan declaring integration-branch: epic/07-x.
make_epic_project() {
  local branch="$1"
  local proj
  proj=$(make_project)
  mkdir -p "$proj/.bionic/docs/plans/epic-fix"
  printf -- '---\ncanonical_sdlc_version: 12\nintent: build\nrigor: audited\nscale: epic\n---\n## SDLC State\nintegration-branch: %s\ncurrent: 1\n' \
    "$branch" > "$proj/.bionic/docs/plans/epic-fix/epic.plan.md"
  touch -t 202001010000 "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || \
    touch -d "2020-01-01" "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || true
  echo "$proj"
}

# 19k — plan integration-branch (main) mismatches the epic's (epic/07-x) at
# the integrate step → exit 0 + merge-target finding.
h19k=$(make_home); p19k=$(make_epic_project "epic/07-x")
write_project_plan "$p19k" \
  "$(wave_epic_plan 8 "$integrate_body" "$matrix_complete" epic-fix main)" \
  "wave-newest.plan.md" > /dev/null
expect_finding_both "19k merge-target mismatch → exit 0 + merge-target finding" \
  "$h19k" "$p19k" 'git commit -m "x"' "merge-target"

# 19l — matching integration-branch → no finding (silent allow).
h19l=$(make_home); p19l=$(make_epic_project "epic/07-x")
write_project_plan "$p19l" \
  "$(wave_epic_plan 8 "$integrate_body" "$matrix_complete" epic-fix "epic/07-x")" \
  "wave-newest.plan.md" > /dev/null
expect_allow_both "19l merge-target match → allow, no finding" \
  "$h19l" "$p19l" 'git commit -m "x"'

# --- (5) T-format is scale: task only ------------------------------------

# `current: T2` on a WAVE-scale plan is not a valid step pointer: the T-format
# belongs to the task-scale ledger. It falls through to the numeric check and
# blocks.
h19m=$(make_home)
write_plan "$h19m" "$(frontmatter wave)
## SDLC State
current: T2
Step 5: whatever" > /dev/null
expect_block "19m wave-scale plan with current: T2 → block (T-format is scale: task only)" \
  "$h19m" 'git commit -m "x"' "valid"

# --- fence-aware SDLC-State extraction (blocking-grade correctness) -------

# A fenced ``` example containing a `## SDLC State` heading + `current: T2`
# line — the D12 task-scale schema as it appears in a plan's PROSE. Single-
# quoted so the triple backticks stay literal (no command substitution).
v11_fenced_sdlcstate_shadow='```
## SDLC State
current: T2

- T1: <evidence>
- T2: <evidence>
```'

# 19o — the SDLC-State extraction must be fence-aware, like matrix_section.
# A plan whose body documents the task-scale schema in a fenced block
# BEFORE the real section must validate against the REAL `## SDLC State`
# (current: 5 + complete matrix), not the shadowed `current: T2`. Before the
# fix the fence-blind awk captured the fenced `current: T2` first →
# CURRENT=T2 → non-numeric → false block. Same defect class the matrix parser
# fixed (fence-blind row parsing). This fix removes false blocks, adds none.
h19o=$(make_home)
write_plan "$h19o" "$(matrix_frontmatter true)

Doc note — the task-scale ledger schema (D12) looks like:

$v11_fenced_sdlcstate_shadow

## SDLC State
current: 5
Step 5:
$step5_base

$matrix_complete" > /dev/null
expect_allow "19o fenced ## SDLC State shadow before real section → validates real section (allow)" \
  "$h19o" 'git commit -m "x"'

# 19p — the `## Tasks` extraction is fence-aware from the start: a fenced ```
# example carrying a bogus-status row before the REAL ## Tasks table must not
# raise a false task-ledger finding (the real ledger is valid). Fence-blind,
# both tables' rows would be read and the T9 `doing` row would log a finding.
v11_fenced_tasks_shadow='```
## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T9 | bugfix | tested | example row | doing |
```'
h19p=$(make_home)
write_plan "$h19p" "$(task_frontmatter_rigor tested)

Example ledger:

$v11_fenced_tasks_shadow

$ledger_valid" > /dev/null
expect_allow "19p fenced ## Tasks example before real table → no false finding (fence-aware)" \
  "$h19p" 'git commit -m "x"'

# 19q — a doc file whose ONLY `## SDLC State` occurrence is inside a fenced
# ``` example (no real section) must pass through as NON-CANONICAL (exit 0),
# not be parsed and false-blocked on the now-empty extraction. The presence
# check must be fence-aware too, matching the extraction: a fenced heading is
# documentation, not state. Decision recorded in the plan's ## Assumptions.
v11_fenced_only_sdlcstate="# Some skill doc

Here is how a canonical-sdlc plan records its state:

$v11_fenced_sdlcstate_shadow

That is the schema — this file itself is not a plan and carries no real
SDLC-State section of its own."
h19q=$(make_home)
write_plan "$h19q" "$v11_fenced_only_sdlcstate" > /dev/null
expect_allow "19q fenced-only ## SDLC State (no real section) → pass through as non-canonical" \
  "$h19q" 'git commit -m "x"'

# --- fence-aware epic-plan read in merge-target (review fix) --------------

# An epic project whose epic.plan.md documents a `## SDLC State` example in a
# fenced ``` block (bogus integration-branch: fenced-decoy) BEFORE its real
# section (integration-branch: $1). Fence-blind, the cross-file read picks the
# decoy (head -1) and mis-reports the merge target.
make_epic_project_fenced() {
  local branch="$1" proj
  proj=$(make_project)
  mkdir -p "$proj/.bionic/docs/plans/epic-fix"
  cat > "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" <<EOF
---
canonical_sdlc_version: 12
intent: build
rigor: audited
scale: epic
---
# Epic plan

The epic's state block looks like this:

\`\`\`
## SDLC State
integration-branch: fenced-decoy
current: 1
\`\`\`

## SDLC State
integration-branch: ${branch}
current: 1
EOF
  touch -t 202001010000 "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || \
    touch -d "2020-01-01" "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || true
  echo "$proj"
}

# 19r — the merge-target epic-plan read must be fence-aware, like every other
# SDLC-State extraction this wave. The wave plan's integration-branch matches
# the epic's REAL value (epic/07-x); the fenced decoy (fenced-decoy) must be
# ignored → silent (no finding). Before the fix the fence-blind awk read the
# decoy first (head -1) → mismatch → spurious merge-target finding. Log-only
# blast radius, but the exact defect class this wave eliminated everywhere else.
h19r=$(make_home); p19r=$(make_epic_project_fenced "epic/07-x")
write_project_plan "$p19r" \
  "$(wave_epic_plan 8 "$integrate_body" "$matrix_complete" epic-fix "epic/07-x")" \
  "wave-newest.plan.md" > /dev/null
expect_allow_both "19r fenced ## SDLC State in epic plan → merge-target reads real section (silent)" \
  "$h19r" "$p19r" 'git commit -m "x"'

# ============================================================
# Section 20: intent-scoped Step-5 evidence keys (R7, log-only)
# ============================================================
#
# Plans declare an `intent:` in frontmatter. Two intents carry a
# conditional Step-5 evidence key set, checked LOG-ONLY (D14) at the Verify
# gate — never blocks:
#   - refactor: requires `behavior-preservation:` (non-empty); `compat-matrix:`
#     and `revert-plan:` are optional but must not be present-and-empty.
#   - tune: requires `baseline:`, `target:`, `re-measure:` (all non-empty).
# Any other intent (e.g. build) gets no check at all — this is intent-scoped,
# not a universal Step-5 key like bundle-fresh/drive-check/stack-health. A
# — no audit write, no finding.

echo ""
echo "=== Section 20: intent-scoped Step-5 evidence keys (R7, log-only) ==="

# Counts occurrences of $substr in stderr — for asserting an exact finding
# count (e.g. the tune intent's three missing keys).
expect_finding_count() {
  local label="$1" home_dir="$2" command="$3" substr="$4" expected="$5"
  TOTAL=$((TOTAL + 1))
  run_hook "$home_dir" "$command"
  local count
  count=$(echo "$HOOK_STDERR" | grep -c "$substr") || count=0
  if [ "$HOOK_EXIT" -eq 0 ] && [ "$count" -eq "$expected" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected allow exit 0 + ${expected}x '$substr'): $label"
    echo "  exit=$HOOK_EXIT count=$count stderr='$HOOK_STDERR'"
    FAIL=$((FAIL + 1))
  fi
}


# Frontmatter with a caller-chosen intent (Section 19's frontmatter
# hardcodes intent: build). $1 intent, $2 scale (default wave).
r7_frontmatter() {
  local intent="$1" scale="${2:-wave}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 12\n'
  printf -- 'intent: %s\n' "$intent"
  printf -- 'rigor: audited\n'
  printf -- 'scale: %s\n' "$scale"
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: false\n'
  printf -- '---\n'
}

# A wave plan with the given intent, at the given current/Step-5 body/
# matrix. $1 intent, $2 current, $3 Step-block body, $4 matrix.
r7_wave_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(r7_frontmatter "$1")" "$2" "$2" "$3" "$4"
}

# Refactor Step-5 body with behavior-preservation already satisfied — the
# base for the compat-matrix/revert-plan sub-cases (20c), which isolate
# that one axis by keeping behavior-preservation clean.
r7_refactor_body_ok="$step5_base
  behavior-preservation: suites 211/211 pre @abc, 211/211 post @def"

# --- 20a/20b: refactor — behavior-preservation required ------------------

# 20a — refactor plan, valid tests floor + matrix, NO behavior-preservation
# key → exit 0 + refactor-evidence finding on stderr AND in the audit file.
h20a=$(make_home)
write_plan "$h20a" "$(r7_wave_plan refactor 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_finding "20a refactor plan missing behavior-preservation → finding" \
  "$h20a" 'git commit -m "x"' "canonical-sdlc \[refactor-evidence\]"
h20a2=$(make_home)
write_plan "$h20a2" "$(r7_wave_plan refactor 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_audit_line "20a2 refactor plan missing behavior-preservation → audit file line" \
  "$h20a2" 'git commit -m "x"' "evidence-gate refactor-evidence:"

# 20b — same plan + behavior-preservation present → exit 0, NO finding.
h20b=$(make_home)
write_plan "$h20b" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok" "$matrix_complete")" > /dev/null
expect_allow "20b refactor plan with behavior-preservation → allow, no finding" \
  "$h20b" 'git commit -m "x"'

# --- 20c: refactor — compat-matrix/revert-plan optional-but-not-empty ----

# 20c1 — compat-matrix present but empty → refactor-evidence finding.
h20c1=$(make_home)
write_plan "$h20c1" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok
  compat-matrix:" "$matrix_complete")" > /dev/null
expect_finding "20c1 refactor compat-matrix present but empty → finding" \
  "$h20c1" 'git commit -m "x"' "compat-matrix"

# 20c2 — compat-matrix: n/a: not a migration (non-empty) → clean.
h20c2=$(make_home)
write_plan "$h20c2" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok
  compat-matrix: n/a: not a migration" "$matrix_complete")" > /dev/null
expect_allow "20c2 refactor compat-matrix non-empty n/a → allow, no finding" \
  "$h20c2" 'git commit -m "x"'

# 20c3 — compat-matrix/revert-plan entirely absent → clean (they are
# optional; only presence-and-empty is a finding).
h20c3=$(make_home)
write_plan "$h20c3" "$(r7_wave_plan refactor 5 "$r7_refactor_body_ok" "$matrix_complete")" > /dev/null
expect_allow "20c3 refactor compat-matrix/revert-plan absent → allow, no finding" \
  "$h20c3" 'git commit -m "x"'

# --- 20d: tune — baseline/target/re-measure all required ------------------

# 20d1 — tune plan missing all three keys → exactly THREE tune-evidence
# findings (assert count, not just "at least one").
h20d1=$(make_home)
write_plan "$h20d1" "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_finding_count "20d1 tune plan missing baseline/target/re-measure → 3 findings" \
  "$h20d1" 'git commit -m "x"' "tune-evidence" 3

# 20d2 — tune plan with all three non-empty → clean.
r7_tune_body_ok="$step5_base
  baseline: p95 340ms @abc
  target: p95 <= 200ms
  re-measure: p95 190ms @def"
h20d2=$(make_home)
write_plan "$h20d2" "$(r7_wave_plan tune 5 "$r7_tune_body_ok" "$matrix_complete")" > /dev/null
expect_allow "20d2 tune plan with baseline/target/re-measure → allow, no finding" \
  "$h20d2" 'git commit -m "x"'

# --- 20e: build — intent-scoped, not universal ----------------------------

# 20e — build intent with none of the refactor/tune keys → NO finding (these
# checks are intent-scoped; build never triggers them).
h20e=$(make_home)
write_plan "$h20e" "$(r7_wave_plan build 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_allow "20e build plan with no intent-scoped keys → allow, no finding" \
  "$h20e" 'git commit -m "x"'

# --- 20g/20h: R7 keys are truly log-only (critic Issue 1) ------------------
#
# The universal placeholder ban (the whole-Step-block scan a few hundred
# lines up) used to scan these six intent-scoped keys too, so a
# placeholder R7 value BLOCKED the commit — contradicting the ratified
# log-only contract. R7 keys are exempted from that ban
# (version-gated: v≤10 plans still block on a stray placeholder R7-named
# line — see 20i); validate_intent_evidence itself now treats a placeholder
# value the same as missing/empty, so the finding still fires.

# 20g — refactor plan, behavior-preservation: TODO (placeholder value, not
# missing) → exit 0 + refactor-evidence finding + audit line (was BLOCKED).
h20g=$(make_home)
write_plan "$h20g" "$(r7_wave_plan refactor 5 "$step5_base
  behavior-preservation: TODO" "$matrix_complete")" > /dev/null
expect_finding "20g refactor behavior-preservation: TODO → allow + refactor-evidence finding" \
  "$h20g" 'git commit -m "x"' "canonical-sdlc \[refactor-evidence\]"
h20g2=$(make_home)
write_plan "$h20g2" "$(r7_wave_plan refactor 5 "$step5_base
  behavior-preservation: TODO" "$matrix_complete")" > /dev/null
expect_audit_line "20g2 refactor behavior-preservation: TODO → audit file line" \
  "$h20g2" 'git commit -m "x"' "evidence-gate refactor-evidence:"

# 20h — tune plan, baseline: tbd (placeholder), target/re-measure valid →
# exit 0 + exactly ONE tune-evidence finding (not three — the other two
# keys are present and non-placeholder).
h20h=$(make_home)
write_plan "$h20h" "$(r7_wave_plan tune 5 "$step5_base
  baseline: tbd
  target: p95 <= 200ms
  re-measure: p95 190ms @def" "$matrix_complete")" > /dev/null
expect_finding_count "20h tune baseline: tbd (rest valid) → exactly 1 tune-evidence finding" \
  "$h20h" 'git commit -m "x"' "tune-evidence" 1

# ============================================================
# Section 21: audit dir follows the plan's project (strategy alignment)
# ============================================================
#
# log_finding's audit_dir now walks up from $PLAN's own directory to the
# nearest ancestor containing .bionic/, matching the governing-skill hook's
# find_project_root_from_path strategy — findings live with the project that
# owns the artifact. PROJECT_DIR is the fallback only.
#
# NOTE (pinning, not RED — see plan ## Assumptions): plan discovery is
# rooted at PROJECT_DIR (PLAN_DIRS is built from $HOME/.claude/plans and
# $PROJECT_DIR/...), so in every case constructible through the hook's real
# discovery paths, walk-up resolves to the SAME directory PROJECT_DIR already
# names. Both cases below pass identically before and after the refactor;
# they pin the new code path (and its fallback) rather than catch a bug.

echo ""
echo "=== Section 21: audit dir follows the plan's project (strategy alignment) ==="

# Like run_hook_with_project, but pins CLAUDE_PROJECT_DIR to $2 (the fixture
# project that owns the plan) while the JSON cwd field AND the actual
# invoking shell's cwd are $3 (an unrelated sibling dir) — proving
# log_finding follows the plan's own project via walk-up, never whatever
# directory happened to invoke the hook.
run_hook_project_elsewhere_cwd() {
  local home_dir="$1" project_dir="$2" elsewhere_dir="$3" command="$4"
  local input
  input=$(jq -n --arg c "$command" --arg cwd "$elsewhere_dir" '{tool_input: {command: $c}, cwd: $cwd}')
  local tmp_err
  tmp_err=$(mktemp)
  if (cd "$elsewhere_dir" && HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"); then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

# 21a — fixture project owns the plan; the JSON cwd field and the actual
# process cwd both point at an unrelated sibling temp dir. Asserts the audit
# line lands in the audit file KEYED ON the fixture project (incident 0001:
# under the sandbox HOME, slugged by the fixture root — never inside the
# project tree), and that NO .bionic/ gets created under the sibling (no cwd
# leak). The "nothing under the fixture tree" arm is paired with the presence
# arm on purpose: alone it would pass if the hook wrote nothing at all.
h21a=$(make_home)
fixture21a=$(make_project)
elsewhere21a=$(mktemp -d); cleanup_dirs+=("$elsewhere21a")
write_project_plan "$fixture21a" "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" > /dev/null
TOTAL=$((TOTAL + 1))
run_hook_project_elsewhere_cwd "$h21a" "$fixture21a" "$elsewhere21a" 'git commit -m "x"'
fixture_audit=$(audit_file_for "$h21a" "$fixture21a")
in_tree21a=$(find "$fixture21a" "$elsewhere21a" -name 'sdlc-audit.md' 2>/dev/null)
if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$fixture_audit" ] && grep -q "tune-evidence" "$fixture_audit" \
  && [ ! -d "$elsewhere21a/.bionic" ] && [ -z "$in_tree21a" ]; then
  echo "PASS: 21a audit line follows the plan's fixture project, not the invoking cwd"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected fixture-keyed audit line under HOME + no audit file in any project tree): 21a"
  echo "  exit=$HOOK_EXIT fixture_audit_exists=$([ -f "$fixture_audit" ] && echo yes || echo no) elsewhere_bionic=$([ -d "$elsewhere21a/.bionic" ] && echo yes || echo no) in_tree='$in_tree21a'"
  FAIL=$((FAIL + 1))
fi

# 21b — fail-open fallback: plan reached only via the ~/.claude/plans global
# convention (Section 19/20's usual fixture), whose ancestry has no .bionic/
# directory anywhere above it. audit_root's walk-up exhausts without a match
# and falls back to $PROJECT_DIR (== $h21b here, via the cwd field) — hook
# still exits 0 and still writes the audit line, unblocked.
h21b=$(make_home)
write_plan "$h21b" "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" > /dev/null
expect_audit_line "21b fail-open: no .bionic ancestor above the plan → PROJECT_DIR fallback used" \
  "$h21b" 'git commit -m "x"' "tune-evidence"

# ============================================================
# Section 21c: AC-10 — the audit root is COMPUTED, never discovered
# ============================================================
#
# audit_root now delegates to resolve_project_root, which computes the root
# from `git rev-parse --path-format=absolute --git-common-dir` instead of
# walking the plan's ancestors for an existing `.bionic/`. Consequences:
# a project whose `.bionic/` has never existed still resolves, and every
# linked worktree of one repo answers with the parent repo — one repo, one
# audit file, instead of one per worktree.
#
# Fixture fidelity: real `git init` repos and a real `git worktree add` on
# disk. The behaviour under test is git's own path-format handling, which a
# stubbed `git` cannot reproduce.

echo ""
echo "=== Section 21c: AC-10 computed audit root ==="

# The five criteria run against the SHIPPED text of the function, extracted
# from the hook and eval'd here — not a reimplementation. That seam cannot
# observe that the hook CALLS it, so 21c-e2e below drives the hook through its
# real stdin contract and pins the call site.
ac10_src=$(awk '/^resolve_project_root\(\)/,/^\}/' "$HOOK")
TOTAL=$((TOTAL + 1))
if [ -n "$ac10_src" ]; then
  echo "PASS: 21c0 resolve_project_root extracted from the hook"
  PASS=$((PASS + 1))
  eval "$ac10_src"
else
  echo "FAIL: 21c0 no resolve_project_root() in $HOOK"
  FAIL=$((FAIL + 1))
  # Keep the criteria below individually reportable rather than aborting.
  resolve_project_root() { :; }
fi

# The hook's own comment claims this helper is a byte-identical twin of the
# governing-skill hook's copy. Assert it, so a one-sided edit shows up here
# rather than as two hooks disagreeing about which project owns an artifact.
TOTAL=$((TOTAL + 1))
ac10_twin=$(awk '/^resolve_project_root\(\)/,/^\}/' "$(dirname "$HOOK")/canonical-sdlc-governing-skill.sh")
if [ -n "$ac10_twin" ] && [ "$ac10_src" = "$ac10_twin" ]; then
  echo "PASS: 21c0b resolve_project_root is byte-identical to the governing-skill copy"
  PASS=$((PASS + 1))
else
  echo "FAIL: 21c0b resolve_project_root diverges from the governing-skill copy"
  FAIL=$((FAIL + 1))
fi

ac10_assert() {  # $1 label, $2 expected, $3 actual
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1"
    echo "  expected='$2' actual='$3'"
    FAIL=$((FAIL + 1))
  fi
}

# main: a repo WITH .bionic/ (untracked, so the worktree checkout has none).
# wt:   a linked worktree of main, given its own .bionic/ on purpose — the
#       predecessor's ancestor walk would stop there.
# nb:   a repo where .bionic/ has NEVER existed.
# out:  a plain directory with no repo above it.
# Physical paths (pwd -P): mktemp -d yields /var/... on macOS, a symlink to
# /private/var/..., and git answers with the physical path.
ac10_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac10_tmp")
ac10_main="$ac10_tmp/main"
mkdir -p "$ac10_main/.bionic/docs/plans" "$ac10_main/deep/sub/dir"
git -C "$ac10_main" init -q .
git -C "$ac10_main" commit -q --allow-empty -m init
git -C "$ac10_main" worktree add -q "$ac10_tmp/wt" -b ac10-wt
ac10_wt="$ac10_tmp/wt"
mkdir -p "$ac10_wt/.bionic/docs/plans"
ac10_nb="$ac10_tmp/nobionic"; mkdir -p "$ac10_nb"; git -C "$ac10_nb" init -q .
ac10_out="$ac10_tmp/outside"; mkdir -p "$ac10_out"

ac10_assert "21c1 repo root → repo root" "$ac10_main" \
  "$(resolve_project_root "$ac10_main/.bionic/docs/plans/active.md")"
ac10_assert "21c2 target in a subdirectory → repo root" "$ac10_main" \
  "$(resolve_project_root "$ac10_main/deep/sub/dir/active.md")"
ac10_assert "21c2b cwd in a subdirectory → repo root (not cwd-relative)" "$ac10_main" \
  "$(cd "$ac10_main/deep/sub/dir" && resolve_project_root "$ac10_main/.bionic/docs/plans/active.md")"
ac10_assert "21c3 inside a worktree → parent repo root" "$ac10_main" \
  "$(resolve_project_root "$ac10_wt/.bionic/docs/plans/active.md")"
ac10_assert "21c4 .bionic/ never existed → repo root" "$ac10_nb" \
  "$(resolve_project_root "$ac10_nb/.bionic/docs/plans/active.md")"
ac10_assert "21c5 outside any repo → the supplied fallback" "$ac10_out" \
  "$(resolve_project_root "$ac10_out/notes/active.md" "$ac10_out")"
ac10_assert "21c5b outside any repo, no fallback → cwd" "$ac10_out" \
  "$(cd "$ac10_out" && resolve_project_root "$ac10_out/notes/active.md")"

# --- git < 2.31 (critic K2 / FIX 5) ----------------------------------------
#
# `--path-format` landed in git 2.31; older git rejects it as an unknown option
# and rev-parse exits 129, which the single-branch predecessor could not tell
# apart from "not a repository". The resolver is a deliberately duplicated
# byte-identical twin, and 21c0b asserts that identity — but a sameness check on
# the copy cannot see whether the copy WORKS, so the fallback is driven here
# too rather than assumed from the governing-skill suite.
#
# The shim rejects ONLY `--path-format=absolute` and `exec`s the real git for
# everything else, so these arms exercise git's actual bare-form behaviour:
# RELATIVE inside the main repo, ABSOLUTE from a linked worktree.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]
ac10_oldgit=$(mktemp -d); cleanup_dirs+=("$ac10_oldgit")
ac10_real_git=$(command -v git)
{
  printf '#!/bin/bash\n'
  printf 'for a in "$@"; do\n'
  printf '  [ "$a" = "--path-format=absolute" ] && exit 129\n'
  printf 'done\n'
  printf 'exec %s "$@"\n' "$ac10_real_git"
} > "$ac10_oldgit/git"
chmod +x "$ac10_oldgit/git"

ac10_oldgit_resolve() {  # PATH saved/restored so nothing else in the suite sees the shim
  local saved="$PATH" out
  PATH="$ac10_oldgit:$PATH"
  out=$(resolve_project_root "$@")
  PATH="$saved"
  printf '%s\n' "$out"
}

ac10_assert "21c7 old git: repo root → repo root" "$ac10_main" \
  "$(ac10_oldgit_resolve "$ac10_main/.bionic/docs/plans/active.md")"
ac10_assert "21c8 old git: subdirectory → repo root (relative bare form)" "$ac10_main" \
  "$(ac10_oldgit_resolve "$ac10_main/deep/sub/dir/active.md")"
ac10_assert "21c9 old git: worktree → parent repo root (absolute bare form)" "$ac10_main" \
  "$(ac10_oldgit_resolve "$ac10_wt/.bionic/docs/plans/active.md")"
ac10_assert "21c10 old git: outside any repo → the supplied fallback" "$ac10_out" \
  "$(ac10_oldgit_resolve "$ac10_out/notes/active.md" "$ac10_out")"

# Every answer is an ABSOLUTE path. The naive `dirname $(git rev-parse
# --git-common-dir)` yields `.` and `..`; a criterion accepting a relative
# answer would pass the defect it exists to catch.
TOTAL=$((TOTAL + 1))
ac10_rel=""
for ac10_p in "$ac10_main/.bionic/docs/plans/active.md" \
              "$ac10_main/deep/sub/dir/active.md" \
              "$ac10_wt/.bionic/docs/plans/active.md" \
              "$ac10_nb/.bionic/docs/plans/active.md" \
              "$ac10_out/notes/active.md"; do
  ac10_v=$(cd "$ac10_out" && resolve_project_root "$ac10_p")
  case "$ac10_v" in /*) ;; *) ac10_rel="${ac10_rel} ${ac10_p}=>${ac10_v}" ;; esac
done
if [ -z "$ac10_rel" ]; then
  echo "PASS: 21c6 every resolution is an absolute path"
  PASS=$((PASS + 1))
else
  echo "FAIL: 21c6 relative resolution(s):$ac10_rel"
  FAIL=$((FAIL + 1))
fi

# 21c-e2e — the CALL SITE, driven through the hook's real stdin contract, from
# INSIDE a linked worktree. The plan lives where the governing-skill hook
# demands it live — the MAIN repo's docs root — and the worktree carries a
# newer decoy plan in its own .bionic/docs/plans/. Three arms, asserted
# together:
#   - the decoy is NOT selected (it would block on a placeholder), so
#     PROJECT_DIR/DOCS_ROOT resolved to the main repo, not the worktree;
#   - the finding lands in the audit file keyed on the main repo;
#   - no audit file keyed on the worktree exists.
# The absence arm alone would pass if the hook had written nothing at all.
#
# Step-6 finding C2/S1 rewrote this case's fixture. It used to put the real
# plan INSIDE the worktree's own .bionic/ — a placement the governing-skill
# hook blocks, so the two hooks disagreed about the same repo and no artifact
# location satisfied both. This shape is the reachable one.
h21c=$(make_home)
printf '%s\n' "$(r7_wave_plan tune 5 "$step5_base" "$matrix_complete")" \
  > "$ac10_main/.bionic/docs/plans/active.md"
touch "$ac10_main/.bionic/docs/plans/active.md"
printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 12\nintent: build\nrigor: tested\nscale: wave\n---\n## SDLC State\ncurrent: 5\nStep 5: TODO\n' \
  > "$ac10_wt/.bionic/docs/plans/decoy.md"
touch "$ac10_wt/.bionic/docs/plans/decoy.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$h21c" "$ac10_wt" 'git commit -m "x"'
ac10_main_audit=$(audit_file_for "$h21c" "$ac10_main")
ac10_wt_audit=$(audit_file_for "$h21c" "$ac10_wt")
if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$ac10_main_audit" ] && grep -q "tune-evidence" "$ac10_main_audit" \
   && [ ! -f "$ac10_wt_audit" ]; then
  echo "PASS: 21c-e2e commit from a worktree → main repo's plan, one audit file keyed on the main repo"
  PASS=$((PASS + 1))
else
  echo "FAIL: 21c-e2e commit from a worktree → main repo's plan and audit file"
  echo "  exit=$HOOK_EXIT main_audit=$([ -f "$ac10_main_audit" ] && echo yes || echo no) wt_audit=$([ -f "$ac10_wt_audit" ] && echo yes || echo no)"
  echo "  stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Section 22: rigor-keyed ledger lanes
# ============================================================
#
# Slice 4/1 makes the task-ledger tested floor BLOCKING for THE ADDRESSED
# UNIT ONLY (the T<n> named by `current: T<n>`). For that one task the gate now
# exits 2 when: its row is absent from `## Tasks`; its `- T<n>:` evidence line
# is missing or a placeholder; or its rigor cell fails `effective_row_rigor`
# (a non-empty cell outside tested|peer-reviewed|audited → INVALID). Every OTHER
# row keeps its log-only handling (D14) at this slice — 22a6 pins that scope.

echo ""
echo "=== Section 22: rigor-keyed ledger lanes ==="

# --- 22a: blocking tested floor on the addressed ledger unit --------------

# 22a1 — ## Tasks has no row for the addressed unit (T2) → block.
v22_no_t2_row="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green"
h22a1=$(make_home)
write_plan "$h22a1" "$(task_plan_rigor tested "$v22_no_t2_row")" > /dev/null
expect_block "22a1 addressed unit T2 has no ## Tasks row → block" \
  "$h22a1" 'git commit -m "x"' "no row"

# 22a2 — T2 row present (active) but no `- T2:` evidence line → block.
v22_t2_no_line="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green"
h22a2=$(make_home)
write_plan "$h22a2" "$(task_plan_rigor tested "$v22_t2_no_line")" > /dev/null
expect_block "22a2 addressed unit T2 missing evidence line → block" \
  "$h22a2" 'git commit -m "x"' "evidence line"

# 22a3 — `- T2: pending` (placeholder value) → block.
v22_t2_placeholder="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: pending"
h22a3=$(make_home)
write_plan "$h22a3" "$(task_plan_rigor tested "$v22_t2_placeholder")" > /dev/null
expect_block "22a3 addressed unit T2 placeholder evidence → block" \
  "$h22a3" 'git commit -m "x"' "placeholder"

# 22a4 — honest addressed unit (row + real evidence + valid rigor) → allow.
v22_t2_valid="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: fixed enum check, bash suite 12/12"
h22a4=$(make_home)
write_plan "$h22a4" "$(task_plan_rigor tested "$v22_t2_valid")" > /dev/null
expect_allow "22a4 honest addressed unit T2 → allow" \
  "$h22a4" 'git commit -m "x"'

# 22a5 — the addressed unit's rigor cell is INVALID ('rigorous') → block.
v22_t2_bad_rigor="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | rigorous | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: fixed enum check, bash suite 12/12"
h22a5=$(make_home)
write_plan "$h22a5" "$(task_plan_rigor tested "$v22_t2_bad_rigor")" > /dev/null
expect_block "22a5 addressed unit T2 invalid rigor cell → block" \
  "$h22a5" 'git commit -m "x"' "invalid rigor"

# 22a6 (regression pin) — a broken NON-addressed row (T1 done, no evidence line)
# while the addressed unit T2 is honest → NO block on a NON-audited plan. The
# non-addressed row keeps its log-only handling (this exits 0 with a task-ledger
# finding, not a block), pinning the addressed-unit-only scope of the 4/1
# blocking floor. NB: slice 4/3 makes this same NON-addressed check BLOCKING
# under frontmatter rigor: audited (pinned by 22c3), so this fixture is
# deliberately NON-audited (tested) to keep exercising the surviving log-only
# lane. Tested also keeps every cell at the floor so the 4/8 downgrade gate
# stays silent — the subject here is the missing-evidence log-only path, not a
# downgrade.
v22_nonaddressed_broken="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T2: fixed enum check, bash suite 12/12"
h22a6=$(make_home)
write_plan "$h22a6" "$(task_plan_rigor tested "$v22_nonaddressed_broken")" > /dev/null
expect_finding "22a6 broken non-addressed row (T1) + honest T2 (non-audited) → no block, log-only finding" \
  "$h22a6" 'git commit -m "x"' "task-ledger"

# --- 22b: proof-shape + auditor/critic lanes (slice 4/2) ------------------
#
# Lane scope (D-slice 4/2): the addressed row (any status) AND every OTHER
# row with status `done` are subject to — effective rigor peer-reviewed OR
# audited: evidence must be proof-shaped (is_proof_shaped); done AND rigor
# >= peer-reviewed: evidence must contain "auditor"; done AND rigor audited:
# evidence must ALSO contain "critic". The `tested` floor carries none of
# this — presence + placeholder (4/1) is its whole contract.
#
# These fixtures run at frontmatter rigor: tested (task_plan_rigor tested),
# so each heavier cell (peer-reviewed/audited) is a RAISE above the floor — the
# CELL drives the lane, and the 4/8 downgrade gate never fires (raises are always
# free). This isolates the lane behavior from the floor check. (Was
# task_plan / audited before slice 4/8, where a tested/peer-reviewed cell
# would now be a blocking downgrade and mask the lane under test.)

# 22b1 — addressed row (peer-reviewed, active) with prose evidence (no digit,
# no command token) → block (not proof-shaped).
v22b_t2_prose="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | peer-reviewed | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: implemented and verified manually"
h22b1=$(make_home)
write_plan "$h22b1" "$(task_plan_rigor tested "$v22b_t2_prose")" > /dev/null
expect_block "22b1 addressed row peer-reviewed active prose evidence → block (not proof-shaped)" \
  "$h22b1" 'git commit -m "x"' "not prose"

# 22b2 — same row, evidence is a command + counts → allow (proof-shaped).
v22b_t2_proof="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | peer-reviewed | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: bash test.sh 232/232 green"
h22b2=$(make_home)
write_plan "$h22b2" "$(task_plan_rigor tested "$v22b_t2_proof")" > /dev/null
expect_allow "22b2 addressed row peer-reviewed active proof-shaped evidence → allow" \
  "$h22b2" 'git commit -m "x"'

# 22b3 — a DONE non-addressed row (T1, peer-reviewed) with proof-shaped
# evidence but no 'auditor' token → block (done needs auditor).
v22b_t1_no_auditor="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | peer-reviewed | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash suite 12/12
- T2: fixed enum check, bash suite 12/12"
h22b3=$(make_home)
write_plan "$h22b3" "$(task_plan_rigor tested "$v22b_t1_no_auditor")" > /dev/null
expect_block "22b3 done row peer-reviewed proof-shaped but no auditor token → block" \
  "$h22b3" 'git commit -m "x"' "auditor"

# 22b4 — same row with an 'auditor' token in the evidence → allow.
v22b_t1_auditor="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | peer-reviewed | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 12/12, auditor CONFIRMED
- T2: fixed enum check, bash suite 12/12"
h22b4=$(make_home)
write_plan "$h22b4" "$(task_plan_rigor tested "$v22b_t1_auditor")" > /dev/null
expect_allow "22b4 done row peer-reviewed with auditor token → allow" \
  "$h22b4" 'git commit -m "x"'

# 22b5 — a DONE row at audited rigor with 'auditor' but no 'critic' → block
# (audited done additionally needs critic).
v22b_t1_audited_no_critic="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 12/12 auditor CONFIRMED
- T2: fixed enum check, bash suite 12/12"
h22b5=$(make_home)
write_plan "$h22b5" "$(task_plan_rigor tested "$v22b_t1_audited_no_critic")" > /dev/null
expect_block "22b5 done row audited with auditor but no critic → block" \
  "$h22b5" 'git commit -m "x"' "critic"

# 22b6 — same row with both 'auditor' and 'critic' tokens → allow.
v22b_t1_audited_complete="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 12/12 auditor CONFIRMED, critic no-blocking
- T2: fixed enum check, bash suite 12/12"
h22b6=$(make_home)
write_plan "$h22b6" "$(task_plan_rigor tested "$v22b_t1_audited_complete")" > /dev/null
expect_allow "22b6 done row audited with auditor and critic → allow" \
  "$h22b6" 'git commit -m "x"'

# 22b7 — addressed row at the tested floor (active), plain prose evidence →
# allow (tested demands no proof-shape/auditor/critic; presence+placeholder
# from 4/1 is its whole contract).
v22b_t2_tested_prose="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: reproduced and fixed the off-by-one"
h22b7=$(make_home)
write_plan "$h22b7" "$(task_plan_rigor tested "$v22b_t2_tested_prose")" > /dev/null
expect_allow "22b7 addressed row tested floor prose evidence → allow (no proof-shape demand)" \
  "$h22b7" 'git commit -m "x"'

# 22b8 — proof-shape unit pin: a command word alone (no digit) is not
# proof-shaped, and a digit alone (no command token) is not proof-shaped
# either — both halves of the AND are load-bearing.

v22b_t2_no_digit="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | peer-reviewed | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: bash test.sh all green"
h22b8a=$(make_home)
write_plan "$h22b8a" "$(task_plan_rigor tested "$v22b_t2_no_digit")" > /dev/null
expect_block "22b8a proof-shape pin: command word, no digit → block" \
  "$h22b8a" 'git commit -m "x"' "not prose"

v22b_t2_no_command="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | bugfix | peer-reviewed | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green
- T2: fixed 3 cases by hand"
h22b8b=$(make_home)
write_plan "$h22b8b" "$(task_plan_rigor tested "$v22b_t2_no_command")" > /dev/null
expect_block "22b8b proof-shape pin: digit, no command token → block" \
  "$h22b8b" 'git commit -m "x"' "not prose"

# --- 22c: audited plan-level strictness + wave D7 dispatch-ledger (slice 4/3) -
#
# Part A (task scale): the previously log-only NON-addressed-row ledger-shape
# checks (missing ## Tasks, bad status enum, active/done row missing/placeholder
# evidence) BLOCK under frontmatter rigor: audited and stay log-only otherwise
# (ledger_shape_fail router). Part B (wave scale): validate_dispatch_ledger
# demands a `## Tasks` dispatched-task ledger section on scale:wave +
# rigor:audited + multi_agent:true plans (absent → block; empty/none-dispatched
# → allow; rows validate at TESTED-FLOOR shape only — enum + evidence-line
# presence, NO per-row auditor/critic, plan Assumption A2). Every other plan is
# a guard no-op.

echo ""
echo "=== Section 22c: audited strictness + D7 dispatch-ledger presence ==="

# ---- Part A: task-scale audited plan-level strictness --------------------

# 22c1 — audited task plan, addressed T1 clean + proof-shaped, a second
# (non-addressed) row T2 with status 'wip' (bad enum) → BLOCK (audited promotes
# the enum check). Isolated: the addressed unit T1 is clean so the block is the
# enum promotion, not the addressed floor. T1's cell is `audited` (= the
# frontmatter floor) so it is not itself a 4/8 downgrade — the subject is T2's
# status promotion. T1's evidence is proof-shaped for the audited-active lane.
v22c_bad_enum="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | audited | do the thing | active |
| T2 | build | tested | second thing | wip |

## SDLC State

scale: task
current: T1

- T1: bash suite 12/12 green"
h22c1=$(make_home)
write_plan "$h22c1" "$(task_plan "$v22c_bad_enum")" > /dev/null
expect_block "22c1 audited task plan, non-addressed row bad status enum → block" \
  "$h22c1" 'git commit -m "x"' "invalid status"

# 22c2 — same fixture at frontmatter rigor peer-reviewed → log-only finding, NOT
# a block (the router stays log-only off audited).
h22c2=$(make_home)
write_plan "$h22c2" "$(task_plan_rigor peer-reviewed "$v22c_bad_enum")" > /dev/null
expect_finding "22c2 same fixture at peer-reviewed → finding (still log-only)" \
  "$h22c2" 'git commit -m "x"' "task-ledger"

# 22c3 — audited task plan, addressed T1 clean, non-addressed T2 status done with
# NO `- T2:` evidence line → BLOCK (audited promotes the missing-evidence check).
# T1's cell is `audited` (= the frontmatter floor) so it is not itself a 4/8
# downgrade; its evidence is proof-shaped for the audited-active lane. The
# subject is T2's promoted missing-evidence block.
v22c_done_no_ev="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | audited | do the thing | active |
| T2 | build | tested | second thing | done |

## SDLC State

scale: task
current: T1

- T1: bash suite 12/12 green"
h22c3=$(make_home)
write_plan "$h22c3" "$(task_plan "$v22c_done_no_ev")" > /dev/null
expect_block "22c3 audited task plan, non-addressed done row missing evidence line → block" \
  "$h22c3" 'git commit -m "x"' "no evidence"

# 22c4 — same fixture at frontmatter rigor tested → log-only finding, NOT a block.
h22c4=$(make_home)
write_plan "$h22c4" "$(task_plan_rigor tested "$v22c_done_no_ev")" > /dev/null
expect_finding "22c4 same fixture at tested → finding (still log-only)" \
  "$h22c4" 'git commit -m "x"' "task-ledger"

# ---- Part B: wave-scale D7 dispatched-task ledger presence ---------------

# A WAVE frontmatter carrying an explicit multi_agent field — the D7
# dispatch-ledger guard fires ONLY on audited + multi_agent:true + wave.
# frontmatter sets NO multi_agent, so every prior wave fixture (19a/b/c,
# 19r, Section 20) is a guaranteed guard no-op. $1 rigor (default audited),
# $2 multi_agent (default true).
d7_wave_frontmatter() {
  local rigor="${1:-audited}" multi="${2:-true}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 12\n'
  printf -- 'intent: build\n'
  printf -- 'rigor: %s\n' "$rigor"
  printf -- 'scale: wave\n'
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: false\n'
  printf -- 'multi_agent: %s\n' "$multi"
  printf -- '---\n'
}

# A wave plan at current: 5 reaching the dispatcher with the SAME valid
# Step-5 body + matrix as 19b (so the ONLY variable under test is the
# dispatched-task ledger; validate_dispatch_ledger runs at the top of
# dispatch_modern, before the matrix machinery). $1 = ## Tasks section text
# (empty omits it); $2 = extra ## SDLC State lines, e.g. a `- T<n>:` evidence
# line (empty omits); $3 rigor (default audited); $4 multi_agent (default true).
d7_wave_plan() {
  local tasks="$1" extra_state="$2" rigor="${3:-audited}" multi="${4:-true}"
  printf '%s\n' "$(d7_wave_frontmatter "$rigor" "$multi")"
  [ -n "$tasks" ] && printf '%s\n\n' "$tasks"
  printf '## SDLC State\ncurrent: 5\nStep 5:\n%s\n' "$step5_base"
  [ -n "$extra_state" ] && printf '%s\n' "$extra_state"
  printf '\n%s\n' "$matrix_complete"
}

# 22c5 — audited multi_agent wave with NO ## Tasks section → block (D7 presence).
h22c5=$(make_home)
write_plan "$h22c5" "$(d7_wave_plan "" "")" > /dev/null
expect_block "22c5 audited multi_agent wave with no ## Tasks → block (D7 presence)" \
  "$h22c5" 'git commit -m "x"' "dispatched-task ledger"

# 22c6 — WITH a ## Tasks section, header-only + a `none dispatched` line, zero
# T-rows → allow (section present suffices; the parser needs no row).
tasks_none="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|

none dispatched — the orchestrator appends one row per dispatched task-shaped unit."
h22c6=$(make_home)
write_plan "$h22c6" "$(d7_wave_plan "$tasks_none" "")" > /dev/null
expect_allow "22c6 audited multi_agent wave with none-dispatched ## Tasks → allow" \
  "$h22c6" 'git commit -m "x"'

# 22c7 — ## Tasks with one dispatched row (done) AND a matching `- T1:` evidence
# line in ## SDLC State → allow. NOTE: the line carries NO auditor/critic token
# yet it passes — tested-floor shape only at wave scale (pins Assumption A2).
tasks_one_done="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | audited | dispatched slice | done |"
h22c7=$(make_home)
write_plan "$h22c7" "$(d7_wave_plan "$tasks_one_done" "- T1: bash suite 9/9 green")" > /dev/null
expect_allow "22c7 audited multi_agent wave dispatched T1 + evidence line → allow (tested-floor shape, no auditor/critic)" \
  "$h22c7" 'git commit -m "x"'

# 22c8 — ## Tasks with a dispatched row (done) but NO `- T1:` evidence line
# anywhere in ## SDLC State → block.
h22c8=$(make_home)
write_plan "$h22c8" "$(d7_wave_plan "$tasks_one_done" "")" > /dev/null
expect_block "22c8 audited multi_agent wave dispatched T1 with no evidence line → block" \
  "$h22c8" 'git commit -m "x"' "evidence line"

# 22c9 — NON-audited wave (rigor peer-reviewed) with NO ## Tasks → allow (the
# guard excludes non-audited plans).
h22c9=$(make_home)
write_plan "$h22c9" "$(d7_wave_plan "" "" peer-reviewed true)" > /dev/null
expect_allow "22c9 non-audited (peer-reviewed) wave with no ## Tasks → allow (guard excludes)" \
  "$h22c9" 'git commit -m "x"'

# 22c10 — audited wave with multi_agent: false and NO ## Tasks → allow (the guard
# excludes single-agent plans).
h22c10=$(make_home)
write_plan "$h22c10" "$(d7_wave_plan "" "" audited false)" > /dev/null
expect_allow "22c10 audited wave with multi_agent:false, no ## Tasks → allow (guard excludes)" \
  "$h22c10" 'git commit -m "x"'

# 22c11 (self-reference pin) — reproduce THIS wave-05 plan's exact ## Tasks shape
# (header + `|---|` separator + blank + a `none dispatched — ...` prose line,
# zero T-rows) on an audited multi_agent wave fixture → allow. This is the shape
# the deployed NEW hook must accept when wave-05 itself advances past the pointer
# steps into the dispatcher.
tasks_selfref="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|

none dispatched — D7 ledger opens empty; the orchestrator appends one row
per dispatched task-shaped unit (slices ledger under Step-4 evidence, not
here, unless dispatched as discrete task-shaped work)."
h22c11=$(make_home)
write_plan "$h22c11" "$(d7_wave_plan "$tasks_selfref" "")" > /dev/null
expect_allow "22c11 self-reference pin — THIS plan's exact ## Tasks shape (zero T-rows) → allow" \
  "$h22c11" 'git commit -m "x"'

# ---- 22d: per-row rigor resolution (slice 4/4, R4) ------------------------
#
# effective_row_rigor resolves cell-first: a non-empty, enum-valid cell wins
# outright — it does NOT blend with, or get overridden by, the frontmatter
# rigor. Frontmatter rigor only supplies the fallback when the cell is empty
# (and 'tested' is the final fallback under an unset/invalid frontmatter
# rigor). 22d1/22d2 pin cell-wins-over-frontmatter in both directions
# (lighter cell overrides heavier frontmatter, and vice versa). 22d3/22d4 pin
# the empty-cell inheritance path. 22d5 pins that the cell alone drives the
# audited lane (auditor+critic), independent of frontmatter. 22d6 is a
# confirmation-vs-actual probe on a NON-addressed row's off-enum rigor cell —
# see its comment for the finding.

echo ""
echo "=== Section 22d: per-row rigor resolution (R4) ==="

# 22d1 — frontmatter rigor tested, addressed row cell peer-reviewed (heavier),
# weak prose evidence → block. The row CELL overrides the lighter frontmatter:
# proof-shape is demanded because the cell says peer-reviewed, not because of
# the (lighter) frontmatter.
v22d1_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | peer-reviewed | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: fixed it manually"
h22d1=$(make_home)
write_plan "$h22d1" "$(task_plan_rigor tested "$v22d1_body")" > /dev/null
expect_block "22d1 frontmatter tested, cell peer-reviewed (heavier), prose evidence → block (cell wins)" \
  "$h22d1" 'git commit -m "x"' "not prose"

# 22d2 — frontmatter rigor audited (task_plan hardcodes it), addressed row
# cell tested (lighter than the frontmatter floor), plain honest one-line
# evidence → this is a DOWNGRADE (A15: the per-row cell is a FLOOR; a cell
# below the frontmatter rigor must be waived). WITHOUT a waiver marker on the
# `- T1:` line it BLOCKS; WITH one it runs at the (lower) tested lane, so the
# plain evidence is fine and it allows. (Was expect_allow under the pre-A15
# "cell wins freely downward" model; slice 4/8 makes downward a recorded
# decision. 22d2/22d2b are the split; 22f1/22f2 restate the same contract
# in the dedicated floor block.)
v22d2_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: reproduced and fixed the boundary case"
h22d2=$(make_home)
write_plan "$h22d2" "$(task_plan "$v22d2_body")" > /dev/null
expect_block "22d2 frontmatter audited, cell tested (downgrade), no waiver → block (floor)" \
  "$h22d2" 'git commit -m "x"' "lowers rigor"

# 22d2b — same fixture with a Waiver-Protocol marker on the `- T1:` line → allow.
# The recorded downgrade runs at the cell's tested lane, so the plain one-line
# evidence satisfies the (tested) contract.
v22d2b_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: reproduced and fixed the boundary case, waiver: dana 2026-07-19 genuine bugfix"
h22d2b=$(make_home)
write_plan "$h22d2b" "$(task_plan "$v22d2b_body")" > /dev/null
expect_allow "22d2b frontmatter audited, cell tested (downgrade), WITH waiver → allow (recorded, runs at tested lane)" \
  "$h22d2b" 'git commit -m "x"'

# 22d3 — frontmatter rigor peer-reviewed, addressed row cell EMPTY (missing
# field-4 value), weak prose evidence → block. An empty cell inherits the
# frontmatter rigor (peer-reviewed), so proof-shape is demanded.
v22d3_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix |  | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: fixed it manually"
h22d3=$(make_home)
write_plan "$h22d3" "$(task_plan_rigor peer-reviewed "$v22d3_body")" > /dev/null
expect_block "22d3 frontmatter peer-reviewed, cell empty, prose evidence → block (inherits frontmatter)" \
  "$h22d3" 'git commit -m "x"' "not prose"

# 22d4 — frontmatter rigor tested, addressed row cell EMPTY, weak prose
# evidence → allow. An empty cell inherits tested, the floor.
v22d4_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix |  | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: fixed it manually"
h22d4=$(make_home)
write_plan "$h22d4" "$(task_plan_rigor tested "$v22d4_body")" > /dev/null
expect_allow "22d4 frontmatter tested, cell empty, prose evidence → allow (inherits tested floor)" \
  "$h22d4" 'git commit -m "x"'

# 22d5 — frontmatter rigor tested (lighter), addressed row cell audited
# (heavier), status done: proof-shaped evidence + auditor + critic tokens →
# allow; drop the critic token (same frontmatter, same cell) → block. Pins
# that the CELL alone drives the audited lane, independent of frontmatter.
v22d5_body_complete="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix enum | done |

## SDLC State

scale: task
current: T1

- T1: bash test.sh 12/12 auditor CONFIRMED, critic no-blocking"
h22d5a=$(make_home)
write_plan "$h22d5a" "$(task_plan_rigor tested "$v22d5_body_complete")" > /dev/null
expect_allow "22d5a frontmatter tested, cell audited, done, proof+auditor+critic → allow (cell drives lane)" \
  "$h22d5a" 'git commit -m "x"'

v22d5_body_no_critic="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix enum | done |

## SDLC State

scale: task
current: T1

- T1: bash test.sh 12/12 auditor CONFIRMED"
h22d5b=$(make_home)
write_plan "$h22d5b" "$(task_plan_rigor tested "$v22d5_body_no_critic")" > /dev/null
expect_block "22d5b same, drop critic token → block (cell audited lane still demands it)" \
  "$h22d5b" 'git commit -m "x"' "critic"

# 22d6 — an off-enum rigor cell 'reviewed' on a NON-addressed 'done' row.
# effective_row_rigor("reviewed") resolves to the INVALID sentinel. Slice 4/4
# pinned (as expect_allow) that this evaded detection entirely: INVALID was
# only ever explicitly checked on the ADDRESSED unit's own row (4/1's
# `if [ "$eff" = "INVALID" ]` block), so the non-addressed done-row path called
# apply_rigor_lanes(id, status, "INVALID", ev) directly and its case arms —
# matching only tested|peer-reviewed|audited — fell through as a silent no-op:
# no block, and (unlike the ledger_shape_fail-routed defects) no log-only
# finding either.
#
# Slice 4/6 closes that gap: the non-addressed done-row path now guards for
# eff=INVALID BEFORE calling apply_rigor_lanes, mirroring the addressed unit's
# 4/1 INVALID block. A malformed rigor cell makes the row's lane indeterminate
# — you cannot resolve which evidence contract applies — so it is a hard
# STRUCTURAL error that blocks UNCONDITIONALLY at ANY frontmatter rigor, NOT
# routed through the audited-only ledger_shape_fail. 22d6a/b/c pin the block at
# audited / tested / peer-reviewed frontmatter respectively (proving "at any
# rigor"); 22d6d/e are controls proving ONLY the INVALID sentinel blocks — a
# valid enum cell and an empty (inherits-frontmatter) cell both still allow.
v22d6_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | reviewed | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 12/12 auditor CONFIRMED, critic no-blocking
- T2: fixed enum check, bash suite 12/12"
h22d6a=$(make_home)
write_plan "$h22d6a" "$(task_plan "$v22d6_body")" > /dev/null
expect_block "22d6a frontmatter audited, non-addressed off-enum rigor cell → block (INVALID lane is a hard structural error)" \
  "$h22d6a" 'git commit -m "x"' "invalid rigor"

h22d6b=$(make_home)
write_plan "$h22d6b" "$(task_plan_rigor tested "$v22d6_body")" > /dev/null
expect_block "22d6b frontmatter tested, non-addressed off-enum rigor cell → block (blocks at any rigor, not just audited)" \
  "$h22d6b" 'git commit -m "x"' "invalid rigor"

# 22d6c — same off-enum cell, frontmatter peer-reviewed → block. Third rigor
# level, proving the INVALID guard fires UNCONDITIONALLY (a, b, c together
# cover audited / tested / peer-reviewed).
h22d6c=$(make_home)
write_plan "$h22d6c" "$(task_plan_rigor peer-reviewed "$v22d6_body")" > /dev/null
expect_block "22d6c frontmatter peer-reviewed, non-addressed off-enum rigor cell → block (blocks at any rigor)" \
  "$h22d6c" 'git commit -m "x"' "invalid rigor"

# 22d6d — negative control: a VALID enum cell (peer-reviewed) on a non-addressed
# done row, with proof-shaped + auditor evidence, frontmatter tested → allow.
# The fix targets ONLY the INVALID sentinel; a well-formed heavier cell resolves
# its lane and (evidence being proof-shaped + auditor-named) passes cleanly.
v22d6d_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | peer-reviewed | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 12/12 auditor CONFIRMED
- T2: fixed enum check, bash suite 12/12"
h22d6d=$(make_home)
write_plan "$h22d6d" "$(task_plan_rigor tested "$v22d6d_body")" > /dev/null
expect_allow "22d6d control: valid peer-reviewed cell on non-addressed done row, proof+auditor evidence → allow (only INVALID blocks)" \
  "$h22d6d" 'git commit -m "x"'

# 22d6e — empty-cell control: an EMPTY rigor cell on a non-addressed done row
# inherits the frontmatter rigor (tested, the floor), with honest one-line
# evidence → allow. Empty ≠ INVALID: the empty cell resolves via inheritance,
# not the malformation sentinel, so no structural block fires.
v22d6e_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix |  | fix the frontmatter parser | done |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: reproduced and fixed the boundary case
- T2: fixed enum check, bash suite 12/12"
h22d6e=$(make_home)
write_plan "$h22d6e" "$(task_plan_rigor tested "$v22d6e_body")" > /dev/null
expect_allow "22d6e control: empty rigor cell on non-addressed done row inherits tested floor, honest evidence → allow (empty ≠ INVALID)" \
  "$h22d6e" 'git commit -m "x"'

# 22d6f/g/h — slice 4/7 closes the residual left by 4/6: an off-enum rigor cell
# blocked only on the addressed unit (any status, 4/1) and on non-addressed DONE
# rows (4/6), but a non-addressed ACTIVE or PENDING row with an off-enum cell
# still passed SILENTLY — its lane was never resolved, so no block and no
# finding. The spec's semantic model bans unknown cell values as a blocking
# malformation "at any rigor" with NO status qualifier (whole-value enum
# equality, the exact idiom used for the status cell, which is validated per-row
# regardless of status). 4/7 consolidates the INVALID check into ONE per-row
# guard that runs before the status-based branching, so a malformed rigor cell
# blocks UNIFORMLY on any row (addressed or not; done, active, pending, dropped)
# at any frontmatter rigor. 22d6f (active) and 22d6g (pending) are the residuals
# this slice closes; 22d6h is a negative control proving an EMPTY cell on an
# active row still inherits and allows (empty ≠ INVALID — active rows without a
# done claim are not over-blocked).

# 22d6f — non-addressed ACTIVE row with an off-enum rigor cell 'reviewed',
# frontmatter tested, addressed unit T2 honest → block. Pre-4/7 this passed
# silently (the active branch never resolves the cell).
v22d6f_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | reviewed | fix the frontmatter parser | active |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: reworking the parser
- T2: fixed enum check, bash suite 12/12"
h22d6f=$(make_home)
write_plan "$h22d6f" "$(task_plan_rigor tested "$v22d6f_body")" > /dev/null
expect_block "22d6f frontmatter tested, non-addressed ACTIVE off-enum rigor cell → block (INVALID blocks regardless of status)" \
  "$h22d6f" 'git commit -m "x"' "invalid rigor"

# 22d6g — non-addressed PENDING row with an off-enum rigor cell, frontmatter
# peer-reviewed, addressed unit T2 honest → block. Pending rows carry no
# evidence line, so pre-4/7 the whole row was skipped and the bad cell never
# surfaced.
v22d6g_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | reviewed | fix the frontmatter parser | pending |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T2: fixed enum check, bash suite 12/12"
h22d6g=$(make_home)
write_plan "$h22d6g" "$(task_plan_rigor peer-reviewed "$v22d6g_body")" > /dev/null
expect_block "22d6g frontmatter peer-reviewed, non-addressed PENDING off-enum rigor cell → block (INVALID blocks even on a pending row)" \
  "$h22d6g" 'git commit -m "x"' "invalid rigor"

# 22d6h — negative control: non-addressed ACTIVE row with an EMPTY rigor cell,
# honest evidence, frontmatter tested → allow. The empty cell inherits the
# frontmatter (tested, the floor); empty ≠ INVALID, so the per-row guard does
# not fire and an active row without a done claim is not over-blocked.
v22d6h_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix |  | fix the frontmatter parser | active |
| T2 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: reworking the parser
- T2: fixed enum check, bash suite 12/12"
h22d6h=$(make_home)
write_plan "$h22d6h" "$(task_plan_rigor tested "$v22d6h_body")" > /dev/null
expect_allow "22d6h control: empty rigor cell on non-addressed active row inherits tested floor, honest evidence → allow (empty ≠ INVALID)" \
  "$h22d6h" 'git commit -m "x"'

# ---- 22f: row rigor is a FLOOR — downgrade blocks unless waived (slice 4/8) --
#
# A15 (user-ratified, momentous): the per-row `rigor` cell is a FLOOR unified
# with the run-rigor floor model. A cell that RAISES a row above the
# frontmatter rigor is always allowed (the cell drives the heavier lane —
# 22d1/22d5 already pin this). A cell that LOWERS a row below the frontmatter
# rigor is a DOWNGRADE: it BLOCKS (exit 2) UNLESS the row's `- T<n>:` evidence
# line carries a whole-word `waiver` marker (Waiver Protocol), in which case the
# row runs at the (lower) cell lane. The gate fires exactly where the rigor
# lanes apply — the addressed unit (any status) and non-addressed `done` rows
# with real evidence — after the presence/placeholder/INVALID checks, so a
# missing/placeholder-evidence or malformed-cell block still wins. 22f7 also
# pins the F3 word-boundary fix on the critic/auditor lane tokens.

echo ""
echo "=== Section 22f: row rigor is a floor — downgrade blocks unless waived ==="

# 22f1 — frontmatter audited, ADDRESSED row cell tested (downgrade), real
# non-placeholder prose evidence, NO waiver → block. This is the critic's F1
# repro: under the pre-A15 model the tested cell "won" downward and this
# allowed; the floor rule flips it to a block.
v22f1_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: reproduced and fixed the boundary case"
h22f1=$(make_home)
write_plan "$h22f1" "$(task_plan "$v22f1_body")" > /dev/null
expect_block "22f1 audited frontmatter, addressed tested cell (downgrade), no waiver → block" \
  "$h22f1" 'git commit -m "x"' "lowers rigor"

# 22f2 — same, but the `- T1:` line carries a Waiver-Protocol marker → allow
# (recorded downgrade; runs at the tested lane so the prose evidence is fine).
v22f2_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: reproduced and fixed the boundary case, waiver: dana 2026-07-19 genuine bugfix"
h22f2=$(make_home)
write_plan "$h22f2" "$(task_plan "$v22f2_body")" > /dev/null
expect_allow "22f2 audited frontmatter, addressed tested cell + waiver → allow (recorded downgrade)" \
  "$h22f2" 'git commit -m "x"'

# 22f3 — frontmatter tested, addressed row cell audited (RAISE), done, evidence
# proof-shaped + auditor + critic → allow. Raising above the floor is always
# free; the cell drives the heavier (audited) lane.
v22f3_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix enum | done |

## SDLC State

scale: task
current: T1

- T1: bash test.sh 12/12 auditor CONFIRMED, critic no-blocking"
h22f3=$(make_home)
write_plan "$h22f3" "$(task_plan_rigor tested "$v22f3_body")" > /dev/null
expect_allow "22f3 tested frontmatter, addressed audited cell (raise), proof+auditor+critic → allow" \
  "$h22f3" 'git commit -m "x"'

# 22f4 — frontmatter peer-reviewed, addressed row cell tested (downgrade). No
# waiver → block; with waiver → allow (runs at the tested lane).
v22f4_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: fixed it by hand"
h22f4a=$(make_home)
write_plan "$h22f4a" "$(task_plan_rigor peer-reviewed "$v22f4_body")" > /dev/null
expect_block "22f4a peer-reviewed frontmatter, addressed tested cell (downgrade), no waiver → block" \
  "$h22f4a" 'git commit -m "x"' "lowers rigor"

v22f4b_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix enum | active |

## SDLC State

scale: task
current: T1

- T1: fixed it by hand, waiver: dana 2026-07-19 quick bugfix"
h22f4b=$(make_home)
write_plan "$h22f4b" "$(task_plan_rigor peer-reviewed "$v22f4b_body")" > /dev/null
expect_allow "22f4b peer-reviewed frontmatter, addressed tested cell + waiver → allow" \
  "$h22f4b" 'git commit -m "x"'

# 22f5 — frontmatter audited, addressed row cell audited (EQUAL, no downgrade),
# done, proper evidence → allow. The floor comparison is strict-less-than, so an
# equal cell is never a downgrade.
v22f5_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix enum | done |

## SDLC State

scale: task
current: T1

- T1: bash test.sh 12/12 auditor CONFIRMED, critic no-blocking"
h22f5=$(make_home)
write_plan "$h22f5" "$(task_plan "$v22f5_body")" > /dev/null
expect_allow "22f5 audited frontmatter, addressed audited cell (equal) → allow (no downgrade)" \
  "$h22f5" 'git commit -m "x"'

# 22f6 — NON-addressed done row (T1) at frontmatter audited with cell
# peer-reviewed (downgrade). Addressed unit T2 is honest and non-downgrade
# (cell audited). No waiver on T1 → block; with a waiver on T1 → allow (T1 runs
# at the peer-reviewed lane, so its proof-shaped + auditor evidence suffices).
v22f6_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | peer-reviewed | fix the parser | done |
| T2 | build | audited | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 9/9 auditor CONFIRMED
- T2: bash suite 12/12 green"
h22f6a=$(make_home)
write_plan "$h22f6a" "$(task_plan "$v22f6_body")" > /dev/null
expect_block "22f6a audited frontmatter, non-addressed done peer-reviewed cell (downgrade), no waiver → block" \
  "$h22f6a" 'git commit -m "x"' "lowers rigor"

v22f6b_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | peer-reviewed | fix the parser | done |
| T2 | build | audited | fix enum | active |

## SDLC State

scale: task
current: T2

- T1: bash test.sh 9/9 auditor CONFIRMED, waiver: dana 2026-07-19 scoped down to peer-reviewed
- T2: bash suite 12/12 green"
h22f6b=$(make_home)
write_plan "$h22f6b" "$(task_plan "$v22f6b_body")" > /dev/null
expect_allow "22f6b same, waiver on the non-addressed done row → allow (runs at peer-reviewed lane)" \
  "$h22f6b" 'git commit -m "x"'

# 22f7 (F3 word-boundary) — audited addressed done row whose evidence contains
# `critical` (which embeds the substring `critic`) and `auditor CONFIRMED` but
# NO standalone `critic` token → block on the critic lane. Under the pre-fix
# unanchored `grep -q "critic"` the `critical` substring satisfied the lane and
# this allowed; the whole-word `grep -Ewq 'critic'` fix restores the block.
# Adding a standalone `critic no-blocking` token then allows.
v22f7a_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix the parser | done |

## SDLC State

scale: task
current: T1

- T1: bash test.sh 9/9, auditor CONFIRMED, fixed a critical path bug"
h22f7a=$(make_home)
write_plan "$h22f7a" "$(task_plan "$v22f7a_body")" > /dev/null
expect_block "22f7a audited done row, 'critical' (no standalone critic) → block (word-boundary critic token)" \
  "$h22f7a" 'git commit -m "x"' "critic"

v22f7b_body="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | audited | fix the parser | done |

## SDLC State

scale: task
current: T1

- T1: bash test.sh 9/9, auditor CONFIRMED, fixed a critical path bug, critic no-blocking"
h22f7b=$(make_home)
write_plan "$h22f7b" "$(task_plan "$v22f7b_body")" > /dev/null
expect_allow "22f7b same evidence + standalone 'critic no-blocking' token → allow" \
  "$h22f7b" 'git commit -m "x"'

# ============================================================
# Section 23: canonical_sdlc_version — exactly one supported value
# ============================================================
#
# The hook supports canonical_sdlc_version: 12 and nothing else. Every other
# value blocks with exit 2 and a message naming the value found. One
# table-driven case over representative bad values — an older number, a much
# older number, a legacy single digit, a far-future number, an empty value, and
# non-numeric garbage — because there is one behavior here, not one per value.
#
# The version check sits ahead of every shape check, so these fixtures carry a
# valid ## SDLC State: what is under test is the version, not the evidence.

echo ""
echo "=== Section 23: canonical_sdlc_version — exactly one supported value ==="

versioned_plan() {  # $1 = the canonical_sdlc_version value to declare
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: %s\n' "$1"
  printf -- 'intent: build\nrigor: tested\nscale: wave\n'
  printf -- '---\n'
  printf -- '## SDLC State\ncurrent: 3\nStep 3: .bionic/docs/plans/wave-01.plan.md\n'
}

for bad_version in 11 9 2 99 "" banana 12.0 v12; do
  h=$(make_home)
  write_plan "$h" "$(versioned_plan "$bad_version")" > /dev/null
  expect_block "unsupported canonical_sdlc_version '${bad_version:-<empty>}' → block, naming the value found" \
    "$h" 'git commit -m "x"' "canonical_sdlc_version: '${bad_version}'"
done

# A plan with NO canonical_sdlc_version line at all is not a special case: it
# reads as the empty value and blocks the same way.
h23none=$(make_home)
write_plan "$h23none" "---
governing-skill: canonical-sdlc
intent: build
rigor: tested
scale: wave
---
## SDLC State
current: 3
Step 3: .bionic/docs/plans/wave-01.plan.md" > /dev/null
expect_block "absent canonical_sdlc_version → block" \
  "$h23none" 'git commit -m "x"' "the only supported version"

# The supported value passes the version gate (proved by reaching — and
# satisfying — the evidence checks beyond it).
h23ok=$(make_home)
write_plan "$h23ok" "$(versioned_plan 12)" > /dev/null
expect_allow "canonical_sdlc_version: 12 → allow" "$h23ok" 'git commit -m "x"'

# ============================================================
# Section 24: AC-13 — the plan-search fail-open
# ============================================================
#
# This hook fails open DIFFERENTLY from the governing-skill hook. It never
# tests `.bionic/` at all: every candidate plan directory is skipped by
# `[ -d "$d" ] || continue`, PLAN comes back empty, and the commit passes
# ungated. Closing the governing-skill hook's fail-open does nothing for this
# one, which is why the two are driven independently here.
#
# The distinction the AC draws, applied to a commit gate:
#   ABSENT     — no plan anywhere. Not a canonical-sdlc run. Never blocks;
#                this is every commit in every project that does not use the
#                lifecycle, and a wall there would be intolerable.
#   MISPLACED  — a plan carrying the run marker exists in the project, but
#                outside every directory the gate searches. The gate is
#                silently disabled and the commit would sail through. Blocks,
#                naming where the plan belongs.
echo ""
echo "=== Section 24: AC-13 — misplaced plan blocks, absent plan never does ==="

s24_marked_plan() {  # a plan carrying the run-state marker + a satisfied state
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf -- 'canonical_sdlc_version: 12\nintent: build\nrigor: tested\nscale: wave\n---\n'
  printf -- '## SDLC State\ncurrent: 3\nStep 3: .bionic/docs/plans/wave-01.plan.md\n'
}

echo "-- c1: ABSENCE never blocks --"
# A project with no .bionic/ at all and no plan file anywhere. The single most
# common commit in the world; it must pass, silently.
s24_h1=$(make_home)
s24_p1=$(mktemp -d); cleanup_dirs+=("$s24_p1")
mkdir -p "$s24_p1/src"
printf 'echo hi\n' > "$s24_p1/src/main.sh"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h1" "$s24_p1" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: no .bionic/, no plan anywhere → allow, silently"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): no .bionic/, no plan anywhere"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# .bionic/docs/plans/ exists but is empty — a project that has run Step 0 and
# not yet written a plan. Still absence, still no block.
s24_h1b=$(make_home)
s24_p1b=$(make_project)
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h1b" "$s24_p1b" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: empty .bionic/docs/plans/ → allow, silently"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): empty .bionic/docs/plans/"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- c2: MISPLACEMENT blocks, naming the correct path --"
# The legacy layout, and the shape a moved-or-renamed tree leaves behind: a
# real canonical-sdlc plan the gate cannot see.
s24_h2=$(make_home)
s24_p2=$(mktemp -d); cleanup_dirs+=("$s24_p2")
mkdir -p "$s24_p2/docs/bionic/plans/epic-01-demo"
s24_marked_plan > "$s24_p2/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h2" "$s24_p2" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && echo "$HOOK_STDERR" | grep -q "misplaced" \
   && echo "$HOOK_STDERR" | grep -qF "$s24_p2/.bionic/docs/plans/"; then
  echo "PASS: misplaced plan → block, naming the correct path"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block naming $s24_p2/.bionic/docs/plans/): misplaced plan"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# The identical plan in the right place is found and gated normally — proof the
# block above is about WHERE the file is, not about the file.
s24_h3=$(make_home)
s24_p3=$(make_project)
s24_marked_plan > "$s24_p3/.bionic/docs/plans/wave-01-x.plan.md"
expect_allow "the same plan under .bionic/docs/plans/ → found and gated, allow" \
  "$s24_h3" 'git commit -m "x"'

echo "-- c3: unmarked files are unaffected --"
# A *.plan.md with no canonical_sdlc_version is not a canonical-sdlc run
# artifact. Plenty of projects have plan-shaped markdown; none of it is this
# hook's business.
s24_h4=$(make_home)
s24_p4=$(mktemp -d); cleanup_dirs+=("$s24_p4")
mkdir -p "$s24_p4/notes"
printf '# Some plan\n\nnot a canonical-sdlc artifact\n' > "$s24_p4/notes/roadmap.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h4" "$s24_p4" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: unmarked *.plan.md → allow, silently"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): unmarked *.plan.md"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# A FENCED example of the frontmatter is documentation. Only the leading block
# counts — the recurring trap in this repo is a parser that reads fenced
# examples as real declarations.
s24_h5=$(make_home)
s24_p5=$(mktemp -d); cleanup_dirs+=("$s24_p5")
mkdir -p "$s24_p5/docs"
{ printf '# How to write a plan\n\n```\n---\ncanonical_sdlc_version: 12\n---\n```\n'; } \
  > "$s24_p5/docs/example.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h5" "$s24_p5" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: fenced frontmatter example → allow, silently"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): fenced frontmatter example"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- c4: elsewhere under the docs root is PLACED, not misplaced --"
# <docs-root>/spikes/ and <docs-root>/record/ hold real artifacts carrying this
# frontmatter. The governing-skill hook treats the whole docs root as placed;
# this hook must agree, or the two would disagree about the same file.
s24_h6=$(make_home)
s24_p6=$(make_project)
mkdir -p "$s24_p6/.bionic/docs/spikes"
s24_marked_plan > "$s24_p6/.bionic/docs/spikes/spike-x.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h6" "$s24_p6" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: marked plan under <docs-root>/spikes/ → placed, allow"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): marked plan under <docs-root>/spikes/"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- c5: the named path follows docs-root: in config.yaml --"
s24_h7=$(make_home)
s24_p7=$(mktemp -d); cleanup_dirs+=("$s24_p7")
mkdir -p "$s24_p7/.bionic" "$s24_p7/.bionic/docs/plans/epic-01-demo"
printf 'docs-root: custom/docs\n' > "$s24_p7/.bionic/config.yaml"
s24_marked_plan > "$s24_p7/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h7" "$s24_p7" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && echo "$HOOK_STDERR" | grep -qF "$s24_p7/custom/docs/plans/"; then
  echo "PASS: block names the CONFIGURED docs root, not a hardcoded .bionic/"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block naming $s24_p7/custom/docs/plans/): configured docs-root"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- c6: a non-commit command is never touched by any of this --"
s24_h8=$(make_home)
expect_allow "non-commit command in the c2 misplaced project → allow" \
  "$s24_h8" 'git status'

echo "-- c7: a NON-EMPTY ~/.claude/plans must not make the sweep unreachable --"
# Step-6 finding C1/S2. The guard on this whole block used to be "no plan was
# found in ANY searched directory", and the FIRST directory searched is the
# global, project-agnostic ~/.claude/plans/. One unrelated .md there — the
# harness's own plan mode writes into exactly that directory — made $PLAN
# non-empty and the block dead. Two such files were sitting on the developing
# machine, so the branch AC-13 added had never executed in production.
#
# Every other runner in this suite pins HOME to make_home(), which creates an
# EMPTY ~/.claude/plans/. That fixture substitutes away the precondition under
# test — the recorded seam-blindness class. These cases put a file there on
# purpose. The guard is now scoped to the PROJECT plan directories.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]
s24_h9=$(make_home)
printf '# just a note\n' > "$s24_h9/.claude/plans/stray.md"
s24_p9=$(mktemp -d); cleanup_dirs+=("$s24_p9")
mkdir -p "$s24_p9/docs/bionic/plans/epic-01-demo"
s24_marked_plan > "$s24_p9/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h9" "$s24_p9" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && echo "$HOOK_STDERR" | grep -q "misplaced" \
   && echo "$HOOK_STDERR" | grep -qF "$s24_p9/.bionic/docs/plans/"; then
  echo "PASS: misplaced plan blocks even with a non-empty ~/.claude/plans"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block): misplaced plan with a non-empty ~/.claude/plans"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# The widened guard must not widen the BLOCK. A project whose plan is correctly
# placed has a project plan, so the sweep never runs — regardless of what the
# global directory holds.
s24_h10=$(make_home)
printf '# just a note\n' > "$s24_h10/.claude/plans/stray.md"
s24_p10=$(make_project)
s24_marked_plan > "$s24_p10/.bionic/docs/plans/wave-01-x.plan.md"
touch "$s24_p10/.bionic/docs/plans/wave-01-x.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h10" "$s24_p10" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: correctly-placed project plan + non-empty ~/.claude/plans → no false block"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): correctly-placed project plan + non-empty ~/.claude/plans"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# ABSENCE still never blocks, even though the sweep now runs in this state.
s24_h11=$(make_home)
printf '# just a note\n' > "$s24_h11/.claude/plans/stray.md"
s24_p11=$(mktemp -d); cleanup_dirs+=("$s24_p11")
mkdir -p "$s24_p11/src"
printf 'echo hi\n' > "$s24_p11/src/main.sh"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s24_h11" "$s24_p11" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: no project plan, nothing misplaced, non-empty ~/.claude/plans → allow"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): absence with a non-empty ~/.claude/plans"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Section 25: C2/S1 — the two hooks name ONE root per repo
# ============================================================
#
# The governing-skill hook resolves the project root with resolve_project_root
# (`--git-common-dir`, i.e. the MAIN repo even from inside a linked worktree).
# This gate derived PROJECT_DIR — and therefore DOCS_ROOT, PLAN_DIRS and the
# AC-13 misplacement sweep's root — from CLAUDE_PROJECT_DIR/.cwd/pwd, i.e. the
# WORKTREE. Slice 1 migrated only audit_root().
#
# The consequence was that in a linked worktree NO artifact placement satisfied
# both hooks: put the plan where the governing hook demands (the main repo) and
# every commit from the worktree ran ungated; put it in the worktree so the gate
# finds it and every artifact write was blocked. canonical-sdlc ships a
# `use_worktree` flag, so this is the lifecycle's own normal mode.
#
# Fixture fidelity: a real `git init` + `git worktree add`, like Section 21c —
# the behaviour under test is git's own --git-common-dir handling.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]

echo ""
echo "=== Section 25: one root per repo across both hooks (worktrees) ==="

s25_plan() {  # a canonical plan whose current step evidence is a placeholder
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 12\n'
  printf -- 'intent: build\nrigor: tested\nscale: wave\n'
  printf -- 'deploy_target: none\nuse_worktree: true\nhas_ui: false\n---\n'
  printf -- '## SDLC State\ncurrent: 5\nStep 5: TODO\n'
}

s25_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25_tmp")
s25_main="$s25_tmp/main"
mkdir -p "$s25_main/.bionic/docs/plans"
git -C "$s25_main" init -q .
git -C "$s25_main" commit -q --allow-empty -m init
git -C "$s25_main" worktree add -q "$s25_tmp/wt" -b s25-wt
s25_wt="$s25_tmp/wt"
s25_plan > "$s25_main/.bionic/docs/plans/wave-01-x.plan.md"

echo "-- 25a: a commit FROM the worktree is gated against the main repo's plan --"
s25_h1=$(make_home)
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s25_h1" "$s25_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && echo "$HOOK_STDERR" | grep -q "placeholder" \
   && echo "$HOOK_STDERR" | grep -qF "$s25_main/.bionic/docs/plans/wave-01-x.plan.md"; then
  echo "PASS: 25a commit from a linked worktree is gated by the main repo's plan"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block naming the main repo's plan): 25a worktree commit"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- 25b: control — the identical commit from the MAIN repo --"
s25_h2=$(make_home)
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s25_h2" "$s25_main" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] && echo "$HOOK_STDERR" | grep -q "placeholder"; then
  echo "PASS: 25b commit from the main repo blocks identically"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block): 25b main-repo commit"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- 25c: the misplacement sweep also walks the MAIN repo, not the worktree --"
# Same shape, no plan anywhere the gate searches, and a marked plan sitting
# outside the docs root in the MAIN repo. Both the sweep's root and the docs
# root it names must be the main repo's.
s25_tmp2=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$s25_tmp2")
s25_main2="$s25_tmp2/main"
mkdir -p "$s25_main2/notes"
git -C "$s25_main2" init -q .
git -C "$s25_main2" commit -q --allow-empty -m init
git -C "$s25_main2" worktree add -q "$s25_tmp2/wt" -b s25-wt2
s25_wt2="$s25_tmp2/wt"
s25_marked_plan_body() {
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf -- 'canonical_sdlc_version: 12\nintent: build\nrigor: tested\nscale: wave\n---\n'
  printf -- '## SDLC State\ncurrent: 3\nStep 3: .bionic/docs/plans/wave-01.plan.md\n'
}
s25_marked_plan_body > "$s25_main2/notes/rogue.plan.md"
s25_h3=$(make_home)
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s25_h3" "$s25_wt2" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && echo "$HOOK_STDERR" | grep -q "misplaced" \
   && echo "$HOOK_STDERR" | grep -qF "$s25_main2/notes/rogue.plan.md" \
   && echo "$HOOK_STDERR" | grep -qF "$s25_main2/.bionic/docs/plans/"; then
  echo "PASS: 25c sweep from a worktree finds the main repo's misplaced plan"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block naming the main repo's paths): 25c worktree sweep"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- 25e: ONE file, BOTH hooks, one worktree — the two must agree --"
# A19: every worktree fixture in this tree had asked ONE hook about the
# placement convenient to that hook, and the two suites' answers contradicted
# each other while both stayed green. This case puts a single artifact path in
# front of both binaries in the order the lifecycle actually uses them:
#   1. the governing-skill hook REFUSES the worktree-local placement and names
#      the main repo's docs root;
#   2. it ACCEPTS the placement it named;
#   3. this gate, invoked from the worktree, gates the commit against that same
#      file.
# Before the C2/S1 repair, (3) was exit 0 — obey (1) and every commit from a
# worktree ran ungated.
s25_gov_hook="$(dirname "$HOOK")/canonical-sdlc-governing-skill.sh"
s25_gov_home=$(make_home)   # keeps the governing hook's audit writes off the real ~/.claude
s25_run_write() {  # $1=file path, $2=content → S25_GOV_EXIT / S25_GOV_STDERR
  local input tmp_err
  input=$(jq -n --arg p "$1" --arg c "$2" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  tmp_err=$(mktemp)
  if HOME="$s25_gov_home" bash "$s25_gov_hook" <<< "$input" >/dev/null 2>"$tmp_err"; then
    S25_GOV_EXIT=0
  else
    S25_GOV_EXIT=$?
  fi
  S25_GOV_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}
s25_artifact='---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-01-demo
wave: wave-01-x
canonical_sdlc_version: 12
intent: build
rigor: tested
scale: wave
cleanup_on_finish: true
use_worktree: true
surface_type: none
language: none
has_ui: false
multi_agent: false
deploy_target: none
model_plan: orchestrator=fable-5-high
---

## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

## SDLC State
current: 5
Step 5: TODO
'
s25_run_write "$s25_wt/.bionic/docs/plans/epic-01-demo/both.plan.md" "$s25_artifact"
TOTAL=$((TOTAL + 1))
if [ "$S25_GOV_EXIT" -eq 2 ] && echo "$S25_GOV_STDERR" | grep -qF "$s25_main/.bionic/docs"; then
  echo "PASS: 25e1 governing hook refuses the worktree-local placement, names the main repo"
  PASS=$((PASS + 1))
else
  echo "FAIL: 25e1 governing hook on a worktree-local artifact"
  echo "  exit=$S25_GOV_EXIT stderr='$S25_GOV_STDERR'"
  FAIL=$((FAIL + 1))
fi

mkdir -p "$s25_main/.bionic/docs/plans/epic-01-demo"
s25_run_write "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md" "$s25_artifact"
TOTAL=$((TOTAL + 1))
if [ "$S25_GOV_EXIT" -eq 0 ]; then
  echo "PASS: 25e2 governing hook accepts the placement it named"
  PASS=$((PASS + 1))
else
  echo "FAIL: 25e2 governing hook rejects the placement it named"
  echo "  exit=$S25_GOV_EXIT stderr='$S25_GOV_STDERR'"
  FAIL=$((FAIL + 1))
fi

printf '%s' "$s25_artifact" > "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md"
touch "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md"
s25_h5=$(make_home)
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s25_h5" "$s25_wt" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 2 ] \
   && echo "$HOOK_STDERR" | grep -q "placeholder" \
   && echo "$HOOK_STDERR" | grep -qF "$s25_main/.bionic/docs/plans/epic-01-demo/both.plan.md"; then
  echo "PASS: 25e3 the gate, from the worktree, gates the SAME file the governing hook accepted"
  PASS=$((PASS + 1))
else
  echo "FAIL: 25e3 the gate does not see the file the governing hook accepted"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- 25f: git < 2.31 — the two hooks still agree on one root --"
# FIX 1 and FIX 5 meet here. Under old git the resolver's primary branch fails,
# so if the fallback did not exist the gate would keep PROJECT_DIR at the
# worktree and C2/S1 would be reopened on every pre-2.31 machine — a green
# 25a would be proving nothing about them. Same fixture, same assertion, one
# variable changed.
# [WALL: hooks/canonical-sdlc-evidence-gate.sh]
s25_h6=$(make_home)
TOTAL=$((TOTAL + 1))
s25_saved_path="$PATH"
PATH="$ac10_oldgit:$PATH"
run_hook_with_project "$s25_h6" "$s25_wt" 'git commit -m "x"'
PATH="$s25_saved_path"
if [ "$HOOK_EXIT" -eq 2 ] \
   && echo "$HOOK_STDERR" | grep -q "placeholder" \
   && echo "$HOOK_STDERR" | grep -qF "$s25_main/.bionic/docs/plans/"; then
  echo "PASS: 25f old git — worktree commit still gated by the main repo's plan"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected block naming the main repo): 25f old-git worktree commit"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

echo "-- 25d: a non-repo project dir still resolves to itself (fallback intact) --"
# resolve_project_root falls back to the supplied value when git cannot answer,
# so every non-repo fixture in this suite keeps its previous meaning.
s25_h4=$(make_home)
s25_p4=$(make_project)
s24_marked_plan > "$s25_p4/.bionic/docs/plans/wave-01-x.plan.md"
TOTAL=$((TOTAL + 1))
run_hook_with_project "$s25_h4" "$s25_p4" 'git commit -m "x"'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
  echo "PASS: 25d non-repo project dir resolves to itself, plan still found"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected allow): 25d non-repo project dir"
  echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
