#!/usr/bin/env bash
# tests/agent-roles.test.sh — frontmatter + tool-permission gate for agents/*.md role files.
#
# Sections:
#   1. six role files exist
#   2. frontmatter: name / model∈set / effort∈set, exact per-file values
#   3. disallowedTools present on researcher/auditor/critic/test-runner, absent on both implementors
#
# WHAT THIS SUITE NO LONGER DOES.
#
# (epic-17 W4 S2, spec AC-2 / design ledger D1) Sections 5 and 7 held the role files'
# SHARED-CORE and REPORT-CONTRACT blocks in agreement PAIRWISE — every file byte-diffed
# against a reference copy. Those blocks now have exactly one source apiece under
# agents-src/blocks/ and the finals are generated from it, so there is no second copy to
# drift: identity by construction retires identity by enforcement.
#
# (epic-18 T14, 2026-08-22) Sections 4 and 6 held the auditor/critic MANDATE and AXIS
# blocks byte-identical to SKILL.md's blockquotes, with meta-evidence planting one-byte
# drift in both directions. Every one of those assertions had rendered PROSE as its
# subject: their only possible failure was "the wording of two copies of a paragraph
# diverged", which leaves no machine in a wrong state. Retired under the ratified
# testing doctrine — behavior tests good, output-text pins bad.
#
# What stays is what a role file's CONFIGURATION says: the frontmatter values the harness
# actually reads when it dispatches an agent, and the tool-permission fields that decide
# what that agent may do.
#
# Harness idiom mirrors the other suites: PASS/FAIL counters, nonzero exit on any fail.
#
# Usage: bash tests/agent-roles.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
AGENTS="$REPO/agents"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

# ---------- extraction ----------

# fm_value <file> <key>: value of a frontmatter key (between the first two --- fences).
fm_value() {
  awk -v k="$2" '/^---$/{d++; next} d==1 && $0 ~ "^"k":" {sub("^"k":[[:space:]]*",""); print; exit}' "$1"
}

FILES="implementor senior-implementor researcher auditor critic test-runner"

# ===== Section 1: six role files exist =====
echo "== Section 1: files exist =="
for r in $FILES; do
  if [ -f "$AGENTS/$r.md" ]; then pass "agents/$r.md exists"; else fail "agents/$r.md missing"; fi
done

# ===== Section 2: frontmatter name / model / effort =====
echo "== Section 2: frontmatter =="
MODELS_OK="sonnet opus haiku fable inherit"
EFFORT_OK="low medium high xhigh max"
in_set() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }

# expected: file|model|effort
EXPECT="implementor|sonnet|high
senior-implementor|opus|high
researcher|opus|high
auditor|opus|high
critic|opus|high
test-runner|haiku|medium"

while IFS='|' read -r r m e; do
  f="$AGENTS/$r.md"
  [ -f "$f" ] || { fail "$r.md missing (frontmatter skipped)"; continue; }
  name="$(fm_value "$f" name)"
  model="$(fm_value "$f" model)"
  effort="$(fm_value "$f" effort)"
  [ "$name" = "$r" ] && pass "$r: name=$name" || fail "$r: name=$name (want $r)"
  if in_set "$MODELS_OK" "$model"; then pass "$r: model in set ($model)"; else fail "$r: model '$model' not in {$MODELS_OK}"; fi
  if in_set "$EFFORT_OK" "$effort"; then pass "$r: effort in set ($effort)"; else fail "$r: effort '$effort' not in {$EFFORT_OK}"; fi
  [ "$model" = "$m" ] && pass "$r: model=$m" || fail "$r: model=$model (want $m)"
  [ "$effort" = "$e" ] && pass "$r: effort=$e" || fail "$r: effort=$effort (want $e)"
done <<< "$EXPECT"

# ===== Section 3: disallowedTools presence/absence =====
echo "== Section 3: disallowedTools =="
DENY_EXPECT="researcher auditor critic test-runner"
NODENY_EXPECT="implementor senior-implementor"
for r in $DENY_EXPECT; do
  v="$(fm_value "$AGENTS/$r.md" disallowedTools)"
  if echo "$v" | grep -q 'Write' && echo "$v" | grep -q 'Edit' && echo "$v" | grep -q 'NotebookEdit'; then
    pass "$r: disallowedTools present ($v)"
  else
    fail "$r: disallowedTools missing/incomplete ('$v')"
  fi
done
for r in $NODENY_EXPECT; do
  v="$(fm_value "$AGENTS/$r.md" disallowedTools)"
  if [ -z "$v" ]; then pass "$r: no disallowedTools (inherits all)"; else fail "$r: unexpected disallowedTools ('$v')"; fi
done

# ---------- summary ----------
echo "──────────────────────────────────────────────"
echo "agent-roles: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
