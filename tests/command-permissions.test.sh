#!/bin/bash
# COMMAND PERMISSIONS — epic-17 wave-06 slice S9b (walk finding W-1; plan A-5.4).
#
# WHY THIS SUITE EXISTS. Permission rules prefix-match the LITERAL command
# string the model is about to run. That was measured, not reasoned: with one
# unchanged rule `Bash(bash <root>/scripts/doctor.sh:*)`, a command body that
# invoked `bash "<root>/scripts/doctor.sh"` — QUOTED — hit the approval wall,
# and the same body unquoted RAN
# (record/epic-17-w6/r2-control-quoted.txt vs r2-control-unquoted.txt). Every
# bionic command file shipped the quoted spelling while every rule was
# unquoted, in frontmatter and in the profile template alike, which is the
# first-order reason bionic's own slash commands prompted their own user.
#
# The same measurement established the fix that works from any cwd, headless:
# `${CLAUDE_PLUGIN_ROOT}` DOES substitute inside command frontmatter, so a
# command file carrying its own `allowed-tools: Bash(bash
# ${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh:*)` and invoking the script unquoted
# prints its full report with no prompt
# (record/epic-17-w6/r2-variant4-subst-unquoted.txt).
#
# WHAT THIS SUITE OWNS. The AGREEMENT between three strings that must stay
# byte-identical or the wall returns, for each of setup, doctor and remove:
#
#   1. the command file's own frontmatter rule prefix — between `Bash(` and `:*)`
#   2. the start of every fenced `bash ` invocation line in that same file
#   3. the profile template's rule for the same script, once
#      `__BIONIC_PLUGIN_ROOT__` is read as `${CLAUDE_PLUGIN_ROOT}`
#
# and, across the whole command surface, the absence of the regression class
# itself: no `bash "` anywhere in a command file. Nothing here judges what a
# script DOES; that is the script suites' subject. Nothing here judges path
# ROOTING either — tests/command-format.test.sh owns that rule and this suite
# would pass a wrongly-rooted path that agreed with itself, which is why both
# suites exist.
#
# help.md carries no rule and is checked only by the no-`bash "` arm: after W6
# it invokes no script (its one line reads plugin.json), so it has nothing to
# authorize.
#
# HERMETIC. No network, no `claude` CLI, no daemon. Reads four committed files
# plus a copy of each in a scratch dir for the mutation arms.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh). Containment uses bash `[[ == * ]]`
# in-process; extraction runs awk/grep against a FILE argument, never a pipe
# from another process's stdout.
#
# Usage: bash tests/command-permissions.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
COMMANDS_DIR="${REPO}/payload/commands"
PROFILE="${REPO}/payload/permissions/profile.template.json"

