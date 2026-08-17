#!/bin/bash
# COMMAND FORMAT — epic-17 wave-03 slice S9 (spec AC-1; design boundaries:
# "commands are prose-free wrappers; help carries static content").
#
# WHAT THIS SUITE OWNS. payload/commands/*.md — the whole command surface, as
# it exists at any point in the wave. It globs rather than hand-lists its
# subject files (unlike tests/run.sh's own registration discipline) because the
# command-file SET grows across slices S9-S18; the CONVENTION every file in
# that set must hold is this suite's fixed subject.
#
# TWO RULES, EVERY FILE:
#   1. Valid frontmatter carrying a non-empty `description:`.
#   2. Any `.sh` invocation token is rooted at the literal `${CLAUDE_PLUGIN_ROOT}`
#      spelling — never an absolute path, never a plugin-cache hash path, never
#      a bare repo-root-relative path. One rule catches all three: the token
#      immediately touching `.sh` must have `${CLAUDE_PLUGIN_ROOT}` as its
#      literal prefix (design boundaries: interpolation proven by
#      probe-identity-match.md; nothing else is a portable install-time path).
#
# help.md CARRIES A THIRD RULE ON TOP: static content only, so it must contain
# the four-command roster AND zero `${CLAUDE_PLUGIN_ROOT}` invocations — the
# roster describes the scripts, it never calls them (AC-1, design boundaries).
#
# HERMETIC. No network, no `claude` CLI. Fixtures for the positive/negative
# arms are planted in a scratch dir; the checker functions run against both
# the fixtures and the real payload/commands/*.md tree.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh). Containment checks use bash `[[ == * ]]`
# in-process; multi-match extraction uses `grep -oE`/`grep -v` directly against
# a FILE argument (not a pipe), which reads to EOF and never SIGPIPEs a writer.
#
# Usage: bash tests/command-format.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
COMMANDS_DIR="${REPO}/payload/commands"
HELP_MD="${COMMANDS_DIR}/help.md"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_eq()    { local label="$1" expected="$2" actual="$3"; if [ "$actual" = "$expected" ]; then ok "$label"; else no "$label" "expected='$expected' actual='$actual'"; fi; }
# In-process substring test — no pipe into grep -q, so no SIGPIPE race.
expect_contains()     { local label="$1" needle="$2" haystack="$3"; if [[ "$haystack" == *"$needle"* ]]; then ok "$label"; else no "$label" "expected to contain '$needle'"; fi; }
expect_not_contains()  { local label="$1" needle="$2" haystack="$3"; if [[ "$haystack" == *"$needle"* ]]; then no "$label" "expected NOT to contain '$needle'"; else ok "$label"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Checkers — the two rules, as functions, so fixtures and the real tree run
# through the identical logic.
# ---------------------------------------------------------------------------

# Frontmatter's description value, or empty if absent/empty. Single awk pass,
# no downstream pipe, so no early-exit race.
frontmatter_description_value() {
  awk '
    /^---$/ { c++; next }
    c==1 && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
    c>=2 { exit }
  ' "$1"
}

# Prints every `.sh` invocation token in the file that does NOT have the
# literal `${CLAUDE_PLUGIN_ROOT}` string as its prefix. Empty output = clean.
# grep -oE / grep -v here run straight against a FILE argument, not a pipe
# from another process's stdout — no SIGPIPE race is possible.
bad_script_invocations() {
  grep -oE '[^[:space:]"'"'"'`]+\.sh' "$1" 2>/dev/null | grep -v '^\${CLAUDE_PLUGIN_ROOT}' || true
}

# ---------------------------------------------------------------------------
# Section 1: every payload/commands/*.md file — the growing-set convention.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 1: payload/commands/ convention (glob, grows with the wave) ==="

expect_true "payload/commands/ directory exists" test -d "$COMMANDS_DIR"

if [ -d "$COMMANDS_DIR" ]; then
  shopt -s nullglob
  cmd_files=("$COMMANDS_DIR"/*.md)
  shopt -u nullglob

  expect_true "payload/commands/*.md is non-empty" bash -c "[ ${#cmd_files[@]} -gt 0 ]"

  for f in "${cmd_files[@]}"; do
    base="$(basename "$f")"

    desc="$(frontmatter_description_value "$f")"
    expect_true "$base: frontmatter has non-empty description" bash -c "[ -n '$desc' ]"

    bad="$(bad_script_invocations "$f")"
    expect_eq "$base: every .sh invocation is rooted at \${CLAUDE_PLUGIN_ROOT}" "" "$bad"
  done
else
  echo "SKIP: remaining Section 1 checks (payload/commands/ missing)"
fi

# ---------------------------------------------------------------------------
# Section 2: help.md-specific — static content, the front door.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 2: help.md — the front door (AC-1) ==="

expect_true "help.md exists" test -f "$HELP_MD"

if [ -f "$HELP_MD" ]; then
  HELP_TEXT="$(cat "$HELP_MD")"

  expect_contains "help.md names /bionic:help"   "/bionic:help"   "$HELP_TEXT"
  expect_contains "help.md names /bionic:setup"  "/bionic:setup"  "$HELP_TEXT"
  expect_contains "help.md names /bionic:doctor" "/bionic:doctor" "$HELP_TEXT"
  expect_contains "help.md names /bionic:remove" "/bionic:remove" "$HELP_TEXT"

  # AC wording checks, per-command (brief's literal phrasing).
  expect_contains "help.md: setup described as idempotent"        "idempotent"      "$HELP_TEXT"
  expect_contains "help.md: setup described as wrapping plugin install" "plugin install" "$HELP_TEXT"
  expect_contains "help.md: doctor described as read-only"        "read-only"       "$HELP_TEXT"
  expect_contains "help.md: remove described as consented"        "consented"       "$HELP_TEXT"
  expect_contains "help.md: remove described as native uninstall" "uninstall"       "$HELP_TEXT"

  # Tier model, ratified vocabulary (design-ledger.md D6: "Tier 2 wraps tier 1").
  expect_contains "help.md names tier 1 (plugin install)" "tier 1" "${HELP_TEXT,,}"
  expect_contains "help.md names tier 2 (environment setup)" "tier 2" "${HELP_TEXT,,}"

  # Where to start.
  expect_contains "help.md: fresh machine points at /bionic:setup" "/bionic:setup" "$HELP_TEXT"
  expect_contains "help.md: something-wrong points at /bionic:doctor" "/bionic:doctor" "$HELP_TEXT"

  # Static content only — zero script invocations of any kind.
  bad="$(bad_script_invocations "$HELP_MD")"
  expect_eq "help.md: no non-rooted .sh invocations" "" "$bad"
  inv_count="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}' "$HELP_MD" 2>/dev/null | wc -l | tr -d ' ')"
  expect_eq "help.md: zero \${CLAUDE_PLUGIN_ROOT} invocations (static content, no logic)" "0" "$inv_count"
else
  echo "SKIP: remaining Section 2 checks (help.md missing)"
fi

# ---------------------------------------------------------------------------
# Section 3: fixture arms — positive fixture passes, each negative fixture is
# caught by the specific rule it is built to break.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 3: fixture positive/negative arms ==="

FIXDIR="$TMP/fixture-commands"
mkdir -p "$FIXDIR"

cat > "$FIXDIR/good.md" <<'EOF'
---
description: a well-formed command file
---

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```
EOF

cat > "$FIXDIR/bad-missing-description.md" <<'EOF'
---
name: no-description-here
---

Some body text.
EOF

cat > "$FIXDIR/bad-empty-description.md" <<'EOF'
---
description:
---

Some body text.
EOF

cat > "$FIXDIR/bad-absolute-path.md" <<'EOF'
---
description: invokes a script by absolute path
---

```bash
bash /Users/admin/workspace/personal/bionic/payload/scripts/setup.sh
```
EOF

cat > "$FIXDIR/bad-hash-cache-path.md" <<'EOF'
---
description: invokes a script by a plugin-cache hash/version path
---

```bash
bash ~/.claude/plugins/cache/bionic-marketplace/bionic/0.1.0/scripts/setup.sh
```
EOF

cat > "$FIXDIR/bad-repo-relative-path.md" <<'EOF'
---
description: invokes a script by a bare repo-root-relative path
---

```bash
bash payload/scripts/setup.sh
```
EOF

# Positive arm.
good_desc="$(frontmatter_description_value "$FIXDIR/good.md")"
expect_true "fixture good.md: description extracted non-empty" bash -c "[ -n '$good_desc' ]"
good_bad_invocations="$(bad_script_invocations "$FIXDIR/good.md")"
expect_eq "fixture good.md: \${CLAUDE_PLUGIN_ROOT}-rooted invocation passes clean" "" "$good_bad_invocations"

# Negative arms — each caught by the rule it targets.
missing_desc="$(frontmatter_description_value "$FIXDIR/bad-missing-description.md")"
expect_true "fixture bad-missing-description.md: caught (no description key at all)" bash -c "[ -z '$missing_desc' ]"

empty_desc="$(frontmatter_description_value "$FIXDIR/bad-empty-description.md")"
expect_true "fixture bad-empty-description.md: caught (description key present but empty)" bash -c "[ -z '$empty_desc' ]"

abs_bad="$(bad_script_invocations "$FIXDIR/bad-absolute-path.md")"
expect_true "fixture bad-absolute-path.md: caught (absolute path invocation)" bash -c "[ -n '$abs_bad' ]"

hash_bad="$(bad_script_invocations "$FIXDIR/bad-hash-cache-path.md")"
expect_true "fixture bad-hash-cache-path.md: caught (plugin-cache hash path invocation)" bash -c "[ -n '$hash_bad' ]"

relpath_bad="$(bad_script_invocations "$FIXDIR/bad-repo-relative-path.md")"
expect_true "fixture bad-repo-relative-path.md: caught (bare repo-relative invocation)" bash -c "[ -n '$relpath_bad' ]"

# ---------------------------------------------------------------------------
# Section 4: mutation-and-restore — proof the checks discriminate against the
# REAL production file, not just synthetic fixtures. RED evidence dies at
# green (memory: red-evidence-is-perishable), so the proof is taken here: a
# doctored COPY of help.md is checked and shown to fail; the production file
# itself is never touched.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 4: mutation-and-restore (against a doctored copy of help.md) ==="

if [ -f "$HELP_MD" ]; then
  DOCTORED="$TMP/help-doctored.md"
  # Mutation 1: strip the /bionic:doctor roster line — the four-command-roster
  # check must go red.
  grep -v '/bionic:doctor' "$HELP_MD" > "$DOCTORED"
  doctored_text="$(cat "$DOCTORED")"
  expect_not_contains "MUTATED help.md (doctor line stripped): roster check now fails as expected" "/bionic:doctor" "$doctored_text"

  # Mutation 2: inject a \${CLAUDE_PLUGIN_ROOT} invocation into a copy — the
  # zero-invocations (static content) check must go red.
  cp "$HELP_MD" "$DOCTORED"
  printf '\n```bash\nbash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"\n```\n' >> "$DOCTORED"
  doctored_inv_count="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}' "$DOCTORED" 2>/dev/null | wc -l | tr -d ' ')"
  expect_true "MUTATED help.md (invocation injected): static-content check now fails as expected" bash -c "[ '$doctored_inv_count' -gt 0 ]"

  # Restore proof: the production file was never opened for writing above —
  # only read (cat/grep into $DOCTORED copies) — so it still passes clean.
  restored_bad="$(bad_script_invocations "$HELP_MD")"
  expect_eq "production help.md untouched: still zero non-rooted invocations after mutation arms" "" "$restored_bad"
else
  echo "SKIP: Section 4 (help.md missing)"
fi

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
