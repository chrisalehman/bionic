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

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
