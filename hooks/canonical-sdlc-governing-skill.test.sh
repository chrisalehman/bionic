#!/bin/bash
# Tests for canonical-sdlc-governing-skill.sh
#
# Strategy: build synthetic Write/Edit tool_input payloads that target
# files in a temp project dir. No HOME override needed — the hook only
# inspects the posted JSON and, for Edit, reads the file at the given
# path.
#
# Usage: bash hooks/canonical-sdlc-governing-skill.test.sh

set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/canonical-sdlc-governing-skill.sh"
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

make_project() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans/epic-01-demo"
  mkdir -p "$dir/.bionic/docs/specs/epic-01-demo"
  mkdir -p "$dir/.bionic/docs/adrs/epic-01-demo"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# Runs hook with a synthetic Write payload for $FILE with $CONTENT.
run_write() {
  local file_path="$1" content="$2"
  local input
  input=$(jq -n \
    --arg p "$file_path" \
    --arg c "$content" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  local tmp_err
  tmp_err=$(mktemp)
  if bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

run_edit() {
  local file_path="$1" old_str="$2" new_str="$3"
  local input
  input=$(jq -n \
    --arg p "$file_path" \
    --arg o "$old_str" \
    --arg n "$new_str" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}')
  local tmp_err
  tmp_err=$(mktemp)
  if bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
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
    printf '  FAIL  %s (expected=%q actual=%q)\n' "$label" "$expected" "$actual"
  fi
}

# Asserts $3 (haystack, typically $HOOK_STDERR) contains substring $2.
# Same PASS/FAIL accounting + output shape as the inline `case` idiom
# used throughout this file, hoisted to a helper for the v11 section's
# many stderr-substring checks.
assert_contains() {
  local label="$1" needle="$2" hay="$3"
  TOTAL=$((TOTAL + 1))
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)); printf '  PASS  %s\n' "$label" ;;
    *) FAIL=$((FAIL + 1)); printf '  FAIL  %s (missing %q in %q)\n' "$label" "$needle" "$hay" ;;
  esac
}

VALID_FRONTMATTER='---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-01-demo
wave: wave-01-x
mode: full
---

# Plan body
'

MISSING_FM='# Plan body, no frontmatter
'

EMPTY_GOVERNING='---
governing-skill:
sdlc-step: 3
---
body
'

# ---------- cases ----------

project=$(make_project)

echo "Write: plan file with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: plan file missing frontmatter → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: plan file with empty governing-skill → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$EMPTY_GOVERNING"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: spec file with valid frontmatter → allow"
run_write "$project/.bionic/docs/specs/epic-01-demo/wave-01-x.spec.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: adr file with valid frontmatter → allow"
run_write "$project/.bionic/docs/adrs/epic-01-demo/adr-001-x.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: continuation.md with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: continuation-checkpoint.md with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation-checkpoint.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: README.md under plans dir, no frontmatter → allow (not an enforced artifact)"
run_write "$project/.bionic/docs/plans/epic-01-demo/README.md" "# some notes"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: .plan.md OUTSIDE any .bionic/-rooted project → allow (hook scope is path-gated)"
outside=$(mktemp -d)
cleanup_dirs+=("$outside")
run_write "$outside/random.plan.md" "$MISSING_FM"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: adr-named file under adrs/ missing frontmatter → block"
run_write "$project/.bionic/docs/adrs/epic-01-demo/adr-007-x.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit: existing file with valid frontmatter → allow"
existing="$project/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md"
printf '%s' "$VALID_FRONTMATTER" > "$existing"
run_edit "$existing" "Plan body" "Updated body"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Edit: existing file missing frontmatter → block"
bad="$project/.bionic/docs/plans/epic-01-demo/wave-03-z.plan.md"
printf '%s' "$MISSING_FM" > "$bad"
run_edit "$bad" "Plan body" "Updated body"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit: file doesn't exist (Edit would fail anyway) → block"
run_edit "$project/.bionic/docs/plans/epic-01-demo/does-not-exist.plan.md" "x" "y"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Bash tool (non-Write/Edit) → allow"
input=$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')
HOOK_EXIT=0
if ! bash "$HOOK" <<< "$input" >/dev/null 2>&1; then
  HOOK_EXIT=$?
fi
assert_eq "exit 0" 0 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version v1/v2/v3/v4 enforcement
# ============================================================
#
# Schema:
#   - canonical_sdlc_version: 1 → legacy-skip (grandfathered)
#   - canonical_sdlc_version: 2 → legacy-skip (grandfathered)
#   - canonical_sdlc_version: 3 + mode: autonomous
#       → require all 2 v3 opt-in flags + 5 discriminator flags
#   - canonical_sdlc_version: 4 + mode: autonomous
#       → require the v3 set PLUS model_plan
#   - canonical_sdlc_version absent → not v3-managed; pass through
#   - canonical_sdlc_version with other value → block

V1_LEGACY='---
governing-skill: canonical-sdlc
sdlc-step: N/A
epic: N/A
wave: N/A
mode: N/A
canonical_sdlc_version: 1
evidence_schema: legacy
created: 2026-04-24
---

