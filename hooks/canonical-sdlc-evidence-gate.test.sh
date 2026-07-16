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
  input=$(jq -n --arg c "$command" '{tool_input: {command: $c}}')
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
  input=$(jq -n --arg c "$command" '{tool_input: {command: $c}}')
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

# Case-insensitive placeholder match
h5b=$(make_home)
write_plan "$h5b" "## SDLC State
current: 5
Phase 5: Todo — still writing" > /dev/null
expect_block "placeholder 'Todo' (mixed case)" "$h5b" 'git commit -m "x"' "placeholder"

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
