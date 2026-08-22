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
# help.md CARRIES A THIRD RULE ON TOP: it is the orientation page, so it must
# contain the four-command roster and it must not act on the machine. That was
# pinned as "zero `${CLAUDE_PLUGIN_ROOT}` invocations" until epic-17 W6 S1,
# which opened the page with `bionic <version> (installed)` READ from plugin.json
# at runtime and narrowed the pin to "exactly one, and it is a read". The Step-5
# walk (finding W-2) measured what that read costs a user: from a session whose
# working directory is not this repo it is REFUSED, and the refusal prints above
# the page. W6 S9a bakes the version at RENDER time instead — plugin.json is
# still the version's single owner, help.md is a rendering of it — so the pin
# returns to its strongest form: ZERO invocations, static content, no tool call
# of any kind.
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

    # R-4. A command file that tells the user to run `claude plugin install
    # bionic` is naming something the machine does not run: every other
    # surface in the payload spells the marketplace-qualified id, and the
    # bare form is not a shorthand for it. Match the install verb with any
    # id that is not `bionic@`-qualified.
    bare_install="$(grep -nE 'plugin install +bionic([^@a-zA-Z0-9_-]|$)' "$f" || true)"
    expect_eq "$base: no unqualified \`plugin install bionic\` (the id is bionic@bionic)" \
      "" "$bare_install"
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

  # EVERY SHIPPED SKILL IS ON THE FRONT DOOR (epic-18 T3, AC-6). The set is DERIVED from
  # payload/skills/ rather than listed here, for the reason the payload path wall gives about
  # its own file set: an enumeration can only pin what somebody already noticed, and the way
  # a skill goes missing from this page is by being added to the payload and nowhere else.
  # That is precisely how excalidraw-diagram arrived — shipped, and unmentioned by the one
  # page whose whole job is to say what bionic gives you.
  MISSING_SKILLS=""
  for _sk in "${REPO}/payload/skills"/*; do
    [ -e "${_sk}/SKILL.md" ] || continue
    _slug="${_sk##*/}"
    case "$HELP_TEXT" in
      *"/bionic:${_slug}"*) ;;
      *) MISSING_SKILLS="${MISSING_SKILLS}${_slug} " ;;
    esac
  done
  expect_eq "help.md names every skill the payload ships" "" "${MISSING_SKILLS% }"

  # ZERO INVOCATIONS: THE PAGE IS STATIC (epic-17 W6 S9a; walk finding W-2).
  #
  # The runtime read this pin was narrowed for is gone. What the walk measured: run
  # `/bionic:help` from any session whose working directory is not this repo and the read of
  # plugin.json is refused — a permission notice the first time, a working-directory sandbox
  # error the second, each printed ABOVE the page in different words, and no version line
  # either time. A front door whose first line is an error about a file the user never named
  # is worse than a front door with no version on it.
  #
  # So the version is baked at RENDER time: agents-src/render.sh substitutes
  # @@PLUGIN_VERSION@@ from payload/.claude-plugin/plugin.json, exactly as marketplace.json
  # is a rendering of the dependency list. plugin.json remains the version's single owner —
  # a baked value is a copy, and the copy is kept honest by `render.sh --check`, which goes
  # red the moment the owner moves without a re-render (tests/agent-render.test.sh §I5) and
  # by the agreement arm below on the shipped side.
  bad="$(bad_script_invocations "$HELP_MD")"
  expect_eq "help.md: no non-rooted .sh invocations" "" "$bad"
  inv_count="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}' "$HELP_MD" 2>/dev/null | wc -l | tr -d ' ')"
  expect_eq "help.md: zero \${CLAUDE_PLUGIN_ROOT} invocations (the page acts on nothing)" "0" "$inv_count"
  sh_count="$(grep -oE '[A-Za-z0-9_./{}$-]*\.sh' "$HELP_MD" 2>/dev/null | wc -l | tr -d ' ')"
  expect_eq "help.md: names no script at all" "0" "$sh_count"
  fence_count="$(grep -cE '^[[:space:]]*```' "$HELP_MD" 2>/dev/null | tr -d ' ')"
  expect_eq "help.md: carries no fenced code block" "0" "$fence_count"
  subst_count="$(grep -oE '\$\(' "$HELP_MD" 2>/dev/null | wc -l | tr -d ' ')"
  expect_eq "help.md: carries no command substitution" "0" "$subst_count"

  # THE VERSION LINE, and its agreement with the file that owns the version.
  PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
  expect_true "payload/.claude-plugin/plugin.json exists (the version's single owner)" test -f "$PLUGIN_JSON"
  PJ_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" 2>/dev/null | head -1)"
  expect_true "plugin.json declares a non-empty version" bash -c "[ -n '$PJ_VERSION' ]"
  expect_contains "help.md carries the baked version line 'bionic ${PJ_VERSION} (installed)'" \
    "bionic ${PJ_VERSION} (installed)" "$HELP_TEXT"
  # ...and it OPENS the page: the first line that is either the version line or the page
  # heading has to be the version line, or the page opens with something else.
  first_page_line="$(grep -m1 -E '^(bionic |# bionic$)' "$HELP_MD" 2>/dev/null)"
  expect_eq "help.md: the version line opens the page, ahead of the heading" \
    "bionic ${PJ_VERSION} (installed)" "$first_page_line"
  # The runtime read's format string is gone, not merely joined by a static line.
  expect_not_contains "help.md: no printf format string left where the version goes" \
    'bionic %s (installed)' "$HELP_TEXT"
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