# Body
'

V2_LEGACY='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 2
---

# Body (legacy v2 plan — no v3 enforcement)
'

# Helper to build a v3 plan with optional omissions. Pass the names of
# flags to omit as args; everything else is included.
build_v3_plan() {
  local omit=" $* "
  local out='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 4
canonical_sdlc_version: 3
'
  local opt_in=("cleanup_on_finish:true" "use_worktree:false")
  local discriminators=("surface_type:none" "language:none" \
                        "has_ui:false" "multi_agent:false" \
                        "deploy_target:none")
  for kv in "${opt_in[@]}" "${discriminators[@]}"; do
    local key="${kv%%:*}"
    local val="${kv#*:}"
    case "$omit" in
      *" $key "*) continue ;;
    esac
    out+="${key}: ${val}"$'\n'
  done
  out+='---

# Body
'
  printf '%s' "$out"
}

project=$(make_project)

echo "v1 (canonical_sdlc_version: 1, no v3 flags) → allow (grandfathered)"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$V1_LEGACY"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v2 (canonical_sdlc_version: 2, no v3 flags) → allow (grandfathered)"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01b-v2.plan.md" "$V2_LEGACY"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v3 with all 2 opt-in flags + 5 discriminators → allow"
v3_full=$(build_v3_plan)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md" "$v3_full"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v3 missing use_worktree → block, error names the flag"
v3_no_worktree=$(build_v3_plan use_worktree)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-03-z.plan.md" "$v3_no_worktree"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *use_worktree*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions use_worktree\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing use_worktree: %q\n' "$HOOK_STDERR" ;;
esac

echo "v3 missing cleanup_on_finish → block, error names the flag"
v3_no_cleanup=$(build_v3_plan cleanup_on_finish)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-03b-z.plan.md" "$v3_no_cleanup"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *cleanup_on_finish*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions cleanup_on_finish\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing cleanup_on_finish: %q\n' "$HOOK_STDERR" ;;
esac

echo "v3 missing surface_type → block, error names the flag"
v3_no_surface=$(build_v3_plan surface_type)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-04-q.plan.md" "$v3_no_surface"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *surface_type*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions surface_type\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing surface_type: %q\n' "$HOOK_STDERR" ;;
esac

echo "v3 missing multiple flags → block, error lists all of them"
v3_multi_missing=$(build_v3_plan has_ui multi_agent deploy_target)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-05-m.plan.md" "$v3_multi_missing"
assert_eq "exit 2" 2 "$HOOK_EXIT"
for flag in has_ui multi_agent deploy_target; do
  case "$HOOK_STDERR" in
    *"$flag"*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions %s\n' "$flag" ;;
    *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing %s: %q\n' "$flag" "$HOOK_STDERR" ;;
  esac
done

echo "plan with NO canonical_sdlc_version → allow (not v3-managed)"
no_marker='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 0
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-06-n.plan.md" "$no_marker"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "writing-plans plan WITH canonical_sdlc_version: 3 + autonomous + missing v3 flag → block"
# v3 schema enforcement gates on canonical_sdlc_version, not on governing-skill.
sp_v3_partial='---
governing-skill: superpowers:writing-plans
mode: autonomous
sdlc-step: 3
canonical_sdlc_version: 3
cleanup_on_finish: true
use_worktree: false
surface_type: api
language: typescript
has_ui: false
multi_agent: false
---

# Body (deploy_target intentionally missing)
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-06b-sp.plan.md" "$sp_v3_partial"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *deploy_target*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error names deploy_target on writing-plans + v3 plan\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing deploy_target: %q\n' "$HOOK_STDERR" ;;
esac

echo "v3 plan with mode != autonomous → allow (v3 schema only enforced for autonomous)"
v3_design='---
governing-skill: canonical-sdlc
mode: design-refresh
sdlc-step: 1
canonical_sdlc_version: 3
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-07-d.plan.md" "$v3_design"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "non-canonical-sdlc plan (governing-skill: superpowers:writing-plans) without version → allow"
sp_plan='---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-01-demo
wave: wave-01-x
mode: full
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-08-s.plan.md" "$sp_plan"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v1 legacy with governing-skill present but missing v3 flags → allow (grandfathered)"
v1_minimal='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 1
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-09-l.plan.md" "$v1_minimal"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "unsupported canonical_sdlc_version: 99 → block"
bad_ver='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 99
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-09b-bad.plan.md" "$bad_ver"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "unsupported canonical_sdlc_version: 12 → block (boundary: 11 is current, 12 is not yet minted)"
v12_bad='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 12
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-09c-v12.plan.md" "$v12_bad"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit on existing v1-migrated file (simulating live continuation-checkpoint.md) → allow"
migrated="$project/.bionic/docs/plans/epic-01-demo/continuation-checkpoint.md"
printf '%s' "$V1_LEGACY" > "$migrated"
run_edit "$migrated" "# Body" "# Updated"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "docs-root override: file under docs/bionic/ in a project with .bionic/config.yaml → enforced"
override_proj=$(mktemp -d); cleanup_dirs+=("$override_proj")
mkdir -p "$override_proj/docs/bionic/plans/epic-99-x"
mkdir -p "$override_proj/.bionic"
printf '%s' "docs-root: docs/bionic" > "$override_proj/.bionic/config.yaml"
run_write "$override_proj/docs/bionic/plans/epic-99-x/wave-01.plan.md" "$MISSING_FM"
assert_eq "exit 2 (override path resolved; missing frontmatter blocks)" 2 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version v4 enforcement (model_plan required)
# ============================================================
#
# v4 = the v3 contract (5 discriminators + 2 opt-in) PLUS a required
# model_plan field, for autonomous mode only. v3 plans keep the prior
# contract (no model_plan). Non-autonomous v4 plans are not flag-enforced.

