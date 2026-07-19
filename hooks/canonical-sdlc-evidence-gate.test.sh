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

# ============================================================
# Section 1: non-commit commands always allowed
# ============================================================

echo ""
echo "=== Section 1: Non-commit commands pass through ==="

h1=$(make_home)
# Seed a plan that WOULD block if the command were a commit.
write_plan "$h1" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null

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
write_plan "$h3" "# plan

## SDLC State
mode: overnight
current: 5
Phase 1: /path/to/ideate.md
Phase 2: /path/to/spec.md
Phase 3: ~/.claude/plans/this.md
Phase 4: git worktree at /tmp/wt
Phase 5: tests passing, commit abc123

## Other section" > /dev/null

# Step-vocabulary variant (new plans) — must be accepted equally.
h3b=$(make_home)
write_plan "$h3b" "# plan (new vocabulary)

## SDLC State
mode: full
current: 5
Step 1: /path/to/ideate.md
Step 2: /path/to/spec.md
Step 3: ~/.claude/plans/this.md
Step 4: git worktree at /tmp/wt
Step 5: tests passing, commit def456

## Other section" > /dev/null
expect_allow "Step N: vocabulary — allowed" "$h3b" 'git commit -m "x"'

# Mixed Phase/Step — legacy plan that partially migrated. The current
# step's line must exist under either prefix; hook accepts either.
h3c=$(make_home)
write_plan "$h3c" "## SDLC State
current: 5
Phase 1: done
Phase 2: done
Step 5: mixed-vocab evidence" > /dev/null
expect_allow "mixed Phase/Step with Step for current — allowed" "$h3c" 'git commit -m "x"'
expect_allow "valid phase 5 evidence — allow" "$h3" 'git commit -m "phase 5 done"'

h3b=$(make_home)
write_plan "$h3b" "## SDLC State
current: 8b
Phase 8b: critic report attached in docs/review.md" > /dev/null
expect_allow "valid phase 8b evidence — allow" "$h3b" 'git commit -m "critic done"'

h3c=$(make_home)
write_plan "$h3c" "## SDLC State
current: 10
- Phase 10: commit SHA abc123 body written" > /dev/null
expect_allow "bulleted Phase line — allow" "$h3c" 'git commit -m "x"'

# ============================================================
# Section 4: malformed / missing SDLC State pieces
# ============================================================

echo ""
echo "=== Section 4: Malformed SDLC State — blocked ==="

h4=$(make_home)
write_plan "$h4" "## SDLC State
# no current line, no phase lines

## Next section" > /dev/null
expect_block "missing 'current: N' line" "$h4" 'git commit -m "x"' "missing a valid 'current: N'"

h4b=$(make_home)
write_plan "$h4b" "## SDLC State
current: 5
Phase 1: done
Phase 2: done
# no Phase 5 line" > /dev/null
expect_block "no matching Step N line (legacy Phase lines don't match)" "$h4b" 'git commit -m "x"' "no 'Step 5:' line"

h4c=$(make_home)
write_plan "$h4c" "## SDLC State
current: five
Phase 5: something" > /dev/null
expect_block "non-numeric current" "$h4c" 'git commit -m "x"' "missing a valid 'current: N'"

# ============================================================
# Section 5: empty / placeholder evidence — blocked
# ============================================================

echo ""
echo "=== Section 5: Placeholder evidence — blocked ==="

h5=$(make_home)
write_plan "$h5" "## SDLC State
current: 5
Phase 5:   " > /dev/null
expect_block "empty evidence line" "$h5" 'git commit -m "x"' "is empty"

for token in TODO pending "in progress" XXX TBD placeholder; do
  h=$(make_home)
  write_plan "$h" "## SDLC State
current: 5
Phase 5: $token" > /dev/null
  expect_block "placeholder '$token'" "$h" 'git commit -m "x"' "placeholder"
done

# Case-insensitive placeholder match. Under whole-value equality the ENTIRE
# trimmed value must equal a token, so the fixture is the bare token 'Todo'
# (was "Todo — still writing", which is prose that merely starts with the
# token — legal under the new contract; see 5e).
h5b=$(make_home)
write_plan "$h5b" "## SDLC State
current: 5
Phase 5: Todo" > /dev/null
expect_block "placeholder 'Todo' (mixed case, bare token)" "$h5b" 'git commit -m "x"' "placeholder"

# --- whole-value equality: the placeholder ban matches only when the whole
# trimmed, lowercased value EQUALS a token (todo/pending/in progress/
# inprogress/xxx/tbd/placeholder). A token appearing as a substring of a
# longer value is legal evidence.

# 5c — whole-line 'Step 5: pending' (single-line value) → block.
h5c=$(make_home)
write_plan "$h5c" "## SDLC State
current: 5
Step 5: pending" > /dev/null
expect_block "whole-line 'Step 5: pending' → block" "$h5c" 'git commit -m "x"' "placeholder"

# 5d — trim + lowercase before comparison: '  Pending  ' (padded, mixed case)
# as a continuation value still equals the token → block.
h5d=$(make_home)
write_plan "$h5d" "## SDLC State
current: 5
Step 5:
  readback:   Pending  " > /dev/null
expect_block "padded mixed-case 'readback:   Pending  ' → block" "$h5d" 'git commit -m "x"' "placeholder"

# 5e — a value that merely CONTAINS a token as a substring is legal:
# 'resolved all TODOs from the last review' (contains 'todo') → allow. Under
# the OLD substring ban this was a false block.
h5e=$(make_home)
write_plan "$h5e" "## SDLC State
current: 5
Step 5: resolved all TODOs from the last review" > /dev/null
expect_allow "substring-only 'resolved all TODOs' → allow (whole-value equality)" \
  "$h5e" 'git commit -m "x"'

# 5f — a continuation key whose whole value equals a token still blocks:
# 'stack-health: pending' (value 'pending') → block.
h5f=$(make_home)
write_plan "$h5f" "## SDLC State
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
write_plan "$h6" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null
expect_block "cd && git commit" "$h6" 'cd /tmp && git commit -m "x"' "placeholder"
expect_block "git add && git commit" "$h6" 'git add . && git commit -m "x"' "placeholder"

# False-positive check: quoted "git commit" as prose shouldn't trigger
# gate on its own, but a real `git commit` in the same command does.
h6b=$(make_home)
write_plan "$h6b" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null
expect_allow "echo only, no real commit" "$h6b" 'echo "we will git commit later"'

# ============================================================
# Section 7: newest-plan-wins
# ============================================================

echo ""
echo "=== Section 7: Newest plan file is the one enforced ==="

h7=$(make_home)
# Older plan with valid state
write_plan "$h7" "## SDLC State
current: 5
Phase 5: tests green" "old.md" > /dev/null
# Make old.md older than now.
touch -t 202001010000 "$h7/.claude/plans/old.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h7/.claude/plans/old.md" 2>/dev/null || true
# Newer plan with bad state
write_plan "$h7" "## SDLC State
current: 5
Phase 5: TODO" "new.md" > /dev/null
expect_block "newest plan rules — bad state blocks even with valid older plan" \
  "$h7" 'git commit -m "x"' "placeholder"

# Inverse: newer plan without ## SDLC State lets commit pass even if
# an older plan has bad state.
h7b=$(make_home)
write_plan "$h7b" "## SDLC State
current: 5
Phase 5: TODO" "old-bad.md" > /dev/null
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
write_project_plan "$p8a" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null
expect_block_both "project-local plan (bad) blocks with no global plan" \
  "$h8a" "$p8a" 'git commit -m "x"' "placeholder"

# 8b — project-local plan alone, global empty: good evidence allows.
h8b=$(make_home); p8b=$(make_project)
write_project_plan "$p8b" "## SDLC State
current: 5
Phase 5: commit abc123 tests green" > /dev/null
expect_allow_both "project-local plan (good) allows with no global plan" \
  "$h8b" "$p8b" 'git commit -m "x"'

# 8c — both plans exist, project is newer → project wins.
h8c=$(make_home); p8c=$(make_project)
write_plan "$h8c" "## SDLC State
current: 5
Phase 5: commit xyz green" "old-global.md" > /dev/null
touch -t 202001010000 "$h8c/.claude/plans/old-global.md" 2>/dev/null || \
  touch -d "2020-01-01" "$h8c/.claude/plans/old-global.md" 2>/dev/null || true
write_project_plan "$p8c" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null
expect_block_both "newer project plan (bad) wins over older global (good)" \
  "$h8c" "$p8c" 'git commit -m "x"' "placeholder"

# 8d — both plans exist, global is newer → global wins.
h8d=$(make_home); p8d=$(make_project)
write_project_plan "$p8d" "## SDLC State
current: 5
Phase 5: TODO" "old-proj.md" > /dev/null
touch -t 202001010000 "$p8d/.bionic/docs/plans/old-proj.md" 2>/dev/null || \
  touch -d "2020-01-01" "$p8d/.bionic/docs/plans/old-proj.md" 2>/dev/null || true
write_plan "$h8d" "## SDLC State
current: 5
Phase 5: commit xyz green" > /dev/null
expect_allow_both "newer global plan (good) wins over older project (bad)" \
  "$h8d" "$p8d" 'git commit -m "x"'

# 8e — project dir lacks .bionic/docs/plans/: hook falls back to global.
h8e=$(make_home)
p8e=$(mktemp -d); cleanup_dirs+=("$p8e") # no .bionic/docs/plans/ inside
write_plan "$h8e" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null
expect_block_both "project without .bionic/docs/plans/ falls back to global plan" \
  "$h8e" "$p8e" 'git commit -m "x"' "placeholder"

# 8f — CLAUDE_PROJECT_DIR unset: original behavior (global only).
h8f=$(make_home)
write_plan "$h8f" "## SDLC State
current: 5
Phase 5: TODO" > /dev/null
expect_block "CLAUDE_PROJECT_DIR unset: still gates on global plan" \
  "$h8f" 'git commit -m "x"' "placeholder"

# 8g — also covers superpowers convention.
h8g=$(make_home); p8g=$(mktemp -d); cleanup_dirs+=("$p8g")
mkdir -p "$p8g/docs/superpowers/plans"
printf '## SDLC State\ncurrent: 5\nPhase 5: TODO\n' > "$p8g/docs/superpowers/plans/active.md"
touch "$p8g/docs/superpowers/plans/active.md"
expect_block_both "docs/superpowers/plans/ plan is honored alongside bionic" \
  "$h8g" "$p8g" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 9: v2 evidence schema — shape validation
# ============================================================
#
# When frontmatter declares `evidence_schema: v2`, the hook performs
# per-step shape checks on top of the existing presence/placeholder
# rules. Plans with `evidence_schema: legacy` (or absent — the default
# for pre-v2 plans) keep the original presence-only behavior. See
# canonical-sdlc-autonomous-redesign.md §2.1.

echo ""
echo "=== Section 9: v2 evidence_schema shape validation ==="

# Shared helper: build a v2-frontmatter prefix block that the hook
# parses for `evidence_schema` (and `deploy_target` for Step 13).
v2_frontmatter() {
  local schema="$1" deploy="${2:-none}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 2
evidence_schema: ${schema}
deploy_target: ${deploy}
---
EOF
}

# 9a — legacy (evidence_schema: legacy) → existing presence-only path.
# A free-form Step 4 line is fine; no shape complaint.
h9a=$(make_home)
write_plan "$h9a" "$(v2_frontmatter legacy)
## SDLC State
current: 4
Phase 4: worktree at /path, base SHA abc123" > /dev/null
expect_allow "v2-frontmatter with evidence_schema: legacy → no shape check" \
  "$h9a" 'git commit -m "x"'

# 9b — evidence_schema absent → defaults to legacy behavior.
h9b=$(make_home)
write_plan "$h9b" "---
governing-skill: canonical-sdlc
mode: autonomous
---

## SDLC State
current: 4
Phase 4: worktree at /path, base SHA abc123" > /dev/null
expect_allow "frontmatter without evidence_schema → legacy behavior" \
  "$h9b" 'git commit -m "x"'

# 9c — evidence_schema: v2, Step 4 in v2 fields form, all required
# fields present → allow.
h9c=$(make_home)
write_plan "$h9c" "$(v2_frontmatter v2)
## SDLC State
current: 4
Step 4:
  worktree: /Users/x/.worktrees/feature-x
  base-sha: abc1234abc1234abc1234abc1234abc1234abc1
  branch: feature-x" > /dev/null
expect_allow "v2 Step 4 with all required fields → allow" \
  "$h9c" 'git commit -m "x"'

