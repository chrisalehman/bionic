#!/bin/bash
# Tests for migrate-frontmatter.sh
#
# Strategy: build temp project trees with synthetic plan/spec/adr files,
# invoke the migration script on file paths, and assert on resulting file
# contents. The script's date is pinned via MIGRATE_TODAY for determinism.
#
# Usage: bash skills/canonical-sdlc/migrate-frontmatter.test.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/migrate-frontmatter.sh"
PASS=0
FAIL=0
TOTAL=0

# Pinned migration date for deterministic assertions.
export MIGRATE_TODAY="2026-05-02"

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
  mkdir -p "$dir/docs/bionic/plans"
  mkdir -p "$dir/docs/bionic/specs"
  mkdir -p "$dir/docs/bionic/adrs"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# Run the script with one or more file paths. Captures exit code and
# stderr in HOOK_EXIT and HOOK_STDERR.
run_script() {
  local tmp_err
  tmp_err=$(mktemp)
  if bash "$SCRIPT" "$@" >/dev/null 2>"$tmp_err"; then
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
    printf '  FAIL  %s (missing: %q)\n' "$label" "$needle"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" <<< "$haystack"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s (unexpectedly contains: %q)\n' "$label" "$needle"
  else
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$label"
  fi
}

# ---------- cases ----------

# Case 1: matching file (continuation*.md) missing all three fields → all three added.
echo "Case 1: matching file with no v1 fields → all three added"
proj=$(make_project)
file="$proj/docs/bionic/plans/continuation-checkpoint.md"
cat > "$file" <<'EOF'
---
governing-skill: canonical-sdlc
sdlc-step: N/A
epic: N/A
---

# Body
EOF
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
content=$(cat "$file")
assert_contains "adds canonical_sdlc_version: 1" "canonical_sdlc_version: 1" "$content"
assert_contains "adds evidence_schema: legacy" "evidence_schema: legacy" "$content"
assert_contains "adds created: 2026-05-02" "created: 2026-05-02" "$content"
assert_contains "preserves governing-skill" "governing-skill: canonical-sdlc" "$content"
assert_contains "preserves body" "# Body" "$content"

# Case 2: matching .plan.md file with partial fields → only missing fields added.
echo "Case 2: partial fields → only missing fields added, existing preserved"
proj=$(make_project)
file="$proj/docs/bionic/plans/wave-01-x.plan.md"
cat > "$file" <<'EOF'
---
governing-skill: superpowers:writing-plans
canonical_sdlc_version: 1
created: 2026-01-15
---

# Body
EOF
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
content=$(cat "$file")
assert_contains "preserves existing canonical_sdlc_version" "canonical_sdlc_version: 1" "$content"
assert_contains "preserves existing created" "created: 2026-01-15" "$content"
assert_not_contains "does NOT overwrite created" "created: 2026-05-02" "$content"
assert_contains "adds missing evidence_schema" "evidence_schema: legacy" "$content"

# Case 3: matching file with all three fields present → no-op (file unchanged byte-for-byte).
echo "Case 3: all three fields present → idempotent no-op"
proj=$(make_project)
file="$proj/docs/bionic/plans/already-migrated.plan.md"
cat > "$file" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 1
evidence_schema: legacy
created: 2025-12-01
---

# Body
EOF
before=$(cat "$file")
before_mtime=$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file")
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
after=$(cat "$file")
assert_eq "content unchanged" "$before" "$after"

# Case 4: matching file without any frontmatter → skipped (file unchanged).
echo "Case 4: file without frontmatter → skipped, exit 0, file unchanged"
proj=$(make_project)
file="$proj/docs/bionic/plans/no-frontmatter.plan.md"
cat > "$file" <<'EOF'
# This file has no frontmatter

Just body content.
EOF
before=$(cat "$file")
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
after=$(cat "$file")
assert_eq "no-frontmatter file unchanged" "$before" "$after"

