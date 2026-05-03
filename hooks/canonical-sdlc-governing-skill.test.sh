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
  mkdir -p "$dir/docs/bionic/plans/epic-01-demo"
  mkdir -p "$dir/docs/bionic/specs/epic-01-demo"
  mkdir -p "$dir/docs/bionic/adrs/epic-01-demo"
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
run_write "$project/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: plan file missing frontmatter → block"
run_write "$project/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: plan file with empty governing-skill → block"
run_write "$project/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" "$EMPTY_GOVERNING"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: spec file with valid frontmatter → allow"
run_write "$project/docs/bionic/specs/epic-01-demo/wave-01-x.spec.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: adr file with valid frontmatter → allow"
run_write "$project/docs/bionic/adrs/epic-01-demo/adr-001-x.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: continuation.md with valid frontmatter → allow"
run_write "$project/docs/bionic/plans/epic-01-demo/continuation.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: continuation-checkpoint.md with valid frontmatter → allow"
run_write "$project/docs/bionic/plans/epic-01-demo/continuation-checkpoint.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: README.md under plans dir, no frontmatter → allow (not an enforced artifact)"
run_write "$project/docs/bionic/plans/epic-01-demo/README.md" "# some notes"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: .plan.md OUTSIDE docs/bionic/ → allow (hook scope is path-gated)"
outside=$(mktemp -d)
cleanup_dirs+=("$outside")
run_write "$outside/random.plan.md" "$MISSING_FM"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: adr-named file under adrs/ missing frontmatter → block"
run_write "$project/docs/bionic/adrs/epic-01-demo/adr-007-x.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit: existing file with valid frontmatter → allow"
existing="$project/docs/bionic/plans/epic-01-demo/wave-02-y.plan.md"
printf '%s' "$VALID_FRONTMATTER" > "$existing"
run_edit "$existing" "Plan body" "Updated body"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Edit: existing file missing frontmatter → block"
bad="$project/docs/bionic/plans/epic-01-demo/wave-03-z.plan.md"
printf '%s' "$MISSING_FM" > "$bad"
run_edit "$bad" "Plan body" "Updated body"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit: file doesn't exist (Edit would fail anyway) → block"
run_edit "$project/docs/bionic/plans/epic-01-demo/does-not-exist.plan.md" "x" "y"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Bash tool (non-Write/Edit) → allow"
input=$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')
HOOK_EXIT=0
if ! bash "$HOOK" <<< "$input" >/dev/null 2>&1; then
  HOOK_EXIT=$?
fi
assert_eq "exit 0" 0 "$HOOK_EXIT"

# ============================================================
# Wave 1b: canonical_sdlc_version v1/v2 enforcement
# ============================================================
#
# Schema (from canonical-sdlc-autonomous-redesign.md §1.2.2 and §6.4):
#   - canonical_sdlc_version: 1 → legacy-skip (v2 enforcement off)
#   - canonical_sdlc_version: 2 + governing-skill: canonical-sdlc + mode: autonomous
#       → require all 4 v2 opt-in flags + 8 discriminator flags
#   - canonical_sdlc_version absent + governing-skill: canonical-sdlc
#       → block with message naming the missing version field
#   - non-canonical-sdlc governing-skill (e.g. superpowers:writing-plans)
#       → version field not enforced (v2 schema is canonical-sdlc-specific)

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

# Helper to build a v2 plan with optional omissions. Pass the names of
# flags to omit as args; everything else is included.
build_v2_plan() {
  local omit=" $* "
  local out='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 5
canonical_sdlc_version: 2
'
  local v2_flags=("narrative_verbose:false" "dispatch_enforce:false" \
                  "cleanup_on_finish:false" "archived:false")
  local discriminators=("surface_type:none" "language:none" \
                        "perf_critical:false" "security_boundary:false" \
                        "distributed:false" "has_ui:false" \
                        "multi_agent:false" "deploy_target:none")
  for kv in "${v2_flags[@]}" "${discriminators[@]}"; do
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

echo "v1 (canonical_sdlc_version: 1, no v2 flags) → allow"
run_write "$project/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" "$V1_LEGACY"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v2 with all 4 opt-in flags + 8 discriminators → allow"
v2_full=$(build_v2_plan)
run_write "$project/docs/bionic/plans/epic-01-demo/wave-02-y.plan.md" "$v2_full"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v2 missing dispatch_enforce → block, error names the flag"
v2_no_enforce=$(build_v2_plan dispatch_enforce)
run_write "$project/docs/bionic/plans/epic-01-demo/wave-03-z.plan.md" "$v2_no_enforce"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *dispatch_enforce*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions dispatch_enforce\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing dispatch_enforce: %q\n' "$HOOK_STDERR" ;;
esac

echo "v2 missing surface_type → block, error names the flag"
v2_no_surface=$(build_v2_plan surface_type)
run_write "$project/docs/bionic/plans/epic-01-demo/wave-04-q.plan.md" "$v2_no_surface"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *surface_type*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions surface_type\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing surface_type: %q\n' "$HOOK_STDERR" ;;
esac

echo "v2 missing multiple flags → block, error lists all of them"
v2_multi_missing=$(build_v2_plan archived has_ui multi_agent)
run_write "$project/docs/bionic/plans/epic-01-demo/wave-05-m.plan.md" "$v2_multi_missing"
assert_eq "exit 2" 2 "$HOOK_EXIT"
for flag in archived has_ui multi_agent; do
  case "$HOOK_STDERR" in
    *"$flag"*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions %s\n' "$flag" ;;
    *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing %s: %q\n' "$flag" "$HOOK_STDERR" ;;
  esac
done

echo "canonical-sdlc plan with NO canonical_sdlc_version → block, error names the field"
no_marker='---
governing-skill: canonical-sdlc
mode: autonomous
sdlc-step: 0
---

# Body
'
run_write "$project/docs/bionic/plans/epic-01-demo/wave-06-n.plan.md" "$no_marker"
assert_eq "exit 2" 2 "$HOOK_EXIT"
case "$HOOK_STDERR" in
  *canonical_sdlc_version*) PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  error mentions canonical_sdlc_version\n' ;;
  *) FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  error missing canonical_sdlc_version: %q\n' "$HOOK_STDERR" ;;
esac

echo "v2 plan with mode != autonomous → allow (v2 schema only enforced for autonomous)"
v2_design='---
governing-skill: canonical-sdlc
mode: design-refresh
sdlc-step: 1
canonical_sdlc_version: 2
---

# Body
'
run_write "$project/docs/bionic/plans/epic-01-demo/wave-07-d.plan.md" "$v2_design"
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
run_write "$project/docs/bionic/plans/epic-01-demo/wave-08-s.plan.md" "$sp_plan"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "v1 legacy with governing-skill present but missing v2 flags → allow (grandfathered)"
v1_minimal='---
governing-skill: canonical-sdlc
mode: autonomous
canonical_sdlc_version: 1
---

# Body
'
run_write "$project/docs/bionic/plans/epic-01-demo/wave-09-l.plan.md" "$v1_minimal"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Edit on existing v1-migrated file (simulating live continuation-checkpoint.md) → allow"
migrated="$project/docs/bionic/plans/epic-01-demo/continuation-checkpoint.md"
printf '%s' "$V1_LEGACY" > "$migrated"
run_edit "$migrated" "# Body" "# Updated"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