# 9d — v2, Step 4 missing 'base-sha:' → block, error names base-sha.
h9d=$(make_home)
write_plan "$h9d" "$(v2_frontmatter v2)
## SDLC State
current: 4
Step 4:
  worktree: /Users/x/.worktrees/feature-x
  branch: feature-x" > /dev/null
expect_block "v2 Step 4 missing base-sha → block" \
  "$h9d" 'git commit -m "x"' "base-sha"

# 9e — v2, Step 7 with all four fields, pass==total → allow.
h9e=$(make_home)
write_plan "$h9e" "$(v2_frontmatter v2)
## SDLC State
current: 7
Step 7:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-7" > /dev/null
expect_allow "v2 Step 7 with full shape → allow" \
  "$h9e" 'git commit -m "x"'

# 9f — v2, Step 7 missing 'pass:' → block, error names pass.
h9f=$(make_home)
write_plan "$h9f" "$(v2_frontmatter v2)
## SDLC State
current: 7
Step 7:
  cmd: bash test.sh
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-7" > /dev/null
expect_block "v2 Step 7 missing pass field → block" \
  "$h9f" 'git commit -m "x"' "pass"

# 9g — v2, Step 7 with pass != total → block, error mentions pass and total.
h9g=$(make_home)
write_plan "$h9g" "$(v2_frontmatter v2)
## SDLC State
current: 7
Step 7:
  cmd: bash test.sh
  pass: 330
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-7" > /dev/null
expect_block "v2 Step 7 pass != total → block" \
  "$h9g" 'git commit -m "x"' "pass"

# 9h — v2, Step 6 with 'n/a: <reason>' → allow (Step 6 accepts n/a).
h9h=$(make_home)
write_plan "$h9h" "$(v2_frontmatter v2)
## SDLC State
current: 6
Step 6:
  n/a: no UI; agent-skills:browser-testing-with-devtools sufficient" > /dev/null
expect_allow "v2 Step 6 with n/a → allow" \
  "$h9h" 'git commit -m "x"'

# 9i — v2, Step 6 with neither devtools-trace nor n/a → block.
h9i=$(make_home)
write_plan "$h9i" "$(v2_frontmatter v2)
## SDLC State
current: 6
Step 6:
  notes: skipped" > /dev/null
expect_block "v2 Step 6 missing devtools-trace and n/a → block" \
  "$h9i" 'git commit -m "x"' "devtools-trace"

# 9j — v2, Step 11 with 'n/a: PR-less workflow' → allow.
h9j=$(make_home)
write_plan "$h9j" "$(v2_frontmatter v2)
## SDLC State
current: 11
Step 11:
  n/a: PR-less workflow" > /dev/null
expect_allow "v2 Step 11 with n/a: PR-less workflow → allow" \
  "$h9j" 'git commit -m "x"'

# 9k — v2, Step 11 with 'pr: <url>' → allow.
h9k=$(make_home)
write_plan "$h9k" "$(v2_frontmatter v2)
## SDLC State
current: 11
Step 11:
  pr: https://github.com/example/repo/pull/42" > /dev/null
expect_allow "v2 Step 11 with pr → allow" \
  "$h9k" 'git commit -m "x"'

# 9l — v2, Step 13 with 'n/a: <reason>' AND deploy_target: none → allow.
h9l=$(make_home)
write_plan "$h9l" "$(v2_frontmatter v2 none)
## SDLC State
current: 13
Step 13:
  n/a: no deploy target" > /dev/null
expect_allow "v2 Step 13 with n/a + deploy_target=none → allow" \
  "$h9l" 'git commit -m "x"'

# 9m — v2, Step 13 with 'n/a' but deploy_target: k8s → block (n/a only
# valid when deploy_target is none).
h9m=$(make_home)
write_plan "$h9m" "$(v2_frontmatter v2 k8s)
## SDLC State
current: 13
Step 13:
  n/a: skipped" > /dev/null
expect_block "v2 Step 13 n/a with deploy_target=k8s → block" \
  "$h9m" 'git commit -m "x"' "deploy_target"

# 9n — v2, Step 13 with deploy/verified-at/monitor + deploy_target: k8s
# → allow.
h9n=$(make_home)
write_plan "$h9n" "$(v2_frontmatter v2 k8s)
## SDLC State
current: 13
Step 13:
  deploy: prod
  verified-at: 2026-05-02T18:00:00Z
  monitor: https://grafana.example.com/d/foo" > /dev/null
expect_allow "v2 Step 13 full deploy fields + deploy_target=k8s → allow" \
  "$h9n" 'git commit -m "x"'

# 9o — v2, pointer step (Step 5) — single-line free-form is acceptable.
# Pointer steps (1, 2, 3, 5, 8, 8b) skip shape check in v1; presence-only.
h9o=$(make_home)
write_plan "$h9o" "$(v2_frontmatter v2)
## SDLC State
current: 5
Step 5: /.bionic/docs/plans/wave-04.plan.md#phase-5" > /dev/null
expect_allow "v2 Step 5 (pointer step) free-form → allow (no shape check)" \
  "$h9o" 'git commit -m "x"'

# 9p — v2, Step 8b (adversarial) is a pointer step — single-line allowed.
h9p=$(make_home)
write_plan "$h9p" "$(v2_frontmatter v2)
## SDLC State
current: 8b
Step 8b: /.bionic/docs/plans/wave-04.plan.md#step-8b-findings" > /dev/null
expect_allow "v2 Step 8b (pointer step) → allow" \
  "$h9p" 'git commit -m "x"'

# 9q — v2, Step 10 with all required fields → allow.
h9q=$(make_home)
write_plan "$h9q" "$(v2_frontmatter v2)
## SDLC State
current: 10
Step 10:
  commit: abc1234abc1234abc1234abc1234abc1234abc1
  subject: feat(thing): do the thing
  files: 5" > /dev/null
expect_allow "v2 Step 10 with required fields → allow" \
  "$h9q" 'git commit -m "x"'

# 9r — v2, Step 10 missing 'commit:' → block.
h9r=$(make_home)
write_plan "$h9r" "$(v2_frontmatter v2)
## SDLC State
current: 10
Step 10:
  subject: feat(thing): do the thing
  files: 5" > /dev/null
expect_block "v2 Step 10 missing commit field → block" \
  "$h9r" 'git commit -m "x"' "commit"

# 9s — v2, Step 12 with all required fields → allow.
h9s=$(make_home)
write_plan "$h9s" "$(v2_frontmatter v2)
## SDLC State
current: 12
Step 12:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: yes" > /dev/null
expect_allow "v2 Step 12 with required fields → allow" \
  "$h9s" 'git commit -m "x"'

# 9t — placeholder check still applies under v2 (existing behavior).
h9t=$(make_home)
write_plan "$h9t" "$(v2_frontmatter v2)
## SDLC State
current: 4
Step 4: TODO" > /dev/null
expect_block "v2 Step 4 with placeholder TODO → block (presence layer still active)" \
  "$h9t" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 10: v3 canonical_sdlc_version shape validation
# ============================================================
#
# When frontmatter declares canonical_sdlc_version: 3, the hook applies
# the renumbered v3 shape switch. v2 (evidence_schema: v2) plans
# continue to use the original switch.

echo ""
echo "=== Section 10: v3 canonical_sdlc_version shape validation ==="

v3_frontmatter() {
  local deploy="${1:-none}" use_wt="${2:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 3
deploy_target: ${deploy}
use_worktree: ${use_wt}
---
EOF
}

# 10a — v3 Step 4 (Implement) pointer step when use_worktree=false → allow.
h10a=$(make_home)
write_plan "$h10a" "$(v3_frontmatter none false)
## SDLC State
current: 4
Step 4: <docs-root>/plans/wave-04.plan.md#step-4" > /dev/null
expect_allow "v3 Step 4 pointer (use_worktree=false) → allow" \
  "$h10a" 'git commit -m "x"'

# 10b — v3 Step 4 with use_worktree=true and all fields → allow.
h10b=$(make_home)
write_plan "$h10b" "$(v3_frontmatter none true)
## SDLC State
current: 4
Step 4:
  worktree: /Users/x/.worktrees/feature-x
  base-sha: abc1234abc1234abc1234abc1234abc1234abc1
  branch: feature-x" > /dev/null
expect_allow "v3 Step 4 use_worktree=true with all fields → allow" \
  "$h10b" 'git commit -m "x"'

# 10c — v3 Step 4 with use_worktree=true missing base-sha → block.
h10c=$(make_home)
write_plan "$h10c" "$(v3_frontmatter none true)
## SDLC State
current: 4
Step 4:
  worktree: /Users/x/.worktrees/feature-x
  branch: feature-x" > /dev/null
expect_block "v3 Step 4 use_worktree=true missing base-sha → block" \
  "$h10c" 'git commit -m "x"' "base-sha"

# 10d — v3 Step 5 (Browser verify) with devtools-trace → allow.
h10d=$(make_home)
write_plan "$h10d" "$(v3_frontmatter)
## SDLC State
current: 5
Step 5:
  devtools-trace: .bionic/tmp/devtools-trace-001.json" > /dev/null
expect_allow "v3 Step 5 with devtools-trace → allow" \
  "$h10d" 'git commit -m "x"'

# 10e — v3 Step 5 with n/a → allow.
h10e=$(make_home)
write_plan "$h10e" "$(v3_frontmatter)
## SDLC State
current: 5
Step 5:
  n/a: no UI in this wave" > /dev/null
expect_allow "v3 Step 5 with n/a → allow" \
  "$h10e" 'git commit -m "x"'

# 10f — v3 Step 5 with neither → block.
h10f=$(make_home)
write_plan "$h10f" "$(v3_frontmatter)
## SDLC State
current: 5
Step 5:
  notes: skipped" > /dev/null
expect_block "v3 Step 5 missing devtools-trace and n/a → block" \
  "$h10f" 'git commit -m "x"' "devtools-trace"

# 10g — v3 Step 6 (Verify done) — moved from old Step 7.
h10g=$(make_home)
write_plan "$h10g" "$(v3_frontmatter)
## SDLC State
current: 6
Step 6:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-6" > /dev/null
expect_allow "v3 Step 6 full shape (cmd/pass/total/output) → allow" \
  "$h10g" 'git commit -m "x"'

# 10h — v3 Step 6 missing pass → block.
h10h=$(make_home)
write_plan "$h10h" "$(v3_frontmatter)
## SDLC State
current: 6
Step 6:
  cmd: bash test.sh
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-6" > /dev/null
expect_block "v3 Step 6 missing pass → block" \
  "$h10h" 'git commit -m "x"' "pass"

# 10i — v3 Step 7 (Self-review) pointer step → allow.
h10i=$(make_home)
write_plan "$h10i" "$(v3_frontmatter)
## SDLC State
current: 7
Step 7: .bionic/docs/plans/wave-04.plan.md#step-7-review" > /dev/null
expect_allow "v3 Step 7 (pointer step) → allow" \
  "$h10i" 'git commit -m "x"'

# 10j — v3 Step 8 (Adversarial critic) pointer step → allow.
h10j=$(make_home)
write_plan "$h10j" "$(v3_frontmatter)
## SDLC State
current: 8
Step 8: .bionic/docs/plans/wave-04.plan.md#step-8-critic-findings" > /dev/null
expect_allow "v3 Step 8 (Adversarial critic pointer step) → allow" \
  "$h10j" 'git commit -m "x"'

# 10k — v3 Step 9 with adr → allow.
h10k=$(make_home)
write_plan "$h10k" "$(v3_frontmatter)
## SDLC State
current: 9
Step 9:
  adr: .bionic/docs/adrs/epic-01-x/adr-001-decision.md" > /dev/null
expect_allow "v3 Step 9 with adr → allow" \
  "$h10k" 'git commit -m "x"'

# 10l — v3 Step 10 with required fields → allow.
h10l=$(make_home)
write_plan "$h10l" "$(v3_frontmatter)
## SDLC State
current: 10
Step 10:
  commit: abc1234abc1234abc1234abc1234abc1234abc1
  subject: feat(thing): do the thing
  files: 5" > /dev/null
expect_allow "v3 Step 10 with required fields → allow" \
  "$h10l" 'git commit -m "x"'

# 10m — v3 Step 11 with pr → allow.
h10m=$(make_home)
write_plan "$h10m" "$(v3_frontmatter)
## SDLC State
current: 11
Step 11:
  pr: https://github.com/example/repo/pull/42" > /dev/null
expect_allow "v3 Step 11 with pr → allow" \
  "$h10m" 'git commit -m "x"'

# 10n — v3 Step 12 with required fields → allow.
h10n=$(make_home)
write_plan "$h10n" "$(v3_frontmatter)
## SDLC State
current: 12
Step 12:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a" > /dev/null
expect_allow "v3 Step 12 with required fields → allow" \
  "$h10n" 'git commit -m "x"'