# Helper: build a v4 plan with optional omissions (same shape as
# build_v3_plan, plus model_plan). Pass flag names to omit as args.
build_v4_plan() {
  local omit=" $* "
  local out='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 4
canonical_sdlc_version: 4
'
  local opt_in=("cleanup_on_finish:true" "use_worktree:false")
  local discriminators=("surface_type:none" "language:none" \
                        "has_ui:false" "multi_agent:true" \
                        "deploy_target:none")
  local v4_added=("model_plan:orchestrator=opus-4.8-xhigh; execution=opus-4.8-fresh; explore=sonnet-4.6")
  for kv in "${opt_in[@]}" "${discriminators[@]}" "${v4_added[@]}"; do
    local key="${kv%%:*}"
    local val="${kv#*:}"
    case "$omit" in
      *" $key "*) continue ;;
    esac
    out+="${key}: ${val}"$'\n'
  done
  out+='---

# Body
'
  printf '%s' "$out"
}

project=$(make_project)

echo "v4 with all v3 flags + model_plan → allow"
v4_full=$(build_v4_plan)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-10-v4.plan.md" "$v4_full"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v4 missing model_plan → block, error names model_plan"
v4_no_mp=$(build_v4_plan model_plan)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-11-v4.plan.md" "$v4_no_mp"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *model_plan*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions model_plan\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing model_plan: %q\n' "$HOOK_STDERR" ;;
esac

echo "v4 missing a discriminator (multi_agent) but with model_plan → block, names multi_agent"
v4_no_ma=$(build_v4_plan multi_agent)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-12-v4.plan.md" "$v4_no_ma"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *multi_agent*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions multi_agent\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing multi_agent: %q\n' "$HOOK_STDERR" ;;
esac

echo "v3 plan does NOT require model_plan → allow (prior contract preserved)"
v3_no_mp=$(build_v3_plan)   # build_v3_plan never emits model_plan
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-13-v3.plan.md" "$v3_no_mp"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v4 + mode != autonomous → allow (flag enforcement is autonomous-only)"
v4_design='---
governing-skill: canonical-sdlc
mode: design-refresh
sdlc-step: 1
canonical_sdlc_version: 4
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-14-v4d.plan.md" "$v4_design"
assert_eq "exit 0" 0 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version v5 enforcement (gate-collapse; inherits v4 contract)
# ============================================================
#
# v5 collapses Steps 5+6→Verify, 7+8→Review, 12+13→Integrate&close and
# dissolves Commit into a cross-cutting rhythm. The governing-skill flag
# contract is unchanged from v4: 5 discriminators + 2 opt-in + model_plan,
# autonomous mode only.

build_v5_plan() {
  local omit=" $* "
  local out='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 4
canonical_sdlc_version: 5
'
  local opt_in=("cleanup_on_finish:true" "use_worktree:false")
  local discriminators=("surface_type:none" "language:none" \
                        "has_ui:false" "multi_agent:true" \
                        "deploy_target:none")
  local v5_added=("model_plan:orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh")
  for kv in "${opt_in[@]}" "${discriminators[@]}" "${v5_added[@]}"; do
    local key="${kv%%:*}"
    local val="${kv#*:}"
    case "$omit" in
      *" $key "*) continue ;;
    esac
    out+="${key}: ${val}"$'\n'
  done
  out+='---

# Body
'
  printf '%s' "$out"
}

project=$(make_project)

echo "v5 with all v3 flags + model_plan → allow"
v5_full=$(build_v5_plan)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-15-v5.plan.md" "$v5_full"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v5 missing model_plan → block, error names model_plan"
v5_no_mp=$(build_v5_plan model_plan)
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-16-v5.plan.md" "$v5_no_mp"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *model_plan*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions model_plan (v5)\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing model_plan (v5): %q\n' "$HOOK_STDERR" ;;
esac

