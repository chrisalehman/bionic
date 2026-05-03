#!/bin/bash
# Tests for canonical-sdlc-dispatch-gate.sh
#
# Strategy: build temp project trees with synthetic plan files +
# rules.json, drive the hook via stdin JSON simulating Agent tool
# calls. CLAUDE_PROJECT_DIR points at the temp project root so the
# hook's audit log lands inside the temp dir (auto-cleaned).
#
# Usage: bash hooks/canonical-sdlc-dispatch-gate.test.sh

set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/canonical-sdlc-dispatch-gate.sh"
RULES_TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)/skills/canonical-sdlc/sdlc-dispatch-rules.json"
PASS=0
FAIL=0
TOTAL=0

cleanup_dirs=()
cleanup() {
  for d in "${cleanup_dirs[@]}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# Build a temp project with a docs/bionic/plans/<plan>.md and
# (optionally) a .bionic/sdlc-dispatch-rules.json. Returns the project
# root path.
make_project() {
  local plan_body="$1"
  local plan_name="${2:-test.plan.md}"
  local rules="${3:-default}"     # "default" | "none" | "<json>"
  local dir
  dir=$(mktemp -d)
  cleanup_dirs+=("$dir")
  mkdir -p "$dir/docs/bionic/plans/epic-01-demo"
  printf '%s' "$plan_body" > "$dir/docs/bionic/plans/epic-01-demo/${plan_name}"
  if [ "$rules" = "default" ]; then
    mkdir -p "$dir/.bionic"
    cp "$RULES_TEMPLATE" "$dir/.bionic/sdlc-dispatch-rules.json"
  elif [ "$rules" = "none" ]; then
    :
  else
    mkdir -p "$dir/.bionic"
    printf '%s' "$rules" > "$dir/.bionic/sdlc-dispatch-rules.json"
  fi
  echo "$dir"
}

# Run the hook with a synthetic Agent tool call. Captures HOOK_EXIT
# and HOOK_STDERR.
run_agent() {
  local project_dir="$1" subagent_type="$2" prompt="${3:-}"
  local input
  input=$(jq -n \
    --arg cwd "$project_dir" \
    --arg sa "$subagent_type" \
    --arg pr "$prompt" \
    '{tool_name:"Agent", cwd:$cwd, tool_input:{subagent_type:$sa, prompt:$pr}}')
  local tmp_err
  tmp_err=$(mktemp)
  if CLAUDE_PROJECT_DIR="$project_dir" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

# Same as run_agent but for an arbitrary tool name (used for the
# "non-Agent tool passes through" case).
run_other_tool() {
  local project_dir="$1" tool_name="$2"
  local input
  input=$(jq -n --arg cwd "$project_dir" --arg t "$tool_name" \
    '{tool_name:$t, cwd:$cwd, tool_input:{}}')
  local tmp_err
  tmp_err=$(mktemp)
  if CLAUDE_PROJECT_DIR="$project_dir" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n        expected: %q\n        actual:   %q\n' \
      "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" <<< "$haystack"; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s (missing: %q in: %q)\n' "$label" "$needle" "$haystack"
  fi
}

assert_audit_entry() {
  local label="$1" project_dir="$2" needle="$3"
  local audit="$project_dir/.bionic/memory/dispatch-audit.md"
  TOTAL=$((TOTAL + 1))
  if [ -f "$audit" ] && grep -qF -- "$needle" "$audit"; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s (audit missing or no match for %q)\n' "$label" "$needle"
    [ -f "$audit" ] && printf '        audit content: %q\n' "$(cat "$audit")"
  fi
}

assert_no_audit() {
  local label="$1" project_dir="$2"
  local audit="$project_dir/.bionic/memory/dispatch-audit.md"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$audit" ] || [ ! -s "$audit" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s (audit file should be empty/absent: %q)\n' "$label" "$(cat "$audit")"
  fi
}

# ---------- helpers to build plan fixtures ----------

# All v2 plans share a common header. Caller passes step + flag overrides.
v2_plan() {
  local step="$1" surface_type="${2:-none}" language="${3:-none}" \
        perf_critical="${4:-false}" security_boundary="${5:-false}" \
        distributed="${6:-false}" has_ui="${7:-false}" \
        multi_agent="${8:-false}" deploy_target="${9:-none}" \
        dispatch_enforce="${10:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: ${step}
canonical_sdlc_version: 2
narrative_verbose: false
dispatch_enforce: ${dispatch_enforce}
cleanup_on_finish: false
archived: false
surface_type: ${surface_type}
language: ${language}
perf_critical: ${perf_critical}
security_boundary: ${security_boundary}
distributed: ${distributed}
has_ui: ${has_ui}
multi_agent: ${multi_agent}
deploy_target: ${deploy_target}
---

## SDLC State
mode: autonomous
current: ${step}
EOF
}

V1_LEGACY_PLAN='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 1
sdlc-step: 5
---

## SDLC State
mode: autonomous
current: 5
'

NON_CANONICAL_PLAN='---
governing-skill: superpowers:writing-plans
mode: full
sdlc-step: 5
---

# Plan body
'

NON_AUTONOMOUS_PLAN='---
governing-skill: canonical-sdlc
mode: design-refresh
sdlc-step: 5
canonical_sdlc_version: 2
---

# Plan body
'

# ============================================================
# Test cases
# ============================================================

echo "1. Tool name not Agent (e.g. Bash) → allow"
proj=$(make_project "$(v2_plan 5 none typescript)")
run_other_tool "$proj" "Bash"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "2. No plan file at all → allow"
proj_empty=$(mktemp -d); cleanup_dirs+=("$proj_empty")
mkdir -p "$proj_empty/docs/bionic/plans"
input=$(jq -n --arg cwd "$proj_empty" \
  '{tool_name:"Agent", cwd:$cwd, tool_input:{subagent_type:"voltagent-lang:typescript-pro", prompt:""}}')
HOOK_EXIT=0
if ! CLAUDE_PROJECT_DIR="$proj_empty" bash "$HOOK" <<< "$input" >/dev/null 2>&1; then
  HOOK_EXIT=$?
fi
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "3. governing-skill != canonical-sdlc → allow"
proj=$(make_project "$NON_CANONICAL_PLAN")
run_agent "$proj" "voltagent-qa-sec:code-reviewer"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "4. mode != autonomous → allow"
proj=$(make_project "$NON_AUTONOMOUS_PLAN")
run_agent "$proj" "voltagent-qa-sec:code-reviewer"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "5. v1 legacy plan (canonical_sdlc_version: 1) → allow (legacy-skip)"
proj=$(make_project "$V1_LEGACY_PLAN")
run_agent "$proj" "voltagent-lang:rust-engineer"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "6. Step 5, language=typescript, dispatch typescript-pro → allow"
proj=$(make_project "$(v2_plan 5 none typescript)")
run_agent "$proj" "voltagent-lang:typescript-pro"
assert_eq "exit 0" 0 "$HOOK_EXIT"
assert_no_audit "no audit entry on match" "$proj"

echo "7. Step 5, language=typescript, dispatch rust-engineer (mismatch), enforce=false → log + allow"
proj=$(make_project "$(v2_plan 5 none typescript)")
run_agent "$proj" "voltagent-lang:rust-engineer"
assert_eq "exit 0 (log-only)" 0 "$HOOK_EXIT"
assert_audit_entry "audit names expected agent (typescript-pro)" "$proj" "voltagent-lang:typescript-pro"
assert_audit_entry "audit names actual agent (rust-engineer)" "$proj" "voltagent-lang:rust-engineer"
assert_audit_entry "audit tagged log-only" "$proj" "log-only"

echo "8. Same mismatch, enforce=true → block, error names typescript-pro"
proj=$(make_project "$(v2_plan 5 none typescript false false false false false none true)")
run_agent "$proj" "voltagent-lang:rust-engineer"
assert_eq "exit 2" 2 "$HOOK_EXIT"
assert_contains "stderr names required agent" "voltagent-lang:typescript-pro" "$HOOK_STDERR"

echo "9. Step 8 (always parallel), dispatch one of two required → allow"
proj=$(make_project "$(v2_plan 8)")
run_agent "$proj" "voltagent-qa-sec:code-reviewer"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "10. Step 8 parallel, dispatch a third agent (mismatch), enforce=true → block"
proj=$(make_project "$(v2_plan 8 none none false false false false false none true)")
run_agent "$proj" "voltagent-qa-sec:performance-engineer"
assert_eq "exit 2" 2 "$HOOK_EXIT"
assert_contains "stderr names code-reviewer" "voltagent-qa-sec:code-reviewer" "$HOOK_STDERR"
assert_contains "stderr names security-auditor" "voltagent-qa-sec:security-auditor" "$HOOK_STDERR"

echo "11. Step 8 parallel mismatch, enforce=false → log + allow"
proj=$(make_project "$(v2_plan 8)")
run_agent "$proj" "voltagent-qa-sec:performance-engineer"
assert_eq "exit 0 (log-only)" 0 "$HOOK_EXIT"
assert_audit_entry "parallel mismatch logged" "$proj" "voltagent-qa-sec:performance-engineer"

echo "12. Step 1 → default agent: null → allow any subagent_type"
proj=$(make_project "$(v2_plan 1)")
run_agent "$proj" "voltagent-lang:rust-engineer"
assert_eq "exit 0" 0 "$HOOK_EXIT"
assert_no_audit "no audit on null-agent phase" "$proj"

echo "13. dispatch_override:\"reason\" in prompt → log + allow regardless of subagent_type"
proj=$(make_project "$(v2_plan 5 none typescript false false false false false none true)")
run_agent "$proj" "voltagent-lang:rust-engineer" 'Migrating SQL+TS together. dispatch_override:"single-agent fullstack reroute"'
assert_eq "exit 0 (override)" 0 "$HOOK_EXIT"
assert_audit_entry "override reason recorded" "$proj" "single-agent fullstack reroute"
assert_audit_entry "override marked override" "$proj" "override"

echo "14. Rules JSON missing → allow"
proj=$(make_project "$(v2_plan 5 none typescript)" "test.plan.md" "none")
run_agent "$proj" "voltagent-lang:rust-engineer"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "15. Rules JSON malformed → allow with warning (fail-open)"
proj=$(make_project "$(v2_plan 5 none typescript)" "test.plan.md" "{ malformed json")
run_agent "$proj" "voltagent-lang:rust-engineer"
assert_eq "exit 0 (fail-open)" 0 "$HOOK_EXIT"
assert_contains "stderr warns about malformed rules" "malformed" "$HOOK_STDERR"

echo "16. Step 8b with security_boundary=true → penetration-tester required"
proj=$(make_project "$(v2_plan 8b none none false true false false false none true)")
run_agent "$proj" "voltagent-qa-sec:debugger"
assert_eq "exit 2" 2 "$HOOK_EXIT"
assert_contains "stderr names penetration-tester" "voltagent-qa-sec:penetration-tester" "$HOOK_STDERR"

echo "17. Step 8b with security_boundary=true → dispatching penetration-tester allowed"
proj=$(make_project "$(v2_plan 8b none none false true)")
run_agent "$proj" "voltagent-qa-sec:penetration-tester"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "18. Step 3, multi_agent=true → enforce agent-organizer (above workflow-orchestrator)"
proj=$(make_project "$(v2_plan 3 system none false false false false true none true)")
run_agent "$proj" "voltagent-meta:workflow-orchestrator"
assert_eq "exit 2" 2 "$HOOK_EXIT"
assert_contains "stderr names agent-organizer" "voltagent-meta:agent-organizer" "$HOOK_STDERR"

echo "19. Step 5, surface_type=mobile && language=swift → swift-expert"
proj=$(make_project "$(v2_plan 5 mobile swift false false false false false none true)")
run_agent "$proj" "voltagent-lang:typescript-pro"
assert_eq "exit 2" 2 "$HOOK_EXIT"
assert_contains "stderr names swift-expert" "voltagent-lang:swift-expert" "$HOOK_STDERR"

echo "20. Step 5, default → agent: null → allow any (language=none, surface_type=none)"
proj=$(make_project "$(v2_plan 5)")
run_agent "$proj" "voltagent-lang:typescript-pro"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