# Case 5: non-matching filename → skipped (file unchanged), no error.
echo "Case 5: non-matching filename (e.g. README.md) → skipped, file unchanged"
proj=$(make_project)
file="$proj/docs/bionic/plans/README.md"
cat > "$file" <<'EOF'
---
title: Plans directory
---

Just a readme.
EOF
before=$(cat "$file")
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
after=$(cat "$file")
assert_eq "non-matching file unchanged" "$before" "$after"

# Case 6: idempotency — running twice on the same file leaves it identical
# after the first migration.
echo "Case 6: idempotent — running twice yields stable result"
proj=$(make_project)
file="$proj/docs/bionic/specs/wave-01-x.spec.md"
cat > "$file" <<'EOF'
---
governing-skill: superpowers:spec-driven-development
sdlc-step: 1
---

# Spec
EOF
run_script "$file"
assert_eq "first-run exit 0" 0 "$HOOK_EXIT"
after_first=$(cat "$file")
run_script "$file"
assert_eq "second-run exit 0" 0 "$HOOK_EXIT"
after_second=$(cat "$file")
assert_eq "second run is no-op" "$after_first" "$after_second"

# Case 7: adr-NNN-foo.md is recognized as a matching artifact.
echo "Case 7: adr-*.md is matched"
proj=$(make_project)
file="$proj/docs/bionic/adrs/adr-001-decision.md"
cat > "$file" <<'EOF'
---
governing-skill: agent-skills:documentation-and-adrs
---

# Decision
EOF
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
content=$(cat "$file")
assert_contains "adr migrated: canonical_sdlc_version" "canonical_sdlc_version: 1" "$content"
assert_contains "adr migrated: evidence_schema" "evidence_schema: legacy" "$content"
assert_contains "adr migrated: created" "created: 2026-05-02" "$content"

# Case 8: multiple files in one invocation — mix of matching, non-matching,
# and already-migrated.
echo "Case 8: multiple files in one invocation"
proj=$(make_project)
fresh="$proj/docs/bionic/plans/continuation-foo.md"
already="$proj/docs/bionic/plans/done.plan.md"
skipped="$proj/docs/bionic/plans/notes.md"
cat > "$fresh" <<'EOF'
---
governing-skill: canonical-sdlc
---
body
EOF
cat > "$already" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 1
evidence_schema: legacy
created: 2025-11-01
---
body
EOF
cat > "$skipped" <<'EOF'
---
title: notes
---
body
EOF
already_before=$(cat "$already")
skipped_before=$(cat "$skipped")
run_script "$fresh" "$already" "$skipped"
assert_eq "multi exit 0" 0 "$HOOK_EXIT"
assert_contains "fresh got migrated" "canonical_sdlc_version: 1" "$(cat "$fresh")"
assert_eq "already-migrated unchanged" "$already_before" "$(cat "$already")"
assert_eq "non-matching unchanged" "$skipped_before" "$(cat "$skipped")"

# Case 9: insertion order is stable. New fields land at the end of the
# frontmatter block, in fixed order (canonical_sdlc_version, evidence_schema,
# created), and the closing `---` is preserved exactly once.
echo "Case 9: insertion order — fields land at end of frontmatter, in fixed order"
proj=$(make_project)
file="$proj/docs/bionic/plans/order-check.plan.md"
cat > "$file" <<'EOF'
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
---

# Body
EOF
run_script "$file"
assert_eq "exit 0" 0 "$HOOK_EXIT"
fm=$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$file")
# The last three non-empty lines of the frontmatter block must be the
# three new fields in order.
last3=$(echo "$fm" | grep -v '^[[:space:]]*$' | tail -3)
expected="canonical_sdlc_version: 1
evidence_schema: legacy
created: 2026-05-02"
assert_eq "new fields appended in fixed order" "$expected" "$last3"

# Verify exactly two `---` markers (no duplicated frontmatter delimiter).
delim_count=$(grep -c '^---$' "$file")
assert_eq "exactly 2 frontmatter delimiters" "2" "$delim_count"

# ---------- summary ----------
echo
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