# 10o — v3 Step 13 (Post-merge cleanup) with required fields → allow.
h10o=$(make_home)
write_plan "$h10o" "$(v3_frontmatter)
## SDLC State
current: 13
Step 13:
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 14/14" > /dev/null
expect_allow "v3 Step 13 (Post-merge cleanup) with required fields → allow" \
  "$h10o" 'git commit -m "x"'

# 10p — v3 Step 13 missing tmp-wiped → block.
h10p=$(make_home)
write_plan "$h10p" "$(v3_frontmatter)
## SDLC State
current: 13
Step 13:
  cleanup: ok
  tasks-completed: 14/14" > /dev/null
expect_block "v3 Step 13 missing tmp-wiped → block" \
  "$h10p" 'git commit -m "x"' "tmp-wiped"

# 10q — v3 Step 13 with n/a (cleanup_on_finish=false case) → allow.
h10q=$(make_home)
write_plan "$h10q" "$(v3_frontmatter)
## SDLC State
current: 13
Step 13:
  n/a: cleanup_on_finish=false" > /dev/null
expect_allow "v3 Step 13 with n/a → allow" \
  "$h10q" 'git commit -m "x"'

# 10r — v3 Step 14 (Ship) with deploy fields → allow.
h10r=$(make_home)
write_plan "$h10r" "$(v3_frontmatter k8s)
## SDLC State
current: 14
Step 14:
  deploy: prod
  verified-at: 2026-05-10T18:00:00Z
  monitor: https://grafana.example.com/d/foo" > /dev/null
expect_allow "v3 Step 14 with deploy fields → allow" \
  "$h10r" 'git commit -m "x"'

# 10s — v3 Step 14 with n/a + deploy_target=none → allow.
h10s=$(make_home)
write_plan "$h10s" "$(v3_frontmatter none)
## SDLC State
current: 14
Step 14:
  n/a: no deploy target" > /dev/null
expect_allow "v3 Step 14 n/a + deploy_target=none → allow" \
  "$h10s" 'git commit -m "x"'

# 10t — v3 Step 14 with n/a but deploy_target=k8s → block.
h10t=$(make_home)
write_plan "$h10t" "$(v3_frontmatter k8s)
## SDLC State
current: 14
Step 14:
  n/a: skipped" > /dev/null
expect_block "v3 Step 14 n/a with deploy_target=k8s → block" \
  "$h10t" 'git commit -m "x"' "deploy_target"

# 10u — v3 pointer step 1/2/3 → allow.
for step in 1 2 3; do
  h=$(make_home)
  write_plan "$h" "$(v3_frontmatter)
## SDLC State
current: $step
Step $step: pointer evidence here" > /dev/null
  expect_allow "v3 Step $step (pointer step) → allow" \
    "$h" 'git commit -m "x"'
done

# 10v — v3 placeholder check still active.
h10v=$(make_home)
write_plan "$h10v" "$(v3_frontmatter)
## SDLC State
current: 6
Step 6: TODO" > /dev/null
expect_block "v3 Step 6 with placeholder TODO → block" \
  "$h10v" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 11: v5 canonical_sdlc_version shape validation
# ============================================================
#
# v5 collapses the step set: Step 5 = Verify gate (tests modality always +
# browser modality devtools-trace/n-a), Step 6 = Review (pointer), Step 7 =
# Document (was 9), Step 8 = External review (was 11), Step 9 = Integrate &
# close (merge + cleanup, was 12+13), Step 10 = Ship (was 14). Commit is a
# cross-cutting rhythm, no longer a numbered step.

echo ""
echo "=== Section 11: v5 canonical_sdlc_version shape validation ==="

v5_frontmatter() {
  local deploy="${1:-none}" use_wt="${2:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 5
deploy_target: ${deploy}
use_worktree: ${use_wt}
---
EOF
}

# 11a — v5 Step 4 (Implement) pointer step when use_worktree=false → allow.
h11a=$(make_home)
write_plan "$h11a" "$(v5_frontmatter none false)
## SDLC State
current: 4
Step 4: <docs-root>/plans/wave-04.plan.md#step-4" > /dev/null
expect_allow "v5 Step 4 pointer (use_worktree=false) → allow" \
  "$h11a" 'git commit -m "x"'

# 11b — v5 Step 4 with use_worktree=true and all fields → allow.
h11b=$(make_home)
write_plan "$h11b" "$(v5_frontmatter none true)
## SDLC State
current: 4
Step 4:
  worktree: /Users/x/.worktrees/feature-x
  base-sha: abc1234abc1234abc1234abc1234abc1234abc1
  branch: feature-x" > /dev/null
expect_allow "v5 Step 4 use_worktree=true with all fields → allow" \
  "$h11b" 'git commit -m "x"'

# 11c — v5 Step 4 with use_worktree=true missing base-sha → block.
h11c=$(make_home)
write_plan "$h11c" "$(v5_frontmatter none true)
## SDLC State
current: 4
Step 4:
  worktree: /Users/x/.worktrees/feature-x
  branch: feature-x" > /dev/null
expect_block "v5 Step 4 use_worktree=true missing base-sha → block" \
  "$h11c" 'git commit -m "x"' "base-sha"

# 11d — v5 Step 5 (Verify) full shape: tests + browser devtools-trace → allow.
h11d=$(make_home)
write_plan "$h11d" "$(v5_frontmatter)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-5
  devtools-trace: .bionic/tmp/evidence-golden.png" > /dev/null
expect_allow "v5 Step 5 Verify full (tests + browser trace) → allow" \
  "$h11d" 'git commit -m "x"'

# 11e — v5 Step 5 tests + browser n/a (non-UI wave) → allow.
h11e=$(make_home)
write_plan "$h11e" "$(v5_frontmatter)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 100
  total: 100
  output: .bionic/docs/plans/wave-04.plan.md#step-5
  n/a: no UI in this wave" > /dev/null
expect_allow "v5 Step 5 Verify tests + browser n/a → allow" \
  "$h11e" 'git commit -m "x"'

# 11f — v5 Step 5 tests present but browser modality missing (no trace, no n/a) → block.
h11f=$(make_home)
write_plan "$h11f" "$(v5_frontmatter)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 10
  total: 10
  output: x" > /dev/null
expect_block "v5 Step 5 missing browser modality (devtools-trace/n-a) → block" \
  "$h11f" 'git commit -m "x"' "devtools-trace"

# 11g — v5 Step 5 missing pass → block.
h11g=$(make_home)
write_plan "$h11g" "$(v5_frontmatter)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  total: 332
  output: x
  devtools-trace: .bionic/tmp/e.png" > /dev/null
expect_block "v5 Step 5 missing pass → block" \
  "$h11g" 'git commit -m "x"' "pass"

# 11h — v5 Step 5 pass != total → block.
h11h=$(make_home)
write_plan "$h11h" "$(v5_frontmatter)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 331
  total: 332
  output: x
  devtools-trace: .bionic/tmp/e.png" > /dev/null
expect_block "v5 Step 5 pass != total → block" \
  "$h11h" 'git commit -m "x"' "not fully green"

# 11i — v5 Step 6 (Review) pointer step → allow.
h11i=$(make_home)
write_plan "$h11i" "$(v5_frontmatter)
## SDLC State
current: 6
Step 6: .bionic/docs/plans/wave-04.plan.md#step-6-review" > /dev/null
expect_allow "v5 Step 6 (Review pointer step) → allow" \
  "$h11i" 'git commit -m "x"'

# 11j — v5 Step 7 (Document) with adr → allow.
h11j=$(make_home)
write_plan "$h11j" "$(v5_frontmatter)
## SDLC State
current: 7
Step 7:
  adr: .bionic/docs/adrs/epic-01-x/adr-001-decision.md" > /dev/null
expect_allow "v5 Step 7 Document with adr → allow" \
  "$h11j" 'git commit -m "x"'

# 11k — v5 Step 7 with rca → allow.
h11k=$(make_home)
write_plan "$h11k" "$(v5_frontmatter)
## SDLC State
current: 7
Step 7:
  rca: .bionic/docs/incidents/0001-x/rca.md" > /dev/null
expect_allow "v5 Step 7 Document with rca → allow" \
  "$h11k" 'git commit -m "x"'

# 11l — v5 Step 7 missing adr/rca/n-a → block.
h11l=$(make_home)
write_plan "$h11l" "$(v5_frontmatter)
## SDLC State
current: 7
Step 7:
  notes: forgot the decision record" > /dev/null
expect_block "v5 Step 7 missing adr/rca/n-a → block" \
  "$h11l" 'git commit -m "x"' "adr"

# 11m — v5 Step 8 (External review) with pr → allow.
h11m=$(make_home)
write_plan "$h11m" "$(v5_frontmatter)
## SDLC State
current: 8
Step 8:
  pr: https://github.com/example/repo/pull/42" > /dev/null
expect_allow "v5 Step 8 External review with pr → allow" \
  "$h11m" 'git commit -m "x"'

# 11n — v5 Step 8 with n/a → allow.
h11n=$(make_home)
write_plan "$h11n" "$(v5_frontmatter)
## SDLC State
current: 8
Step 8:
  n/a: PR-less workflow" > /dev/null
expect_allow "v5 Step 8 External review with n/a → allow" \
  "$h11n" 'git commit -m "x"'

# 11o — v5 Step 9 (Integrate & close) full: merge + cleanup triple → allow.
h11o=$(make_home)
write_plan "$h11o" "$(v5_frontmatter)
## SDLC State
current: 9
Step 9:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 11/11" > /dev/null
expect_allow "v5 Step 9 Integrate & close full (merge + cleanup) → allow" \
  "$h11o" 'git commit -m "x"'

# 11p — v5 Step 9 with cleanup: n/a (cleanup_on_finish=false) → allow.
h11p=$(make_home)
write_plan "$h11p" "$(v5_frontmatter)
## SDLC State
current: 9
Step 9:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: n/a" > /dev/null
expect_allow "v5 Step 9 with cleanup: n/a → allow" \
  "$h11p" 'git commit -m "x"'

# 11p2 — v5 Step 9 with cleanup: n/a + reason (cleanup_on_finish=false / already cleaned) → allow.
h11p2=$(make_home)
write_plan "$h11p2" "$(v5_frontmatter)
## SDLC State
current: 9
Step 9:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: n/a: cleanup_on_finish=false" > /dev/null
expect_allow "v5 Step 9 with cleanup: n/a + reason → allow" \
  "$h11p2" 'git commit -m "x"'

# 11q — v5 Step 9 missing merge → block.
h11q=$(make_home)
write_plan "$h11q" "$(v5_frontmatter)
## SDLC State
current: 9
Step 9:
  worktree-removed: n/a
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 11/11" > /dev/null
expect_block "v5 Step 9 missing merge → block" \
  "$h11q" 'git commit -m "x"' "merge"

# 11r — v5 Step 9 cleanup present but missing tmp-wiped → block.
h11r=$(make_home)
write_plan "$h11r" "$(v5_frontmatter)
## SDLC State
current: 9
Step 9:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: ok
  tasks-completed: 11/11" > /dev/null
expect_block "v5 Step 9 cleanup present, missing tmp-wiped → block" \
  "$h11r" 'git commit -m "x"' "tmp-wiped"

# 11s — v5 Step 10 (Ship) with deploy fields → allow.
h11s=$(make_home)
write_plan "$h11s" "$(v5_frontmatter k8s)
## SDLC State
current: 10
Step 10:
  deploy: prod
  verified-at: 2026-06-19T18:00:00Z
  monitor: https://grafana.example.com/d/foo" > /dev/null
expect_allow "v5 Step 10 Ship with deploy fields → allow" \
  "$h11s" 'git commit -m "x"'

# 11t — v5 Step 10 with n/a + deploy_target=none → allow.
h11t=$(make_home)
write_plan "$h11t" "$(v5_frontmatter none)
## SDLC State
current: 10
Step 10:
  n/a: no deploy target" > /dev/null
expect_allow "v5 Step 10 n/a + deploy_target=none → allow" \
  "$h11t" 'git commit -m "x"'

# 11u — v5 Step 10 with n/a but deploy_target=k8s → block.
h11u=$(make_home)
write_plan "$h11u" "$(v5_frontmatter k8s)
## SDLC State
current: 10
Step 10:
  n/a: skipped" > /dev/null
expect_block "v5 Step 10 n/a with deploy_target=k8s → block" \
  "$h11u" 'git commit -m "x"' "deploy_target"