echo "v5 + mode != autonomous → allow (flag enforcement is autonomous-only)"
v5_design='---
governing-skill: canonical-sdlc
mode: design-refresh
sdlc-step: 1
canonical_sdlc_version: 5
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-17-v5d.plan.md" "$v5_design"
assert_eq "exit 0" 0 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version v6/v7/v8 enforcement (inherit v4 flag contract)
# ============================================================
#
# v6 drops the external-review step; v7 adds the Step-5 bundle-fresh
# evidence key (enforced by the evidence-gate hook, not here). Neither
# changes the governing-skill flag contract: 5 discriminators + 2 opt-in
# + model_plan, autonomous mode only. This hook must ACCEPT both versions
# — a version missing from its allowlist blocks every plan write.
# v8 adds the Step-5 drive-check evidence key (enforced by the
# evidence-gate hook, not here). The flag contract is unchanged.

build_versioned_plan() {
  local version="$1"; shift
  local omit=" $* "
  local out="---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 4
canonical_sdlc_version: ${version}
"
  local opt_in=("cleanup_on_finish:true" "use_worktree:false")
  local discriminators=("surface_type:none" "language:none" \
                        "has_ui:false" "multi_agent:true" \
                        "deploy_target:none")
  local v4_added=("model_plan:orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh")
  for kv in "${opt_in[@]}" "${discriminators[@]}" "${v4_added[@]}"; do
    local key="${kv%%:*}"
    local val="${kv#*:}"
    case "$omit" in
      *" $key "*) continue ;;
    esac
    out+="${key}: ${val}"$'\n'
  done
  out+='---

# Body
'
  # v10 additionally requires a "## Verification Matrix" section at
  # sdlc-step >= 3 (this helper's sdlc-step: 4). This loop's job is to
  # isolate the flag contract, not the matrix check — the dedicated
  # v10 matrix-check cases below exercise that behavior — so give v10
  # bodies a minimal matrix section here.
  if [ "$version" = "10" ]; then
    out+='
## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
'
  fi
  printf '%s' "$out"
}

for version in 6 7 8 9 10; do
  echo "v${version} with all v3 flags + model_plan → allow"
  vN_full=$(build_versioned_plan "$version")
  run_write "$project/.bionic/docs/plans/epic-01-demo/wave-18-v${version}.plan.md" "$vN_full"
  assert_eq "exit 0" 0 "$HOOK_EXIT"

  echo "v${version} missing model_plan → block, error names model_plan"
  vN_no_mp=$(build_versioned_plan "$version" model_plan)
  run_write "$project/.bionic/docs/plans/epic-01-demo/wave-19-v${version}.plan.md" "$vN_no_mp"
  assert_eq "exit 2" 2 "$HOOK_EXIT"
  case "$HOOK_STDERR" in
    *model_plan*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions model_plan (v%s)\n' "$version" ;;
    *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing model_plan (v%s): %q\n' "$version" "$HOOK_STDERR" ;;
  esac

  echo "v${version} + mode != autonomous → allow (flag enforcement is autonomous-only)"
  vN_design="---
governing-skill: canonical-sdlc
mode: design-refresh
sdlc-step: 1
canonical_sdlc_version: ${version}
---

# Body
"
  run_write "$project/.bionic/docs/plans/epic-01-demo/wave-20-v${version}d.plan.md" "$vN_design"
  assert_eq "exit 0" 0 "$HOOK_EXIT"
done

# ============================================================
# CRLF line endings — frontmatter parses under \r\n (Write path)
# ============================================================
#
# Plan files with CRLF (\r\n) line endings previously defeated the
# hook's exact-match awk frontmatter parser (`$0=="---"` never matches
# "---\r"), so a CRLF artifact's frontmatter was read as entirely
# absent — false-BLOCKed as "missing a YAML frontmatter block" even
# when every required flag was present. Strip \r at extraction time so
# CRLF artifacts get the same treatment as LF artifacts.

# Converts LF line endings to CRLF by inserting a literal CR before
# each newline. Bash-3.2-safe ANSI-C quoting embeds a real CR byte in
# the sed script itself (BSD sed's replacement text does not interpret
# the two-character "\r" as an escape).
to_crlf() {
  printf '%s' "$1" | sed $'s/$/\r/'
}

echo "CRLF v8 autonomous plan with full valid frontmatter → allow"
v8_full_crlf=$(to_crlf "$(build_versioned_plan 8)")
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-21-v8-crlf.plan.md" "$v8_full_crlf"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "CRLF v8 Write missing model_plan → block, error names model_plan"
v8_no_mp_crlf=$(to_crlf "$(build_versioned_plan 8 model_plan)")
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-22-v8-crlf-no-mp.plan.md" "$v8_no_mp_crlf"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *model_plan*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  CRLF error mentions model_plan\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  CRLF error missing model_plan: %q\n' "$HOOK_STDERR" ;;
esac

# ============================================================
# v10: matrix-required-at-step-3 check
# ============================================================
#
# v10 shares the v4+ flag contract. Additionally, when mode: autonomous,
# the basename matches *.plan.md, and sdlc-step is numeric >= 3, CONTENT
# must contain a line matching ^## Verification Matrix — else block.
# v9 and earlier are grandfathered out of this check entirely.