# The three commands that RUN a script and therefore need a rule.
SCRIPTED_COMMANDS="setup doctor remove"
# The whole shipped surface — the regression-class arm covers all of it.
ALL_COMMANDS="help setup doctor remove"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_eq()    { local label="$1" expected="$2" actual="$3"; if [ "$actual" = "$expected" ]; then ok "$label"; else no "$label" "expected='$expected' actual='$actual'"; fi; }
expect_prefix() {
  local label="$1" prefix="$2" line="$3"
  if [[ "$line" == "$prefix"* ]]; then ok "$label"; else no "$label" "line='$line' does not start with '$prefix'"; fi
}
expect_not_prefix() {
  local label="$1" prefix="$2" line="$3"
  if [[ "$line" == "$prefix"* ]]; then no "$label" "line='$line' still starts with '$prefix'"; else ok "$label"; fi
}
# Values are tested DIRECTLY, never interpolated into a `bash -c` string: the
# strings this suite handles contain the double quote character by definition —
# it is the regression under test — and a quote inside a `bash -c "[ -n '...' ]"`
# would turn a content assertion into a shell syntax error reported as a content
# failure (the same trap tests/doctor.test.sh documents for descriptions).
expect_nonempty() { local label="$1" value="$2"; if [ -n "$value" ]; then ok "$label"; else no "$label" "expected a non-empty value"; fi; }
expect_gt0()      { local label="$1" n="$2"; if [ "$n" -gt 0 ] 2>/dev/null; then ok "$label"; else no "$label" "expected a count above zero, got '$n'"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extractors — functions, so the production files and the mutated copies run
# through identical logic.
# ---------------------------------------------------------------------------

# Every `allowed-tools:` line inside the file's opening frontmatter fence.
frontmatter_allowed_tools_lines() {
  awk '
    /^---$/ { c++; if (c >= 2) exit; next }
    c == 1 && /^allowed-tools:/ { print }
  ' "$1"
}

# The rule PREFIX carried by the frontmatter: the text between `Bash(` and the
# trailing `:*)`. Empty output means "absent or not in the expected shape" —
# both are failures, distinguished by the arms below.
allowed_tools_rule_prefix() {
  frontmatter_allowed_tools_lines "$1" | awk '
    {
      line = $0
      sub(/^allowed-tools:[[:space:]]*/, "", line)
      if (line ~ /^Bash\(.*:\*\)$/) {
        sub(/^Bash\(/, "", line)
        sub(/:\*\)$/, "", line)
        print line
      }
      exit
    }
  '
}

# Every fenced `bash ` invocation line in the body: inside a ``` fence, and
# starting with the literal `bash `. Frontmatter is skipped so a rule line can
# never be mistaken for an invocation.
fenced_bash_invocation_lines() {
  awk '
    BEGIN { fm = 0; fence = 0 }
    /^---$/ && fm < 2 { fm++; next }
    fm < 2 { next }
    /^```/ { fence = 1 - fence; next }
    fence == 1 && /^bash / { print }
  ' "$1"
}

# The profile template's rule prefix for one payload script, with the shipped
# token read as the frontmatter spelling. grep runs against the FILE.
profile_rule_prefix() {
  local script="$1"
  grep -oE 'Bash\(bash __BIONIC_PLUGIN_ROOT__/scripts/'"${script}"'\.sh:\*\)' "$PROFILE" 2>/dev/null \
    | head -1 \
    | sed -e 's/^Bash(//' -e 's/:\*)$//' -e 's/__BIONIC_PLUGIN_ROOT__/${CLAUDE_PLUGIN_ROOT}/'
}

# ---------------------------------------------------------------------------
# Section 1: the rule exists, in the ratified shape and position.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 1: frontmatter allowed-tools rule (setup, doctor, remove) ==="

expect_true "payload/commands/ exists" test -d "$COMMANDS_DIR"
expect_true "payload/permissions/profile.template.json exists" test -f "$PROFILE"

for c in $SCRIPTED_COMMANDS; do
  f="${COMMANDS_DIR}/${c}.md"
  if [ ! -f "$f" ]; then
    no "payload/commands/${c}.md exists"
    continue
  fi
  ok "payload/commands/${c}.md exists"

  rule_count="$(frontmatter_allowed_tools_lines "$f" | wc -l | tr -d ' ')"
  expect_eq "${c}.md: exactly one allowed-tools line in frontmatter" "1" "$rule_count"

  # Position: first line after the opening fence, ahead of description. The
  # CLI does not require it; the file's readers do — the rule is the first
  # thing that has to be true about the command.
  line2="$(sed -n '2p' "$f")"
  expect_prefix "${c}.md: allowed-tools is the first line after the opening ---" \
    "allowed-tools:" "$line2"

  prefix="$(allowed_tools_rule_prefix "$f")"
  expect_eq "${c}.md: the rule is Bash(<prefix>:*) with the substituted-root prefix" \
    "bash \${CLAUDE_PLUGIN_ROOT}/scripts/${c}.sh" "$prefix"
done

# ---------------------------------------------------------------------------
# Section 2: rule prefix == the start of every invocation in the same file.
#
# THE AXIS TEST. This is the byte-for-byte agreement the wall is made of: a
# rule prefix-matches the literal command string, so one quote character in
# the body is enough to make the rule stop applying, silently.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 2: rule prefix ↔ every fenced invocation in the same file ==="

for c in $SCRIPTED_COMMANDS; do
  f="${COMMANDS_DIR}/${c}.md"
  [ -f "$f" ] || continue

  prefix="$(allowed_tools_rule_prefix "$f")"
  if [ -z "$prefix" ]; then
    no "${c}.md: rule prefix extractable (Section 2 arms need it)" \
       "frontmatter carries no Bash(<prefix>:*) rule"
    continue
  fi

  inv_count=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    inv_count=$((inv_count + 1))
    expect_prefix "${c}.md: invocation ${inv_count} is covered by the file's own rule" \
      "$prefix" "$line"
  done < <(fenced_bash_invocation_lines "$f")

  expect_gt0 "${c}.md: at least one fenced bash invocation exists" "$inv_count"
done

# ---------------------------------------------------------------------------
# Section 3: the profile template's rule for the same script agrees.
#
# Two grants, one string. The frontmatter rule is what makes the command work
# for a user who never ran /bionic:setup; the profile rule is what tier 2
# applies machine-wide. They authorize the same invocation, so they must spell
# it the same way — and the profile's rules were already unquoted, which is
# what made the command bodies the half that was wrong.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 3: profile.template.json rule ↔ the same prefix ==="

for c in $SCRIPTED_COMMANDS; do
  f="${COMMANDS_DIR}/${c}.md"
  [ -f "$f" ] || continue

  fm_prefix="$(allowed_tools_rule_prefix "$f")"
  pf_prefix="$(profile_rule_prefix "$c")"

  expect_true "profile.template.json carries a rule for scripts/${c}.sh" \
    test -n "$pf_prefix"
  expect_eq "${c}: profile rule prefix == frontmatter rule prefix (token substituted)" \
    "$fm_prefix" "$pf_prefix"
done

# ---------------------------------------------------------------------------
# Section 4: the regression class, walled across the whole surface.
#
# `bash "` is the exact spelling that was measured to hit the wall. It is
# banned outright rather than checked per-file, because the next command file
# added to this surface will be written by copying one of these four.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 4: no quoted invocation anywhere in payload/commands/ ==="

for c in $ALL_COMMANDS; do
  f="${COMMANDS_DIR}/${c}.md"
  if [ ! -f "$f" ]; then
    no "payload/commands/${c}.md exists (Section 4)"
    continue
  fi
  quoted="$(grep -n 'bash "' "$f" || true)"
  expect_eq "${c}.md: carries no quoted \`bash \"\` invocation" "" "$quoted"
done

# ---------------------------------------------------------------------------
# Section 5: mutation-and-restore — proof the arms discriminate against the
# REAL production files, not only against a well-behaved reading of them.
# RED evidence dies at green (memory: red-evidence-is-perishable), so the
# proof is taken here: a doctored COPY re-acquires the quote, Section 2's and
# Section 4's checks are shown to go red on it, and the production file is
# then re-checked untouched.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 5: mutation-and-restore (quote re-introduced in a copy) ==="

for c in $SCRIPTED_COMMANDS; do
  f="${COMMANDS_DIR}/${c}.md"
  [ -f "$f" ] || continue

  DOCTORED="${TMP}/${c}-doctored.md"
  # Re-quote every invocation, exactly as the file was written before S9b.
  sed -e 's|^bash \${CLAUDE_PLUGIN_ROOT}/scripts/\([a-z]*\)\.sh|bash "${CLAUDE_PLUGIN_ROOT}/scripts/\1.sh"|' \
      "$f" > "$DOCTORED"

  # The mutation must actually have landed, or the arms below prove nothing.
  mutated="$(grep -c 'bash "' "$DOCTORED" 2>/dev/null || true)"
  expect_gt0 "MUTATED ${c}.md: the quote was re-introduced (arm is live)" "$mutated"

  prefix="$(allowed_tools_rule_prefix "$DOCTORED")"
  expect_eq "MUTATED ${c}.md: the frontmatter rule is unchanged by the mutation" \
    "bash \${CLAUDE_PLUGIN_ROOT}/scripts/${c}.sh" "$prefix"

  first_inv="$(fenced_bash_invocation_lines "$DOCTORED" | head -1)"
  expect_not_prefix "MUTATED ${c}.md: Section 2 goes red — the rule no longer covers the body" \
    "$prefix" "$first_inv"

  doctored_quoted="$(grep -n 'bash "' "$DOCTORED" || true)"
  expect_nonempty "MUTATED ${c}.md: Section 4 goes red — the quoted invocation is visible" \
    "$doctored_quoted"

  # Restore proof: the production file was only ever read above.
  prod_quoted="$(grep -n 'bash "' "$f" || true)"
  expect_eq "production ${c}.md untouched: still carries no quoted invocation" "" "$prod_quoted"
  prod_first="$(fenced_bash_invocation_lines "$f" | head -1)"
  expect_prefix "production ${c}.md untouched: first invocation still covered by its rule" \
    "$prefix" "$prod_first"
done

# ---------------------------------------------------------------------------
# Section 6: the PIPED invocation the addressable-consent route uses.
#
# WHY IT NEEDS ITS OWN SECTION. Section 2 reads lines that START with `bash `.
# The route a user is given for saying yes to one item does not — it is
# `printf 'y\n' | bash <root>/scripts/<x>.sh --only <item>` — so Section 2 walks
# straight past it, and the rule that has to cover it is the same rule.
#
# MEASURED, NOT ASSUMED (epic-17 W6 S12, and the critic's F-2 capture before it):
# the permission layer splits a pipeline and matches each segment on its own. A
# scratch project command carrying this exact rule form ran the unquoted piped
# body with no prompt, and the SAME rule walled the quoted piped body with "This
# Bash command contains multiple operations. The following part requires
# approval: bash \"…/setup.sh\" --only permission-mode". So the segment after the
# pipe is a literal command string like any other, and this section is the
# agreement test for it.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 6: the piped --only invocation ↔ the same rule ==="

# Every fenced line that pipes into `bash `, with everything up to and including
# the pipe removed — i.e. the command string the permission layer will match.
fenced_piped_bash_segments() {
  awk '
    BEGIN { fm = 0; fence = 0 }
    /^---$/ && fm < 2 { fm++; next }
    fm < 2 { next }
    /^```/ { fence = 1 - fence; next }
    fence == 1 && /\| bash / {
      i = index($0, "| bash ")
      print substr($0, i + 2)
    }
  ' "$1"
}

for c in $SCRIPTED_COMMANDS; do
  f="${COMMANDS_DIR}/${c}.md"
  [ -f "$f" ] || continue
  case "$c" in doctor) continue ;; esac   # doctor mutates nothing and asks nothing

  prefix="$(allowed_tools_rule_prefix "$f")"
  if [ -z "$prefix" ]; then
    no "${c}.md: rule prefix extractable (Section 6 arms need it)"
    continue
  fi

  piped_count=0
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    piped_count=$((piped_count + 1))
    expect_prefix "${c}.md: piped invocation ${piped_count} is covered by the file's own rule" \
      "$prefix" "$seg"
    expect_true "${c}.md: piped invocation ${piped_count} carries the --only flag" \
      bash -c 'case "$1" in *" --only "*) exit 0 ;; *) exit 1 ;; esac' _ "$seg"
  done < <(fenced_piped_bash_segments "$f")

  expect_gt0 "${c}.md: the addressable-consent route is present at all" "$piped_count"
done

# Mutation-and-restore: re-quote the piped body in a COPY and watch the
# agreement break. Without this the section is an absence, and an absence
# proves nothing about the extractor that looked for it.
for c in setup remove; do
  f="${COMMANDS_DIR}/${c}.md"
  [ -f "$f" ] || continue
  DOCTORED="${TMP}/${c}-piped-doctored.md"
  sed -e 's,| bash \${CLAUDE_PLUGIN_ROOT}/scripts/\([a-z]*\)\.sh,| bash "${CLAUDE_PLUGIN_ROOT}/scripts/\1.sh",' \
      "$f" > "$DOCTORED"
  prefix="$(allowed_tools_rule_prefix "$f")"
  mut_seg="$(fenced_piped_bash_segments "$DOCTORED" | head -1)"
  expect_nonempty "MUTATED ${c}.md: the piped line is still extractable (arm is live)" "$mut_seg"
  expect_not_prefix "MUTATED ${c}.md: Section 6 goes red — the rule no longer covers the piped body" \
    "$prefix" "$mut_seg"
  prod_seg="$(fenced_piped_bash_segments "$f" | head -1)"
  expect_prefix "production ${c}.md untouched: the piped body is still covered" \
    "$prefix" "$prod_seg"
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