# 11v — v5 pointer step 1/2/3 → allow.
for step in 1 2 3; do
  h=$(make_home)
  write_plan "$h" "$(v5_frontmatter)
## SDLC State
current: $step
Step $step: pointer evidence here" > /dev/null
  expect_allow "v5 Step $step (pointer step) → allow" \
    "$h" 'git commit -m "x"'
done

# 11w — v5 placeholder check still active.
h11w=$(make_home)
write_plan "$h11w" "$(v5_frontmatter)
## SDLC State
current: 5
Step 5: TODO" > /dev/null
expect_block "v5 Step 5 with placeholder TODO → block" \
  "$h11w" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 12: v6 canonical_sdlc_version shape validation
# ============================================================
#
# v6 drops the external-review step from v5 (0–9 shape): Step 8 =
# Integrate & close (was v5 Step 9), Step 9 = Ship (was v5 Step 10).
# Step 5 shape is identical to v5. Regression-critical: v6 plans must
# NOT require the v7 `bundle-fresh:` key, even when has_ui is true.

echo ""
echo "=== Section 12: v6 canonical_sdlc_version shape validation ==="

v6_frontmatter() {
  local deploy="${1:-none}" use_wt="${2:-false}" has_ui="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 6
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
---
EOF
}

# 12a — v6 Step 5 full shape, has_ui=true, NO bundle-fresh → allow
# (grandfathered: the bundle-fresh requirement is v7-only).
h12a=$(make_home)
write_plan "$h12a" "$(v6_frontmatter none false true)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-5
  devtools-trace: .bionic/tmp/evidence-golden.png" > /dev/null
expect_allow "v6 Step 5 has_ui=true without bundle-fresh → allow (grandfathered)" \
  "$h12a" 'git commit -m "x"'

# 12b — v6 Step 5 missing browser modality → block (v6 base rules intact).
h12b=$(make_home)
write_plan "$h12b" "$(v6_frontmatter)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 10
  total: 10
  output: x" > /dev/null
expect_block "v6 Step 5 missing browser modality (devtools-trace/n-a) → block" \
  "$h12b" 'git commit -m "x"' "devtools-trace"

# 12c — v6 Step 8 (Integrate & close, renumbered from v5 Step 9) → allow.
h12c=$(make_home)
write_plan "$h12c" "$(v6_frontmatter)
## SDLC State
current: 8
Step 8:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 10/10" > /dev/null
expect_allow "v6 Step 8 Integrate & close full → allow" \
  "$h12c" 'git commit -m "x"'

# 12d — v6 Step 9 (Ship, renumbered from v5 Step 10) n/a + deploy_target=none → allow.
h12d=$(make_home)
write_plan "$h12d" "$(v6_frontmatter none)
## SDLC State
current: 9
Step 9:
  n/a: no deploy target" > /dev/null
expect_allow "v6 Step 9 Ship n/a + deploy_target=none → allow" \
  "$h12d" 'git commit -m "x"'

# 12e — v6 Step 6 (Review) pointer step → allow.
h12e=$(make_home)
write_plan "$h12e" "$(v6_frontmatter)
## SDLC State
current: 6
Step 6: .bionic/docs/plans/wave-04.plan.md#step-6-review" > /dev/null
expect_allow "v6 Step 6 (Review pointer step) → allow" \
  "$h12e" 'git commit -m "x"'

# ============================================================
# Section 13: v7 canonical_sdlc_version — bundle-freshness gate
# ============================================================
#
# v7 = v6 plus ONE addition: the Step 5 block must carry
# `bundle-fresh: <proof>` or `bundle-fresh: n/a: <reason>` — universal
# with an n/a escape, exactly like `devtools-trace:`. Frontmatter flags
# (has_ui included) do NOT gate the requirement. The proof format is
# project-specific by design — the hook validates presence + non-empty
# value/reason + the existing placeholder ban only.

echo ""
echo "=== Section 13: v7 bundle-freshness gate ==="

v7_frontmatter() {
  local has_ui="${1:-true}" deploy="${2:-none}" use_wt="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 7
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
---
EOF
}

# Shared Step-5 body (tests + browser modalities satisfied) so each case
# isolates the bundle-fresh variable.
v7_step5_base="  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-5
  devtools-trace: .bionic/tmp/evidence-golden.png"

# 13a — v7 has_ui=true, Step 5 complete but NO bundle-fresh → block,
# message names the key.
h13a=$(make_home)
write_plan "$h13a" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base" > /dev/null
expect_block "v7 has_ui=true Step 5 without bundle-fresh → block" \
  "$h13a" 'git commit -m "x"' "bundle-fresh"

# 13b — v7 has_ui=true + bundle-fresh proof line → allow.
h13b=$(make_home)
write_plan "$h13b" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh: FRESH — canary token-9f3a round-tripped to dist/main.js in 4.2s" > /dev/null
expect_allow "v7 has_ui=true + bundle-fresh proof → allow" \
  "$h13b" 'git commit -m "x"'

# 13c — v7 has_ui=true + bundle-fresh: n/a with reason → allow.
h13c=$(make_home)
write_plan "$h13c" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh: n/a: CLI tool, no served bundle" > /dev/null
expect_allow "v7 has_ui=true + bundle-fresh: n/a with reason → allow" \
  "$h13c" 'git commit -m "x"'

# 13d — v7 has_ui=true + bundle-fresh placeholder → block (placeholder ban).
h13d=$(make_home)
write_plan "$h13d" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh: TBD" > /dev/null
expect_block "v7 bundle-fresh: TBD → block (placeholder ban)" \
  "$h13d" 'git commit -m "x"' "placeholder"

# 13e — v7 has_ui=true + bundle-fresh: n/a with NO reason → block.
h13e=$(make_home)
write_plan "$h13e" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh: n/a" > /dev/null
expect_block "v7 bundle-fresh: n/a without reason → block" \
  "$h13e" 'git commit -m "x"' "bundle-fresh"

# 13f — v7 has_ui=true + bundle-fresh empty value → block.
h13f=$(make_home)
write_plan "$h13f" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh:" > /dev/null
expect_block "v7 bundle-fresh with empty value → block" \
  "$h13f" 'git commit -m "x"' "bundle-fresh"

# 13g — v7 has_ui=false, no bundle-fresh key → block (the requirement is
# universal; frontmatter flags don't gate it).
h13g=$(make_home)
write_plan "$h13g" "$(v7_frontmatter false)
## SDLC State
current: 5
Step 5:
$v7_step5_base" > /dev/null
expect_block "v7 has_ui=false without bundle-fresh → block (universal key)" \
  "$h13g" 'git commit -m "x"' "bundle-fresh"

# 13h — v7 has_ui=false + bundle-fresh: n/a with reason → allow (the n/a
# escape is how non-served waves satisfy the universal key).
h13h=$(make_home)
write_plan "$h13h" "$(v7_frontmatter false)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh: n/a: no served artifact in this wave" > /dev/null
expect_allow "v7 has_ui=false + bundle-fresh: n/a with reason → allow" \
  "$h13h" 'git commit -m "x"'

# 13i — v7 has_ui=true with bundle-fresh but missing browser modality →
# block (v6 base rules still apply under v7).
h13i=$(make_home)
write_plan "$h13i" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 10
  total: 10
  output: x
  bundle-fresh: FRESH — canary token-9f3a round-tripped in 4.2s" > /dev/null
expect_block "v7 Step 5 missing devtools-trace (base v6 rules intact) → block" \
  "$h13i" 'git commit -m "x"' "devtools-trace"

# 13j — v7 non-Step-5 shapes unchanged from v6: Step 8 Integrate & close → allow.
h13j=$(make_home)
write_plan "$h13j" "$(v7_frontmatter true)
## SDLC State
current: 8
Step 8:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 10/10" > /dev/null
expect_allow "v7 Step 8 Integrate & close full → allow" \
  "$h13j" 'git commit -m "x"'

# 13k — v7 pointer steps 1/2/3/6 → allow.
for step in 1 2 3 6; do
  h=$(make_home)
  write_plan "$h" "$(v7_frontmatter true)
## SDLC State
current: $step
Step $step: pointer evidence here" > /dev/null
  expect_allow "v7 Step $step (pointer step) → allow" \
    "$h" 'git commit -m "x"'
done

# ============================================================
# Section 14: v8 canonical_sdlc_version — drive-check gate
# ============================================================
#
# v8 = v7 plus ONE addition: the Step 5 block must carry
# `drive-check: <observed delta>` (or `suite: <named test — what it asserts>` /
# `n/a: <reason>`) — proof that one trusted interaction changed app
# state, read back semantically, before browser-modality evidence
# counts. Universal with an n/a escape, exactly like `bundle-fresh:`.
# The hook validates presence + non-empty value/reason + the existing
# placeholder ban only; the suite-credit semantics live in skill prose.

echo ""
echo "=== Section 14: v8 drive-check gate ==="

v8_frontmatter() {
  local has_ui="${1:-true}" deploy="${2:-none}" use_wt="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 8
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
---
EOF
}

# Shared Step-5 body (tests + browser + bundle-fresh satisfied) so each
# case isolates the drive-check variable.
v8_step5_base="  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-5
  devtools-trace: .bionic/tmp/evidence-golden.png
  bundle-fresh: FRESH — canary token-9f3a round-tripped to dist/main.js in 4.2s"

# 14a — v8 Step 5 complete but NO drive-check → block, message names the key.
h14a=$(make_home)
write_plan "$h14a" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base" > /dev/null
expect_block "v8 Step 5 without drive-check → block" \
  "$h14a" 'git commit -m "x"' "drive-check"

# 14b — v8 + drive-check observed-delta proof → allow.
h14b=$(make_home)
write_plan "$h14b" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: drag on target surface moved app value 3 → 7 via eval readback" > /dev/null
expect_allow "v8 + drive-check observed delta → allow" \
  "$h14b" 'git commit -m "x"'

# 14c — v8 + drive-check suite-credit form → allow.
h14c=$(make_home)
write_plan "$h14c" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: suite: e2e drag-updates-value.spec — real pointer input on the target surface, asserts app state delta" > /dev/null
expect_allow "v8 + drive-check: suite-credit form → allow" \
  "$h14c" 'git commit -m "x"'

# 14d — v8 + drive-check: n/a with reason → allow.
h14d=$(make_home)
write_plan "$h14d" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: n/a: no browser modality in this wave" > /dev/null
expect_allow "v8 + drive-check: n/a with reason → allow" \
  "$h14d" 'git commit -m "x"'

# 14e — v8 + drive-check placeholder → block (placeholder ban).
h14e=$(make_home)
write_plan "$h14e" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: TBD" > /dev/null
expect_block "v8 drive-check: TBD → block (placeholder ban)" \
  "$h14e" 'git commit -m "x"' "placeholder"

# 14f — v8 + drive-check: n/a with NO reason → block.
h14f=$(make_home)
write_plan "$h14f" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: n/a" > /dev/null
expect_block "v8 drive-check: n/a without reason → block" \
  "$h14f" 'git commit -m "x"' "drive-check"

# 14g — v8 + drive-check empty value → block.
h14g=$(make_home)
write_plan "$h14g" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check:" > /dev/null
expect_block "v8 drive-check with empty value → block" \
  "$h14g" 'git commit -m "x"' "drive-check"

# 14h — v8 has_ui=false: key is universal (block without; n/a satisfies).
h14h1=$(make_home)
write_plan "$h14h1" "$(v8_frontmatter false)
## SDLC State
current: 5
Step 5:
$v8_step5_base" > /dev/null
expect_block "v8 has_ui=false without drive-check → block (universal key)" \
  "$h14h1" 'git commit -m "x"' "drive-check"

h14h2=$(make_home)
write_plan "$h14h2" "$(v8_frontmatter false)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: n/a: no interactive surface in this wave" > /dev/null
expect_allow "v8 has_ui=false + drive-check: n/a with reason → allow" \
  "$h14h2" 'git commit -m "x"'

# 14i — v8 with drive-check but missing bundle-fresh → block (v7 base
# rules still apply under v8).
h14i=$(make_home)
write_plan "$h14i" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 10
  total: 10
  output: x
  devtools-trace: .bionic/tmp/evidence-golden.png
  drive-check: click toggled app flag false → true via eval readback" > /dev/null
expect_block "v8 Step 5 missing bundle-fresh (base v7 rules intact) → block" \
  "$h14i" 'git commit -m "x"' "bundle-fresh"

# 14j — v8 non-Step-5 shapes unchanged from v7: Step 8 → allow.
h14j=$(make_home)
write_plan "$h14j" "$(v8_frontmatter true)
## SDLC State
current: 8
Step 8:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 10/10" > /dev/null
expect_allow "v8 Step 8 Integrate & close full → allow" \
  "$h14j" 'git commit -m "x"'