build_v10_frontmatter() {
  local sdlc_step="$1"
  local mode="${2:-autonomous}"
  cat <<EOF
---
governing-skill: canonical-sdlc
mode: ${mode}
sdlc-step: ${sdlc_step}
canonical_sdlc_version: 10
cleanup_on_finish: true
use_worktree: false
surface_type: none
language: none
has_ui: false
multi_agent: false
deploy_target: none
model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh
---
EOF
}

NO_MATRIX_BODY='
# Plan body

Some content without a verification matrix section.
'

WITH_MATRIX_BODY='
# Plan body

## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
'

project=$(make_project)

echo "v10 autonomous plan.md sdlc-step 3 WITHOUT Verification Matrix → block"
v10_step3_no_matrix="$(build_v10_frontmatter 3)"$'\n'"$NO_MATRIX_BODY"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-23-v10-nomatrix.plan.md" "$v10_step3_no_matrix"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *"Verification Matrix"*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error names Verification Matrix\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing Verification Matrix: %q\n' "$HOOK_STDERR" ;;
esac

echo "v10 autonomous plan.md sdlc-step 3 WITH Verification Matrix → allow"
v10_step3_matrix="$(build_v10_frontmatter 3)"$'\n'"$WITH_MATRIX_BODY"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-24-v10-matrix.plan.md" "$v10_step3_matrix"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v10 autonomous spec.md sdlc-step 2 without Verification Matrix → allow (not *.plan.md, and step < 3)"
v10_step2_spec="$(build_v10_frontmatter 2)"$'\n'"$NO_MATRIX_BODY"
run_write "$project/.bionic/docs/specs/epic-01-demo/wave-25-v10-spec.spec.md" "$v10_step2_spec"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v10 non-autonomous plan.md sdlc-step 3 without Verification Matrix → allow (matrix check is autonomous-only)"
v10_nonauto="$(build_v10_frontmatter 3 design-refresh)"$'\n'"$NO_MATRIX_BODY"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-26-v10-nonauto.plan.md" "$v10_nonauto"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v9 plan.md sdlc-step 3 without Verification Matrix → allow (grandfathered, no v10 matrix check)"
v9_step3='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 3
canonical_sdlc_version: 9
cleanup_on_finish: true
use_worktree: false
surface_type: none
language: none
has_ui: false
multi_agent: false
deploy_target: none
model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh
---
'"$NO_MATRIX_BODY"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-27-v9-nomatrix.plan.md" "$v9_step3"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v10 continuation.md (sdlc-step 10, not *.plan.md) without Verification Matrix → allow"
v10_continuation="$(build_v10_frontmatter 10)"$'\n'"$NO_MATRIX_BODY"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation.md" "$v10_continuation"
assert_eq "exit 0" 0 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version v11: intent × rigor × scale triple
# ============================================================
#
# v11 re-keys governance off the legacy `mode:` axis onto the triple
# (intent × rigor × scale). This section exercises R1 (triple presence +
# whole-value enum validation + mode split-brain guard + barred cells)
# and R2 (universal structural contract — flags/model_plan/matrix without
# the mode gate). Baseline fixture: build_v11_plan (all defaults valid);
# every case below mutates ONE aspect of it.
#
# Enums: intent ∈ {build,bugfix,refactor,tune,spike,incident-response};
#        rigor ∈ {tested,peer-reviewed,audited}; scale ∈ {task,wave,epic}.
# Barred intent × scale cells: bugfix·epic, spike·epic, incident-response·epic.

# Builds a v11 plan. All config via KEY=VALUE args (bash-3.2 arg parse):
#   intent/rigor/scale — triple values (default build/audited/wave);
#     value OMIT drops the line entirely (missing-field cases).
#   step  — sdlc-step (default 3).
#   mode  — if set, inject a `mode:` line (split-brain guard case).
#   omit  — space-separated flag names to drop (missing-flag cases).
#   matrix — yes|no; drop the "## Verification Matrix" section when no.
build_v11_plan() {
  local intent=build rigor=audited scale=wave step=3 mode="OMIT" omit=" " matrix=yes
  local arg
  for arg in "$@"; do
    case "$arg" in
      intent=*) intent="${arg#intent=}" ;;
      rigor=*)  rigor="${arg#rigor=}" ;;
      scale=*)  scale="${arg#scale=}" ;;
      step=*)   step="${arg#step=}" ;;
      mode=*)   mode="${arg#mode=}" ;;
      omit=*)   omit=" ${arg#omit=} " ;;
      matrix=*) matrix="${arg#matrix=}" ;;
    esac
  done

  local out='---
governing-skill: superpowers:writing-plans
sdlc-step: '"$step"'
epic: epic-01-demo
wave: wave-01-x
canonical_sdlc_version: 11
'
  [ "$mode" = OMIT ]   || out+="mode: $mode"$'\n'
  [ "$intent" = OMIT ] || out+="intent: $intent"$'\n'
  [ "$rigor" = OMIT ]  || out+="rigor: $rigor"$'\n'
  [ "$scale" = OMIT ]  || out+="scale: $scale"$'\n'

  local flags=("cleanup_on_finish:true" "use_worktree:false" \
    "surface_type:none" "language:none" "has_ui:false" \
    "multi_agent:false" "deploy_target:none" \
    "model_plan:orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh")
  local kv key val
  for kv in "${flags[@]}"; do
    key="${kv%%:*}"; val="${kv#*:}"
    case "$omit" in *" $key "*) continue ;; esac
    out+="${key}: ${val}"$'\n'
  done
  out+='---