# The positive fixture models the RATIFIED spelling, unquoted (epic-17 W6 S9b,
# plan A-5.4): a permission rule prefix-matches the literal command string, so
# the quoted form this fixture used to carry is the form that hits the approval
# wall. What this fixture is here to prove is unchanged — the path is rooted at
# ${CLAUDE_PLUGIN_ROOT} — and quoting was never part of that rule; the
# rule-vs-body agreement lives in tests/command-permissions.test.sh.
cat > "$FIXDIR/good.md" <<'EOF'
---
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)
description: a well-formed command file
---

Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
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

  # Mutation 2: inject an invocation, in a fence, into a copy — the
  # zero-invocation pin and the no-fence pin must BOTH go red. Rewritten at W6
  # S9a: this arm injected a SECOND invocation while exactly-one was the
  # healthy state; with the version baked at render time the healthy state is
  # zero again, so left as it was the arm would have gone on passing while
  # proving nothing about the pin it sits under.
  cp "$HELP_MD" "$DOCTORED"
  printf '\n```bash\nbash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh\n```\n' >> "$DOCTORED"
  doctored_inv_count="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}' "$DOCTORED" 2>/dev/null | wc -l | tr -d ' ')"
  expect_true "MUTATED help.md (invocation injected): the zero-invocation check now fails as expected" bash -c "[ '$doctored_inv_count' -ne 0 ]"
  doctored_fence_count="$(grep -cE '^[[:space:]]*```' "$DOCTORED" 2>/dev/null | tr -d ' ')"
  expect_true "MUTATED help.md (fenced block injected): the no-fence check now fails as expected" bash -c "[ '$doctored_fence_count' -ne 0 ]"

  # Mutation 3: bake a version its owner does not carry. A copied value is only
  # safe while something compares it against the copy's source, and an absence
  # check ("the page never disagrees with plugin.json") proves nothing on its
  # own — this is the arm that shows the comparison discriminates.
  sed "s|^bionic ${PJ_VERSION} (installed)\$|bionic 9.9.9 (installed)|" "$HELP_MD" > "$DOCTORED"
  doctored_text="$(cat "$DOCTORED")"
  expect_not_contains "MUTATED help.md (version drifted from plugin.json): the agreement check now fails as expected" \
    "bionic ${PJ_VERSION} (installed)" "$doctored_text"
  expect_contains "MUTATED help.md: ...and the drifted value is what it now carries" \
    "bionic 9.9.9 (installed)" "$doctored_text"

  # Restore proof: the production file was never opened for writing above —
  # only read (cat/grep into $DOCTORED copies) — so it still passes clean.
  restored_bad="$(bad_script_invocations "$HELP_MD")"
  expect_eq "production help.md untouched: still zero non-rooted invocations after mutation arms" "" "$restored_bad"
else
  echo "SKIP: Section 4 (help.md missing)"
fi


# ---------------------------------------------------------------------------
# Section 5 — the one-answer route is described where a model will read it (AC-9)
# ---------------------------------------------------------------------------
#
# `--all` exists for the person who has already decided to do everything, and a
# model that reached for it by default would have turned per-item consent into a
# single blanket yes it chose on the user's behalf. So the command files carry
# one sentence saying when it is allowed and what to do with the question it
# asks: the flag is for a user who asked for everything, and its one question is
# relayed word for word like every other.
ALL_DOCTRINE="Use --all only when the user asks for everything; relay its one question verbatim."
for c in setup remove; do
  f="${COMMANDS_DIR}/${c}.md"
  if [ ! -f "$f" ]; then
    no "${c}.md exists (Section 5 needs it)"
    continue
  fi
  expect_contains "${c}.md says when --all may be reached for, and what to do with its question" \
    "$ALL_DOCTRINE" "$(cat "$f")"
done

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