# 14k — v8 pointer steps 1/2/3/6 → allow.
for step in 1 2 3 6; do
  h=$(make_home)
  write_plan "$h" "$(v8_frontmatter true)
## SDLC State
current: $step
Step $step: pointer evidence here" > /dev/null
  expect_allow "v8 Step $step (pointer step) → allow" \
    "$h" 'git commit -m "x"'
done

# 14l — GRANDFATHERING: a v7 plan at Step 5 with bundle-fresh but NO
# drive-check must still pass after the v8 switch lands. (13b proves the
# same shape; this case exists as the explicit named regression.)
h14l=$(make_home)
write_plan "$h14l" "$(v7_frontmatter true)
## SDLC State
current: 5
Step 5:
$v7_step5_base
  bundle-fresh: FRESH — canary token-9f3a round-tripped to dist/main.js in 4.2s" > /dev/null
expect_allow "GRANDFATHER: v7 Step 5 without drive-check → allow" \
  "$h14l" 'git commit -m "x"'

# ============================================================
# Section 15: CRLF line endings — frontmatter parses under \r\n
# ============================================================
#
# Plan files with CRLF (\r\n) line endings previously defeated the
# hook's exact-match awk frontmatter parser (`$0=="---"` never matches
# "---\r"), silently downgrading v8 plans to legacy presence-only mode
# — every shape check (including the drive-check gate from Section 14)
# skipped. Strip \r at extraction time so CRLF plans get the same
# enforcement as LF plans.

echo ""
echo "=== Section 15: CRLF line endings ==="

# Converts LF line endings to CRLF by inserting a literal CR before
# each newline. Bash-3.2-safe ANSI-C quoting embeds a real CR byte in
# the sed script itself (BSD sed's replacement text does not interpret
# the two-character "\r" as an escape).
to_crlf() {
  printf '%s' "$1" | sed $'s/$/\r/'
}

# 15a — CRLF v8 plan, Step 5 complete but NO drive-check → block. Before
# the fix: FRONTMATTER parses empty (canonical_sdlc_version lost) → hook
# silently downgrades to legacy presence-only mode → incorrectly allows.
h15a=$(make_home)
write_plan "$h15a" "$(to_crlf "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base")" > /dev/null
expect_block "CRLF v8 Step 5 without drive-check → block" \
  "$h15a" 'git commit -m "x"' "drive-check"

# 15b — CRLF v8 plan with a complete, valid Step-5 block (drive-check
# present) → allow.
h15b=$(make_home)
write_plan "$h15b" "$(to_crlf "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: click toggled app flag false → true via eval readback")" > /dev/null
expect_allow "CRLF v8 Step 5 complete (drive-check present) → allow" \
  "$h15b" 'git commit -m "x"'

# ============================================================
# Section 16: v9 canonical_sdlc_version — universal stack-health gate
# ============================================================
#
# v9 = v8 plus ONE addition: the Step 5 block must carry
# `stack-health: <before/after snapshot, no delta>` or
# `stack-health: n/a: <reason>` — proof that the serving stack's
# runtime-integrity indicators (process restarts, crash/OOM state) did
# not change across the walk, so a crash-restart mid-walk cannot swallow
# the bug being probed while the app returns looking healthy. Universal
# with an n/a escape, exactly like `bundle-fresh:` and `drive-check:`.
# The hook validates presence + non-empty value/reason + the existing
# placeholder ban only; the snapshot command is project-specific by
# design.

echo ""
echo "=== Section 16: v9 stack-health gate ==="

v9_frontmatter() {
  local has_ui="${1:-true}" deploy="${2:-none}" use_wt="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 9
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
---
EOF
}

# Shared Step-5 body (tests + browser + bundle-fresh + drive-check
# satisfied) so each case isolates the stack-health variable.
v9_step5_base="  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-04.plan.md#step-5
  devtools-trace: .bionic/tmp/evidence-golden.png
  bundle-fresh: FRESH — canary token-9f3a round-tripped to dist/main.js in 4.2s
  drive-check: click toggled app flag false → true via eval readback"

# 16a — v9 Step 5 complete (all v8 keys present) but NO stack-health →
# block, message names the key.
h16a=$(make_home)
write_plan "$h16a" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base" > /dev/null
expect_block "v9 Step 5 without stack-health → block" \
  "$h16a" 'git commit -m "x"' "stack-health"

# 16b — v9 + stack-health before/after snapshot with no delta → allow.
h16b=$(make_home)
write_plan "$h16b" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base
  stack-health: process restarts 0 → 0 across walk; no crash/OOM state change" > /dev/null
expect_allow "v9 + stack-health no-delta snapshot → allow" \
  "$h16b" 'git commit -m "x"'

# 16c — v9 + stack-health: n/a with reason → allow.
h16c=$(make_home)
write_plan "$h16c" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base
  stack-health: n/a: no long-running serve observed" > /dev/null
expect_allow "v9 + stack-health: n/a with reason → allow" \
  "$h16c" 'git commit -m "x"'

# 16d — v9 + stack-health empty value → block.
h16d=$(make_home)
write_plan "$h16d" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base
  stack-health:" > /dev/null
expect_block "v9 stack-health with empty value → block" \
  "$h16d" 'git commit -m "x"' "stack-health"

# 16e — v9 + stack-health: n/a with NO reason → block.
h16e=$(make_home)
write_plan "$h16e" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base
  stack-health: n/a" > /dev/null
expect_block "v9 stack-health: n/a without reason → block" \
  "$h16e" 'git commit -m "x"' "stack-health"

# 16f — v9 + stack-health placeholder → block (placeholder ban).
h16f=$(make_home)
write_plan "$h16f" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base
  stack-health: TBD" > /dev/null
expect_block "v9 stack-health: TBD → block (placeholder ban)" \
  "$h16f" 'git commit -m "x"' "placeholder"

# 16g — v9 non-Step-5 spot-checks: document (Step 7) and integrate
# (Step 8) shapes unchanged from v8.
h16g1=$(make_home)
write_plan "$h16g1" "$(v9_frontmatter true)
## SDLC State
current: 7
Step 7:
  adr: .bionic/docs/adrs/adr-001-example.md" > /dev/null
expect_allow "v9 Step 7 Document with adr → allow" \
  "$h16g1" 'git commit -m "x"'

h16g2=$(make_home)
write_plan "$h16g2" "$(v9_frontmatter true)
## SDLC State
current: 8
Step 8:
  merge: abc1234abc1234abc1234abc1234abc1234abc1
  worktree-removed: n/a
  cleanup: ok
  tmp-wiped: yes
  tasks-completed: 10/10" > /dev/null
expect_allow "v9 Step 8 Integrate & close full → allow" \
  "$h16g2" 'git commit -m "x"'

# 16h — GRANDFATHER (named regression): a v8 plan at Step 5 with all v8
# keys (including drive-check — v8's own requirement) but NO stack-health
# must still pass after the v9 switch lands.
h16h=$(make_home)
write_plan "$h16h" "$(v8_frontmatter true)
## SDLC State
current: 5
Step 5:
$v8_step5_base
  drive-check: click toggled app flag false → true via eval readback" > /dev/null
expect_allow "GRANDFATHER: v8 Step 5 without stack-health → allow" \
  "$h16h" 'git commit -m "x"'

# 16i — whole-value equality on the flat Step-5 block: a field VALUE that
# merely CONTAINS a placeholder token as a substring (here output: "...
# *.example placeholders ...") is legal — only a whole-value match blocks.
# This was the live false block under the OLD substring ban.
h16i=$(make_home)
write_plan "$h16i" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: rendered 3 *.example placeholders in the fixture snapshot
  devtools-trace: .bionic/tmp/evidence-golden.png
  bundle-fresh: FRESH — canary token-9f3a round-tripped to dist/main.js in 4.2s
  drive-check: click toggled app flag false → true via eval readback
  stack-health: process restarts 0 → 0 across walk; no crash/OOM state change" > /dev/null
expect_allow "v9 Step 5 output containing '*.example placeholders' substring → allow (whole-value equality)" \
  "$h16i" 'git commit -m "x"'

# ============================================================
# Section 17: v10 canonical_sdlc_version — Verification Matrix gate
# ============================================================
#
# v10 replaces the flat Step-5 universal-key stack (bundle-fresh /
# drive-check / stack-health) with a pre-registered Verification Matrix
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
echo "=== Section 17: v10 Verification Matrix gate ==="

v10_frontmatter() {
  local has_ui="${1:-true}" deploy="${2:-none}" use_wt="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 10
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
---
EOF
}

# Shared Step-5 block: tests floor + the required auditor pointer.
v10_step5_base="  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"

# Assemble a full v10 plan: frontmatter + ## SDLC State (current + Step
# block) + a ## Verification Matrix section. $1 current, $2 Step-block
# body (indented lines), $3 full matrix section text.
v10_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(v10_frontmatter true)" "$1" "$1" "$2" "$3"
}

# A pointer body for post-Verify steps (6..9): non-empty, non-placeholder.
v10_step6_body="  review: .bionic/docs/plans/wave-01.plan.md#step-6-review"

# --- matrix fixtures -------------------------------------------------------

# Complete, valid matrix: T3 (all five fields), T1 (tier-run+readback),
# waived T3 row. stack-health present. All auditor cells CONFIRMED/waived.
v10_matrix_complete="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: chris 2026-07-16 env stale | waived |

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
v10_matrix_no_block="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |

AC-2:
  tier-run: bash test.sh
  readback: 332/332 asserted"

# AC-1 readback is a placeholder token.
v10_matrix_placeholder="## Verification Matrix

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
v10_matrix_live_na="## Verification Matrix

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
v10_matrix_suite_credit="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: suite: hermetic-x
  readback: 12/12 asserted"

# Complete matrix but AC-1 auditor verdict is REFUTED.
v10_matrix_refuted="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | REFUTED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: chris 2026-07-16 env stale | waived |

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
v10_matrix_waived_empty="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: chris 2026-07-16 env stale |  |

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
v10_matrix_no_stackhealth="## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted"

# stack-health via the n/a escape.
v10_matrix_stackhealth_na="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted"

# T0/T1/T2-only matrix — no T3 fields, no browser artifacts anywhere.
v10_matrix_lower_tiers="## Verification Matrix

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
v10_matrix_false_green_unpaired="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted

false-green: hermetic-x — green over broken branch"

# false-green entry WITH a paired rewritten entry.
v10_matrix_false_green_paired="## Verification Matrix

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
v10_matrix_malformed="## Verification Matrix

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
write_plan "$h17a" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_allow "v10 17a complete matrix (T3 + T1 + waived T3) at current 5 → allow" \
  "$h17a" 'git commit -m "x"'

# 17b — discharged row with NO AC evidence block → block, names the AC.
h17b=$(make_home)
write_plan "$h17b" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_no_block")" > /dev/null
expect_block "v10 17b discharged T3 row with no AC block → block (names AC-1)" \
  "$h17b" 'git commit -m "x"' "AC-1"

# 17c — placeholder token in an AC evidence field → block.
h17c=$(make_home)
write_plan "$h17c" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_placeholder")" > /dev/null
expect_block "v10 17c readback: TBD in AC block → block (placeholder ban)" \
  "$h17c" 'git commit -m "x"' "placeholder"

# 17c-substr — a matrix AC field VALUE that merely CONTAINS a placeholder
# token as a substring is legal; only a whole-value match blocks. readback:
# 'status pending → done ...' (contains 'pending') → allow.
v10_matrix_substr_ok="## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: status pending → done, 40/40 asserted"
h17c2=$(make_home)
write_plan "$h17c2" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_substr_ok")" > /dev/null
expect_allow "v10 17c matrix readback containing 'pending' substring → allow (whole-value equality)" \
  "$h17c2" 'git commit -m "x"'

# 17d — T3 row with self-written n/a on a field, no waiver → block, points
# at the Waiver Protocol.
h17d=$(make_home)
write_plan "$h17d" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_live_na")" > /dev/null
expect_block "v10 17d T3 contact: n/a, no waiver → block (Waiver Protocol)" \
  "$h17d" 'git commit -m "x"' "Waiver Protocol"