'
  if [ "$matrix" = yes ]; then
    out+='
## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
'
  else
    out+='
# Plan body without a matrix section
'
  fi
  printf '%s' "$out"
}

project=$(make_project)

echo "v11 valid plan (full triple + flags + model_plan + matrix) → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-valid.plan.md" "$(build_v11_plan)"
assert_eq "v11_accepts_valid_plan exit 0" 0 "$HOOK_EXIT"

echo "v11 missing intent → block, error names intent"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-no-intent.plan.md" "$(build_v11_plan intent=OMIT)"
assert_eq "v11_blocks_missing_intent exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_missing_intent names intent" "intent" "$HOOK_STDERR"

echo "v11 missing rigor → block, error names rigor"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-no-rigor.plan.md" "$(build_v11_plan rigor=OMIT)"
assert_eq "v11_blocks_missing_rigor exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_missing_rigor names rigor" "rigor" "$HOOK_STDERR"

echo "v11 missing scale → block, error names scale"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-no-scale.plan.md" "$(build_v11_plan scale=OMIT)"
assert_eq "v11_blocks_missing_scale exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_missing_scale names scale" "scale" "$HOOK_STDERR"

echo "v11 bad intent enum (intent: feature) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-bad-intent.plan.md" "$(build_v11_plan intent=feature)"
assert_eq "v11_blocks_bad_intent_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_bad_intent_enum lists allowed" "allowed" "$HOOK_STDERR"

echo "v11 bad rigor enum (rigor: reviewed) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-bad-rigor.plan.md" "$(build_v11_plan rigor=reviewed)"
assert_eq "v11_blocks_bad_rigor_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_bad_rigor_enum lists allowed" "allowed" "$HOOK_STDERR"

echo "v11 bad scale enum (scale: session) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-bad-scale.plan.md" "$(build_v11_plan scale=session)"
assert_eq "v11_blocks_bad_scale_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_bad_scale_enum lists allowed" "allowed" "$HOOK_STDERR"

echo "v11 with mode: present (split-brain) → block, error names mode"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-mode.plan.md" "$(build_v11_plan mode=autonomous)"
assert_eq "v11_blocks_mode_present exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_mode_present names mode" "mode" "$HOOK_STDERR"

echo "v11 barred cell bugfix × epic → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-bugfix-epic.plan.md" "$(build_v11_plan intent=bugfix scale=epic)"
assert_eq "v11_blocks_barred_bugfix_epic exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_barred_bugfix_epic says barred" "barred" "$HOOK_STDERR"

echo "v11 barred cell spike × epic → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-spike-epic.plan.md" "$(build_v11_plan intent=spike scale=epic)"
assert_eq "v11_blocks_barred_spike_epic exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_barred_spike_epic says barred" "barred" "$HOOK_STDERR"

echo "v11 barred cell incident-response × epic → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-incident-epic.plan.md" "$(build_v11_plan intent=incident-response scale=epic)"
assert_eq "v11_blocks_barred_incident_epic exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_barred_incident_epic says barred" "barred" "$HOOK_STDERR"

echo "v11 missing a discriminator flag (surface_type) → block WITHOUT a mode gate"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-no-flag.plan.md" "$(build_v11_plan omit=surface_type)"
assert_eq "v11_blocks_missing_flag exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_missing_flag names surface_type" "surface_type" "$HOOK_STDERR"

echo "v11 missing model_plan → block, error names model_plan"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-no-mp.plan.md" "$(build_v11_plan omit=model_plan)"
assert_eq "v11_blocks_missing_model_plan exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_missing_model_plan names model_plan" "model_plan" "$HOOK_STDERR"

echo "v11 *.plan.md at sdlc-step 3 without matrix → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-no-matrix.plan.md" "$(build_v11_plan step=3 matrix=no)"
assert_eq "v11_blocks_plan_step3_no_matrix exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_plan_step3_no_matrix names matrix" "Verification Matrix" "$HOOK_STDERR"

echo "v11 *.spec.md at sdlc-step 2 without matrix → allow (matrix is plan-only, step >= 3)"
run_write "$project/.bionic/docs/specs/epic-01-demo/v11-spec.spec.md" "$(build_v11_plan step=2 matrix=no)"
assert_eq "v11_accepts_spec_step2_no_matrix exit 0" 0 "$HOOK_EXIT"