# 17d-case — the live-tier n/a ban must be case-insensitive: 'N/A' and
# 'N/a: <reason>' are the same self-written downgrade as lowercase 'n/a'
# (review-gate finding: a single capital letter must not defeat the ban).
# The variants are written as full literal matrices rather than derived from
# v10_matrix_live_na via ${var/pat/rep}: a slash in the contact value forces
# an escaped slash in the pattern, and bash 3.2 leaves that backslash in the
# replacement (producing 'contact: N\/A'), so the variant is never built.
v10_matrix_live_na_upper="## Verification Matrix

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
write_plan "$h17d2" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_live_na_upper")" > /dev/null
expect_block "v10 17d T3 contact: N/A (uppercase), no waiver → block" \
  "$h17d2" 'git commit -m "x"' "Waiver Protocol"

v10_matrix_live_na_mixed="## Verification Matrix

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
write_plan "$h17d3" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_live_na_mixed")" > /dev/null
expect_block "v10 17d T3 contact: N/a: <reason> (mixed case), no waiver → block" \
  "$h17d3" 'git commit -m "x"' "Waiver Protocol"

# 17e — T3 row with only the suite-credit shape (missing fresh/cold-client/
# contact) → block.
h17e=$(make_home)
write_plan "$h17e" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_suite_credit")" > /dev/null
expect_block "v10 17e T3 suite-credit shape missing live-tier fields → block (fresh)" \
  "$h17e" 'git commit -m "x"' "fresh"

# 17f — current: 6, one row auditor REFUTED → block.
h17f1=$(make_home)
write_plan "$h17f1" "$(v10_plan 6 "$v10_step6_body" "$v10_matrix_refuted")" > /dev/null
expect_block "v10 17f current 6 with a REFUTED row → block (CONFIRMED required)" \
  "$h17f1" 'git commit -m "x"' "CONFIRMED"

# 17f — current: 6, all non-waived rows CONFIRMED → allow.
h17f2=$(make_home)
write_plan "$h17f2" "$(v10_plan 6 "$v10_step6_body" "$v10_matrix_complete")" > /dev/null
expect_allow "v10 17f current 6 all CONFIRMED (waived row exempt) → allow" \
  "$h17f2" 'git commit -m "x"'

# 17f — current: 6, waived row with an empty auditor cell → allow.
h17f3=$(make_home)
write_plan "$h17f3" "$(v10_plan 6 "$v10_step6_body" "$v10_matrix_waived_empty")" > /dev/null
expect_allow "v10 17f current 6 waived row with empty auditor cell → allow" \
  "$h17f3" 'git commit -m "x"'

# 17g — v10 at current: 5 with NO ## Verification Matrix section → block.
h17g=$(make_home)
write_plan "$h17g" "$(v10_frontmatter true)
## SDLC State
current: 5
Step 5:
$v10_step5_base" > /dev/null
expect_block "v10 17g current 5 with no Verification Matrix section → block" \
  "$h17g" 'git commit -m "x"' "Verification Matrix"

# 17h — matrix missing the stack-health line → block.
h17h1=$(make_home)
write_plan "$h17h1" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_no_stackhealth")" > /dev/null
expect_block "v10 17h matrix missing stack-health → block" \
  "$h17h1" 'git commit -m "x"' "stack-health"

# 17h — stack-health via the n/a escape → allow.
h17h2=$(make_home)
write_plan "$h17h2" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_stackhealth_na")" > /dev/null
expect_allow "v10 17h stack-health: n/a with reason → allow" \
  "$h17h2" 'git commit -m "x"'

# 17i — T0/T1/T2-only matrix, no T3 fields, no browser artifacts → allow.
h17i=$(make_home)
write_plan "$h17i" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_lower_tiers")" > /dev/null
expect_allow "v10 17i lower-tier-only matrix (T0/T1/T2) → allow" \
  "$h17i" 'git commit -m "x"'

# 17j — Step-5 block missing the auditor pointer → block.
h17j1=$(make_home)
write_plan "$h17j1" "$(v10_plan 5 "  cmd: bash test.sh
  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5" "$v10_matrix_complete")" > /dev/null
expect_block "v10 17j Step-5 missing auditor → block" \
  "$h17j1" 'git commit -m "x"' "auditor"

# 17j — Step-5 block missing the tests floor (cmd) → block (validator reuse).
h17j2=$(make_home)
write_plan "$h17j2" "$(v10_plan 5 "  pass: 332
  total: 332
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md" "$v10_matrix_complete")" > /dev/null
expect_block "v10 17j Step-5 missing tests floor cmd → block" \
  "$h17j2" 'git commit -m "x"' "cmd"

# 17k — GRANDFATHER: a v9 plan at current: 5 with v9 keys and NO matrix must
# still pass after the v10 switch lands (reuses the v9 fixtures).
h17k1=$(make_home)
write_plan "$h17k1" "$(v9_frontmatter true)
## SDLC State
current: 5
Step 5:
$v9_step5_base
  stack-health: process restarts 0 → 0 across walk; no crash/OOM state change" > /dev/null
expect_allow "GRANDFATHER: v9 Step 5 (no matrix) after v10 lands → allow" \
  "$h17k1" 'git commit -m "x"'

# 17k — same v9 plan at current: 6 (pointer step) → allow.
h17k2=$(make_home)
write_plan "$h17k2" "$(v9_frontmatter true)
## SDLC State
current: 6
Step 6: .bionic/docs/plans/wave-04.plan.md#step-6-review" > /dev/null
expect_allow "GRANDFATHER: v9 Step 6 pointer (no matrix) → allow" \
  "$h17k2" 'git commit -m "x"'

# 17l — false-green entry with NO paired rewritten entry → block.
h17l1=$(make_home)
write_plan "$h17l1" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_false_green_unpaired")" > /dev/null
expect_block "v10 17l false-green without rewritten → block" \
  "$h17l1" 'git commit -m "x"' "rewritten"

# 17l — false-green entry WITH a paired rewritten entry → allow.
h17l2=$(make_home)
write_plan "$h17l2" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_false_green_paired")" > /dev/null
expect_allow "v10 17l false-green with paired rewritten → allow" \
  "$h17l2" 'git commit -m "x"'

# 17l — no false-green entry at all (key is optional) → allow.
h17l3=$(make_home)
write_plan "$h17l3" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_lower_tiers")" > /dev/null
expect_allow "v10 17l no false-green entry (optional key) → allow" \
  "$h17l3" 'git commit -m "x"'

# 17m — a malformed table row (stray literal | shears a cell) → block.
h17m=$(make_home)
write_plan "$h17m" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_malformed")" > /dev/null
expect_block "v10 17m malformed row (extra literal |) → block" \
  "$h17m" 'git commit -m "x"' "malformed"

# --- v10.1: mid-discharge commits at the Verify gate ------------------------
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
write_plan "$h17n1" "$(v10_plan 5 "$v10_step5_base" "$v101_matrix_pending")" > /dev/null
expect_allow "v10.1 17n pending row without AC block at current 5 → allow" \
  "$h17n1" 'git commit -m "x"'

# 17n — pending row AND no auditor pointer → allow (the auditor is the
# Step-5 exit gate; it cannot have run while rows are pending).
h17n2=$(make_home)
write_plan "$h17n2" "$(v10_plan 5 "$v101_step5_noauditor" "$v101_matrix_pending")" > /dev/null
expect_allow "v10.1 17n pending row + no auditor pointer at current 5 → allow" \
  "$h17n2" 'git commit -m "x"'

# 17n — blocked row, no auditor pointer → allow (same relaxation).
h17n3=$(make_home)
write_plan "$h17n3" "$(v10_plan 5 "$v101_step5_noauditor" "$v101_matrix_blocked")" > /dev/null
expect_allow "v10.1 17n blocked row + no auditor pointer at current 5 → allow" \
  "$h17n3" 'git commit -m "x"'

# 17n — pending row with a partial block carrying a live-tier n/a → allow
# at current 5 (deferred, not licensed: it blocks at discharge/advance).
h17n4=$(make_home)
write_plan "$h17n4" "$(v10_plan 5 "$v10_step5_base" "$v101_matrix_pending_partial")" > /dev/null
expect_allow "v10.1 17n pending row with partial block (contact: n/a) at current 5 → allow" \
  "$h17n4" 'git commit -m "x"'

# 17o — fully discharged matrix + missing auditor pointer → still block
# (17j1 pins the same shape; this pins it against the v10.1 relaxation).
h17o1=$(make_home)
write_plan "$h17o1" "$(v10_plan 5 "$v101_step5_noauditor" "$v10_matrix_complete")" > /dev/null
expect_block "v10.1 17o fully discharged matrix + no auditor pointer → block" \
  "$h17o1" 'git commit -m "x"' "auditor"

# 17p — invalid status token → block, names the row and the enum.
h17p1=$(make_home)
write_plan "$h17p1" "$(v10_plan 5 "$v10_step5_base" "$v101_matrix_bad_status")" > /dev/null
expect_block "v10.1 17p invalid status 'done' at current 5 → block (enum)" \
  "$h17p1" 'git commit -m "x"' "invalid status"

h17p2=$(make_home)
write_plan "$h17p2" "$(v10_plan 6 "$v10_step6_body" "$v101_matrix_bad_status")" > /dev/null
expect_block "v10.1 17p invalid status 'done' at current 6 → block (enum)" \
  "$h17p2" 'git commit -m "x"' "invalid status"

# 17q — the relaxation is 5-only: a pending row at current: 6 blocks (its
# per-tier keys are demanded by the prefix check).
h17q=$(make_home)
write_plan "$h17q" "$(v10_plan 6 "$v10_step6_body" "$v101_matrix_pending")" > /dev/null
expect_block "v10.1 17q pending row at current 6 → block (relaxation is 5-only)" \
  "$h17q" 'git commit -m "x"' "AC-2"

# ============================================================
# Section 18: v10 matrix parser — section scoping + fenced-code skip
# ============================================================
#
# The v10 matrix validator reads every parse (stack-health, false-green,
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
echo "=== Section 18: v10 matrix section scoping + fenced-code skip ==="

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
v10_matrix_fence_after="$v10_matrix_complete

$v10_fence_block"

h18a=$(make_home)
write_plan "$h18a" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_fence_after")" > /dev/null
expect_allow "v10 18a fenced jq (leading-pipe) inside matrix section at current 5 → allow" \
  "$h18a" 'git commit -m "x"'

# (b) A leading-pipe line OUTSIDE the matrix section (a later ## section),
# not fenced → allow. Pins that row grammar is scoped to the matrix section.
h18b=$(make_home)
write_plan "$h18b" "$(v10_frontmatter true)
## SDLC State
current: 5
Step 5:
$v10_step5_base

$v10_matrix_complete

## Notes
| this stray pipe line lives outside the matrix section
| and must never be read as a table row" > /dev/null
expect_allow "v10 18b leading-pipe line outside the matrix section → allow" \
  "$h18b" 'git commit -m "x"'

# (c) A fenced pipeline (skipped) AND a genuinely malformed table row (a
# stray literal | shears a cell) → still block. Pins that fence-skip does
# not suppress real malformed rows.
v10_matrix_fence_and_malformed="## Verification Matrix

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
write_plan "$h18c" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_fence_and_malformed")" > /dev/null
expect_block "v10 18c fenced pipeline + genuinely malformed row → block (malformed)" \
  "$h18c" 'git commit -m "x"' "malformed"

# (d) A fenced pipeline placed between stack-health and the table (mid-
# section), containing leading-pipe lines → allow. Pins that fence-skip works
# anywhere in the section, not just at the tail.
v10_matrix_fence_before_table="## Verification Matrix

stack-health: n/a: no long-running serve

$v10_fence_block

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |

AC-1:
  tier-run: bash test.sh
  readback: 40/40 asserted"

h18d=$(make_home)
write_plan "$h18d" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_fence_before_table")" > /dev/null
expect_allow "v10 18d fenced pipeline before the table (mid-section) → allow" \
  "$h18d" 'git commit -m "x"'

# ============================================================
# Section 19: v11 — triple re-key, task ledger, merge-target
# ============================================================
#
# v11 re-keys plans from `mode:` to the intent × rigor × scale triple. For
# the evidence gate two shapes matter:
#   (1) Wave/epic-scale v11 plans carry the v10 shape unchanged — pointer
#       steps 1..4, the Verification Matrix at the Verify gate, integrate=8,
#       ship=9. They join `dispatch_modern` via `v10|v11` case arms.
#   (2) Task-scale v11 plans (scale: task) address a ledger TASK, not a
#       numbered step: `current: T<n>` with a `## Tasks` registration table
#       and one `- T<n>:` evidence line per task in `## SDLC State`. The hook
#       MUST accept `current: T<n>` without blocking (structural correctness),
#       and validates the ledger LOG-ONLY (D14, check-id `task-ledger`):
#       missing `## Tasks`, status outside the enum, an active/done task with
#       no evidence line or a placeholder value — each appends one finding and
#       exits 0.
# A v11 wave plan naming an `epic:` also gets a LOG-ONLY merge-target check at
# the integrate step (check-id `merge-target`): a mismatch between the plan's
# `integration-branch:` and the epic plan's is logged, never blocks.
# All new read paths (epic plan, audit file) are fail-open; a `current: T<n>`
# on a v≤10 plan still blocks (T-format is v11 + scale:task only).

echo ""
echo "=== Section 19: v11 triple re-key, task ledger, merge-target ==="

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
  local af="$home_dir/.bionic/memory/sdlc-v11-audit.md"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$af" ] && grep -q "$substr" "$af"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected exit 0 + audit-file line '$substr'): $label"
    echo "  exit=$HOOK_EXIT audit='$( [ -f "$af" ] && cat "$af" )'"
    FAIL=$((FAIL + 1))
  fi
}

# v11 frontmatter: the triple replaces mode:. $1 scale, $2 deploy, $3
# use_worktree, $4 epic (omitted when empty).
v11_frontmatter() {
  local scale="${1:-wave}" deploy="${2:-none}" use_wt="${3:-false}" epic="${4:-}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 11\n'
  printf -- 'intent: build\n'
  printf -- 'rigor: audited\n'
  printf -- 'scale: %s\n' "$scale"
  printf -- 'deploy_target: %s\n' "$deploy"
  printf -- 'use_worktree: %s\n' "$use_wt"
  printf -- 'has_ui: false\n'
  [ -n "$epic" ] && printf -- 'epic: %s\n' "$epic"
  printf -- '---\n'
}

# A v11 wave plan (v10-shaped): frontmatter + ## SDLC State (current + Step
# block) + ## Verification Matrix. Reuses the Section-17 matrix fixtures.
v11_wave_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(v11_frontmatter wave)" "$1" "$1" "$2" "$3"
}

# A v11 wave plan naming an epic and carrying an integration-branch line, for
# the merge-target check. $1 current, $2 step body, $3 matrix, $4 epic,
# $5 integration-branch.
v11_wave_epic_plan() {
  printf '%s\n## SDLC State\nintegration-branch: %s\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(v11_frontmatter wave none false "$4")" "$5" "$1" "$1" "$2" "$3"
}

# A v11 task-scale plan: frontmatter (scale: task) + the given body (a
# ## Tasks table followed by ## SDLC State).
v11_task_plan() {
  printf '%s\n%s\n' "$(v11_frontmatter task)" "$1"
}

# A complete integrate (Step 8) block that passes the shape check, so the
# merge-target log-only check can be exercised in isolation.
v11_integrate_body="  merge: merged wave into epic/07-x
  worktree-removed: n/a
  cleanup: n/a"

# --- (2) wave/epic-scale v11 plans shape as v10 --------------------------

# 19a — v11 wave plan at Step 5 with an incomplete matrix (discharged T3 row
# with no AC block) → block, exactly like v10.
h19a=$(make_home)
write_plan "$h19a" "$(v11_wave_plan 5 "$v10_step5_base" "$v10_matrix_no_block")" > /dev/null
expect_block "v11 19a wave plan Step 5 incomplete matrix → block (shapes as v10)" \
  "$h19a" 'git commit -m "x"' "AC-1"

# 19b — v11 wave plan at Step 5 with a complete matrix + auditor pointer →
# allow (pointer/matrix evidence in place).
h19b=$(make_home)
write_plan "$h19b" "$(v11_wave_plan 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 19b wave plan Step 5 complete matrix → allow" \
  "$h19b" 'git commit -m "x"'

# 19c — step remap: integrate is Step 8. A v11 plan at current: 8 with a
# complete matrix but an integrate block missing merge/worktree-removed →
# block on the shape check (integrate fires at 8 as in v10).
h19c=$(make_home)
write_plan "$h19c" "$(v11_wave_plan 8 "  note: integrating now" "$v10_matrix_complete")" > /dev/null
expect_block "v11 19c integrate Step 8 missing merge fields → block (remap fires as v10)" \
  "$h19c" 'git commit -m "x"' "merge"

# 19c2 — Step 4 is a pointer step in v11 (as in v10): a pointer body allows.
h19c2=$(make_home)
write_plan "$h19c2" "$(v11_frontmatter wave)
## SDLC State
current: 4
Step 4: .bionic/docs/plans/wave.plan.md#step-4" > /dev/null
expect_allow "v11 19c2 wave plan Step 4 pointer → allow" \
  "$h19c2" 'git commit -m "x"'

# --- (2) task-scale ledger fixtures --------------------------------------

# Valid ledger: T1 done with evidence, T2 active with evidence; current: T2.
v11_ledger_valid="## Tasks

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
- T2: extracting helper on branch, commit def456"

# 19d — valid task ledger, current: T2 accepted → allow, no finding (BLOCKING-
# grade correctness: a false block here would be a defect).
h19d=$(make_home)
write_plan "$h19d" "$(v11_task_plan "$v11_ledger_valid")" > /dev/null
expect_allow "v11 19d task plan current: T2 valid ledger → allow (T-format accepted)" \
  "$h19d" 'git commit -m "x"'

# 19e — no ## Tasks section → exit 0 + task-ledger finding.
v11_ledger_no_tasks="## SDLC State

intent: build
rigor: peer-reviewed
scale: task
current: T2

- T2: some evidence"
h19e=$(make_home)
write_plan "$h19e" "$(v11_task_plan "$v11_ledger_no_tasks")" > /dev/null
expect_finding "v11 19e missing ## Tasks section → exit 0 + task-ledger finding" \
  "$h19e" 'git commit -m "x"' "task-ledger"

# 19e2 — the finding is written to the durable audit file with the D14 format.
h19e2=$(make_home)
write_plan "$h19e2" "$(v11_task_plan "$v11_ledger_no_tasks")" > /dev/null
expect_audit_line "v11 19e2 missing ## Tasks → audit file line (evidence-gate task-ledger)" \
  "$h19e2" 'git commit -m "x"' "evidence-gate task-ledger:"

# 19f — status outside the enum (doing) → exit 0 + finding.
v11_ledger_bad_status="${v11_ledger_valid/| T2 | refactor | peer-reviewed | extract the ledger helper | active |/| T2 | refactor | peer-reviewed | extract the ledger helper | doing |}"
h19f=$(make_home)
write_plan "$h19f" "$(v11_task_plan "$v11_ledger_bad_status")" > /dev/null
expect_finding "v11 19f invalid status 'doing' → exit 0 + task-ledger finding" \
  "$h19f" 'git commit -m "x"' "task-ledger"

# 19g — active task (T2) with no `- T2:` evidence line → exit 0 + finding.
v11_ledger_active_no_line="## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | refactor | peer-reviewed | extract the ledger helper | active |

## SDLC State

scale: task
current: T2

- T1: fixed in commit abc123, suite 5/5 green"
h19g=$(make_home)
write_plan "$h19g" "$(v11_task_plan "$v11_ledger_active_no_line")" > /dev/null
expect_finding "v11 19g active task without evidence line → exit 0 + task-ledger finding" \
  "$h19g" 'git commit -m "x"' "task-ledger"

# 19h — active task with a placeholder evidence value (`- T2: TBD`) → finding.
v11_ledger_active_placeholder="${v11_ledger_valid/- T2: extracting helper on branch, commit def456/- T2: TBD}"
h19h=$(make_home)
write_plan "$h19h" "$(v11_task_plan "$v11_ledger_active_placeholder")" > /dev/null
expect_finding "v11 19h active task placeholder evidence → exit 0 + task-ledger finding" \
  "$h19h" 'git commit -m "x"' "task-ledger"

# 19i — done task (T1) with an empty evidence line (`- T1:`) → finding.
v11_ledger_done_empty="${v11_ledger_valid/- T1: fixed in commit abc123, suite 5\/5 green/- T1:}"
h19i=$(make_home)
write_plan "$h19i" "$(v11_task_plan "$v11_ledger_done_empty")" > /dev/null
expect_finding "v11 19i done task missing evidence → exit 0 + task-ledger finding" \
  "$h19i" 'git commit -m "x"' "task-ledger"

# --- (2) task-scale CRLF -------------------------------------------------

# 19j — a valid task ledger with CRLF line endings → exit 0, no false finding
# (every parse path — frontmatter scale, current, ## Tasks, evidence lines —
# strips \r).
h19j=$(make_home)
write_plan "$h19j" "$(to_crlf "$(v11_task_plan "$v11_ledger_valid")")" > /dev/null
expect_allow "v11 19j CRLF task ledger → allow, no false finding" \
  "$h19j" 'git commit -m "x"'

# --- (4) epic merge-target consistency (log-only) ------------------------

# Build a project with an epic plan declaring integration-branch: epic/07-x.
make_epic_project() {
  local branch="$1"
  local proj
  proj=$(make_project)
  mkdir -p "$proj/.bionic/docs/plans/epic-fix"
  printf -- '---\ncanonical_sdlc_version: 11\nintent: build\nrigor: audited\nscale: epic\n---\n## SDLC State\nintegration-branch: %s\ncurrent: 1\n' \
    "$branch" > "$proj/.bionic/docs/plans/epic-fix/epic.plan.md"
  touch -t 202001010000 "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || \
    touch -d "2020-01-01" "$proj/.bionic/docs/plans/epic-fix/epic.plan.md" 2>/dev/null || true
  echo "$proj"
}

# 19k — plan integration-branch (main) mismatches the epic's (epic/07-x) at
# the integrate step → exit 0 + merge-target finding.
h19k=$(make_home); p19k=$(make_epic_project "epic/07-x")
write_project_plan "$p19k" \
  "$(v11_wave_epic_plan 8 "$v11_integrate_body" "$v10_matrix_complete" epic-fix main)" \
  "wave-newest.plan.md" > /dev/null
expect_finding_both "v11 19k merge-target mismatch → exit 0 + merge-target finding" \
  "$h19k" "$p19k" 'git commit -m "x"' "merge-target"

# 19l — matching integration-branch → no finding (silent allow).
h19l=$(make_home); p19l=$(make_epic_project "epic/07-x")
write_project_plan "$p19l" \
  "$(v11_wave_epic_plan 8 "$v11_integrate_body" "$v10_matrix_complete" epic-fix "epic/07-x")" \
  "wave-newest.plan.md" > /dev/null
expect_allow_both "v11 19l merge-target match → allow, no finding" \
  "$h19l" "$p19l" 'git commit -m "x"'

# --- (5) named v≤10 regressions ------------------------------------------

# 19m — a v10 plan with `current: T2` STILL blocks: the T-format is a v11 +
# scale:task feature only, never retrofitted onto v≤10.
h19m=$(make_home)
write_plan "$h19m" "---
canonical_sdlc_version: 10
mode: autonomous
---
## SDLC State
current: T2
Step 5: whatever" > /dev/null
expect_block "v11 19m v10 plan with current: T2 still blocks (T-format is v11+task only)" \
  "$h19m" 'git commit -m "x"' "valid"

# 19n — a v9 plan at a pointer step is untouched (v9 path unchanged).
h19n=$(make_home)
write_plan "$h19n" "---
canonical_sdlc_version: 9
---
## SDLC State
current: 6
Step 6: .bionic/docs/plans/wave.plan.md#step-6" > /dev/null
expect_allow "v11 19n v9 pointer step untouched (named v≤10 regression)" \
  "$h19n" 'git commit -m "x"'

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
# A v10 plan whose body documents the task-scale schema in a fenced block
# BEFORE the real section must validate against the REAL `## SDLC State`
# (current: 5 + complete matrix), not the shadowed `current: T2`. Before the
# fix the fence-blind awk captured the fenced `current: T2` first →
# CURRENT=T2 → non-numeric → false block. Same defect class the matrix parser
# fixed (fence-blind row parsing). This fix removes false blocks, adds none.
h19o=$(make_home)
write_plan "$h19o" "$(v10_frontmatter true)

Doc note — the task-scale ledger schema (D12) looks like:

$v11_fenced_sdlcstate_shadow

## SDLC State
current: 5
Step 5:
$v10_step5_base

$v10_matrix_complete" > /dev/null
expect_allow "v11 19o fenced ## SDLC State shadow before real section → validates real section (allow)" \
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
write_plan "$h19p" "$(v11_frontmatter task)

Example ledger:

$v11_fenced_tasks_shadow

$v11_ledger_valid" > /dev/null
expect_allow "v11 19p fenced ## Tasks example before real table → no false finding (fence-aware)" \
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
expect_allow "v11 19q fenced-only ## SDLC State (no real section) → pass through as non-canonical" \
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
canonical_sdlc_version: 11
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
  "$(v11_wave_epic_plan 8 "$v11_integrate_body" "$v10_matrix_complete" epic-fix "epic/07-x")" \
  "wave-newest.plan.md" > /dev/null