# scale: task plans carry a ## Tasks ledger, not a ## Verification Matrix
# (the matrix is a wave/epic artifact). They must be exempt from the
# matrix-required check regardless of sdlc-step. The wave case above
# (build_v11_plan defaults to scale=wave) is the guard that the exemption
# is scale-scoped, not a blanket removal.
echo "v11 scale:task plan at sdlc-step 3 without matrix → allow (task uses ## Tasks ledger, not a matrix)"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-task-no-matrix.plan.md" "$(build_v11_plan scale=task intent=bugfix rigor=tested step=3 matrix=no)"
assert_eq "v11_accepts_task_step3_no_matrix exit 0" 0 "$HOOK_EXIT"

echo "v11 scale:task plan at sdlc-step 4 without matrix → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-task-no-matrix-s4.plan.md" "$(build_v11_plan scale=task intent=bugfix rigor=tested step=4 matrix=no)"
assert_eq "v11_accepts_task_step4_no_matrix exit 0" 0 "$HOOK_EXIT"

echo "v11 CRLF plan with full valid triple → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-crlf.plan.md" "$(to_crlf "$(build_v11_plan)")"
assert_eq "v11_accepts_crlf_triple exit 0" 0 "$HOOK_EXIT"

# ============================================================
# CR-only line endings — classic-Mac \r (no \n) must parse too
# ============================================================
#
# The prior normalization `tr -d '\r'` DELETED every \r. On CRLF that
# leaves \n (works). On a CR-only artifact (\r as the sole line
# separator) it removed every line break, collapsing the whole file to
# ONE line, so the exact-match `$0 == "---"` frontmatter parser never
# matched and a VALID artifact was false-BLOCKed "missing a YAML
# frontmatter block". Fix: TRANSLATE \r to \n (not delete), matching the
# evidence-gate hook's normalize_newlines. Sibling of the CRLF block above.

# Converts LF line endings to classic-Mac CR-only by replacing each \n
# with a bare \r (no \n remains).
to_cr_only() {
  printf '%s' "$1" | tr '\n' '\r'
}

echo "CR-only v11 plan with full valid triple → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-cr-only.plan.md" "$(to_cr_only "$(build_v11_plan)")"
assert_eq "v11_accepts_cr_only_triple exit 0" 0 "$HOOK_EXIT"

echo "CR-only v8 autonomous plan with full valid frontmatter → allow"
v8_full_cr=$(to_cr_only "$(build_versioned_plan 8)")
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-23-v8-cr-only.plan.md" "$v8_full_cr"
assert_eq "cr_only_v8_full exit 0" 0 "$HOOK_EXIT"

echo "CR-only v8 Write missing model_plan → block for the RIGHT reason (parses, then flags model_plan)"
v8_no_mp_cr=$(to_cr_only "$(build_versioned_plan 8 model_plan)")
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-24-v8-cr-only-no-mp.plan.md" "$v8_no_mp_cr"
assert_eq "cr_only_v8_no_mp exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *model_plan*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  CR-only error mentions model_plan (not "missing frontmatter")\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  CR-only error should name model_plan, got: %q\n' "$HOOK_STDERR" ;;
esac

echo "v11 enum substring (intent: rebuild) → block (whole-value equality, not substring)"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-substr.plan.md" "$(build_v11_plan intent=rebuild)"
assert_eq "v11_blocks_enum_substring exit 2" 2 "$HOOK_EXIT"
assert_contains "v11_blocks_enum_substring lists allowed" "allowed" "$HOOK_STDERR"

echo "v10 grandfather: mode gate intact — autonomous v10 missing a flag still blocks"
v10_auto_no_flag=$(build_versioned_plan 10 surface_type)
run_write "$project/.bionic/docs/plans/epic-01-demo/v10-gf-block.plan.md" "$v10_auto_no_flag"
assert_eq "v10_regression_mode_gate_intact (autonomous blocks) exit 2" 2 "$HOOK_EXIT"
assert_contains "v10_regression_mode_gate_intact names surface_type" "surface_type" "$HOOK_STDERR"

echo "v10 grandfather: mode gate intact — non-autonomous v10 skips flags (byte-identical path)"
v10_nonauto_no_flags='---
governing-skill: canonical-sdlc
mode: spike
sdlc-step: 3
canonical_sdlc_version: 10
---

# Body (no flags, no matrix — mode gate short-circuits before either check)
'
run_write "$project/.bionic/docs/plans/epic-01-demo/v10-gf-skip.plan.md" "$v10_nonauto_no_flags"
assert_eq "v10_regression_mode_gate_intact (non-autonomous skips) exit 0" 0 "$HOOK_EXIT"

echo "unsupported canonical_sdlc_version: 12 → block (allowlist grew to exactly 11)"
v12_unsupported='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 12
---

# Body
'
run_write "$project/.bionic/docs/plans/epic-01-demo/v12-unsupported.plan.md" "$v12_unsupported"
assert_eq "unsupported_v12_still_blocks exit 2" 2 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version v11: floor-consistency checks (LOG-ONLY, D14)
# ============================================================
#
# On every v11 artifact write the hook computes derivable rigor floors and
# appends one line per violation to <project>/.bionic/memory/sdlc-v11-audit.md
# AND echoes it to stderr, then exits 0 — findings NEVER block (R3/D14).
# Floors: incident-response floors at audited; spike is capped at tested;
# `rigor-floor:` in .bionic/config.yaml (invalid value = its own finding);
# `rigor-floor:` in the epic plan's frontmatter (fail-open on missing plan).
# Fixtures build temp project roots; audit writes land under the temp root
# (the hook derives PROJECT_ROOT from the file path's .bionic walk-up), so
# the real repo's .bionic/memory is never touched.