expect_allow_both "v11 19r fenced ## SDLC State in epic plan → merge-target reads real section (silent)" \
  "$h19r" "$p19r" 'git commit -m "x"'

# ============================================================
# Section 20: v11 — intent-scoped Step-5 evidence keys (R7, log-only)
# ============================================================
#
# v11 plans declare an `intent:` in frontmatter. Two intents carry a
# conditional Step-5 evidence key set, checked LOG-ONLY (D14) at the Verify
# gate — never blocks:
#   - refactor: requires `behavior-preservation:` (non-empty); `compat-matrix:`
#     and `revert-plan:` are optional but must not be present-and-empty.
#   - tune: requires `baseline:`, `target:`, `re-measure:` (all non-empty).
# Any other intent (e.g. build) gets no check at all — this is intent-scoped,
# not a universal Step-5 key like bundle-fresh/drive-check/stack-health. A
# v10 plan (no `intent:` line) must be byte-identical to its pre-R7 behavior
# — no audit write, no finding.

echo ""
echo "=== Section 20: v11 intent-scoped Step-5 evidence keys (R7, log-only) ==="

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

# Asserts exit 0, empty stderr, AND that the durable audit file was never
# created — the named v10 grandfather regression (20f) needs the stronger
# "no write at all" guarantee, not just "no finding printed this run".
expect_no_audit_write() {
  local label="$1" home_dir="$2" command="$3"
  TOTAL=$((TOTAL + 1))
  run_hook "$home_dir" "$command"
  local af="$home_dir/.bionic/memory/sdlc-v11-audit.md"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ] && [ ! -f "$af" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected allow exit 0 + no audit file): $label"
    echo "  exit=$HOOK_EXIT stderr='$HOOK_STDERR' audit_exists=$( [ -f "$af" ] && echo yes || echo no )"
    FAIL=$((FAIL + 1))
  fi
}

# v11 frontmatter with a caller-chosen intent (Section 19's v11_frontmatter
# hardcodes intent: build). $1 intent, $2 scale (default wave).
v20_frontmatter() {
  local intent="$1" scale="${2:-wave}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 11\n'
  printf -- 'intent: %s\n' "$intent"
  printf -- 'rigor: audited\n'
  printf -- 'scale: %s\n' "$scale"
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: false\n'
  printf -- '---\n'
}

# A v11 wave plan with the given intent, at the given current/Step-5 body/
# matrix. $1 intent, $2 current, $3 Step-block body, $4 matrix.
v20_wave_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\nStep %s:\n%s\n\n%s\n' \
    "$(v20_frontmatter "$1")" "$2" "$2" "$3" "$4"
}

# Refactor Step-5 body with behavior-preservation already satisfied — the
# base for the compat-matrix/revert-plan sub-cases (20c), which isolate
# that one axis by keeping behavior-preservation clean.
v20_refactor_body_ok="$v10_step5_base
  behavior-preservation: suites 211/211 pre @abc, 211/211 post @def"

# --- 20a/20b: refactor — behavior-preservation required ------------------

# 20a — refactor plan, valid tests floor + matrix, NO behavior-preservation
# key → exit 0 + refactor-evidence finding on stderr AND in the audit file.
h20a=$(make_home)
write_plan "$h20a" "$(v20_wave_plan refactor 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_finding "v11 20a refactor plan missing behavior-preservation → finding" \
  "$h20a" 'git commit -m "x"' "canonical-sdlc v11 \[refactor-evidence\]"
h20a2=$(make_home)
write_plan "$h20a2" "$(v20_wave_plan refactor 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_audit_line "v11 20a2 refactor plan missing behavior-preservation → audit file line" \
  "$h20a2" 'git commit -m "x"' "evidence-gate refactor-evidence:"

# 20b — same plan + behavior-preservation present → exit 0, NO finding.
h20b=$(make_home)
write_plan "$h20b" "$(v20_wave_plan refactor 5 "$v20_refactor_body_ok" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 20b refactor plan with behavior-preservation → allow, no finding" \
  "$h20b" 'git commit -m "x"'

# --- 20c: refactor — compat-matrix/revert-plan optional-but-not-empty ----

# 20c1 — compat-matrix present but empty → refactor-evidence finding.
h20c1=$(make_home)
write_plan "$h20c1" "$(v20_wave_plan refactor 5 "$v20_refactor_body_ok
  compat-matrix:" "$v10_matrix_complete")" > /dev/null
expect_finding "v11 20c1 refactor compat-matrix present but empty → finding" \
  "$h20c1" 'git commit -m "x"' "compat-matrix"

# 20c2 — compat-matrix: n/a: not a migration (non-empty) → clean.
h20c2=$(make_home)
write_plan "$h20c2" "$(v20_wave_plan refactor 5 "$v20_refactor_body_ok
  compat-matrix: n/a: not a migration" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 20c2 refactor compat-matrix non-empty n/a → allow, no finding" \
  "$h20c2" 'git commit -m "x"'

# 20c3 — compat-matrix/revert-plan entirely absent → clean (they are
# optional; only presence-and-empty is a finding).
h20c3=$(make_home)
write_plan "$h20c3" "$(v20_wave_plan refactor 5 "$v20_refactor_body_ok" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 20c3 refactor compat-matrix/revert-plan absent → allow, no finding" \
  "$h20c3" 'git commit -m "x"'

# --- 20d: tune — baseline/target/re-measure all required ------------------

# 20d1 — tune plan missing all three keys → exactly THREE tune-evidence
# findings (assert count, not just "at least one").
h20d1=$(make_home)
write_plan "$h20d1" "$(v20_wave_plan tune 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_finding_count "v11 20d1 tune plan missing baseline/target/re-measure → 3 findings" \
  "$h20d1" 'git commit -m "x"' "tune-evidence" 3

# 20d2 — tune plan with all three non-empty → clean.
v20_tune_body_ok="$v10_step5_base
  baseline: p95 340ms @abc
  target: p95 <= 200ms
  re-measure: p95 190ms @def"
h20d2=$(make_home)
write_plan "$h20d2" "$(v20_wave_plan tune 5 "$v20_tune_body_ok" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 20d2 tune plan with baseline/target/re-measure → allow, no finding" \
  "$h20d2" 'git commit -m "x"'

# --- 20e: build — intent-scoped, not universal ----------------------------

# 20e — build intent with none of the refactor/tune keys → NO finding (these
# checks are intent-scoped; build never triggers them).
h20e=$(make_home)
write_plan "$h20e" "$(v20_wave_plan build 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 20e build plan with no intent-scoped keys → allow, no finding" \
  "$h20e" 'git commit -m "x"'

# --- 20f: named v10 grandfather regression --------------------------------

# 20f — a v10 plan (no `intent:` line) at current: 5 with valid v10 evidence
# → exit 0, no finding, NO audit-file write at all. R7 must be invisible to
# v10 plans.
h20f=$(make_home)
write_plan "$h20f" "$(v10_plan 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_no_audit_write "v11 20f v10 plan (no intent:) → allow, no audit write (grandfather)" \
  "$h20f" 'git commit -m "x"'

# --- 20g/20h: R7 keys are truly log-only (critic Issue 1) ------------------
#
# The universal placeholder ban (the whole-Step-block scan a few hundred
# lines up) used to scan these six v11-intent-scoped keys too, so a
# placeholder R7 value BLOCKED the commit — contradicting the ratified
# log-only contract. R7 keys are exempted from that ban on v11 plans only
# (version-gated: v≤10 plans still block on a stray placeholder R7-named
# line — see 20i); validate_intent_evidence itself now treats a placeholder
# value the same as missing/empty, so the finding still fires.

# 20g — refactor plan, behavior-preservation: TODO (placeholder value, not
# missing) → exit 0 + refactor-evidence finding + audit line (was BLOCKED).
h20g=$(make_home)
write_plan "$h20g" "$(v20_wave_plan refactor 5 "$v10_step5_base
  behavior-preservation: TODO" "$v10_matrix_complete")" > /dev/null
expect_finding "v11 20g refactor behavior-preservation: TODO → allow + refactor-evidence finding" \
  "$h20g" 'git commit -m "x"' "canonical-sdlc v11 \[refactor-evidence\]"
h20g2=$(make_home)
write_plan "$h20g2" "$(v20_wave_plan refactor 5 "$v10_step5_base
  behavior-preservation: TODO" "$v10_matrix_complete")" > /dev/null
expect_audit_line "v11 20g2 refactor behavior-preservation: TODO → audit file line" \
  "$h20g2" 'git commit -m "x"' "evidence-gate refactor-evidence:"

# 20h — tune plan, baseline: tbd (placeholder), target/re-measure valid →
# exit 0 + exactly ONE tune-evidence finding (not three — the other two
# keys are present and non-placeholder).
h20h=$(make_home)
write_plan "$h20h" "$(v20_wave_plan tune 5 "$v10_step5_base
  baseline: tbd
  target: p95 <= 200ms
  re-measure: p95 190ms @def" "$v10_matrix_complete")" > /dev/null
expect_finding_count "v11 20h tune baseline: tbd (rest valid) → exactly 1 tune-evidence finding" \
  "$h20h" 'git commit -m "x"' "tune-evidence" 1

# --- 20i: NAMED grandfather regression (version-gated exemption) -----------
#
# A v10 plan (no `intent:`) with a stray `baseline: TODO` line in its Step-5
# block must STILL block — the R7 exemption from the universal ban is
# version-gated to v11 only. Byte-identical to pre-R7 behavior.
h20i=$(make_home)
write_plan "$h20i" "$(v10_plan 5 "$v10_step5_base
  baseline: TODO" "$v10_matrix_complete")" > /dev/null
expect_block "v11 20i v10 plan stray 'baseline: TODO' → still BLOCKED (grandfather, version-gated)" \
  "$h20i" 'git commit -m "x"' "is a placeholder"

# --- 20j: NAMED regression — n/a is not a placeholder on the new path ------
#
# v11 refactor plan with compat-matrix: n/a: not a migration must stay
# clean — "n/a: <reason>" is explicit non-applicability, not a placeholder
# token, so neither the ban-loop exemption path nor validate_intent_evidence's
# placeholder-aware check may flag it.
h20j=$(make_home)
write_plan "$h20j" "$(v20_wave_plan refactor 5 "$v20_refactor_body_ok
  compat-matrix: n/a: not a migration" "$v10_matrix_complete")" > /dev/null
expect_allow "v11 20j refactor compat-matrix: n/a: not a migration → allow, no finding" \
  "$h20j" 'git commit -m "x"'

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
# line lands in the FIXTURE project's .bionic/memory/sdlc-v11-audit.md, and
# that NO .bionic/ gets created under the sibling (no cwd leak).
h21a=$(make_home)
fixture21a=$(make_project)
elsewhere21a=$(mktemp -d); cleanup_dirs+=("$elsewhere21a")
write_project_plan "$fixture21a" "$(v20_wave_plan tune 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
TOTAL=$((TOTAL + 1))
run_hook_project_elsewhere_cwd "$h21a" "$fixture21a" "$elsewhere21a" 'git commit -m "x"'
fixture_audit="$fixture21a/.bionic/memory/sdlc-v11-audit.md"
if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$fixture_audit" ] && grep -q "tune-evidence" "$fixture_audit" \
  && [ ! -d "$elsewhere21a/.bionic" ]; then
  echo "PASS: v11 21a audit line follows the plan's fixture project, not the invoking cwd"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected fixture audit line + no .bionic under elsewhere cwd): v11 21a"
  echo "  exit=$HOOK_EXIT fixture_audit_exists=$([ -f "$fixture_audit" ] && echo yes || echo no) elsewhere_bionic=$([ -d "$elsewhere21a/.bionic" ] && echo yes || echo no)"
  FAIL=$((FAIL + 1))
fi

# 21b — fail-open fallback: plan reached only via the ~/.claude/plans global
# convention (Section 19/20's usual fixture), whose ancestry has no .bionic/
# directory anywhere above it. audit_root's walk-up exhausts without a match
# and falls back to $PROJECT_DIR (== $h21b here, via the cwd field) — hook
# still exits 0 and still writes the audit line, unblocked.
h21b=$(make_home)
write_plan "$h21b" "$(v20_wave_plan tune 5 "$v10_step5_base" "$v10_matrix_complete")" > /dev/null
expect_audit_line "v11 21b fail-open: no .bionic ancestor above the plan → PROJECT_DIR fallback used" \
  "$h21b" 'git commit -m "x"' "tune-evidence"

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