AUDIT_REL=".bionic/memory/sdlc-v11-audit.md"
read_audit() {
  if [ -f "$1/$AUDIT_REL" ]; then cat "$1/$AUDIT_REL"; else echo ""; fi
}

echo "v11 intent-floor: incident-response + rigor tested → log intent-floor, exit 0"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-incident-floor.plan.md" "$(build_v11_plan intent=incident-response rigor=tested)"
assert_eq "v11_floor_incident_below_audited_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "v11_floor_incident stderr names intent-floor" "intent-floor" "$HOOK_STDERR"
assert_contains "v11_floor_incident audit line names intent-floor" "intent-floor" "$(read_audit "$project")"
assert_contains "v11_floor_incident audit line carries artifact path" "v11-incident-floor.plan.md" "$(read_audit "$project")"

echo "v11 spike-cap: spike + rigor audited → log spike-cap, exit 0"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-spike-cap.plan.md" "$(build_v11_plan intent=spike rigor=audited)"
assert_eq "v11_floor_spike_above_tested_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "v11_floor_spike stderr names spike-cap" "spike-cap" "$HOOK_STDERR"
assert_contains "v11_floor_spike audit names spike-cap" "spike-cap" "$(read_audit "$project")"

echo "v11 project-floor: config rigor-floor audited + plan rigor tested → log project-floor"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-proj-floor.plan.md" "$(build_v11_plan intent=build rigor=tested)"
assert_eq "v11_floor_project_violation_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "v11_floor_project stderr names project-floor" "project-floor" "$HOOK_STDERR"
assert_contains "v11_floor_project audit names project-floor" "project-floor" "$(read_audit "$project")"

echo "v11 project-floor satisfied: rigor audited meets floor → silent (no audit, no stderr)"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-proj-ok.plan.md" "$(build_v11_plan intent=build rigor=audited)"
assert_eq "v11_floor_project_satisfied_silent exit 0" 0 "$HOOK_EXIT"
assert_eq "v11_floor_project_satisfied_silent no audit file" "" "$(read_audit "$project")"
assert_eq "v11_floor_project_satisfied_silent empty stderr" "" "$HOOK_STDERR"

echo "v11 project-floor invalid value: rigor-floor: extreme → invalid-value finding, exit 0"
project=$(make_project)
printf 'rigor-floor: extreme\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-proj-invalid.plan.md" "$(build_v11_plan intent=build rigor=audited)"
assert_eq "v11_floor_project_invalid_value_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "v11_floor_project_invalid stderr names project-floor" "project-floor" "$HOOK_STDERR"
assert_contains "v11_floor_project_invalid audit says invalid" "invalid rigor-floor" "$(read_audit "$project")"

echo "v11 epic-floor: epic.plan.md rigor-floor audited + plan rigor tested → log epic-floor"
project=$(make_project)
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 11
rigor-floor: audited
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-epic-floor.plan.md" "$(build_v11_plan intent=build rigor=tested)"
assert_eq "v11_floor_epic_violation_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "v11_floor_epic stderr names epic-floor" "epic-floor" "$HOOK_STDERR"
assert_contains "v11_floor_epic audit names epic-floor" "epic-floor" "$(read_audit "$project")"

echo "v11 epic-floor: epic names a plan that doesn't exist → silent (fail-open)"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-epic-missing.plan.md" "$(build_v11_plan intent=build rigor=tested)"
assert_eq "v11_floor_epic_plan_missing_silent exit 0" 0 "$HOOK_EXIT"
assert_eq "v11_floor_epic_plan_missing_silent no audit file" "" "$(read_audit "$project")"

echo "v11 audit file + parent dir created on first finding"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-audit-create.plan.md" "$(build_v11_plan intent=spike rigor=audited)"
assert_eq "v11_floor_audit_file_created exit 0" 0 "$HOOK_EXIT"
if [ -f "$project/$AUDIT_REL" ]; then
  PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  v11_floor_audit_file_created (file + dir created)\n'
else
  FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  v11_floor_audit_file_created (file missing)\n'
fi

echo "v11 all-violations fixture (intent + project + epic floors) → still exit 0, all three logged"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 11
rigor-floor: audited
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/v11-all-violations.plan.md" "$(build_v11_plan intent=incident-response rigor=tested)"
assert_eq "v11_floor_never_blocks exit 0" 0 "$HOOK_EXIT"
assert_contains "v11_floor_never_blocks logs intent-floor" "intent-floor" "$(read_audit "$project")"
assert_contains "v11_floor_never_blocks logs project-floor" "project-floor" "$(read_audit "$project")"
assert_contains "v11_floor_never_blocks logs epic-floor" "epic-floor" "$(read_audit "$project")"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
